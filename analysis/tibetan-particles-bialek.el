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
                         "Bialek: Ergative for agents; Instrumental for means/instrument"
                         "Portfolio §1.3 (Ergative/Instrumental)")
                    analysis)
            ;; Standalone particle - marks previous word
            (push (list particle word "ERGATIVE/INSTRUMENTAL (ERG/INST)"
                       "Marks preceding word as AGENT or INSTRUMENT/MEANS"
                       "Translation: 'by [previous]' (agent) or 'by means of [previous]' (instrument)"
                       "Bialek: Ergative/Instrumental (standalone)"
                       "Portfolio §1.3 (Ergative/Instrumental)")
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
          (if (> (length root) 0)
              (push (list particle word "GENITIVE (GEN)"
                         (format "Marks '%s' as POSSESSOR or MODIFIER of following noun" root)
                         (format "Translation: 'of %s' or '%s's [noun]'" root root)
                         "Bialek: Genitive case for possession/modification"
                         "Portfolio §1.2 (Genitive)")
                    analysis)
            ;; Standalone genitive particle
            (push (list particle word "GENITIVE (GEN)"
                       "Marks preceding word as POSSESSOR or MODIFIER of following noun"
                       "Translation: 'of [previous]' or '[previous]'s [noun]'"
                       "Bialek: Genitive case (standalone)"
                       "Portfolio §1.2 (Genitive)")
                  analysis))))

       ;; ========== TERMINATIVE (goal, direction, manner, result) ==========
       ;; Note: ར/དུ/ཏུ/སུ are TERMINATIVE (not dative!) - marks goal/direction/manner
       ;; ལ is DATIVE - marks indirect object, location, recipient
       ;; IMPORTANT: Single-char particles ལ and ར ONLY match as standalone.
       ;; When "attached" (e.g., རྣལ ending in ལ, or འབྱོར ending in ར),
       ;; they are the final consonant of the syllable, NOT agglutinated particles.
       ;; Multi-char particles (དུ, ཏུ, སུ, རུ) can match as suffixes.
       ((or (string-suffix-p "དུ" word) (string-suffix-p "ཏུ" word)
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
                           "Bialek: Dative for indirect objects and destinations")
                         (if is-terminative
                             "Portfolio §1.5 (Terminative)"
                           "Portfolio §1.4 (Dative)"))
                    analysis)
            ;; Standalone particle
            (push (list particle word type
                       (format "Marks preceding word as %s"
                               (if is-terminative "GOAL, DIRECTION, or MANNER" "INDIRECT OBJECT or RECIPIENT"))
                       (format "Translation: '%s [previous word]'"
                               (if is-terminative "toward/into/as" "to/for/at"))
                       (if is-terminative
                           "Bialek: Terminative (standalone) - NOT dative"
                           "Bialek: Dative (standalone)")
                       (if is-terminative
                           "Portfolio §1.5 (Terminative)"
                         "Portfolio §1.4 (Dative)"))
                  analysis))))

       ;; ========== ELATIVE/ABLATIVE (source, origin, starting point) ==========
       ((or (string-suffix-p "ནས" word) (string-suffix-p "ལས" word))
        (let* ((particle (if (string-suffix-p "ནས" word) "ནས" "ལས"))
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "ELATIVE/ABLATIVE (ABL)"
                         (format "Marks '%s' as SOURCE or STARTING POINT" root)
                         (format "Translation: 'from %s' or 'after %s'" root root)
                         "Bialek: Elative for source/origin, temporal 'after'"
                         "Portfolio §1.6 (Elative/Ablative)")
                    analysis)
            ;; Standalone (common in converbs)
            (push (list particle word "ELATIVE/ABLATIVE (ABL)"
                       "Standalone ablative (often in converbial construction)"
                       "Translation: 'from/after [the preceding action]'"
                       "Bialek: Elative in converbs"
                       "Portfolio §1.6 (Elative/Ablative)")
                  analysis))))

       ;; ========== LOCATIVE + CONCESSIVE: ནའང (even when/also in) ==========
       ((or (string-suffix-p "ནའང" word) (string= "ནའང" word))
        (let* ((particle "ནའང")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "LOCATIVE+CONCESSIVE (LOC+CONC)"
                         (format "Marks '%s' with locative+concessive meaning: 'even when/also in'" root)
                         (format "Translation: 'even when %s' or 'also in %s'" root root)
                         "Bialek: ན་ (locative) + འང་ (concessive 'also/even')"
                         "Portfolio §1.7+§2.1 (Locative+Concessive)")
                    analysis)
            ;; Standalone
            (push (list particle word "LOCATIVE+CONCESSIVE (LOC+CONC)"
                       "Concessive locative: 'even when/also in' preceding element"
                       "Translation: 'even when [previous]' or 'also in [previous]'"
                       "Bialek: ན་ (locative) + འང་ (concessive)"
                       "Portfolio §1.7+§2.1 (Locative+Concessive)")
                  analysis))))

       ;; ========== LOCATIVE (location, condition) ==========
       ;; IMPORTANT: ན as single-char only matches standalone.
       ;; When "attached" (e.g., གཞན ending in ན), it's the final consonant,
       ;; NOT an agglutinated locative particle.
       ((string= "ན" word)
        (push (list "ན" word "LOCATIVE (LOC)"
                     "Marks preceding element as LOCATION or expresses CONDITION"
                     "Translation: 'in/at [previous]' or 'when [previous]'"
                     "Bialek: Locative for location or temporal condition"
                     "Portfolio §1.7 (Locative)")
              analysis))

       ;; ========== TOPIC MARKER ནི ==========
       ((or (string-suffix-p "ནི" word) (string= "ནི" word))
        (let* ((particle "ནི")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "TOPIC (TOP)"
                         (format "Marks '%s' as TOPIC - the element being commented on" root)
                         (format "Translation: 'as for %s...' or 'regarding %s...'" root root)
                         "Bialek: Topic marker for thematic focus"
                         "Portfolio §1.8 (Topic marker)")
                    analysis)
            ;; Standalone ནི
            (push (list particle word "TOPIC (TOP)"
                       "Marks preceding word/phrase as TOPIC"
                       "Translation: 'as for [previous]...' or 'regarding [previous]...'"
                       "Bialek: Topic marker (standalone)"
                       "Portfolio §1.8 (Topic marker)")
                  analysis))))

       ;; ========== COMITATIVE/ASSOCIATIVE དང ==========
       ((or (string-suffix-p "དང" word) (string= "དང" word))
        (let* ((particle "དང")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (if (> (length root) 0)
              (push (list particle word "COMITATIVE (COM)"
                         (format "Marks '%s' as accompaniment or connection" root)
                         (format "Translation: 'with %s', '%s and...', 'together with %s'" root root root)
                         "Bialek: Comitative for accompaniment/coordination"
                         "Portfolio §1.9 (Comitative)")
                    analysis)
            ;; Standalone དང
            (push (list particle word "COMITATIVE (COM)"
                       "Marks preceding word as accompaniment/coordination"
                       "Translation: 'with [previous]', '[previous] and...'"
                       "Bialek: Comitative (standalone)"
                       "Portfolio §1.9 (Comitative)")
                  analysis))))))

    ;; ========== TERMINATIVE -ར ON FINAL PIECE OF A COMPOUND ==========
    ;; Bialek's per-piece loop only matches a standalone ‘ར' — it avoids
    ;; matching ‘ར' as a suffix because in many words (འབྱོར, མར, པར …)
    ;; ‘ར' is the syllable-final consonant, not a case particle.
    ;;
    ;; The construction we DO want to catch is the one seen in Milarepa
    ;; seg-4: ཀོ་རོན་སར (“towards Ko ron sa”), where the terminative ‘ར'
    ;; attaches to the last syllable of a multi-piece compound.  The
    ;; discriminator is structural: the input has at least one tsheg,
    ;; and the last piece is a short 2-char ‘Xར' form.  Standalone
    ;; 2-char words like མར/པར/དར are unaffected because they lack the
    ;; multi-piece context.
    (when (and (stringp tibetan-text)
               (string-match-p "་" tibetan-text)
               (not (cl-some (lambda (a)
                               (let ((type (nth 2 a)))
                                 (and type (stringp type)
                                      (string-match-p "TERMINATIVE\\|DATIVE"
                                                      type))))
                             analysis)))
      (let* ((pieces (split-string
                      (replace-regexp-in-string "[།༎༏༐༑༔]" "" tibetan-text)
                      "་" t))
             (last-piece (car (last pieces))))
        (when (and last-piece
                   (= (length last-piece) 2)
                   (string-suffix-p "ར" last-piece))
          (let ((root (mapconcat #'identity (butlast pieces) "་")))
            (push (list "ར" last-piece "TERMINATIVE (ALL)"
                        (format "Marks '%s' as GOAL, DIRECTION, MANNER, or RESULT"
                                (if (string-empty-p root) last-piece root))
                        (format "Translation: 'toward/into/as %s'"
                                (if (string-empty-p root) last-piece root))
                        "Bialek: Terminative ར on final piece of a compound"
                        "Portfolio §1.5 (Terminative)")
                  analysis)))))

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
                         "Bialek: ནས་ converb - temporal sequence, most common converb"
                         "Portfolio §2.11 (V+nas): sequential action, elative converb")
                    analysis)
            ;; Standalone
            (push (list particle word "CONVERBIAL: ABLATIVE CONVERB"
                       "Standalone converb connecting to previous clause"
                       "Translation: 'and then' or 'after that'"
                       "Bialek: ནས་ converb standalone"
                       "Portfolio §2.11 (V+nas)")
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
                         "Bialek: ཏེ་/སྟེ་ converb - coordination and sequence"
                         "Portfolio §2.4 (V+ste): gerundial — temporal sequence, introductory, causal")
                    analysis)
            ;; Standalone
            (push (list particle word "CONVERBIAL: COORDINATIVE CONVERB"
                       "Standalone coordinative converb"
                       "Translation: 'and...' (continuing narrative)"
                       "Bialek: ཏེ་/སྟེ་ converb standalone"
                       "Portfolio §2.4 (V+ste)")
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
                         "Bialek: ཞིང་/ཅིང་ converb - simultaneity, accompanying action"
                         "Portfolio §2.3 (V+cing): coordinative/simultaneous converb")
                    analysis)
            ;; Standalone
            (push (list particle word "CONVERBIAL: SIMULTANEOUS CONVERB"
                       "Standalone simultaneous converb"
                       "Translation: 'and [at the same time]'"
                       "Bialek: ཞིང་/ཅིང་ converb standalone"
                       "Portfolio §2.3 (V+cing)")
                  analysis))))

       ;; ========== CAUSAL CONVERB: པས/བས (cause, reason) ==========
       ((or (string-suffix-p "པས" word) (string-suffix-p "བས" word))
        (let* ((particle (if (string-suffix-p "པས" word) "པས" "བས"))
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "CONVERBIAL: CAUSAL CONVERB"
                       (format "Causal converb: '%s' is the REASON for main verb" root)
                       (format "Translation: 'because %s' or 'since %s'" root root)
                       "Bialek: པས་/བས་ converb - cause/reason"
                       "Portfolio: see Part 1 (case suffixes) for ergative-causal constructions")
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

       ;; ========== CONDITIONAL CONVERB: ན (if/when) ==========
       ;; Note: ན as single-char particle only matches STANDALONE.
       ;; When "attached" (e.g., གཞན ending in ན), it's the final consonant.
       ;; Standalone ན after a verb stem marks conditional.
       ((and (string= "ན" word)
             ;; These are handled by their own rules above
             (not (string-suffix-p "ནས" word))
             (not (string-suffix-p "ནི" word))
             (not (string-suffix-p "ནའང" word)))
        (push (list "ན" word "CONVERBIAL: CONDITIONAL CONVERB"
                     "Conditional converb: standalone ན after verb stem"
                     "Translation: 'if [previous]' or 'when [previous]'"
                     "Bialek: ན་ converb - conditional clause (also locative in nominal contexts)"
                     "Portfolio §2.7 (V+na): conditional converb")
              analysis))

       ;; ========== V+pa dang (immediate sequence) ==========
       ((string-suffix-p "པ་དང" word)
        (let* ((particle "པ་དང")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "CONVERBIAL: IMMEDIATE SEQUENCE"
                       (format "Immediate sequence: 'as soon as %s'" root)
                       (format "Translation: 'as soon as %s-ing' or 'immediately after %s'" root root)
                       "Bialek: V+པ་དང converb - immediate temporal sequence"
                       "Portfolio §2.8 (V+pa dang): immediate sequence")
                  analysis))))

       ;; ========== V+pa la (temporal/circumstantial) ==========
       ((string-suffix-p "པ་ལ" word)
        (let* ((particle "པ་ལ")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "CONVERBIAL: TEMPORAL/CIRCUMSTANTIAL"
                       (format "Temporal/circumstantial: 'when %s' or 'upon %s'" root)
                       (format "Translation: 'when %s' or 'upon %s-ing'" root root)
                       "Bialek: V+པ་ལ converb - temporal or circumstantial"
                       "Portfolio §2.9 (V+pa la): temporal/circumstantial")
                  analysis))))

       ;; ========== V+རུང (concessive: even if) ==========
       ((string-suffix-p "རུང" word)
        (let* ((particle "རུང")
               (root (tibetan-particles-safe-substring word 0 (- (length word) (length particle)))))
          (when (> (length root) 0)
            (push (list particle word "CONVERBIAL: CONCESSIVE (RUNG)"
                       (format "Concessive converb: 'even if %s'" root)
                       (format "Translation: 'even if %s' or 'no matter whether %s'" root root)
                       "Bialek: V+རུང converb - concessive"
                       "Portfolio §2.2 (V+rung): concessive converb")
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
                       "Bialek: Concessive particle - contrast or emphasis"
                       "Portfolio §2.1 (V+kyang): concessive converb")
                  analysis))))))

    (nreverse analysis)))

