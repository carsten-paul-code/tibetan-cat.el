;;; tibetan-claude-queue-test.el --- ERT tests for tibetan-claude-queue -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Tests for `tibetan-claude-queue', the throttled queue that wraps
;; Claude API requests.  Coverage:
;;
;;   - Single submission completes synchronously when capacity allows
;;   - Concurrency cap is honoured: extra jobs sit in :pending until
;;     an in-flight slot frees up
;;   - On (:status ok) the :on-done callback is invoked with the status
;;   - On (:status rate-limited) the job is re-dispatched after the
;;     scheduled backoff delay; counters update accordingly
;;   - On (:status error) the :on-fail callback is invoked
;;   - Retries are capped at `tibetan-claude-queue-max-retries' and the
;;     :on-fail callback fires once retries are exhausted
;;   - Synchronous error inside the THUNK is reported via :on-fail,
;;     never propagates out of the queue
;;   - `tibetan-claude-queue-cancel-pending' drops pending jobs only
;;   - `tibetan-claude-queue-status' returns the expected counters
;;
;; The queue uses `run-at-time' for backoff.  Tests stub `run-at-time'
;; to fire the callback inline so we don't need a real timer loop.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((root (expand-file-name ".." (file-name-directory
                                    (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path root)
  (add-to-list 'load-path (expand-file-name "persist" root)))

(require 'tibetan-claude-queue)

;; ============================================================================
;; FIXTURES
;; ============================================================================

(defmacro tibetan-claude-queue-test--with-fresh-queue (&rest body)
  "Run BODY with the queue's state freshly reset before and after.
Also pins concurrency / retry / delay parameters to known values so
results are deterministic."
  (declare (indent 0))
  `(let ((tibetan-claude-queue-concurrency 2)
         (tibetan-claude-queue-max-retries 3)
         (tibetan-claude-queue-base-delay 1.0)
         (tibetan-claude-queue-max-delay 5.0)
         (tibetan-claude-queue-verbose nil))
     (setq tibetan-claude-queue--pending   nil
           tibetan-claude-queue--in-flight 0
           tibetan-claude-queue--total     0
           tibetan-claude-queue--succeeded 0
           tibetan-claude-queue--failed    0
           tibetan-claude-queue--retried   0)
     (unwind-protect
         (progn ,@body)
       (setq tibetan-claude-queue--pending   nil
             tibetan-claude-queue--in-flight 0))))

(defmacro tibetan-claude-queue-test--with-stubbed-timer (&rest body)
  "Run BODY with `run-at-time' stubbed to fire its callback inline.
Used to make backoff retries deterministic in tests."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'run-at-time)
              (lambda (_delay _repeat fn &rest args)
                (apply fn args)
                nil)))
     ,@body))

;; A "thunk factory" that captures the most-recently-supplied DONE-FN
;; so a test can fire it later (mimicking gptel's async callback).
(defvar tibetan-claude-queue-test--captured-done nil)

(defun tibetan-claude-queue-test--make-async-thunk ()
  "Return a thunk that captures DONE-FN into the test variable."
  (lambda (done) (setq tibetan-claude-queue-test--captured-done done)))

;; ============================================================================
;; SINGLE-JOB BEHAVIOUR
;; ============================================================================

(ert-deftest tibetan-claude-queue/submit-runs-thunk-immediately ()
  "When the queue is empty, submit dispatches the thunk synchronously."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((called nil))
      (tibetan-claude-queue-submit
       (lambda (_done) (setq called t)))
      (should called))))

(ert-deftest tibetan-claude-queue/ok-status-invokes-on-done ()
  "An :ok status calls the :on-done handler exactly once."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((done-called 0)
          (fail-called 0))
      (tibetan-claude-queue-submit
       (lambda (done) (funcall done '(:status ok)))
       :on-done (lambda (_) (cl-incf done-called))
       :on-fail (lambda (_) (cl-incf fail-called)))
      (should (= done-called 1))
      (should (= fail-called 0))
      (should (= 1 (plist-get (tibetan-claude-queue-status) :succeeded))))))

