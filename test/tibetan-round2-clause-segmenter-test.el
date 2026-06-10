;;; tibetan-round2-clause-segmenter-test.el --- Round-2 tests -*- lexical-binding: t -*-

;;; Commentary:
;; Regression tests for `analysis/tibetan-clause-segmenter.el' — the
;; three Round-2 parts (clause segmentation, NP chunking, argument
;; structure).  Each part is tested independently and then end-to-end
;; on a full Milarepa-style segment.

;;; Code:

(require 'ert)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir)))

(require 'tibetan-clause-segmenter)

;; ============================================================================
;; Helpers — hand-built verb entries so these tests don't depend on the
;; full extractor pipeline.
;; ============================================================================

(defun tibetan-round2-test--verb (lemma pos &optional suffix-type source-form)
  "Build a minimal verb alist with the shape Round-2 expects."
  `((lemma . ,lemma)
    (source-pos . ,pos)
    (source-form . ,(or source-form lemma))
    (suffix-type . ,suffix-type)))

(defun tibetan-round2-test--clause-of-type (clauses type)
  (cl-find-if (lambda (c) (eq (alist-get 'type c) type)) clauses))

;; ============================================================================
;; Part A — Clause segmentation
;; ============================================================================

(ert-deftest tibetan-round2-segment-single-main-clause ()
  "One verb, no converbs → one 'main clause covering all positions."
  (let* ((words '("བདག" "གིས" "ལས" "བྱས"))
         (verbs (list (tibetan-round2-test--verb "བྱས" 3)))
         (clauses (tibetan-clause-segment words verbs nil)))
    (should (= (length clauses) 1))
    (let ((c (car clauses)))
      (should (eq (alist-get 'type c) 'main))
      (should (= (alist-get 'start c) 0))
      (should (= (alist-get 'end c) 3))
      (should-not (alist-get 'converb-type c)))))

(ert-deftest tibetan-round2-segment-dependent-then-main ()
  "One dependent clause (causal པས) and one main clause."
  (let* ((words '("དེ" "ལ" "མ" "ཉན" "པས" "ཁྲོས"))
         (verbs (list
                 (tibetan-round2-test--verb "ཉན" 3 "པས" "ཉན་པས")
                 (tibetan-round2-test--verb "ཁྲོས" 5)))
         (clauses (tibetan-clause-segment words verbs nil))
         (dep  (tibetan-round2-test--clause-of-type clauses 'dependent))
         (main (tibetan-round2-test--clause-of-type clauses 'main)))
    (should (= (length clauses) 2))
    (should dep)
    (should main)
    (should (eq (alist-get 'converb-type dep) 'causal))
    (should (equal (alist-get 'converb-particle dep) "པས"))))

(ert-deftest tibetan-round2-segment-trailing-standalone-converb ()
  "Verb followed by a separate converb particle token (ཏེ) is part of
the same clause and tagged coordinative."
  (let* ((words '("ཁྲོས" "ཏེ" "ནོར" "ཕྲོགས"))
         (verbs (list
                 (tibetan-round2-test--verb "ཁྲོས" 0)
                 (tibetan-round2-test--verb "ཕྲོགས" 3)))
         (clauses (tibetan-clause-segment words verbs nil))
         (dep (car clauses)))
    (should (eq (alist-get 'type dep) 'dependent))
    (should (eq (alist-get 'converb-type dep) 'coordinative))
    (should (= (alist-get 'end dep) 1))))

(ert-deftest tibetan-round2-segment-all-dependent-promotes-last ()
  "If the extractor saw only converb-suffixed verbs, the last one is
still promoted to main."
  (let* ((words '("ཉན" "པས"))
         (verbs (list (tibetan-round2-test--verb "ཉན" 0 "པས" "ཉན་པས")))
         (clauses (tibetan-clause-segment words verbs nil)))
    (should (= (length clauses) 1))
    (should (eq (alist-get 'type (car clauses)) 'main))))

;; ============================================================================
;; Part B — NP chunking
;; ============================================================================

(ert-deftest tibetan-round2-np-ergative-suffix ()
  "བདག་གིས → one NP with head=བདག and case=ERG."
  (let* ((words '("བདག་གིས" "བྱས"))
         (verbs (list (tibetan-round2-test--verb "བྱས" 1)))
         (clauses (tibetan-clause-segment words verbs nil))
         (nps (tibetan-np-chunk words clauses nil)))
    (should (= (length nps) 1))
    (let ((np (car nps)))
      (should (equal (alist-get 'head np) "བདག"))
      (should (eq (alist-get 'case np) 'ERG)))))

(ert-deftest tibetan-round2-np-standalone-ergative ()
  "བདག ས བྱས → NP head=བདག, case=ERG via standalone ས absorbed."
  (let* ((words '("བདག" "ས" "བྱས"))
         (verbs (list (tibetan-round2-test--verb "བྱས" 2)))
         (clauses (tibetan-clause-segment words verbs nil))
         (nps (tibetan-np-chunk words clauses nil))
         (np (car nps)))
    (should np)
    (should (equal (alist-get 'head np) "བདག"))
    (should (eq (alist-get 'case np) 'ERG))))

(ert-deftest tibetan-round2-np-dative ()
  "དེ ལ ཉན → one NP head=དེ (determiner) case=DAT."
  (let* ((words '("དེ" "ལ" "ཉན"))
         (verbs (list (tibetan-round2-test--verb "ཉན" 2)))
         (clauses (tibetan-clause-segment words verbs nil))
         (nps (tibetan-np-chunk words clauses nil)))
    (should nps)
    (let ((np (car nps)))
      (should (eq (alist-get 'case np) 'DAT)))))

(ert-deftest tibetan-round2-np-respects-clause-boundaries ()
  "NPs must not span two clauses."
  (let* ((words '("བདག" "གིས" "ལས" "བྱས" "ཏེ" "སངས་རྒྱས" "ཐོབ"))
         (verbs (list
                 (tibetan-round2-test--verb "བྱས" 3)
                 (tibetan-round2-test--verb "ཐོབ" 6)))
         (clauses (tibetan-clause-segment words verbs nil))
         (nps (tibetan-np-chunk words clauses nil)))
    ;; All NPs' positions fall inside exactly one clause's [start..end].
    (dolist (np nps)
      (let ((ci (alist-get 'clause-index np)))
        (should ci)
        (let* ((c (nth ci clauses))
               (cs (alist-get 'start c))
               (ce (alist-get 'end c)))
          (should (>= (alist-get 'start np) cs))
          (should (<= (alist-get 'end np) ce)))))))

;; ============================================================================
;; Part C — Argument structure
;; ============================================================================

(ert-deftest tibetan-round2-args-transitive-erg-abs ()
  "Transitive verb with case_frame Erg-Abs: ERG-NP → agent, bare NP → patient."
  (skip-unless (fboundp 'tibetan-verb-lookup))
  ;; Inject / ensure a verb entry for the test.
  (let* ((words '("བདག་གིས" "ལས" "བྱས"))
         (verbs (list (tibetan-round2-test--verb "བྱེད" 2)))
         (analysis (tibetan-analyze-round2 words verbs nil))
         (args (car (alist-get 'argument-structure analysis))))
    (should args)
    ;; at least one assigned role
    (let ((roles (mapcar (lambda (a) (alist-get 'role a))
                         (alist-get 'arguments args))))
      ;; ERG-tagged NP should be 'agent under any reasonable frame.
      (should (memq 'agent roles)))))

(ert-deftest tibetan-round2-args-dative-recipient ()
  "A DAT-marked NP under a verb with a Dat slot becomes 'recipient' or
'goal' (both acceptable)."
  (let* ((words '("ཁོང" "ལ" "སློབ"))
         (verbs (list (tibetan-round2-test--verb "སློབ" 2)))
         (analysis (tibetan-analyze-round2 words verbs nil))
         (struct (car (alist-get 'argument-structure analysis)))
         (roles (mapcar (lambda (a) (alist-get 'role a))
                        (alist-get 'arguments struct))))
    (should (or (memq 'recipient roles)
                (memq 'goal roles)
                (memq 'location roles)))))

;; ============================================================================
;; Smoke test — end-to-end on a Milarepa-style failing segment.
;; ============================================================================

(ert-deftest tibetan-round2-end-to-end-seg012 ()
  "Seg-012: …མ་ཉན་པས་ཁྲོས་ཏེ…ཕྲོགས — expects two deps + one main,
and NP chunks inside each clause."
  (let* ((words '("དེ" "ལ" "མ" "ཉན" "པས" "ཁྲོས" "ཏེ"
                  "ནོར" "རྫས" "ཐམས་ཅད" "ཕྲོགས"))
         (verbs (list
                 (tibetan-round2-test--verb "ཉན"   3 "པས" "ཉན་པས")
                 (tibetan-round2-test--verb "ཁྲོས" 5)
                 (tibetan-round2-test--verb "ཕྲོགས" 10)))
         (analysis (tibetan-analyze-round2 words verbs nil))
         (clauses (alist-get 'clauses analysis)))
    (should (= (length clauses) 3))
    (should (eq (alist-get 'type (car (last clauses))) 'main))
    ;; ཁྲོས with trailing ཏེ should be dependent/coordinative.
    (let ((mid (nth 1 clauses)))
      (should (eq (alist-get 'converb-type mid) 'coordinative)))))

;; ============================================================================
;; Regression guards for the Round-2 polish (single-char particles,
;; content-word gluing, compound-terminative ར, nominaliser exclusion)
;; ============================================================================

(ert-deftest tibetan-round2-np-final-consonant-not-case ()
  "A single-char case particle that is also a common syllable-final
consonant (ས / ལ / ར / ན) must NOT be stripped as a case suffix.
Otherwise `གཞིས' becomes `གཞི' (ERG), `རྒྱལ' becomes `རྒྱ' (DAT), etc."
  (let ((nps (tibetan-np-chunk '("གཞིས") nil nil)))
    (should nps)
    (should (string= (alist-get 'head (car nps)) "གཞིས"))
    (should (null (alist-get 'case (car nps)))))
  (let ((nps (tibetan-np-chunk '("རྒྱལ") nil nil)))
    (should nps)
    (should (string= (alist-get 'head (car nps)) "རྒྱལ"))
    (should (null (alist-get 'case (car nps)))))
  (let ((nps (tibetan-np-chunk '("ཡུལ") nil nil)))
    (should nps)
    (should (string= (alist-get 'head (car nps)) "ཡུལ"))
    (should (null (alist-get 'case (car nps))))))

(ert-deftest tibetan-round2-np-multichar-suffix-still-strips ()
  "Multi-char case suffixes (གིས / དུ / ནས / …) must still be stripped
— otherwise Fix 1 would regress ordinary Classical Tibetan case-marking."
  (let* ((nps (tibetan-np-chunk '("བདག་གིས") nil nil))
         (np (car nps)))
    (should np)
    (should (string= (alist-get 'head np) "བདག"))
    (should (eq (alist-get 'case np) 'ERG))))

(ert-deftest tibetan-round2-np-glues-compound-proper-noun ()
  "Consecutive content words with no intervening particle are glued
into a single NP.  Uses `ཀོ་རོན' as the compound — both pieces classify
as content (no case-suffix after Fix 1), so they must be glued
rather than produce two separate NPs."
  (let ((nps (tibetan-np-chunk '("ཀོ" "རོན") nil nil)))
    (should (= (length nps) 1))
    (should (string= (alist-get 'head (car nps)) "ཀོ་རོན"))
    (should (null (alist-get 'case (car nps))))))

(ert-deftest tibetan-round2-np-compound-terminative-sar ()
  "A tsheg-compound whose last 2-char piece ends in ར (e.g. `ཀོ་རོན་སར')
is classified as TERMINATIVE with the ར stripped from the head."
  (let* ((nps (tibetan-np-chunk '("ཀོ" "རོན" "སར") nil nil))
         (np (car nps)))
    (should (= (length nps) 1))
    (should (eq (alist-get 'case np) 'TERM))
    (should (string= (alist-get 'head np) "ཀོ་རོན་ས"))))

(ert-deftest tibetan-round2-np-standalone-sar-stays-noun ()
  "Standalone 2-char `སར' alone must NOT be flagged terminative —
only the compound (multi-piece) form triggers the rule."
  (let* ((nps (tibetan-np-chunk '("སར") nil nil))
         (np (car nps)))
    (should np)
    ;; No terminative stripping — head stays `སར'.
    (should (string= (alist-get 'head np) "སར"))))

(ert-deftest tibetan-round2-segment-excludes-nominalised-verb-pa ()
  "A verb followed by a bare nominaliser `པ' does NOT form a clause.
`བརྒྱུད་པ' (the nominalisation of `བརྒྱུད' to the noun `lineage') must
not generate a spurious clause — it's an NP head."
  (let* ((words '("ཁོང" "སླེབ" "བརྒྱུད" "པ"))
         (verbs (list (tibetan-round2-test--verb "སླེབ" 1)
                      (tibetan-round2-test--verb "བརྒྱུད" 2)))
         (clauses (tibetan-clause-segment words verbs nil))
         (lemmas (mapcar (lambda (c)
                           (alist-get 'lemma (alist-get 'verb c)))
                         clauses)))
    (should (member "སླེབ" lemmas))
    (should-not (member "བརྒྱུད" lemmas))))

(ert-deftest tibetan-round2-segment-excludes-nominalised-genitive-pai ()
  "A verb followed by `པའི' (genitive-marked nominaliser) is similarly
an NP head, not a clause.  Regression guard for `སླེབ་པའི' and
`བྱས་པའི' forms."
  (let* ((words '("ཁོང" "འཐོན" "སླེབ" "པའི"))
         (verbs (list (tibetan-round2-test--verb "འཐོན" 1)
                      (tibetan-round2-test--verb "སླེབ" 2)))
         (clauses (tibetan-clause-segment words verbs nil))
         (lemmas (mapcar (lambda (c)
                           (alist-get 'lemma (alist-get 'verb c)))
                         clauses)))
    (should (member "འཐོན" lemmas))
    (should-not (member "སླེབ" lemmas))))

(ert-deftest tibetan-round2-segment-pas-is-causal-not-nominaliser ()
  "`པས' is a CAUSAL CONVERB — a verb followed by `པས' is still a
clause-forming verb (dependent / causal).  Guard that
`tibetan-clause-seg--nominaliser-suffixes' did not accidentally
include `པས'."
  (let* ((words '("བྱས" "པས" "ཕམ"))
         (verbs (list (tibetan-round2-test--verb "བྱེད" 0 nil "བྱས")
                      (tibetan-round2-test--verb "ཕམ" 2)))
         (clauses (tibetan-clause-segment words verbs nil))
         (lemmas (mapcar (lambda (c)
                           (alist-get 'lemma (alist-get 'verb c)))
                         clauses)))
    (should (member "བྱེད" lemmas))
    (should (member "ཕམ" lemmas))))

(ert-deftest tibetan-round2-segment-extends-last-clause-to-tail ()
  "When trailing words are left uncovered by the last clause (typically
because a nominalised verb at the end was filtered), the last
surviving clause's end is extended to cover the tail so the NP
chunker still sees those words as arguments."
  (let* ((words '("ཁོང" "འཐོན" "སླེབ" "པའི" "བརྒྱུད" "པ"))
         (verbs (list (tibetan-round2-test--verb "འཐོན" 1)
                      (tibetan-round2-test--verb "སླེབ" 2)
                      (tibetan-round2-test--verb "བརྒྱུད" 4)))
         (clauses (tibetan-clause-segment words verbs nil)))
    (should (= (length clauses) 1))
    (let ((c (car clauses)))
      (should (eq (alist-get 'type c) 'main))
      (should (= (alist-get 'end c) 5)))))

(ert-deftest tibetan-round2-segment-fallback-when-all-nominalised ()
  "If every verb is followed by a nominaliser, filtering would leave
zero clauses.  The segmenter must fall back to the unfiltered list
so the analysis does not silently drop to empty."
  (let* ((words '("སླེབ" "པ"))
         (verbs (list (tibetan-round2-test--verb "སླེབ" 0)))
         (clauses (tibetan-clause-segment words verbs nil)))
    (should (= (length clauses) 1))))

(ert-deftest tibetan-round2-np-mwu-does-not-cross-verb ()
  "An MWU span that crosses a verb position must NOT pull the verb
into the NP head.  Real-world case: a user-supplied vocab entry
provides `ཡུལ་འཐོན' as a multiword unit (positions 10-11), but
position 11 is the verb `འཐོན' for the current clause.  The MWU
must be truncated to end before the verb (here: empty span,
falling back to the standard content branch on `ཡུལ' alone)."
  (let* ((words '("ཡུལ" "འཐོན"))
         (mwu '((0 1 "ཡུལ་འཐོན" nil)))
         (clauses (tibetan-clause-segment
                   words
                   (list (tibetan-round2-test--verb "འཐོན" 1))
                   mwu))
         (nps (tibetan-np-chunk words clauses mwu))
         (heads (mapcar (lambda (np) (alist-get 'head np)) nps)))
    (should (member "ཡུལ" heads))
    (should-not (member "ཡུལ་འཐོན" heads))))

(ert-deftest tibetan-round2-np-mwu-truncated-when-verb-inside ()
  "When a verb position falls strictly inside an MWU span (not at the
start), the MWU is truncated to end just before the verb so the
preceding piece is still emitted as an NP head."
  (let* ((words '("ཀོ" "རོན" "འཐོན"))
         (mwu '((0 2 "ཀོ་རོན་འཐོན" nil)))
         (clauses (tibetan-clause-segment
                   words
                   (list (tibetan-round2-test--verb "འཐོན" 2))
                   mwu))
         (nps (tibetan-np-chunk words clauses mwu))
         (heads (mapcar (lambda (np) (alist-get 'head np)) nps)))
    (should (member "ཀོ་རོན" heads))
    (should-not (member "ཀོ་རོན་འཐོན" heads))))

(ert-deftest tibetan-round2-np-glue-stops-at-mwu-boundary ()
  "Content-word gluing stops when the next position starts an MWU,
so the MWU branch can take over.  Without this, the chunker would
absorb the MWU's first syllable into the preceding NP."
  (let* ((words '("ཨ" "ཀྱང་ཕོ" "ཀོ་རོན" "སར"))
         ;; Non-verbal MWU at positions 2-3 ("ཀོ་རོན་སར" place-name);
         ;; chunker should treat it as one NP, not glue ཀྱང་ཕོ + ཀོ་རོན.
         (mwu '((2 4 "ཀོ་རོན་སར" ((english . "to Ko ron sa")))))
         (verbs '())
         (clauses '(((start . 0) (end . 3) (type . main)
                     (verb . ((lemma . "x") (source-pos . 99))))))
         (nps (tibetan-np-chunk words clauses mwu))
         (heads (mapcar (lambda (np) (alist-get 'head np)) nps)))
    (should (member "ཀོ་རོན་སར" heads))
    ;; ཨ and ཀྱང་ཕོ should remain separate from the MWU, not glued.
    (should-not (cl-some (lambda (h) (string-match-p "ཀྱང་ཕོ་ཀོ་རོན" h))
                         heads))))

(ert-deftest tibetan-round2-np-skips-verbal-mwu ()
  "A verb-bearing MWU (light-verb compound like `ཆུང་མ་བྱེད') IS the
clause's predicate — it must not surface as an NP at all.  The
verb extractor records the head verb separately."
  (let* ((words '("ཨ་ཁུའི" "ཆུང" "མ" "བྱེད"))
         ;; Verbal MWU: english starts with "to " → verbal-meta-p.
         (mwu '((1 4 "ཆུང་མ་བྱེད" ((english . "to become wife of")))))
         (verbs (list (tibetan-round2-test--verb "བྱེད" 3)))
         (clauses (tibetan-clause-segment words verbs mwu))
         (nps (tibetan-np-chunk words clauses mwu))
         (heads (mapcar (lambda (np) (alist-get 'head np)) nps)))
    ;; The verbal MWU is NOT emitted as an NP head.
    (should-not (member "ཆུང་མ་བྱེད" heads))
    (should-not (member "ཆུང་མ" heads))
    (should-not (member "ཆུང" heads))
    ;; The preceding NP is intact (not glued past the MWU start);
    ;; case-suffix GEN `འི' is stripped so the head reads `ཨ་ཁུ'.
    (should (member "ཨ་ཁུ" heads))))

(ert-deftest tibetan-round2-segment-filters-modal-and-reporter ()
  "Modal (`is-modal') and reporter (`is-reporter') auxiliaries do not
form their own clauses — they chain onto a content verb.  Without
this filter, `...བྱེད་དགོས་ཟེར' would produce three [main] clauses
instead of one (`བྱེད', with `+MODAL:དགོས +SAYS:ཟེར' annotations
surfaced by the Sentence Structure renderer)."
  (let* ((words '("ཁོང" "བྱེད" "དགོས" "ཟེར"))
         (verbs (list `((lemma . "བྱེད") (source-pos . 1)
                        (source-form . "བྱེད")
                        (is-modal . nil) (is-reporter . nil))
                      `((lemma . "དགོས") (source-pos . 2)
                        (source-form . "དགོས")
                        (is-modal . t)   (is-reporter . nil))
                      `((lemma . "ཟེར")  (source-pos . 3)
                        (source-form . "ཟེར")
                        (is-modal . nil) (is-reporter . t))))
         (clauses (tibetan-clause-segment words verbs nil))
         (lemmas (mapcar (lambda (c)
                           (alist-get 'lemma (alist-get 'verb c)))
                         clauses)))
    (should (= (length clauses) 1))
    (should (member "བྱེད" lemmas))
    (should-not (member "དགོས" lemmas))
    (should-not (member "ཟེར" lemmas))
    ;; aux-positions records the filtered modal/reporter source-pos so
    ;; the NP chunker can skip them.
    (let ((aux (alist-get 'aux-positions (car clauses))))
      (should (member 2 aux))
      (should (member 3 aux)))))

(ert-deftest tibetan-round2-np-skips-aux-positions ()
  "When a clause has `aux-positions' (modal/reporter auxiliaries
filtered from clause-segmentation), the NP chunker must NOT absorb
those positions into surrounding NPs."
  (let* ((words '("ཁོང" "བྱེད" "དགོས" "ཟེར"))
         (verbs (list `((lemma . "བྱེད") (source-pos . 1)
                        (source-form . "བྱེད")
                        (is-modal . nil) (is-reporter . nil))
                      `((lemma . "དགོས") (source-pos . 2)
                        (source-form . "དགོས")
                        (is-modal . t)   (is-reporter . nil))
                      `((lemma . "ཟེར")  (source-pos . 3)
                        (source-form . "ཟེར")
                        (is-modal . nil) (is-reporter . t))))
         (clauses (tibetan-clause-segment words verbs nil))
         (nps (tibetan-np-chunk words clauses nil))
         (heads (mapcar (lambda (np) (alist-get 'head np)) nps)))
    ;; Only `ཁོང' is a real NP; `དགོས' / `ཟེར' must NOT show up as NP heads.
    (should (member "ཁོང" heads))
    (should-not (cl-some (lambda (h) (string-match-p "དགོས" h)) heads))
    (should-not (cl-some (lambda (h) (string-match-p "ཟེར" h)) heads))))

(ert-deftest tibetan-round2-mwu-verbal-p-recognizes-sanskrit-absolutive ()
  "Steinert bilingual glosses for converb-marked verbs like `གསོལ་ནས'
are typically Sanskrit absolutives (`bhuktvā', `pītvā',
`jñāpayitvā').  `tibetan-clause-seg--mwu-verbal-p' must recognise
that pattern so these MWUs are correctly classified as verbal."
  (should (tibetan-clause-seg--mwu-verbal-p
           '(0 2 "གསོལ་ནས"
               ((english . "bhuktvā — having eaten (honorific)")))))
  (should (tibetan-clause-seg--mwu-verbal-p
           '(0 3 "FAKE་པ་ནས"
               ((english . "jñāpayitvā")))))
  ;; Non-verb glosses that happen to contain Latin letters must NOT
  ;; false-match (e.g. ordinary noun glosses).
  (should-not (tibetan-clause-seg--mwu-verbal-p
               '(0 2 "FAKE་NOUN"
                   ((english . "instructor; teacher [Hopkins2015]"))))))

(ert-deftest tibetan-round2-segment-tolerates-malformed-verbs ()
  "`tibetan-clause-segment' is a public entry point; a malformed VERBS
element (a bare word-string instead of a verb alist) must not crash
with `wrong-type-argument listp' (the §5.9 / P5 crash class).  Such
elements are ignored; valid verb alists are still processed."
  (let ((words '("བདག" "གིས" "ལས" "བྱས")))
    ;; All-malformed → no crash, no clauses from the junk.
    (should (listp (tibetan-clause-segment words '("གྱུར" "junk") nil)))
    ;; Mixed: the one valid verb alist is still segmented.
    (let ((clauses (tibetan-clause-segment
                    words
                    (list "stray-string"
                          (tibetan-round2-test--verb "བྱས" 3))
                    nil)))
      (should (= (length clauses) 1)))))

(ert-deftest tibetan-round2-np-pas-after-noun-is-ergative ()
  "Phase 2 (verb-first redesign): standalone པས AFTER A NOUN is the
nominaliser པ + ergative ས (`མར་པས' = Mar pa + ERG), not a causal
converb.  The converb-first classification destroyed the ergative so
the agent NP never existed for role assignment (the bla-ma mislabel's
second root)."
  (skip-unless (fboundp 'tibetan-np-chunk))
  ;; bla ma mar pas chos byed : NP1 = bla-ma-mar-pa ERG, NP2 = chos.
  (let* ((words '("བླ་མ" "མར" "པས" "ཆོས" "བྱེད"))
         (verbs (list `((lemma . "བྱེད") (source-pos . 4))))
         (clauses (tibetan-clause-segment words verbs))
         (nps (tibetan-np-chunk words clauses)))
    (let ((erg (cl-find-if (lambda (np) (eq (alist-get 'case np) 'ERG))
                           nps)))
      (should erg)
      (should (string-match-p "བླ་མ" (alist-get 'head erg)))
      (should (string-match-p "པ\\'" (alist-get 'head erg))))))

(ert-deftest tibetan-round2-np-nas-after-noun-is-ablative ()
  "Standalone ནས after a NOUN is the ablative case, not an ablative
converb (which only follows verbs)."
  (skip-unless (fboundp 'tibetan-np-chunk))
  ;; khang pa nas 'gro : NP = khang-pa ABL.
  (let* ((words '("ཁང་པ" "ནས" "འགྲོ"))
         (verbs (list `((lemma . "འགྲོ") (source-pos . 2))))
         (clauses (tibetan-clause-segment words verbs))
         (nps (tibetan-np-chunk words clauses)))
    (should (cl-find-if (lambda (np)
                          (and (eq (alist-get 'case np) 'ABL)
                               (string-match-p "ཁང" (alist-get 'head np))))
                        nps))))

(provide 'tibetan-round2-clause-segmenter-test)
;;; tibetan-round2-clause-segmenter-test.el ends here
