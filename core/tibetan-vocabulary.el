;;; tibetan-vocabulary.el --- Vocabulary lookup with DharmaMitra fallback -*- lexical-binding: t -*-

;;; Commentary:
;; Provides vocabulary lookup with multiple sources:
;; 1. Local comprehensive glossaries (17,777 entries)
;; 2. DharmaMitra API fallback with caching
;;
;; Handles:
;; - Compound word detection
;; - Particle stripping
;; - Cached translations to avoid repeated API calls

;;; Code:

(require 'cl-lib)

;; Safe substring for multi-byte Tibetan text
(defun tibetan-vocab-safe-substring (str start &optional end)
  "Safely extract substring from STR between START and END.
Returns empty string if indices are out of range or invalid."
  (condition-case nil
      (let* ((len (length str))
             (s (max 0 (min start len)))
             (e (if end (max s (min end len)) len)))
        (if (and (<= 0 s) (<= s e) (<= e len))
            (substring str s e)
          ""))
    (error "")))

;; ============================================================================
;; DHARMAMITRA CACHE
;; ============================================================================

(defvar tibetan-dharmamitra-cache (make-hash-table :test 'equal)
  "Cache for DharmaMitra word translations to avoid repeated API calls.")

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
Tries local glossary first, then DharmaMitra fallback.
Returns meaning string or nil."
  (let ((meaning nil))
    ;; Try compound if prev-word provided
    (when prev-word
      (let* ((compound (concat prev-word "་" word))
             (compound-stripped (concat (tibetan-strip-particles prev-word) "་"
                                       (tibetan-strip-particles word))))
        ;; Try local glossary first
        (setq meaning (or (tibetan-lookup-word-in-local-glossary compound)
                         (tibetan-lookup-word-in-local-glossary compound-stripped)))
        ;; If not found, try DharmaMitra
        (unless meaning
          (setq meaning (tibetan-lookup-word-in-dharmamitra compound)))))

    ;; Try single word if compound not found
    (unless meaning
      ;; Try local glossary first
      (setq meaning (tibetan-lookup-word-in-local-glossary word))
      ;; If not found, try DharmaMitra
      (unless meaning
        (setq meaning (tibetan-lookup-word-in-dharmamitra word))))

    meaning))

;; ============================================================================
;; VOCABULARY EXTRACTION
;; ============================================================================

(defun tibetan-extract-vocabulary (tibetan-text)
  "Extract vocabulary from TIBETAN-TEXT with meanings.
Returns list of (word . meaning) pairs.
Handles compound detection and particle stripping automatically."
  (when tibetan-text
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
                ;; Try local glossary (raw first, then stripped)
                (setq meaning (or (tibetan-lookup-word-in-local-glossary compound-raw)
                                 (tibetan-lookup-word-in-local-glossary compound-stripped)))

                ;; If not found, try DharmaMitra for compound
                (unless meaning
                  (setq meaning (tibetan-lookup-word-in-dharmamitra compound-raw)))

                ;; If compound found, add to vocab and skip next word
                (when meaning
                  (setq found-compound t)
                  (push (cons (concat word "་" next) meaning) vocab)
                  (setq i (+ i 2))))

              ;; If no compound, lookup single word
              (unless found-compound
                ;; Try local glossary
                (setq meaning (or (tibetan-lookup-word-in-local-glossary word)
                                 (and (not (equal word word-stripped))
                                      (tibetan-lookup-word-in-local-glossary word-stripped))))

                ;; If not found, try DharmaMitra
                (unless meaning
                  (setq meaning (tibetan-lookup-word-in-dharmamitra word)))

                ;; Add to vocab (even if meaning is nil, to show [look up] message)
                (push (cons word (or meaning "[look up]")) vocab)
                (setq i (+ i 1)))))))

      (nreverse vocab))))

;; ============================================================================
;; GLOSSARY LOADING
;; ============================================================================

(defun reload-all-glossaries ()
  "Reload all glossaries including Hopkins, Bialek, and others."
  (interactive)
  (if (fboundp 'load-all-glossaries)
      (progn
        (load-all-glossaries)
        (message "✓ Reloaded all glossaries"))
    (let ((glossary-file (expand-file-name
                          "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el")))
      (if (file-exists-p glossary-file)
          (progn
            (message "Loading glossary system...")
            (load-file glossary-file)
            (message "✓ Glossary system loaded"))
        (message "⚠ Glossary file not found: %s" glossary-file)))))

(provide 'tibetan-vocabulary)
;;; tibetan-vocabulary.el ends here
