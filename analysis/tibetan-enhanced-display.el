;;; tibetan-enhanced-display.el --- Enhanced analysis display with proper segmentation -*- lexical-binding: t -*-

;;; Commentary:
;; Display analysis using enhanced parser that shows:
;; - Proper word segmentation
;; - Compound/proper noun recognition
;; - Accurate particle identification (boundaries only)
;; - Filtered verb analysis (no false positives)

;;; Code:

(require 'tibetan-enhanced-parser)
(require 'tibetan-wylie)
(require 'tibetan-verb-classifier nil t)  ; Soft load - main loading via tibetan-cat.el
(require 'tibetan-mitra-translation nil t)  ; Optional: Gemma-2-Mitra-E integration

;; ============================================================================
;; HELPER FUNCTIONS (must be defined before main display function)
;; ============================================================================

(defun tibetan-analyze-zero-markers (verbs multiword-units words)
  "Analyze zero-marked NPs to distinguish TOPIC vs. ABSOLUTIVE functions.
Returns list of zero-marker analyses with function, gloss, and notes.
Returns nil if no zero markers found or if inputs are invalid."
  (when (and verbs multiword-units)
    (let ((zero-markers '())
          (verb-positions (mapcar (lambda (v)
                                    (let ((lemma (alist-get 'lemma v)))
                                      (cl-position-if (lambda (w) (string= w lemma)) words)))
                                  verbs)))
      ;; Analyze each unmarked multiword unit
      (dolist (unit multiword-units)
        (let* ((start-idx (nth 0 unit))
               (form (nth 2 unit))
               (data (nth 3 unit))
               (english (alist-get 'english data))
               (syllables (split-string form "་" t))
               (last-syl (car (last syllables)))
               (has-marker (or (string-match "\\(ས\\|གིས\\|ཀྱིས\\|གྱིས\\)$" last-syl)
                               (string= last-syl "ན")
                               (string= last-syl "ལ")
                               (member last-syl '("ར" "སུ" "ཏུ" "དུ")))))
          (unless has-marker
            (unless (or (string-match-p "གཞན་ཡང\\|དེ་ནས\\|དེའི་ཕྱིར" form)
                        (string-match-p "པའི་ཚེ\\|པའི་དུས\\|པའི་ཕྱིར\\|པས་ན" form))
              (let* ((closest-verb-pos (cl-reduce (lambda (a b)
                                                    (if (and a b)
                                                        (if (< (abs (- start-idx a))
                                                               (abs (- start-idx b)))
                                                            a b)
                                                      (or a b)))
                                                  verb-positions
                                                  :initial-value nil))
                     (distance (when closest-verb-pos (- closest-verb-pos start-idx)))
                     (is-preverbal (and distance (> distance 0)))
                     (is-immediately-preverbal (and distance (= distance 1)))
                     (verb-for-unit (when closest-verb-pos
                                      (nth (cl-position closest-verb-pos verb-positions) verbs)))
                     (trans (when verb-for-unit (alist-get 'transitivity verb-for-unit)))
                     (frame (when verb-for-unit (alist-get 'case_frame verb-for-unit))))
                (cond
                 ((and is-immediately-preverbal trans (string-match-p "Intransitive" trans))
                  (push `((form . ,form)
                          (function . "ABSOLUTIVE SUBJECT")
                          (verb . ,(when verb-for-unit (alist-get 'lemma verb-for-unit)))
                          (english . ,english)
                          (gloss . ,(format "\"%s\" — agent/experiencer" (or english form)))
                          (note . nil))
                        zero-markers))
                 ((and is-immediately-preverbal trans (string-match-p "Transitive" trans) frame (string-match-p "Erg" frame))
                  (push `((form . ,form)
                          (function . "ABSOLUTIVE OBJECT")
                          (verb . ,(when verb-for-unit (alist-get 'lemma verb-for-unit)))
                          (english . ,english)
                          (gloss . ,(format "\"%s\" — patient/theme" (or english form)))
                          (note . nil))
                        zero-markers))
                 ((and is-preverbal (> distance 1))
                  (push `((form . ,form)
                          (function . "TOPIC/FOCUS")
                          (verb . nil)
                          (english . ,english)
                          (gloss . ,(format "\"As for %s...\"" (or english form)))
                          (note . "Establishes discourse frame"))
                        zero-markers))
                 (t
                  (when is-preverbal
                    (push `((form . ,form)
                            (function . "UNMARKED")
                            (verb . ,(when verb-for-unit (alist-get 'lemma verb-for-unit)))
                            (english . ,english)
                            (gloss . nil)
                            (note . "Zero-marked NP"))
                          zero-markers)))))))))
      ;; Return the collected markers
      (nreverse zero-markers))))

(defun tibetan-analyze-arguments (verb multiword-units words)
  "Analyze argument structure for VERB given MULTIWORD-UNITS and WORDS.
Returns list of argument alists with keys: role, marker, form, english, function."
  (condition-case err
  (let* ((frame (or (alist-get 'case_frame verb) ""))
         (lemma (alist-get 'lemma verb))
         (arguments '()))

    ;; Only analyze if we have a frame
    (when (and frame (not (string-empty-p frame)) (not (string= frame "?")))

      ;; Find verb position in text (approximate by finding lemma in words)
      (let ((verb-pos (cl-position-if (lambda (w) (string= w lemma)) words)))

        ;; Analyze each multiword unit BEFORE the verb
        (dolist (unit multiword-units)
          (let* ((start-idx (nth 0 unit))
                 (end-idx (nth 1 unit))
                 (form (nth 2 unit))
                 (data (nth 3 unit))
                 (english (alist-get 'english data))
                 ;; Check if unit is before verb (or no verb position found)
                 (before-verb (or (not verb-pos) (< start-idx verb-pos))))

            (when before-verb
              ;; Check for case markers
              (let* ((syllables (split-string form "་" t))
                     (last-syl (car (last syllables)))
                     (marker nil)
                     (role nil)
                     (function nil)
                     (is-topic nil))

                (cond
                 ;; Check for ergative
                 ((string-match "\\(ས\\|གིས\\|ཀྱིས\\|གྱིས\\)$" last-syl)
                  (setq marker (match-string 1 last-syl))
                  (setq role "ERGATIVE")
                  (setq function "SUBJECT (who does)"))

                 ;; Check for locative/oblique
                 ((or (string= last-syl "ན")
                      (string-match "ན$" last-syl))
                  (setq marker "ན")
                  (setq role "OBLIQUE")
                  (setq function "LOCATION (where)"))

                 ;; Check for dative
                 ((or (string= last-syl "ལ")
                      (string-match "ལ$" last-syl))
                  (setq marker "ལ")
                  (setq role "DATIVE")
                  (setq function "RECIPIENT/GOAL"))

                 ;; Check for allative
                 ((member last-syl '("ར" "སུ" "ཏུ" "དུ"))
                  ;; Standalone allative particle - use directly
                  (setq marker last-syl)
                  (setq role "ALLATIVE")
                  (setq function "DIRECTION (toward)"))

                 ;; Check for allative suffix on longer word
                 ((string-match "\\(ར\\|སུ\\|ཏུ\\|དུ\\)$" last-syl)
                  (setq marker (match-string 1 last-syl))
                  (setq role "ALLATIVE")
                  (setq function "DIRECTION (toward)"))

                 ;; No marker = absolutive candidate (or topic)
                 (t
                  (setq marker "Ø")
                  ;; Check distance from verb to determine if topic or argument
                  (let ((distance (when verb-pos (- verb-pos start-idx))))
                    (setq is-topic (and distance (> distance 1))) ; Separated by other constituents = topic

                    (if is-topic
                        ;; It's a topic, not an argument
                        (progn
                          (setq role "TOPIC")
                          (setq function "TOPIC/FOCUS (not verb argument)"))
                      ;; It's an absolutive argument
                      (setq role "ABSOLUTIVE")
                      ;; Function depends on verb transitivity
                      (let ((trans (alist-get 'transitivity verb)))
                        (cond
                         ((and trans (string-match-p "Intransitive" trans))
                          (setq function "SUBJECT (who/what)"))
                         ((and trans (string-match-p "Transitive" trans))
                          ;; Check if frame has ergative - if so, absolutive = object
                          (if (string-match-p "Erg" frame)
                              (setq function "OBJECT (what)")
                            (setq function "SUBJECT (who)")))
                         (t
                          (setq function "SUBJECT/OBJECT"))))))))

                ;; Add to arguments list (all cases, marked or not)
                (push `((role . ,role)
                       (marker . ,marker)
                       (form . ,form)
                       (english . ,english)
                       (function . ,function)
                       (is-topic . ,is-topic))
                      arguments)))))))

    (nreverse arguments))
    (error nil)))

;; ============================================================================
;; ENHANCED SEGMENT ANALYSIS DISPLAY
;; ============================================================================

(defun tibetan-segment-info-enhanced (&optional silent)
  "Show enhanced segment analysis.
Uses compound/proper noun recognition and accurate particle detection.
If SILENT is non-nil, return nil instead of error when not in segment."
  (interactive)
  (let* ((seg-data (tibetan-get-current-segment-any-format))
         (seg-id (car seg-data))
         (tibetan-text (cdr seg-data)))

    (if (not seg-data)
        (unless silent
          (error "Not in a segment"))

      ;; We have segment data - perform enhanced analysis
      (let* ((buffer (get-buffer-create "*Segment Info Enhanced*"))
             ;; Enhanced parsing
             (parsed (tibetan-parse-enhanced tibetan-text))
             (words (alist-get 'words parsed))
             (analysis (alist-get 'analysis parsed))
             (multiword-units (alist-get 'multiword-units parsed))
             ;; Wylie
             (wylie (condition-case err
                        (if (fboundp 'tibetan-to-wylie-fixed)
                            (tibetan-to-wylie-fixed tibetan-text)
                          "[Wylie converter not loaded]")
                      (error (format "[Wylie error: %s]" (error-message-string err)))))
             ;; Verb analysis (compound-aware)
             (verbs (tibetan-extract-verbs-compound-aware tibetan-text words multiword-units))
             ;; DEBUG: Check what verbs contains
             (_ (message "DEBUG verbs: %S" verbs))
             ;; DharmaMitra translation
             (translation (tibetan-get-dharmamitra-translation tibetan-text)))

        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)

            ;; Header
            (insert "╔══════════════════════════════════════════════════════════════╗\n")
            (insert "║         SEGMENT ANALYSIS - ENHANCED                          ║\n")
            (insert "╚══════════════════════════════════════════════════════════════╝\n\n")
            (insert (format "Segment: %s\n\n" seg-id))

            ;; Tibetan text
            (insert "TIBETAN TEXT:\n")
            (insert tibetan-text)
            (insert "\n\n")

            ;; Wylie
            (insert "WYLIE:\n")
            (insert wylie)
            (insert "\n\n")

            ;; Segmentation (compound-aware)
            (insert "SEGMENTATION:\n")
            (let ((segments (tibetan-build-compound-aware-segments words multiword-units)))
              (insert (string-join segments " | ")))
            (insert "\n")
            (tibetan-insert-separator)
            (insert "\n")

            ;; Lexical units (compounds & proper nouns)
            (when multiword-units
              (insert "LEXICAL UNITS:\n")
              (tibetan-insert-separator)
              (dolist (unit multiword-units)
                (let* ((form (nth 2 unit))
                       (data (nth 3 unit))
                       (wylie-val (alist-get 'wylie data))
                       (english (alist-get 'english data))
                       (sanskrit (alist-get 'sanskrit data))
                       (category (alist-get 'category data))
                       ;; Generate Wylie if not in data
                       (wylie-display (or wylie-val
                                         (when (fboundp 'tibetan-to-wylie-fixed)
                                           (tibetan-to-wylie-fixed form))
                                         "?")))
                  (insert (format "%s [%s]\n" form wylie-display))
                  (let ((cat-display (if category
                                         (capitalize (replace-regexp-in-string "_" " " category))
                                       "Vocabulary")))
                    (insert (format "TYPE: %s\n" cat-display)))
                  (insert (format "MEANING: %s\n" (or english "?")))
                  (when sanskrit
                    (insert (format "SANSKRIT: %s\n" sanskrit)))
                  (insert "\n")))
              (tibetan-insert-separator)
              (insert "\n"))

            ;; Particles & case markers (compound-aware)
            (insert "PARTICLES & CASE MARKERS:\n")
            (tibetan-insert-separator)
            (let ((particles-found nil)
                  (claimed-indices (tibetan-get-claimed-indices multiword-units))
                  (seen-particles (make-hash-table :test 'equal)))

              ;; PASS 1: Check each FREE syllable (not in compounds) for particles
              (cl-loop for idx from 0 below (length words)
                       unless (gethash idx claimed-indices)
                       do (let ((word (nth idx words)))
                           (cond
                            ;; Check for ergative particles (agent markers)
                            ((and (string-match "\\(.+\\)\\(ཀྱིས\\|གྱིས\\|གིས\\|འིས\\|ཡིས\\|ས\\)$" word)
                                  (not (gethash (concat word "-erg") seen-particles)))
                             (setq particles-found t)
                             (puthash (concat word "-erg") t seen-particles)
                             (let ((base (match-string 1 word))
                                   (particle (match-string 2 word)))
                               (insert (format "%s (after %s)\n" particle base))
                               (insert "TYPE: Ergative (ERG)\n")
                               (insert "FUNCTION: Marks agent of transitive/controllable verb\n")
                               (insert "REFERENCE: Bialek: Ergative case for TR/C verb subjects\n\n")))

                            ;; Check for genitive particles
                            ((and (string-match "\\(.+\\)\\(འི\\|གི\\|ཀྱི\\|ཡི\\|གྱི\\)$" word)
                                  (not (gethash (concat word "-gen") seen-particles)))
                             (setq particles-found t)
                             (puthash (concat word "-gen") t seen-particles)
                             (let ((base (match-string 1 word))
                                   (particle (match-string 2 word)))
                               (insert (format "%s (after %s)\n" particle base))
                               (insert "TYPE: Genitive (GEN)\n")
                               (insert "FUNCTION: Marks possessor or modifier\n")
                               (insert "REFERENCE: Bialek: Genitive for possession/modification\n\n")))

                            ;; Check for converb particles (attached)
                            ((and (string-match "\\(.+\\)\\(ནས\\|སྟེ\\|ཏེ\\|དེ\\|ཅིང\\|ཞིང\\|ཤིང\\)$" word)
                                  (not (gethash (concat word "-conv") seen-particles)))
                             (setq particles-found t)
                             (puthash (concat word "-conv") t seen-particles)
                             (let ((base (match-string 1 word))
                                   (particle (match-string 2 word)))
                               (insert (format "%s (after %s)\n" particle base))
                               (insert "TYPE: Converb\n")
                               (insert (format "FUNCTION: %s\n"
                                              (cond
                                               ((string= particle "ནས") "Sequential: 'having V-ed' or 'after V-ing'")
                                               ((member particle '("སྟེ" "ཏེ" "དེ")) "Coordinative: 'V-ing and...' or 'having V-ed'")
                                               ((member particle '("ཅིང" "ཞིང" "ཤིང")) "Simultaneous: 'while V-ing'")
                                               (t "Converb connector"))))
                               (insert "REFERENCE: Bialek: Converbial constructions\n\n")))

                            ;; Check for causal converb particles
                            ((and (string-match "\\(.+\\)\\(པས\\|བས\\)$" word)
                                  (not (gethash (concat word "-causal") seen-particles)))
                             (setq particles-found t)
                             (puthash (concat word "-causal") t seen-particles)
                             (let ((base (match-string 1 word))
                                   (particle (match-string 2 word)))
                               (insert (format "%s (after %s)\n" particle base))
                               (insert "TYPE: Causal Converb\n")
                               (insert "FUNCTION: Marks cause/reason: 'because V' or 'since V'\n")
                               (insert "REFERENCE: Bialek: Causal converb\n\n")))

                            ;; Check for nominalizer particles
                            ((and (string-match "\\(.+\\)\\(པ\\|བ\\|པོ\\|བོ\\|མ\\|མོ\\)$" word)
                                  (> (length (match-string 1 word)) 0)
                                  (not (gethash (concat word "-nmz") seen-particles)))
                             (setq particles-found t)
                             (puthash (concat word "-nmz") t seen-particles)
                             (let ((base (match-string 1 word))
                                   (particle (match-string 2 word)))
                               (insert (format "%s (after %s)\n" particle base))
                               (insert "TYPE: Nominalizer (NMZ)\n")
                               (insert "FUNCTION: Creates noun from verb: 'the V-ing' or 'one who V-s'\n")
                               (insert "REFERENCE: Bialek: Nominalization\n\n")))

                            ;; Check for dative/allative particles (attached)
                            ((and (string-match "\\(.+\\)\\(ལ\\|དུ\\|ཏུ\\|སུ\\|རུ\\|ར\\)$" word)
                                  (> (length (match-string 1 word)) 0)
                                  (not (gethash (concat word "-dat") seen-particles)))
                             (setq particles-found t)
                             (puthash (concat word "-dat") t seen-particles)
                             (let ((base (match-string 1 word))
                                   (particle (match-string 2 word)))
                               (insert (format "%s (after %s)\n" particle base))
                               (insert "TYPE: Dative/Allative (DAT)\n")
                               (insert "FUNCTION: Marks goal, recipient, or direction: 'to X', 'toward X'\n")
                               (insert "REFERENCE: Bialek: Dative for indirect objects and destinations\n\n")))

                            ;; Check for standalone case particles
                            ((and (member word '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང"))
                                  (not (gethash word seen-particles)))
                             (setq particles-found t)
                             (puthash word t seen-particles)
                             (insert (format "%s\n" word))
                             (insert "TYPE: Case particle\n")
                             (insert (format "FUNCTION: %s\n"
                                            (cond
                                             ((string= word "ན") "Locative: marks location or temporal/conditional setting")
                                             ((string= word "ལ") "Dative-locative: marks recipient, goal, or location")
                                             ((string= word "ར") "Allative: marks direction or goal")
                                             ((string= word "སུ") "Allative: marks direction or goal")
                                             ((string= word "ཏུ") "Allative: marks direction or goal")
                                             ((string= word "དུ") "Allative: marks direction or goal")
                                             ((string= word "ནས") "Ablative/converb: marks source or 'after V-ing'")
                                             ((string= word "ལས") "Ablative: marks source, origin, or comparison")
                                             ((string= word "དང") "Comitative/connective: 'with' or 'and'")
                                             (t "Case marker"))))
                             (insert "\n")))))

              ;; PASS 2: Check lexical units for embedded particles
              ;; (e.g., མཉན་ཡོད་ན has ན, པའི་ཚེ has འི in པའི)
              (dolist (unit multiword-units)
                (let* ((form (nth 2 unit))
                       (syllables (split-string form "་" t)))
                  ;; Check if compound ends with a case particle
                  (when (and (> (length syllables) 1)
                            (member (car (last syllables)) '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང")))
                    (setq particles-found t)
                    (let* ((particle (car (last syllables)))
                           (base-syllables (butlast syllables))
                           (base (string-join base-syllables "་")))
                      (insert (format "%s (after %s in compound %s)\n" particle base form))
                      (insert "TYPE: Case particle (in lexical unit)\n")
                      (insert (format "FUNCTION: %s\n"
                                     (cond
                                      ((string= particle "ན") "Locative: marks location or temporal/conditional setting")
                                      ((string= particle "ལ") "Dative-locative: marks recipient, goal, or location")
                                      ((string= particle "ར") "Allative: marks direction or goal")
                                      ((string= particle "སུ") "Allative: marks direction or goal")
                                      ((string= particle "ཏུ") "Allative: marks direction or goal")
                                      ((string= particle "དུ") "Allative: marks direction or goal")
                                      ((string= particle "ནས") "Ablative/converb: marks source or 'after V-ing'")
                                      ((string= particle "ལས") "Ablative: marks source, origin, or comparison")
                                      ((string= particle "དང") "Comitative/connective: 'with' or 'and'")
                                      (t "Case marker"))))
                      (insert "\n")))
                  ;; Check ALL syllables for genitive particles (not just last)
                  ;; (e.g., པའི in པའི་ཚེ)
                  (dolist (syl syllables)
                    (when (string-match "\\(.+\\)\\(འི\\|གི\\|ཀྱི\\|ཡི\\|གྱི\\)$" syl)
                      (setq particles-found t)
                      (let* ((base-in-syl (match-string 1 syl))
                             (particle (match-string 2 syl)))
                        (insert (format "%s (after %s in compound %s)\n" particle base-in-syl form))
                        (insert "TYPE: Genitive (GEN) (in lexical unit)\n")
                        (insert "FUNCTION: Marks possessor or modifier\n")
                        (insert "REFERENCE: Bialek: Genitive for possession/modification\n\n"))))))

              (unless particles-found
                (insert "  [No particles detected in this segment]\n\n"))
              (tibetan-insert-separator)
              (insert "\n"))

            ;; Verb analysis (filtered)
            (when verbs
              (insert "VERB ANALYSIS (Hill 2010):\n")
              (tibetan-insert-separator)
              (dolist (verb verbs)
                ;; Skip if verb is not a proper alist
                (when (and verb (listp verb) (consp (car verb)))
                  (let* ((lemma (alist-get 'lemma verb))
                       (present (or (alist-get 'present_stem verb) "—"))
                       (past (or (alist-get 'past_stem verb) "—"))
                       (future (or (alist-get 'future_stem verb) "—"))
                       (imperative (or (alist-get 'imperative_stem verb) "—"))
                       (vol (or (alist-get 'volitionality verb) "?"))
                       (trans (or (alist-get 'transitivity verb) "?"))
                       (frame (or (alist-get 'case_frame verb) "?"))
                       (class (or (alist-get 'indigenous_class verb) "?"))
                       (meaning (alist-get 'meaning verb))
                       ;; Map volitionality to controllability (Schwieger/Bialek terminology)
                       (controllable (cond
                                     ((string= vol "Voluntary") "Controllable")
                                     ((string= vol "Involuntary") "Uncontrollable")
                                     ((string= vol "Both") "Context-dependent")
                                     (t "?"))))
                  (insert (format "%s" lemma))
                  (when meaning (insert (format " - %s" meaning)))
                  (insert "\n")
                  (insert (format "STEMS: %s / %s / %s / %s\n" present past future imperative))
                  (insert (format "VOLITIONALITY: %s\n" vol))
                  (insert (format "CONTROLLABILITY: %s (Schwieger/Bialek)\n" controllable))
                  (insert (format "TRANSITIVITY: %s\n" trans))
                  (insert (format "ARGUMENT FRAME: %s\n" frame))
                  (insert (format "TIBETAN CLASS: %s\n"
                                 (cond
                                  ((string= class "tha_dad_pa") "ཐ་དད་པ་ (tha dad pa - transitive)")
                                  ((string= class "tha_mi_dad_pa") "ཐ་མི་དད་པ་ (tha mi dad pa - intransitive)")
                                  (t "—"))))
                  (insert "\n"))))
              (tibetan-insert-separator)
              (insert "\n"))

            ;; Zero marker analysis (topic vs. absolutive)
            (message "DEBUG: About to call tibetan-analyze-zero-markers")
            (when verbs
              (message "DEBUG: Calling tibetan-analyze-zero-markers with verbs=%S" verbs)
              (let ((zero-analysis (tibetan-analyze-zero-markers verbs multiword-units words)))
                (message "DEBUG: zero-analysis returned: %S" zero-analysis)
                (when zero-analysis
                  (insert "ZERO MARKER ANALYSIS:\n")
                  (tibetan-insert-separator)
                  (dolist (item zero-analysis)
                    (let ((form (alist-get 'form item))
                          (function (alist-get 'function item))
                          (gloss (alist-get 'gloss item))
                          (note (alist-get 'note item))
                          (verb (alist-get 'verb item))
                          (english (alist-get 'english item)))
                      (insert (format "%s (Ø)\n" form))
                      (insert (format "FUNCTION: %s\n" function))
                      (when verb
                        (insert (format "VERB: %s\n" verb)))
                      (when gloss
                        (insert (format "GLOSS: %s\n" gloss)))
                      (when note
                        (insert (format "NOTE: %s\n" note)))
                      (insert "\n")))
                  (tibetan-insert-separator)
                  (insert "\n"))))

            ;; Argument structure analysis (only verb arguments, not topics)
            (when verbs
              (insert "ARGUMENT STRUCTURE:\n")
              (tibetan-insert-separator)
              (dolist (verb verbs)
                (let* ((lemma (alist-get 'lemma verb))
                       (frame (or (alist-get 'case_frame verb) "?"))
                       (meaning (alist-get 'meaning verb))
                       ;; Analyze argument structure (excludes topics)
                       (arg-analysis (tibetan-analyze-arguments verb multiword-units words)))
                  (when arg-analysis
                    (insert (format "%s [%s]" lemma frame))
                    (when meaning
                      (insert (format " \"%s\"" (car (split-string meaning "," t)))))
                    (insert "\n")
                    ;; Display each argument (only actual arguments, not topics)
                    (dolist (arg arg-analysis)
                      (let ((role (alist-get 'role arg))
                            (marker (alist-get 'marker arg))
                            (form (alist-get 'form arg))
                            (english (alist-get 'english arg))
                            (function (alist-get 'function arg))
                            (is-topic (alist-get 'is-topic arg)))
                        ;; Only display if NOT a topic
                        (unless is-topic
                          (insert (format "  • %s (%s): %s"
                                         role
                                         (if (string= marker "Ø") "Ø" marker)
                                         form))
                          (when english
                            (insert (format " \"%s\"" english)))
                          (when function
                            (insert (format " — %s" function)))
                          (insert "\n"))))
                    (insert "\n"))))
              (tibetan-insert-separator)
              (insert "\n"))

            ;; Working Translation (generated from vocabulary)
            (insert "WORKING TRANSLATION:\n")
            (tibetan-insert-separator)
            (let* ((segments (tibetan-build-compound-aware-segments words multiword-units))
                   (gloss-pairs '())
                   (content-words '())
                   ;; Particles to skip in translation
                   (particles '("ནི" "ཡང" "གི" "ཀྱི" "འི" "ཡི" "གྱི" "ལ" "ན" "དུ" "སུ" "ར" "ས" "ནས" "ལས" "དང")))

              ;; Build gloss pairs
              (dolist (seg segments)
                (let ((meaning
                       (or (let ((unit (cl-find-if (lambda (u) (string= (nth 2 u) seg))
                                                   multiword-units)))
                            (when unit
                              (alist-get 'english (nth 3 unit))))
                           (when (boundp 'tibetan-comprehensive-vocabulary)
                             (gethash seg tibetan-comprehensive-vocabulary)))))
                  (push (cons seg (or meaning "?")) gloss-pairs)))
              (setq gloss-pairs (nreverse gloss-pairs))

              ;; Build content words (skip particles and unknown)
              (dolist (pair gloss-pairs)
                (let ((tib (car pair))
                      (eng (cdr pair)))
                  (unless (or (string= eng "?")
                              (string= eng "")
                              (member tib particles))
                    ;; Clean up - take first meaning
                    (when (string-match "^\\([^,;]+\\)" eng)
                      (setq eng (string-trim (match-string 1 eng))))
                    (push eng content-words))))
              (setq content-words (nreverse content-words))

              ;; Build translation
              (let ((trans-text (string-join content-words " ")))
                ;; Add verb meaning if available
                (when (and verbs (car verbs))
                  (let* ((main-verb (car verbs))
                         (verb-meaning (when (and (listp main-verb) (consp (car main-verb)))
                                        (car (split-string (or (alist-get 'meaning main-verb) "") "," t)))))
                    (when (and verb-meaning
                               (not (cl-some (lambda (w) (string-match-p (regexp-quote verb-meaning) w))
                                             content-words)))
                      (setq trans-text (concat trans-text " " verb-meaning)))))
                ;; Capitalize first letter if ASCII
                (when (and (> (length trans-text) 0)
                           (string-match "^[a-z]" trans-text))
                  (setq trans-text (concat (upcase (substring trans-text 0 1))
                                          (substring trans-text 1))))
                (if (> (length trans-text) 0)
                    (insert (format "\"%s\"\n" trans-text))
                  (insert "[Could not generate translation - check vocabulary]\n"))))
            (insert "\n")
            (tibetan-insert-separator)
            (insert "\n")

            ;; DharmaMitra translation
            (insert "DHARMAMITRA TRANSLATION:\n")
            (tibetan-insert-separator)
            (insert (or translation "[Not available]"))
            (insert "\n\n")
            (tibetan-insert-separator)
            (insert "\n")

            ;; Mitra AI translation (if available)
            (when (fboundp 'tibetan-mitra-translate)
              (insert "MITRA AI TRANSLATION (Gemma-2-Mitra-E):\n")
              (tibetan-insert-separator)
              (let ((mitra-translation
                     (condition-case err
                         (tibetan-mitra-translate tibetan-text)
                       (error (format "[Error: %s]" (error-message-string err))))))
                (insert (or mitra-translation "[Not configured - see M-x tibetan-mitra-setup-ollama]")))
              (insert "\n\n")
              (tibetan-insert-separator)
              (insert "\n"))

            ;; Word-by-word gloss (compound-aware)
            (insert "WORD-BY-WORD GLOSS:\n")
            (tibetan-insert-separator)
            (let ((segments (tibetan-build-compound-aware-segments words multiword-units)))
              (dolist (seg segments)
                (let ((meaning
                       ;; Check if it's a compound first
                       (or (let ((unit (cl-find-if (lambda (u) (string= (nth 2 u) seg))
                                                   multiword-units)))
                            (when unit
                              (alist-get 'english (nth 3 unit))))
                           ;; Otherwise lookup as regular word
                           (when (boundp 'tibetan-comprehensive-vocabulary)
                             (gethash seg tibetan-comprehensive-vocabulary)))))
                  (insert (format "%s = %s\n" seg (or meaning "[look up]"))))))
            (insert "\n")
            (tibetan-insert-separator)
            (insert "\n\n")

            (insert "[Press q to close]\n")

            (goto-char (point-min))
            (view-mode 1)))

        ;; Display buffer
        (let ((analysis-window (get-buffer-window "*Segment Info Enhanced*"))
              (source-window (selected-window)))
          (if analysis-window
              (progn
                (set-window-buffer analysis-window buffer)
                (select-window source-window))
            (progn
              (unless (get-buffer-window "*Sentence Workspace*")
                (delete-other-windows))
              (let ((new-window (split-window source-window nil 'right)))
                (set-window-buffer new-window buffer)
                (select-window source-window)))))

        (message "Segment %s - Enhanced analysis on right" seg-id)))))

;; ============================================================================
;; HELPER FUNCTIONS
;; ============================================================================

(defun tibetan-build-compound-aware-segments (words multiword-units)
  "Build segmentation list showing compounds as units.
WORDS is the raw syllable list, MULTIWORD-UNITS are recognized compounds.
Returns list of strings for display."
  (let ((segments '())
        (i 0)
        (claimed-indices (make-hash-table :test 'equal)))

    ;; Mark indices that belong to compounds
    (dolist (unit multiword-units)
      (cl-loop for idx from (nth 0 unit) below (nth 1 unit)
               do (puthash idx t claimed-indices)))

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

(defun tibetan-get-claimed-indices (multiword-units)
  "Get set of syllable indices that are part of compounds.
Returns hash table for fast lookup."
  (let ((claimed (make-hash-table :test 'equal)))
    (dolist (unit multiword-units)
      (cl-loop for idx from (nth 0 unit) below (nth 1 unit)
               do (puthash idx t claimed)))
    claimed))

(defun tibetan-extract-verbs-compound-aware (tibetan-text words multiword-units)
  "Extract and analyze verbs from TIBETAN-TEXT, excluding multi-word compound parts.
WORDS is the syllable list, MULTIWORD-UNITS are recognized compounds.
Checks both single syllables AND multi-syllable compound verbs."
  (when (and tibetan-text
             (fboundp 'tibetan-verb-lookup)
             (not (string-empty-p tibetan-text)))
    (let ((verbs '())
          (claimed-indices (tibetan-get-claimed-indices multiword-units)))

      ;; First, check for multi-syllable compound verbs (e.g., བཀའ་སྩལ)
      (cl-loop for idx from 0 below (1- (length words))
               do (let* ((two-syl (string-join (cl-subseq words idx (+ idx 2)) "་"))
                        (verb-entry (tibetan-verb-lookup two-syl)))
                    (when verb-entry
                      (let ((lemma (alist-get 'lemma verb-entry)))
                        (unless (cl-find lemma verbs
                                        :key (lambda (v) (alist-get 'lemma v))
                                        :test 'string=)
                          (push verb-entry verbs))))))

      ;; Then check each single syllable NOT in a TRUE multi-word compound
      (cl-loop for idx from 0 below (length words)
               do (let* ((syl (nth idx words))
                        (syl-clean (string-trim syl))
                        ;; Check if this syllable is part of a multi-word unit
                        (in-multiword (and (gethash idx claimed-indices)
                                          (cl-some (lambda (unit)
                                                    (and (>= idx (nth 0 unit))
                                                         (< idx (nth 1 unit))
                                                         ;; Only skip if TRUE compound (length > 1)
                                                         (> (- (nth 1 unit) (nth 0 unit)) 1)))
                                                  multiword-units))))
                   ;; Only check for verbs if NOT in a multi-word compound
                   (unless in-multiword
                     (when (not (string-empty-p syl-clean))
                       (let ((verb-entry (tibetan-verb-lookup syl-clean)))
                         (when verb-entry
                           ;; Avoid duplicates by lemma
                           (let ((lemma (alist-get 'lemma verb-entry)))
                             (unless (cl-find lemma verbs
                                            :key (lambda (v) (alist-get 'lemma v))
                                            :test 'string=)
                               (push verb-entry verbs)))))))))
      (nreverse verbs))))

(provide 'tibetan-enhanced-display)
;;; tibetan-enhanced-display.el ends here
