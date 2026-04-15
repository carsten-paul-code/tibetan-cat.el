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
(require 'tibetan-clause-segmenter nil t) ; Soft load - shared case-detection helpers
(require 'tibetan-mitra-translation nil t)  ; Optional: Gemma-2-Mitra-E integration

(declare-function tibetan-get-dharmamitra-translation "tibetan-classroom" (tibetan-text))

;; ============================================================================
;; VERB DETECTION — ROUND 1 (broader detection for compound/modal/report chains)
;; ============================================================================
;;
;; The previous extractor looked verbs up in the Hill 2010 database only,
;; which missed many classical verbs (ཁྲོས, བྱུང, ཕྲོགས, དགོས, ཟེར…) and
;; couldn't see through nominalization / converb suffixes (པས ཏེ པར བ ལ).
;; It also dropped verbs that were the head of a light-verb multiword unit
;; (ཆུང་མ་བྱེད).  The helpers below add:
;;   • A closed "minor verb" set covering common non-Hill verbs.
;;   • A modal set (དགོས ཆོག ཐུབ ཤེས ནུས སྲིད འོས) linked as auxiliary chain.
;;   • A reporting set (ཟེར གསུང གསུངས བཤད སྨྲ སྨྲས ཞུ ཞུས བརྗོད) linked as
;;     reported-speech chain.
;;   • A safe negation stripper (only fires on ma/mi + tsheg + stem, so it
;;     never mis-analyses monosyllables like མཐོང).
;;   • Progressive strip-particles so verbs wearing nominalizers / converbs
;;     (བྱུང་བ, ཁྲོས་ཏེ, ཉན་པས, ཉེན་པར…) still resolve to their lemma.

(defvar tibetan-verb-detect--modal-set
  '("དགོས" "ཆོག" "ཐུབ" "ཤེས" "ནུས" "སྲིད" "འོས")
  "Modal / auxiliary verbs that typically follow a main verb.
dgos=must, chog=may, thub=be able, shes=know-how, nus=be-able,
srid=be-possible, 'os=be-appropriate.")

(defvar tibetan-verb-detect--reporting-set
  '("ཟེར" "གསུང" "གསུངས" "བཤད" "སྨྲ" "སྨྲས" "ཞུ" "ཞུས" "བརྗོད")
  "Reporting verbs — introduce preceding clause as reported speech.")

(defvar tibetan-verb-detect--minor-verb-set
  '("ཁྲོ" "ཁྲོས" "བྱུང" "འབྱུང" "ཕྲོགས" "འཕྲོག"
    "ལེན" "བླངས" "བཞག" "འཇོག"
    "བཅད" "གཅོད" "ཤོར" "ཕུད"
    "ལྟ" "བལྟ" "སྐྱེ" "སྐྱེས" "ཤི" "འཆི"
    "གཏོང" "བཏང" "སྦྱིན" "བསྐུལ"
    "ཁས་ལེན" "ཞུགས" "འཇུག" "སླེབ" "ཕམ"
    "སྐྱིད" "དགའ" "སྡུག" "ཉམས"
    "ཉལ" "བསད" "གསོད" "ལྟུང" "འབབ"
    "ཕྱིན" "ཚོགས" "བཀུར"
    ;; biographical narrative verbs (born, died, arose, attained…)
    "བལྟམས" "སྟོན" "བཙས" "གྲུབ" "འགྲུབ"
    "ཐོབ" "འཐོབ" "རྙེད" "བཞུགས" "བཞེངས"
    "འབྱོན" "བྱོན" "གཤེགས" "གཤེགས་སོ"
    "གནང" "མཛད"
    ;; Honorific eat / drink / request — common in Milarepa narrative
    ;; (e.g. seg-14 `ཆང་གསོལ་ནས' "having drunk beer").
    "གསོལ")
  "Classical verbs not present in the Hill 2010 DB but worth detecting.
Entries produced from this set lack full case-frame data; they are
rendered as minimal verb entries so Sentence Structure still shows them.")

(defun tibetan-verb-detect--minimal-entry (word &optional meaning)
  "Minimal verb-entry alist for WORD when the Hill DB has no full record.
Compatible with the `alist-get' consumers used throughout the analyzer."
  `((lemma . ,word)
    (meaning . ,(or meaning ""))
    (present_stem . ,word)
    (past_stem . nil)
    (future_stem . nil)
    (imperative_stem . nil)
    (transitivity . "?")
    (volitionality . "?")
    (case_frame . "?")
    (indigenous_class . "?")
    (minimal . t)))

(defun tibetan-verb-detect--vocab-says-verb-p (word)
  "Return the gloss string if `tibetan-vocab-lookup-detailed' for WORD
looks like a verb (primary gloss starts with `to ', `pf.', `pres.',
`fut.', `imp.', or contains the word `verb')."
  (when (and word (fboundp 'tibetan-vocab-lookup-detailed))
    (let* ((entry (ignore-errors (tibetan-vocab-lookup-detailed word)))
           (text (and entry (or (plist-get entry :primary)
                                (plist-get entry :detailed)))))
      (when (and text (stringp text))
        (let ((case-fold-search t))
          (when (or (string-match-p "\\`[ \t\n]*to[ \t]" text)
                    (string-match-p "\\`[ \t\n]*\\(pf\\|pres\\|fut\\|ft\\|imp\\)\\."
                                    text)
                    (string-match-p "\\`[ \t\n]*verb:" text)
                    (string-match-p "\\b[Vv]erb\\b" text)
                    ;; Passive / resultative English glosses common in
                    ;; Tibetan dictionaries: "be born", "be full",
                    ;; "become X", "is/was V-ed".  Require a second word
                    ;; after `be'/`become' so bare "be" adjectives like
                    ;; "be good" still don't trip (conservative: also
                    ;; require the second word to start lowercase, which
                    ;; filters proper-noun glosses).
                    (string-match-p
                     "\\`[ \t\n]*be\\(come\\)?[ \t]+[a-z]" text))
            text))))))

(defconst tibetan-verb-detect--nominalizer-set
  '("པ" "བ" "པོ" "བོ" "མ" "མོ"
    "པའི" "བའི" "པོའི" "བོའི"
    "པར" "བར" "པས" "བས" "པའོ" "བའོ")
  "Words that are nominalisers or noun-forming enclitic particles only —
never standalone verbs.  `tibetan-verb-detect--lookup' returns nil for
these even if a vocabulary dictionary entry happens to carry verbal
glosses (P1: seg-4 regression; see test file).")

(defun tibetan-verb-detect--lookup (candidate)
  "Try to resolve CANDIDATE to a verb entry.
Search order:
 0. Reject if CANDIDATE is a bare nominaliser/enclitic particle.
 1. Hill 2010 DB (full record via `tibetan-verb-lookup').
 2. Closed minor-verb / modal / reporting set (minimal record).
 3. Vocabulary dictionary — only when the gloss looks verbal."
  (when (and candidate (stringp candidate) (not (string-empty-p candidate)))
    (let ((c (replace-regexp-in-string "[།༎༔ \t]+\\'" "" (string-trim candidate))))
      (and
       (not (member c tibetan-verb-detect--nominalizer-set))
       (or
       (and (fboundp 'tibetan-verb-lookup) (tibetan-verb-lookup c))
       (and (member c (append tibetan-verb-detect--minor-verb-set
                              tibetan-verb-detect--modal-set
                              tibetan-verb-detect--reporting-set))
            ;; Try to pull a gloss out of the vocab DB so the Sentence
            ;; Structure line reads `- ཕྲོགས 'to take away' ...' rather
            ;; than a lemma with no meaning.  Since we already know this
            ;; word is a verb (it's in our closed set), any vocab primary
            ;; field is good enough — no verbal-marker filter needed.
            (let* ((entry (and (fboundp 'tibetan-vocab-lookup-detailed)
                               (ignore-errors
                                 (tibetan-vocab-lookup-detailed c))))
                   (gloss (and entry
                               (or (plist-get entry :primary)
                                   (plist-get entry :detailed)))))
              (tibetan-verb-detect--minimal-entry c gloss)))
       (let ((gloss (tibetan-verb-detect--vocab-says-verb-p c)))
         (and gloss (tibetan-verb-detect--minimal-entry c gloss))))))))

(defun tibetan-verb-detect--strip-negation (word)
  "If WORD starts with `མ་' or `མི་' followed by at least one more syllable,
return (BARE . t).  Otherwise (WORD . nil).  The tsheg boundary is
mandatory so monosyllabic verbs (མཐོང, མི) are never mis-analysed."
  (cond
   ((and word (stringp word)
         (string-match "\\`\\(?:མ\\|མི\\)་\\(.+\\)" word))
    (cons (match-string 1 word) t))
   (t (cons word nil))))

(defun tibetan-verb-detect--progressive (word)
  "Try to locate a verb hit for WORD, stripping negation and particles.
Returns a plist (:entry E :source-form WORD :negated BOOL :suffix-type S)
or nil.  The progressive candidate list is:
  (stripped word, strip-particles once, strip-particles twice, head syllable)."
  (when (and word (stringp word) (not (string-empty-p word)))
    (let* ((orig word)
           (neg (tibetan-verb-detect--strip-negation word))
           (start (car neg))
           (negated (cdr neg))
           (candidates (list start)))
      (when (fboundp 'tibetan-strip-particles)
        (let* ((s1 (ignore-errors (tibetan-strip-particles start)))
               (s2 (and s1 (not (string= s1 start))
                        (not (string-empty-p s1))
                        (ignore-errors (tibetan-strip-particles s1)))))
          (when (and s1 (not (string= s1 start)) (not (string-empty-p s1)))
            (setq candidates (append candidates (list s1))))
          (when (and s2 (not (string= s2 s1)) (not (string-empty-p s2)))
            (setq candidates (append candidates (list s2))))))
      ;; Head syllable as last-ditch candidate (for compounds the strip
      ;; function can't reduce, like `ཆུང་མ་བྱེད').  We DON'T use the head
      ;; if a longer candidate already hit, because the head might be a
      ;; non-verb prefix (e.g. ཁས in ཁས་ལེན).
      (let ((head (car (split-string start "་" t))))
        (when (and head (not (member head candidates)))
          (setq candidates (append candidates (list head)))))
      (let (entry hit-cand)
        (catch 'found
          (dolist (c candidates)
            (let ((e (tibetan-verb-detect--lookup c)))
              (when e
                (setq entry e hit-cand c)
                (throw 'found t)))))
        (when entry
          (let ((suffix (when (fboundp 'tibetan-analysis--detect-verb-suffix)
                          (tibetan-analysis--detect-verb-suffix orig hit-cand))))
            (list :entry entry
                  :source-form orig
                  :negated negated
                  :suffix-type suffix)))))))

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
        (when (and unit (listp unit) (>= (length unit) 4))
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
                          (position . ,start-idx)
                          (distance-from-verb . ,distance)
                          (verb . ,(when verb-for-unit (alist-get 'lemma verb-for-unit)))
                          (english . ,english)
                          (gloss . ,(format "\"%s\" — agent/experiencer" (or english form)))
                          (note . nil))
                        zero-markers))
                 ((and is-immediately-preverbal trans
                       ;; Match "Transitive" but NOT "Intransitive".
                       (not (string-match-p "[Ii]ntransitive" trans))
                       (string-match-p "[Tt]ransitive" trans)
                       frame (string-match-p "Erg" frame))
                  (push `((form . ,form)
                          (function . "ABSOLUTIVE OBJECT")
                          (position . ,start-idx)
                          (distance-from-verb . ,distance)
                          (verb . ,(when verb-for-unit (alist-get 'lemma verb-for-unit)))
                          (english . ,english)
                          (gloss . ,(format "\"%s\" — patient/theme" (or english form)))
                          (note . nil))
                        zero-markers))
                 ((and is-preverbal (> distance 1))
                  (push `((form . ,form)
                          (function . "TOPIC/FOCUS")
                          (position . ,start-idx)
                          (distance-from-verb . ,distance)
                          (verb . nil)
                          (english . ,english)
                          (gloss . ,(format "\"As for %s...\"" (or english form)))
                          (note . "Establishes discourse frame"))
                        zero-markers))
                 (t
                  (when is-preverbal
                    (push `((form . ,form)
                            (function . "UNMARKED")
                            (position . ,start-idx)
                            (distance-from-verb . ,distance)
                            (verb . ,(when verb-for-unit (alist-get 'lemma verb-for-unit)))
                            (english . ,english)
                            (gloss . nil)
                            (note . "Zero-marked NP"))
                          zero-markers))))))))))
      ;; Return the collected markers
      (nreverse zero-markers))))

(defun tibetan-analyze-arguments (verb multiword-units words &optional all-verbs)
  "Analyze argument structure for VERB given MULTIWORD-UNITS and WORDS.
Returns list of argument alists with keys: role, marker, form,
english, function.
When ALL-VERBS is given, arguments are restricted to the clause ending
at VERB — i.e. only units positioned AFTER the previous verb in the
sentence and BEFORE (or at) this verb.  Without ALL-VERBS, falls back
to the legacy behaviour of collecting every unit before VERB."
  (condition-case _err
  (let* ((frame (or (alist-get 'case_frame verb) ""))
         (lemma (alist-get 'lemma verb))
         (arguments '()))

    ;; Only analyze if we have a frame
    (when (and frame (not (string-empty-p frame)) (not (string= frame "?")))

      ;; Find verb position in text.  Prefer the `source-pos' recorded by
      ;; the Round-1 extractor (authoritative — handles duplicate syllables
      ;; correctly); fall back to the first-match heuristic for callers
      ;; that still hand us plain verb records.
      (let* ((verb-pos (or (alist-get 'source-pos verb)
                           (cl-position-if (lambda (w) (string= w lemma)) words)))
             ;; Determine the previous verb's position so we only pick up
             ;; arguments belonging to *this* clause rather than the whole
             ;; preceding sentence.  Walk ALL-VERBS in order and remember
             ;; the highest lemma-position strictly less than VERB-POS.
             (prev-verb-pos
              (when (and verb-pos all-verbs)
                (let ((best -1))
                  (dolist (v all-verbs)
                    (when (and v (listp v) (consp (car v)))
                      (let* ((other-lemma (alist-get 'lemma v))
                             (other-pos (alist-get 'source-pos v))
                             (p (or other-pos
                                    (and other-lemma
                                         (not (string= other-lemma lemma))
                                         (cl-position-if
                                          (lambda (w)
                                            (string= w other-lemma))
                                          words)))))
                        (when (and p (not (equal p verb-pos))
                                   (< p verb-pos) (> p best))
                          (setq best p)))))
                  (and (>= best 0) best)))))

        ;; Analyze each multiword unit BEFORE the verb (and AFTER any
        ;; previous verb that terminates an earlier clause).
        (dolist (unit multiword-units)
          (let* ((start-idx (nth 0 unit))
                 (_end-idx (nth 1 unit))
                 (form (nth 2 unit))
                 (data (nth 3 unit))
                 (english (alist-get 'english data))
                 (before-verb (or (not verb-pos) (< start-idx verb-pos)))
                 (after-prev (or (not prev-verb-pos)
                                 (> start-idx prev-verb-pos))))

            (when (and before-verb after-prev)
              ;; Check for case markers — route through the segmenter's
              ;; case helpers so single-char `ས/ལ/ར/ན' don't get
              ;; mistaken for particles when they're the syllable's
              ;; final consonant (e.g. རྒྱལ "king" was being mis-tagged
              ;; as DATIVE because of its trailing ལ).  This is the same
              ;; standalone-only rule the Round-2 NP chunker uses; both
              ;; renderers now share one source of truth.
              (let* ((syllables (split-string form "་" t))
                     (last-syl (car (last syllables)))
                     (kase (and (fboundp 'tibetan-clause-seg--case-of)
                                (tibetan-clause-seg--case-of last-syl)))
                     (particle (and kase
                                    (fboundp 'tibetan-clause-seg--case-particle)
                                    (tibetan-clause-seg--case-particle
                                     last-syl)))
                     (marker nil)
                     (role nil)
                     (function nil)
                     (is-topic nil))

                (cond
                 ;; Ergative / Instrumental
                 ((eq kase 'ERG)
                  (setq marker particle)
                  (setq role "ERGATIVE")
                  (setq function "SUBJECT (who does)"))

                 ;; Locative
                 ((eq kase 'LOC)
                  (setq marker particle)
                  (setq role "OBLIQUE")
                  (setq function "LOCATION (where)"))

                 ;; Dative
                 ((eq kase 'DAT)
                  (setq marker particle)
                  (setq role "DATIVE")
                  (setq function "RECIPIENT/GOAL"))

                 ;; Terminative / Allative (`ར' standalone, plus `སུ/ཏུ/དུ/རུ')
                 ((eq kase 'TERM)
                  (setq marker particle)
                  (setq role "ALLATIVE")
                  (setq function "DIRECTION (toward)"))

                 ;; Ablative / Elative (`ནས', `ལས')
                 ((eq kase 'ABL)
                  (setq marker particle)
                  (setq role "ABLATIVE")
                  (setq function "SOURCE (from/after)"))

                 ;; Genitive
                 ((eq kase 'GEN)
                  (setq marker particle)
                  (setq role "GENITIVE")
                  (setq function "POSSESSOR/MODIFIER"))

                 ;; Comitative
                 ((eq kase 'COM)
                  (setq marker particle)
                  (setq role "COMITATIVE")
                  (setq function "ACCOMPANIMENT"))

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

;;;###autoload
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
             (_analysis (alist-get 'analysis parsed))
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

                            ;; Check for dative (ལ only) and terminative (ར/དུ/ཏུ/སུ) particles
                            ((and (string-match "\\(.+\\)\\(ལ\\|དུ\\|ཏུ\\|སུ\\|རུ\\|ར\\)$" word)
                                  (> (length (match-string 1 word)) 0)
                                  (not (gethash (concat word "-dat") seen-particles)))
                             (setq particles-found t)
                             (puthash (concat word "-dat") t seen-particles)
                             (let* ((base (match-string 1 word))
                                    (particle (match-string 2 word))
                                    (is-terminative (member particle '("ར" "དུ" "ཏུ" "སུ" "རུ"))))
                               (insert (format "%s (after %s)\n" particle base))
                               (if is-terminative
                                   (progn
                                     (insert "TYPE: Terminative (TERM)\n")
                                     (insert "FUNCTION: Marks goal, direction, manner, or result: 'toward X', 'into X', 'as X'\n")
                                     (insert "REFERENCE: Bialek: Terminative - NOT dative\n\n"))
                                 (progn
                                   (insert "TYPE: Dative (DAT)\n")
                                   (insert "FUNCTION: Marks recipient, indirect object, or location: 'to/for X', 'at X'\n")
                                   (insert "REFERENCE: Bialek: Dative for indirect objects and destinations\n\n")))))

                            ;; Check for standalone case particles
                            ((and (member word '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང"))
                                  (not (gethash word seen-particles)))
                             (setq particles-found t)
                             (puthash word t seen-particles)
                             (insert (format "%s\n" word))
                             (insert (format "TYPE: %s\n"
                                            (cond
                                             ((string= word "ན") "Locative (LOC)")
                                             ((string= word "ལ") "Dative (DAT)")
                                             ((member word '("ར" "སུ" "ཏུ" "དུ")) "Terminative (TERM)")
                                             ((member word '("ནས" "ལས")) "Ablative (ABL)")
                                             ((string= word "དང") "Comitative (COM)")
                                             (t "Case particle"))))
                             (insert (format "FUNCTION: %s\n"
                                            (cond
                                             ((string= word "ན") "Locative: marks location or temporal/conditional setting")
                                             ((string= word "ལ") "Dative: marks recipient, indirect object, or location")
                                             ((string= word "ར") "Terminative: marks direction, goal, manner, or result")
                                             ((string= word "སུ") "Terminative: marks direction, goal, manner, or result")
                                             ((string= word "ཏུ") "Terminative: marks direction, goal, manner, or result")
                                             ((string= word "དུ") "Terminative: marks direction, goal, manner, or result")
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
                           (base (string-join base-syllables "་"))
                           (is-terminative (member particle '("ར" "སུ" "ཏུ" "དུ"))))
                      (insert (format "%s (after %s in compound %s)\n" particle base form))
                      (insert (format "TYPE: %s (in lexical unit)\n"
                                     (cond
                                      ((string= particle "ན") "Locative (LOC)")
                                      ((string= particle "ལ") "Dative (DAT)")
                                      (is-terminative "Terminative (TERM)")
                                      ((member particle '("ནས" "ལས")) "Ablative (ABL)")
                                      ((string= particle "དང") "Comitative (COM)")
                                      (t "Case particle"))))
                      (insert (format "FUNCTION: %s\n"
                                     (cond
                                      ((string= particle "ན") "Locative: marks location or temporal/conditional setting")
                                      ((string= particle "ལ") "Dative: marks recipient, indirect object, or location")
                                      (is-terminative "Terminative: marks direction, goal, manner, or result")
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
                          (_english (alist-get 'english item)))
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
                       (arg-analysis (tibetan-analyze-arguments verb multiword-units words verbs)))
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
  "Extract verbs from TIBETAN-TEXT, compound-, particle-, and chain-aware.

Returns a list of verb-entry alists.  Each entry carries the usual
Hill 2010 fields (lemma, meaning, stems, transitivity, volitionality,
case_frame, indigenous_class) plus Round-1/Round-3 annotations:
  source-form    as-appears-in-text
  source-pos     first syllable index in WORDS (nil if unknown)
  negated        t when ma-/mi- negation applies (stripped from within
                 the form, preceding separate syllable, or intrinsic for
                 `མེད' / `མིན')
  suffix-type    morphological suffix description, or nil
  minimal        t when only a closed-set / vocab fallback gave the hit
  is-modal       t for auxiliary verbs (dgos, chog, thub…)
  is-reporter    t for reporting verbs (zer, gsungs…)
  modal-of       lemma of a following modal, when this verb chains into one
  reports-p      lemma of a following reporting verb, when chained
  conditional    t when the verb is negated AND a `ན' conditional follows
                 within 1–2 positions (pattern `མ་X་ན')

Strategy:
 1. Scan 3- and 2-syllable windows for multi-syllable Hill DB entries.
 2. For each multiword unit try progressive verb detection on the whole
    unit; if that fails, try its head-with-strip, then each constituent.
 3. For each unclaimed single syllable, try progressive detection.
 4. Link modal / reporting chains based on adjacent syllable positions.
 5. Tag conditional negations (`མ་X་ན')."
  (when (and tibetan-text
             (fboundp 'tibetan-verb-lookup)
             (not (string-empty-p tibetan-text)))
    (let* ((n (length words))
           (verbs '())
           (seen (make-hash-table :test 'equal)))
      (cl-labels
          ((pos-inside-mwu-p (pos)
             ;; t when POS sits inside a parser-detected MWU span (start
             ;; inclusive, end exclusive — the loop in
             ;; `tibetan-get-claimed-indices' uses the same convention).
             (and (numberp pos)
                  (cl-some (lambda (u)
                             (and (>= pos (nth 0 u))
                                  (< pos (nth 1 u))))
                           multiword-units)))
           (same-mwu-p (a b)
             ;; t when positions A and B both fall inside the same MWU.
             (and (numberp a) (numberp b)
                  (cl-some (lambda (u)
                             (and (>= (min a b) (nth 0 u))
                                  (< (max a b) (nth 1 u))))
                           multiword-units)))
           (prev-word-negates-p (idx)
             ;; t when words[idx-1] is a standalone `མ' or `མི' negation —
             ;; UNLESS that `མ' is part of the same MWU as the verb (e.g.
             ;; `ཆུང་མ་བྱེད', where `མ' is the noun-tail of `ཆུང་མ' "wife",
             ;; not a free negator).  Segmentation may split `མ་ཉན' into
             ;; two words, so step-wise verb detection alone misses the
             ;; negation — check siblings, but respect MWU boundaries.
             (and (numberp idx) (> idx 0)
                  (let ((prev (string-trim (nth (1- idx) words))))
                    (and (or (string= prev "མ") (string= prev "མི"))
                         (not (same-mwu-p (1- idx) idx))))))
           (intrinsic-neg-p (lemma)
             ;; `མེད' and `མིན' are inherently negated copulas; nothing
             ;; needs to precede them for the clause to be negated.
             (and lemma (or (string= lemma "མེད") (string= lemma "མིན"))))
           (record (entry source-form source-pos negated suffix)
             (let ((key (format "%s@%s" (alist-get 'lemma entry)
                                (or source-pos "-"))))
               (unless (gethash key seen)
                 (puthash key t seen)
                 (let* ((lemma (alist-get 'lemma entry))
                        (eff-negated (or negated
                                         (and (numberp source-pos)
                                              (prev-word-negates-p source-pos))
                                         (intrinsic-neg-p lemma)))
                        (is-modal (and lemma (member lemma
                                               tibetan-verb-detect--modal-set)))
                        (is-reporter (and lemma
                                          (member lemma
                                             tibetan-verb-detect--reporting-set)))
                        (enriched
                         (append entry
                                 `((source-form . ,source-form)
                                   (source-pos . ,source-pos)
                                   (negated . ,eff-negated)
                                   (suffix-type . ,suffix)
                                   (is-modal . ,(and is-modal t))
                                   (is-reporter . ,(and is-reporter t))))))
                   (push enriched verbs))))))

        ;; 1. Multi-syllable Hill-DB compound verbs.  Skip windows that
        ;; overlap any parser-detected MWU — those are handled by step 2
        ;; and treating them as candidate verbs here would produce
        ;; spurious matches inside noun compounds (e.g. `ཀློག་སློབ' inside
        ;; `ཀློག་སློབ་པའི་སློབ་དཔོན').
        (dolist (width '(3 2))
          (cl-loop
           for idx from 0 to (max -1 (- n width))
           do (let* ((overlaps-mwu
                      (cl-loop for k from idx below (+ idx width)
                               thereis (pos-inside-mwu-p k)))
                     (chunk (string-join
                             (cl-subseq words idx (+ idx width)) "་"))
                     (entry (and (not overlaps-mwu)
                                 (fboundp 'tibetan-verb-lookup)
                                 (tibetan-verb-lookup chunk))))
                (when entry (record entry chunk idx nil nil)))))

        ;; 2. Multiword units.  Verb extraction from an MWU is gated on
        ;; the MWU's metadata: an MWU is treated as verb-bearing only
        ;; when its `english' meta describes a verb (starts with `to ',
        ;; carries `pf./pres./fut./imp.', or contains `verb').  Without
        ;; this guard, noun compounds like `ཀློག་སློབ' "instructor" or
        ;; `སློབ་དཔོན' "master" would be tagged as verbs (because their
        ;; head syllable, `སློབ', happens to match a Hill-DB verb stem
        ;; `to train').  The exception path below covers MWUs that lack
        ;; useful meta but match the Hill DB as a whole compound — those
        ;; are unambiguously verbal regardless of meta wording.
        (dolist (unit multiword-units)
          (when (and unit (listp unit) (>= (length unit) 3))
            (let* ((start (nth 0 unit))
                   (form  (nth 2 unit))
                   ;; Single source of truth for "is this MWU verbal?"
                   ;; — see `tibetan-clause-seg--mwu-verbal-p'.
                   (verbal-meta-p
                    (and (fboundp 'tibetan-clause-seg--mwu-verbal-p)
                         (tibetan-clause-seg--mwu-verbal-p unit)))
                   ;; Whole-MWU Hill DB hit is unambiguous — a verb
                   ;; compound the dictionary itself recognises.
                   (whole-hit (and (fboundp 'tibetan-verb-lookup)
                                   (tibetan-verb-lookup form))))
              (cond
               (whole-hit
                (record whole-hit form start nil nil))
               (verbal-meta-p
                (let ((hit (tibetan-verb-detect--progressive form)))
                  (if hit
                      (record (plist-get hit :entry)
                              (plist-get hit :source-form)
                              start
                              (plist-get hit :negated)
                              (plist-get hit :suffix-type))
                    ;; Fallback: scan RIGHT-TO-LEFT through the MWU's
                    ;; syllables, skipping trailing converb and final
                    ;; particles (they sit AFTER the verb in head-final
                    ;; Tibetan).  Record the first syllable that
                    ;; resolves to a verb.  This handles:
                    ;;   `ཆུང་མ་བྱེད'   → `བྱེད' (last = verb)
                    ;;   `གླུ་ལེན་ཞིང'  → `ལེན' (tail ཞིང is converb)
                    ;;   `གསོལ་ནས'     → `གསོལ' (tail ནས is converb)
                    (let* ((syls (split-string form "་" t))
                           (i (1- (length syls))))
                      ;; Skip converb / sentence-final particles from
                      ;; the right — they are suffixes, never heads.
                      (while (and (>= i 0)
                                  (let ((s (nth i syls)))
                                    (or (and (fboundp 'tibetan-clause-seg--classify-word)
                                             (memq (tibetan-clause-seg--classify-word s)
                                                   '(converb final)))
                                        (member s '("ནས" "ལས")))))
                        (cl-decf i))
                      (when (>= i 0)
                        (let* ((head-syl (nth i syls))
                               (h (tibetan-verb-detect--progressive head-syl)))
                          (when h
                            (record (plist-get h :entry)
                                    (plist-get h :source-form)
                                    (+ start i)
                                    (plist-get h :negated)
                                    (plist-get h :suffix-type))))))))))
              ;; If neither path applied, the MWU is non-verbal and we
              ;; emit no verb entry for it.
              )))

        ;; 3. Single syllables not inside any multiword unit.
        ;; Cross-word negation is handled centrally inside `record' via
        ;; `prev-word-negates-p', so all three detection paths benefit.
        (let ((claimed (tibetan-get-claimed-indices multiword-units)))
          (cl-loop for idx from 0 below n
                   do (unless (gethash idx claimed)
                        (let* ((syl (string-trim (nth idx words)))
                               (h (tibetan-verb-detect--progressive syl)))
                          (when h
                            (record (plist-get h :entry)
                                    (plist-get h :source-form)
                                    idx
                                    (plist-get h :negated)
                                    (plist-get h :suffix-type)))))))

        ;; 4. Link modal / reporting chains (by adjacent source-pos).
        (setq verbs (nreverse verbs))
        (let ((lemma-at-pos (make-hash-table :test 'eql)))
          (dolist (v verbs)
            (let ((p (alist-get 'source-pos v)))
              (when p (puthash p (alist-get 'lemma v) lemma-at-pos))))
          (setq verbs
                (mapcar
                 (lambda (v)
                   (let* ((pos (alist-get 'source-pos v))
                          (candidates
                           (and pos
                                (list (gethash (1+ pos) lemma-at-pos)
                                      (gethash (+ 2 pos) lemma-at-pos)
                                      (gethash (+ 3 pos) lemma-at-pos))))
                          (modal (cl-find-if
                                  (lambda (l)
                                    (and l (member
                                            l tibetan-verb-detect--modal-set)))
                                  candidates))
                          (reporter (cl-find-if
                                     (lambda (l)
                                       (and l (member
                                               l tibetan-verb-detect--reporting-set)))
                                     candidates)))
                     (append v
                             (and modal `((modal-of . ,modal)))
                             (and reporter `((reports-p . ,reporter))))))
                 verbs)))

        ;; 5. Conditional negation (`མ་X་ན' pattern).
        ;; When a negated verb is followed by the conditional `ན' within
        ;; 1–2 syllables, tag it `(conditional . t)'. We cap the look-ahead
        ;; at 2 so an intervening suffix particle (e.g. `པར') is tolerated
        ;; but longer gaps (which usually mean a new clause) are not.
        (setq verbs
              (mapcar
               (lambda (v)
                 (let* ((pos (alist-get 'source-pos v))
                        (negated (alist-get 'negated v))
                        (followed-by-na
                         (and (numberp pos) negated
                              (cl-some
                               (lambda (k)
                                 (let ((i (+ pos k)))
                                   (and (< i n)
                                        (let ((w (string-trim (nth i words))))
                                          (or (string= w "ན")
                                              (string= w "ན་"))))))
                               '(1 2)))))
                   (if followed-by-na
                       (append v '((conditional . t)))
                     v)))
               verbs))
        verbs))))

(provide 'tibetan-enhanced-display)
;;; tibetan-enhanced-display.el ends here
