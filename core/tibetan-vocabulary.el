;;; tibetan-vocabulary.el --- Vocabulary lookup with DharmaMitra fallback -*- lexical-binding: t -*-

;;; Commentary:
;; Provides vocabulary lookup with multiple sources:
;; 1. Custom vocabulary file (per-document, via #+TIBETAN_VOCAB_FILE header)
;; 2. Local comprehensive glossaries (17,777 entries)
;; 3. DharmaMitra API fallback with caching
;;
;; Handles:
;; - Compound word detection
;; - Particle stripping
;; - Cached translations to avoid repeated API calls
;;
;; Custom vocabulary:
;; Add #+TIBETAN_VOCAB_FILE: path/to/wordlist.pdf to your document header
;; The PDF will be parsed and cached for priority lookup

;;; Code:

(require 'cl-lib)

;; Safe substring for multi-byte Tibetan text
(defun tibetan-vocab-safe-substring (str start &optional end)
  "Safely extract substring from STR between START and END.
Returns empty string if indices are out of range or invalid."
  (condition-case nil
      (if (not (stringp str))
          ""
        (let* ((len (length str))
               (s (max 0 (min start len)))
               (e (if end (max s (min end len)) len)))
          (if (and (integerp s)
                   (integerp e)
                   (<= 0 s)
                   (<= s e)
                   (<= e len))
              (substring str s e)
            "")))
    (error "")))

;; ============================================================================
;; CACHES
;; ============================================================================

(defvar tibetan-dharmamitra-cache (make-hash-table :test 'equal)
  "Cache for DharmaMitra word translations to avoid repeated API calls.")

(defvar tibetan-custom-vocab-cache (make-hash-table :test 'equal)
  "Cache for custom vocabulary files.
Key: absolute path to vocab file
Value: hash-table of (tibetan-term . definition)")

;; ============================================================================
;; RANGJUNG YESHE FALLBACK DICTIONARY (162k entries, lazy-loaded)
;; ============================================================================

(defvar tibetan-rangjung-yeshe-vocabulary nil
  "Hash table for Rangjung Yeshe dictionary entries.
Lazy-loaded on first lookup to avoid slow startup.")

(defvar tibetan-rangjung-yeshe-loaded nil
  "Whether Rangjung Yeshe dictionary has been loaded.")

(defun tibetan-rangjung-yeshe-get-path ()
  "Get path to Rangjung Yeshe dictionary file.
Returns the Tibetan-keyed version if it exists, otherwise Wylie version."
  (let* ((base-dir (or (file-name-directory
                        (or load-file-name
                            (locate-library "tibetan-cat")
                            default-directory))
                       default-directory))
         (tib-path (expand-file-name "data/glossaries/rangjung-yeshe-tibetan.txt" base-dir))
         (wylie-path (expand-file-name "data/glossaries/rangjung-yeshe-wylie.txt" base-dir)))
    (cond
     ((file-exists-p tib-path) tib-path)
     ((file-exists-p wylie-path) wylie-path)
     ;; Try alternative location
     (t (let ((alt-tib "/Users/cp/tibetan-cat.el/data/glossaries/rangjung-yeshe-tibetan.txt"))
          (when (file-exists-p alt-tib) alt-tib))))))

(defun tibetan-rangjung-yeshe-load ()
  "Load Rangjung Yeshe dictionary (lazy, called on first lookup).
This is a large dictionary (162k entries) so we load it on-demand.
Stores entries under both Tibetan and Wylie keys for flexible lookup."
  (unless tibetan-rangjung-yeshe-loaded
    (let ((dict-path (tibetan-rangjung-yeshe-get-path)))
      (if (not dict-path)
          (progn
            (setq tibetan-rangjung-yeshe-loaded t)
            (message "⚠ Rangjung Yeshe dictionary not found"))
        (message "Loading Rangjung Yeshe dictionary (162k entries)...")
        (setq tibetan-rangjung-yeshe-vocabulary (make-hash-table :test 'equal :size 350000))
        (with-temp-buffer
          (insert-file-contents dict-path)
          (goto-char (point-min))
          (let ((count 0))
            (while (not (eobp))
              (let ((line (buffer-substring-no-properties
                           (line-beginning-position) (line-end-position))))
                ;; Skip comments and empty lines
                (unless (or (string-empty-p (string-trim line))
                            (string-prefix-p "#" line))
                  (let* ((parts (split-string line "\t"))
                         (term (when (car parts) (string-trim (car parts))))
                         (def (when (cadr parts) (string-trim (cadr parts))))
                         (wylie (when (nth 2 parts) (string-trim (nth 2 parts)))))
                    (when (and term def (not (string-empty-p term)) (not (string-empty-p def)))
                      ;; Store under primary key (Tibetan or Wylie depending on file)
                      (puthash term def tibetan-rangjung-yeshe-vocabulary)
                      ;; Also store under Wylie if available (third column)
                      (when (and wylie (not (string-empty-p wylie)))
                        (puthash wylie def tibetan-rangjung-yeshe-vocabulary))
                      (setq count (1+ count))))))
              (forward-line 1))
            (setq tibetan-rangjung-yeshe-loaded t)
            (message "✓ Loaded Rangjung Yeshe dictionary: %d entries" count)))))))

(defun tibetan-lookup-word-in-rangjung-yeshe (word)
  "Look up WORD in Rangjung Yeshe dictionary (lazy-loads if needed).
Tries Tibetan script first, then Wylie conversion.
Returns meaning if found, nil otherwise."
  ;; Lazy-load the dictionary on first use
  (tibetan-rangjung-yeshe-load)
  (when tibetan-rangjung-yeshe-vocabulary
    (let* ((root-form (tibetan-strip-particles word))
           (entry (or
                   ;; Try full word as-is
                   (gethash word tibetan-rangjung-yeshe-vocabulary)
                   ;; Try with particles stripped
                   (gethash root-form tibetan-rangjung-yeshe-vocabulary))))
      ;; If not found, try Wylie conversion
      (unless entry
        (when (fboundp 'tibetan-to-wylie-fixed)
          (let* ((wylie (ignore-errors (tibetan-to-wylie-fixed word)))
                 (wylie-root (ignore-errors (tibetan-to-wylie-fixed root-form))))
            (setq entry (or
                         (and wylie (gethash wylie tibetan-rangjung-yeshe-vocabulary))
                         (and wylie-root (gethash wylie-root tibetan-rangjung-yeshe-vocabulary)))))))
      entry)))

(defvar tibetan-current-custom-vocab nil
  "Current buffer's custom vocabulary hash-table, or nil if none.")

;; ============================================================================
;; CUSTOM VOCABULARY FILE SUPPORT
;; ============================================================================

(defvar tibetan-resources-vocab-cache (make-hash-table :test 'equal)
  "Cache for Resources folder vocabulary.
Key: directory path, Value: hash-table of (term . definition)")

(defvar tibetan-current-resources-vocab nil
  "Current buffer's Resources vocabulary hash-table, or nil if none.")

(defun tibetan-get-custom-vocab-file ()
  "Get custom vocabulary file path from #+TIBETAN_VOCAB_FILE header.
Returns absolute path or nil if not set."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+TIBETAN_VOCAB_FILE:\\s-*\\(.+\\)$" nil t)
      (let ((path (string-trim (match-string 1))))
        ;; Resolve relative paths from buffer's directory
        (if (file-name-absolute-p path)
            path
          (when buffer-file-name
            (expand-file-name path (file-name-directory buffer-file-name))))))))

(defun tibetan-find-resources-folder ()
  "Find Resources folder relative to current buffer.
Looks in: ./Resources, ../Resources, ../../Resources
Returns absolute path or nil."
  (when buffer-file-name
    (let ((dir (file-name-directory buffer-file-name)))
      (catch 'found
        (dolist (rel '("Resources" "../Resources" "../../Resources"))
          (let ((res-dir (expand-file-name rel dir)))
            (when (file-directory-p res-dir)
              (throw 'found res-dir))))))))

(defun tibetan-parse-wordlist-pdf (pdf-path)
  "Parse a Tibetan wordlist PDF (Wortliste format).
Format: Wylie or Tibetan term followed by German // English definitions.
Returns hash-table with both Wylie and Tibetan keys."
  (let ((vocab-table (make-hash-table :test 'equal)))
    (when (and pdf-path (file-exists-p pdf-path))
      (condition-case err
          (let* ((text (shell-command-to-string
                        (format "pdftotext -layout %s -"
                                (shell-quote-argument pdf-path))))
                 (lines (split-string text "\n"))
                 (current-term nil)
                 (current-def "")
                 (page-section nil))
            (dolist (line lines)
              (cond
               ;; Page reference like "(30.6)" or "(31.3–4)"
               ((string-match "^(\\([0-9]+\\.[0-9]\\)" line)
                (setq page-section (match-string 1 line))
                ;; Save previous entry
                (when (and current-term (not (string-empty-p current-def)))
                  (tibetan--store-vocab-entry vocab-table current-term current-def))
                (setq current-term nil current-def ""))

               ;; Page numbers to skip
               ((string-match "^[0-9]+$" (string-trim line))
                nil)

               ;; Empty lines - save entry
               ((string-empty-p (string-trim line))
                (when (and current-term (not (string-empty-p current-def)))
                  (tibetan--store-vocab-entry vocab-table current-term current-def))
                (setq current-term nil current-def ""))

               ;; Tibetan term line (starts with Tibetan character)
               ((string-match "^\\([ༀ-࿿][^[:space:]]*\\(?:་[ༀ-࿿][^[:space:]]*\\)*\\)" line)
                ;; Save previous entry
                (when (and current-term (not (string-empty-p current-def)))
                  (tibetan--store-vocab-entry vocab-table current-term current-def))
                (setq current-term (match-string 1 line))
                (setq current-def ""))

               ;; Wylie term line (starts with lowercase, no indentation)
               ((and (not (string-match "^\\s-" line))
                     (string-match "^\\([a-z][a-z' ]*[a-z]\\)" (string-trim line)))
                ;; Save previous entry
                (when (and current-term (not (string-empty-p current-def)))
                  (tibetan--store-vocab-entry vocab-table current-term current-def))
                (let ((term (string-trim (match-string 1 (string-trim line)))))
                  ;; Skip if it looks like a definition (contains "to ", "a ", etc.)
                  (unless (string-match-p "^\\(to \\|a \\|the \\|one \\)" term)
                    (setq current-term term)
                    (setq current-def ""))))

               ;; Definition line (indented or following term)
               ((and current-term
                     (string-match "\\(.+\\)" line))
                (let ((content (string-trim (match-string 1 line))))
                  (unless (string-empty-p content)
                    (setq current-def (concat current-def
                                             (if (string-empty-p current-def) "" " ")
                                             content)))))))

            ;; Save last entry
            (when (and current-term (not (string-empty-p current-def)))
              (tibetan--store-vocab-entry vocab-table current-term current-def)))
        (error
         (message "Warning: Could not parse wordlist PDF %s: %s" pdf-path err))))
    vocab-table))

(defun tibetan--store-vocab-entry (vocab-table term def)
  "Store TERM with DEF in VOCAB-TABLE under both Wylie and Tibetan keys."
  (let ((clean-def (string-trim def)))
    ;; Store under original key
    (puthash term clean-def vocab-table)
    ;; If term is Wylie, also store under Tibetan
    (when (string-match-p "^[a-z]" term)
      (when (fboundp 'tibetan-wylie-to-tibetan)
        (let ((tib (ignore-errors (tibetan-wylie-to-tibetan term))))
          (when (and tib (not (string-empty-p tib)))
            (puthash tib clean-def vocab-table)))))
    ;; If term is Tibetan, also store under Wylie
    (when (string-match-p "^[ༀ-࿿]" term)
      (when (fboundp 'tibetan-to-wylie-fixed)
        (let ((wylie (ignore-errors (tibetan-to-wylie-fixed term))))
          (when (and wylie (not (string-empty-p wylie)))
            (puthash wylie clean-def vocab-table)))))))

(defun tibetan-parse-wordlist-txt (txt-path)
  "Parse a plain text Tibetan wordlist file.
Format: One entry per line, Tibetan/Wylie term followed by definition.
Supports formats:
  - TAB-separated: term<TAB>definition
  - Colon-separated: term: definition
  - Dash-separated: term - definition
Returns hash-table with both Wylie and Tibetan keys."
  (let ((vocab-table (make-hash-table :test 'equal)))
    (when (and txt-path (file-exists-p txt-path))
      (with-temp-buffer
        (insert-file-contents txt-path)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            ;; Skip empty lines and comments
            (unless (or (string-empty-p (string-trim line))
                        (string-match-p "^[#;/]" line))
              (let ((term nil) (def nil))
                (cond
                 ;; TAB-separated
                 ((string-match "^\\([^\t]+\\)\t+\\(.+\\)$" line)
                  (setq term (string-trim (match-string 1 line)))
                  (setq def (string-trim (match-string 2 line))))
                 ;; Colon-separated (but not URL patterns)
                 ((string-match "^\\([^:]+\\):\\s-+\\(.+\\)$" line)
                  (setq term (string-trim (match-string 1 line)))
                  (setq def (string-trim (match-string 2 line))))
                 ;; Dash-separated
                 ((string-match "^\\([^ -]+\\)\\s-+-\\s-+\\(.+\\)$" line)
                  (setq term (string-trim (match-string 1 line)))
                  (setq def (string-trim (match-string 2 line)))))
                (when (and term def (not (string-empty-p term)) (not (string-empty-p def)))
                  (tibetan--store-vocab-entry vocab-table term def)))))
          (forward-line 1))))
    vocab-table))

(defun tibetan-parse-wordlist-org (org-path)
  "Parse an org-mode Tibetan wordlist file.
Format: Headings are terms, content below is definition.
  * term
    definition
Or table format:
  | term | definition |
Returns hash-table with both Wylie and Tibetan keys."
  (let ((vocab-table (make-hash-table :test 'equal)))
    (when (and org-path (file-exists-p org-path))
      (with-temp-buffer
        (insert-file-contents org-path)
        (goto-char (point-min))
        ;; Check for table format first
        (if (re-search-forward "^|" nil t)
            (progn
              (goto-char (point-min))
              (while (re-search-forward "^|\\s-*\\([^|]+\\)|\\s-*\\([^|]+\\)|" nil t)
                (let ((term (string-trim (match-string 1)))
                      (def (string-trim (match-string 2))))
                  (unless (or (string-match-p "^-+$" term)  ; Skip separator lines
                              (string= term "Term")        ; Skip header
                              (string-empty-p term))
                    (tibetan--store-vocab-entry vocab-table term def)))))
          ;; Heading format
          (while (re-search-forward "^\\*+\\s-+\\(.+\\)$" nil t)
            (let ((term (string-trim (match-string 1)))
                  (def-start (point))
                  (def-end nil))
              ;; Find definition (text until next heading or end)
              (if (re-search-forward "^\\*" nil t)
                  (setq def-end (line-beginning-position))
                (setq def-end (point-max)))
              (let ((def (string-trim (buffer-substring-no-properties def-start def-end))))
                (unless (string-empty-p def)
                  (tibetan--store-vocab-entry vocab-table term def))))))))
    vocab-table))

(defun tibetan-load-resources-vocab ()
  "Load vocabulary from Resources folder if present.
Looks for wordlist files (PDF, TXT, ORG) in the Resources folder.
Priority: TXT > ORG > PDF (PDF requires pdftotext)."
  (let ((res-dir (tibetan-find-resources-folder)))
    (when res-dir
      (let ((cached (gethash res-dir tibetan-resources-vocab-cache)))
        (if cached
            (setq tibetan-current-resources-vocab cached)
          ;; Find wordlist files in priority order
          (let ((vocab-table (make-hash-table :test 'equal))
                (txt-files (directory-files res-dir t "\\(Wortliste\\|wordlist\\|Word.?list\\|vocab\\).*\\.txt$" t))
                (org-files (directory-files res-dir t "\\(Wortliste\\|wordlist\\|Word.?list\\|vocab\\).*\\.org$" t))
                (pdf-files (directory-files res-dir t "\\(Wortliste\\|wordlist\\|Word.?list\\).*\\.pdf$" t)))
            ;; Load TXT files first (highest priority)
            (dolist (txt txt-files)
              (message "Loading Resources vocabulary from %s..." (file-name-nondirectory txt))
              (let ((entries (tibetan-parse-wordlist-txt txt)))
                (maphash (lambda (k v) (puthash k v vocab-table)) entries)))
            ;; Load ORG files
            (dolist (org org-files)
              (message "Loading Resources vocabulary from %s..." (file-name-nondirectory org))
              (let ((entries (tibetan-parse-wordlist-org org)))
                (maphash (lambda (k v) (puthash k v vocab-table)) entries)))
            ;; Load PDF files (requires pdftotext)
            (dolist (pdf pdf-files)
              (if (executable-find "pdftotext")
                  (progn
                    (message "Loading Resources vocabulary from %s..." (file-name-nondirectory pdf))
                    (let ((entries (tibetan-parse-wordlist-pdf pdf)))
                      (maphash (lambda (k v) (puthash k v vocab-table)) entries)))
                (message "⚠ Cannot load %s - pdftotext not installed. Export to .txt or install poppler."
                         (file-name-nondirectory pdf))))
            (if (> (hash-table-count vocab-table) 0)
                (progn
                  (puthash res-dir vocab-table tibetan-resources-vocab-cache)
                  (setq tibetan-current-resources-vocab vocab-table)
                  (message "✓ Loaded %d entries from Resources" (hash-table-count vocab-table)))
              (when pdf-files
                (message "⚠ No vocabulary loaded from Resources. Create a wordlist.txt or install pdftotext.")))))))))

(defun tibetan-lookup-word-in-resources-vocab (word)
  "Look up WORD in current Resources vocabulary.
Returns meaning if found, nil otherwise."
  (when tibetan-current-resources-vocab
    (let* ((root-form (tibetan-strip-particles word))
           (entry (or
                   (gethash word tibetan-current-resources-vocab)
                   (gethash root-form tibetan-current-resources-vocab))))
      ;; Try Wylie conversion
      (unless entry
        (when (fboundp 'tibetan-to-wylie-fixed)
          (let* ((wylie (ignore-errors (tibetan-to-wylie-fixed word)))
                 (wylie-root (ignore-errors (tibetan-to-wylie-fixed root-form))))
            (setq entry (or (and wylie (gethash wylie tibetan-current-resources-vocab))
                           (and wylie-root (gethash wylie-root tibetan-current-resources-vocab)))))))
      entry)))

(defun tibetan-parse-vocab-pdf (pdf-path)
  "Parse a vocabulary PDF file and return a hash-table of entries.
Supports two formats:
1. Tibetan script: ཚིག་མཛོད།\\n   definition
2. Wylie transliteration: shes rab\\n   definition
Both Tibetan and Wylie keys are stored for lookup."
  (let ((vocab-table (make-hash-table :test 'equal)))
    (when (and pdf-path (file-exists-p pdf-path))
      (condition-case err
          (let* ((text (shell-command-to-string
                        (format "pdftotext -layout %s -"
                                (shell-quote-argument pdf-path))))
                 (lines (split-string text "\n"))
                 (in-word-list nil))
            ;; Parse the word list format
            (let ((current-term nil)
                  (current-def ""))
              (dolist (line lines)
                ;; Detect start of word list section
                (when (string-match "^Word list" line)
                  (setq in-word-list t))

                (when in-word-list
                  (cond
                   ;; Skip section headers like "(142.2–5)" or "The Brahmin's Dog"
                   ((or (string-match "^([0-9]" line)
                        (string-match "^The " line)
                        (string-match "^Secondary Literature" line)
                        (string-match "^[0-9]+$" line)  ; page numbers
                        (string-empty-p (string-trim line)))
                    ;; Save previous entry before skipping
                    (when (and current-term (not (string-empty-p current-def)))
                      (let ((def (string-trim current-def)))
                        ;; Store under Wylie key
                        (puthash current-term def vocab-table)
                        ;; Also try to convert to Tibetan and store that
                        (when (fboundp 'tibetan-wylie-to-tibetan)
                          (let ((tib (ignore-errors (tibetan-wylie-to-tibetan current-term))))
                            (when (and tib (not (string-empty-p tib)))
                              (puthash tib def vocab-table))))))
                    (setq current-term nil)
                    (setq current-def ""))

                   ;; Line starting with Tibetan character = new Tibetan term
                   ((string-match "^\\([ཀ-ྼ][^[:space:]]*\\)" line)
                    ;; Save previous entry
                    (when (and current-term (not (string-empty-p current-def)))
                      (puthash current-term (string-trim current-def) vocab-table))
                    (setq current-term (match-string 1 line))
                    (setq current-def ""))

                   ;; Non-indented line with lowercase letters = Wylie term
                   ((and (not (string-match "^\\s-" line))
                         (string-match "^\\([a-z' ]+\\)$" (string-trim line)))
                    ;; Save previous entry
                    (when (and current-term (not (string-empty-p current-def)))
                      (let ((def (string-trim current-def)))
                        (puthash current-term def vocab-table)
                        (when (fboundp 'tibetan-wylie-to-tibetan)
                          (let ((tib (ignore-errors (tibetan-wylie-to-tibetan current-term))))
                            (when (and tib (not (string-empty-p tib)))
                              (puthash tib def vocab-table))))))
                    (setq current-term (string-trim line))
                    (setq current-def ""))

                   ;; Indented line = definition continuation
                   ((and current-term
                         (string-match "^\\s-+\\(.+\\)" line))
                    (setq current-def (concat current-def
                                             (if (string-empty-p current-def) "" " ")
                                             (string-trim (match-string 1 line))))))))

              ;; Save last entry
              (when (and current-term (not (string-empty-p current-def)))
                (let ((def (string-trim current-def)))
                  (puthash current-term def vocab-table)
                  (when (fboundp 'tibetan-wylie-to-tibetan)
                    (let ((tib (ignore-errors (tibetan-wylie-to-tibetan current-term))))
                      (when (and tib (not (string-empty-p tib)))
                        (puthash tib def vocab-table))))))))
        (error
         (message "Warning: Could not parse vocab PDF %s: %s" pdf-path err))))
    vocab-table))

(defun tibetan-load-custom-vocab ()
  "Load custom vocabulary for current buffer if #+TIBETAN_VOCAB_FILE is set.
Caches the parsed vocabulary for reuse."
  (let ((vocab-file (tibetan-get-custom-vocab-file)))
    (if vocab-file
        (let ((cached (gethash vocab-file tibetan-custom-vocab-cache)))
          (if cached
              (setq tibetan-current-custom-vocab cached)
            ;; Parse and cache
            (message "Loading custom vocabulary from %s..." (file-name-nondirectory vocab-file))
            (let ((vocab (tibetan-parse-vocab-pdf vocab-file)))
              (puthash vocab-file vocab tibetan-custom-vocab-cache)
              (setq tibetan-current-custom-vocab vocab)
              (message "✓ Loaded %d custom vocabulary entries" (hash-table-count vocab)))))
      (setq tibetan-current-custom-vocab nil))))

(defun tibetan-lookup-word-in-custom-vocab (word)
  "Look up WORD in current buffer's custom vocabulary.
Tries Tibetan script first, then converts to Wylie for lookup.
Returns meaning if found, nil otherwise."
  (when tibetan-current-custom-vocab
    (let* ((root-form (tibetan-strip-particles word))
           (entry (or
                   ;; Try full Tibetan word
                   (gethash word tibetan-current-custom-vocab)
                   ;; Try root form (Tibetan)
                   (gethash root-form tibetan-current-custom-vocab))))
      ;; If not found, try Wylie conversion
      (unless entry
        (when (fboundp 'tibetan-to-wylie-fixed)
          (let* ((wylie (ignore-errors (tibetan-to-wylie-fixed word)))
                 (wylie-root (ignore-errors (tibetan-to-wylie-fixed root-form))))
            (setq entry (or (and wylie (gethash wylie tibetan-current-custom-vocab))
                           (and wylie-root (gethash wylie-root tibetan-current-custom-vocab)))))))
      entry)))

;; ============================================================================
;; PARTICLE STRIPPING
;; ============================================================================

(defun tibetan-strip-particles (word)
  "Strip common particles and punctuation from WORD to find root form.
Only strips unambiguous multi-character particles to avoid false positives."
  (let ((root word))
    ;; First strip any Tibetan punctuation
    (setq root (replace-regexp-in-string "[།༎༏]" "" root))

    ;; Then strip particles - ONLY multi-character ones or very clear single ones
    ;; Avoid stripping single chars that could be part of words (like ར in ཕྱིར)
    (let ((particle-patterns
           '("ཀྱིས" "གྱིས" "གིས" "འིས" "ཡིས"    ; ergative (longer first)
             "འི" "ཀྱི" "གི" "ཡི" "གྱི"           ; genitive
             "པས" "བས"                             ; causal converb
             "ནས" "ལས"                             ; ablative
             "སྟེ" "ཏེ" "ཅིང" "ཞིང"              ; converbs
             "ཀྱང" "ཡང" "འང"                     ; concessive
             "ནི"                                   ; topic
             "སོ" "ཏོ" "ནོ" "དོ" "རོ" "འོ" "ངོ")))  ; sentence-final
      (dolist (particle particle-patterns)
        (when (string-suffix-p particle root)
          (setq root (tibetan-vocab-safe-substring root 0 (- (length root) (length particle)))))))
    root))

;; ============================================================================
;; VOCABULARY LOOKUP
;; ============================================================================

(defun tibetan-lookup-word-in-local-glossary (word)
  "Look up WORD in local comprehensive glossary.
Tries Tibetan script first, then converts to Wylie for lookup.
Returns meaning if found, nil otherwise."
  (when (and (boundp 'tibetan-comprehensive-vocabulary)
             tibetan-comprehensive-vocabulary)
    (let* ((root-form (tibetan-strip-particles word))
           (entry (or
                   ;; Try full word as-is (Tibetan script)
                   (gethash word tibetan-comprehensive-vocabulary)
                   ;; Try word with particles stripped (Tibetan script)
                   (gethash root-form tibetan-comprehensive-vocabulary))))
      ;; If not found with Tibetan script, try Wylie conversion
      ;; (glossaries are often keyed by Wylie like "'jig rten")
      (unless entry
        (when (fboundp 'tibetan-to-wylie-fixed)
          (let* ((wylie (ignore-errors (tibetan-to-wylie-fixed word)))
                 (wylie-root (ignore-errors (tibetan-to-wylie-fixed root-form))))
            (setq entry (or
                         (and wylie (gethash wylie tibetan-comprehensive-vocabulary))
                         (and wylie-root (gethash wylie-root tibetan-comprehensive-vocabulary)))))))
      (when entry
        (if (listp entry) (car entry) entry)))))

(defun tibetan-lookup-word-in-dharmamitra (word)
  "Look up WORD in DharmaMitra with caching.
Returns meaning if found, nil otherwise."
  (let ((cached (gethash word tibetan-dharmamitra-cache)))
    (if cached
        ;; Return cached result
        cached
      ;; Query DharmaMitra and cache result
      (when (fboundp 'dharmamitra-text-get-translation)
        (condition-case nil
            (let ((dm-trans (dharmamitra-text-get-translation word)))
              (when (and dm-trans
                        (not (string-empty-p dm-trans))
                        (not (string= dm-trans "null")))
                (setq dm-trans (string-trim dm-trans))
                ;; Clean up DharmaMitra output: remove quotes, "A/An/The" prefixes
                (setq dm-trans (replace-regexp-in-string "^[\"']\\|[\"']$" "" dm-trans))
                (setq dm-trans (replace-regexp-in-string "^\\(A\\|An\\|The\\) " "" dm-trans))
                (setq dm-trans (downcase dm-trans))
                ;; Cache it
                (puthash word dm-trans tibetan-dharmamitra-cache)
                dm-trans))
          (error nil))))))

(defun tibetan-format-bilingual-meaning (english german)
  "Format ENGLISH and GERMAN meanings, English first, German in brackets.
If only one is available, return that. If both, format as 'english (DE: german)'."
  (cond
   ((and english german
         (not (string= english german))
         (not (string-match-p "^[A-Z]" german)))  ; German often starts with capital
    ;; Both available and different
    (format "%s (DE: %s)" english german))
   ((and english german (not (string= english german)))
    (format "%s (DE: %s)" english german))
   (english english)
   (german german)
   (t nil)))

(defun tibetan-extract-english-from-bilingual (meaning)
  "Extract English part from a bilingual meaning string.
Handles formats like 'German // English' or 'German (English)'."
  (when (and meaning (stringp meaning))
    (cond
     ;; Format: "German // English"
     ((string-match "// *\\(.+\\)$" meaning)
      (string-trim (match-string 1 meaning)))
     ;; Format: "German (English)" - but not "(DE: ...)"
     ((and (string-match "(\\([^)]+\\)) *$" meaning)
           (let ((matched (match-string 0 meaning)))
             (not (string-match-p "^(DE:" matched))))
      (string-trim (match-string 1 meaning)))
     ;; Already English (starts with lowercase or common English words)
     ((string-match-p "^\\(to \\|a \\|the \\|[a-z]\\)" meaning)
      meaning)
     (t meaning))))

(defun tibetan-lookup-word (word &optional prev-word)
  "Look up WORD with optional PREV-WORD for compound detection.
Returns meaning with English first, German in brackets if available.
Priority: Rangjung Yeshe (English) > Resources (German) > others."
  (let ((meaning nil))
    ;; Try compound if prev-word provided
    (when prev-word
      (let* ((compound (concat prev-word "་" word))
             (compound-stripped (concat (tibetan-strip-particles prev-word) "་"
                                       (tibetan-strip-particles word)))
             (english-meaning nil)
             (german-meaning nil))
        ;; Get English from Rangjung Yeshe/local glossary
        (setq english-meaning (or (tibetan-lookup-word-in-rangjung-yeshe compound)
                                  (tibetan-lookup-word-in-rangjung-yeshe compound-stripped)
                                  (tibetan-lookup-word-in-local-glossary compound)
                                  (tibetan-lookup-word-in-local-glossary compound-stripped)))
        ;; Get German from Resources/custom
        (setq german-meaning (or (tibetan-lookup-word-in-resources-vocab compound)
                                 (tibetan-lookup-word-in-resources-vocab compound-stripped)
                                 (tibetan-lookup-word-in-custom-vocab compound)
                                 (tibetan-lookup-word-in-custom-vocab compound-stripped)))
        ;; Handle "German // English" format
        (when (and german-meaning (string-match-p "//" german-meaning))
          (let ((parts (split-string german-meaning "//" t)))
            (when (>= (length parts) 2)
              (setq german-meaning (string-trim (car parts)))
              (unless english-meaning
                (setq english-meaning (string-trim (cadr parts)))))))
        ;; Merge bilingual
        (setq meaning (tibetan-format-bilingual-meaning
                       (tibetan-extract-english-from-bilingual english-meaning)
                       german-meaning))
        ;; Fallback to DharmaMitra
        (unless meaning
          (setq meaning (tibetan-lookup-word-in-dharmamitra compound)))))

    ;; Try single word if compound not found
    (unless meaning
      ;; Strategy: Get English from Rangjung Yeshe, German from Resources, merge
      (let ((english-meaning nil)
            (german-meaning nil)
            (word-stripped (tibetan-strip-particles word)))

        ;; 1. Get English meaning (Rangjung Yeshe is primarily English)
        (setq english-meaning (or (tibetan-lookup-word-in-rangjung-yeshe word)
                                  (tibetan-lookup-word-in-rangjung-yeshe word-stripped)
                                  (tibetan-lookup-word-in-local-glossary word)
                                  (tibetan-lookup-word-in-local-glossary word-stripped)))

        ;; 2. Get German meaning from Resources/Custom vocab
        (setq german-meaning (or (tibetan-lookup-word-in-resources-vocab word)
                                 (tibetan-lookup-word-in-resources-vocab word-stripped)
                                 (tibetan-lookup-word-in-custom-vocab word)
                                 (tibetan-lookup-word-in-custom-vocab word-stripped)))

        ;; 3. If German has "// English" format, extract both parts
        (when (and german-meaning (string-match-p "//" german-meaning))
          (let ((parts (split-string german-meaning "//" t)))
            (when (>= (length parts) 2)
              (setq german-meaning (string-trim (car parts)))
              (unless english-meaning
                (setq english-meaning (string-trim (cadr parts)))))))

        ;; 4. Merge: English first, German in brackets
        (setq meaning (tibetan-format-bilingual-meaning
                       (tibetan-extract-english-from-bilingual english-meaning)
                       german-meaning))

        ;; 5. Fallback to DharmaMitra if nothing found
        (unless meaning
          (setq meaning (tibetan-lookup-word-in-dharmamitra word)))))

    meaning))

;; ============================================================================
;; CONVERB PATTERN DETECTION
;; ============================================================================

(defconst tibetan-converb-particles
  '("ཅིང" "ཞིང" "ཤིང"    ; simultaneous converbs
    "སྟེ" "ཏེ" "དེ"       ; sequential converbs
    "ནས"                   ; "after" converb
    )
  "List of converb particles that attach to verb stems.")

(defconst tibetan-nominalized-suffixes
  '("བར" "པར"             ; terminative on nominalizer (for purpose/goal)
    "བའི" "པའི"           ; genitive on nominalizer
    "བས" "པས"             ; instrumental/causal on nominalizer
    "བ" "པ"               ; plain nominalizer
    )
  "List of nominalized verb suffixes.")

(defun tibetan-detect-verb-with-suffix (syllables start-idx)
  "Detect if SYLLABLES starting at START-IDX form a verb+suffix pattern.
Returns (COMBINED-FORM BASE-VERB SUFFIX MEANING) or nil.
Handles: verb་ཅིང་, verb་སྟེ་, verb་བར་, verb་བའི་, etc."
  (let ((num-syls (length syllables)))
    (when (< (1+ start-idx) num-syls)
      (let* ((syl1 (nth start-idx syllables))
             (syl2 (nth (1+ start-idx) syllables))
             (combined (concat syl1 "་" syl2)))
        (cond
         ;; Check if syl2 is a converb particle
         ((member syl2 tibetan-converb-particles)
          (let ((base-meaning (or (tibetan-lookup-word-in-rangjung-yeshe syl1)
                                  (tibetan-lookup-word-in-local-glossary syl1)
                                  (tibetan-lookup-word-in-resources-vocab syl1)
                                  (tibetan-lookup-word-in-custom-vocab syl1))))
            (when base-meaning
              (list combined syl1 syl2 base-meaning))))
         ;; Check if syl2 is a nominalized suffix
         ((member syl2 tibetan-nominalized-suffixes)
          (let ((base-meaning (or (tibetan-lookup-word-in-rangjung-yeshe syl1)
                                  (tibetan-lookup-word-in-local-glossary syl1)
                                  (tibetan-lookup-word-in-resources-vocab syl1)
                                  (tibetan-lookup-word-in-custom-vocab syl1))))
            (when base-meaning
              (list combined syl1 syl2 base-meaning)))))))))

;; ============================================================================
;; VOCABULARY EXTRACTION
;; ============================================================================

(defun tibetan-extract-vocabulary (tibetan-text)
  "Extract vocabulary from TIBETAN-TEXT with meanings.
Returns list of (word . meaning) pairs.
Uses greedy matching: tries longer compounds first (4, 3, 2 syllables) before single.
Handles compound detection and particle stripping automatically.
Priority: Resources > Custom > Local glossary > Rangjung Yeshe > DharmaMitra."
  (when tibetan-text
    ;; Load vocabularies
    (tibetan-load-resources-vocab)
    (tibetan-load-custom-vocab)
    ;; First normalize: replace spaces with tsheg for consistent splitting
    (setq tibetan-text (replace-regexp-in-string " " "་" tibetan-text))
    (let* ((words (split-string tibetan-text "་" t))
           (num-words (length words))
           (vocab '())
           (i 0))
      (while (< i num-words)
        (let* ((word (string-trim (nth i words)))
               (word-stripped (tibetan-strip-particles word))
               (found nil)
               (matched-len 1))

          (if (or (string-empty-p word) (string-match-p "^[།༎༏]+$" word))
              (setq i (+ i 1))

            ;; FIRST: Check for verb+converb or verb+nominalized patterns
            ;; This handles ཚིག་ཅིང་ (burning), འབར་བར་ (to blaze), etc.
            (let ((verb-pattern (tibetan-detect-verb-with-suffix words i)))
              (when verb-pattern
                (let* ((combined (nth 0 verb-pattern))
                       (base-verb (nth 1 verb-pattern))
                       (suffix (nth 2 verb-pattern))
                       (base-meaning (nth 3 verb-pattern))
                       ;; Build meaning description based on suffix type
                       (suffix-desc (cond
                                     ((member suffix '("ཅིང" "ཞིང" "ཤིང"))
                                      (format "%s [converb: and/while]" base-meaning))
                                     ((member suffix '("སྟེ" "ཏེ" "དེ"))
                                      (format "%s [converb: and then]" base-meaning))
                                     ((member suffix '("བར" "པར"))
                                      (format "%s [nominalized: in order to]" base-meaning))
                                     ((member suffix '("བའི" "པའི"))
                                      (format "%s [nominalized genitive: of -ing]" base-meaning))
                                     ((member suffix '("བས" "པས"))
                                      (format "%s [causal: because of -ing]" base-meaning))
                                     ((member suffix '("བ" "པ"))
                                      (format "%s [nominalized]" base-meaning))
                                     (t base-meaning))))
                  (push (cons combined suffix-desc) vocab)
                  (setq found t)
                  (setq matched-len 2)))) ;; close setq, let*, when, outer let

            ;; SECOND: Greedy matching - try 4, 3, 2 syllable compounds
            (unless found
              (cl-loop for compound-len from 4 downto 2
                       until found
                       when (<= (+ i compound-len) num-words)
                       do
                       (let* ((syls-raw (cl-loop for j from i below (+ i compound-len)
                                                 collect (string-trim (nth j words))))
                              (compound-raw (mapconcat #'identity syls-raw "་"))
                              ;; Use bilingual lookup for compounds
                              (meaning (tibetan-lookup-word compound-raw)))
                         ;; If found, record and skip forward
                         (when meaning
                           (push (cons compound-raw meaning) vocab)
                           (setq found t)
                           (setq matched-len compound-len)))))

            ;; THIRD: If no compound found, lookup single word using bilingual lookup
            (unless found
              (let ((meaning (tibetan-lookup-word word)))
                ;; Add to vocab (even if meaning is nil, to show [look up] message)
                (push (cons word (or meaning "[look up]")) vocab)))

            ;; Advance by the number of words matched
            (setq i (+ i matched-len)))))

      (nreverse vocab))))

;; ============================================================================
;; GLOSSARY LOADING
;; ============================================================================

(defun tibetan-vocabulary-initialize ()
  "Initialize vocabulary by loading bundled glossaries.
Called automatically when tibetan-vocabulary is loaded.
Set `tibetan-skip-external-glossaries' to non-nil to skip loading."
  ;; Skip if testing flag is set
  (when (not (bound-and-true-p tibetan-skip-external-glossaries))
    (let ((bundled-glossary (expand-file-name
                             "data/tibetan-bundled-glossary.el"
                             (file-name-directory
                              (or load-file-name
                                  (locate-library "tibetan-cat")
                                  default-directory)))))
      ;; Try bundled glossary first (for standalone package use)
      (if (file-exists-p bundled-glossary)
          (progn
            (load bundled-glossary)
            (when (fboundp 'tibetan-bundled-load-all-glossaries)
              (tibetan-bundled-load-all-glossaries)))
        ;; Fall back to external glossary path (legacy support)
        (let ((external-glossary (expand-file-name
                                  "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el")))
          (when (file-exists-p external-glossary)
            (load-file external-glossary)))))))

(defun reload-all-glossaries ()
  "Reload all glossaries including bundled and external sources."
  (interactive)
  (cond
   ;; Try bundled glossary reload first
   ((fboundp 'tibetan-bundled-reload-glossaries)
    (tibetan-bundled-reload-glossaries)
    (message "Reloaded bundled glossaries"))
   ;; Fall back to legacy function
   ((fboundp 'load-all-glossaries)
    (load-all-glossaries)
    (message "Reloaded all glossaries"))
   ;; Try to load from external path
   (t
    (let ((glossary-file (expand-file-name
                          "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el")))
      (if (file-exists-p glossary-file)
          (progn
            (message "Loading glossary system...")
            (load-file glossary-file)
            (message "Glossary system loaded"))
        (message "No glossary files found"))))))

;; Auto-initialize glossaries when loaded
(tibetan-vocabulary-initialize)

;; ============================================================================
;; VOCABULARY FORMATTING - Improved readable display
;; ============================================================================

(defun tibetan-vocab-extract-short-meaning (full-meaning)
  "Extract a short, readable meaning from FULL-MEANING.
Returns just the core translation without lengthy explanations."
  (when (and full-meaning (stringp full-meaning))
    (let ((meaning full-meaning))
      ;; If it starts with "in tibetan..." or similar preamble, try to extract the core
      (when (string-match "\\*\\([^*]+\\)\\*.*primarily refers to \"\\([^\"]+\\)\"" meaning)
        (setq meaning (format "%s - %s" (match-string 1 meaning) (match-string 2 meaning))))
      ;; If still too long and has multiple meanings, take first one
      (when (and (> (length meaning) 80)
                 (string-match "^\\([^.!?:]+[.!?]?\\)" meaning))
        (setq meaning (match-string 1 meaning)))
      ;; If it has numbered list (1. 2. etc), take up to first item
      (when (string-match "^\\(.*?\\)\\s-*1\\." meaning)
        (let ((preamble (string-trim (match-string 1 meaning))))
          (when (> (length preamble) 10)
            (setq meaning preamble))))
      ;; Truncate if still too long
      (when (> (length meaning) 100)
        (setq meaning (concat (substring meaning 0 97) "...")))
      (string-trim meaning))))

(defun tibetan-vocab-has-extended-info-p (full-meaning)
  "Check if FULL-MEANING has extended information worth showing."
  (and full-meaning
       (stringp full-meaning)
       (> (length full-meaning) 120)))

(defun tibetan-vocab-format-entry (tibetan-word full-meaning &optional format-type)
  "Format a single vocabulary entry for display.
TIBETAN-WORD is the Tibetan text.
FULL-MEANING is the full dictionary meaning.
FORMAT-TYPE controls output style:
  nil or 'compact  - Short one-line format: Tibetan *wylie* — short-meaning
  'org-compact     - Org format with short meaning (for vocab section)
  'org-detailed    - Org format with full meaning (for detailed section)
  'full            - Plain text with full meaning (for classroom detailed)
Returns formatted string."
  (let* ((wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed tibetan-word))
                  (error nil)))
         (short-meaning (tibetan-vocab-extract-short-meaning full-meaning))
         (display-meaning (or full-meaning "[look up]")))
    (pcase format-type
      ;; Org-mode compact: short meaning, no extended block
      ('org-compact
       (format "- %s /*%s*/ — %s"
               tibetan-word
               (or wylie "")
               (or short-meaning "[look up]")))
      ;; Org-mode detailed: full dictionary entry
      ('org-detailed
       (format "- %s /*%s*/\n  %s"
               tibetan-word
               (or wylie "")
               (string-trim display-meaning)))
      ;; Plain text full: for classroom detailed section
      ('full
       (format "  %s *%s*\n    %s"
               tibetan-word
               (or wylie "")
               (string-trim display-meaning)))
      ;; Default compact: short one-liner
      (_
       (format "  %s *%s* — %s"
               tibetan-word
               (or wylie "")
               (or short-meaning "[look up]"))))))

(defun tibetan-vocab-format-list (vocab-pairs &optional format-type)
  "Format a list of vocabulary pairs for display.
VOCAB-PAIRS is list of (tibetan . meaning) cons cells.
FORMAT-TYPE is passed to `tibetan-vocab-format-entry'.
Returns formatted string."
  (let ((entries '()))
    (dolist (pair vocab-pairs)
      (let ((tib (car pair))
            (meaning (cdr pair)))
        (push (tibetan-vocab-format-entry tib meaning format-type) entries)))
    (mapconcat 'identity (nreverse entries) "\n")))

(defun tibetan-vocab-format-detailed-list (vocab-pairs &optional for-org)
  "Format vocabulary list with FULL dictionary entries.
VOCAB-PAIRS is list of (tibetan . meaning) cons cells.
FOR-ORG if non-nil, uses org-mode formatting.
Returns formatted string with complete dictionary information."
  (let ((entries '()))
    (dolist (pair vocab-pairs)
      (let* ((tib (car pair))
             (meaning (cdr pair))
             (format-type (if for-org 'org-detailed 'full)))
        (push (tibetan-vocab-format-entry tib meaning format-type) entries)))
    (mapconcat 'identity (nreverse entries) "\n\n")))

(provide 'tibetan-vocabulary)
;;; tibetan-vocabulary.el ends here
