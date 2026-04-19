;;; generate-test-doc.el --- Generate living documentation from ERT tests -*- lexical-binding: t -*-

;;; Commentary:
;; Generates an HTML living documentation report from ERT unit tests.
;; Parses test files to extract test names, docstrings, and section structure,
;; then runs all tests and produces a browsable report.
;;
;; Usage:
;;   emacs --batch -L . -L core -L analysis -L persist -L workspace \
;;     -L philology -L config -L data -L doc-prep -L setup -L spec -L test \
;;     -l tibetan-cat.el -l test/generate-test-doc.el \
;;     -f tibetan-ert-generate-living-doc

;;; Code:

(require 'cl-lib)
(require 'ert)

;; ============================================================================
;; TEST FILE PARSING
;; ============================================================================

(defun tibetan-ert-doc--parse-test-file (filepath)
  "Parse FILEPATH to extract test metadata.
Returns alist with :file, :module, :commentary, :sections."
  (let* ((filename (file-name-nondirectory filepath))
         (module (replace-regexp-in-string
                  "-test\\.el$" ""
                  (replace-regexp-in-string "^tibetan-" "" filename)))
         (commentary nil)
         (sections '())
         (current-section "General")
         (tests '()))
    (with-temp-buffer
      (insert-file-contents filepath)
      ;; Extract Commentary
      (goto-char (point-min))
      (when (re-search-forward "^;;; Commentary:\n" nil t)
        (let ((start (point))
              (end (or (save-excursion
                         (when (re-search-forward "^;;; Code:" nil t)
                           (match-beginning 0)))
                       (point-max))))
          (setq commentary
                (replace-regexp-in-string
                 "^;+ ?" ""
                 (string-trim (buffer-substring-no-properties start end))))))
      ;; Extract sections and tests
      (goto-char (point-min))
      (while (not (eobp))
        (cond
         ;; Section header comment
         ((looking-at "^;; =+\n;; \\(.+\\)\n;; =+")
          (setq current-section (match-string 1))
          (forward-line 3))
         ;; ert-deftest
         ((looking-at "^(ert-deftest \\([^ ]+\\) ()")
          (let* ((test-name (match-string 1))
                 (docstring nil)
                 (body-start nil)
                 (body-end nil))
            ;; Find docstring
            (save-excursion
              (forward-line 1)
              (when (looking-at "^  \"\\(.*\\)\"")
                (setq docstring (match-string 1))))
            ;; Find test body extent
            (setq body-start (point))
            (forward-sexp 1)
            (setq body-end (point))
            (let ((body (buffer-substring-no-properties body-start body-end)))
              (push `((name . ,test-name)
                      (docstring . ,(or docstring ""))
                      (section . ,current-section)
                      (body . ,body)
                      (assertions . ,(tibetan-ert-doc--count-assertions body))
                      (tibetan-input . ,(tibetan-ert-doc--extract-tibetan body)))
                    tests))))
         (t (forward-line 1)))))
    ;; Group tests by section
    (let ((section-map (make-hash-table :test 'equal)))
      (dolist (test (nreverse tests))
        (let ((sec (alist-get 'section test)))
          (puthash sec (append (gethash sec section-map) (list test))
                   section-map)))
      (maphash (lambda (name tests-in-sec)
                 (push `((name . ,name) (tests . ,tests-in-sec))
                       sections))
               section-map)
      `((file . ,filename)
        (module . ,module)
        (commentary . ,commentary)
        (sections . ,(nreverse sections))
        (test-count . ,(length tests))))))

(defun tibetan-ert-doc--count-assertions (body)
  "Count assertion forms in test BODY."
  (let ((count 0) (start 0))
    (while (string-match "(should\\b" body start)
      (cl-incf count)
      (setq start (match-end 0)))
    count))

(defun tibetan-ert-doc--extract-tibetan (body)
  "Extract Tibetan text examples from test BODY, if any."
  (let ((examples '()))
    (let ((start 0))
      (while (string-match "\"\\([^\"]*[ༀ-࿿][^\"]*\\)\"" body start)
        (push (match-string 1 body) examples)
        (setq start (match-end 0))))
    (when examples
      (cl-remove-duplicates (nreverse examples) :test 'equal))))

;; ============================================================================
;; SECTION NAME CLEANING & FUNCTION DESCRIPTION LOOKUP
;; ============================================================================

(defun tibetan-ert-doc--clean-section-name (name)
  "Clean section NAME by removing trailing TESTS/TEST and annotations."
  (let* ((cleaned (replace-regexp-in-string
                   "[ \t]*TESTS?[ \t]*$" "" name))
         (cleaned (replace-regexp-in-string
                   "[ \t]*(untested public function)[ \t]*$" "" cleaned))
         (cleaned (string-trim cleaned)))
    (if (string-empty-p cleaned) name cleaned)))

(defun tibetan-ert-doc--section-func-docstring (section-name)
  "Try to find the docstring for the function implied by SECTION-NAME.
Derives the function name from the section heading and looks up its docstring."
  (let* ((cleaned (tibetan-ert-doc--clean-section-name section-name))
         ;; Convert section name to function name:
         ;; \"FILENAME GENERATION\" -> \"tibetan-filename-generation\"
         ;; \"PARSE ENHANCED\" -> \"tibetan-parse-enhanced\"
         (func-name (concat "tibetan-"
                            (downcase (replace-regexp-in-string
                                       "[ \t]+" "-" cleaned))))
         (sym (intern-soft func-name)))
    (when (and sym (fboundp sym))
      (let ((doc (documentation sym)))
        (when doc
          (car (split-string doc "\n")))))))

;; ============================================================================
;; TEST EXECUTION
;; ============================================================================

(defun tibetan-ert-doc--run-all-tests ()
  "Run all defined ERT tests and return results as hash table.
Keys are test name strings, values are passed, skipped, or (failed . detail).
Uses `ert-test-most-recent-result' which is always set by `ert-run-test',
even when it signals conditions like `ert-test-failed' or `ert-test-skipped'."
  (let ((result-map (make-hash-table :test 'equal)))
    (mapatoms
     (lambda (sym)
       (when (ert-test-boundp sym)
         (let* ((test-name (symbol-name sym))
                (test-obj (ert-get-test sym))
                (run-error nil))
           ;; ert-run-test records the result on the test object but may
           ;; also signal ert-test-failed or ert-test-skipped.  Catch all
           ;; signals, then inspect the recorded result.
           (condition-case err
               (ert-run-test test-obj)
             (error
              (setq run-error (error-message-string err))))
           ;; Inspect recorded result
           (let ((result (ert-test-most-recent-result test-obj)))
             (cond
              ((null result)
               (puthash test-name
                        (cons 'failed (or run-error "No result recorded"))
                        result-map))
              ((ert-test-passed-p result)
               (puthash test-name 'passed result-map))
              ((or (ert-test-result-type-p result :skipped)
                   (and (fboundp 'ert-test-skipped-p)
                        (ert-test-skipped-p result)))
               (puthash test-name 'skipped result-map))
              (t
               (let ((msg (or (let ((m (condition-case nil
                                           (ert-test-result-messages result)
                                         (error nil))))
                                (when (and m (not (string-empty-p m))) m))
                              ;; Try to get condition info for should failures
                              (condition-case nil
                                  (let ((cond-data (ert-test-result-with-condition-condition result)))
                                    (when cond-data (format "%S" cond-data)))
                                (error nil))
                              run-error
                              (format "Result type: %s" (type-of result)))))
                 (puthash test-name (cons 'failed msg) result-map)))))))))
    result-map))

;; ============================================================================
;; HTML GENERATION
;; ============================================================================

(defun tibetan-ert-doc--html-escape (str)
  "Escape HTML special characters in STR."
  (if (not (stringp str)) ""
    (let ((s str))
      (setq s (replace-regexp-in-string "&" "&amp;" s))
      (setq s (replace-regexp-in-string "<" "&lt;" s))
      (setq s (replace-regexp-in-string ">" "&gt;" s))
      (setq s (replace-regexp-in-string "\"" "&quot;" s))
      s)))

(defun tibetan-ert-doc--generate-html (modules result-map)
  "Generate HTML report from MODULES data and RESULT-MAP."
  (let ((total-tests 0)
        (total-passed 0)
        (total-failed 0)
        (total-skipped 0)
        (total-assertions 0)
        (timestamp (format-time-string "%Y-%m-%d %H:%M:%S")))
    ;; Count totals
    (dolist (mod modules)
      (dolist (sec (alist-get 'sections mod))
        (dolist (test (alist-get 'tests sec))
          (cl-incf total-tests)
          (cl-incf total-assertions (alist-get 'assertions test))
          (let ((res (gethash (alist-get 'name test) result-map)))
            (cond
             ((eq res 'passed) (cl-incf total-passed))
             ((or (eq res 'skipped) (null res)) (cl-incf total-skipped))
             (t (cl-incf total-failed)))))))

    (concat
     "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
     "<meta charset=\"UTF-8\">\n"
     "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
     "<title>Tibetan CAT Tool — Unit Test Report</title>\n"
     (tibetan-ert-doc--generate-css)
     "</head>\n<body>\n"

     ;; Header
     "<header>\n"
     "<div class=\"header-content\">\n"
     "<h1>ༀ Tibetan CAT Tool</h1>\n"
     "<p class=\"subtitle\">Unit Test Report — ERT Living Documentation</p>\n"
     "<p class=\"meta\">Generated: " timestamp "</p>\n"
     "</div>\n</header>\n"

     ;; Dashboard
     "<div class=\"dashboard\">\n"
     (tibetan-ert-doc--stat-card (number-to-string (length modules)) "Modules" "")
     (tibetan-ert-doc--stat-card (number-to-string total-tests) "Tests" "")
     (tibetan-ert-doc--stat-card (number-to-string total-assertions) "Assertions" "")
     (tibetan-ert-doc--stat-card (number-to-string total-passed) "Passing" " stat-passed")
     (if (> total-failed 0)
         (tibetan-ert-doc--stat-card (number-to-string total-failed) "Failing" " stat-failed")
       "")
     (if (> total-skipped 0)
         (tibetan-ert-doc--stat-card (number-to-string total-skipped) "Skipped" " stat-skipped")
       "")
     (tibetan-ert-doc--stat-card
      (format "%.0f%%" (* 100.0 (/ (float total-passed) (max 1 total-tests))))
      "Pass Rate" "")
     "</div>\n"

     ;; Progress bar
     "<div class=\"progress-container\">\n"
     "<div class=\"progress-bar\" style=\"width: "
     (format "%.1f" (* 100.0 (/ (float total-passed) (max 1 total-tests))))
     "%\"></div>\n</div>\n"

     ;; Table of contents
     "<nav class=\"toc\">\n<h2>Modules Under Test</h2>\n<ul>\n"
     (mapconcat
      (lambda (mod)
        (let* ((module (alist-get 'module mod))
               (count (alist-get 'test-count mod))
               (commentary (or (alist-get 'commentary mod) "")))
          (format "<li><a href=\"#%s\">%s</a> <span class=\"toc-count\">%d tests</span><br><span class=\"toc-desc\">%s</span></li>\n"
                  module
                  (tibetan-ert-doc--html-escape module)
                  count
                  (tibetan-ert-doc--html-escape
                   (car (split-string commentary "\n"))))))
      modules "")
     "</ul>\n</nav>\n"

     ;; Module sections
     "<main>\n"
     (mapconcat
      (lambda (mod) (tibetan-ert-doc--generate-module-html mod result-map))
      modules "\n")
     "</main>\n"

     ;; Cross-reference
     "<nav class=\"toc\" style=\"margin-top:32px;text-align:center;\">\n"
     "<p style=\"font-size:1rem;\">See also: "
     "<a href=\"function-overview.html\" style=\"font-weight:600;\">Function Overview &amp; Test Coverage Map</a>"
     " — all public functions with their test mappings</p>\n"
     "</nav>\n"

     ;; Footer
     "<footer>\n"
     "<p>Tibetan CAT Tool v2.1.0 — ERT Unit Test Living Documentation</p>\n"
     "<p>Framework: Emacs Regression Testing (ERT)</p>\n"
     "</footer>\n"
     "</body>\n</html>\n")))

(defun tibetan-ert-doc--stat-card (number label extra-class)
  "Generate a stat card with NUMBER, LABEL, and EXTRA-CLASS."
  (format "<div class=\"stat-card%s\"><div class=\"stat-number\">%s</div><div class=\"stat-label\">%s</div></div>\n"
          extra-class number label))

(defun tibetan-ert-doc--generate-module-html (mod result-map)
  "Generate HTML for a module MOD using RESULT-MAP."
  (let* ((module (alist-get 'module mod))
         (file (alist-get 'file mod))
         (commentary (alist-get 'commentary mod))
         (sections (alist-get 'sections mod))
         (mod-passed 0) (mod-failed 0) (mod-skipped 0))
    ;; Count per module
    (dolist (sec sections)
      (dolist (test (alist-get 'tests sec))
        (let ((res (gethash (alist-get 'name test) result-map)))
          (cond
           ((eq res 'passed) (cl-incf mod-passed))
           ((or (eq res 'skipped) (null res)) (cl-incf mod-skipped))
           (t (cl-incf mod-failed))))))
    (concat
     "<section class=\"suite\" id=\"" module "\">\n"
     "<div class=\"suite-header\">\n"
     "<h2>" (tibetan-ert-doc--html-escape module) "</h2>\n"
     "<p class=\"suite-file\">" (tibetan-ert-doc--html-escape file) "</p>\n"
     (if commentary
         (format "<p class=\"suite-desc\">%s</p>\n"
                 (tibetan-ert-doc--html-escape
                  (car (split-string commentary "\n"))))
       "")
     "<div class=\"suite-stats\">"
     (format "<span class=\"badge badge-passed\">%d passed</span>" mod-passed)
     (if (> mod-failed 0)
         (format "<span class=\"badge badge-failed\">%d failed</span>" mod-failed)
       "")
     (if (> mod-skipped 0)
         (format "<span class=\"badge badge-skipped\">%d skipped</span>" mod-skipped)
       "")
     "</div>\n</div>\n"

     ;; Sections within module
     (mapconcat
      (lambda (sec)
        (let* ((sec-name (alist-get 'name sec))
               (clean-name (tibetan-ert-doc--clean-section-name sec-name))
               (func-doc (tibetan-ert-doc--section-func-docstring sec-name))
               (tests (alist-get 'tests sec)))
          (concat
           "<div class=\"test-section\">\n"
           "<h3 class=\"section-title\">"
           (tibetan-ert-doc--html-escape clean-name) "</h3>\n"
           (if func-doc
               (format "<p class=\"section-desc\">%s</p>\n"
                       (tibetan-ert-doc--html-escape func-doc))
             "")
           "<div class=\"specs\">\n"
           (mapconcat
            (lambda (test) (tibetan-ert-doc--generate-test-html test result-map))
            tests "\n")
           "</div>\n</div>\n")))
      sections "\n")
     "</section>\n")))

(defun tibetan-ert-doc--generate-test-html (test result-map)
  "Generate HTML for a single TEST using RESULT-MAP."
  (let* ((name (alist-get 'name test))
         (docstring (alist-get 'docstring test))
         (assertions (alist-get 'assertions test))
         (tibetan-input (alist-get 'tibetan-input test))
         (result (gethash name result-map))
         (status (cond ((eq result 'passed) "passed")
                       ((eq result 'skipped) "skipped")
                       ((null result) "skipped")  ; not loaded/run
                       (t "failed")))
         (icon (cond ((eq result 'passed) "&#10003;")
                     ((or (eq result 'skipped) (null result)) "&#9711;")
                     (t "&#10007;"))))
    (concat
     "<div class=\"spec spec-" status "\">\n"
     "<div class=\"spec-header\" onclick=\"this.parentElement.classList.toggle('expanded')\">\n"
     "<span class=\"status-icon " status "\">" icon "</span>\n"
     "<span class=\"spec-name\">"
     (tibetan-ert-doc--html-escape
      (replace-regexp-in-string "^tibetan-" "" name))
     "</span>\n"
     (if (> assertions 0)
         (format "<span class=\"assertion-count\">%d assertions</span>" assertions)
       "")
     "</div>\n"

     ;; Body
     "<div class=\"spec-body\">\n"
     (if (and docstring (not (string-empty-p docstring)))
         (format "<div class=\"docstring\">%s</div>\n"
                 (tibetan-ert-doc--html-escape docstring))
       "")
     ;; Tibetan examples
     (if tibetan-input
         (concat "<div class=\"tibetan-examples\">"
                 "<span class=\"label\">Tibetan input:</span> "
                 (mapconcat
                  (lambda (t-text)
                    (format "<span class=\"tibetan-text\">%s</span>"
                            (tibetan-ert-doc--html-escape t-text)))
                  (cl-subseq tibetan-input 0 (min 3 (length tibetan-input)))
                  " ")
                 (if (> (length tibetan-input) 3) " ..." "")
                 "</div>\n")
       "")
     ;; Failure detail
     (when (and (listp result) (eq (car result) 'failed))
       (format "<div class=\"failure-msg\">%s</div>\n"
               (tibetan-ert-doc--html-escape (or (cdr result) ""))))
     "</div>\n</div>\n")))

;; ============================================================================
;; CSS
;; ============================================================================

(defun tibetan-ert-doc--generate-css ()
  "Generate CSS for the ERT test report."
  "<style>
:root {
  --bg: #fafafa; --surface: #ffffff; --text: #1a1a2e;
  --text-muted: #6b7280; --border: #e5e7eb;
  --primary: #1e40af; --primary-light: #dbeafe;
  --passed: #059669; --passed-bg: #ecfdf5;
  --failed: #dc2626; --failed-bg: #fef2f2;
  --skipped: #d97706; --skipped-bg: #fffbeb;
  --tibetan-deep: #0f172a;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: var(--bg); color: var(--text); line-height: 1.6;
  max-width: 1100px; margin: 0 auto; padding: 0 24px 48px;
}
header {
  background: linear-gradient(135deg, var(--tibetan-deep), var(--primary));
  color: white; padding: 40px 32px; margin: 0 -24px 32px; text-align: center;
}
header h1 { font-size: 2rem; font-weight: 700; margin-bottom: 4px; }
.subtitle { font-size: 1.1rem; opacity: 0.9; font-weight: 300; }
.meta { font-size: 0.85rem; opacity: 0.7; margin-top: 8px; }

.dashboard {
  display: flex; gap: 16px; margin-bottom: 8px; flex-wrap: wrap;
  justify-content: center;
}
.stat-card {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 8px; padding: 16px 24px; text-align: center;
  min-width: 110px; flex: 1; max-width: 160px;
}
.stat-number { font-size: 2rem; font-weight: 700; color: var(--primary); }
.stat-label { font-size: 0.8rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; }
.stat-passed .stat-number { color: var(--passed); }
.stat-failed .stat-number { color: var(--failed); }
.stat-skipped .stat-number { color: var(--skipped); }

.progress-container {
  background: var(--border); border-radius: 8px; height: 8px;
  margin-bottom: 32px; overflow: hidden;
}
.progress-bar {
  background: linear-gradient(90deg, var(--passed), #34d399);
  height: 100%; border-radius: 8px;
}

.toc {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 8px; padding: 24px; margin-bottom: 32px;
}
.toc h2 { font-size: 1.1rem; margin-bottom: 12px; color: var(--primary); }
.toc ul { list-style: none; columns: 2; column-gap: 32px; }
.toc li { margin-bottom: 8px; break-inside: avoid; }
.toc a { color: var(--primary); text-decoration: none; font-weight: 500; }
.toc a:hover { text-decoration: underline; }
.toc-count { color: var(--text-muted); font-size: 0.85rem; }
.toc-desc { color: var(--text-muted); font-size: 0.85rem; }

.suite {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 8px; margin-bottom: 24px; overflow: hidden;
}
.suite-header {
  padding: 20px 24px; border-bottom: 1px solid var(--border);
  background: linear-gradient(to right, var(--primary-light), var(--surface));
}
.suite-header h2 { font-size: 1.25rem; color: var(--tibetan-deep); }
.suite-file { font-size: 0.85rem; color: var(--text-muted); font-family: monospace; }
.suite-desc { color: var(--text-muted); margin-top: 4px; }
.suite-stats { margin-top: 8px; display: flex; gap: 8px; }
.badge {
  font-size: 0.8rem; padding: 2px 10px; border-radius: 12px; font-weight: 500;
}
.badge-passed { background: var(--passed-bg); color: var(--passed); }
.badge-failed { background: var(--failed-bg); color: var(--failed); }
.badge-skipped { background: var(--skipped-bg); color: var(--skipped); }

.test-section { padding: 0 16px; }
.section-title {
  font-size: 0.9rem; color: var(--text-muted); padding: 12px 0 4px;
  border-bottom: 1px solid var(--border); margin-bottom: 2px;
  text-transform: uppercase; letter-spacing: 0.5px;
}
.section-desc {
  font-size: 0.85rem; color: var(--text-muted); font-style: italic;
  margin: 0 0 8px 0; padding: 0;
}

.specs { padding-bottom: 8px; }
.spec {
  border-left: 4px solid var(--passed); margin: 6px 0;
  border-radius: 4px; background: var(--passed-bg);
}
.spec-failed { border-left-color: var(--failed); background: var(--failed-bg); }
.spec-skipped { border-left-color: var(--skipped); background: var(--skipped-bg); }
.spec-header {
  padding: 8px 14px; cursor: pointer; display: flex;
  align-items: center; gap: 8px; flex-wrap: wrap;
}
.spec-header:hover { opacity: 0.85; }
.status-icon { font-size: 1rem; font-weight: 700; width: 20px; text-align: center; }
.status-icon.passed { color: var(--passed); }
.status-icon.failed { color: var(--failed); }
.status-icon.skipped { color: var(--skipped); }
.spec-name { font-weight: 500; flex: 1; font-size: 0.95rem; }
.assertion-count {
  font-size: 0.75rem; color: var(--text-muted);
  background: var(--border); padding: 1px 8px; border-radius: 10px;
}

.spec-body {
  max-height: 0; overflow: hidden; transition: max-height 0.3s ease;
  padding: 0 14px;
}
.spec.expanded .spec-body {
  max-height: 400px; padding: 10px 14px 14px;
  border-top: 1px solid rgba(0,0,0,0.08);
}
.docstring { font-style: italic; color: var(--text-muted); margin-bottom: 6px; }
.tibetan-examples { margin-bottom: 6px; }
.tibetan-examples .label { font-size: 0.85rem; color: var(--text-muted); }
.tibetan-text {
  font-family: 'Noto Sans Tibetan', 'Tibetan Machine Uni', serif;
  font-size: 1.1rem; color: var(--tibetan-deep);
  background: rgba(0,0,0,0.04); padding: 2px 6px; border-radius: 3px;
  margin: 0 2px;
}
.failure-msg {
  background: var(--failed-bg); border: 1px solid #fca5a5;
  border-radius: 4px; padding: 8px 12px; margin-top: 8px;
  font-family: monospace; font-size: 0.85rem; color: var(--failed);
  white-space: pre-wrap; max-height: 200px; overflow-y: auto;
}

footer {
  text-align: center; padding: 32px; color: var(--text-muted);
  font-size: 0.85rem; border-top: 1px solid var(--border); margin-top: 32px;
}
footer p { margin-bottom: 4px; }

@media (max-width: 700px) {
  .toc ul { columns: 1; }
  .dashboard { flex-direction: column; align-items: center; }
}
</style>\n")

;; ============================================================================
;; ENTRY POINT
;; ============================================================================

;;;###autoload
(defun tibetan-ert-generate-living-doc ()
  "Generate living documentation HTML from ERT unit tests.
Parses test files, runs all tests, and produces a browsable HTML report."
  (interactive)
  (let* ((project-root (or (getenv "PROJECT_ROOT") default-directory))
         (test-dir (expand-file-name "test" project-root))
         (test-files (sort (directory-files test-dir t "-test\\.el$")
                           #'string<))
         (modules '()))

    ;; Parse all test files
    (dolist (file test-files)
      (condition-case err
          (let ((mod-data (tibetan-ert-doc--parse-test-file file)))
            (when (> (alist-get 'test-count mod-data) 0)
              (push mod-data modules)))
        (error (message "Warning: Could not parse %s: %s"
                        file (error-message-string err)))))
    (setq modules (nreverse modules))

    ;; Run all tests
    (princ "Running all ERT tests...\n")
    (let* ((result-map (tibetan-ert-doc--run-all-tests))
           (html (tibetan-ert-doc--generate-html modules result-map))
           (output-file (expand-file-name "docs/test-documentation.html" project-root)))

      (with-temp-file output-file
        (insert html))

      ;; Summary
      (let ((total 0) (passed 0) (failed 0) (skipped 0))
        (maphash (lambda (_k v)
                   (cl-incf total)
                   (cond ((eq v 'passed) (cl-incf passed))
                         ((eq v 'skipped) (cl-incf skipped))
                         (t (cl-incf failed))))
                 result-map)
        (princ (format "\nTest documentation: %s\n" output-file))
        (princ (format "Modules: %d | Tests: %d | Passed: %d | Failed: %d | Skipped: %d\n"
                       (length modules) total passed failed skipped))))))

(provide 'generate-test-doc)
;;; generate-test-doc.el ends here
