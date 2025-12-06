;;; cat-parser.el --- Enhanced Tibetan text parser -*- lexical-binding: t -*-

;;; Commentary:
;; Enhanced parsing for Tibetan text that:
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

(require 'cl-lib)
(require 'json)
(require 'cat-utils)

;; ============================================================================
;; DICTIONARY DATA
;; ============================================================================

(defvar cat-parser-compounds-dict nil
  "Hash table of Tibetan compound terms.
Key: Tibetan text, Value: alist with wylie, english, sanskrit, category.")

(defvar cat-parser-proper-nouns-dict nil
  "Hash table of Tibetan proper nouns.
Key: Tibetan text, Value: alist with wylie, english, sanskrit, category.")

(defvar cat-parser-data-dir nil
  "Directory containing parser data files.")

;; ============================================================================
;; DICTIONARY LOADING
;; ============================================================================

(defun cat-parser-set-data-dir (dir)
  "Set the parser data directory to DIR."
  (setq cat-parser-data-dir dir))

(defun cat-parser-load-json-dict (filename)
  "Load JSON dictionary from FILENAME, return as hash table."
  (when cat-parser-data-dir
    (let ((file-path (expand-file-name filename cat-parser-data-dir)))
      (when (file-exists-p file-path)
        (condition-case err
            (let* ((json-object-type 'alist)
                   (json-array-type 'list)
                   (json-key-type 'symbol)
                   (json-data (json-read-file file-path))
                   (hash (make-hash-table :test 'equal)))
              (dolist (entry json-data)
                (let ((key (car entry))
                      (value (cdr entry)))
                  (puthash key value hash)))
              hash)
          (error
           (message "Error loading %s: %s" filename (error-message-string err))
           nil))))))

(defun cat-parser-load-dictionaries ()
  "Load compound and proper noun dictionaries from JSON files."
  (unless cat-parser-compounds-dict
    (setq cat-parser-compounds-dict
          (cat-parser-load-json-dict "dictionaries/compounds.json"))
    (when cat-parser-compounds-dict
      (message "CAT Parser: Loaded %d compound terms"
               (hash-table-count cat-parser-compounds-dict))))

  (unless cat-parser-proper-nouns-dict
    (setq cat-parser-proper-nouns-dict
          (cat-parser-load-json-dict "dictionaries/proper_nouns.json"))
    (when cat-parser-proper-nouns-dict
      (message "CAT Parser: Loaded %d proper nouns"
               (hash-table-count cat-parser-proper-nouns-dict)))))

(defun cat-parser-reload-dictionaries ()
  "Force reload of dictionaries."
  (interactive)
  (setq cat-parser-compounds-dict nil)
  (setq cat-parser-proper-nouns-dict nil)
  (cat-parser-load-dictionaries))

;; ============================================================================
;; MULTI-WORD UNIT DETECTION
;; ============================================================================

(defun cat-parser-find-multiword-units (words)
  "Find multi-word compound/proper noun units in WORDS list.
Uses longest-match-first strategy.
Returns list of (start-index end-index form data) tuples."
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
                        ;; Check comprehensive vocabulary first
                        (comp-vocab (when (boundp 'tibetan-comprehensive-vocabulary)
                                     (gethash joined tibetan-comprehensive-vocabulary)))
                        ;; Then check JSON dictionaries
                        (compound (when cat-parser-compounds-dict
                                   (gethash joined cat-parser-compounds-dict)))
                        (proper-noun (when cat-parser-proper-nouns-dict
                                      (gethash joined cat-parser-proper-nouns-dict))))
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

(defun cat-parser-get-claimed-indices (multiword-units)
  "Get set of syllable indices that are part of compounds.
MULTIWORD-UNITS is list from `cat-parser-find-multiword-units'.
Returns hash table for fast lookup."
  (let ((claimed (make-hash-table :test 'equal)))
    (dolist (unit multiword-units)
      (cl-loop for idx from (nth 0 unit) below (nth 1 unit)
               do (puthash idx t claimed)))
    claimed))

;; ============================================================================
;; COMPOUND-AWARE SEGMENTATION
;; ============================================================================

(defun cat-parser-build-segments (words multiword-units)
  "Build segmentation list showing compounds as units.
WORDS is the raw syllable list, MULTIWORD-UNITS are recognized compounds.
Returns list of strings for display."
  (let ((segments '())
        (i 0)
        (claimed-indices (cat-parser-get-claimed-indices multiword-units)))

    ;; Build segment list
    (while (< i (length words))
      (if (gethash i claimed-indices)
          ;; Part of compound - find which one and add it
          (let ((unit (cl-find-if (lambda (u)
                                   (and (>= i (nth 0 u))
                                        (< i (nth 1 u))))
                                 multiword-units)))
            (when (and unit (= i (nth 0 unit)))  ; Only add once at start
              (push (nth 2 unit) segments))
            ;; Skip to end of compound
            (setq i (nth 1 unit)))
        ;; Regular word
        (push (nth i words) segments)
        (setq i (1+ i))))

    (nreverse segments)))

;; ============================================================================
;; MAIN PARSING INTERFACE
;; ============================================================================

(cl-defstruct cat-parse-result
  "Structure holding parsing results."
  words            ; List of raw syllables
  multiword-units  ; List of (start end form data) tuples
  segments         ; List of display segments (compounds as single units)
  claimed-indices) ; Hash table of indices in compounds

(defun cat-parser-parse (text)
  "Parse Tibetan TEXT with compound recognition.
Returns a `cat-parse-result' struct."
  ;; Ensure dictionaries are loaded
  (cat-parser-load-dictionaries)

  (let* ((words (cat-segment-text text))
         (multiword-units (cat-parser-find-multiword-units words))
         (claimed-indices (cat-parser-get-claimed-indices multiword-units))
         (segments (cat-parser-build-segments words multiword-units)))

    (make-cat-parse-result
     :words words
     :multiword-units multiword-units
     :segments segments
     :claimed-indices claimed-indices)))

;; ============================================================================
;; WORD ANALYSIS
;; ============================================================================

(defun cat-parser-analyze-word (word prev-word next-word)
  "Analyze single tsheg-delimited WORD with context.
PREV-WORD and NEXT-WORD provide context.
Returns alist with analysis data."
  (let ((result nil))
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
                    (function . ,(cat-parser-particle-function word)))))

     ;; Default: just a word
     (t
      (setq result `((type . "word")
                    (form . ,word)))))

    result))

(defun cat-parser-particle-function (particle)
  "Return function description for standalone PARTICLE."
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
;; VERB EXTRACTION (COMPOUND-AWARE)
;; ============================================================================

(defun cat-parser-extract-verbs (parse-result)
  "Extract verbs from PARSE-RESULT, excluding compound parts.
Returns list of verb entries from the verb dictionary."
  (when (fboundp 'tibetan-verb-lookup)
    (let ((verbs '())
          (words (cat-parse-result-words parse-result))
          (claimed (cat-parse-result-claimed-indices parse-result))
          (multiword-units (cat-parse-result-multiword-units parse-result)))

      (cl-loop for idx from 0 below (length words)
               do (let* ((syl (nth idx words))
                        (syl-clean (string-trim syl))
                        ;; Check if in multi-word compound (length > 1)
                        (in-multiword
                         (and (gethash idx claimed)
                              (cl-some (lambda (unit)
                                        (and (>= idx (nth 0 unit))
                                             (< idx (nth 1 unit))
                                             (> (- (nth 1 unit) (nth 0 unit)) 1)))
                                      multiword-units))))
                   (unless in-multiword
                     (when (not (string-empty-p syl-clean))
                       (let ((verb-entry (tibetan-verb-lookup syl-clean)))
                         (when verb-entry
                           (let ((lemma (alist-get 'lemma verb-entry)))
                             (unless (cl-find lemma verbs
                                            :key (lambda (v) (alist-get 'lemma v))
                                            :test 'string=)
                               (push verb-entry verbs)))))))))
      (nreverse verbs))))

;; ============================================================================
;; LOOKUP HELPERS
;; ============================================================================

(defun cat-parser-lookup-compound (text)
  "Look up TEXT in compound dictionary."
  (when cat-parser-compounds-dict
    (gethash text cat-parser-compounds-dict)))

(defun cat-parser-lookup-proper-noun (text)
  "Look up TEXT in proper noun dictionary."
  (when cat-parser-proper-nouns-dict
    (gethash text cat-parser-proper-nouns-dict)))

(defun cat-parser-lookup-segment (segment parse-result)
  "Look up meaning for SEGMENT using PARSE-RESULT context.
Returns meaning string or nil."
  (or
   ;; Check if it's a compound
   (when-let ((unit (cl-find-if (lambda (u) (string= (nth 2 u) segment))
                                (cat-parse-result-multiword-units parse-result))))
     (alist-get 'english (nth 3 unit)))
   ;; Otherwise lookup as regular word
   (cat-lookup-word segment)
   ;; Try with particle stripped
   (cat-lookup-with-particle-strip segment)))

;; ============================================================================
;; FORMATTING
;; ============================================================================

(defun cat-parser-format-multiword-unit (unit)
  "Format UNIT data for display.
UNIT is (start-index end-index form data)."
  (let* ((form (nth 2 unit))
         (data (nth 3 unit))
         (wylie (alist-get 'wylie data))
         (english (alist-get 'english data))
         (sanskrit (alist-get 'sanskrit data))
         (category (alist-get 'category data)))
    (concat form " [" (or wylie "?") "]"
            "\n  TYPE: " (or category "Vocabulary")
            "\n  MEANING: " (or english "?")
            (when sanskrit (concat "\n  SANSKRIT: " sanskrit)))))

(provide 'cat-parser)
;;; cat-parser.el ends here
