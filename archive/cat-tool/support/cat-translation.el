;;; cat-translation.el --- Translation generation for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Translation generation and suggestion module for Tibetan CAT.
;; Combines vocabulary lookups with grammar analysis to produce
;; context-aware translation suggestions.
;;
;; Features:
;; - Word-by-word gloss generation
;; - Grammar-informed translation building
;; - Context-aware rendering (Madhyamaka, verse, etc.)
;; - Connector/converb handling for natural English

;;; Code:

(require 'cl-lib)
(require 'cat-utils)
(require 'cat-grammar)
(require 'cat-parser)

;; ============================================================================
;; TRANSLATION CONTEXT
;; ============================================================================

(defvar cat-translation-contexts
  '((bhutan-kagyu-madhyamaka
     :name "Bhutan Kagyu Madhyamaka"
     :style verse
     :terminology philosophical)
    (gelug-madhyamaka
     :name "Gelug Madhyamaka"
     :style verse
     :terminology philosophical)
    (classical-prose
     :name "Classical Prose"
     :style prose
     :terminology general)
    (sutra
     :name "Sutra"
     :style formal
     :terminology buddhist)
    (commentary
     :name "Commentary"
     :style analytical
     :terminology philosophical))
  "Translation context definitions with style and terminology hints.")

(defun cat-translation-get-context (context-symbol)
  "Get context definition for CONTEXT-SYMBOL."
  (assq context-symbol cat-translation-contexts))

;; ============================================================================
;; GLOSS BUILDING
;; ============================================================================

(defun cat-translation-build-gloss (parse-result)
  "Build word-by-word gloss from PARSE-RESULT.
Returns list of (tibetan . english) pairs."
  (let ((segments (cat-parse-result-segments parse-result))
        (gloss-pairs '()))
    (dolist (seg segments)
      (let ((meaning (cat-parser-lookup-segment seg parse-result)))
        (push (cons seg (or meaning "?")) gloss-pairs)))
    (nreverse gloss-pairs)))

(defun cat-translation-gloss-to-string (gloss-pairs &optional separator)
  "Convert GLOSS-PAIRS to string with SEPARATOR (default ' | ')."
  (let ((sep (or separator " | ")))
    (mapconcat
     (lambda (pair)
       (format "%s=%s" (car pair) (cdr pair)))
     gloss-pairs
     sep)))

;; ============================================================================
;; GRAMMAR-INFORMED TRANSLATION
;; ============================================================================

(defun cat-translation-apply-particle-transforms (gloss-pairs particles)
  "Transform GLOSS-PAIRS based on detected PARTICLES.
Returns modified gloss with grammatical markers applied."
  (let ((result (copy-sequence gloss-pairs)))
    (dolist (p particles)
      (let* ((word (cat-particle-word p))
             (type (cat-particle-type p))
             (pair (assoc word result)))
        (when pair
          (let ((meaning (cdr pair)))
            (setcdr pair
                    (cond
                     ;; Ergative: mark as agent
                     ((eq type 'ergative)
                      (format "[by] %s" meaning))
                     ;; Genitive: mark as possessor
                     ((eq type 'genitive)
                      (format "%s's" meaning))
                     ;; Dative/Allative: mark as goal
                     ((memq type '(dative allative))
                      (format "[to/toward] %s" meaning))
                     ;; Ablative: mark as source
                     ((eq type 'ablative)
                      (format "[from] %s" meaning))
                     ;; Locative: mark as location
                     ((eq type 'locative)
                      (format "[in/at] %s" meaning))
                     ;; Converbs: indicate sequence
                     ((memq type '(converb-sequential converb-coordinative))
                      (format "[having %s-ed]" meaning))
                     ((eq type 'converb-simultaneous)
                      (format "[while %s-ing]" meaning))
                     ;; Causal
                     ((eq type 'causal)
                      (format "[because %s]" meaning))
                     ;; Default: keep as is
                     (t meaning)))))))
    result))

;; ============================================================================
;; TRANSLATION GENERATION
;; ============================================================================

(defun cat-translation-extract-content-words (gloss-pairs)
  "Extract content words from GLOSS-PAIRS, filtering particles."
  (let ((skip-words '("ནི" "ཡང" "གི" "ཀྱི" "འི" "ཡི" "གྱི"
                     "ལ" "ན" "དུ" "སུ" "ར" "ས" "ནས" "ལས" "དང")))
    (cl-remove-if
     (lambda (pair)
       (or (string= (cdr pair) "?")
           (string-empty-p (cdr pair))
           (member (car pair) skip-words)))
     gloss-pairs)))

(defun cat-translation-clean-meaning (meaning)
  "Clean MEANING string by taking first definition."
  (if (string-match "^\\([^,;]+\\)" meaning)
      (string-trim (match-string 1 meaning))
    (string-trim meaning)))

(defun cat-translation-generate-basic (parse-result &optional verbs)
  "Generate basic translation from PARSE-RESULT and optional VERBS."
  (let* ((gloss-pairs (cat-translation-build-gloss parse-result))
         (content-pairs (cat-translation-extract-content-words gloss-pairs))
         (words '()))

    ;; Collect cleaned meanings
    (dolist (pair content-pairs)
      (push (cat-translation-clean-meaning (cdr pair)) words))
    (setq words (nreverse words))

    ;; Add verb meaning if available and not already included
    (when (and verbs (car verbs))
      (let* ((main-verb (car verbs))
             (verb-meaning (when (and (listp main-verb) (consp (car main-verb)))
                            (car (split-string
                                  (or (alist-get 'meaning main-verb) "")
                                  "," t)))))
        (when (and verb-meaning
                   (not (cl-some (lambda (w)
                                  (string-match-p (regexp-quote verb-meaning) w))
                                words)))
          (push verb-meaning words))))

    ;; Build translation
    (let ((trans (string-join words " ")))
      ;; Capitalize if ASCII start
      (when (and (> (length trans) 0)
                 (string-match "^[a-z]" trans))
        (setq trans (concat (upcase (substring trans 0 1))
                           (substring trans 1))))
      trans)))

(defun cat-translation-generate-with-grammar (parse-result particles &optional verbs)
  "Generate grammar-aware translation from PARSE-RESULT, PARTICLES, and VERBS."
  (let* ((gloss-pairs (cat-translation-build-gloss parse-result))
         (transformed (cat-translation-apply-particle-transforms gloss-pairs particles))
         (content-pairs (cat-translation-extract-content-words transformed))
         (words '()))

    ;; Collect transformed meanings
    (dolist (pair content-pairs)
      (push (cat-translation-clean-meaning (cdr pair)) words))
    (setq words (nreverse words))

    ;; Add verb
    (when (and verbs (car verbs))
      (let* ((main-verb (car verbs))
             (verb-meaning (when (and (listp main-verb) (consp (car main-verb)))
                            (car (split-string
                                  (or (alist-get 'meaning main-verb) "")
                                  "," t)))))
        (when verb-meaning
          (push verb-meaning words))))

    (let ((trans (string-join words " ")))
      (when (and (> (length trans) 0)
                 (string-match "^[a-z]" trans))
        (setq trans (concat (upcase (substring trans 0 1))
                           (substring trans 1))))
      trans)))

;; ============================================================================
;; LINE CONNECTORS (for compound/verse translation)
;; ============================================================================

(defun cat-translation-detect-connector (text next-text)
  "Detect inter-line connector between TEXT and NEXT-TEXT.
Returns connector type symbol or nil."
  (let ((words (cat-segment-text text))
        (last-word (when words (car (last words)))))
    (cond
     ;; Sequential converb: "having done X, ..."
     ((and last-word
           (or (string-suffix-p "ནས" last-word)
               (string-suffix-p "སྟེ" last-word)
               (string-suffix-p "ཏེ" last-word)))
      'sequential)

     ;; Simultaneous converb: "while doing X, ..."
     ((and last-word
           (or (string-suffix-p "ཅིང" last-word)
               (string-suffix-p "ཞིང" last-word)))
      'simultaneous)

     ;; Causal: "because X, ..."
     ((and last-word
           (or (string-suffix-p "པས" last-word)
               (string-suffix-p "བས" last-word)))
      'causal)

     ;; Conditional: "if/when X, ..."
     ((and last-word (string-suffix-p "ན" last-word))
      'conditional)

     ;; Coordination
     ((and last-word (string= last-word "དང"))
      'conjunction)

     ;; Default: no special connector
     (t nil))))

(defun cat-translation-apply-connector (line-trans connector-type is-first is-last)
  "Apply CONNECTOR-TYPE transformation to LINE-TRANS.
IS-FIRST and IS-LAST indicate position in compound."
  (let ((text line-trans))
    (unless is-first
      (cond
       ((eq connector-type 'sequential)
        ;; Lower case if not first, add "Having..."
        (when (string-match "^[A-Z]" text)
          (setq text (concat (downcase (substring text 0 1))
                            (substring text 1))))
        (setq text (concat "Having " text ",")))

       ((eq connector-type 'simultaneous)
        (when (string-match "^[A-Z]" text)
          (setq text (concat (downcase (substring text 0 1))
                            (substring text 1))))
        (setq text (concat "while " text ",")))

       ((eq connector-type 'causal)
        (when (string-match "^[A-Z]" text)
          (setq text (concat (downcase (substring text 0 1))
                            (substring text 1))))
        (setq text (concat "because " text ",")))

       ((eq connector-type 'conditional)
        (when (string-match "^[A-Z]" text)
          (setq text (concat (downcase (substring text 0 1))
                            (substring text 1))))
        (setq text (concat "when " text ",")))

       ((eq connector-type 'conjunction)
        (setq text (concat text " and")))))

    ;; Capitalize first letter of first line
    (when is-first
      (when (and (> (length text) 0)
                 (string-match "^[a-z]" text))
        (setq text (concat (upcase (substring text 0 1))
                          (substring text 1)))))

    ;; Add period to last line
    (when is-last
      (setq text (concat text ".")))

    text))

;; ============================================================================
;; COMPOUND TRANSLATION
;; ============================================================================

(defun cat-translation-generate-compound (lines context)
  "Generate translation for compound (verse/sentence).
LINES is list of (seg-id . text), CONTEXT is context symbol."
  (let ((line-translations '())
        (total (length lines)))

    ;; Generate per-line translations with connectors
    (cl-loop for idx from 0 below total
             for line in lines
             do (let* ((text (cdr line))
                      (next-text (when (< idx (1- total))
                                  (cdr (nth (1+ idx) lines))))
                      (parse-result (cat-parser-parse text))
                      (particles (cat-grammar-analyze-text text))
                      (verbs (cat-parser-extract-verbs parse-result))
                      (line-trans (cat-translation-generate-with-grammar
                                  parse-result particles verbs))
                      (connector (cat-translation-detect-connector text next-text))
                      (is-first (= idx 0))
                      (is-last (= idx (1- total)))
                      (final-trans (cat-translation-apply-connector
                                   line-trans connector is-first is-last)))
                 (push final-trans line-translations)))

    ;; Combine lines
    (string-join (nreverse line-translations) "\n")))

;; ============================================================================
;; MAIN INTERFACE
;; ============================================================================

(defun cat-translation-suggest (tibetan-text &optional context)
  "Generate translation suggestion for TIBETAN-TEXT.
Optional CONTEXT provides translation context.
Returns alist with :basic, :grammar-aware, and :gloss."
  (let* ((parse-result (cat-parser-parse tibetan-text))
         (particles (cat-grammar-analyze-text tibetan-text))
         (verbs (cat-parser-extract-verbs parse-result))
         (gloss-pairs (cat-translation-build-gloss parse-result))
         (basic (cat-translation-generate-basic parse-result verbs))
         (grammar-aware (cat-translation-generate-with-grammar
                        parse-result particles verbs)))

    `((:basic . ,basic)
      (:grammar-aware . ,grammar-aware)
      (:gloss . ,gloss-pairs)
      (:particles . ,particles)
      (:verbs . ,verbs))))

(provide 'cat-translation)
;;; cat-translation.el ends here