(ert-deftest tibetan-claude-queue/error-status-invokes-on-fail ()
  "A non-retryable error calls :on-fail and bumps the failed counter."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((seen-status nil))
      (tibetan-claude-queue-submit
       (lambda (done)
         (funcall done '(:status error :error "boom")))
       :on-fail (lambda (s) (setq seen-status s)))
      (should (eq 'error (plist-get seen-status :status)))
      (should (equal "boom" (plist-get seen-status :error)))
      (should (= 1 (plist-get (tibetan-claude-queue-status) :failed))))))

(ert-deftest tibetan-claude-queue/synchronous-thunk-error-is-caught ()
  "A throw inside the thunk is reported via :on-fail, not raised out."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((seen nil))
      (tibetan-claude-queue-submit
       (lambda (_done) (error "synchronous crash"))
       :on-fail (lambda (s) (setq seen s)))
      (should (eq 'error (plist-get seen :status)))
      (should (string-match-p "synchronous crash"
                              (plist-get seen :error))))))

;; ============================================================================
;; CONCURRENCY CAP
;; ============================================================================

(ert-deftest tibetan-claude-queue/concurrency-cap-blocks-third-job ()
  "Submissions beyond the cap stay :pending until a slot frees."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((tibetan-claude-queue-concurrency 2)
          (captured nil))
      (dotimes (_ 3)
        (let ((my-fn (lambda (done) (push done captured))))
          (tibetan-claude-queue-submit my-fn)))
      ;; Two thunks ran (their captured done-fns landed in `captured').
      ;; The third sat in :pending.
      (should (= (length captured) 2))
      (should (= 2 (plist-get (tibetan-claude-queue-status) :in-flight)))
      (should (= 1 (plist-get (tibetan-claude-queue-status) :pending)))
      ;; Finish one in-flight job → the third should auto-dispatch.
      (funcall (pop captured) '(:status ok))
      (should (= (length captured) 2))           ; new thunk added a done
      (should (= 2 (plist-get (tibetan-claude-queue-status) :in-flight)))
      (should (= 0 (plist-get (tibetan-claude-queue-status) :pending))))))

(ert-deftest tibetan-claude-queue/in-flight-decrements-on-finish ()
  "Finishing a job decrements :in-flight back toward zero."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((captured nil))
      (tibetan-claude-queue-submit
       (lambda (done) (push done captured)))
      (should (= 1 (plist-get (tibetan-claude-queue-status) :in-flight)))
      (funcall (pop captured) '(:status ok))
      (should (= 0 (plist-get (tibetan-claude-queue-status) :in-flight))))))

(ert-deftest tibetan-claude-queue/double-finish-clamps-to-zero ()
  "A buggy thunk that finishes twice doesn't drive :in-flight negative."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((captured nil))
      (tibetan-claude-queue-submit
       (lambda (done) (push done captured)))
      (let ((done (pop captured)))
        (funcall done '(:status ok))
        (funcall done '(:status ok)))
      (should (>= (plist-get (tibetan-claude-queue-status) :in-flight) 0)))))

;; ============================================================================
;; RATE-LIMITED RETRY
;; ============================================================================

(ert-deftest tibetan-claude-queue/rate-limited-reschedules ()
  "A :rate-limited finish increments :retried and re-runs the job."
  (tibetan-claude-queue-test--with-fresh-queue
    (tibetan-claude-queue-test--with-stubbed-timer
      (let ((attempts 0))
        (tibetan-claude-queue-submit
         (lambda (done)
           (cl-incf attempts)
           (if (< attempts 2)
               (funcall done '(:status rate-limited))
             (funcall done '(:status ok)))))
        ;; Attempt 1 → rate-limited → stubbed timer fires immediately
        ;; → attempt 2 → ok.
        (should (= attempts 2))
        (let ((s (tibetan-claude-queue-status)))
          (should (= 1 (plist-get s :retried)))
          (should (= 1 (plist-get s :succeeded)))
          (should (= 0 (plist-get s :failed))))))))

(ert-deftest tibetan-claude-queue/retries-capped-then-on-fail ()
  "After max-retries, an :on-fail handler fires with :exhausted t."
  (tibetan-claude-queue-test--with-fresh-queue
    (tibetan-claude-queue-test--with-stubbed-timer
      (let ((tibetan-claude-queue-max-retries 2)
            (attempts 0)
            (failure nil))
        (tibetan-claude-queue-submit
         (lambda (done)
           (cl-incf attempts)
           (funcall done '(:status rate-limited)))
         :on-fail (lambda (s) (setq failure s)))
        (should (= attempts 2))   ; first try + 1 retry, then exhausted
        (should (eq 'rate-limited (plist-get failure :status)))
        (should (eq t (plist-get failure :exhausted)))
        (let ((s (tibetan-claude-queue-status)))
          (should (= 1 (plist-get s :failed)))
          (should (= 0 (plist-get s :succeeded))))))))

(ert-deftest tibetan-claude-queue/retry-does-not-double-count-total ()
  "A retried job counts once in :total, even after multiple retries."
  (tibetan-claude-queue-test--with-fresh-queue
    (tibetan-claude-queue-test--with-stubbed-timer
      (let ((attempts 0))
        (tibetan-claude-queue-submit
         (lambda (done)
           (cl-incf attempts)
           (if (< attempts 3)
               (funcall done '(:status rate-limited))
             (funcall done '(:status ok)))))
        (should (= 1 (plist-get (tibetan-claude-queue-status) :total)))))))

;; ============================================================================
;; CANCELLATION + DIAGNOSTICS
;; ============================================================================

(ert-deftest tibetan-claude-queue/cancel-pending-drops-queued-only ()
  "`tibetan-claude-queue-cancel-pending' drops :pending, not :in-flight."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((tibetan-claude-queue-concurrency 1)
          (captured nil))
      ;; First submission goes in-flight.
      (tibetan-claude-queue-submit
       (lambda (done) (push done captured)))
      ;; Second + third sit in :pending.
      (tibetan-claude-queue-submit (lambda (_done) nil))
      (tibetan-claude-queue-submit (lambda (_done) nil))
      (should (= 2 (plist-get (tibetan-claude-queue-status) :pending)))
      (tibetan-claude-queue-cancel-pending)
      (should (= 0 (plist-get (tibetan-claude-queue-status) :pending)))
      (should (= 1 (plist-get (tibetan-claude-queue-status) :in-flight)))
      ;; The in-flight job still completes normally.
      (funcall (pop captured) '(:status ok))
      (should (= 0 (plist-get (tibetan-claude-queue-status) :in-flight))))))

(ert-deftest tibetan-claude-queue/status-shape ()
  "`tibetan-claude-queue-status' returns the documented plist keys."
  (tibetan-claude-queue-test--with-fresh-queue
    (let ((s (tibetan-claude-queue-status)))
      (dolist (k '(:pending :in-flight :total :succeeded :failed :retried))
        (should (plist-member s k))))))

(ert-deftest tibetan-claude-queue/reset-stats-zeroes-counters ()
  "`tibetan-claude-queue-reset-stats' zeroes lifetime counters."
  (tibetan-claude-queue-test--with-fresh-queue
    (tibetan-claude-queue-submit
     (lambda (done) (funcall done '(:status ok))))
    (should (= 1 (plist-get (tibetan-claude-queue-status) :succeeded)))
    (tibetan-claude-queue-reset-stats)
    (let ((s (tibetan-claude-queue-status)))
      (should (= 0 (plist-get s :succeeded)))
      (should (= 0 (plist-get s :total))))))

;; ============================================================================
;; SUBMIT VALIDATION
;; ============================================================================

(ert-deftest tibetan-claude-queue/submit-rejects-non-function ()
  "Submitting a non-function THUNK raises immediately."
  (tibetan-claude-queue-test--with-fresh-queue
    (should-error (tibetan-claude-queue-submit "not a function"))))

;; ============================================================================
;; INTEGRATION: ANALYSIS FAILURE STUB
;; ============================================================================
;;
;; Verify that `tibetan-analysis--write-claude-failure-stub' writes a
;; visible placeholder when the *** Claude Translation section is empty
;; but does NOT clobber a real prior translation.

(require 'tibetan-analysis-persist)

(ert-deftest tibetan-analysis-failure-stub/writes-into-empty-section ()
  "Failure stub appears under *** Claude Translation when section is empty."
  (let* ((dir (make-temp-file "tib-stub-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert "* Tibetan Text\nfoo\n"
                    "* Provided Translations\n"
                    "*** Claude Translation\n\n"
                    "*** Claude Grammar\n\n"
                    "*** Claude Context\n\n")
            (write-region (point-min) (point-max) file))
          (tibetan-analysis--write-claude-failure-stub
           file "[Claude request failed: HTTP 429 — re-run later]")
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (should (re-search-forward "Claude request failed: HTTP 429"
                                       nil t))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-failure-stub/does-not-clobber-real-translation ()
  "Failure stub leaves a real Claude translation untouched."
  (let* ((dir (make-temp-file "tib-stub-" t))
         (file (expand-file-name "seg-002.org" dir)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert "* Tibetan Text\nfoo\n"
                    "* Provided Translations\n"
                    "*** Claude Translation\n"
                    "Real translation that must not be touched.\n\n"
                    "*** Claude Grammar\n\n"
                    "*** Claude Context\n\n")
            (write-region (point-min) (point-max) file))
          (tibetan-analysis--write-claude-failure-stub
           file "[Claude request failed: HTTP 429 — re-run later]")
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (should (re-search-forward
                     "Real translation that must not be touched"
                     nil t))
            (goto-char (point-min))
            (should-not (re-search-forward "request failed" nil t))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-failure-stub/replaces-prior-stub ()
  "A new failure stub replaces an older `[Claude ...]' placeholder."
  (let* ((dir (make-temp-file "tib-stub-" t))
         (file (expand-file-name "seg-003.org" dir)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert "* Tibetan Text\nfoo\n"
                    "* Provided Translations\n"
                    "*** Claude Translation\n"
                    "[Claude request failed: HTTP 503 — re-run later]\n\n"
                    "*** Claude Grammar\n\n"
                    "*** Claude Context\n\n")
            (write-region (point-min) (point-max) file))
          (tibetan-analysis--write-claude-failure-stub
           file "[Claude request failed: HTTP 429 — re-run later]")
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (should (re-search-forward "HTTP 429" nil t))
            (goto-char (point-min))
            (should-not (re-search-forward "HTTP 503" nil t))))
      (delete-directory dir t))))

;; ============================================================================
;; INTEGRATION: 429 DETECTION HELPER
;; ============================================================================

(ert-deftest tibetan-analysis-claude-status-rate-limited-p/detects-429 ()
  "The helper returns t for HTTP/2 429 and similar status strings."
  (should (tibetan-analysis--claude-status-rate-limited-p
           '(:status "HTTP/2 429")))
  (should (tibetan-analysis--claude-status-rate-limited-p
           '(:status "429 Too Many Requests")))
  (should-not (tibetan-analysis--claude-status-rate-limited-p
               '(:status "200 OK")))
  (should-not (tibetan-analysis--claude-status-rate-limited-p
               '(:status "HTTP/2 500 Internal Server Error")))
  (should-not (tibetan-analysis--claude-status-rate-limited-p nil)))

(provide 'tibetan-claude-queue-test)
;;; tibetan-claude-queue-test.el ends here
