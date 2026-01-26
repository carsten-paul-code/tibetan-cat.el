;;; tibetan-translation-engine.el --- CAT-suggested translation engine -*- lexical-binding: t -*-

;;; Commentary:
;; Generates CAT-suggested translations by combining:
;; - Vocabulary glosses from comprehensive dictionary
;; - Grammatical structure from particle analysis
;; - Verb case frames for argument ordering
;;
;; This produces a "scholar's rough draft" - not polished but useful
;; for understanding the grammatical structure.

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; COMMON TIBETAN CONSTRUCTIONS
;; ============================================================================

(defvar tibetan-cat-constructions
  '(;; Temporal constructions
    ("པའི་ཚེ" . "at the time when ... %s")
    ("བའི་ཚེ" . "at the time when ... %s")
    ("པའི་དུས" . "at the time when ... %s")
    ("བའི་དུས" . "at the time when ... %s")
    ("ན" . "when %s")
    ("ནས" . "after %s-ing / from %s")
    ("ཏེ" . "having %s-ed, ...")
    ;; Locative
    ("དུ" . "in/to %s")
    ("ལ" . "to/for %s")
    ("ར" . "to/for %s")
    ;; Genitive
    ("གི" . "%s's")
    ("གྱི" . "%s's")
    ("ཀྱི" . "%s's")
    ("འི" . "%s's")
    ;; Ergative/Instrumental
    ("གིས" . "by %s")
    ("ཀྱིས" . "by %s")
    ("ས" . "by %s"))
  "Common Tibetan grammatical constructions and their English patterns.
%s is replaced with the relevant noun or verb phrase.")

;; ============================================================================
;; WORD ORDER MAPPING
;; ============================================================================

(defvar tibetan-cat-translation-word-order
  '((Erg-Abs . (AGENT PATIENT VERB))
    (Erg-Abs-Dat . (AGENT PATIENT GOAL VERB))
    (Abs . (SUBJECT VERB))
    (Abs-Loc . (SUBJECT LOCATION VERB))
    (Abs-Dat . (SUBJECT GOAL VERB))
    (? . (TOPIC VERB)))
  "Mapping of Tibetan case frames to English word order.
Tibetan is SOV, English is SVO, so we reorder arguments.")

;; ============================================================================
;; ARGUMENT EXTRACTION
;; ============================================================================

