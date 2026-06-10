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

(provide 'tibetan-sentence-tree-test)
;;; tibetan-sentence-tree-test.el ends here
