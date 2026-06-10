;;; tibetan-sentence-tree-test.el --- Tests for verb-first sentence trees -*- lexical-binding: t -*-

;;; Commentary:
;; Phase 1 of the verb-first redesign: the frame slot engine.
;; Pure-data tests — NP alists are hand-built in the chunker shape
;; ((start . s) (end . e) (head . H) (case . C) ...), no parser, no
;; network.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-sentence-tree)

(defun tstree-np (start end head &optional case)
  "Build a chunker-shaped NP alist for tests."
  `((start . ,start) (end . ,end) (head . ,head) (case . ,case)))

;; ----------------------------------------------------------------------------
;; Frame → slot specs
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-frame-slots-erg-abs-shape ()
  "\"Erg-Abs\" yields agent(ERG, required) then patient(ABS, required)."
  (let ((slots (tibetan-frame-slots "Erg-Abs")))
    (should (= 2 (length slots)))
    (should (eq 'agent (plist-get (nth 0 slots) :role)))
    (should (equal '(ERG) (plist-get (nth 0 slots) :cases)))
    (should (plist-get (nth 0 slots) :required))
    (should (eq 'patient (plist-get (nth 1 slots) :role)))
    (should (equal '(ABS) (plist-get (nth 1 slots) :cases)))))

(ert-deftest tibetan-frame-slots-covers-all-attested-frames ()
  "All 8 frame strings in the verb DB return slot lists; unknown → nil."
  (dolist (f '("Erg-Abs" "Erg-Abs-Dat" "Erg-Abs-Loc" "Abs" "Abs-Abs"
               "Abs-Loc" "Abs-Term" "Abs-Abl"))
    (should (tibetan-frame-slots f)))
  (should-not (tibetan-frame-slots "Bogus-Frame"))
  (should-not (tibetan-frame-slots nil)))

;; ----------------------------------------------------------------------------
;; Slot filling: saturation, proximity, elision, adjuncts
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-frame-fill-saturation-second-erg-is-adjunct ()
  "Each slot is filled at most once: a second ERG NP becomes an adjunct."
  (let* ((nps (list (tstree-np 0 1 "བདག" 'ERG)
                    (tstree-np 2 3 "རྒྱལ་པོ" 'ERG)
                    (tstree-np 4 5 "ཆོས" nil)))
         (res (tibetan-frame-fill-slots
               (tibetan-frame-slots "Erg-Abs") nps 6))
         (agent (cl-find-if (lambda (s) (eq (plist-get s :role) 'agent))
                            (plist-get res :slots))))
    (should (equal "བདག" (alist-get 'head (plist-get agent :filler))))
    (should (= 1 (length (plist-get res :adjuncts))))
    (should (equal "རྒྱལ་པོ"
                   (alist-get 'head (car (plist-get res :adjuncts)))))))

(ert-deftest tibetan-frame-fill-proximity-patient-nearest-preceding ()
  "With ERG filled and TWO bare NPs, the patient slot takes the bare NP
NEAREST the verb; the other becomes an adjunct (the bla-ma bug class)."
  (let* ((nps (list (tstree-np 0 2 "བླ་མ" nil)     ; far from verb
                    (tstree-np 3 4 "མར་པ" 'ERG)
                    (tstree-np 5 7 "ལས་ཀ" nil)))   ; nearest verb @8
         (res (tibetan-frame-fill-slots
               (tibetan-frame-slots "Erg-Abs") nps 8))
         (patient (cl-find-if (lambda (s) (eq (plist-get s :role) 'patient))
                              (plist-get res :slots))))
    (should (equal "ལས་ཀ" (alist-get 'head (plist-get patient :filler))))
    ;; bla-ma is NOT the patient — it is an adjunct.
    (should (member "བླ་མ"
                    (mapcar (lambda (np) (alist-get 'head np))
                            (plist-get res :adjuncts))))))

(ert-deftest tibetan-frame-fill-abs-abs-copula-two-bare-nps ()
  "Abs-Abs copula: two bare NPs fill subject then predicate in textual
order; nothing is ever labelled patient."
  (let* ((nps (list (tstree-np 0 1 "འདི" nil)
                    (tstree-np 2 3 "ཆོས" nil)))
         (res (tibetan-frame-fill-slots
               (tibetan-frame-slots "Abs-Abs") nps 4))
         (roles (mapcar (lambda (s)
                          (cons (plist-get s :role)
                                (and (plist-get s :filler)
                                     (alist-get 'head (plist-get s :filler)))))
                        (plist-get res :slots))))
    (should (equal '((subject . "འདི") (predicate . "ཆོས")) roles))
    (should-not (plist-get res :adjuncts))))

(ert-deftest tibetan-frame-fill-unfilled-required-slot-marked-elided ()
  "Erg-Abs with no NPs at all: both required slots are elided."
  (let ((res (tibetan-frame-fill-slots
              (tibetan-frame-slots "Erg-Abs") nil 3)))
    (should (cl-every (lambda (s) (plist-get s :elided))
                      (plist-get res :slots)))))

(ert-deftest tibetan-frame-fill-no-frame-all-nps-adjuncts ()
  "nil frame → no slots; every NP is an adjunct."
  (let ((res (tibetan-frame-fill-slots
              nil (list (tstree-np 0 1 "ཁང་པ" 'LOC)) 2)))
    (should-not (plist-get res :slots))
    (should (= 1 (length (plist-get res :adjuncts))))))

;; ----------------------------------------------------------------------------
;; NP post-passes
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-frame-attach-genitive-as-possessor ()
  "A GEN NP folds into the FOLLOWING NP's :possessors; a dangling
sentence-final GEN stays in the list."
  (let* ((nps (list (tstree-np 0 1 "རྔོག" 'GEN)
                    (tstree-np 2 3 "དྲུང" 'TERM)))
         (out (tibetan-frame--attach-genitives nps)))
    (should (= 1 (length out)))
    (should (equal "དྲུང" (alist-get 'head (car out))))
    (should (equal "རྔོག"
                   (alist-get 'head (car (alist-get 'possessors (car out)))))))
  ;; Dangling GEN survives unattached.
  (let ((out (tibetan-frame--attach-genitives
              (list (tstree-np 0 1 "བདག" 'GEN)))))
    (should (= 1 (length out)))
    (should (eq 'GEN (alist-get 'case (car out))))))

(ert-deftest tibetan-frame-merge-dang-coordination ()
  "NP(COM) + adjacent NP merge into one coordinated NP carrying the
second NP's case."
  (let* ((nps (list (tstree-np 0 2 "འཁར་ལས" 'COM)
                    (tstree-np 3 5 "ཕྲུ་རློག" 'DAT)))
         (out (tibetan-frame--merge-coordinates nps)))
    (should (= 1 (length out)))
    (should (eq 'DAT (alist-get 'case (car out))))
    (should (alist-get 'coordinated (car out)))
    (should (string-match-p "འཁར་ལས" (alist-get 'head (car out))))
    (should (string-match-p "ཕྲུ་རློག" (alist-get 'head (car out))))))

;; ----------------------------------------------------------------------------
;; Phase 3 — verb-headed tree builder (acceptance battery)
;; ----------------------------------------------------------------------------

(defun tstree-slot-head (tree role)
  "Head string of TREE's filled slot ROLE, or nil."
  (let ((s (cl-find-if (lambda (x) (eq (plist-get x :role) role))
                       (plist-get tree :slots))))
    (and s (plist-get s :filler)
         (alist-get 'head (plist-get s :filler)))))

(defun tstree-all-fillers (tree)
  "All filled NP heads anywhere in TREE (slots + subtrees)."
  (append
   (cl-loop for s in (plist-get tree :slots)
            when (plist-get s :filler)
            collect (cons (plist-get s :role)
                          (alist-get 'head (plist-get s :filler))))
   (cl-loop for c in (plist-get tree :complements)
            append (tstree-all-fillers (plist-get c :node)))
   (cl-loop for c in (plist-get tree :converbs)
            append (tstree-all-fillers (plist-get c :node)))))

(ert-deftest tibetan-sentence-tree-bcug-causative ()
  "The seg-37/97 flagship: `bla ma mar pas ... byed du bcug'.
Root = བཅུག (lemma འཇུག, Erg-Abs-Loc); the AGENT is bla-ma-mar-pa
\(ERG, via Phase 2); byed-du is a nested COMPLEMENT; and — the
negative assertion that pins the old bug dead — bla-ma is NOBODY's
patient/causee."
  (skip-unless (and (fboundp 'tibetan-verb-lookup)
                    (tibetan-verb-lookup "འཇུག")))
  (let* ((words '("བླ་མ" "མར" "པས" "འཁར" "ལས" "མང་པོ" "དང"
                  "ཕྲུ་རློག" "ལ" "སོགས་པ" "བྱེད" "དུ" "བཅུག"))
         (verbs (list `((lemma . "བྱེད") (source-pos . 10))
                      `((lemma . "འཇུག") (source-pos . 12))))
         (tree (tibetan-analyze-sentence words verbs)))
    (should tree)
    ;; Root verb is the FINAL one.
    (should (equal "འཇུག" (alist-get 'lemma (plist-get tree :verb))))
    (should (equal "Erg-Abs-Loc" (plist-get tree :frame)))
    ;; Agent = bla-ma-mar-pa (ERG claimed across the complement span).
    (should (equal "བླ་མ་མར་པ" (tstree-slot-head tree 'agent)))
    ;; byed-du is a complement child.
    (should (= 1 (length (plist-get tree :complements))))
    (should (equal "བྱེད"
                   (alist-get 'lemma
                              (plist-get
                               (plist-get (car (plist-get tree :complements))
                                          :node)
                               :verb))))
    ;; bla-ma fills NO patient/causee slot anywhere in the tree.
    (should-not (cl-find-if
                 (lambda (pair)
                   (and (memq (car pair) '(patient causee))
                        (string-match-p "བླ་མ" (cdr pair))))
                 (tstree-all-fillers tree)))))

(ert-deftest tibetan-sentence-tree-phyin-elided-subject ()
  "`rngog gi drung du phyin nas': frame Abs → subject ELIDED; the
TERM NP is an adjunct carrying the GEN possessor རྔོག."
  (skip-unless (and (fboundp 'tibetan-verb-lookup)
                    (tibetan-verb-lookup "འགྲོ")))
  (let* ((words '("རྔོག" "གི" "དྲུང" "དུ" "ཕྱིན" "ནས"))
         (verbs (list `((lemma . "འགྲོ") (source-pos . 4))))
         (tree (tibetan-analyze-sentence words verbs)))
    (should (equal "Abs" (plist-get tree :frame)))
    (let ((subj (cl-find-if (lambda (s) (eq (plist-get s :role) 'subject))
                            (plist-get tree :slots))))
      (should (plist-get subj :elided)))
    (let ((adj (cl-find-if (lambda (np) (eq (alist-get 'case np) 'TERM))
                           (plist-get tree :adjuncts))))
      (should adj)
      (should (string-match-p "དྲུང" (alist-get 'head adj)))
      (should (equal "རྔོག"
                     (alist-get 'head
                                (car (alist-get 'possessors adj))))))))

(ert-deftest tibetan-sentence-tree-converb-chain-order ()
  "A dependent converb clause chains to the main verb with its label."
  (skip-unless (and (fboundp 'tibetan-verb-lookup)
                    (tibetan-verb-lookup "བྱེད")))
  ;; kho song nas chos byas : song+nas dependent (ablative), byas main.
  (let* ((words '("ཁོ" "སོང" "ནས" "ཆོས" "བྱས"))
         (verbs (list `((lemma . "འགྲོ") (source-pos . 1))
                      `((lemma . "བྱེད") (source-pos . 4))))
         (tree (tibetan-analyze-sentence words verbs)))
    (should (equal "བྱེད" (alist-get 'lemma (plist-get tree :verb))))
    (should (= 1 (length (plist-get tree :converbs))))
    (let ((cv (car (plist-get tree :converbs))))
      (should (eq 'ablative (plist-get cv :label)))
      (should (equal "འགྲོ"
                     (alist-get 'lemma
                                (plist-get (plist-get cv :node) :verb)))))))

(ert-deftest tibetan-sentence-tree-copula-abs-abs ()
  "`X Y yin': subject + predicate in textual order, no patients."
  (skip-unless (and (fboundp 'tibetan-verb-lookup)
                    (tibetan-verb-lookup "ཡིན")))
  ;; ནི (topic) separates the two bare NPs — without a separator,
  ;; juxtaposed bare nouns are indistinguishable from one compound.
  (let* ((words '("འདི" "ནི" "ཆོས" "ཡིན"))
         (verbs (list `((lemma . "ཡིན") (source-pos . 3))))
         (tree (tibetan-analyze-sentence words verbs)))
    (should (equal "Abs-Abs" (plist-get tree :frame)))
    (should (equal "འདི" (tstree-slot-head tree 'subject)))
    (should (equal "ཆོས" (tstree-slot-head tree 'predicate)))
    (should-not (plist-get tree :adjuncts))))

(provide 'tibetan-sentence-tree-test)
;;; tibetan-sentence-tree-test.el ends here
