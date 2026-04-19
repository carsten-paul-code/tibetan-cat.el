;;; tibetan-claude-queue.el --- Throttled queue for Claude API requests -*- lexical-binding: t -*-

;; Author: Carsten Paul <post@carstenpaul.de>
;; URL: https://github.com/carsten-paul-code/tibetan-cat.el
;; Version: 1.0.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: languages, tibetan, translation, internal

;;; Commentary:
;;
;; A small in-process queue that throttles outgoing Claude API requests
;; to a configurable concurrency cap, retries on HTTP 429 with
;; exponential backoff + jitter, and dispatches per-job success / failure
;; callbacks so callers can write a placeholder into their analysis file
;; when a request ultimately fails.
;;
;; Why this exists:
;;   `tibetan-analysis-batch-reanalyze' dispatches one Claude request per
;;   segment (282 for Milarepa) when called with re-request-claude.  The
;;   prior implementation fan-outed all 282 requests in tight succession
;;   using `gptel-request' directly, which immediately tripped the
;;   Anthropic API rate limit.  Symptoms in *Messages*:
;;
;;     Claude translation failed: HTTP/2 429   [46 times]
;;     error in process sentinel: gptel-curl--parse-response: ...
;;
;;   The queue keeps at most `tibetan-claude-queue-concurrency'
;;   requests in flight, retries the rate-limited ones with backoff,
;;   and lets each caller decide what to write into the analysis file
;;   when retries are exhausted.
;;
;; Public API
;; ----------
;;   (tibetan-claude-queue-submit THUNK
;;     :on-done FN :on-fail FN :label STR)
;;
;;     THUNK is a function of one argument DONE-FN.  THUNK performs the
;;     work asynchronously (typically a `gptel-request' call) and, when
;;     the work completes, calls (funcall DONE-FN STATUS) with one of:
;;
;;       (:status ok)                -- success; ON-DONE will be called
;;       (:status rate-limited)      -- HTTP 429; queue will retry with
;;                                      exponential backoff up to
;;                                      `tibetan-claude-queue-max-retries'.
;;       (:status error :error STR)  -- non-retryable failure
;;
;;   (tibetan-claude-queue-status)
;;     -> (:pending N :in-flight N :total N :succeeded N :failed N
;;         :retried N)
;;
;;   M-x tibetan-claude-queue-show-status
;;     Echoes the current queue snapshot (handy mid-batch).
;;
;;   M-x tibetan-claude-queue-cancel-pending
;;     Drops everything that has not yet started; in-flight requests
;;     are unaffected.
;;
;; The queue is intentionally simple: a FIFO list, an in-flight counter,
;; and `run-at-time' for backoff.  It is *not* persistent across Emacs
;; restarts.  Callers that need durability should write their own
;; on-disk markers (e.g. failure stubs in the analysis file) inside
;; their :on-fail handler.

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; CUSTOMIZATION
;; ============================================================================

(defgroup tibetan-claude-queue nil
  "Throttling and retry policy for Claude API requests."
  :group 'tibetan-cat
  :prefix "tibetan-claude-queue-")

