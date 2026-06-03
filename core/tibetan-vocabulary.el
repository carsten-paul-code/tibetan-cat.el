;;; tibetan-vocabulary.el --- Vocabulary lookup with DharmaMitra fallback -*- lexical-binding: t -*-

;;; Commentary:
;; Provides vocabulary lookup with multiple configurable sources:
;; 1. Resources folder wordlist (auto-detected from ../Resources/)
;; 2. Custom vocabulary file (per-document, via #+TIBETAN_VOCAB_FILE header)
;; 3. Rangjung Yeshe dictionary (English, bundled)
;; 4. Christian Steinert's dictionary collection (Hopkins, Valby, 84000, etc.)
;; 5. Local comprehensive glossaries (17,777 entries)
;; 6. DharmaMitra API fallback with caching
;;
;; Handles:
;; - Compound word detection
;; - Particle stripping
;; - Bilingual merge (English + German)
;; - Cached translations to avoid repeated API calls
;;
;; Dictionary priority is configurable:
;; - Global: customize `tibetan-dictionary-priority'
;; - Per-buffer: #+TIBETAN_DICT_PRIORITY: resources custom rangjung-yeshe
;;
;; Custom vocabulary:
;; Add #+TIBETAN_VOCAB_FILE: path/to/wordlist.pdf to your document header
;; The PDF will be parsed and cached for priority lookup
;;
;; Resources wordlist:
;; Place a wordlist.txt (or .pdf/.org) in the Resources/ folder next to
;; your working file.  Supports multiple formats including term-on-line
;; with indented definition below.

;;; Code:

(require 'cl-lib)
;; Steinert is the SQLite-backed dictionary layer (see core/tibetan-steinert.el).
;; Soft-required so this file still loads when the DB or sqlite.el is absent —
;; `tibetan-lookup-word-in-steinert' handles the disabled case gracefully.
(require 'tibetan-steinert nil t)

;; `tibetan-vocab--mwu-exists-p' lives in `core/tibetan-vocabulary-
;; detailed.el', which itself requires this file — so we declare the
;; symbol here (avoiding the circular `require') and let the
;; `fboundp' guard at the actual call site short-circuit when the
;; detailed module isn't loaded yet (in which case MWU detection
;; falls back to single-syllable, the same result as on a fresh
;; checkout without dictionary backing).
(declare-function tibetan-vocab--mwu-exists-p "tibetan-vocabulary-detailed" (compound))

;; ============================================================================
;; DICTIONARY PRIORITY CONFIGURATION
;; ============================================================================

(defcustom tibetan-dictionary-priority
  '(resources custom verbs rangjung-yeshe steinert local-glossary dharmamitra)
  "Priority order for dictionary lookup.
Each symbol names a dictionary source.  When looking up a word,
sources are tried in order; the first match wins for each language
category (English sources vs. German sources are merged separately).

Available sources:
  `resources'       — Wordlist from the Resources folder (auto-detected).
                      Bilingual German // English.  Ideal for text-specific
                      vocabulary prepared for class or study.
  `custom'          — Per-document vocabulary (via #+TIBETAN_VOCAB_FILE).
  `verbs'           — Verb classifier database with stem forms,
                      transitivity, and case frames.
  `rangjung-yeshe'  — Rangjung Yeshe dictionary (~162k entries, English).
  `steinert'        — Christian Steinert's dictionary collection
                      (Hopkins, Valby, Waldo, 84000, Bialek, etc.).
                      Wylie-keyed pipe-delimited files.
  `local-glossary'  — Bundled glossaries: common vocabulary, Hopkins,
                      Madhyamaka terms, tibetan-english, unified.
  `dharmamitra'     — DharmaMitra API (online AI translation fallback).

Can be overridden per-buffer with an org header:
  #+TIBETAN_DICT_PRIORITY: resources custom verbs rangjung-yeshe steinert

Example configurations:
  ;; Classroom: text wordlist first, then general
  (setq tibetan-dictionary-priority
        \\='(resources custom verbs rangjung-yeshe
          steinert local-glossary dharmamitra))
  ;; Research: Steinert collection first for breadth
  (setq tibetan-dictionary-priority
        \\='(steinert rangjung-yeshe verbs resources
          local-glossary dharmamitra))"
  :type '(repeat (choice (const :tag "Resources folder wordlist" resources)
                         (const :tag "Custom vocab file" custom)
                         (const :tag "Verb classifier" verbs)
                         (const :tag "Rangjung Yeshe" rangjung-yeshe)
                         (const :tag "Steinert collection" steinert)
                         (const :tag "Local glossary" local-glossary)
                         (const :tag "DharmaMitra API" dharmamitra)))
  :group 'tibetan)

(defun tibetan-get-buffer-dict-priority ()
  "Get dictionary priority for current buffer.
Checks for #+TIBETAN_DICT_PRIORITY header first, falls back to
`tibetan-dictionary-priority' customization."
  (or (save-excursion
        (goto-char (point-min))
        (when (re-search-forward
               "^#\\+TIBETAN_DICT_PRIORITY:\\s-*\\(.+\\)$" nil t)
          (let ((sources (split-string (match-string 1) "\\s-+" t)))
            (mapcar #'intern sources))))
      tibetan-dictionary-priority))

(defun tibetan--lookup-in-source (source word &optional word-stripped)
  "Look up WORD in dictionary SOURCE.  Try WORD-STRIPPED as fallback.
Returns meaning string or nil."
  (let ((stripped (or word-stripped (tibetan-strip-particles word))))
    (pcase source
      ('resources
       (or (tibetan-lookup-word-in-resources-vocab word)
           (tibetan-lookup-word-in-resources-vocab stripped)))
      ('custom
       (or (tibetan-lookup-word-in-custom-vocab word)
           (tibetan-lookup-word-in-custom-vocab stripped)))
      ('verbs
       (when (fboundp 'tibetan-verb-lookup)
         (let ((verb-entry (or (tibetan-verb-lookup word)
                               (tibetan-verb-lookup stripped))))
           (when verb-entry
             ;; Format verb entry for display
             (let ((meaning (alist-get 'meaning verb-entry))
                   (trans (alist-get 'transitivity verb-entry))
                   (case-frame (alist-get 'case_frame verb-entry)))
               (when meaning
                 (concat meaning
                         (when (or trans case-frame)
                           (format " [verb: %s%s]"
                                   (or trans "")
                                   (if case-frame
                                       (format ", %s" case-frame) ""))))))))))
      ('rangjung-yeshe
       (or (tibetan-lookup-word-in-rangjung-yeshe word)
           (tibetan-lookup-word-in-rangjung-yeshe stripped)))
      ('steinert
       (or (tibetan-lookup-word-in-steinert word)
           (tibetan-lookup-word-in-steinert stripped)))
      ('local-glossary
       (or (tibetan-lookup-word-in-local-glossary word)
           (tibetan-lookup-word-in-local-glossary stripped)))
      ('dharmamitra
       (tibetan-lookup-word-in-dharmamitra word)))))

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
  "Look up WORD in the combined 64-source dictionary or Rangjung Yeshe.
Tries the combined dictionary first (if loaded from init-tibetan-legacy.el),
then falls back to the local Rangjung Yeshe copy.
Returns meaning if found, nil otherwise."
  (let* ((root-form (tibetan-strip-particles word))
         (entry nil))
    ;; 1. Try combined 64-source dictionary (loaded by init-tibetan-legacy.el)
    (when (fboundp 'lookup-combined-dictionary-first)
      (setq entry (or (lookup-combined-dictionary-first word)
                      (lookup-combined-dictionary-first root-form)
                      ;; Try with/without trailing tsheg
                      (unless (string-suffix-p "་" word)
                        (lookup-combined-dictionary-first (concat word "་")))
                      (unless (string-suffix-p "་" root-form)
                        (lookup-combined-dictionary-first (concat root-form "་"))))))
    ;; 2. Fallback to local Rangjung Yeshe copy
    (unless entry
      (tibetan-rangjung-yeshe-load)
      (when tibetan-rangjung-yeshe-vocabulary
        (setq entry (or (gethash word tibetan-rangjung-yeshe-vocabulary)
                        (gethash root-form tibetan-rangjung-yeshe-vocabulary)))
        ;; Try Wylie conversion
        (unless entry
          (when (fboundp 'tibetan-to-wylie-fixed)
            (let* ((wylie (ignore-errors (tibetan-to-wylie-fixed word)))
                   (wylie-root (ignore-errors (tibetan-to-wylie-fixed root-form))))
              (setq entry (or
                           (and wylie (gethash wylie tibetan-rangjung-yeshe-vocabulary))
                           (and wylie-root (gethash wylie-root tibetan-rangjung-yeshe-vocabulary)))))))))
    entry))

(defvar tibetan-current-custom-vocab nil
  "Current buffer's custom vocabulary hash-table, or nil if none.")

;; ============================================================================
;; STEINERT DICTIONARY COLLECTION (SQLite-backed, lazy query)
;; ============================================================================
;;
;; The heavy lifting lives in `core/tibetan-steinert.el', which queries a
;; SQLite database built from Christian Steinert's aggregated dictionary
;; sources (800k+ entries across 60+ glossaries). This file just exposes a
;; thin, priority-dispatch-compatible wrapper.
;;
;; If the DB isn't built yet, `tibetan-steinert-lookup' returns nil and
;; priority dispatch falls through to the next source — no crash, no
;; pre-loaded 215k-entry hash table sitting in RAM. Build with:
;;   make build-steinert
;; or run `scripts/build-steinert-db.py' directly. See NOTICE-steinert.md.

(defvar tibetan--steinert-build-hint-shown nil
  "Non-nil once the one-shot build-hint message has been emitted.")

(defun tibetan--steinert-maybe-hint-build ()
  "Print a one-time hint pointing at the DB build script.
Only fires when the SQLite backend is present but no DB is on disk,
so users who have intentionally disabled Steinert never see it."
  (unless tibetan--steinert-build-hint-shown
    (setq tibetan--steinert-build-hint-shown t)
    (when (and (featurep 'tibetan-steinert)
               (boundp 'tibetan-steinert-db-path)
               tibetan-steinert-db-path
               (not (file-readable-p tibetan-steinert-db-path)))
      (message "Steinert dictionary DB missing — run `make build-steinert' (or scripts/build-steinert-db.py) to enable it"))))

(defun tibetan-lookup-word-in-steinert (word)
  "Look up WORD in the Steinert dictionary collection.
Returns a single definition string tagged with its source
(e.g. \"...explanation... [01-Hopkins2015]\"), or nil when the
word is absent / the DB is unavailable.

This is the legacy-shaped entry point used by the priority
dispatcher in `tibetan--lookup-in-source'. The richer plist API
lives in `tibetan-steinert-lookup' in core/tibetan-steinert.el."
  (tibetan--steinert-maybe-hint-build)
  (when (fboundp 'tibetan-steinert-lookup)
    (let* ((hits (tibetan-steinert-lookup word 1))
           (first (car hits)))
      (when first
        (let ((gloss  (plist-get first :gloss))
              (source (plist-get first :source)))
          (when (and gloss (not (string-empty-p gloss)))
            (if (and source (not (string-empty-p source)))
                (format "%s [%s]" (string-trim gloss) source)
              (string-trim gloss))))))))

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
                 (current-def ""))
            (dolist (line lines)
              (cond
               ;; Page reference like "(30.6)" or "(31.3–4)"
               ((string-match "^(\\([0-9]+\\.[0-9]+\\))" line)
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
  "Store TERM with DEF in VOCAB-TABLE under both Wylie and Tibetan keys.
Strips folio markers like (12a5) and collapses extra whitespace."
  (let* ((clean-def (string-trim def))
         ;; Remove folio markers: (12a5), (16b), (3a2) etc.
         (clean-def (replace-regexp-in-string "([0-9]+[ab][0-9]*)" "" clean-def))
         ;; Collapse multiple spaces left by removal
         (clean-def (replace-regexp-in-string "  +" " " (string-trim clean-def))))
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
  - Indented: term on non-indented line, definition on indented line(s) below
Returns hash-table with both Wylie and Tibetan keys."
  (let ((vocab-table (make-hash-table :test 'equal)))
    (when (and txt-path (file-exists-p txt-path))
      (with-temp-buffer
        (insert-file-contents txt-path)
        (goto-char (point-min))
        ;; Detect format: if file has indented lines, use block mode
        (let ((has-indented-lines
               (save-excursion
                 (re-search-forward "^    " nil t))))
          (if has-indented-lines
              ;; Block mode: term on non-indented line, definition on indented lines
              (let ((current-term nil)
                    (current-def-parts nil))
                (while (not (eobp))
                  (let ((line (buffer-substring-no-properties
                               (line-beginning-position) (line-end-position))))
                    (cond
                     ;; Skip empty lines and comments
                     ((or (string-empty-p (string-trim line))
                          (string-match-p "^[#;/]" line))
                      ;; Save previous entry on blank line
                      (when (and current-term current-def-parts)
                        (tibetan--store-vocab-entry
                         vocab-table current-term
                         (mapconcat #'identity (nreverse current-def-parts) " "))
                        (setq current-term nil current-def-parts nil)))
                     ;; Indented line = definition continuation
                     ((string-match "^\\s-+\\(.+\\)" line)
                      (when current-term
                        (push (string-trim line) current-def-parts)))
                     ;; Non-indented line = new term
                     (t
                      ;; Save previous entry
                      (when (and current-term current-def-parts)
                        (tibetan--store-vocab-entry
                         vocab-table current-term
                         (mapconcat #'identity (nreverse current-def-parts) " ")))
                      (setq current-term (string-trim line))
                      (setq current-def-parts nil))))
                  (forward-line 1))
                ;; Save last entry
                (when (and current-term current-def-parts)
                  (tibetan--store-vocab-entry
                   vocab-table current-term
                   (mapconcat #'identity (nreverse current-def-parts) " "))))
            ;; Single-line mode (original behavior)
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
              (forward-line 1))))))
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
            ;; Load TXT files first (highest priority).
            (dolist (txt txt-files)
              (message "Loading Resources vocabulary from %s..." (file-name-nondirectory txt))
              (let ((entries (tibetan-parse-wordlist-txt txt)))
                (maphash (lambda (k v) (puthash k v vocab-table)) entries)))
            ;; Load ORG files.
            (dolist (org org-files)
              (message "Loading Resources vocabulary from %s..." (file-name-nondirectory org))
              (let ((entries (tibetan-parse-wordlist-org org)))
                (maphash (lambda (k v) (puthash k v vocab-table)) entries)))
            ;; Load PDF files only if no TXT/ORG entries were loaded.
            ;; The `pdftotext -layout' output for two-column Wortliste PDFs
            ;; interleaves right-column continuation text into left-column
            ;; entries, fusing neighbouring entries' glosses (e.g. ལྕགས་ཕོ
            ;; ended up with gloss text from `bya yis' + `khas nyen bab').
            ;; PDF output is therefore only trustworthy as a last resort.
            (if (> (hash-table-count vocab-table) 0)
                (when pdf-files
                  (message
                   "ℹ Skipping %d PDF wordlist file(s); TXT/ORG entries take precedence"
                   (length pdf-files)))
              (dolist (pdf pdf-files)
                (if (executable-find "pdftotext")
                    (progn
                      (message "Loading Resources vocabulary from %s..."
                               (file-name-nondirectory pdf))
                      (let ((entries (tibetan-parse-wordlist-pdf pdf)))
                        (maphash (lambda (k v) (puthash k v vocab-table)) entries)))
                  (message "⚠ Cannot load %s - pdftotext not installed. Export to .txt or install poppler."
                           (file-name-nondirectory pdf)))))
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
                 (in-word-list nil)
                 (current-term nil)
                 (current-def ""))
            ;; Parse the word list format.  current-term / current-def
            ;; are bound at let* scope so the post-loop save-last-entry
            ;; block at the bottom of the function can see their final
            ;; values without byte-compile warnings.
            (dolist (line lines)
              ;; Detect start of word list section
              (when (string-match "^Word list" line)
                (setq in-word-list t))

              (when in-word-list
                (cond
                 ;; Skip section headers like "(142.2–5)" or "The Brahmin's Dog"
                 ((or (string-match "^([0-9.].*)" line)
                      (string-match "^The " line)
                      (string-match "^Secondary Literature" line)
                      (string-match "^[0-9]+$" line)
                      (string-empty-p (string-trim line)))
                  (tibetan--maybe-store-vocab-entry
                   vocab-table current-term current-def)
                  (setq current-term nil)
                  (setq current-def ""))

                 ;; Line starting with Tibetan character = new Tibetan term
                 ((string-match "^\\([ཀ-ྼ][^[:space:]]*\\)" line)
                  (when (and current-term (not (string-empty-p current-def)))
                    (puthash current-term (string-trim current-def)
                             vocab-table))
                  (setq current-term (match-string 1 line))
                  (setq current-def ""))

                 ;; Non-indented line with lowercase letters = Wylie term
                 ((and (not (string-match "^\\s-" line))
                       (string-match "^\\([a-z' ]+\\)$" (string-trim line)))
                  (tibetan--maybe-store-vocab-entry
                   vocab-table current-term current-def)
                  (setq current-term (string-trim line))
                  (setq current-def ""))

                 ;; Indented line = definition continuation
                 ((and current-term
                       (string-match "^\\s-+\\(.+\\)" line))
                  (setq current-def
                        (concat current-def
                                (if (string-empty-p current-def) "" " ")
                                (string-trim (match-string 1 line))))))))

            ;; Save last entry (still inside the let*).
            (tibetan--maybe-store-vocab-entry
             vocab-table current-term current-def))
        (error
         (message "Warning: Could not parse vocab PDF %s: %s" pdf-path err))))
    vocab-table))

(defun tibetan--maybe-store-vocab-entry (vocab-table term def)
  "Store TERM with DEF in VOCAB-TABLE under Wylie and (if convertible)
Tibetan keys, when TERM is non-nil and DEF non-empty.  No-op otherwise."
  (when (and term (stringp def) (not (string-empty-p def)))
    (let ((trimmed (string-trim def)))
      (unless (string-empty-p trimmed)
        (puthash term trimmed vocab-table)
        (when (fboundp 'tibetan-wylie-to-tibetan)
          (let ((tib (ignore-errors (tibetan-wylie-to-tibetan term))))
            (when (and tib (not (string-empty-p tib)))
              (puthash tib trimmed vocab-table))))))))

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
Only strips unambiguous multi-character particles to avoid false positives.
Also trims any trailing tsheg (་) or whitespace so that stripped forms
match the canonical (tsheg-free) keys used in the Resources and other
dictionaries.

Verb-stem guard: if WORD is itself a known Hill-DB verb form (past,
imperative, etc.), it is returned unchanged.  Without this guard
`བསླབས' (past of སློབ) and `སླེབས' (past of སླེབ) would match the
`བས' causal-converb pattern and get split into nonsense roots
(`བསླ' / `སླེ') that fail every dictionary lookup downstream."
  (let ((root word))
    ;; First strip any Tibetan punctuation
    (setq root (replace-regexp-in-string "[།༎༏]" "" root))

    ;; Short-circuit: if the full (punctuation-stripped) word is a
    ;; Hill-DB verb stem, it's an inflected verb form, NOT a lexical
    ;; root + particle.  Return as-is (minus trailing whitespace).
    (if (and (fboundp 'tibetan-verb-lookup)
             (ignore-errors (tibetan-verb-lookup root)))
        (replace-regexp-in-string "[་ \t]+$" "" root)

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
      ;; Strip trailing tsheg/whitespace left behind after particle removal
      ;; (e.g. "ཕམ་ནས" → strip "ནས" → "ཕམ་" → trim to "ཕམ" so it matches
      ;; Resources keys).
      (replace-regexp-in-string "[་ \t]+$" "" root))))

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
  "Look up WORD in DharmaMitra with caching (positive AND negative).
Returns meaning if found, nil otherwise.

A miss is cached as the sentinel `none' so repeated lookups of an
out-of-dictionary word during a batch do not re-hit the network on
every call (previously only hits were cached)."
  (let ((cached (gethash word tibetan-dharmamitra-cache 'absent)))
    (cond
     ((eq cached 'none) nil)                 ; cached miss
     ((not (eq cached 'absent)) cached)      ; cached hit (a string)
     (t
      (let ((result
             (when (fboundp 'dharmamitra-text-get-translation)
               (condition-case nil
                   (let ((dm-trans (dharmamitra-text-get-translation word)))
                     (when (and dm-trans
                                (not (string-empty-p dm-trans))
                                (not (string= dm-trans "null")))
                       (setq dm-trans (string-trim dm-trans))
                       ;; Clean up DM output: strip quotes, "A/An/The".
                       (setq dm-trans (replace-regexp-in-string "^[\"']\\|[\"']$" "" dm-trans))
                       (setq dm-trans (replace-regexp-in-string "^\\(A\\|An\\|The\\) " "" dm-trans))
                       (downcase dm-trans)))
                 (error nil)))))
        ;; Cache the outcome — `none' for a miss so we don't re-query.
        (puthash word (or result 'none) tibetan-dharmamitra-cache)
        result)))))

(defun tibetan-format-bilingual-meaning (english german)
  "Format ENGLISH and GERMAN meanings, English first, German in brackets.
If only one is available, return that. If both, format as
\='english (DE: german)\='."
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
Handles formats like \='German // English\=' or \='German (English)\='."
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

(defun tibetan--collect-bilingual (word &optional word-stripped)
  "Collect English and German meanings for WORD from all sources.
Respects `tibetan-dictionary-priority' for ordering.
Returns (ENGLISH-MEANING . GERMAN-MEANING) cons cell."
  (let ((priority (tibetan-get-buffer-dict-priority))
        (stripped (or word-stripped (tibetan-strip-particles word)))
        (english-meaning nil)
        (german-meaning nil))
    ;; English-primary sources: rangjung-yeshe, local-glossary, dharmamitra
    ;; German-primary sources: resources, custom (format: German // English)
    (dolist (source priority)
      (let ((result (tibetan--lookup-in-source source word stripped)))
        (when result
          (if (memq source '(resources custom))
              ;; German-primary: may contain "German // English"
              (unless german-meaning
                (if (string-match-p "//" result)
                    (let ((parts (split-string result "//" t)))
                      (setq german-meaning (string-trim (car parts)))
                      (when (and (>= (length parts) 2) (not english-meaning))
                        (setq english-meaning (string-trim (cadr parts)))))
                  (setq german-meaning result)))
            ;; English-primary
            (unless english-meaning
              (setq english-meaning result))))))
    (cons english-meaning german-meaning)))

(defun tibetan-lookup-word (word &optional prev-word)
  "Look up WORD with optional PREV-WORD for compound detection.
Returns meaning with bilingual merge (English + German).
Dictionary priority is controlled by `tibetan-dictionary-priority'
and can be overridden per-buffer with #+TIBETAN_DICT_PRIORITY."
  (let ((meaning nil))
    ;; Try compound if prev-word provided
    (when prev-word
      (let* ((compound (concat prev-word "་" word))
             (compound-stripped (concat (tibetan-strip-particles prev-word) "་"
                                       (tibetan-strip-particles word)))
             (bilingual (tibetan--collect-bilingual compound compound-stripped)))
        (setq meaning (tibetan-format-bilingual-meaning
                       (tibetan-extract-english-from-bilingual (car bilingual))
                       (cdr bilingual)))))

    ;; Try single word if compound not found
    (unless meaning
      (let* ((bilingual (tibetan--collect-bilingual word)))
        (setq meaning (tibetan-format-bilingual-meaning
                       (tibetan-extract-english-from-bilingual (car bilingual))
                       (cdr bilingual)))))

    meaning))

;; ============================================================================
;; VOCABULARY EXTRACTION
;; ============================================================================

(defconst tibetan-extract-vocab--particle-tails
  '("ར" "ལ" "ན" "ས" "སུ" "ཏུ" "དུ" "རུ" "ནས" "ལས" "དང"
    "གི" "གྱི" "ཀྱི" "ཡི" "ནི" "འི" "པར" "བར"
    "ཀྱིས" "གིས" "གྱིས" "ཡིས" "སྟེ" "ཏེ" "དེ"
    "ཅིང" "ཞིང" "ཤིང" "པས" "བས")
  "Case / converb particle tails that disqualify a compound lookup.
When the LAST syllable of a candidate 2-, 3-, or 4-syllable compound
matches one of these, `tibetan-extract-vocabulary' falls through to
the single-syllable loop so the stem and particle are tokenised
separately — matching the Particle Map's grammatical split.

Deliberately excludes nominaliser tails (`པ', `བ', `མ') because forms
like `བསྐལ་པ' (kalpa) and `ཆོས་ཉིད' are legitimate lexical compounds
that should be picked up as a unit.

Kept in sync with `tibetan-enhanced-parser--case-particle-tails';
see the comment in the MWU helper for the rationale.")

(defun tibetan-extract-vocab--tail-is-particle-p (joined)
  "Return non-nil when JOINED (a `་'-joined Tibetan compound) ends
in a case or converb particle listed in
`tibetan-extract-vocab--particle-tails'."
  (let ((parts (split-string joined "་" t)))
    (and parts
         (member (car (last parts))
                 tibetan-extract-vocab--particle-tails))))

(defun tibetan-extract-vocab--head-is-particle-p (joined)
  "Return non-nil when JOINED starts with a case or converb particle
listed in `tibetan-extract-vocab--particle-tails'.

A particle can never legitimately be the HEAD of a compound — it's
always attached to a preceding content word.  This rejection
prevents the greedy compound loop from stranding a particle with
the following word: e.g. after `བདག་ལ' has split into stem + LA,
the next iteration starts at `ལ' and must not be allowed to pick
up `ལ་སྟོད' (\"Latö, western Tsang\") as a 2-syllable compound."
  (let ((parts (split-string joined "་" t)))
    (and parts
         (member (car parts)
                 tibetan-extract-vocab--particle-tails))))

(declare-function tibetan-verb-lookup "tibetan-verb-classifier" (word))

(defun tibetan-extract-vocab--tail-is-verb-p (joined)
  "Return non-nil when JOINED (a `་'-joined compound of ≥2 syllables)
ends in a syllable that `tibetan-verb-lookup' recognises as a finite
Hill-DB verb.

Used to stop the greedy Interlinear MWU loop from gluing an
auto-sourced phrasal dictionary entry onto a following verb — e.g.
the Rangjung-Yeshe entry `དྲུང་དུ་ཕྱིན' was absorbing the verb `ཕྱིན'
(\"went\"), hiding it from clause / Verb-Classification analysis and
surfacing the entry's Tibetan example sentence as the token's gloss
(Milarepa Segment 39).

Mirrors `tibetan-enhanced-parser--verb-tail-p' for the second MWU
loop.  No-op (returns nil) when the verb classifier isn't loaded."
  (when (and joined (stringp joined) (fboundp 'tibetan-verb-lookup))
    (let* ((parts (split-string joined "་" t))
           (tail (car (last parts))))
      (and tail (>= (length parts) 2)
           (tibetan-verb-lookup tail) t))))

(defun tibetan-extract-vocabulary (tibetan-text)
  "Extract vocabulary from TIBETAN-TEXT with meanings.
Returns list of (word . meaning) pairs.

MWU detection uses `tibetan-vocab--mwu-exists-p' (the strict,
exact-key check shared with `tibetan-vocab-extract-detailed') so
the Interlinear Gloss and Detailed Dictionary agree on which
syllable groupings form MWUs.  Without this agreement, the
Interlinear used to emit `[[term-X][label]]' links whose `<<term-X>>'
anchors didn't exist in DD, breaking `org-export-dispatch'
(Tibetisch IV seg-049 report, 2026-05-18).

Greedy matching:  tries 4 / 3 / 2 syllable compounds before
falling back to single.  Rejects any compound whose head OR tail
syllable is a case / converb particle (`tibetan-extract-vocab--
{head,tail}-is-particle-p').

The legacy `verb+converb' merging path (which used to combine
`phyar' + `nas' into a `phyar nas [converb]' display token) has
been REMOVED — DD never produced a matching anchor for such
combinations, so they showed up as dangling links.  Verb
morphology is rendered separately by Particle Map, Clause
Structure, and Grammar.

Per-stem GLOSS lookup falls back through
`tibetan-lookup-word' (particle-stripping bilingual lookup).
Strict existence check guards MWU DETECTION;  loose gloss lookup
populates the final `(word . meaning)' cell."
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
               (_word-stripped (tibetan-strip-particles word))
               (found nil)
               (matched-len 1))

          (if (or (string-empty-p word) (string-match-p "^[།༎༏]+$" word))
              (setq i (+ i 1))

            ;; Greedy MWU matching — 4, 3, 2 syllable compounds.
            ;;
            ;; Reject any compound whose head OR tail syllable is a
            ;; case / converb particle.  Then check existence via the
            ;; STRICT `tibetan-vocab--mwu-exists-p' (exact-key
            ;; `gethash' across all consulted dictionaries) — not via
            ;; `tibetan-lookup-word', whose internal particle-
            ;; stripping fallback used to produce false-positive MWUs
            ;; like `rnams ngo so' (returned the `rnams' gloss after
            ;; stripping `so' + `ngo' both sentence-final particles).
            ;; See `tibetan-vocab--mwu-exists-p' for the seg-049
            ;; root-cause context.
            ;;
            ;; User-curated compounds with particle tails (uncommon
            ;; but possible — e.g. a Resources entry for a lexicalised
            ;; idiom) should be added to the Resources vocab file,
            ;; which takes priority in the strict lookup.
            (unless found
              (cl-loop for compound-len from 4 downto 2
                       until found
                       when (<= (+ i compound-len) num-words)
                       do
                       (let* ((syls-raw (cl-loop for j from i below (+ i compound-len)
                                                 collect (string-trim (nth j words))))
                              (compound-raw (mapconcat #'identity syls-raw "་")))
                         (unless (or (tibetan-extract-vocab--tail-is-particle-p
                                       compound-raw)
                                     (tibetan-extract-vocab--head-is-particle-p
                                      compound-raw)
                                     ;; Verb-tail guard: reject an
                                     ;; auto-sourced phrasal entry that
                                     ;; ends in a finite verb, so the
                                     ;; verb reaches clause analysis.
                                     ;; User-curated MWUs are EXEMPT.
                                     (and (tibetan-extract-vocab--tail-is-verb-p
                                           compound-raw)
                                          (not (tibetan-lookup-word-in-resources-vocab
                                                compound-raw))
                                          (not (tibetan-lookup-word-in-custom-vocab
                                                compound-raw))))
                           (when (and (fboundp 'tibetan-vocab--mwu-exists-p)
                                      (tibetan-vocab--mwu-exists-p compound-raw))
                             (let ((meaning (or (tibetan-lookup-word compound-raw)
                                                "[look up]")))
                               (push (cons compound-raw meaning) vocab)
                               (setq found t)
                               (setq matched-len compound-len)))))))

            ;; Single-word fallback when no compound matched.
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
Set `tibetan-skip-external-glossaries' to non-nil to skip loading.

As of the glossary-loader unification (2026-04) there is one canonical
bundled module — `tibetan-glossary-loader' — which `tibetan-cat.el'
already `require's at boot.  That module's `load-all-glossaries' is
idempotent (guards on `tibetan-glossaries-loaded'), so calling it
here is safe even though it has already been auto-called when the
loader module was required.  The legacy external-path fallback is
kept for users who install the package without the bundled data dir."
  (when (not (bound-and-true-p tibetan-skip-external-glossaries))
    (cond
     ;; Canonical path: the bundled loader.
     ((fboundp 'load-all-glossaries)
      (load-all-glossaries))
     ;; Legacy external path (pre-open-source installs).
     (t
      (let ((external-glossary (expand-file-name
                                "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el")))
        (when (file-exists-p external-glossary)
          (load-file external-glossary)))))))

;;;###autoload
(defun reload-all-glossaries ()
  "Reload all glossaries, forcing a fresh read from disk.
Uses the canonical `load-all-glossaries' with the FORCE flag, which
resets the idempotence guard and re-emits every bundled source."
  (interactive)
  (cond
   ;; Canonical path: force a fresh reload of the bundled glossaries.
   ((fboundp 'load-all-glossaries)
    (load-all-glossaries t)
    (message "Reloaded all glossaries"))
   ;; Legacy external path (pre-open-source installs).
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
  nil or \='compact\=  - Short one-line format: Tibetan *wylie* — short-meaning
  \='org-compact\=     - Org format with short meaning (for vocab section)
  \='org-detailed\=    - Org format with full meaning (for detailed section)
  \='full\=            - Plain text with full meaning (for classroom detailed)
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
