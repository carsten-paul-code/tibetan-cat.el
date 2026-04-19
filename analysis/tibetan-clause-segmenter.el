;;; tibetan-clause-segmenter.el --- Round-2 clause segmentation + NP chunking + argument structure -*- lexical-binding: t -*-

;;; Commentary:
;; Round-2 of the tibetan-cat.el grammar pipeline.  Unlike the older,
;; text-based `tibetan-clause-analysis.el' (which re-splits syllables and
;; is kept for backward-compat), this module operates on the *position-
;; indexed* representation produced by `tibetan-parse-enhanced' /
;; `tibetan-extract-verbs-compound-aware':
;;
;;     words :: (string ...)        ;; n syllable-words, positions 0..n-1
;;     mwu   :: ((start end form meta) ...)  ;; multiword-unit spans
;;     verbs :: ((lemma . L) (source-pos . P) (suffix-type . S) ...)
;;
;; It exposes three public entry points, each usable independently:
;;
;;   (tibetan-clause-segment WORDS VERBS &optional MWU)
;;       Return a list of clause alists:
;;           ((start . s) (end . e) (verb . V-entry)
;;            (type . main|dependent)
;;            (converb-type . sym-or-nil)
;;            (converb-particle . str-or-nil))
;;       Clauses cover non-overlapping position ranges and are ordered
;;       left-to-right.  Dependent clauses precede the main clause they
;;       modify; the final clause is of type 'main.
;;
;;   (tibetan-np-chunk WORDS &optional CLAUSES MWU)
;;       Return a list of NP alists:
;;           ((start . s) (end . e) (head . H)
;;            (case . ERG|ABS|DAT|GEN|LOC|TERM|INST|COM|nil)
;;            (modifiers . ((kind . mod-kind) (form . str) ...))
;;            (negated . bool)
;;            (clause-index . i-or-nil))
;;       NPs never cross a clause boundary; a trailing case particle
;;       closes and tags the NP.
;;
;;   (tibetan-build-argument-structure CLAUSES NPS)
;;       For each clause, look up the main verb's `case_frame' (via
;;       `tibetan-verb-classifier') and assign the NPs in that clause
;;       to semantic roles.  Returns a list of:
;;           ((clause . CLAUSE) (verb . V)
;;            (case-frame . FRAME)
;;            (arguments . (((role . agent|patient|recipient|...)
;;                           (np . NP)) ...)))
;;
;; The three parts compose cleanly (see `tibetan-analyze-round2') but
;; each is independently testable and side-effect-free.

;;; Code:

