;;; tibetan-defer-mt-test.el --- Portfolio-mode MT deferral tests -*- lexical-binding: t -*-

;; Portfolio mode (2026-07-21): a source carrying `#+TIBETAN_DEFER_MT: t'
;; must never fire Claude or DharmaMitra requests — the Tibetisch IV
;; Portfolio assignment permits AI tools only for revising a self-made
;; translation.  These tests cover the predicate plus ALL FIVE leaf fire
;; entry points; each guard test asserts the underlying queue submit /
;; HTTP fire is NOT reached when the header is set, and IS reached when
;; it is absent (control).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tibetan-analysis-persist)
(require 'tibetan-analysis-claude)
(require 'tibetan-sentence-persist)
(require 'tibetan-sentence-claude)
(require 'tibetan-dharmamitra-translation)

(defun tibetan-defer-test--write (path contents)
  (with-temp-buffer (insert contents) (write-region (point-min) (point-max) path nil 'silent)))

(defmacro tibetan-defer-test--fixture (defer &rest body)
  "Temp workspace: source.org (DEFER non-nil → with the header) +
two suffixed child seg files + one sent file, all with #+SOURCE links
and placeholder Claude/DM sections.  Binds dir, source-file, seg1,
seg2, sent1 for BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-defer-" t))
          (source-file (expand-file-name "source.org" dir))
          (seg1 (expand-file-name "seg-001-source.org" dir))
          (seg2 (expand-file-name "seg-002-source.org" dir))
          (sent1 (expand-file-name "sent-001-source.org" dir)))
     (unwind-protect
         (progn
           (tibetan-defer-test--write
            source-file
            (concat "#+TITLE: Defer fixture\n"
                    ,(if defer "#+TIBETAN_DEFER_MT: t\n" "")
                    "\n* Tibetan Text\n"
                    "*** Sentence 1\n"
                    "**** Segment 1\nབཀྲ་ཤིས།\n"
                    "**** Segment 2\nབདེ་ལེགས།\n"))
           (dolist (spec (list (cons seg1 "Segment 1")
                               (cons seg2 "Segment 2")))
             (tibetan-defer-test--write
              (car spec)
              (concat "#+TITLE: " (cdr spec) " Analysis\n"
                      "#+SOURCE: [[file:source.org::*" (cdr spec)
                      "][source.org / " (cdr spec) "]]\n\n"
                      "* Tibetan Analysis\n"
                      "** Translation\n[Requesting translation...]\n\n"
                      "** DharmaMitra Translation\n[Awaiting DharmaMitra…]\n")))
           (tibetan-defer-test--write
            sent1
            (concat "#+TITLE: Sentence 1 Analysis\n"
                    "#+SOURCE: [[file:source.org::*Sentence 1][source.org / Sentence 1]]\n\n"
                    "* Tibetan Analysis\n"
                    "** Translation\n[Requesting translation...]\n"))
           ,@body)
       (delete-directory dir t))))

;; ----------------------------------------------------------------------------
;; Predicate
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-defer-mt-predicate-resolves-source-and-analysis ()
  "`tibetan-analysis--defer-mt-p' is t for a deferring source file AND
for an analysis file whose #+SOURCE resolves to it; nil for a
non-deferring source, nil input, and a nonexistent path."
  (tibetan-defer-test--fixture t
    (should (tibetan-analysis--defer-mt-p source-file))
    (should (tibetan-analysis--defer-mt-p seg1)))
  (tibetan-defer-test--fixture nil
    (should-not (tibetan-analysis--defer-mt-p source-file))
    (should-not (tibetan-analysis--defer-mt-p seg1)))
  (should-not (tibetan-analysis--defer-mt-p nil))
  (should-not (tibetan-analysis--defer-mt-p "/nonexistent/nowhere.org")))

;; ----------------------------------------------------------------------------
;; Guard 1: segment-level Claude request
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-defer-mt-blocks-segment-claude-request ()
  "With the header set, `tibetan-analysis--request-claude-translation'
must not submit to the Claude queue; without it, it must."
  (let ((submits 0))
    (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
               (lambda (&rest _) (cl-incf submits))))
      (tibetan-defer-test--fixture t
        (tibetan-analysis--request-claude-translation
         "བཀྲ་ཤིས།" seg1 source-file)
        (should (= submits 0)))
      (tibetan-defer-test--fixture nil
        (tibetan-analysis--request-claude-translation
         "བཀྲ་ཤིས།" seg1 source-file)
        (should (= submits 1))))))

