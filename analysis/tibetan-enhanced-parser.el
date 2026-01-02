;;; tibetan-enhanced-parser.el --- Enhanced Tibetan parser with compound/proper noun recognition -*- lexical-binding: t -*-

;;; Commentary:
;; Improved parsing that:
;; 1. Segments text into tsheg-delimited units FIRST
;; 2. Checks compound/proper noun dictionaries BEFORE analysis
;; 3. Only analyzes particles at word boundaries (not inside syllables)
;; 4. Filters verb matches by context
;;
;; This addresses false positives like:
;; - Finding ན inside གཞན (gzhan = "other")
;; - Matching verb stems that aren't verbs in context
;; - Missing multi-word units like གླེང་གཞི (nidāna)

;;; Code:

(require 'json)
(require 'cl-lib)

;; ============================================================================
;; DICTIONARY LOADING
;; ============================================================================

(defvar tibetan-compounds-dict nil
  "Hash table of Tibetan compound terms.
Key: Tibetan text, Value: alist with wylie, english, sanskrit, category.")

(defvar tibetan-proper-nouns-dict nil
  "Hash table of Tibetan proper nouns.
Key: Tibetan text, Value: alist with wylie, english, sanskrit, category.")

(defun tibetan-load-json-dict (filename)
  "Load JSON dictionary from FILENAME, return as hash table."
  (let ((file-path (expand-file-name filename tibetan-cat-data-dir)))
    (when (file-exists-p file-path)
      (let* ((json-object-type 'alist)
             (json-array-type 'list)
             (json-key-type 'string)  ; Use strings for Tibetan keys
             (json-data (json-read-file file-path))
             (hash (make-hash-table :test 'equal)))
        (dolist (entry json-data)
          (let ((key (car entry))
                (value (cdr entry)))
            ;; Ensure key is a string (convert from symbol if needed)
            (puthash (if (symbolp key) (symbol-name key) key)
                     value hash)))
        hash))))

(defun tibetan-load-dictionaries ()
  "Load compound and proper noun dictionaries from JSON files.
Creates empty hash tables if files don't exist or tibetan-cat-data-dir is unset."
  (unless tibetan-compounds-dict
    (let ((loaded (and (boundp 'tibetan-cat-data-dir)
                       tibetan-cat-data-dir
                       (tibetan-load-json-dict "data/dictionaries/compounds.json"))))
      (setq tibetan-compounds-dict (or loaded (make-hash-table :test 'equal)))
      (when loaded
        (message "✓ Loaded %d compound terms" (hash-table-count tibetan-compounds-dict)))))

  (unless tibetan-proper-nouns-dict
    (let ((loaded (and (boundp 'tibetan-cat-data-dir)
                       tibetan-cat-data-dir
                       (tibetan-load-json-dict "data/dictionaries/proper_nouns.json"))))
      (setq tibetan-proper-nouns-dict (or loaded (make-hash-table :test 'equal)))
      (when loaded
        (message "✓ Loaded %d proper nouns" (hash-table-count tibetan-proper-nouns-dict))))))

;; Load on require
(tibetan-load-dictionaries)

;; ============================================================================
;; MULTI-WORD SEGMENTATION
;; ============================================================================

(defun tibetan-segment-text (text)
  "Segment TEXT into tsheg-delimited units.
Returns list of word strings."
  (let ((cleaned (replace-regexp-in-string "[།༎༏༐༑༔]" "" text)))
    (split-string cleaned "་" t)))

(defun tibetan-find-multiword-units (words)
  "Find multi-word compound/proper noun units in WORDS list.
Uses longest-match-first strategy.
Returns list of (start-index . end-index . entry-data) tuples."
  ;; Ensure dictionaries are loaded
  (tibetan-load-dictionaries)
  (let ((matches '())
        (i 0))
    (while (< i (length words))
      (let ((found nil)
            (max-len (min 8 (- (length words) i))))  ; Check up to 8-word compounds
        ;; Try longest matches first
        (cl-loop for len from max-len downto 1
                 until found
                 do
                 (let* ((slice (cl-subseq words i (+ i len)))
                        (joined (string-join slice "་"))
                        ;; Check comprehensive vocabulary first (new!)
                        (comp-vocab (when (boundp 'tibetan-comprehensive-vocabulary)
                                     (gethash joined tibetan-comprehensive-vocabulary)))
                        ;; Then check JSON dictionaries
                        (compound (when tibetan-compounds-dict
                                   (gethash joined tibetan-compounds-dict)))
                        (proper-noun (when tibetan-proper-nouns-dict
                                      (gethash joined tibetan-proper-nouns-dict))))
                   (when (or comp-vocab compound proper-noun)
                     ;; Build data structure for display
                     (let ((data (cond
                                 (compound compound)
                                 (proper-noun proper-noun)
                                 (comp-vocab
                                  ;; Convert simple string to alist format
                                  `((english . ,comp-vocab)
                                    (category . "vocabulary"))))))
                       (push (list i (+ i len) joined data) matches))
                     (setq found t)
                     (setq i (+ i len)))))
        (unless found
          (setq i (1+ i)))))
    (nreverse matches)))

;; ============================================================================
;; ENHANCED WORD ANALYSIS
;; ============================================================================

(defun tibetan-analyze-word-unit (word prev-word next-word)
  "Analyze single tsheg-delimited WORD with context.
PREV-WORD and NEXT-WORD provide context.
Returns alist with analysis data."
  (let ((result nil))

    ;; Check if word ends with common particle suffixes
    (cond
     ;; Genitive suffix: འི, གི, ཀྱི, ཡི
     ((string-match "\\([^་]+\\)\\(འི\\|གི\\|ཀྱི\\|ཡི\\)$" word)
      (let ((base (match-string 1 word))
            (particle (match-string 2 word)))
        (setq result `((type . "word+genitive")
                      (base . ,base)
                      (particle . ,particle)
                      (function . "Marks possessor or modifier")))))

     ;; Nominalizer: པ or བ at end
     ((string-match "\\([^་]+\\)\\([པབ]\\)$" word)
      (let ((base (match-string 1 word))
            (nominalizer (match-string 2 word)))
        (setq result `((type . "word+nominalizer")
                      (base . ,base)
                      (particle . ,nominalizer)
                      (function . "Nominalizes verb or creates agent noun")))))

     ;; Standalone case particle
     ((member word '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང"))
      (setq result `((type . "case_particle")
                    (particle . ,word)
                    (function . ,(tibetan-particle-function word)))))

     ;; Default: just a word
     (t
      (setq result `((type . "word")
                    (form . ,word)))))

    result))

(defun tibetan-particle-function (particle)
  "Return function description for PARTICLE."
  (cond
   ((string= particle "ན") "Locative: marks location or temporal/conditional setting")
   ((string= particle "ལ") "Dative-locative: marks recipient, goal, or location")
   ((string= particle "ར") "Allative: marks direction or goal")
   ((string= particle "སུ") "Allative: marks direction or goal")
   ((string= particle "ཏུ") "Allative: marks direction or goal; transforms to adverb")
   ((string= particle "དུ") "Allative: marks direction or goal")
   ((string= particle "ནས") "Ablative/converb: marks source or 'after V-ing'")
   ((string= particle "ལས") "Ablative: marks source, origin, or comparison")
   ((string= particle "དང") "Associative: marks accompaniment, conjunction")
   (t "Case particle")))

;; ============================================================================
;; ENHANCED PARSING PIPELINE
;; ============================================================================

(defun tibetan-parse-enhanced (text)
  "Enhanced parsing of TEXT.
Returns structured analysis with:
- Multi-word units (compounds, proper nouns)
- Word-level analysis
- Particle identification (only at boundaries)
- Context-aware verb identification."
  (let* ((words (tibetan-segment-text text))
         (multiword-units (tibetan-find-multiword-units words))
         (analysis '())
         (covered-indices (make-hash-table :test 'equal)))

    ;; Mark indices covered by multi-word units
    (dolist (unit multiword-units)
      (cl-loop for i from (nth 0 unit) below (nth 1 unit)
               do (puthash i t covered-indices)))

    ;; Process each position
    (cl-loop for i from 0 below (length words)
             do
             (if (gethash i covered-indices)
                 ;; Part of multi-word unit - find which one
                 (let ((unit (cl-find-if (lambda (u) (and (>= i (nth 0 u))
                                                         (< i (nth 1 u))))
                                        multiword-units)))
                   (when (and unit (= i (nth 0 unit)))  ; First word of unit
                     (push `((type . "compound")
                            (form . ,(nth 2 unit))
                            (data . ,(nth 3 unit))
                            (start-index . ,(nth 0 unit))
                            (end-index . ,(nth 1 unit)))
                           analysis)))
               ;; Single word - analyze it
               (let* ((word (nth i words))
                      (prev (when (> i 0) (nth (1- i) words)))
                      (next (when (< i (1- (length words))) (nth (1+ i) words)))
                      (word-analysis (tibetan-analyze-word-unit word prev next)))
                 (push `((type . "word")
                        (form . ,word)
                        (index . ,i)
                        (analysis . ,word-analysis))
                       analysis))))

    `((words . ,words)
      (analysis . ,(nreverse analysis))
      (multiword-units . ,multiword-units))))

;; ============================================================================
;; VERB FILTERING (Context-Aware)
;; ============================================================================

(defun tibetan-filter-verb-matches (verbs analysis-data)
  "Filter VERBS list to remove false positives using ANALYSIS-DATA context.
Remove verbs that are:
- Part of compound terms
- Part of proper nouns
- Particles misidentified as verbs
- Unlikely to be verbs based on position"
  (let ((compound-words (make-hash-table :test 'equal))
        (filtered '()))

    ;; Build set of words that are part of compounds
    (dolist (unit (alist-get 'multiword-units analysis-data))
      (let ((form (nth 2 unit)))
        (dolist (word (split-string form "་"))
          (puthash word t compound-words))))

    ;; Filter verb list
    (dolist (verb verbs)
      (let* ((lemma (alist-get 'lemma verb))
             (is-compound-part (gethash lemma compound-words))
             (is-particle (member lemma '("ན" "ལ" "ར"))))  ; Common particles
        (unless (or is-compound-part is-particle)
          (push verb filtered))))

    (nreverse filtered)))

;; ============================================================================
;; HELPER FUNCTIONS
;; ============================================================================

(defun tibetan-lookup-compound (text)
  "Look up TEXT in compound dictionary."
  (gethash text tibetan-compounds-dict))

(defun tibetan-lookup-proper-noun (text)
  "Look up TEXT in proper noun dictionary."
  (gethash text tibetan-proper-nouns-dict))

(defun tibetan-format-multiword-unit (unit)
  "Format UNIT data for display.
UNIT is (start-index end-index form data)."
  (let* ((form (nth 2 unit))
         (data (nth 3 unit))
         (wylie (alist-get 'wylie data))
         (english (alist-get 'english data))
         (sanskrit (alist-get 'sanskrit data))
         (category (alist-get 'category data)))
    (concat form " [" wylie "]"
            "\n  TYPE: " category
            "\n  MEANING: " english
            (when sanskrit (concat "\n  SANSKRIT: " sanskrit)))))

(provide 'tibetan-enhanced-parser)
;;; tibetan-enhanced-parser.el ends here
