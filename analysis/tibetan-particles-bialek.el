;;; tibetan-particles-bialek.el --- Grammar analysis using Bialek terminology -*- lexical-binding: t -*-

;;; Commentary:
;; Grammar analysis based on Joanna Bialek's "A Textbook in Classical Tibetan"
;;
;; Key features:
;; - Uses Bialek's terminology (Absolutive, Ergative, Elative, Dative, etc.)
;; - Special focus on CONVERBIAL CONSTRUCTIONS (major Bialek emphasis)
;; - Detailed classroom-appropriate explanations
;; - Translation guidance for each construction
;;
;; Converbial constructions are clauses that depend on a main clause,
;; expressing temporal sequence, cause, manner, or accompaniment.

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; BIALEK GRAMMAR ANALYSIS - CASE PARTICLES
;; ============================================================================

(defun tibetan-analyze-cases-bialek (tibetan-text)
  "Analyze case particles using Bialek's terminology.
Returns list of (particle word case function translation-guide bialek-ref)."
  (let ((analysis '())
        (words (split-string (replace-regexp-in-string "[།༎༏༐༑༔]" "" tibetan-text) "་" t)))

    (dolist (word words)
      (cond
       ;; ========== ERGATIVE (agent of transitive/controllable verbs) ==========
       ((or (string-suffix-p "ཀྱིས" word) (string-suffix-p "གྱིས" word)
            (string-suffix-p "གིས" word) (string-suffix-p "འིས" word) (string-suffix-p "ཡིས" word))
        (let* ((particle (cond ((string-suffix-p "ཀྱིས" word) "ཀྱིས")
                              ((string-suffix-p "གྱིས" word) "གྱིས")
                              ((string-suffix-p "འིས" word) "འིས")
                              ((string-suffix-p "ཡིས" word) "ཡིས")
                              (t "གིས")))
               (root (substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "ERGATIVE (ERG)"
                       (format "Marks '%s' as AGENT of a transitive/controllable verb" root)
                       (format "Translation: 'by %s' or '%s [does the action]'" root root)
                       "Bialek: Ergative case for TR/C verb subjects")
                  analysis))))

       ;; ========== GENITIVE (possession, modification) ==========
       ((or (string-suffix-p "ཀྱི" word) (string-suffix-p "གྱི" word)
            (string-suffix-p "གི" word) (string-suffix-p "འི" word) (string-suffix-p "ཡི" word))
        (let* ((particle (cond ((string-suffix-p "ཀྱི" word) "ཀྱི")
                              ((string-suffix-p "གྱི" word) "གྱི")
                              ((string-suffix-p "འི" word) "འི")
                              ((string-suffix-p "ཡི" word) "ཡི")
                              (t "གི")))
               (root (substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "GENITIVE (GEN)"
                       (format "Marks '%s' as POSSESSOR or MODIFIER of following noun" root)
                       (format "Translation: 'of %s' or '%s's [noun]'" root root)
                       "Bialek: Genitive case for possession/modification")
                  analysis))))

       ;; ========== DATIVE (goal, recipient, indirect object) ==========
       ((or (string-suffix-p "ལ" word) (string-suffix-p "ར" word)
            (string-suffix-p "དུ" word) (string-suffix-p "ཏུ" word)
            (string-suffix-p "སུ" word) (string-suffix-p "རུ" word))
        (let* ((particle (cond ((string-suffix-p "ལ" word) "ལ")
                              ((string-suffix-p "དུ" word) "དུ")
                              ((string-suffix-p "ཏུ" word) "ཏུ")
                              ((string-suffix-p "སུ" word) "སུ")
                              ((string-suffix-p "རུ" word) "རུ")
                              (t "ར")))
               (root (substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "DATIVE (DAT)"
                       (format "Marks '%s' as GOAL, RECIPIENT, or LOCATION" root)
                       (format "Translation: 'to %s', 'for %s', 'in/at %s'" root root root)
                       "Bialek: Dative for indirect objects and destinations")
                  analysis))))

       ;; ========== ELATIVE/ABLATIVE (source, origin, starting point) ==========
       ((or (string-suffix-p "ནས" word) (string-suffix-p "ལས" word))
        (let* ((particle (if (string-suffix-p "ནས" word) "ནས" "ལས"))
               (root (substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "ELATIVE/ABLATIVE (ABL)"
                         (format "Marks '%s' as SOURCE or STARTING POINT" root)
                         (format "Translation: 'from %s' or 'after %s'" root root)
                         "Bialek: Elative for source/origin, temporal 'after'")
                    analysis)
            ;; Standalone (common in converbs)
            (push (list particle word "ELATIVE/ABLATIVE (ABL)"
                       "Standalone ablative (often in converbial construction)"
                       "Translation: 'from/after [the preceding action]'"
                       "Bialek: Elative in converbs")
                  analysis))))

       ;; ========== LOCATIVE (location, condition) ==========
       ((string-suffix-p "ན" word)
        (let* ((particle "ན")
               (root (substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "LOCATIVE (LOC)"
                       (format "Marks '%s' as LOCATION or expresses CONDITION" root)
                       (format "Translation: 'in/at %s' or 'when %s'" root root)
                       "Bialek: Locative for location or temporal condition")
                  analysis))))))

    (nreverse analysis)))

;; ============================================================================
;; CONVERBIAL CONSTRUCTIONS (Main Focus for Bialek)
;; ============================================================================

(defun tibetan-analyze-converbs-bialek (tibetan-text)
  "Analyze CONVERBIAL CONSTRUCTIONS - major emphasis in Bialek.

Converbial constructions are dependent clauses that express:
- Temporal sequence ('having done X, then...')
- Cause/reason ('because of X')
- Simultaneity ('while doing X')
- Manner ('by means of X')

Returns list of (particle word type function translation-guide bialek-ref)."
  (let ((analysis '())
        (words (split-string (replace-regexp-in-string "[།༎༏༐༑༔]" "" tibetan-text) "་" t)))

    (dolist (word words)
      (cond
       ;; ========== ABLATIVE CONVERB: ནས (sequential action) ==========
       ((string-suffix-p "ནས" word)
        (let* ((particle "ནས")
               (root (substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "CONVERBIAL: ABLATIVE CONVERB"
                         (format "Sequential converb: '%s' happens BEFORE main verb" root)
                         (format "Translation: 'having %s-ed' or 'after %s-ing'" root root)
                         "Bialek: ནས་ converb - temporal sequence, most common converb")
                    analysis)
            ;; Standalone
            (push (list particle word "CONVERBIAL: ABLATIVE CONVERB"
                       "Standalone converb connecting to previous clause"
                       "Translation: 'and then' or 'after that'"
                       "Bialek: ནས་ converb standalone")
                  analysis))))

       ;; ========== COORDINATIVE CONVERB: ཏེ/སྟེ (sequential + coordinative) ==========
       ((or (string-suffix-p "ཏེ" word) (string-suffix-p "སྟེ" word) (string-suffix-p "དེ" word))
        (let* ((particle (cond ((string-suffix-p "སྟེ" word) "སྟེ")
                              ((string-suffix-p "དེ" word) "དེ")
                              (t "ཏེ")))
               (root (substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "CONVERBIAL: COORDINATIVE CONVERB"
                         (format "Connects '%s' to following action sequentially" root)
                         (format "Translation: '%s and...' or 'having %s-ed'" root root)
                         "Bialek: ཏེ་/སྟེ་ converb - coordination and sequence")
                    analysis)
            ;; Standalone
            (push (list particle word "CONVERBIAL: COORDINATIVE CONVERB"
                       "Standalone coordinative converb"
                       "Translation: 'and...' (continuing narrative)"
                       "Bialek: ཏེ་/སྟེ་ converb standalone")
                  analysis))))

       ;; ========== SIMULTANEOUS CONVERB: ཞིང/ཅིང (simultaneous/accompanying action) ==========
       ((or (string-suffix-p "ཞིང" word) (string-suffix-p "ཅིང" word) (string-suffix-p "ཤིང" word))
        (let* ((particle (cond ((string-suffix-p "ཞིང" word) "ཞིང")
                              ((string-suffix-p "ཤིང" word) "ཤིང")
                              (t "ཅིང")))
               (root (substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "CONVERBIAL: SIMULTANEOUS CONVERB"
                         (format "Simultaneous converb: '%s' happens AT SAME TIME as main verb" root)
                         (format "Translation: 'while %s-ing' or '%s-ing and [also]...'" root root)
                         "Bialek: ཞིང་/ཅིང་ converb - simultaneity, accompanying action")
                    analysis)
            ;; Standalone
            (push (list particle word "CONVERBIAL: SIMULTANEOUS CONVERB"
                       "Standalone simultaneous converb"
                       "Translation: 'and [at the same time]'"
                       "Bialek: ཞིང་/ཅིང་ converb standalone")
                  analysis))))

       ;; ========== CAUSAL CONVERB: པས/བས (cause, reason) ==========
       ((or (string-suffix-p "པས" word) (string-suffix-p "བས" word))
        (let* ((particle (if (string-suffix-p "པས" word) "པས" "བས"))
               (root (substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "CONVERBIAL: CAUSAL CONVERB"
                       (format "Causal converb: '%s' is the REASON for main verb" root)
                       (format "Translation: 'because %s' or 'since %s'" root root)
                       "Bialek: པས་/བས་ converb - cause/reason")
                  analysis))))

       ;; ========== CONCESSIVE: ཀྱང/ཡང/འང (even, also, though) ==========
       ((or (string-suffix-p "ཀྱང" word) (string-suffix-p "ཡང" word) (string-suffix-p "འང" word))
        (let* ((particle (cond ((string-suffix-p "ཀྱང" word) "ཀྱང")
                              ((string-suffix-p "འང" word) "འང")
                              (t "ཡང")))
               (root (substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "CONCESSIVE PARTICLE"
                       (format "Marks '%s' with concessive meaning" root)
                       (format "Translation: 'even %s' or 'although %s' or '%s also'" root root root)
                       "Bialek: Concessive particle - contrast or emphasis")
                  analysis))))))

    (nreverse analysis)))

;; ============================================================================
;; UNIFIED BIALEK ANALYSIS
;; ============================================================================

(defun tibetan-analyze-grammar-bialek (tibetan-text)
  "Complete grammar analysis using Bialek's framework.
Combines case analysis and converbial construction analysis.
Returns list of all grammatical features detected."
  (let ((cases (tibetan-analyze-cases-bialek tibetan-text))
        (converbs (tibetan-analyze-converbs-bialek tibetan-text)))
    ;; Merge and remove duplicates (converbs take precedence)
    (let ((all-particles (append converbs cases))
          (seen-words (make-hash-table :test 'equal))
          (result '()))
      (dolist (item all-particles)
        (let ((word (nth 1 item)))
          (unless (gethash word seen-words)
            (puthash word t seen-words)
            (push item result))))
      (nreverse result))))

;; ============================================================================
;; FORMATTING FOR DISPLAY
;; ============================================================================

(defun tibetan-format-grammar-bialek (analysis-list)
  "Format Bialek grammar analysis for classroom display.
Shows particle, word, type, function, translation guide, and Bialek reference."
  (if (not analysis-list)
      "  [No grammatical markers detected]\n"
    (let ((result ""))
      (dolist (a analysis-list)
        (let ((particle (nth 0 a))
              (word (nth 1 a))
              (type (nth 2 a))
              (function (nth 3 a))
              (translation (nth 4 a))
              (reference (nth 5 a)))
          (setq result (concat result
                              (format "  • %s in '%s'\n" particle word)
                              (format "    TYPE: %s\n" type)
                              (format "    FUNCTION: %s\n" function)
                              (format "    TRANSLATION: %s\n" translation)
                              (format "    REFERENCE: %s\n\n" reference)))))
      result)))

;; ============================================================================
;; CONVERBIAL CONSTRUCTION SUMMARY (for teaching)
;; ============================================================================

(defun tibetan-summarize-converbs (analysis-list)
  "Generate a summary of converbial constructions found.
Useful for classroom teaching to highlight these important structures."
  (let ((converbs (cl-remove-if-not
                   (lambda (item) (string-match-p "CONVERBIAL" (nth 2 item)))
                   analysis-list)))
    (if (not converbs)
        "  [No converbial constructions detected in this segment]\n"
      (concat
       "  CONVERBIAL CONSTRUCTIONS FOUND:\n"
       (mapconcat
        (lambda (item)
          (format "    - %s: %s" (nth 1 item) (nth 3 item)))
        converbs
        "\n")
       "\n\n  These are DEPENDENT CLAUSES that modify the main verb!\n"))))

(provide 'tibetan-particles-bialek)
;;; tibetan-particles-bialek.el ends here