;; ----------------------------------------------------------------------------
;; Guard 2: sentence-level dispatcher returns 'deferred (no fallback)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-defer-mt-dispatcher-returns-deferred ()
  "With the header set, `tibetan-analysis--fire-sentence-level' returns
the non-nil symbol `deferred' WITHOUT claiming or requesting — non-nil
so the caller does not fall back to per-segment Claude."
  (let ((requests 0) (claims 0))
    (cl-letf (((symbol-function 'tibetan-sentence-claude--request)
               (lambda (&rest _) (cl-incf requests)))
              ((symbol-function 'tibetan-sentence-claude--claim)
               (lambda (&rest _) (cl-incf claims) t))
              ((symbol-function 'tibetan-sentence-claude--schedule-dm)
               (lambda (&rest _) nil)))
      (tibetan-defer-test--fixture t
        (should (eq (tibetan-analysis--fire-sentence-level
                     "བཀྲ་ཤིས།" seg1 source-file 1)
                    'deferred))
        (should (= requests 0))
        (should (= claims 0)))
      ;; Control: without the header the dispatcher fires normally.
      (tibetan-defer-test--fixture nil
        (should (eq (tibetan-analysis--fire-sentence-level
                     "བཀྲ་ཤིས།" seg1 source-file 1)
                    'fired))
        (should (= requests 1))))))

;; ----------------------------------------------------------------------------
;; Guard 3: sentence-level Claude request (legacy per-sentence path)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-defer-mt-blocks-sentence-claude-request ()
  "With the header set, `tibetan-sentence--request-claude' must not
submit to the Claude queue; without it, it must."
  (let ((submits 0))
    (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
               (lambda (&rest _) (cl-incf submits))))
      (tibetan-defer-test--fixture t
        (tibetan-sentence--request-claude
         "བཀྲ་ཤིས། བདེ་ལེགས།" '(1 2) sent1 source-file dir)
        (should (= submits 0)))
      (tibetan-defer-test--fixture nil
        (tibetan-sentence--request-claude
         "བཀྲ་ཤིས། བདེ་ལེགས།" '(1 2) sent1 source-file dir)
        (should (= submits 1))))))

;; ----------------------------------------------------------------------------
;; Guard 4: DharmaMitra segment fire
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-defer-mt-blocks-dm-segment-fire ()
  "With the header set, `tibetan-dharmamitra-translation-fire-for-segment'
must not reach the Tibetan DM fire; without it, it must (the fixture's
DM section is a placeholder, so needs-request-p is t)."
  (let ((fires 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-translation-fire-tibetan)
               (lambda (&rest _) (cl-incf fires))))
      (tibetan-defer-test--fixture t
        (tibetan-dharmamitra-translation-fire-for-segment
         "བཀྲ་ཤིས།" seg1 source-file 1)
        (should (= fires 0)))
      (tibetan-defer-test--fixture nil
        (tibetan-dharmamitra-translation-fire-for-segment
         "བཀྲ་ཤིས།" seg1 source-file 1)
        (should (= fires 1))))))

;; ----------------------------------------------------------------------------
;; Guard 5: DharmaMitra sentence fire
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-defer-mt-blocks-dm-sentence-fire ()
  "With the header set, `tibetan-dharmamitra-translation-fire-tibetan-sentence'
must not reach the DM HTTP layer; the defer source is resolved from the
child files' #+SOURCE links.  Without the header it fires."
  (let ((calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (&rest _) (cl-incf calls) "stub translation")))
      (tibetan-defer-test--fixture t
        (tibetan-dharmamitra-translation-fire-tibetan-sentence
         "བཀྲ་ཤིས། བདེ་ལེགས།" 1 '(1 2) (list seg1 seg2) sent1)
        (should (= calls 0)))
      (tibetan-defer-test--fixture nil
        (tibetan-dharmamitra-translation-fire-tibetan-sentence
         "བཀྲ་ཤིས། བདེ་ལེགས།" 1 '(1 2) (list seg1 seg2) sent1)
        (should (>= calls 1))))))

(provide 'tibetan-defer-mt-test)
;;; tibetan-defer-mt-test.el ends here
