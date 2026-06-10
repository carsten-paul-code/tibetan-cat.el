;;; tibetan-sentence-tree.el --- Verb-first sentence-structure trees -*- lexical-binding: t -*-

;;; Commentary:
;; Verb-first (head-driven) grammar analysis.  Classical Tibetan is
;; verb-final: the FINAL verb is the head of the sentence; its Hill
;; 2010 case frame predicts the expected arguments (ergative agent,
;; absolutive patient, ...); case-marked NPs fill those slots (each at
;; most once), the remainder are labelled adjuncts, and converb
;; clauses chain to the main verb.
;;
;; This module replaces the flat case→role mapping of
;; `tibetan-build-argument-structure' (analysis/tibetan-clause-
;; segmenter.el Part C), whose lack of slot saturation labelled every
;; bare NP in an "Erg-Abs" clause a patient (the seg-37 `bla ma' =
;; DIRECT OBJECT bug).
;;
;; Phase 1 (this file's lower half): the pure frame slot engine.
;;   `tibetan-frame-slots'        frame string → ordered slot plists
;;   `tibetan-frame-fill-slots'   slots + NPs → filled slots + adjuncts
;;   `tibetan-frame--attach-genitives'  GEN NPs → :possessors
;;   `tibetan-frame--merge-coordinates' dang-coordination merge
;;
;; Later phases add `tibetan-analyze-sentence' (the tree builder) on
;; top of the clause segmenter's Parts A+B.

;;; Code:

(require 'cl-lib)
;; Substrate: clause segmentation + NP chunking (Parts A+B).  Soft so
;; the pure slot engine stays loadable in minimal batch environments.
(require 'tibetan-clause-segmenter nil t)
(require 'tibetan-verb-classifier nil t)

;; ----------------------------------------------------------------------------
;; Frame slot specs
;; ----------------------------------------------------------------------------

(defconst tibetan-frame--slot-specs
  '(("Erg-Abs"     . ((agent     (ERG)      t)
                      (patient   (ABS)      t)))
    ("Erg-Abs-Dat" . ((agent     (ERG)      t)
                      (patient   (ABS)      t)
                      (recipient (DAT)      t)))
    ;; The causative frame (འཇུག/བཅུག): agent puts the causee INTO an
    ;; activity — the activity slot surfaces as LOC or the V+du
    ;; terminative complement.
    ("Erg-Abs-Loc" . ((agent      (ERG)      t)
                      (causee     (ABS)      t)
                      (complement (LOC TERM) nil)))
    ("Abs"         . ((subject   (ABS)      t)))
    ("Abs-Abs"     . ((subject   (ABS)      t)
                      (predicate (ABS)      t)))
    ("Abs-Loc"     . ((subject   (ABS)      t)
                      (location  (LOC)      nil)))
    ("Abs-Term"    . ((subject   (ABS)      t)
                      (goal      (TERM)     nil)))
    ("Abs-Abl"     . ((subject   (ABS)      t)
                      (source    (ABL)      nil))))
  "Hill 2010 case-frame strings → ordered argument slots.
Each slot is (ROLE CASES REQUIRED): ROLE a symbol, CASES the case
tags that can fill it (a bare NP may fill an ABS slot — Tibetan
absolutive is zero-marked), REQUIRED non-nil when an unfilled slot
should render as elided (Tibetan pro-drop pedagogy).")

(defun tibetan-frame-slots (frame)
  "Return the ordered slot plists for FRAME (a case-frame string).
Each element is (:role R :cases (C...) :required B).  nil for an
unknown or nil FRAME — the caller then treats every NP as an adjunct."
  (when (and frame (stringp frame))
    (mapcar (lambda (spec)
              (list :role (nth 0 spec)
                    :cases (nth 1 spec)
                    :required (nth 2 spec)))
            (cdr (assoc frame tibetan-frame--slot-specs)))))

;; ----------------------------------------------------------------------------
;; NP post-passes
;; ----------------------------------------------------------------------------

(defun tibetan-frame--attach-genitives (nps)
  "Fold each GEN-cased NP into the FOLLOWING NP as a possessor.
Returns a new NP list where the following NP carries an extra
`(possessors . (NP ...))' alist entry.  A GEN NP with no following NP
(dangling, e.g. sentence-final) is kept as-is.  Input NPs are the
chunker alists; output preserves their shape."
  (let ((out '()) (pending '()))
    (dolist (np nps)
      (if (eq (alist-get 'case np) 'GEN)
          (push np pending)
        (let ((np2 (copy-alist np)))
          (when pending
            (setf (alist-get 'possessors np2) (nreverse pending))
            (setq pending '()))
          (push np2 out))))
    ;; Dangling genitives: keep them so nothing silently vanishes
    ;; (the M4 lesson — every NP must surface somewhere).
    (dolist (g (nreverse pending)) (push g out))
    (nreverse out)))

(defun tibetan-frame--merge-coordinates (nps)
  "Merge each COM-cased NP with the IMMEDIATELY FOLLOWING NP.
`X dang Y' is a coordination: the pair becomes one NP whose head is
\"X дང Y\"-style concatenation, carrying the SECOND NP's case (the
coordination's shared case marking sits on the final conjunct in
Tibetan) plus `(coordinated . t)'.  A dangling COM NP is kept as-is."
  (let ((out '()) (pending nil))
    (dolist (np nps)
      (cond
       ((eq (alist-get 'case np) 'COM)
        ;; Chain: an earlier pending COM merges into this one.
        (setq pending
              (if pending
                  (let ((m (copy-alist np)))
                    (setf (alist-get 'head m)
                          (concat (alist-get 'head pending) "་དང་"
                                  (alist-get 'head np)))
                    (setf (alist-get 'start m) (alist-get 'start pending))
                    m)
                np)))
       (pending
        (let ((m (copy-alist np)))
          (setf (alist-get 'head m)
                (concat (alist-get 'head pending) "་དང་"
                        (alist-get 'head np)))
          (setf (alist-get 'start m) (alist-get 'start pending))
          (setf (alist-get 'coordinated m) t)
          (push m out)
          (setq pending nil)))
       (t (push np out))))
    (when pending (push pending out))
    (nreverse out)))

;; ----------------------------------------------------------------------------
;; Slot filling
;; ----------------------------------------------------------------------------

(defun tibetan-frame--np-distance (np verb-pos)
  "Distance from NP's end to VERB-POS (smaller = nearer the verb)."
  (abs (- verb-pos (or (alist-get 'end np) 0))))

(defun tibetan-frame-fill-slots (slots nps verb-pos)
  "Fill SLOTS (from `tibetan-frame-slots') with candidate NPS.
VERB-POS is the head verb's word position, used for proximity
tie-breaks.  Returns (:slots FILLED :adjuncts LEFTOVER) where each
filled slot plist gains `:filler NP-or-nil' and `:elided B'.

Algorithm (saturation — each slot at most once, each NP at most once):
1. Explicitly-cased NPs claim matching slots: the agent slot takes the
   LEFTMOST ERG; other slots take their case's NPs in textual order.
2. Bare NPs (case nil) fill still-open ABS slots: a single open ABS
   slot takes the bare NP NEAREST the verb (patient position); the
   Abs-Abs copula's two slots fill in textual order.
3. NPs left over become adjuncts; required unfilled slots are elided."
  (let* ((remaining (copy-sequence (or nps '())))
         (filled '()))
    (dolist (slot (or slots '()))
      (let* ((cases (plist-get slot :cases))
             (role (plist-get slot :role))
             ;; Pass 1: explicit case match.
             (candidates (cl-remove-if-not
                          (lambda (np) (memq (alist-get 'case np) cases))
                          remaining))
             (pick
              (cond
               ((null candidates) nil)
               ;; Agent: leftmost ERG.
               ((eq role 'agent)
                (car (cl-sort (copy-sequence candidates) #'<
                              :key (lambda (np) (or (alist-get 'start np) 0)))))
               ;; Default: textual order.
               (t (car (cl-sort (copy-sequence candidates) #'<
                                :key (lambda (np)
                                       (or (alist-get 'start np) 0))))))))
        (push (append slot (list :filler pick :elided nil)) filled)
        (when pick (setq remaining (delq pick remaining)))))
    (setq filled (nreverse filled))
    ;; Pass 2: bare NPs into still-open ABS slots.
    (let ((open-abs (cl-remove-if-not
                     (lambda (s) (and (memq 'ABS (plist-get s :cases))
                                      (null (plist-get s :filler))))
                     filled))
          (bare (cl-sort (cl-remove-if-not
                          (lambda (np) (null (alist-get 'case np)))
                          remaining)
                         #'< :key (lambda (np) (or (alist-get 'start np) 0)))))
      (cond
       ;; Two open ABS slots (Abs-Abs copula): textual order.
       ((>= (length open-abs) 2)
        (cl-loop for s in open-abs
                 for np in bare
                 do (progn
                      (plist-put s :filler np)
                      (setq remaining (delq np remaining)))))
       ;; One open ABS slot: bare NP nearest the verb (patient slot).
       ((= (length open-abs) 1)
        (when bare
          (let ((nearest (car (cl-sort (copy-sequence bare) #'<
                                       :key (lambda (np)
                                              (tibetan-frame--np-distance
                                               np verb-pos))))))
            (plist-put (car open-abs) :filler nearest)
            (setq remaining (delq nearest remaining)))))))
    ;; Mark elided required slots.
    (dolist (s filled)
      (when (and (plist-get s :required) (null (plist-get s :filler)))
        (plist-put s :elided t)))
    (list :slots filled :adjuncts remaining)))

;; ----------------------------------------------------------------------------
;; Phase 3 — verb-headed tree builder
;; ----------------------------------------------------------------------------

(declare-function tibetan-clause-segment "tibetan-clause-segmenter")
(declare-function tibetan-np-chunk "tibetan-clause-segmenter")
(declare-function tibetan-clause-seg--lookup-case-frame
                  "tibetan-clause-segmenter")

(defconst tibetan-sentence-tree--term-particles '("དུ" "ཏུ" "སུ" "རུ" "ར")
  "Standalone terminative particles that mark a V+TERM complement
clause (`byed du' under `bcug').")

(defun tibetan-sentence-tree--build-node (clause nps)
  "Build a tree node for CLAUSE from its candidate NPS.
Runs the NP post-passes (genitive attachment, dang-coordination),
looks up the verb's Hill case frame, and fills the frame slots.
Returns the node plist (without :complements/:converbs — the caller
attaches those)."
  (let* ((verb (alist-get 'verb clause))
         (lemma (alist-get 'lemma verb))
         (frame (and lemma
                     (fboundp 'tibetan-clause-seg--lookup-case-frame)
                     (tibetan-clause-seg--lookup-case-frame lemma)))
         (vpos (or (alist-get 'source-pos verb)
                   (alist-get 'end clause) 0))
         (prepped (tibetan-frame--merge-coordinates
                   (tibetan-frame--attach-genitives (or nps '()))))
         (fill (tibetan-frame-fill-slots
                (tibetan-frame-slots frame) prepped vpos)))
    (list :verb verb :frame frame :clause clause
          :slots (plist-get fill :slots)
          :adjuncts (plist-get fill :adjuncts)
          :complements nil :converbs nil)))

(defun tibetan-sentence-tree--complement-p (clause words)
  "Non-nil when CLAUSE's verb is immediately followed by a standalone
terminative particle — the V+TERM complement pattern (byed du …)."
  (let* ((verb (alist-get 'verb clause))
         (vpos (alist-get 'source-pos verb)))
    (and vpos
         (< (1+ vpos) (length words))
         (member (string-trim (nth (1+ vpos) words))
                 tibetan-sentence-tree--term-particles))))

(defun tibetan-analyze-sentence (words verbs &optional mwu)
  "Verb-first analysis of WORDS/VERBS: return the head-driven tree.

The FINAL clause's verb is the root.  Its Hill case frame is filled
from the root clause's NPs (with the matrix-ERG-claiming rule: an
unfilled agent slot may claim the leftmost ERG NP from a complement
clause's span — V+du complements essentially never carry their own
overt ergative agent).  Non-final clauses attach as :complements
\(V+TERM pattern) or :converbs (with their Bialek label), each
recursively slot-filled from its own remaining NPs.

Tree node shape:
  (:verb V :frame STR|nil :clause CLAUSE
   :slots (...) :adjuncts (NP ...)
   :complements ((:complement-case TERM :node NODE) ...)
   :converbs    ((:label SYM :particle STR :node NODE) ...))

Returns nil when the substrate is unavailable or no clause is found."
  (when (and words verbs
             (fboundp 'tibetan-clause-segment)
             (fboundp 'tibetan-np-chunk))
    (let* ((clauses (tibetan-clause-segment words verbs mwu))
           (nps (tibetan-np-chunk words clauses mwu))
           (n (length clauses)))
      (when (> n 0)
        (let ((pools (make-vector n nil)))
          ;; Group NPs by clause-index.
          (dolist (np nps)
            (let ((ci (or (alist-get 'clause-index np) 0)))
              (when (< ci n)
                (aset pools ci (append (aref pools ci) (list np))))))
          (let* ((main-idx (1- n))
                 (main-clause (nth main-idx clauses))
                 (comp-idxs '())
                 (conv-idxs '()))
            (dotimes (i main-idx)
              (if (tibetan-sentence-tree--complement-p (nth i clauses) words)
                  (push i comp-idxs)
                (push i conv-idxs)))
            (setq comp-idxs (nreverse comp-idxs)
                  conv-idxs (nreverse conv-idxs))
            ;; Matrix-ERG claim: when the root frame has an agent slot
            ;; and the root pool carries no ERG NP, the leftmost ERG NP
            ;; inside a COMPLEMENT clause's span fills the matrix agent.
            (let* ((root-verb (alist-get 'verb main-clause))
                   (root-frame (and (fboundp
                                     'tibetan-clause-seg--lookup-case-frame)
                                    (tibetan-clause-seg--lookup-case-frame
                                     (alist-get 'lemma root-verb))))
                   (wants-agent
                    (assq 'agent (cdr (assoc root-frame
                                             tibetan-frame--slot-specs))))
                   (root-has-erg
                    (cl-find-if (lambda (np)
                                  (eq (alist-get 'case np) 'ERG))
                                (aref pools main-idx))))
              (when (and wants-agent (not root-has-erg))
                (catch 'claimed
                  (dolist (ci comp-idxs)
                    (let ((erg (cl-find-if
                                (lambda (np)
                                  (eq (alist-get 'case np) 'ERG))
                                (aref pools ci))))
                      (when erg
                        (aset pools ci (delq erg (aref pools ci)))
                        (aset pools main-idx
                              (cons erg (aref pools main-idx)))
                        (throw 'claimed t)))))))
            ;; Build root + children.
            (let ((root (tibetan-sentence-tree--build-node
                         main-clause (aref pools main-idx))))
              (plist-put root :complements
                         (mapcar
                          (lambda (ci)
                            (list :complement-case 'TERM
                                  :node (tibetan-sentence-tree--build-node
                                         (nth ci clauses) (aref pools ci))))
                          comp-idxs))
              (plist-put root :converbs
                         (mapcar
                          (lambda (ci)
                            (let ((c (nth ci clauses)))
                              (list :label (alist-get 'converb-type c)
                                    :particle (alist-get 'converb-particle c)
                                    :node (tibetan-sentence-tree--build-node
                                           c (aref pools ci)))))
                          conv-idxs))
              root)))))))

(provide 'tibetan-sentence-tree)
;;; tibetan-sentence-tree.el ends here
