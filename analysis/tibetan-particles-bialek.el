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

;; Safe substring for multi-byte Tibetan text
(defun tibetan-particles-safe-substring (str start &optional end)
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
;; BIALEK GRAMMAR ANALYSIS - CASE PARTICLES
;; ============================================================================

(defun tibetan-analyze-cases-bialek (tibetan-text)
  "Analyze case particles using Bialek's terminology.
Returns list of (particle word case function translation-guide bialek-ref)."
  (let ((analysis '())
        (words (split-string (replace-regexp-in-string "[།༎༏༐༑༔]" "" tibetan-text) "་" t)))

    (dolist (word words)
      (cond
       ;; ========== ERGATIVE/INSTRUMENTAL (agent OR instrument/means) ==========
       ;; Note: Same particles mark both agent (ergative) and instrument/means
       ((or (string-suffix-p "ཀྱིས" word) (string-suffix-p "གྱིས" word)
            (string-suffix-p "གིས" word) (string-suffix-p "འིས" word) (string-suffix-p "ཡིས" word)
            (string= "ས" word))  ; Standalone ས
        (let* ((particle (cond ((string-suffix-p "ཀྱིས" word) "ཀྱིས")
                              ((string-suffix-p "གྱིས" word) "གྱིས")
                              ((string-suffix-p "འིས" word) "འིས")
                              ((string-suffix-p "ཡིས" word) "ཡིས")
                              ((string= "ས" word) "ས")
                              (t "གིས")))
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          ;; Handle both attached and standalone particles
          (if (> (length root) 0)
              (push (list particle word "ERGATIVE/INSTRUMENTAL (ERG/INST)"
                         (format "Marks '%s' as AGENT or INSTRUMENT/MEANS" root)
                         (format "Translation: 'by %s' (agent) or 'by means of %s' (instrument)" root root)
                         "Bialek: Ergative for agents; Instrumental for means/instrument")
                    analysis)
            ;; Standalone particle - marks previous word
            (push (list particle word "ERGATIVE/INSTRUMENTAL (ERG/INST)"
                       "Marks preceding word as AGENT or INSTRUMENT/MEANS"
                       "Translation: 'by [previous]' (agent) or 'by means of [previous]' (instrument)"
                       "Bialek: Ergative/Instrumental (standalone)")
                  analysis))))

       ;; ========== GENITIVE (possession, modification) ==========
       ((or (string-suffix-p "ཀྱི" word) (string-suffix-p "གྱི" word)
            (string-suffix-p "གི" word) (string-suffix-p "འི" word) (string-suffix-p "ཡི" word))
        (let* ((particle (cond ((string-suffix-p "ཀྱི" word) "ཀྱི")
                              ((string-suffix-p "གྱི" word) "གྱི")
                              ((string-suffix-p "འི" word) "འི")
                              ((string-suffix-p "ཡི" word) "ཡི")
                              (t "གི")))
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "GENITIVE (GEN)"
                       (format "Marks '%s' as POSSESSOR or MODIFIER of following noun" root)
                       (format "Translation: 'of %s' or '%s's [noun]'" root root)
                       "Bialek: Genitive case for possession/modification")
                  analysis))))

       ;; ========== TERMINATIVE (goal, direction, manner, result) ==========
       ;; Note: ར/དུ/ཏུ/སུ are TERMINATIVE (not dative!) - marks goal/direction/manner
       ;; ལ is DATIVE - marks indirect object, location, recipient
       ((or (string-suffix-p "ལ" word) (string-suffix-p "ར" word)
            (string-suffix-p "དུ" word) (string-suffix-p "ཏུ" word)
            (string-suffix-p "སུ" word) (string-suffix-p "རུ" word)
            (member word '("ལ" "ར" "དུ" "ཏུ" "སུ" "རུ")))  ; Standalone particles
        (let* ((particle (cond ((or (string-suffix-p "དུ" word) (string= "དུ" word)) "དུ")
                              ((or (string-suffix-p "ཏུ" word) (string= "ཏུ" word)) "ཏུ")
                              ((or (string-suffix-p "སུ" word) (string= "སུ" word)) "སུ")
                              ((or (string-suffix-p "རུ" word) (string= "རུ" word)) "རུ")
                              ((or (string-suffix-p "ལ" word) (string= "ལ" word)) "ལ")
                              (t "ར")))
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle))))
               ;; ར/དུ/ཏུ/སུ/རུ are TERMINATIVE; ལ is DATIVE
               (is-terminative (member particle '("ར" "དུ" "ཏུ" "སུ" "རུ")))
               (type (if is-terminative "TERMINATIVE (ALL)" "DATIVE (DAT)")))
          (if (> (length root) 0)
              (push (list particle word type
                         (format "Marks '%s' as %s" root
                                 (if is-terminative "GOAL, DIRECTION, MANNER, or RESULT" "INDIRECT OBJECT, RECIPIENT, or LOCATION"))
                         (format "Translation: '%s %s'"
                                 (if is-terminative "toward/into/as" "to/for/at") root)
                         (if is-terminative
                             "Bialek: Terminative - goal/direction/manner/result (NOT dative)"
                           "Bialek: Dative for indirect objects and destinations"))
                    analysis)
            ;; Standalone particle
            (push (list particle word type
                       (format "Marks preceding word as %s"
                               (if is-terminative "GOAL, DIRECTION, or MANNER" "INDIRECT OBJECT or RECIPIENT"))
                       (format "Translation: '%s [previous word]'"
                               (if is-terminative "toward/into/as" "to/for/at"))
                       (if is-terminative
                           "Bialek: Terminative (standalone) - NOT dative"
                           "Bialek: Dative (standalone)"))
                  analysis))))

       ;; ========== ELATIVE/ABLATIVE (source, origin, starting point) ==========
       ((or (string-suffix-p "ནས" word) (string-suffix-p "ལས" word))
        (let* ((particle (if (string-suffix-p "ནས" word) "ནས" "ལས"))
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
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

       ;; ========== LOCATIVE + CONCESSIVE: ནའང (even when/also in) ==========
       ((or (string-suffix-p "ནའང" word) (string= "ནའང" word))
        (let* ((particle "ནའང")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "LOCATIVE+CONCESSIVE (LOC+CONC)"
                         (format "Marks '%s' with locative+concessive meaning: 'even when/also in'" root)
                         (format "Translation: 'even when %s' or 'also in %s'" root root)
                         "Bialek: ན་ (locative) + འང་ (concessive 'also/even')")
                    analysis)
            ;; Standalone
            (push (list particle word "LOCATIVE+CONCESSIVE (LOC+CONC)"
                       "Concessive locative: 'even when/also in' preceding element"
                       "Translation: 'even when [previous]' or 'also in [previous]'"
                       "Bialek: ན་ (locative) + འང་ (concessive)")
                  analysis))))

       ;; ========== LOCATIVE (location, condition) ==========
       ((string-suffix-p "ན" word)
        (let* ((particle "ན")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "LOCATIVE (LOC)"
                       (format "Marks '%s' as LOCATION or expresses CONDITION" root)
                       (format "Translation: 'in/at %s' or 'when %s'" root root)
                       "Bialek: Locative for location or temporal condition")
                  analysis))))

       ;; ========== TOPIC MARKER ནི ==========
       ((or (string-suffix-p "ནི" word) (string= "ནི" word))
        (let* ((particle "ནི")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "TOPIC (TOP)"
                         (format "Marks '%s' as TOPIC - the element being commented on" root)
                         (format "Translation: 'as for %s...' or 'regarding %s...'" root root)
                         "Bialek: Topic marker for thematic focus")
                    analysis)
            ;; Standalone ནི
            (push (list particle word "TOPIC (TOP)"
                       "Marks preceding word/phrase as TOPIC"
                       "Translation: 'as for [previous]...' or 'regarding [previous]...'"
                       "Bialek: Topic marker (standalone)")
                  analysis))))

       ;; ========== COMITATIVE/ASSOCIATIVE དང ==========
       ((or (string-suffix-p "དང" word) (string= "དང" word))
        (let* ((particle "དང")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "COMITATIVE (COM)"
                         (format "Marks '%s' as accompaniment or connection" root)
                         (format "Translation: 'with %s', '%s and...', 'together with %s'" root root root)
                         "Bialek: Comitative for accompaniment/coordination")
                    analysis)
            ;; Standalone དང
            (push (list particle word "COMITATIVE (COM)"
                       "Marks preceding word as accompaniment/coordination"
                       "Translation: 'with [previous]', '[previous] and...'"
                       "Bialek: Comitative (standalone)")
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
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
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
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
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
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
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
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "CONVERBIAL: CAUSAL CONVERB"
                       (format "Causal converb: '%s' is the REASON for main verb" root)
                       (format "Translation: 'because %s' or 'since %s'" root root)
                       "Bialek: པས་/བས་ converb - cause/reason")
                  analysis))))

       ;; ========== LOCATIVE+CONCESSIVE: ནའང (even when/also in) ==========
       ;; Must check BEFORE general འང to catch the composite particle
       ((or (string-suffix-p "ནའང" word) (string= "ནའང" word))
        (let* ((particle "ནའང")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "LOCATIVE+CONCESSIVE (LOC+CONC)"
                         (format "Marks '%s' with locative+concessive meaning: 'even when/also in'" root)
                         (format "Translation: 'even when %s' or 'also in %s'" root root)
                         "Bialek: ན་ (locative) + འང་ (concessive 'also/even')")
                    analysis)
            ;; Standalone ནའང
            (push (list particle word "LOCATIVE+CONCESSIVE (LOC+CONC)"
                       "Concessive locative: 'even when/also in' preceding element"
                       "Translation: 'even when [previous]' or 'also in [previous]'"
                       "Bialek: ན་ (locative) + འང་ (concessive)")
                  analysis))))

       ;; ========== CONCESSIVE: ཀྱང/ཡང/འང (even, also, though) ==========
       ((or (string-suffix-p "ཀྱང" word) (string-suffix-p "ཡང" word) (string-suffix-p "འང" word))
        (let* ((particle (cond ((string-suffix-p "ཀྱང" word) "ཀྱང")
                              ((string-suffix-p "འང" word) "འང")
                              (t "ཡང")))
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
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


;; ============================================================================
;; CONVERBIAL CONSTRUCTION SUMMARY (for teaching)
;; ============================================================================


(provide 'tibetan-particles-bialek)
;;; tibetan-particles-bialek.el ends here