(defun tibetan-cat--get-arguments-from-structure (structure-text)
  "Parse STRUCTURE-TEXT from analysis to extract arguments.
Returns alist of (role . (form . english))."
  (let ((args '())
        (lines (split-string structure-text "\n" t)))
    (dolist (line lines)
      (cond
       ;; PREDICATE line
       ((string-match "PREDICATE: \\([^ ]+\\)" line)
        (let ((verb (match-string 1 line))
              (meaning nil))
          (when (string-match "\"\\([^\"]+\\)\"" line)
            (setq meaning (match-string 1 line)))
          (push (list 'VERB verb meaning) args)))
       ;; Argument lines (AGENT, PATIENT, etc.)
       ((string-match "^  - \\([A-Z]+\\): \\([^ ]+\\)" line)
        (let ((role (intern (match-string 1 line)))
              (form (match-string 2 line))
              (english nil))
          (when (string-match "\"\\([^\"]+\\)\"" line)
            (setq english (match-string 1 line)))
          (push (list role form english) args)))))
    (nreverse args)))

;; ============================================================================
;; TRANSLATION GENERATION
;; ============================================================================

(defun tibetan-cat--gloss-word (tibetan-word &optional multiword-units)
  "Get English gloss for TIBETAN-WORD.
Checks MULTIWORD-UNITS first, then vocabulary.
Returns nil for empty or nil input."
  (when (and tibetan-word (stringp tibetan-word) (not (string-empty-p tibetan-word)))
    (let ((gloss nil))
      ;; Check multiword units
      (when multiword-units
      (dolist (unit multiword-units)
        (when (string= (nth 2 unit) tibetan-word)
          (let ((data (nth 3 unit)))
            (setq gloss (alist-get 'english data))))))
    ;; Check vocabulary
    (unless gloss
      (when (and (boundp 'tibetan-comprehensive-vocabulary)
                 tibetan-comprehensive-vocabulary)
        (setq gloss (gethash tibetan-word tibetan-comprehensive-vocabulary))))
    ;; Try tibetan-lookup-word
    (unless gloss
      (when (fboundp 'tibetan-lookup-word)
        (setq gloss (tibetan-lookup-word tibetan-word))))
    ;; Clean up gloss
    (when gloss
      (setq gloss (string-trim gloss))
      ;; Take first meaning if multiple
      (when (string-match "^\\([^;,]+\\)" gloss)
        (setq gloss (match-string 1 gloss)))
      (setq gloss (string-trim gloss)))
    gloss)))

(defun tibetan-cat--build-verb-phrase (verb-form verb-meaning verb-info)
  "Build English verb phrase from VERB-FORM, VERB-MEANING, and VERB-INFO."
  (let ((base (or verb-meaning
                  (tibetan-cat--gloss-word verb-form)
                  verb-form)))
    ;; Clean up verb form
    (setq base (replace-regexp-in-string "^to " "" base))
    ;; Check for past tense markers in original text
    ;; (For now, just return the base form)
    base))

(defun tibetan-cat--build-noun-phrase (form english role marker)
  "Build English noun phrase from FORM, ENGLISH, ROLE, and MARKER."
  (let ((base (or english
                  (tibetan-cat--gloss-word form)
                  (format "[%s]" form))))
    ;; Add role-appropriate preposition
    (cond
     ((eq role 'AGENT) base)
     ((eq role 'PATIENT) base)
     ((eq role 'GOAL) (format "to %s" base))
     ((eq role 'SOURCE) (format "from %s" base))
     ((eq role 'LOCATION) (format "in %s" base))
     ((eq role 'ALLATIVE) (format "in %s" base))
     ((eq role 'INSTRUMENT) (format "by %s" base))
     ((eq role 'BENEFICIARY) (format "for %s" base))
     ((eq role 'TOPIC) base)
     (t base))))

;; ============================================================================
;; SENTENCE-INITIAL PARTICLES
;; ============================================================================

(defvar tibetan-cat-sentence-particles
  '(("ཡང" . "Again, ")
    ("དེ་ནས" . "Then, ")
    ("དེའི་ཚེ" . "At that time, ")
    ("འདི་ལྟར" . "Thus, ")
    ("གང་གི་ཚེ" . "When ")
    ("ཇི་ལྟར" . "Just as "))
  "Sentence-initial particles and their English translations.")

(defun tibetan-cat-generate-translation (tibetan-text &optional parsed verbs)
  "Generate CAT-suggested translation for TIBETAN-TEXT.
Uses PARSED analysis and VERBS if provided, otherwise generates them.
Returns a string with the suggested translation."
  ;; Guard for nil/empty input
  (if (or (null tibetan-text) (string-empty-p tibetan-text))
      ""  ; Return empty string for empty input
    ;; Else: generate translation
    (progn
      ;; Ensure vocabulary is loaded
      (when (fboundp 'tibetan-analysis--ensure-vocabulary)
        (tibetan-analysis--ensure-vocabulary))

      ;; Get parsed data if not provided
      (unless parsed
        (when (fboundp 'tibetan-parse-enhanced)
          (setq parsed (tibetan-parse-enhanced tibetan-text))))

      (let* ((words (alist-get 'words parsed))
         (multiword-units (alist-get 'multiword-units parsed))
         ;; Get verbs if not provided
         (verbs (or verbs
                    (when (fboundp 'tibetan-extract-verbs-compound-aware)
                      (tibetan-extract-verbs-compound-aware tibetan-text words multiword-units))))
         ;; Get argument analysis
         (args-by-verb '())
         (translation-parts '()))

    ;; Analyze arguments for each verb
    (dolist (verb verbs)
      (when (and verb (listp verb) (consp (car verb)))
        (let* ((lemma (alist-get 'lemma verb))
               (meaning (alist-get 'meaning verb))
               (frame (or (alist-get 'case_frame verb) "?"))
               (trans (alist-get 'transitivity verb))
               (arg-analysis (when (fboundp 'tibetan-analyze-arguments)
                               (tibetan-analyze-arguments verb multiword-units words)))
               (clause-parts '())
               (agent nil)
               (patient nil)
               (goal nil)
               (other-args '()))

          ;; Categorize arguments
          (dolist (arg arg-analysis)
            (let ((role (alist-get 'role arg))
                  (form (alist-get 'form arg))
                  (english (alist-get 'english arg))
                  (marker (alist-get 'marker arg)))
              (cond
               ((string= role "AGENT") (setq agent (list form english marker)))
               ((string= role "PATIENT") (setq patient (list form english marker)))
               ((string= role "GOAL") (setq goal (list form english marker)))
               (t (push (list role form english marker) other-args)))))

          ;; Build English clause in SVO order
          ;; Agent/Subject first
          (when agent
            (push (tibetan-cat--build-noun-phrase
                   (nth 0 agent) (nth 1 agent) 'AGENT (nth 2 agent))
                  clause-parts))

          ;; Verb
          (push (tibetan-cat--build-verb-phrase lemma meaning verb)
                clause-parts)

          ;; Patient/Object
          (when patient
            (push (tibetan-cat--build-noun-phrase
                   (nth 0 patient) (nth 1 patient) 'PATIENT (nth 2 patient))
                  clause-parts))

          ;; Goal/Indirect object
          (when goal
            (push (tibetan-cat--build-noun-phrase
                   (nth 0 goal) (nth 1 goal) 'GOAL (nth 2 goal))
                  clause-parts))

          ;; Other arguments
          (dolist (arg (nreverse other-args))
            (push (tibetan-cat--build-noun-phrase
                   (nth 1 arg) (nth 2 arg) (intern (nth 0 arg)) (nth 3 arg))
                  clause-parts))

          ;; Join parts into clause
          (when clause-parts
            (push (string-join (nreverse clause-parts) " ") translation-parts)))))

    ;; If no verbs found or translation is incomplete, build structured translation
    (unless translation-parts
      (setq translation-parts
            (list (tibetan-cat--build-structured-translation
                   tibetan-text words multiword-units))))

      ;; Join clauses
      (if translation-parts
          (string-join (nreverse translation-parts) "; ")
        "[Unable to generate translation]")))))

;; ============================================================================
;; STRUCTURED TRANSLATION BUILDER
;; ============================================================================

(defun tibetan-cat--build-structured-translation (tibetan-text words multiword-units)
  "Build a structured English translation from TIBETAN-TEXT.
Uses WORDS and MULTIWORD-UNITS for vocabulary lookup.
Analyzes grammatical structure to produce proper English word order."
  (let ((segments (when (fboundp 'tibetan-build-compound-aware-segments)
                    (tibetan-build-compound-aware-segments words multiword-units)))
        (bialek (when (fboundp 'tibetan-analyze-grammar-bialek)
                  (tibetan-analyze-grammar-bialek tibetan-text)))
        (sentence-parts '())
        (subject nil)
        (location nil)
        (verb-phrase nil)
        (temporal-clause nil)
        (topic nil)
        (sentence-initial nil))

    ;; Check for sentence-initial particles
    (dolist (particle-pair tibetan-cat-sentence-particles)
      (when (string-match-p (concat "^" (car particle-pair)) tibetan-text)
        (setq sentence-initial (cdr particle-pair))))

    ;; Analyze grammatical markers to identify sentence components
    (dolist (gram bialek)
      (let* ((particle (nth 0 gram))
             (word (nth 1 gram))
             (gram-type (nth 2 gram))
             (word-gloss (tibetan-cat--gloss-word
                          (replace-regexp-in-string particle "$" "" word))))
        (cond
         ;; Terminative/Allative (དུ/ལ/ར) - location or goal
         ((string-match-p "TERMINATIVE\\|ALLATIVE\\|DATIVE" gram-type)
          (let ((np (tibetan-cat--gloss-word
                     (replace-regexp-in-string "[དལར]$" "" word))))
            (setq location (format "in %s" (or np word)))))

         ;; Genitive with temporal marker (པའི་ཚེ, etc.)
         ((and (string-match-p "GENITIVE" gram-type)
               (string-match-p "ཚེ\\|དུས" tibetan-text))
          ;; This is part of a temporal clause
          (setq temporal-clause t))

         ;; Ergative - agent/subject
         ((string-match-p "ERGATIVE" gram-type)
          (let ((np (tibetan-cat--gloss-word
                     (replace-regexp-in-string "[གཀས]\\(ིས\\)?$" "" word))))
            (setq subject (or np word)))))))

    ;; Get verb and meaning
    (let ((verb-info (when (fboundp 'tibetan-extract-verbs-compound-aware)
                       (car (tibetan-extract-verbs-compound-aware
                             tibetan-text words multiword-units)))))
      (when (and verb-info (listp verb-info) (consp (car verb-info)))
        (let ((meaning (alist-get 'meaning verb-info))
              (lemma (alist-get 'lemma verb-info)))
          (setq verb-phrase (or meaning
                                (tibetan-cat--gloss-word lemma)
                                lemma)))))

    ;; Build glosses for words not yet identified
    (let ((glosses '()))
      (dolist (seg segments)
        (let ((gloss (tibetan-cat--gloss-word seg multiword-units)))
          (when (and gloss
                     (not (string= gloss (or subject "")))
                     (not (string-match-p "^in " (or location ""))))
            (push gloss glosses))))
      (when (and glosses (not verb-phrase))
        (setq verb-phrase (car glosses))
        (setq glosses (cdr glosses)))
      ;; Remaining glosses could be topic/subject
      (when (and glosses (not subject))
        (setq subject (car (last glosses)))))

    ;; Build the English sentence
    ;; Check for temporal construction (པའི་ཚེ)
    (if (string-match-p "པའི་ཚེ\\|བའི་ཚེ" tibetan-text)
        ;; Temporal clause: "At the time when [subject] [verb] in [location]..."
        (let ((parts '()))
          (when sentence-initial (push sentence-initial parts))
          (push "at the time when" parts)
          (when subject (push (format "the %s" subject) parts))
          (when (and verb-phrase (not (string-match-p "^to " verb-phrase)))
            (push "was" parts))
          (when verb-phrase
            (push (replace-regexp-in-string "^to " "" (replace-regexp-in-string " (hon\\.)" "" verb-phrase)) parts))
          (when location (push location parts))
          (concat (string-join (nreverse parts) " ") ", ..."))

      ;; Regular sentence: [Sentence-initial] [Subject] [Verb] [Location/Object]
      (let ((parts '()))
        (when sentence-initial (push sentence-initial parts))
        (when subject (push subject parts))
        (when verb-phrase
          (push (replace-regexp-in-string "^to " "" verb-phrase) parts))
        (when location (push location parts))
        (if parts
            (string-join (nreverse parts) " ")
          ;; Fallback to simple gloss
          (let ((glosses '()))
            (dolist (seg segments)
              (let ((gloss (tibetan-cat--gloss-word seg multiword-units)))
                (push (or gloss (format "[%s]" seg)) glosses)))
            (when sentence-initial
              (push sentence-initial glosses))
            (string-join (nreverse glosses) " ")))))))

;; ============================================================================
;; INTERACTIVE COMMAND
;; ============================================================================

(defun tibetan-cat-insert-translation ()
  "Generate and insert CAT translation for current segment.
Works within an analysis buffer to fill in the CAT Suggested line."
  (interactive)
  (let ((tibetan-text nil))
    ;; Try to get Tibetan text from current buffer (analysis file)
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Text$" nil t)
        (forward-line 1)
        (let ((start (point)))
          (if (re-search-forward "^\\* " nil t)
              (setq tibetan-text (string-trim (buffer-substring-no-properties start (line-beginning-position))))
            (setq tibetan-text (string-trim (buffer-substring-no-properties start (point-max))))))))

    (if tibetan-text
        (let ((translation (tibetan-cat-generate-translation tibetan-text)))
          ;; Find and update the CAT Suggested line
          (save-excursion
            (goto-char (point-min))
            (if (re-search-forward "^- CAT Suggested: .*$" nil t)
                (progn
                  (replace-match (format "- CAT Suggested: %s" translation))
                  (message "CAT translation inserted"))
              ;; If no CAT Suggested line, just show in message
              (message "CAT translation: %s" translation))))
      (message "No Tibetan text found in buffer"))))

(defun tibetan-cat-translate-region (start end)
  "Generate CAT translation for Tibetan text in region from START to END."
  (interactive "r")
  (let* ((tibetan-text (buffer-substring-no-properties start end))
         (translation (tibetan-cat-generate-translation tibetan-text)))
    (message "CAT: %s" translation)
    translation))

(provide 'tibetan-translation-engine)
;;; tibetan-translation-engine.el ends here
