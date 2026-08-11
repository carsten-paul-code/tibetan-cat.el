;;; sentence-first-spec.el --- BDD: sentence-first fill end-to-end -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Part B Phase 0+1 (2026-07-28): ONE whole-sentence Claude call fans
;; out to every child seg file and the sent file; a second non-FORCE
;; run must leave populated children byte-identical.  These specs run
;; the REAL pipeline — dispatcher → claim → queue → gptel → response
;; landing — with only the process edges stubbed:
;;
;;   - `tibetan-claude-queue-submit' runs the thunk synchronously
;;   - `gptel-request' invokes its :callback with a canned response
;;     (the gptel feature flag is bound dynamically, not provided)
;;   - `run-at-time' executes immediately (the fan-out and the DM
;;     stagger both defer through it; DM's HTTP layer is stubbed
;;     globally by run-specs.el, so the DM leg is a silent no-op)
;;
;; No network, no timers, deterministic.

;;; Code:

(require 'tibetan-bdd)
(require 'cl-lib)
;; The whole pipeline under test — explicit requires so the suite does
;; not depend on another suite's transitive load order.
(require 'tibetan-analysis-claude)
(require 'tibetan-sentence-persist)
(require 'tibetan-sentence-claude)
(require 'tibetan-cascade)

;; ============================================================================
;; Canned sentence-first responses (five-section schema, ⟦N⟧ span markers)
;; ============================================================================

(defconst sentence-first-spec--response-1
  "## Translation
⟦105⟧The lama went to rNgog's place⟦/105⟧ and ⟦106⟧requested the dharma⟦/106⟧.
### Segment 105
Having gone to rNgog's place,
### Segment 106
[he] requested the dharma.

## Vocabulary
### Segment 105
rngog, proper noun, \"rNgog\", a disciple
### Segment 106
chos, noun, \"dharma\", the teaching

## Grammar
A two-clause chain: ablative converb then main verb.
### Segment 105
- *Verb backbone:* phyin is the past of 'gro.
### Segment 106
- *Verb backbone:* zhus is the past of zhu.

## Particles
### Segment 105
nas, nas, 2.11, ablative converb
### Segment 106
la, la, 1.4, dative

## Concept Notes
- **rNgog** — one of Mar pa's four pillars.
"
  "First-run canned response for segments 105+106.")

(defconst sentence-first-spec--response-2
  (replace-regexp-in-string
   "requested the dharma" "BACKFILL-RUN wording"
   (replace-regexp-in-string
    "Having gone to rNgog's place," "BACKFILL-RUN sub-translation,"
    sentence-first-spec--response-1))
  "Second-run response with distinct wording — if any populated child
absorbs it, the landing gate is broken.")

;; ============================================================================
;; Corpus + fire helpers
;; ============================================================================

(defun sentence-first-spec--corpus (dir &optional populated-children)
  "Write doc.org + child seg files 105/106 + placeholder sent-004.org.
Children are placeholders, or carry hand content when
POPULATED-CHILDREN.  Returns a plist of the four paths."
  (let ((src (expand-file-name "doc.org" dir))
        (sent (expand-file-name "sent-004.org" dir)))
    (with-temp-file src
      (insert "#+TITLE: D\n\n* Tibetan Text\n"
              "*** Sentence 4\n"
              "**** Segment 105\nབདག\n\n"
              "**** Segment 106\nཆོས\n\n"))
    (dolist (n '(105 106))
      (with-temp-file (expand-file-name (format "seg-%03d.org" n) dir)
        (insert (format "#+TITLE: Segment %d Analysis\n" n)
                (format
                 "#+SOURCE: [[file:doc.org::*Segment %d][doc / Segment %d]]\n\n"
                 n n)
                "* Tibetan Text\nབདག\n\n"
                "* Tibetan Analysis\n"
                "** Translation\n"
                (if populated-children
                    (format "HAND CONTENT segment %d.\n" n)
                  "[Awaiting Claude…]\n")
                "\n** Claude Vocabulary\n"
                (if populated-children "hand, noun, \"kept\"\n"
                  "[Awaiting Claude…]\n")
                "\n** Grammar\n*** Claude Grammar\n\n"
                "** Provided Translations\n*** Claude Particles\n\n"
                "** Concept Notes\n[Awaiting Claude…]\n\n"
                "* Footnotes\n")))
    (with-temp-file sent
      (insert "#+TITLE: Sentence 4 Analysis\n"
              "#+SOURCE: [[file:doc.org::*Sentence 4][doc / Sentence 4]]\n\n"
              "* Tibetan Text\nབདག ཆོས\n\n* Tibetan Analysis\n"
              "** Claude Vocabulary\n\n** Translation\n[Awaiting Claude…]\n\n"
              "** Grammar\n*** Claude Grammar\n\n"
              "** Concept Notes\n[Awaiting Claude…]\n\n* Footnotes\n"))
    (list :src src :sent sent
          :c105 (expand-file-name "seg-105.org" dir)
          :c106 (expand-file-name "seg-106.org" dir))))

(defun sentence-first-spec--read (path)
  "File PATH's content as a string."
  (with-temp-buffer (insert-file-contents path) (buffer-string)))

(defun sentence-first-spec--fire (paths response)
  "Fire the dispatcher non-FORCE for segment 105 with RESPONSE canned.
Returns (DISPATCHER-VALUE . DONE-STATUSES).  Stubs only the process
edges; everything from the claim to the landed files is real code.

The gptel feature flag is provided for the call and withdrawn in the
unwind — it can NOT be let-bound: `features' is not a special
variable, so under this file's lexical binding a `let' would only
create a lexical shadow that `featurep' never consults (verified —
that silent no-op cost a debugging round)."
  (tibetan-sentence-claude-clear-inflight)
  (let ((statuses '())
        (had-gptel (featurep 'gptel)))
    (unwind-protect
        (progn
          (unless had-gptel (provide 'gptel))
          (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
                     (lambda (thunk &rest _)
                       (funcall thunk
                                (lambda (status) (push status statuses)))))
                    ((symbol-function 'gptel-request)
                     (lambda (_prompt &rest args)
                       (funcall (plist-get args :callback)
                                response '(:status 200))))
                    ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
                     (lambda (&rest _) t))
                    ((symbol-function 'run-at-time)
                     (lambda (_secs _repeat fn &rest args)
                       (apply fn args) nil)))
            (cons (tibetan-analysis--fire-sentence-level
                   "བདག ཆོས" (plist-get paths :c105)
                   (plist-get paths :src) 105 nil)
                  statuses)))
      (unless had-gptel
        (setq features (delq 'gptel features))))))

;; ============================================================================
;; SENTENCE-FIRST SUITE
;; ============================================================================

(define-bdd-suite sentence-first
    "Whole-sentence Claude fill with per-segment fan-out (Part B 0+1)"

  (spec "Whole-sentence call fills every child and the sent file"
    :given (setq sentence-first-spec--dir
                 (make-temp-file "bdd-sfirst-" t))
    :when (let* ((paths (sentence-first-spec--corpus
                         sentence-first-spec--dir))
                 (fire (sentence-first-spec--fire
                        paths sentence-first-spec--response-1)))
            (list :fired (car fire) :statuses (cdr fire)
                  :s105 (sentence-first-spec--read (plist-get paths :c105))
                  :s106 (sentence-first-spec--read (plist-get paths :c106))
                  :sent (sentence-first-spec--read (plist-get paths :sent))))
    :then (;; The queue job must complete ok — a failing thunk surfaces
           ;; its error string right here instead of as a blank file.
           (tibetan-bdd-assert-contains
            (format "%S" (plist-get result :statuses)) "(:status ok)"
            "Queue job should complete ok")
           (should (eq 'fired (plist-get result :fired)))
           ;; Child 105: own span highlighted, sub-translation landed.
           (tibetan-bdd-assert-contains
            (plist-get result :s105) "⟪The lama went to rNgog's place⟫"
            "Child 105 should carry its ⟪own-span⟫ highlight")
           (tibetan-bdd-assert-contains
            (plist-get result :s105) "Having gone to rNgog's place"
            "Child 105 should carry its sub-translation")
           ;; Child 106 sees the whole sentence with ITS span.
           (tibetan-bdd-assert-contains
            (plist-get result :s106) "⟪requested the dharma⟫"
            "Child 106 should carry its ⟪own-span⟫ highlight")
           ;; Sent file: whole translation, markers stripped.
           (tibetan-bdd-assert-contains
            (plist-get result :sent)
            "The lama went to rNgog's place and requested the dharma."
            "Sent file should carry the plain whole-sentence translation")
           (should-not (string-match-p "⟦" (plist-get result :sent)))
           (progn (delete-directory sentence-first-spec--dir t) t))
    :example "Fresh 2-segment sentence, one Claude call, full fan-out"
    :tags (:sentence-first :fan-out))

  (spec "Backfill leaves populated children byte-identical"
    :given (setq sentence-first-spec--dir
                 (make-temp-file "bdd-sfirst-" t))
    :when (let* ((paths (sentence-first-spec--corpus
                         sentence-first-spec--dir 'populated))
                 (before-105 (sentence-first-spec--read
                              (plist-get paths :c105)))
                 (before-106 (sentence-first-spec--read
                              (plist-get paths :c106)))
                 (fire (sentence-first-spec--fire
                        paths sentence-first-spec--response-2)))
            (list :fired (car fire) :statuses (cdr fire)
                  :identical-105 (equal before-105
                                        (sentence-first-spec--read
                                         (plist-get paths :c105)))
                  :identical-106 (equal before-106
                                        (sentence-first-spec--read
                                         (plist-get paths :c106)))
                  :sent (sentence-first-spec--read (plist-get paths :sent))))
    :then ((should (equal '((:status ok)) (plist-get result :statuses)))
           ;; The placeholder SENT file alone opened the gate (B-1.1).
           (should (eq 'fired (plist-get result :fired)))
           ;; Populated children byte-identical after the fire.
           (should (plist-get result :identical-105))
           (should (plist-get result :identical-106))
           ;; The sent file DID absorb the new response.
           (tibetan-bdd-assert-contains
            (plist-get result :sent) "BACKFILL-RUN wording"
            "Sent file should carry the backfill run's translation")
           (progn (delete-directory sentence-first-spec--dir t) t))
    :example "Khu-dbon state: filled children + placeholder sent files"
    :tags (:sentence-first :backfill :landing-gate))

  (spec "Cascade document: one file, spans landed, no seg files"
    :given (setq sentence-first-spec--dir
                 (make-temp-file "bdd-cascade-" t))
    :when (let* ((dir sentence-first-spec--dir)
                 (src (expand-file-name "doc.org" dir)))
            (with-temp-file src
              (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                      "* Tibetan Text\n"
                      "*** Sentence 4\n"
                      "**** Segment 105\nབདག་གིས་ལས་བྱས།\n\n"
                      "**** Segment 106\nཆོས་ཟབ་མོ་ཡིན།\n\n"))
            (let* ((cascade-file
                    (tibetan-cascade--create-file
                     4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
                     src))
                   (fire-1 (sentence-first-spec--fire
                            (list :src src :c105 cascade-file)
                            sentence-first-spec--response-1))
                   (content (sentence-first-spec--read cascade-file))
                   (fire-2 (sentence-first-spec--fire
                            (list :src src :c105 cascade-file)
                            sentence-first-spec--response-2)))
              (list :fired-1 (car fire-1) :statuses (cdr fire-1)
                    :fired-2 (car fire-2)
                    :content content
                    :c105-file cascade-file
                    ;; R6: dual-format reader — serves the legacy
                    ;; subtree today and the ⟦N⟧ line after R8.
                    :rendering-105 (tibetan-cascade--read-rendering
                                    cascade-file 105)
                    :seg-files (directory-files
                                (file-name-directory cascade-file)
                                nil "\\`seg-"))))
    :then ((tibetan-bdd-assert-contains
            (format "%S" (plist-get result :statuses)) "(:status ok)"
            "Cascade queue job should complete ok")
           (should (eq 'fired (plist-get result :fired-1)))
           ;; Sentence-level Translation: plain whole, no markers.
           (tibetan-bdd-assert-contains
            (plist-get result :content)
            "The lama went to rNgog's place and requested the dharma."
            "Cascade file should carry the whole-sentence translation")
           ;; R8: the Reading view's `- ⟦N⟧' keys legitimately carry
           ;; span markers — only the TRANSLATION body must be clean.
           (should-not
            (string-match-p
             "⟦"
             (or (tibetan-sentence--read-l2-body
                  (plist-get result :c105-file) "Translation")
                 "")))
           ;; Subsegment rendering = the extracted span only.
           (should (equal "The lama went to rNgog's place"
                          (plist-get result :rendering-105)))
           ;; The sub-translations were DISCARDED.
           (should-not (string-match-p "Having gone to rNgog's place"
                                       (plist-get result :content)))
           ;; NO seg files exist — one artifact per sentence.
           (should (null (plist-get result :seg-files)))
           ;; Second non-FORCE fire declines (nothing needs Claude).
           (should-not (plist-get result :fired-2))
           (progn (delete-directory sentence-first-spec--dir t) t))
    :example "CASCADE v2: sentence file with shad subsegments (C3)"
    :tags (:sentence-first :cascade))

  (spec "Fully populated sentence does not fire non-FORCE"
    :given (setq sentence-first-spec--dir
                 (make-temp-file "bdd-sfirst-" t))
    :when (let ((paths (sentence-first-spec--corpus
                        sentence-first-spec--dir 'populated)))
            ;; Populate the sent file too — nothing needs Claude now.
            (with-temp-file (plist-get paths :sent)
              (insert "#+TITLE: Sentence 4 Analysis\n\n"
                      "* Tibetan Analysis\n"
                      "** Translation\nDone already.\n"))
            (prog1 (list :fired (car (sentence-first-spec--fire
                                      paths
                                      sentence-first-spec--response-1)))
              (delete-directory sentence-first-spec--dir t)))
    :then ((should-not (plist-get result :fired)))
    :example "No placeholder anywhere → fire gate stays closed"
    :tags (:sentence-first :fire-gate))
  )

(provide 'sentence-first-spec)
;;; sentence-first-spec.el ends here
