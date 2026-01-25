;;; tibetan-vocabulary-detailed.el --- Detailed dictionary-style vocabulary lookup -*- lexical-binding: t -*-

;;; Commentary:
;; Provides enhanced vocabulary lookup that returns detailed dictionary entries
;; with primary translation, detailed explanation, Sanskrit terms, and source info.
;;
;; Entry format:
;;   ((primary . "main translation")
;;    (detailed . "full detailed explanation with all meanings")
;;    (sanskrit . "Sanskrit term if available")
;;    (wylie . "Wylie transliteration")
;;    (source . "source glossary name")
;;    (compound-p . t/nil))
;;
;; Used by both C-c u i and C-c u A for consistent output.

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; DETAILED VOCABULARY CACHE
;; ============================================================================

(defvar tibetan-detailed-vocab-cache (make-hash-table :test 'equal)
  "Cache for detailed vocabulary entries.
Key: Tibetan or Wylie term
Value: plist with :primary :detailed :sanskrit :wylie :source")

;; ============================================================================
;; ENTRY PARSING - Extract structured info from raw glossary entries
;; ============================================================================

(defun tibetan-vocab--parse-entry (raw-entry)
  "Parse RAW-ENTRY string into structured format.
Returns plist with :primary :detailed :sanskrit."
  (when (and raw-entry (stringp raw-entry) (not (string-empty-p raw-entry)))
    (let ((primary nil)
          (detailed raw-entry)
          (sanskrit nil))

      ;; Extract Sanskrit term if present (common patterns)
      ;; Pattern: {Skt. term} or (Skt: term) or [Sanskrit: term]
      (when (string-match "{\\([^}]+\\)}" raw-entry)
        (let ((match (match-string 1 raw-entry)))
          (when (or (string-match-p "^[A-Za-z]" match)
                    (string-match-p "skt\\|Skt\\|SKT\\|sanskrit\\|Sanskrit" match))
            (setq sanskrit (replace-regexp-in-string "^[Ss]kt\\.?:?\\s-*" "" match)))))

      ;; Also check for Skt. or Sanskrit: patterns
      (unless sanskrit
        (when (string-match "[Ss]anskrit:?\\s-*\\([A-Za-z][a-z]*\\)" raw-entry)
          (setq sanskrit (match-string 1 raw-entry))))

      ;; Extract primary meaning (first part before semicolon, comma, or period)
      (let ((first-meaning raw-entry))
        ;; Remove leading numbers like "1) " or "1. "
        (setq first-meaning (replace-regexp-in-string "^[0-9]+[.):]\\s-*" "" first-meaning))
        ;; Take first meaning segment
        (when (string-match "^\\([^;.,]+\\)" first-meaning)
          (setq primary (string-trim (match-string 1 first-meaning))))
        ;; Clean up primary
        (when primary
          (setq primary (replace-regexp-in-string "\\s-+$" "" primary))
          ;; Remove "to " prefix for verbs if it makes it cleaner
          ;; (setq primary (replace-regexp-in-string "^to " "" primary))
          ))

      (list :primary (or primary detailed)
            :detailed detailed
            :sanskrit sanskrit))))

(defun tibetan-vocab--get-wylie (tibetan-word)
  "Get Wylie transliteration for TIBETAN-WORD."
  (when (and tibetan-word (string-match-p "^[ༀ-࿿]" tibetan-word))
    (condition-case nil
        (when (fboundp 'tibetan-to-wylie-fixed)
          (tibetan-to-wylie-fixed tibetan-word))
      (error nil))))

(defun tibetan-vocab--tibetan-from-wylie (wylie)
  "Get Tibetan script from WYLIE transliteration."
  (when (and wylie (string-match-p "^[a-z]" wylie))
    (condition-case nil
        (when (fboundp 'tibetan-wylie-to-tibetan)
          (tibetan-wylie-to-tibetan wylie))
      (error nil))))

;; ============================================================================
;; COMPREHENSIVE LOOKUP - Try all sources
;; ============================================================================

(defun tibetan-vocab-lookup-detailed (word)
  "Look up WORD and return detailed dictionary entry.
Tries: Resources vocab, custom vocab, bundled glossaries, DharmaMitra.
WORD can be Tibetan script or Wylie.
Returns plist with :primary :detailed :sanskrit :wylie :source, or nil."
  (when (and word (stringp word) (not (string-empty-p word)))
    ;; Check cache first
    (let ((cached (gethash word tibetan-detailed-vocab-cache)))
      (if cached
          cached
        ;; Not cached - do full lookup
        (let ((result nil)
              (wylie (if (string-match-p "^[ༀ-࿿]" word)
                         (tibetan-vocab--get-wylie word)
                       word))
              (tibetan (if (string-match-p "^[a-z]" word)
                           (tibetan-vocab--tibetan-from-wylie word)
                         word)))

          ;; Try Resources vocabulary first (highest priority)
          (unless result
            (when (and (boundp 'tibetan-current-resources-vocab)
                       tibetan-current-resources-vocab)
              (let ((entry (or (gethash tibetan tibetan-current-resources-vocab)
                               (and wylie (gethash wylie tibetan-current-resources-vocab)))))
                (when entry
                  (let ((parsed (tibetan-vocab--parse-entry entry)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit (plist-get parsed :sanskrit)
                                       :wylie wylie
                                       :source "Resources")))))))

          ;; Try custom vocabulary
          (unless result
            (when (and (boundp 'tibetan-current-custom-vocab)
                       tibetan-current-custom-vocab)
              (let ((entry (or (gethash tibetan tibetan-current-custom-vocab)
                               (and wylie (gethash wylie tibetan-current-custom-vocab)))))
                (when entry
                  (let ((parsed (tibetan-vocab--parse-entry entry)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit (plist-get parsed :sanskrit)
                                       :wylie wylie
                                       :source "Custom")))))))

          ;; Try bundled glossaries (Rangjung Yeshe, Hopkins, etc.)
          (unless result
            (when (and (boundp 'tibetan-comprehensive-vocabulary)
                       tibetan-comprehensive-vocabulary)
              (let ((entry (or (gethash tibetan tibetan-comprehensive-vocabulary)
                               (and wylie (gethash wylie tibetan-comprehensive-vocabulary)))))
                (when entry
                  (let ((parsed (tibetan-vocab--parse-entry entry)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit (plist-get parsed :sanskrit)
                                       :wylie wylie
                                       :source "Bundled")))))))

          ;; Try DharmaMitra as fallback
          (unless result
            (when (fboundp 'tibetan-lookup-word-in-dharmamitra)
              (let ((dm-result (tibetan-lookup-word-in-dharmamitra (or tibetan word))))
                (when dm-result
                  (let ((parsed (tibetan-vocab--parse-entry dm-result)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit nil
                                       :wylie wylie
                                       :source "DharmaMitra")))))))

          ;; Cache and return
          (when result
            (puthash word result tibetan-detailed-vocab-cache))
          result)))))

;; ============================================================================
;; COMPOUND-AWARE VOCABULARY EXTRACTION
;; ============================================================================

(defun tibetan-vocab-extract-detailed (tibetan-text)
  "Extract detailed vocabulary from TIBETAN-TEXT.
Returns list of plists, each with :tibetan :wylie :primary :detailed :sanskrit :source.
Handles compound detection and provides consistent format for C-c u i and C-c u A."
  (when (and tibetan-text (not (string-empty-p tibetan-text)))
    ;; Load vocabularies
    (when (fboundp 'tibetan-load-resources-vocab)
      (tibetan-load-resources-vocab))
    (when (fboundp 'tibetan-load-custom-vocab)
      (tibetan-load-custom-vocab))

    ;; Normalize text
    (setq tibetan-text (replace-regexp-in-string " " "་" tibetan-text))
    (setq tibetan-text (replace-regexp-in-string "།+" "།" tibetan-text))

    (let* ((syllables (split-string tibetan-text "་" t))
           (vocab-list '())
           (i 0)
           (seen (make-hash-table :test 'equal)))  ; Avoid duplicates

      (while (< i (length syllables))
        (let* ((syl (string-trim (nth i syllables)))
               (syl-clean (replace-regexp-in-string "[།༎༏]" "" syl))
               (next-syl (when (< (1+ i) (length syllables))
                           (replace-regexp-in-string "[།༎༏]" ""
                                                     (string-trim (nth (1+ i) syllables)))))
               (found nil))

          (unless (or (string-empty-p syl-clean)
                      (gethash syl-clean seen))

            ;; Try 2-syllable compound first
            (when next-syl
              (let* ((compound (concat syl-clean "་" next-syl))
                     (entry (tibetan-vocab-lookup-detailed compound)))
                (when entry
                  (puthash compound t seen)
                  (push (list :tibetan compound
                              :wylie (plist-get entry :wylie)
                              :primary (plist-get entry :primary)
                              :detailed (plist-get entry :detailed)
                              :sanskrit (plist-get entry :sanskrit)
                              :source (plist-get entry :source)
                              :compound-p t)
                        vocab-list)
                  (setq found t)
                  (setq i (1+ i)))))  ; Skip next syllable

            ;; Try single syllable
            (unless found
              (let ((entry (tibetan-vocab-lookup-detailed syl-clean)))
                (when entry
                  (puthash syl-clean t seen)
                  (push (list :tibetan syl-clean
                              :wylie (plist-get entry :wylie)
                              :primary (plist-get entry :primary)
                              :detailed (plist-get entry :detailed)
                              :sanskrit (plist-get entry :sanskrit)
                              :source (plist-get entry :source)
                              :compound-p nil)
                        vocab-list))
                ;; Even if not found, add placeholder
                (unless entry
                  (let ((wylie (tibetan-vocab--get-wylie syl-clean)))
                    (puthash syl-clean t seen)
                    (push (list :tibetan syl-clean
                                :wylie wylie
                                :primary "[not found]"
                                :detailed nil
                                :sanskrit nil
                                :source nil
                                :compound-p nil)
                          vocab-list))))))

          (setq i (1+ i))))

      (nreverse vocab-list))))

;; ============================================================================
;; FORMATTED OUTPUT - For display in analysis
;; ============================================================================

(defun tibetan-vocab-format-entry-short (entry)
  "Format ENTRY plist as short one-line summary.
Format: ཚིག /*wylie*/ — primary meaning"
  (let ((tibetan (plist-get entry :tibetan))
        (wylie (plist-get entry :wylie))
        (primary (plist-get entry :primary)))
    (format "%s /*%s*/ — %s"
            tibetan
            (or wylie "?")
            (or primary "[not found]"))))

(defun tibetan-vocab-format-entry-full (entry)
  "Format ENTRY plist as full dictionary entry.
Format:
  ཚིག /*wylie*/
    Primary: meaning
    Full: detailed explanation
    Sanskrit: term (if available)
    Source: glossary name"
  (let ((tibetan (plist-get entry :tibetan))
        (wylie (plist-get entry :wylie))
        (primary (plist-get entry :primary))
        (detailed (plist-get entry :detailed))
        (sanskrit (plist-get entry :sanskrit))
        (source (plist-get entry :source)))
    (concat
     (format "◆ %s" tibetan)
     (when wylie (format "  [%s]" wylie))
     "\n"
     (format "  %s\n" (or primary "[not found]"))
     (when (and detailed (not (equal detailed primary)))
       (format "  Full: %s\n"
               (if (> (length detailed) 200)
                   (concat (substring detailed 0 197) "...")
                 detailed)))
     (when sanskrit (format "  Sanskrit: %s\n" sanskrit))
     (when source (format "  Source: %s\n" source)))))

(defun tibetan-vocab-format-list-short (vocab-list)
  "Format VOCAB-LIST as short vocabulary section for analysis files."
  (mapconcat #'tibetan-vocab-format-entry-short vocab-list "\n"))

(defun tibetan-vocab-format-list-full (vocab-list)
  "Format VOCAB-LIST as full dictionary section."
  (mapconcat #'tibetan-vocab-format-entry-full vocab-list "\n"))

;; ============================================================================
;; INTEGRATION FUNCTION - For analysis generation
;; ============================================================================

(defun tibetan-generate-vocabulary-section (tibetan-text &optional full-p)
  "Generate vocabulary section for TIBETAN-TEXT.
If FULL-P is non-nil, include full detailed entries.
Returns formatted string for insertion in analysis."
  (let ((vocab-list (tibetan-vocab-extract-detailed tibetan-text)))
    (if vocab-list
        (if full-p
            (tibetan-vocab-format-list-full vocab-list)
          (tibetan-vocab-format-list-short vocab-list))
      "[No vocabulary extracted]")))

(provide 'tibetan-vocabulary-detailed)
;;; tibetan-vocabulary-detailed.el ends here
