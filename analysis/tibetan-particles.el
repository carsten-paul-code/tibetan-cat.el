;;; tibetan-particles.el --- Context-aware particle analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Identifies grammatical particles in Tibetan text with:
;; - Particle type (GEN, ERG, ABL, SEQ, CAUSAL, etc.)
;; - Function in specific context
;; - Translation guidance
;; - Schwieger textbook references
;;
;; Focuses on unambiguous multi-character particles to avoid false positives.

;;; Code:

(require 'cl-lib)

;; Safe substring for multi-byte Tibetan text
(defun tibetan-particles-safe-substr (str start &optional end)
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
;; PARTICLE IDENTIFICATION
;; ============================================================================

(defun tibetan-identify-particles (tibetan-text)
  "Identify particles with Schwieger references.
Returns list of (pattern type reference) for basic particle detection."
  (let ((particles '())
        (patterns '(("འི\\|ཀྱི\\|གི\\|ཡི\\|གྱི" "GEN (genitive case)" "Schwieger: §4.2 - possession, relation, or modification")
                   ("ཀྱིས\\|གྱིས\\|གིས\\|འིས\\|ཡིས" "ERG (ergative case)" "Schwieger: §4.1 - agent of transitive verb")
                   ("ལ\\|ར\\|དུ\\|ཏུ\\|སུ\\|རུ" "DAT/LOC (dative/locative)" "Schwieger: §4.3 - indirect object, location, goal")
                   ("ན" "LOC (locative case)" "Schwieger: §4.3 - location or condition")
                   ("ནས\\|ལས" "ABL (ablative case)" "Schwieger: §4.4 - source, origin, starting point")
                   ("པས\\|བས" "Causal converb" "Schwieger: §6.3 - cause/reason")
                   ("ཏེ\\|སྟེ\\|ཅིང\\|ཞིང" "Sequential converb" "Schwieger: §6.2 - sequential action")
                   ("ཀྱང\\|ཡང\\|འང" "Concessive" "Schwieger: §5.4 - also/even/though")
                   ("ནི" "Topic marker" "Schwieger: §5.3 - topic/contrast"))))
    (dolist (p patterns)
      (when (string-match-p (nth 0 p) tibetan-text)
        (push (list (nth 0 p) (nth 1 p) (nth 2 p)) particles)))
    (nreverse particles)))

;; ============================================================================
;; CONTEXT-AWARE PARTICLE ANALYSIS
;; ============================================================================

(defun tibetan-analyze-particles-in-context (tibetan-text)
  "Analyze particles in context with specific function and translation effect.
Returns list of (particle word type function translation-effect schwieger-ref).
Focuses on unambiguous multi-character particles to avoid false positives.

Each element in the returned list is:
  (PARTICLE WORD TYPE FUNCTION TRANSLATION-EFFECT SCHWIEGER-REF)

Where:
  PARTICLE - the particle itself (e.g., 'འི')
  WORD - the full word containing the particle (e.g., 'པའི')
  TYPE - grammatical type (e.g., 'GEN', 'ERG', 'ABL')
  FUNCTION - description of function in this specific context
  TRANSLATION-EFFECT - guidance for translation
  SCHWIEGER-REF - reference to Schwieger's grammar"

  (let ((analysis '())
        ;; Clean text: remove punctuation first
        (clean-text (replace-regexp-in-string "[།༎༏༐༑༔]" "" tibetan-text))
        (words (split-string (replace-regexp-in-string " " "་"
                              (replace-regexp-in-string "[།༎༏༐༑༔]" "" tibetan-text)) "་" t)))

    ;; Process each word
    (dolist (word words)
      (let ((found nil))
        ;; Check for multi-character particles (less ambiguous)
        (cond
         ;; ========== GENITIVE ==========
         ((or (string-suffix-p "ཀྱི" word) (string-suffix-p "གྱི" word) (string-suffix-p "འི" word))
          (let* ((particle (cond ((string-suffix-p "ཀྱི" word) "ཀྱི")
                                ((string-suffix-p "གྱི" word) "གྱི")
                                (t "འི")))
                 (root (tibetan-particles-safe-substr word 0 (- (length word) (length particle)))))
            (when (> (length root) 0)
              (push (list particle word "GEN"
                         (format "Marks '%s' as possessor/modifier" root)
                         (format "Translate: 'of %s' or '%s's'" root root)
                         "Schwieger §4.2")
                    analysis))))

         ;; ========== ERGATIVE ==========
         ((or (string-suffix-p "ཀྱིས" word) (string-suffix-p "གྱིས" word) (string-suffix-p "གིས" word))
          (let* ((particle (cond ((string-suffix-p "ཀྱིས" word) "ཀྱིས")
                                ((string-suffix-p "གྱིས" word) "གྱིས")
                                (t "གིས")))
                 (root (tibetan-particles-safe-substr word 0 (- (length word) (length particle)))))
            (when (> (length root) 0)
              (push (list particle word "ERG"
                         (format "Marks '%s' as agent of transitive verb" root)
                         (format "Translate: 'by %s' (actor)" root)
                         "Schwieger §4.1")
                    analysis))))

         ;; ========== ABLATIVE ==========
         ((or (string-suffix-p "ནས" word) (string-suffix-p "ལས" word))
          (let* ((particle (if (string-suffix-p "ནས" word) "ནས" "ལས"))
                 (root (tibetan-particles-safe-substr word 0 (- (length word) (length particle)))))
            (if (> (length root) 0)
                (push (list particle word "ABL"
                           (format "Marks '%s' as source/starting point" root)
                           (format "Translate: 'from %s' or 'after %s'" root root)
                           "Schwieger §4.4")
                      analysis)
              ;; Standalone particle (rare but possible)
              (push (list particle word "ABL"
                         "Standalone ablative particle"
                         "Translate: 'from/after [preceding phrase]'"
                         "Schwieger §4.4")
                    analysis))))

         ;; ========== SEQUENTIAL CONVERBS ==========
         ((or (string-suffix-p "ཞིང" word) (string-suffix-p "ཅིང" word) (string-suffix-p "སྟེ" word))
          (let* ((particle (cond ((string-suffix-p "ཞིང" word) "ཞིང")
                                ((string-suffix-p "ཅིང" word) "ཅིང")
                                (t "སྟེ")))
                 (root (tibetan-particles-safe-substr word 0 (- (length word) (length particle)))))
            (if (> (length root) 0)
                (push (list particle word "SEQ"
                           (format "Connects '%s' to next action" root)
                           (format "Translate: '%s and...' (continuing action)" root)
                           "Schwieger §6.2")
                      analysis)
              ;; Standalone particle (common for ཞིང)
              (push (list particle word "SEQ"
                         "Standalone sequential converb"
                         "Translate: 'and...' (connects to previous action)"
                         "Schwieger §6.2")
                    analysis))))

         ;; ========== CAUSAL CONVERBS ==========
         ((or (string-suffix-p "པས" word) (string-suffix-p "བས" word))
          (let* ((particle (if (string-suffix-p "པས" word) "པས" "བས"))
                 (root (tibetan-particles-safe-substr word 0 (- (length word) (length particle)))))
            (when (> (length root) 0)
              (push (list particle word "CAUSAL"
                         (format "Marks '%s' as cause/reason" root)
                         (format "Translate: 'because of %s' or 'having %s-ed'" root root)
                         "Schwieger §6.3")
                    analysis)))))))

    (nreverse analysis)))

;; ============================================================================
;; FORMATTING HELPERS
;; ============================================================================

(defun tibetan-format-particle-analysis (analysis-list)
  "Format particle ANALYSIS-LIST for display.
Returns formatted string with each particle on separate lines."
  (if (not analysis-list)
      "  [No particles detected]\n"
    (let ((result ""))
      (dolist (a analysis-list)
        (let ((particle (nth 0 a))
              (word (nth 1 a))
              (type (nth 2 a))
              (function (nth 3 a))
              (translation (nth 4 a))
              (reference (nth 5 a)))
          (setq result (concat result
                              (format "  • %s in '%s' — %s\n" particle word type)
                              (format "    Function: %s\n" function)
                              (format "    %s\n" translation)
                              (format "    %s\n\n" reference)))))
      result)))

(provide 'tibetan-particles)
;;; tibetan-particles.el ends here
