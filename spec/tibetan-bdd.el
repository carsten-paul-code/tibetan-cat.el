;;; tibetan-bdd.el --- BDD testing framework for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Behavior-Driven Development framework using Specification by Example.
;;
;; Specs are organized into suites by feature area.
;; Golden examples are captured from working functionality to prevent regressions.
;;
;; Usage:
;;   (tibetan-bdd-run-all)           ; Run all specs
;;   (tibetan-bdd-run-suite 'verbs)  ; Run specific suite
;;   (tibetan-bdd-capture-example)   ; Capture current behavior as spec

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; SPEC DATA STRUCTURES
;; ============================================================================

(defvar tibetan-bdd-suites (make-hash-table :test 'eq)
  "Hash table of spec suites, keyed by suite name symbol.")

(defvar tibetan-bdd-results nil
  "Results from last spec run.")

(cl-defstruct tibetan-bdd-spec
  "A single BDD specification."
  name           ; Descriptive name
  given          ; Setup/preconditions (string or form)
  when           ; Action to perform (form)
  then           ; Expected outcomes (list of assertions)
  example-source ; Where this example came from (file, segment, etc.)
  tags)          ; Tags for filtering (:regression, :critical, etc.)

(cl-defstruct tibetan-bdd-suite
  "A collection of related specs."
  name           ; Suite name (symbol)
  description    ; Human-readable description
  specs          ; List of tibetan-bdd-spec
  setup          ; Common setup for all specs in suite
  teardown)      ; Common teardown

;; ============================================================================
;; SUITE DEFINITION MACROS
;; ============================================================================

(defmacro define-bdd-suite (name description &rest body)
  "Define a BDD suite NAME with DESCRIPTION.
BODY contains spec definitions."
  (declare (indent 2))
  `(let ((suite (make-tibetan-bdd-suite
                 :name ',name
                 :description ,description
                 :specs nil)))
     ,@body
     (puthash ',name suite tibetan-bdd-suites)
     suite))

(defmacro spec (name &rest clauses)
  "Define a spec NAME with GIVEN/WHEN/THEN clauses.
Adds to the current suite being defined."
  (declare (indent 1))
  (let ((given nil)
        (when-form nil)
        (then-forms nil)
        (example-source nil)
        (tags nil))
    ;; Parse clauses
    (while clauses
      (let ((key (pop clauses))
            (val (pop clauses)))
        (pcase key
          (:given (setq given val))
          (:when (setq when-form val))
          (:then (setq then-forms (if (listp (car val)) val (list val))))
          (:example (setq example-source val))
          (:tags (setq tags val)))))
    `(push (make-tibetan-bdd-spec
            :name ,name
            :given ',given
            :when ',when-form
            :then ',then-forms
            :example-source ,example-source
            :tags ',tags)
           (tibetan-bdd-suite-specs suite))))

;; ============================================================================
;; ASSERTION HELPERS
;; ============================================================================

(defun tibetan-bdd-assert-contains (haystack needle &optional message)
  "Assert that HAYSTACK contains NEEDLE."
  (unless (and haystack (string-match-p (regexp-quote needle) haystack))
    (error "FAILED: %s\n  Expected to contain: %s\n  Actual: %s"
           (or message "contains assertion")
           needle
           (or haystack "nil"))))

(defun tibetan-bdd-assert-has-key (result key &optional message)
  "Assert that RESULT alist has KEY."
  (unless (alist-get key result)
    (error "FAILED: %s\n  Expected key: %s\n  In: %s"
           (or message "has-key assertion")
           key result)))

(defun tibetan-bdd-assert-equal (expected actual &optional message)
  "Assert that EXPECTED equals ACTUAL."
  (unless (equal expected actual)
    (error "FAILED: %s\n  Expected: %s\n  Actual: %s"
           (or message "equality assertion")
           expected actual)))

(defun tibetan-bdd-assert-matches (pattern text &optional message)
  "Assert that TEXT matches regex PATTERN."
  (unless (and text (string-match-p pattern text))
    (error "FAILED: %s\n  Pattern: %s\n  Text: %s"
           (or message "regex assertion")
           pattern (or text "nil"))))

(defun tibetan-bdd-assert-count-gte (list min-count &optional message)
  "Assert that LIST has at least MIN-COUNT elements."
  (unless (>= (length list) min-count)
    (error "FAILED: %s\n  Expected at least: %d\n  Actual count: %d"
           (or message "count assertion")
           min-count (length list))))

(defun tibetan-bdd-assert-truthy (value &optional message)
  "Assert that VALUE is non-nil."
  (unless value
    (error "FAILED: %s\n  Expected truthy value, got: %s"
           (or message "truthy assertion")
           value)))

(defun tibetan-bdd-assert-nil (value &optional message)
  "Assert that VALUE is nil."
  (when value
    (error "FAILED: %s\n  Expected nil, got: %s"
           (or message "nil assertion")
           value)))

;; Alias for ERT-style should
(defalias 'should 'tibetan-bdd-assert-truthy)
(defalias 'should-not 'tibetan-bdd-assert-nil)

;; ============================================================================
;; SPEC RUNNER
;; ============================================================================

(defvar tibetan-bdd--current-result nil
  "Holds the result of the WHEN clause for use in THEN assertions.")

(defun tibetan-bdd-run-spec (spec)
  "Run a single SPEC, returning (name . result)."
  (let ((name (tibetan-bdd-spec-name spec))
        (result nil))
    (condition-case err
        (progn
          ;; Execute GIVEN (setup)
          (when (tibetan-bdd-spec-given spec)
            (eval (tibetan-bdd-spec-given spec)))
          ;; Execute WHEN (action) and capture result
          (setq result (eval (tibetan-bdd-spec-when spec)))
          (setq tibetan-bdd--current-result result)
          ;; Execute THEN (assertions) with result bound
          (dolist (assertion (tibetan-bdd-spec-then spec))
            ;; Substitute 'result' symbol with actual value in assertion
            (eval `(let ((result ',result))
                     ,assertion)))
          (cons name 'passed))
      (error
       (cons name (list 'failed (error-message-string err)))))))

(defun tibetan-bdd-run-suite (suite-name)
  "Run all specs in SUITE-NAME, returning results."
  (let* ((suite (gethash suite-name tibetan-bdd-suites))
         (results nil))
    (unless suite
      (error "Suite not found: %s" suite-name))
    ;; Run setup if defined
    (when (tibetan-bdd-suite-setup suite)
      (eval (tibetan-bdd-suite-setup suite)))
    ;; Run each spec
    (dolist (spec (reverse (tibetan-bdd-suite-specs suite)))
      (push (tibetan-bdd-run-spec spec) results))
    ;; Run teardown if defined
    (when (tibetan-bdd-suite-teardown suite)
      (eval (tibetan-bdd-suite-teardown suite)))
    (nreverse results)))

(defun tibetan-bdd-run-all ()
  "Run all defined specs, returning summary."
  (let ((all-results nil)
        (passed 0)
        (failed 0))
    (maphash
     (lambda (name suite)
       (let ((suite-results (tibetan-bdd-run-suite name)))
         (dolist (r suite-results)
           (push (cons name r) all-results)
           (if (eq (cdr r) 'passed)
               (cl-incf passed)
             (cl-incf failed)))))
     tibetan-bdd-suites)
    (setq tibetan-bdd-results (nreverse all-results))
    (list :passed passed :failed failed :results tibetan-bdd-results)))

;; ============================================================================
;; REPORTING
;; ============================================================================

(defun tibetan-bdd-report (results)
  "Print a report of RESULTS."
  (let ((passed (plist-get results :passed))
        (failed (plist-get results :failed)))
    (princ "\n")
    (princ "=========================================\n")
    (princ "BDD Specification Results\n")
    (princ "=========================================\n\n")

    ;; Show failures first
    (when (> failed 0)
      (princ "FAILURES:\n")
      (dolist (r (plist-get results :results))
        (let ((suite (car r))
              (spec-name (cadr r))
              (result (cddr r)))
          (when (listp result)
            (princ (format "\n  [%s] %s\n" suite spec-name))
            (princ (format "    %s\n" (cadr result))))))
      (princ "\n"))

    ;; Summary
    (princ (format "Passed: %d\n" passed))
    (princ (format "Failed: %d\n" failed))
    (princ (format "Total:  %d\n" (+ passed failed)))
    (princ "=========================================\n")

    (if (= failed 0)
        (princ "All specifications passed!\n")
      (princ (format "%d specification(s) failed!\n" failed)))

    ;; Return exit code
    (if (= failed 0) 0 1)))

;; ============================================================================
;; REVERSE SPECIFICATION - CAPTURE WORKING EXAMPLES
;; ============================================================================

(defun tibetan-bdd-capture-verb-example (tibetan-text expected-verbs)
  "Capture a verb detection example.
TIBETAN-TEXT is the input, EXPECTED-VERBS is list of (verb . meaning)."
  `(spec ,(format "Detect verbs in: %.30s..." tibetan-text)
     :given (setq test-text ,tibetan-text)
     :when (tibetan-bdd--extract-verbs test-text)
     :then ((tibetan-bdd-assert-count-gte result ,(length expected-verbs)
             "Should find expected number of verbs")
            ,@(mapcar (lambda (v)
                        `(tibetan-bdd-assert-contains
                          (mapconcat (lambda (x) (alist-get 'lemma x)) result " ")
                          ,(car v)
                          ,(format "Should detect verb %s" (car v))))
                      expected-verbs))
     :example "Captured from working analysis"
     :tags (:regression :verb-detection)))

(defun tibetan-bdd--extract-verbs (text)
  "Helper to extract verbs from TEXT for testing."
  (when (fboundp 'tibetan-parse-enhanced)
    (let* ((parsed (tibetan-parse-enhanced text))
           (words (alist-get 'words parsed))
           (multiword-units (alist-get 'multiword-units parsed)))
      (when (fboundp 'tibetan-extract-verbs-compound-aware)
        (tibetan-extract-verbs-compound-aware text words multiword-units)))))

(provide 'tibetan-bdd)
;;; tibetan-bdd.el ends here
