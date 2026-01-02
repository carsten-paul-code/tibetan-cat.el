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

(defvar tibetan-current-custom-vocab nil
  "Current buffer's custom vocabulary hash-table, or nil if none.")

;; ============================================================================
;; CUSTOM VOCABULARY FILE SUPPORT
;; ============================================================================

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
Returns meaning if found, nil otherwise."
  (when (and (boundp 'tibetan-comprehensive-vocabulary)
             tibetan-comprehensive-vocabulary)
    (let* ((root-form (tibetan-strip-particles word))
           (entry (or
                   ;; Try full word as-is
                   (gethash word tibetan-comprehensive-vocabulary)
                   ;; Try word with particles stripped
                   (gethash root-form tibetan-comprehensive-vocabulary))))
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

(defun tibetan-lookup-word (word &optional prev-word)
  "Look up WORD with optional PREV-WORD for compound detection.
Priority order:
1. Custom vocabulary (if #+TIBETAN_VOCAB_FILE is set)
2. Local comprehensive glossary
3. DharmaMitra API fallback
Returns meaning string or nil."
  (let ((meaning nil))
    ;; Try compound if prev-word provided
    (when prev-word
      (let* ((compound (concat prev-word "་" word))
             (compound-stripped (concat (tibetan-strip-particles prev-word) "་"
                                       (tibetan-strip-particles word))))
        ;; 1. Try custom vocabulary first
        (setq meaning (or (tibetan-lookup-word-in-custom-vocab compound)
                         (tibetan-lookup-word-in-custom-vocab compound-stripped)))
        ;; 2. Try local glossary
        (unless meaning
          (setq meaning (or (tibetan-lookup-word-in-local-glossary compound)
                           (tibetan-lookup-word-in-local-glossary compound-stripped))))
        ;; 3. If not found, try DharmaMitra
        (unless meaning
          (setq meaning (tibetan-lookup-word-in-dharmamitra compound)))))

    ;; Try single word if compound not found
    (unless meaning
      ;; 1. Try custom vocabulary first
      (setq meaning (tibetan-lookup-word-in-custom-vocab word))
      ;; 2. Try local glossary
      (unless meaning
        (setq meaning (tibetan-lookup-word-in-local-glossary word)))
      ;; 3. If not found, try DharmaMitra
      (unless meaning
        (setq meaning (tibetan-lookup-word-in-dharmamitra word))))

    meaning))

;; ============================================================================
;; VOCABULARY EXTRACTION
;; ============================================================================

(defun tibetan-extract-vocabulary (tibetan-text)
  "Extract vocabulary from TIBETAN-TEXT with meanings.
Returns list of (word . meaning) pairs.
Handles compound detection and particle stripping automatically.
Checks custom vocabulary first if #+TIBETAN_VOCAB_FILE is set."
  (when tibetan-text
    ;; Load custom vocabulary if available
    (tibetan-load-custom-vocab)
    ;; First normalize: replace spaces with tsheg for consistent splitting
    (setq tibetan-text (replace-regexp-in-string " " "་" tibetan-text))
    (let* ((words (split-string tibetan-text "་" t))
           (vocab '())
           (i 0))
      (while (< i (length words))
        (let* ((word (string-trim (nth i words)))
               (next (when (< (+ i 1) (length words))
                      (string-trim (nth (+ i 1) words)))))
          (if (or (string-empty-p word) (string-match-p "^[།༎༏]+$" word))
              (setq i (+ i 1))

            ;; Try to find a 2-syllable compound first
            (let* ((compound-raw (when next (concat word "་" next)))
                   (word-stripped (tibetan-strip-particles word))
                   (next-stripped (when next (tibetan-strip-particles next)))
                   (compound-stripped (when next (concat word-stripped "་" next-stripped)))
                   (found-compound nil)
                   (meaning nil))

              ;; Check if compound exists
              (when next
                ;; 1. Try custom vocabulary first
                (setq meaning (or (tibetan-lookup-word-in-custom-vocab compound-raw)
                                 (tibetan-lookup-word-in-custom-vocab compound-stripped)))
                ;; 2. Try local glossary (raw first, then stripped)
                (unless meaning
                  (setq meaning (or (tibetan-lookup-word-in-local-glossary compound-raw)
                                   (tibetan-lookup-word-in-local-glossary compound-stripped))))

                ;; 3. If not found, try DharmaMitra for compound
                (unless meaning
                  (setq meaning (tibetan-lookup-word-in-dharmamitra compound-raw)))

                ;; If compound found, add to vocab and skip next word
                (when meaning
                  (setq found-compound t)
                  (push (cons (concat word "་" next) meaning) vocab)
                  (setq i (+ i 2))))

              ;; If no compound, lookup single word
              (unless found-compound
                ;; 1. Try custom vocabulary first
                (setq meaning (tibetan-lookup-word-in-custom-vocab word))
                (unless meaning
                  (setq meaning (tibetan-lookup-word-in-custom-vocab word-stripped)))
                ;; 2. Try local glossary
                (unless meaning
                  (setq meaning (or (tibetan-lookup-word-in-local-glossary word)
                                   (and (not (equal word word-stripped))
                                        (tibetan-lookup-word-in-local-glossary word-stripped)))))

                ;; 3. If not found, try DharmaMitra
                (unless meaning
                  (setq meaning (tibetan-lookup-word-in-dharmamitra word)))

                ;; Add to vocab (even if meaning is nil, to show [look up] message)
                (push (cons word (or meaning "[look up]")) vocab)
                (setq i (+ i 1)))))))

      (nreverse vocab))))

;; ============================================================================
;; GLOSSARY LOADING
;; ============================================================================

(defun tibetan-vocabulary-initialize ()
  "Initialize vocabulary by loading bundled glossaries.
Called automatically when tibetan-vocabulary is loaded."
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
          (load-file external-glossary))))))

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

(provide 'tibetan-vocabulary)
;;; tibetan-vocabulary.el ends here
