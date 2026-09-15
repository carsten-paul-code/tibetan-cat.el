;;; tibetan-analysis-nav-test.el --- Tests for source↔analysis navigation -*- lexical-binding: t -*-

;;; Commentary:
;; Masterarbeit view 1 ergonomics: back-jump to the source heading
;; and next/previous sentence-file navigation.  Fixtures in temp
;; dirs; buffers cleaned up per test.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../workspace" base-dir))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir)))

(require 'tibetan-analysis-nav)
(require 'tibetan-sentence-persist)

(defmacro tibetan-analysis-nav-test--with-fixture (&rest body)
  "Source `quelle.org' (2 sentences) + analysis/ with sent files 1+2
at the resolver's paths; binds DIR, SOURCE-FILE, ANALYSIS-DIR, F1,
F2.  Kills fixture-visiting buffers on exit."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "nav-" t))
          (source-file (expand-file-name "quelle.org" dir))
          (analysis-dir (expand-file-name "analysis" dir)))
     (make-directory analysis-dir)
     (with-temp-file source-file
       (insert "#+TITLE: Q\n\n* Tibetan Text\n"
               "*** Sentence 1\n**** Segment 1\nབདག\n"
               "*** Sentence 2\n**** Segment 2\nཆོས\n"))
     (let ((f1 (tibetan-sentence--filepath 1 analysis-dir source-file))
           (f2 (tibetan-sentence--filepath 2 analysis-dir source-file)))
       (dolist (pair (list (cons f1 1) (cons f2 2)))
         (with-temp-file (car pair)
           (insert (format "#+TITLE: Sentence %d Analysis\n" (cdr pair))
                   (format "#+SOURCE: [[file:../quelle.org::*Sentence %d][quelle.org / Sentence %d]]\n\n"
                           (cdr pair) (cdr pair))
                   "* Working Translation\n\n* Tibetan Text\nབདག\n")))
       (unwind-protect
           (progn ,@body)
         (dolist (f (list f1 f2 source-file))
           (when-let ((b (find-buffer-visiting f)))
             (kill-buffer b)))
         (delete-directory dir t)))))

;; ----------------------------------------------------------------------------
;; Back-jump to source
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-nav-source-link-parses ()
  "The #+SOURCE header parses into absolute path + heading target."
  (tibetan-analysis-nav-test--with-fixture
    (let ((link (tibetan-analysis-nav--source-link f2)))
      (should link)
      (should (equal (expand-file-name source-file) (car link)))
      (should (equal "Sentence 2" (cdr link))))))

(ert-deftest tibetan-analysis-nav-jump-to-source-lands-on-heading ()
  "From the sentence-2 analysis buffer, the jump visits the source
with point on the `*** Sentence 2' heading."
  (tibetan-analysis-nav-test--with-fixture
    (with-current-buffer (find-file-noselect f2)
      (tibetan-analysis-jump-to-source))
    ;; The command SELECTED a window showing the source…
    (let ((src-buf (find-buffer-visiting source-file)))
      (should src-buf)
      (should (eq src-buf (window-buffer (selected-window))))
      ;; …with point on the sentence heading.
      (with-current-buffer src-buf
        (should (looking-at-p "\\*\\*\\* Sentence 2"))))))

(ert-deftest tibetan-analysis-nav-jump-errors-without-link ()
  "A buffer without a #+SOURCE link gets a user-error, not a crash."
  (tibetan-analysis-nav-test--with-fixture
    (let ((plain (expand-file-name "plain.org" dir)))
      (with-temp-file plain (insert "#+TITLE: X\nText.\n"))
      (unwind-protect
          (with-current-buffer (find-file-noselect plain)
            (should-error (tibetan-analysis-jump-to-source)
                          :type 'user-error))
        (when-let ((b (find-buffer-visiting plain)))
          (kill-buffer b))))))

(provide 'tibetan-analysis-nav-test)

;;; tibetan-analysis-nav-test.el ends here