;; ============================================================================
;; WORD BOUNDARY DETECTION (prevents false positives in compounds)
;; ============================================================================

(defun tibetan-tokenize-into-words (tibetan-text)
  "Tokenize TIBETAN-TEXT into word-level tokens using dictionary lookup.
Returns a list of strings, where each string may be a multi-syllable
compound (e.g., \"རྣལ་འབྱོར\") or a single syllable.
Uses greedy matching (longest match first) via the vocabulary system.

This is used to prevent the grammar analysis from incorrectly parsing
particles inside compound words (e.g., ལ in རྣལ་འབྱོར is NOT dative)."
  (let* ((cleaned (replace-regexp-in-string "[།༎༏༐༑༔]" "" tibetan-text))
         (syllables (split-string cleaned "་" t))
         (num-syllables (length syllables))
         (tokens '())
         (i 0))
    (while (< i num-syllables)
      (let ((found nil)
            (matched-len 1))
        ;; Try greedy matching: 4, 3, 2 syllable compounds first
        (cl-loop for compound-len from (min 4 (- num-syllables i)) downto 2
                 until found
                 do
                 (let* ((syls (cl-loop for j from i below (+ i compound-len)
                                       collect (string-trim (nth j syllables))))
                        (compound (mapconcat #'identity syls "་"))
                        ;; Check vocabulary lookup (comprehensive glossary)
                        (meaning (condition-case nil
                                     (when (fboundp 'tibetan-lookup-word)
                                       (tibetan-lookup-word compound))
                                   (error nil)))
                        ;; Also check detailed lookup
                        (detailed (unless meaning
                                    (condition-case nil
                                        (when (fboundp 'tibetan-vocab-lookup-detailed)
                                          (tibetan-vocab-lookup-detailed compound))
                                      (error nil)))))
                   (when (or meaning detailed)
                     (push compound tokens)
                     (setq found t)
                     (setq matched-len compound-len))))
        ;; Single syllable if no compound found
        (unless found
          (push (string-trim (nth i syllables)) tokens))
        (setq i (+ i matched-len))))
    (nreverse tokens)))

(defun tibetan--syllable-internal-p (syllable tokens)
  "Return non-nil if SYLLABLE appears only as part of a multi-syllable token.
TOKENS is the list from `tibetan-tokenize-into-words'.
A syllable is internal if it appears inside a compound but never as
a standalone token."
  (let ((is-standalone nil)
        (is-internal nil))
    (dolist (tok tokens)
      (if (string= tok syllable)
          (setq is-standalone t)
        ;; Check if syllable appears inside this multi-syllable token
        (when (string-match-p (regexp-quote syllable)
                              (replace-regexp-in-string "་" "\x00" tok))
          ;; syllable is part of a compound token
          (let ((parts (split-string tok "་" t)))
            (when (and (> (length parts) 1)
                       (member syllable parts))
              (setq is-internal t))))))
    (and is-internal (not is-standalone))))

;; ============================================================================
;; UNIFIED BIALEK ANALYSIS
;; ============================================================================

(defun tibetan-analyze-grammar-bialek (tibetan-text)
  "Complete grammar analysis using Bialek's framework.
Combines case analysis and converbial construction analysis.

False positives from single-character particles (ལ, ར, ན) inside
compound words are prevented at the source: the case and converb
analyzers only match these as standalone syllables, not as suffixes.
Multi-character particles (གྱི, དུ, ནས, སྟེ, etc.) are distinctive
enough to be reliably detected as suffixes.

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