(require 'cl-lib)
(require 'tibetan-verb-classifier nil t)

;; ============================================================================
;; Shared vocabulary
;; ============================================================================

(defconst tibetan-clause-seg--converb-suffixes
  '(("ནས"  . ablative)
    ("ཏེ"  . coordinative)
    ("སྟེ" . coordinative)
    ("དེ"  . coordinative)
    ("ཞིང" . simultaneous)
    ("ཅིང" . simultaneous)
    ("ཤིང" . simultaneous)
    ("པས"  . causal)
    ("བས"  . causal)
    ("ཀྱང" . concessive)
    ("ཡང"  . concessive)
    ("འང"  . concessive)
    ("ན"   . conditional))
  "Particles that (as standalone words OR word-final suffixes) end
a dependent clause.  The value is the converb type symbol.")

(defconst tibetan-clause-seg--final-particles
  '("སོ" "འོ" "ཏོ" "དོ" "ནོ" "བོ" "མོ" "གོ" "ངོ" "རོ" "ལོ")
  "Sentence-final particles that follow the main verb.")

(defconst tibetan-clause-seg--case-particles
  '(;; Ergative / Instrumental
    ("ཀྱིས" . ERG) ("གྱིས" . ERG) ("གིས" . ERG)
    ("འིས"  . ERG) ("ཡིས" . ERG) ("ས"    . ERG)
    ;; Genitive
    ("ཀྱི" . GEN) ("གྱི" . GEN) ("གི" . GEN)
    ("འི" . GEN) ("ཡི" . GEN)
    ;; Terminative (goal / direction / manner)
    ("དུ" . TERM) ("ཏུ" . TERM) ("སུ" . TERM) ("རུ" . TERM) ("ར" . TERM)
    ;; Dative / locative
    ("ལ" . DAT) ("ན" . LOC)
    ;; Ablative / elative — both ནས and ལས per Bialek's case analyzer.
    ("ནས" . ABL) ("ལས" . ABL)
    ;; Comitative
    ("དང" . COM))
  "Case particles.  Either as a standalone word or as a suffix on a
noun-word, these tag the preceding NP with a case.")

(defconst tibetan-clause-seg--negators '("མ" "མི")
  "Pre-verbal negation particles (standalone).")

(defconst tibetan-clause-seg--nominaliser-suffixes
  '("པ" "བ" "པོ" "བོ" "པའི" "བའི" "པོའི" "བོའི"
    "པར" "བར" "པའོ" "བའོ")
  "Bare and case-marked nominaliser suffixes that turn a verb stem
into a noun / noun-phrase head.  When one of these appears
immediately after a verb in the word stream, the verb is being
nominalised: it does NOT form a finite clause, and its position is
absorbed into the surrounding NP.

Note: `པས' / `བས' are deliberately EXCLUDED — those are causal
converbs (see `tibetan-clause-seg--converb-suffixes') and DO form
dependent clauses.")

;; Demonstratives + quantifiers routinely cluster with a noun head.
(defconst tibetan-clause-seg--determiners
  '("དེ" "འདི" "ཐམས་ཅད" "ཀུན" "ཚང་མ"))

;; ============================================================================
;; Part A — Clause segmentation
;; ============================================================================

(defun tibetan-clause-seg--verb-at (verbs pos)
  "Return the verb entry in VERBS whose source-pos = POS, or nil."
  (cl-find-if (lambda (v) (equal (alist-get 'source-pos v) pos)) verbs))

(defun tibetan-clause-seg--suffix-type (verb)
  "Return the converb type associated with VERB's suffix, or nil."
  (let ((sfx (alist-get 'suffix-type verb)))
    (and sfx (cdr (assoc sfx tibetan-clause-seg--converb-suffixes)))))

(defun tibetan-clause-segment (words verbs &optional _mwu)
  "Segment WORDS into clauses using VERBS (from Round-1 extractor).

Returns a list of clause alists — see commentary of this file.
Each verb becomes exactly one clause.  The clause's span runs from the
position after the previous clause's end up to and including the verb
position (plus any trailing converb particle or final particle)."
  (let* ((n (length words))
         ;; Only verbs we can locate in the word list: require numeric pos.
         ;; Also drop modal / reporter auxiliaries — those don't form
         ;; their own clauses, they chain onto a content verb (the
         ;; Sentence Structure renderer surfaces them as `+MODAL:X' /
         ;; `+SAYS:X' annotations).  Without this filter, seg-11
         ;; (`...བྱེད་དགོས་ཟེར།') produced three spurious main clauses.
         (placed (cl-remove-if-not
                  (lambda (v)
                    (and (numberp (alist-get 'source-pos v))
                         (not (alist-get 'is-modal v))
                         (not (alist-get 'is-reporter v))))
                  verbs))
         ;; Order by position, de-dup same pos (keep first).
         (by-pos (cl-sort (cl-copy-list placed) #'<
                          :key (lambda (v) (alist-get 'source-pos v))))
         (seen (make-hash-table :test 'eql))
         (all-ordered (cl-loop for v in by-pos
                               for p = (alist-get 'source-pos v)
                               unless (gethash p seen)
                               do (puthash p t seen) and collect v))
         ;; Filter out verbs immediately followed by a bare nominaliser —
         ;; these are nominalised noun phrases, not finite clauses
         ;; (e.g. `བརྒྱུད་པ' "lineage", `སླེབ་པའི' "of the arriving").
         ;; If filtering leaves zero verbs, fall back to the full list —
         ;; better to emit a possibly-wrong clause than nothing at all.
         (filtered (cl-remove-if
                    (lambda (v)
                      (let* ((p (alist-get 'source-pos v))
                             (nxt (and (numberp p) (< (1+ p) n)
                                       (string-trim (nth (1+ p) words)))))
                        (and nxt
                             (member nxt
                                     tibetan-clause-seg--nominaliser-suffixes))))
                    all-ordered))
         (ordered (or filtered all-ordered))
         (clauses '())
         (cursor 0))
    (dolist (v ordered)
      (let* ((vpos (alist-get 'source-pos v))
             ;; Extend end to include a trailing standalone converb or
             ;; final particle directly after the verb.
             (end  (let ((e vpos))
                     (while (and (< (1+ e) n)
                                 (let ((nxt (string-trim (nth (1+ e) words))))
                                   (or (assoc nxt tibetan-clause-seg--converb-suffixes)
                                       (member nxt tibetan-clause-seg--final-particles))))
                       (setq e (1+ e)))
                     e))
             (converb-type (tibetan-clause-seg--suffix-type v))
             (converb-particle nil))
        ;; If the trailing word past the verb is itself a converb/final,
        ;; prefer that as the converb marker.
        (when (and (< vpos end))
          (let ((trailer (string-trim (nth end words))))
            (let ((hit (assoc trailer tibetan-clause-seg--converb-suffixes)))
              (when hit
                (setq converb-type (cdr hit))
                (setq converb-particle (car hit))))))
        (unless converb-particle
          (when converb-type
            ;; derive particle from the verb's source-form tail
            (let ((form (alist-get 'source-form v)))
              (setq converb-particle
                    (car (cl-find-if
                          (lambda (pair)
                            (and form (string-suffix-p (car pair) form)))
                          tibetan-clause-seg--converb-suffixes))))))
        (push `((start . ,cursor)
                (end   . ,end)
                (verb  . ,v)
                (type  . ,(if converb-type 'dependent 'main))
                (converb-type     . ,converb-type)
                (converb-particle . ,converb-particle))
              clauses)
        (setq cursor (1+ end))))
    ;; The last clause is the main clause; if its type was miscomputed
    ;; (e.g. verb carries no suffix), it is already 'main.  But if ALL
    ;; clauses are dependent we promote the last one.  We also extend
    ;; the last clause's end to cover any trailing words (typically
    ;; nominalised NPs that were filtered out as clause-forming
    ;; verbs) so the NP chunker still sees them as arguments of the
    ;; main clause rather than silently dropping them.
    (let ((rev (nreverse clauses)))
      (when rev
        (when (cl-every (lambda (c) (eq (alist-get 'type c) 'dependent)) rev)
          (let ((last (car (last rev))))
            (setf (alist-get 'type last) 'main)))
        (let* ((last (car (last rev)))
               (cur-end (alist-get 'end last)))
          (when (and (numberp cur-end) (< cur-end (1- n)))
            (setf (alist-get 'end last) (1- n))))
        ;; Annotate each clause with `aux-positions': source-pos of any
        ;; modal/reporter auxiliary verb (filtered out above) that falls
        ;; inside the clause's [start, end] range.  The NP chunker uses
        ;; this to skip those positions instead of glueing them into
        ;; surrounding NPs (so e.g. seg-11's `དགོས' and `ཟེར' don't
        ;; leak as `དགོས་ཟེར (—)' arguments of `བྱེད').
        (let ((aux-verbs (cl-remove-if-not
                          (lambda (v)
                            (and (numberp (alist-get 'source-pos v))
                                 (or (alist-get 'is-modal v)
                                     (alist-get 'is-reporter v))))
                          verbs)))
          ;; Rebuild via mapcar so the new alist key actually lives in
          ;; the list element, not just a let-bound copy.  `setf' on
          ;; `alist-get' rebinds the local variable when the key is
          ;; missing — it does not mutate the list cell.
          (setq rev
                (mapcar
                 (lambda (c)
                   (let* ((cs (alist-get 'start c))
                          (ce (alist-get 'end c))
                          (aux (cl-loop for v in aux-verbs
                                        for p = (alist-get 'source-pos v)
                                        when (and (numberp p)
                                                  (>= p cs) (<= p ce))
                                        collect p)))
                     (if aux
                         (append c `((aux-positions . ,aux)))
                       c)))
                 rev))))
      rev)))

;; ============================================================================
;; Part B — NP chunking
;; ============================================================================

(defun tibetan-clause-seg--multichar-suffix-p (pair)
  "Non-nil when PAIR's particle is longer than one character and can
therefore be safely matched as a suffix on another word.

Single-character case particles (ས / ལ / ར / ན) are ambiguous with
syllable-final consonants (e.g. `གཞིས' ends in ས as final consonant,
not as an agglutinated ergative).  We therefore allow them to match
only as standalone words (via the earlier `assoc' lookups), never
via `string-suffix-p'.  Bialek's particle analyzer documents the
same rule at `analysis/tibetan-particles-bialek.el' (§terminative)."
  (> (length (car pair)) 1))

(defun tibetan-clause-seg--classify-word (w)
  "Return a symbol for W indicating its grammatical role.
Possible return values: \\='case-suffix, \\='case-standalone, \\='negator,
\\='determiner, \\='final, \\='converb, or nil (= content/head
candidate).  Detects the longest matching suffix.  Single-character
case particles match only as standalone — see
`tibetan-clause-seg--multichar-suffix-p'."
  (let ((w (string-trim w)))
    (cond
     ((member w tibetan-clause-seg--negators) 'negator)
     ((member w tibetan-clause-seg--determiners) 'determiner)
     ((member w tibetan-clause-seg--final-particles) 'final)
     ((assoc w tibetan-clause-seg--converb-suffixes) 'converb)
     ((assoc w tibetan-clause-seg--case-particles) 'case-standalone)
     ((cl-some (lambda (pair)
                 (and (tibetan-clause-seg--multichar-suffix-p pair)
                      (> (length w) (length (car pair)))
                      (string-suffix-p (car pair) w)))
               tibetan-clause-seg--case-particles)
      'case-suffix)
     (t nil))))

(defun tibetan-clause-seg--case-of (w)
  "Return the case symbol for W, preferring the longest matching
particle/suffix.  Only multi-character particles may match as a
suffix (see `tibetan-clause-seg--multichar-suffix-p')."
  (let ((w (string-trim w)))
    (or (cdr (assoc w tibetan-clause-seg--case-particles))
        (let ((best nil) (best-len 0))
          (dolist (pair tibetan-clause-seg--case-particles)
            (let ((p (car pair)))
              (when (and (tibetan-clause-seg--multichar-suffix-p pair)
                         (string-suffix-p p w)
                         (> (length w) (length p))
                         (> (length p) best-len))
                (setq best (cdr pair) best-len (length p)))))
          best))))

(defun tibetan-clause-seg--case-particle (w)
  "Return the particle string at the end of W (the literal substring
that the case-of helper recognised), or nil if W carries no case.

Standalone particle (W itself is a case particle) → return W.
Suffix particle (multi-char, see `--multichar-suffix-p') → return the
matched suffix.  Used by callers that need the particle text in
addition to the case symbol — e.g. legacy renderers that print
`form(MARKER)' annotations."
  (let ((w (string-trim w)))
    (cond
     ((assoc w tibetan-clause-seg--case-particles) w)
     (t
      (let ((best nil) (best-len 0))
        (dolist (pair tibetan-clause-seg--case-particles)
          (let ((p (car pair)))
            (when (and (tibetan-clause-seg--multichar-suffix-p pair)
                       (string-suffix-p p w)
                       (> (length w) (length p))
                       (> (length p) best-len))
              (setq best p best-len (length p)))))
        best)))))

(defun tibetan-clause-seg--case-strip (w)
  "If W ends in a case particle longer than itself, return the stem;
otherwise return W unchanged.  Only multi-character particles may
match — a final ས / ལ / ར / ན on a stem is NOT stripped, since
single-character case particles are ambiguous with syllable-final
consonants."
  (let ((w (string-trim w))
        (best-p nil) (best-len 0))
    (dolist (pair tibetan-clause-seg--case-particles)
      (let ((p (car pair)))
        (when (and (tibetan-clause-seg--multichar-suffix-p pair)
                   (string-suffix-p p w)
                   (> (length w) (length p))
                   (> (length p) best-len))
          (setq best-p p best-len (length p)))))
    (if best-p
        (let ((stem (substring w 0 (- (length w) (length best-p)))))
          ;; Strip a trailing tsheg left behind by the separation
          ;; (e.g. "བདག་གིས" → "བདག་" → "བདག").
          (replace-regexp-in-string "་+$" "" stem))
      w)))

(defun tibetan-clause-seg--verb-position-p (pos verbs)
  (cl-some (lambda (v) (equal pos (alist-get 'source-pos v))) verbs))

(defun tibetan-clause-seg--mwu-verbal-p (mwu-entry)
  "Return non-nil when an MWU entry's `english' meta describes a verb.

MWU-ENTRY has the shape `(start end form meta)' where META is an
alist (typically containing an `english' key).  An MWU is treated as
verb-bearing when its English gloss starts with `to <lowercase>',
`pf./pres./fut./ft./imp.', or contains the word `verb' / `Verb'.
Single source of truth used by both the NP chunker (which then
SKIPS the MWU entirely — verbal MWUs are predicates, not NPs) and
the verb extractor (which then attempts head-verb detection).

The lowercase-letter requirement after `to ' is intentional:
directional / terminative glosses like `to Ko ron sa' or
`to the temple' would otherwise spuriously match."
  (let* ((meta (and mwu-entry (listp mwu-entry) (>= (length mwu-entry) 4)
                    (nth 3 mwu-entry)))
         (english (and (listp meta) (alist-get 'english meta))))
    (and english (stringp english)
         (let ((case-fold-search nil))
           (or (string-match-p "\\`[ \t]*to[ \t]+[a-z]" english)
               (string-match-p
                "\\`[ \t]*\\(pf\\|pres\\|fut\\|ft\\|imp\\)\\." english)
               ;; Sanskrit absolutive (`bhuktvā', `pītvā', `jñāpayitvā',
               ;; `prāpya', etc.) — Steinert's bilingual entries for
               ;; converb-marked compound verbs like `གསོལ་ནས' typically
               ;; gloss them with the Sanskrit absolutive form.  Without
               ;; this pattern, `གསོལ་ནས' would be treated as a noun
               ;; NP and the head verb `གསོལ' never surfaces as a clause.
               (string-match-p "[a-zāīūṛēō][a-zāīūṛēō]+tvā\\b" english)
               (string-match-p "\\b[Vv]erb\\b" english))))))

(defun tibetan-clause-seg--mwu-span-at (pos mwu)
  "Return (start . end) if POS starts an MWU in MWU, else nil.
MWU entries are (start end form meta)."
  (let ((hit (cl-find-if (lambda (s) (= pos (nth 0 s))) mwu)))
    (when hit (cons (nth 0 hit) (nth 1 hit)))))

(defun tibetan-np-chunk (words &optional clauses mwu)
  "Chunk WORDS into noun phrases, optionally bounded by CLAUSES.
MWU spans are treated as atomic heads.  Returns a list of NP alists
(see commentary)."
  (let* ((n (length words))
         ;; If CLAUSES not supplied, treat the whole text as one span.
         (spans (if clauses
                    (mapcar (lambda (c)
                              (list (alist-get 'start c)
                                    (alist-get 'end c)
                                    c))
                            clauses)
                  (list (list 0 (1- n) nil))))
         (nps '()))
    (cl-loop for (cs ce clause) in spans
             for ci from 0
             do
             (let ((i cs)
                   ;; Positions within this clause that NPs must skip:
                   ;; the clause's own verb, plus any modal/reporter
                   ;; auxiliaries recorded in `aux-positions'.  Without
                   ;; the latter, filtered-out auxiliaries get glued
                   ;; into surrounding NPs (seg-11 regression).
                   (verb-pos (when clause
                               (cons (alist-get 'source-pos
                                                (alist-get 'verb clause))
                                     (alist-get 'aux-positions clause)))))
               (while (<= i ce)
                 (let* ((w (string-trim (nth i words)))
                        (cls (tibetan-clause-seg--classify-word w))
                        (mwu-span (tibetan-clause-seg--mwu-span-at i mwu)))
                   (cond
                    ;; Skip verbs, converbs, finals, naked case particles,
                    ;; negators (handled by verb layer).
                    ((or (memq cls '(final converb negator))
                         (member i verb-pos))
                     (cl-incf i))
                    ;; Standalone case particle with no preceding head
                    ;; (shouldn't happen after a proper head — if it does,
                    ;; skip).
                    ((eq cls 'case-standalone)
                     (cl-incf i))
                    ;; A verb-bearing MWU (light-verb compound like
                    ;; `ཆུང་མ་བྱེད') is the clause's predicate — it must
                    ;; not surface as an NP at all.  Detect it via the
                    ;; MWU meta (`english' starts with `to ', etc.) and
                    ;; skip past it; the verb extractor already records
                    ;; the head verb separately.
                    ;; NOTE on MWU span convention: `tibetan-clause-seg
                    ;; --mwu-span-at' returns `(start . end)' where END is
                    ;; the parser's EXCLUSIVE end (`(+ start len)' in
                    ;; `tibetan-find-multiword-units').  The branches
                    ;; below normalise to an INCLUSIVE last-position (e-1)
                    ;; for `number-sequence' / `nth' indexing.  Pre-fix,
                    ;; the existing chunker treated END as inclusive and
                    ;; over-iterated by one position (silent in production
                    ;; because the spurious `nth' fell on a real syllable
                    ;; that just happened to glue cleanly).
                    ((and mwu-span
                          (tibetan-clause-seg--mwu-verbal-p
                           (cl-find-if
                            (lambda (u) (= (car mwu-span) (nth 0 u)))
                            mwu)))
                     (setq i (cdr mwu-span)))
                    ;; A non-verbal MWU span: absorb as a single NP head
                    ;; — but never cross a verb position.  A user-supplied
                    ;; vocab MWU like `ཡུལ་འཐོན' (homeland + go-out) would
                    ;; otherwise pull the verb into the NP head.  Truncate
                    ;; the MWU end to just before the first verb position
                    ;; it overlaps; if that leaves an empty span, fall back
                    ;; to the standard content-word branch.
                    ((and mwu-span
                          (let* ((s (car mwu-span))
                                 (e (cdr mwu-span))
                                 (vp (cl-find-if
                                      (lambda (v) (and (>= v s) (< v e)))
                                      verb-pos)))
                            (cond ((null vp) t)
                                  ((= vp s) (setq mwu-span nil))
                                  ;; Truncate so the new exclusive end
                                  ;; sits exactly at the verb position
                                  ;; (excluding it).
                                  (t (setq mwu-span (cons s vp)) t)))
                          mwu-span)
                     (let* ((s (car mwu-span))
                            (e (cdr mwu-span))         ; exclusive end
                            (last-pos (1- e))          ; inclusive end
                            (form (mapconcat (lambda (k) (nth k words))
                                             (number-sequence s last-pos) "་"))
                            (np-start s)
                            (np-end last-pos)
                            (np-case nil)
                            (modifiers '()))
                       ;; Trailing case: either as suffix on the MWU's last
                       ;; syllable (last-pos) OR as the standalone
                       ;; particle word right after the MWU (at exclusive
                       ;; end e).
                       (let* ((last-w (string-trim (nth last-pos words)))
                              (sfx-case (tibetan-clause-seg--case-of last-w)))
                         (when (and sfx-case
                                    (> (length last-w)
                                       (length (car (rassq sfx-case
                                                           (mapcar (lambda (p)
                                                                     (cons (car p) (cdr p)))
                                                                   tibetan-clause-seg--case-particles))))))
                           (setq np-case sfx-case)))
                       (when (and (not np-case) (<= e ce))
                         (let* ((nxt-pos e)
                                (nxt (and (<= nxt-pos ce)
                                          (string-trim (nth nxt-pos words)))))
                           (when (and nxt
                                      (assoc nxt tibetan-clause-seg--case-particles))
                             (setq np-case (cdr (assoc nxt
                                                       tibetan-clause-seg--case-particles)))
                             (setq np-end nxt-pos))))
                       (push `((start . ,np-start)
                               (end   . ,np-end)
                               (head  . ,form)
                               (case  . ,np-case)
                               (modifiers . ,modifiers)
                               (clause-index . ,ci))
                             nps)
                       (setq i (1+ np-end))))
                    ;; A head-noun candidate (content word, possibly
                    ;; carrying a case suffix).  Consecutive content
                    ;; words with no particle between them are glued
                    ;; into one compound head — proper nouns like
                    ;; `ཀོ་རོན་སར' arrive tsheg-split and would otherwise
                    ;; produce three spurious NPs.
                    (t
                     (let* ((np-start i)
                            (modifiers '())
                            (np-case nil)
                            (np-end i)
                            ;; Accumulate contiguous content words into
                            ;; `pieces' (list of tsheg-separated stems).
                            (pieces (list w)))
                       (while (and (< (1+ np-end) (1+ ce))
                                   (not (member (1+ np-end) verb-pos))
                                   ;; Stop if the next position starts a new
                                   ;; MWU — the MWU branch must take over so
                                   ;; light-verb compounds (`ཆུང་མ་བྱེད') and
                                   ;; other parser-glued units aren't half-
                                   ;; absorbed by the surrounding NP.
                                   (not (tibetan-clause-seg--mwu-span-at
                                         (1+ np-end) mwu))
                                   (let* ((nxt (string-trim
                                                (nth (1+ np-end) words)))
                                          (ncls (tibetan-clause-seg--classify-word
                                                 nxt)))
                                     ;; Keep gluing only on bare content
                                     ;; words (classify returns nil) — a
                                     ;; case-suffix word ends the glue
                                     ;; chain but is absorbed as the tail.
                                     (or (null ncls) (eq ncls 'case-suffix))))
                         (setq np-end (1+ np-end))
                         (setq pieces (append pieces
                                              (list (string-trim
                                                     (nth np-end words))))))
                       (let* ((head (mapconcat #'identity pieces "་"))
                              (last-piece (car (last pieces))))
                         ;; Case suffix on the last glued piece?  Only
                         ;; fires for multi-char suffixes (see Fix 1).
                         (when (eq (tibetan-clause-seg--classify-word last-piece)
                                   'case-suffix)
                           (setq np-case (tibetan-clause-seg--case-of last-piece))
                           (let ((stripped (tibetan-clause-seg--case-strip
                                            last-piece)))
                             (setq pieces (append (butlast pieces)
                                                  (list stripped)))
                             (setq head (mapconcat #'identity pieces "་"))))
                         ;; Compound-terminative `Xར' rule (matches bialek's
                         ;; fallback in `tibetan-analyze-cases-bialek'):
                         ;; when the head is a tsheg-compound (>1 piece) and
                         ;; its final piece is a 2-char `Xར' form, treat the
                         ;; ར as a terminative suffix.  Conservative: never
                         ;; fires on a standalone 2-char word like པར/མར.
                         (when (and (null np-case)
                                    (> (length pieces) 1)
                                    (let ((lp (car (last pieces))))
                                      (and (= (length lp) 2)
                                           (string-suffix-p "ར" lp))))
                           (setq np-case 'TERM)
                           (let* ((lp (car (last pieces)))
                                  (stem (substring lp 0 (- (length lp) 1))))
                             (setq pieces (append (butlast pieces) (list stem)))
                             (setq head (mapconcat #'identity pieces "་"))))
                         ;; Trailing determiner (དེ/འདི) glues to head.
                         (when (and (null np-case)
                                    (< (1+ np-end) (1+ ce)))
                           (let* ((nxt (string-trim (nth (1+ np-end) words)))
                                  (ncls (tibetan-clause-seg--classify-word nxt)))
                             (when (eq ncls 'determiner)
                               (push `((kind . determiner) (form . ,nxt))
                                     modifiers)
                               (setq np-end (1+ np-end)))))
                         ;; Trailing standalone case particle?
                         (when (and (null np-case)
                                    (< (1+ np-end) (1+ ce)))
                           (let ((nxt (string-trim (nth (1+ np-end) words))))
                             (when (and nxt
                                        (assoc nxt tibetan-clause-seg--case-particles))
                               (setq np-case (cdr (assoc nxt
                                                         tibetan-clause-seg--case-particles)))
                               (setq np-end (1+ np-end)))))
                         (push `((start . ,np-start)
                                 (end   . ,np-end)
                                 (head  . ,head)
                                 (case  . ,np-case)
                                 (modifiers . ,(nreverse modifiers))
                                 (clause-index . ,ci))
                               nps)
                         (setq i (1+ np-end))))))))))
    (nreverse nps)))

;; ============================================================================
;; Part C — Argument structure
;; ============================================================================

(defconst tibetan-clause-seg--case-frame-role-map
  '(("Erg-Abs" . ((ERG . agent) (nil . patient) (ABS . patient) (DAT . recipient) (LOC . location)))
    ("Abs"     . ((nil . subject) (ABS . subject) (DAT . goal)   (LOC . location)))
    ("Abs-Abs" . ((nil . subject) (ABS . subject)))
    ("Abs-Dat" . ((nil . subject) (ABS . subject) (DAT . goal)))
    ("Abs-Loc" . ((nil . subject) (ABS . subject) (LOC . location)))
    ("Erg-Abs-Dat" . ((ERG . agent) (nil . patient) (ABS . patient) (DAT . recipient))))
  "Map from `case_frame' label to an alist of (NP-case . role).")

(defun tibetan-clause-seg--lookup-case-frame (lemma)
  "Return the `case_frame' string for LEMMA via the verb classifier, or nil."
  (when (and lemma (fboundp 'tibetan-verb-lookup))
    (let ((entry (ignore-errors (tibetan-verb-lookup lemma))))
      (and entry (alist-get 'case_frame entry)))))

(defun tibetan-clause-seg--role-for-case (frame case-sym)
  "Resolve CASE-SYM to a role given FRAME string."
  (let ((map (cdr (assoc frame tibetan-clause-seg--case-frame-role-map))))
    (or (cdr (assoc case-sym map))
        ;; generic fallbacks
        (pcase case-sym
          ('ERG  'agent)
          ('DAT  'recipient)
          ('LOC  'location)
          ('ABL  'source)
          ('TERM 'goal)
          ('INST 'instrument)
          ('COM  'comitative)
          ('GEN  nil) ;; possessors aren't clause arguments
          ('nil  'subject)
          (_ nil)))))

(defun tibetan-build-argument-structure (clauses nps)
  "Assign each NP in NPS to a role under its clause's main verb.

CLAUSES is the output of `tibetan-clause-segment'.  NPS is the output
of `tibetan-np-chunk'.  Returns a list of clause-structure alists (see
commentary)."
  (cl-loop for clause in clauses
           for ci from 0
           for v = (alist-get 'verb clause)
           for lemma = (alist-get 'lemma v)
           for frame = (tibetan-clause-seg--lookup-case-frame lemma)
           for clause-nps = (cl-remove-if-not
                             (lambda (np)
                               (equal (alist-get 'clause-index np) ci))
                             nps)
           for args = (mapcar
                       (lambda (np)
                         (let* ((c (alist-get 'case np))
                                (role (tibetan-clause-seg--role-for-case
                                       frame c)))
                           `((role . ,role) (np . ,np))))
                       clause-nps)
           collect `((clause     . ,clause)
                     (verb       . ,v)
                     (case-frame . ,frame)
                     (arguments  . ,args))))

;; ============================================================================
;; Convenience wrapper
;; ============================================================================

(defun tibetan-analyze-round2 (words verbs &optional mwu)
  "Run Round-2 end-to-end.  Returns an alist:
  ((clauses . ...) (nps . ...) (argument-structure . ...))."
  (let* ((clauses (tibetan-clause-segment words verbs mwu))
         (nps     (tibetan-np-chunk words clauses mwu))
         (args    (tibetan-build-argument-structure clauses nps)))
    `((clauses . ,clauses)
      (nps     . ,nps)
      (argument-structure . ,args))))

(provide 'tibetan-clause-segmenter)
;;; tibetan-clause-segmenter.el ends here
