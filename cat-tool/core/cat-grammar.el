;;; cat-grammar.el --- Unified Tibetan grammar analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Unified grammar analysis module for Tibetan CAT.
;; Consolidates particle identification, case analysis, and converb detection.
;;
;; Based on:
;; - Bialek's "A Textbook in Classical Tibetan" (primary terminology)
;; - Schwieger's grammar (cross-references)
;; - Tibetan III class analysis (WS25-26)
;;
;; Key concepts:
;; - CASE PARTICLES: Mark grammatical roles (ergative, genitive, dative, etc.)
;; - ABSOLUTIVE: Zero-marked arguments (subjects of intransitives, objects of transitives)
;; - CONVERBS: Dependent clause markers (sequential, simultaneous, causal)
;; - NOMINALIZERS: Create nouns from verbs

;;; Code:

(require 'cl-lib)
(require 'cat-utils)

;; Optional verb classifier integration
(require 'tibetan-verb-classifier nil t)

(defvar cat-grammar-verb-classifier-available
  (featurep 'tibetan-verb-classifier)
  "Non-nil if verb classifier (Hill lexicon) is available.")

;; ============================================================================
;; GRAMMAR ANALYSIS DATA STRUCTURES
;; ============================================================================

(cl-defstruct cat-particle
  "Structure representing a detected particle."
  type        ; Symbol: 'ergative, 'genitive, 'dative, 'ablative, 'locative,
              ;         'terminative, 'elative, 'converb, 'causal, 'nominalizer,
              ;         'concessive, 'topic
  particle    ; String: the particle itself (e.g., "ཀྱིས")
  word        ; String: the full word containing the particle
  root        ; String: the root after stripping particle
  function    ; String: grammatical function description
  translation ; String: translation guidance
  reference)  ; String: textbook reference

(cl-defstruct cat-absolutive
  "Structure representing a detected absolutive (zero-marked) argument."
  word        ; String: the unmarked word
  role        ; Symbol: 'subject-intransitive, 'object-transitive,
              ;         'existential-subject, 'focus
  verb        ; String: the related verb (if identified)
  verb-info   ; Plist: verb classification from Hill lexicon
  confidence) ; Symbol: 'high, 'medium, 'low

;; ============================================================================
;; PARTICLE TYPE DEFINITIONS
;; ============================================================================

(defconst cat-grammar-particle-info
  '((ergative
     :particles ("ཀྱིས" "གྱིས" "གིས" "འིས" "ཡིས" "ས")
     :type-name "ERGATIVE (ERG)"
     :function "Marks agent of transitive/controllable verb"
     :translation "by %s; %s [does the action]"
     :reference "Bialek: Ergative case for TR/C verb subjects")

    (genitive
     :particles ("ཀྱི" "གྱི" "གི" "འི" "ཡི")
     :type-name "GENITIVE (GEN)"
     :function "Marks possessor, modifier, or links postpositional phrases"
     :translation "of %s; %s's [noun]"
     :reference "Bialek: Genitive case for possession/modification")

    (dative
     :particles ("ལ")
     :type-name "DATIVE (DAT)"
     :function "Marks recipient, possessor (with yod), or object of certain verbs"
     :translation "to %s; for %s; %s has..."
     :reference "Tibetan III: Dative for indirect objects and possession")

    (terminative
     :particles ("དུ" "ཏུ" "སུ" "རུ" "ར")
     :type-name "TERMINATIVE (TER)"
     :function "Marks direction, location, or adverbial function"
     :translation "to/in %s; %s-ward; as %s [adverb]"
     :reference "Tibetan III: Terminative for direction and location")

    (elative
     :particles ("ནས" "ལས")
     :type-name "ELATIVE (ELA)"
     :function "Marks spatial origin or starting point"
     :translation "from %s [place/source]"
     :reference "Tibetan III: Elative for spatial origin")

    (ablative-temporal
     :particles ("ནས")
     :type-name "ABLATIVE-TEMPORAL (ABL)"
     :function "After V-ing; sequential converb attached to verb"
     :translation "after %s-ing; having %s-ed"
     :reference "Tibetan III: ནས converb for temporal sequence")

    (locative
     :particles ("ན")
     :type-name "LOCATIVE (LOC)"
     :function "Marks location or expresses condition"
     :translation "in/at %s; when %s"
     :reference "Bialek: Locative for location or temporal condition")

    (converb-sequential
     :particles ("ནས")
     :type-name "CONVERB: SEQUENTIAL"
     :function "Sequential action: happens BEFORE main verb"
     :translation "having %s-ed; after %s-ing"
     :reference "Bialek: ནས converb - temporal sequence")

    (converb-coordinative
     :particles ("སྟེ" "ཏེ" "དེ")
     :type-name "CONVERB: COORDINATIVE"
     :function "Connects to following action sequentially"
     :translation "%s and...; having %s-ed"
     :reference "Bialek: ཏེ/སྟེ converb - coordination and sequence")

    (converb-simultaneous
     :particles ("ཅིང" "ཞིང" "ཤིང")
     :type-name "CONVERB: SIMULTANEOUS"
     :function "Simultaneous: happens AT SAME TIME as main verb"
     :translation "while %s-ing; %s-ing and [also]..."
     :reference "Bialek: ཞིང/ཅིང converb - simultaneity")

    (causal
     :particles ("པས" "བས")
     :type-name "CONVERB: CAUSAL"
     :function "Marks cause or reason for main verb"
     :translation "because %s; since %s"
     :reference "Bialek: པས/བས converb - cause/reason")

    (nominalizer
     :particles ("པ" "བ" "པོ" "བོ" "མ" "མོ")
     :type-name "NOMINALIZER (NMZ)"
     :function "Creates noun from verb: 'the V-ing' or 'one who V-s'"
     :translation "the %s-ing; one who %s-s"
     :reference "Bialek: Nominalization")

    (concessive
     :particles ("ཀྱང" "ཡང" "འང")
     :type-name "CONCESSIVE"
     :function "Marks concessive meaning"
     :translation "even %s; although %s; %s also"
     :reference "Bialek: Concessive particle - contrast or emphasis")

    (topic
     :particles ("ནི")
     :type-name "TOPIC MARKER"
     :function "Marks topic or establishes discourse frame"
     :translation "as for %s; regarding %s"
     :reference "Bialek: Topic marker"))
  "Particle type definitions with linguistic information.")

;; Copulas for absolutive detection
(defconst cat-grammar-copulas
  '("ཡོད" "ཡིན" "འདུག" "རེད" "བཞུགས" "ཡོད་པ" "མེད" "མིན")
  "Existential and equative copulas for absolutive detection.")

;; ============================================================================
;; CORE ANALYSIS FUNCTIONS
;; ============================================================================

(defun cat-grammar-detect-particle (word)
  "Detect any grammatical particle in WORD.
Returns a `cat-particle' struct or nil if no particle found.
Uses longest-match-first strategy."
  (catch 'found
    (dolist (type-def cat-grammar-particle-info)
      (let* ((type (car type-def))
             (info (cdr type-def))
             (particles (plist-get info :particles)))
        ;; Sort particles by length (longest first) to avoid partial matches
        (dolist (particle (sort (copy-sequence particles)
                               (lambda (a b) (> (length a) (length b)))))
          (when (and (string-suffix-p particle word)
                     ;; Ensure there's a root remaining
                     (> (length word) (length particle)))
            (let ((root (cat-safe-substring word 0 (- (length word) (length particle)))))
              (when (> (length root) 0)
                (throw 'found
                       (make-cat-particle
                        :type type
                        :particle particle
                        :word word
                        :root root
                        :function (plist-get info :function)
                        :translation (format (plist-get info :translation) root root)
                        :reference (plist-get info :reference)))))))))
    nil))

(defun cat-grammar-detect-standalone-particle (word)
  "Check if WORD is a standalone case particle.
Returns a `cat-particle' struct or nil."
  (when (member word '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང"))
    (let* ((function
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
             (t "Case particle")))
           (type (cond
                  ((member word '("ན")) 'locative)
                  ((member word '("ལ" "ར" "སུ" "ཏུ" "དུ")) 'dative)
                  ((member word '("ནས" "ལས")) 'ablative)
                  ((string= word "དང") 'comitative)
                  (t 'case-particle))))
      (make-cat-particle
       :type type
       :particle word
       :word word
       :root nil
       :function function
       :translation (format "Standalone %s" function)
       :reference "Bialek: Case particles"))))

(defun cat-grammar-get-type-name (type)
  "Get the display name for particle TYPE symbol."
  (let ((info (cdr (assq type cat-grammar-particle-info))))
    (or (plist-get info :type-name)
        (upcase (symbol-name type)))))

;; ============================================================================
;; TEXT ANALYSIS
;; ============================================================================

(defun cat-grammar-analyze-text (tibetan-text)
  "Analyze all grammatical particles in TIBETAN-TEXT.
Returns list of `cat-particle' structs."
  (let ((words (cat-segment-text tibetan-text))
        (results '())
        (seen (make-hash-table :test 'equal)))
    (dolist (word words)
      ;; Skip if already processed this exact word
      (unless (gethash word seen)
        (puthash word t seen)
        ;; Check for attached particles first
        (when-let ((particle (cat-grammar-detect-particle word)))
          (push particle results))
        ;; Then check for standalone particles
        (when-let ((standalone (cat-grammar-detect-standalone-particle word)))
          (push standalone results))))
    (nreverse results)))

(defun cat-grammar-analyze-cases (tibetan-text)
  "Analyze only case particles in TIBETAN-TEXT.
Returns list of case-related `cat-particle' structs."
  (cl-remove-if-not
   (lambda (p)
     (memq (cat-particle-type p)
           '(ergative genitive dative terminative elative ablative-temporal
             locative comitative case-particle)))
   (cat-grammar-analyze-text tibetan-text)))

(defun cat-grammar-analyze-converbs (tibetan-text)
  "Analyze only converb particles in TIBETAN-TEXT.
Returns list of converb-related `cat-particle' structs."
  (cl-remove-if-not
   (lambda (p)
     (memq (cat-particle-type p)
           '(converb-sequential converb-coordinative converb-simultaneous causal)))
   (cat-grammar-analyze-text tibetan-text)))

;; ============================================================================
;; FORMATTING FOR DISPLAY
;; ============================================================================

(defun cat-grammar-format-particle (particle)
  "Format a single PARTICLE struct for display.
Returns formatted string."
  (let* ((p-str (cat-particle-particle particle))
         (word (cat-particle-word particle))
         (root (cat-particle-root particle))
         (type-name (cat-grammar-get-type-name (cat-particle-type particle)))
         (function (cat-particle-function particle))
         (trans (cat-particle-translation particle))
         (ref (cat-particle-reference particle)))
    (concat
     (if root
         (format "%s (after %s)\n" p-str root)
       (format "%s\n" p-str))
     (format "TYPE: %s\n" type-name)
     (format "FUNCTION: %s\n" function)
     (format "TRANSLATION: %s\n" trans)
     (format "REFERENCE: %s\n" ref))))

(defun cat-grammar-format-analysis (particles)
  "Format list of PARTICLES for display output.
Returns formatted string."
  (if (null particles)
      "  [No grammatical markers detected]\n"
    (mapconcat #'cat-grammar-format-particle particles "\n")))

(defun cat-grammar-insert-analysis (tibetan-text)
  "Insert formatted grammar analysis for TIBETAN-TEXT at point."
  (let ((particles (cat-grammar-analyze-text tibetan-text)))
    (cat-insert-header "Particles & Case Markers")
    (if particles
        (dolist (p particles)
          (insert (cat-grammar-format-particle p))
          (insert "\n"))
      (insert "  [No particles detected in this segment]\n\n"))))

;; ============================================================================
;; CONVERBIAL CONSTRUCTION ANALYSIS (for teaching)
;; ============================================================================

(defun cat-grammar-summarize-converbs (tibetan-text)
  "Generate teaching summary of converbial constructions in TIBETAN-TEXT."
  (let ((converbs (cat-grammar-analyze-converbs tibetan-text)))
    (if (null converbs)
        "  [No converbial constructions detected in this segment]\n"
      (concat
       "  CONVERBIAL CONSTRUCTIONS FOUND:\n"
       (mapconcat
        (lambda (p)
          (format "    - %s: %s"
                  (cat-particle-word p)
                  (cat-particle-function p)))
        converbs
        "\n")
       "\n\n  These are DEPENDENT CLAUSES that modify the main verb!\n"))))

;; ============================================================================
;; SPECIALIZED DETECTION (for enhanced display)
;; ============================================================================

(defun cat-grammar-detect-all-in-word (word)
  "Detect all possible particle analyses for WORD.
Returns list of (type particle root) tuples for each detected particle.
Used when we want to check multiple particle types without early exit."
  (let ((results '()))
    ;; Check ergative (longer patterns first to avoid matching ས in ཀྱིས)
    (when (string-match "\\(.+\\)\\(ཀྱིས\\|གྱིས\\|གིས\\|འིས\\|ཡིས\\)$" word)
      (push (list 'ergative (match-string 2 word) (match-string 1 word)) results))
    (when (and (null results) (string-match "\\(.+\\)\\(ས\\)$" word))
      (push (list 'ergative (match-string 2 word) (match-string 1 word)) results))

    ;; Check genitive
    (when (string-match "\\(.+\\)\\(འི\\|གི\\|ཀྱི\\|ཡི\\|གྱི\\)$" word)
      (push (list 'genitive (match-string 2 word) (match-string 1 word)) results))

    ;; Check converbs
    (when (string-match "\\(.+\\)\\(ནས\\|སྟེ\\|ཏེ\\|དེ\\|ཅིང\\|ཞིང\\|ཤིང\\)$" word)
      (push (list 'converb (match-string 2 word) (match-string 1 word)) results))

    ;; Check causal
    (when (string-match "\\(.+\\)\\(པས\\|བས\\)$" word)
      (push (list 'causal (match-string 2 word) (match-string 1 word)) results))

    ;; Check nominalizer
    (when (string-match "\\(.+\\)\\(པ\\|བ\\|པོ\\|བོ\\|མ\\|མོ\\)$" word)
      (let ((root (match-string 1 word)))
        (when (> (length root) 0)
          (push (list 'nominalizer (match-string 2 word) root) results))))

    ;; Check dative (ལ only)
    (when (string-match "\\(.+\\)\\(ལ\\)$" word)
      (let ((root (match-string 1 word)))
        (when (> (length root) 0)
          (push (list 'dative (match-string 2 word) root) results))))

    ;; Check terminative (དུ/ཏུ/སུ/རུ/ར)
    (when (string-match "\\(.+\\)\\(དུ\\|ཏུ\\|སུ\\|རུ\\|ར\\)$" word)
      (let ((root (match-string 1 word)))
        (when (> (length root) 0)
          (push (list 'terminative (match-string 2 word) root) results))))

    (nreverse results)))

;; ============================================================================
;; VERB CLASSIFIER INTEGRATION
;; ============================================================================

(defun cat-grammar-get-verb-info (word)
  "Get verb classification for WORD from Hill lexicon.
Returns plist with :transitivity :volitionality :case-frame or nil."
  (when (and cat-grammar-verb-classifier-available
             (fboundp 'tibetan-verb-classify))
    (tibetan-verb-classify word)))

(defun cat-grammar-is-verb-p (word)
  "Check if WORD is a verb in the Hill lexicon."
  (when (and cat-grammar-verb-classifier-available
             (fboundp 'tibetan-verb-lookup))
    (tibetan-verb-lookup word)))

;; ============================================================================
;; ELATIVE VS ABLATIVE-TEMPORAL CLASSIFICATION
;; ============================================================================

(defun cat-grammar-classify-nas-particle (word)
  "Classify ནས particle as elative (spatial) or ablative-temporal (converb).
Returns 'elative or 'ablative-temporal based on whether root is a verb."
  (when (string-suffix-p "ནས" word)
    (let ((root (cat-safe-substring word 0 (- (length word) 2))))
      (if (and (> (length root) 0)
               (cat-grammar-is-verb-p root))
          'ablative-temporal  ; Root is a verb → converb use
        'elative))))          ; Root is not a verb → spatial origin

(defun cat-grammar-classify-las-particle (word)
  "Classify ལས particle. Usually elative (source/comparison)."
  (when (string-suffix-p "ལས" word)
    'elative))

;; ============================================================================
;; ABSOLUTIVE (ZERO MARKER) DETECTION
;; ============================================================================

(defun cat-grammar-has-case-marker-p (word)
  "Check if WORD has any overt case marker suffix.
Returns the detected particle or nil."
  (or (cat-grammar-detect-particle word)
      (cat-grammar-detect-standalone-particle word)))

(defun cat-grammar-detect-absolutives (words)
  "Detect absolutive (unmarked) arguments in WORDS list.
Returns list of `cat-absolutive' structs.

Absolutive marks:
- Subject of intransitive verbs
- Direct object of transitive verbs
- Subject of existential copulas
- Focus/topic (sentence-initial)"
  (let ((results '())
        (verbs '()))

    ;; First pass: identify all verbs in the sentence
    (dolist (word words)
      (when-let ((verb-info (cat-grammar-get-verb-info word)))
        (push (cons word verb-info) verbs)))

    ;; Second pass: identify absolutive arguments
    (let ((i 0))
      (dolist (word words)
        ;; Skip words with case markers, particles, or that are verbs/copulas
        (unless (or (cat-grammar-has-case-marker-p word)
                    (member word cat-grammar-copulas)
                    (assoc word verbs))
          ;; Check context to determine absolutive role
          (let ((role-info (cat-grammar-determine-absolutive-role
                            word i words verbs)))
            (when role-info
              (push (make-cat-absolutive
                     :word word
                     :role (nth 0 role-info)
                     :verb (nth 1 role-info)
                     :verb-info (nth 2 role-info)
                     :confidence (nth 3 role-info))
                    results))))
        (cl-incf i)))
    (nreverse results)))

(defun cat-grammar-determine-absolutive-role (word index words verbs)
  "Determine the absolutive role of unmarked WORD at INDEX in WORDS.
VERBS is an alist of (word . verb-info) for verbs in the sentence.
Returns (role verb verb-info confidence) or nil."
  (let ((following-words (nthcdr (1+ index) words))
        (preceding-words (cl-subseq words 0 index)))

    (cond
     ;; Before existential copula → existential subject
     ((cl-some (lambda (w) (member w cat-grammar-copulas)) following-words)
      (list 'existential-subject nil nil 'high))

     ;; Before intransitive verb → subject of intransitive
     ((cl-some (lambda (v)
                 (let ((vword (car v))
                       (vinfo (cdr v)))
                   (and (member vword following-words)
                        (string= (plist-get vinfo :transitivity) "Intransitive"))))
               verbs)
      (let ((verb-entry (cl-find-if
                         (lambda (v)
                           (let ((vword (car v))
                                 (vinfo (cdr v)))
                             (and (member vword following-words)
                                  (string= (plist-get vinfo :transitivity) "Intransitive"))))
                         verbs)))
        (list 'subject-intransitive (car verb-entry) (cdr verb-entry) 'high)))

     ;; Before transitive verb → likely direct object
     ((cl-some (lambda (v)
                 (let ((vword (car v))
                       (vinfo (cdr v)))
                   (and (member vword following-words)
                        (string= (plist-get vinfo :transitivity) "Transitive"))))
               verbs)
      (let ((verb-entry (cl-find-if
                         (lambda (v)
                           (let ((vword (car v))
                                 (vinfo (cdr v)))
                             (and (member vword following-words)
                                  (string= (plist-get vinfo :transitivity) "Transitive"))))
                         verbs)))
        ;; Check if there's an ergative-marked word (confirms object role)
        (let ((has-ergative (cl-some
                             (lambda (w)
                               (when-let ((p (cat-grammar-detect-particle w)))
                                 (eq (cat-particle-type p) 'ergative)))
                             words)))
          (list 'object-transitive
                (car verb-entry)
                (cdr verb-entry)
                (if has-ergative 'high 'medium)))))

     ;; Sentence-initial unmarked noun → possible focus/topic
     ((and (= index 0)
           (not (member word cat-grammar-copulas)))
      (list 'focus nil nil 'low))

     ;; Default: not enough context to determine
     (t nil))))

(defun cat-grammar-analyze-absolutives (tibetan-text)
  "Analyze absolutive arguments in TIBETAN-TEXT.
Returns list of `cat-absolutive' structs."
  (let ((words (cat-segment-text tibetan-text)))
    (cat-grammar-detect-absolutives words)))

;; ============================================================================
;; ENHANCED PARTICLE DETECTION WITH CONTEXT
;; ============================================================================

(defun cat-grammar-detect-particle-with-context (word words)
  "Detect particle in WORD with context from WORDS list.
Uses verb classifier for elative/ablative distinction.
Returns a `cat-particle' struct or nil."
  ;; First check for ནས with context-aware classification
  (if (string-suffix-p "ནས" word)
      (let* ((root (cat-safe-substring word 0 (- (length word) 2)))
             (type (cat-grammar-classify-nas-particle word))
             (info (cdr (assq type cat-grammar-particle-info))))
        (if (and info (> (length root) 0))
            (make-cat-particle
             :type type
             :particle "ནས"
             :word word
             :root root
             :function (plist-get info :function)
             :translation (format (plist-get info :translation) root root)
             :reference (plist-get info :reference))
          ;; Fall back to standard detection
          (cat-grammar-detect-particle word)))
    ;; Fall back to standard detection
    (cat-grammar-detect-particle word)))

;; ============================================================================
;; FORMATTING FOR ABSOLUTIVE DISPLAY
;; ============================================================================

(defun cat-grammar-format-absolutive (abs)
  "Format a single ABS (cat-absolutive struct) for display."
  (let ((word (cat-absolutive-word abs))
        (role (cat-absolutive-role abs))
        (verb (cat-absolutive-verb abs))
        (verb-info (cat-absolutive-verb-info abs))
        (confidence (cat-absolutive-confidence abs)))
    (concat
     (format "%s\n" word)
     (format "  CASE: ABSOLUTIVE (ABS) - zero marker\n")
     (format "  ROLE: %s\n" (cat-grammar-absolutive-role-name role))
     (when verb
       (format "  VERB: %s (%s, %s)\n"
               verb
               (or (plist-get verb-info :transitivity) "?")
               (or (plist-get verb-info :volitionality) "?")))
     (format "  CONFIDENCE: %s\n" confidence))))

(defun cat-grammar-absolutive-role-name (role)
  "Get display name for absolutive ROLE symbol."
  (pcase role
    ('subject-intransitive "Subject of intransitive verb (S)")
    ('object-transitive "Direct object of transitive verb (O)")
    ('existential-subject "Subject of existential copula")
    ('focus "Focus/Topic (sentence-initial)")
    (_ "Unmarked argument")))

(defun cat-grammar-format-absolutives (absolutives)
  "Format list of ABSOLUTIVES for display."
  (if (null absolutives)
      ""
    (concat
     "ABSOLUTIVE ARGUMENTS (Zero Marking):\n"
     (mapconcat #'cat-grammar-format-absolutive absolutives "\n"))))

(provide 'cat-grammar)
;;; cat-grammar.el ends here