(defcustom tibetan-claude-queue-concurrency 3
  "Maximum number of Claude API requests in flight at once.
Lower this if you still see HTTP 429 (rate-limited) errors during
large batches; raise it if your Anthropic-API tier can sustain more
parallel requests and you want batches to finish faster."
  :type 'integer
  :group 'tibetan-claude-queue)

(defcustom tibetan-claude-queue-max-retries 4
  "Maximum number of retries for a rate-limited (HTTP 429) request.
After this many retries the job is considered failed and its
:on-fail callback runs."
  :type 'integer
  :group 'tibetan-claude-queue)

(defcustom tibetan-claude-queue-base-delay 2.0
  "Base delay (seconds) for exponential backoff on HTTP 429.
The actual delay before retry N is roughly
  base * 2^N + ±25% jitter
capped at `tibetan-claude-queue-max-delay'."
  :type 'number
  :group 'tibetan-claude-queue)

(defcustom tibetan-claude-queue-max-delay 60.0
  "Upper bound on the per-retry backoff delay, in seconds."
  :type 'number
  :group 'tibetan-claude-queue)

(defcustom tibetan-claude-queue-verbose t
  "When non-nil, echo per-job lifecycle messages to *Messages*.
Useful while debugging or while watching a long batch run; set to
nil for quieter operation."
  :type 'boolean
  :group 'tibetan-claude-queue)

;; ============================================================================
;; INTERNAL STATE
;; ============================================================================

(defvar tibetan-claude-queue--pending nil
  "FIFO list of pending jobs, oldest first.
Each job is a plist (:thunk FN :attempt N
:on-done FN :on-fail FN :label STR).")

(defvar tibetan-claude-queue--in-flight 0
  "Count of currently in-flight Claude requests.")

(defvar tibetan-claude-queue--total 0
  "Total jobs ever submitted in this Emacs session.")

(defvar tibetan-claude-queue--succeeded 0
  "Count of jobs that completed successfully.")

(defvar tibetan-claude-queue--failed 0
  "Count of jobs that ultimately failed.")

(defvar tibetan-claude-queue--retried 0
  "Total count of retries scheduled (across all jobs).")

;; ============================================================================
;; STATUS / DIAGNOSTICS
;; ============================================================================

;;;###autoload
(defun tibetan-claude-queue-status ()
  "Return a plist describing current Claude queue state.
Keys: :pending :in-flight :total :succeeded :failed :retried."
  (list :pending   (length tibetan-claude-queue--pending)
        :in-flight tibetan-claude-queue--in-flight
        :total     tibetan-claude-queue--total
        :succeeded tibetan-claude-queue--succeeded
        :failed    tibetan-claude-queue--failed
        :retried   tibetan-claude-queue--retried))

;;;###autoload
(defun tibetan-claude-queue-show-status ()
  "Echo current Claude queue stats in the minibuffer."
  (interactive)
  (let ((s (tibetan-claude-queue-status)))
    (message
     "Claude queue: %d pending / %d in-flight | done %d ok, %d failed, %d retried"
     (plist-get s :pending) (plist-get s :in-flight)
     (plist-get s :succeeded) (plist-get s :failed)
     (plist-get s :retried))))

;;;###autoload
(defun tibetan-claude-queue-cancel-pending ()
  "Drop all not-yet-started jobs from the Claude queue.
In-flight requests are unaffected and will still run to completion
(or to retry exhaustion)."
  (interactive)
  (let ((n (length tibetan-claude-queue--pending)))
    (setq tibetan-claude-queue--pending nil)
    (message "Claude queue: cancelled %d pending job%s (in-flight unaffected)"
             n (if (= n 1) "" "s"))))

;;;###autoload
(defun tibetan-claude-queue-reset-stats ()
  "Reset the Claude queue's lifetime counters.
Does not touch pending or in-flight jobs."
  (interactive)
  (setq tibetan-claude-queue--total     0
        tibetan-claude-queue--succeeded 0
        tibetan-claude-queue--failed    0
        tibetan-claude-queue--retried   0)
  (when (called-interactively-p 'interactive)
    (message "Claude queue: stats reset")))

;; ============================================================================
;; SUBMIT / DISPATCH
;; ============================================================================

;;;###autoload
(cl-defun tibetan-claude-queue-submit (thunk &key on-done on-fail label)
  "Submit THUNK to the throttled Claude request queue.

THUNK must be a function of one argument DONE-FN.  THUNK starts the
asynchronous work (typically a `gptel-request' call) and, when the
result is known, calls (funcall DONE-FN STATUS) with one of:

  \\='(:status ok)                — success; ON-DONE is invoked
  \\='(:status rate-limited)      — HTTP 429; queue retries with
                                    exponential backoff up to
                                    `tibetan-claude-queue-max-retries'
  \\='(:status error :error STR)  — non-retryable failure; ON-FAIL
                                    is invoked

Optional keyword args:
  :on-done FN  — called with the success status plist on success
  :on-fail FN  — called with the failure status plist when retries
                 are exhausted, or on a non-retryable error
  :label   STR — a short string used in diagnostic messages
                 (typically the analysis filename)

Synchronous errors raised inside THUNK are caught and reported as
\\='(:status error :error STR).  Errors raised inside ON-DONE / ON-FAIL
are caught and logged so they do not break queue progress."
  (unless (functionp thunk)
    (error "tibetan-claude-queue-submit: THUNK must be a function"))
  (cl-incf tibetan-claude-queue--total)
  (let ((job (list :thunk   thunk
                   :attempt 0
                   :on-done on-done
                   :on-fail on-fail
                   :label   (or label "<job>"))))
    (setq tibetan-claude-queue--pending
          (append tibetan-claude-queue--pending (list job)))
    (tibetan-claude-queue--maybe-dispatch)))

(defun tibetan-claude-queue--maybe-dispatch ()
  "Dispatch jobs from the pending queue up to the concurrency cap."
  (while (and tibetan-claude-queue--pending
              (< tibetan-claude-queue--in-flight
                 tibetan-claude-queue-concurrency))
    (let ((job (pop tibetan-claude-queue--pending)))
      (tibetan-claude-queue--start job))))

(defun tibetan-claude-queue--start (job)
  "Actually run JOB.  Internal."
  (cl-incf tibetan-claude-queue--in-flight)
  (when tibetan-claude-queue-verbose
    (message "Claude queue: dispatching %s (attempt %d, %d in-flight)"
             (plist-get job :label)
             (1+ (plist-get job :attempt))
             tibetan-claude-queue--in-flight))
  (let ((thunk (plist-get job :thunk)))
    (condition-case err
        (funcall thunk
                 (lambda (status)
                   (tibetan-claude-queue--handle-finish job status)))
      (error
       ;; Synchronous error inside the thunk itself.  Report and move on.
       (tibetan-claude-queue--handle-finish
        job (list :status 'error
                  :error  (error-message-string err)))))))

(defun tibetan-claude-queue--handle-finish (job status)
  "Called when JOB's thunk reports completion via STATUS.
Runs the appropriate user callback and dispatches the next pending
job.  Kept robust against repeated calls (idempotent on counters)."
  (cl-decf tibetan-claude-queue--in-flight)
  (when (< tibetan-claude-queue--in-flight 0)
    ;; Defensive: a buggy thunk that calls done twice could push us
    ;; below zero.  Clamp so dispatch keeps working sanely.
    (setq tibetan-claude-queue--in-flight 0))
  (let* ((kind  (plist-get status :status))
         (label (plist-get job :label)))
    (cond
     ;; ----- success ---------------------------------------------------
     ((eq kind 'ok)
      (cl-incf tibetan-claude-queue--succeeded)
      (when tibetan-claude-queue-verbose
        (message "Claude queue: %s ok" label))
      (let ((cb (plist-get job :on-done)))
        (when cb
          (condition-case err
              (funcall cb status)
            (error
             (message "Claude queue: on-done for %s raised: %s"
                      label (error-message-string err)))))))
     ;; ----- rate-limited: schedule retry ------------------------------
     ((eq kind 'rate-limited)
      (let* ((attempt (plist-get job :attempt))
             (next    (1+ attempt)))
        (if (>= next tibetan-claude-queue-max-retries)
            (progn
              (cl-incf tibetan-claude-queue--failed)
              (message
               "Claude queue: %s gave up after %d retries (still rate-limited)"
               label tibetan-claude-queue-max-retries)
              (tibetan-claude-queue--call-fail
               job (list :status 'rate-limited :exhausted t)))
          (cl-incf tibetan-claude-queue--retried)
          (let* ((raw   (* tibetan-claude-queue-base-delay
                           (expt 2 attempt)))
                 (capped (min raw tibetan-claude-queue-max-delay))
                 ;; ±25% jitter so synchronised retry storms don't
                 ;; immediately re-trip the rate limit.
                 (jitter (* capped 0.25 (- (cl-random 1.0) 0.5)))
                 (delay  (max 0.5 (+ capped jitter))))
            (setq job (plist-put job :attempt next))
            (message
             "Claude queue: %s rate-limited, retry %d/%d in %.1fs"
             label next tibetan-claude-queue-max-retries delay)
            (let ((retry-job job))
              (run-at-time
               delay nil
               (lambda ()
                 ;; Push to the front so the retry takes priority over
                 ;; freshly-submitted work — keeps batches fair.
                 (setq tibetan-claude-queue--pending
                       (cons retry-job tibetan-claude-queue--pending))
                 (tibetan-claude-queue--maybe-dispatch))))))))
     ;; ----- non-retryable error ---------------------------------------
     (t
      (cl-incf tibetan-claude-queue--failed)
      (message "Claude queue: %s failed: %s"
               label (or (plist-get status :error) "unknown"))
      (tibetan-claude-queue--call-fail job status))))
  ;; Always try to advance the queue, regardless of branch above.
  (tibetan-claude-queue--maybe-dispatch))

(defun tibetan-claude-queue--call-fail (job status)
  "Invoke JOB's :on-fail callback (if any) with STATUS, swallowing errors."
  (let ((cb (plist-get job :on-fail))
        (label (plist-get job :label)))
    (when cb
      (condition-case err
          (funcall cb status)
        (error
         (message "Claude queue: on-fail for %s raised: %s"
                  label (error-message-string err)))))))

(provide 'tibetan-claude-queue)
;;; tibetan-claude-queue.el ends here
