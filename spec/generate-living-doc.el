;;; generate-living-doc.el --- Generate living documentation from BDD specs -*- lexical-binding: t -*-

;;; Commentary:
;; Generates an HTML living documentation report from BDD specifications.
;; Inspired by Serenity BDD, SpecFlow, and Cucumber living documentation.
;;
;; Usage:
;;   emacs --batch -L . -L core -L analysis -L persist -L workspace \
;;     -L philology -L config -L data -L doc-prep -L setup -L spec -L test \
;;     -l tibetan-cat.el -l spec/generate-living-doc.el \
;;     -f tibetan-bdd-generate-living-doc

;;; Code:

(require 'cl-lib)
(require 'tibetan-bdd)

;; Ensure tibetan-cat-data-dir points to project root (not data/ subdir)
;; so that dictionary paths like "data/dictionaries/compounds.json" resolve
(let ((project-root (or (getenv "PROJECT_ROOT") default-directory)))
  (setq tibetan-cat-data-dir project-root)
  ;; Reload dictionaries with correct path
  (when (fboundp 'tibetan-load-dictionaries)
    (setq tibetan-compounds-dict nil)
    (setq tibetan-proper-nouns-dict nil)
    (tibetan-load-dictionaries)))

;; Load all spec suites
(let ((spec-dir (expand-file-name "spec/suites/"
                  (or (getenv "PROJECT_ROOT") default-directory))))
  (when (file-directory-p spec-dir)
    (dolist (file (directory-files spec-dir t "-spec\\.el$"))
      (condition-case err
          (load file nil t)
        (error (message "Warning: Could not load %s: %s" file (error-message-string err)))))))

;; ============================================================================
;; DATA EXTRACTION
;; ============================================================================

(defun tibetan-bdd--extract-all-suites ()
  "Extract all suite data as structured alists for report generation."
  (let ((suites '()))
    (maphash
     (lambda (name suite)
       (let ((specs '()))
         (dolist (spec (reverse (tibetan-bdd-suite-specs suite)))
           (push `((name . ,(tibetan-bdd-spec-name spec))
                   (given . ,(tibetan-bdd-spec-given spec))
                   (when . ,(tibetan-bdd-spec-when spec))
                   (then . ,(tibetan-bdd-spec-then spec))
                   (example . ,(tibetan-bdd-spec-example-source spec))
                   (tags . ,(tibetan-bdd-spec-tags spec)))
                 specs))
         (push `((name . ,name)
                 (description . ,(tibetan-bdd-suite-description suite))
                 (specs . ,(nreverse specs))
                 (count . ,(length (tibetan-bdd-suite-specs suite))))
               suites)))
     tibetan-bdd-suites)
    ;; Sort suites alphabetically
    (sort suites (lambda (a b)
                   (string< (symbol-name (alist-get 'name a))
                            (symbol-name (alist-get 'name b)))))))

(defun tibetan-bdd--run-and-collect ()
  "Run all specs and collect results keyed by suite+spec name."
  (let ((result-map (make-hash-table :test 'equal))
        (run-results (tibetan-bdd-run-all)))
    (dolist (r (plist-get run-results :results))
      (let* ((suite-name (symbol-name (car r)))
             (spec-name (cadr r))
             (outcome (cddr r))
             (key (format "%s::%s" suite-name spec-name)))
        (puthash key (if (eq outcome 'passed) 'passed
                       (list 'failed (cadr outcome)))
                 result-map)))
    (list :map result-map
          :passed (plist-get run-results :passed)
          :failed (plist-get run-results :failed))))

;; ============================================================================
;; HTML HELPERS
;; ============================================================================

(defun tibetan-bdd--html-escape (str)
  "Escape HTML special characters in STR."
  (if (not (stringp str)) (format "%S" str)
    (let ((s str))
      (setq s (replace-regexp-in-string "&" "&amp;" s))
      (setq s (replace-regexp-in-string "<" "&lt;" s))
      (setq s (replace-regexp-in-string ">" "&gt;" s))
      (setq s (replace-regexp-in-string "\"" "&quot;" s))
      s)))

(defun tibetan-bdd--format-sexp (sexp)
  "Format SEXP as readable, escaped string."
  (tibetan-bdd--html-escape
   (let ((print-level 4)
         (print-length 8))
     (format "%S" sexp))))

(defun tibetan-bdd--tag-class (tag)
  "Return CSS class for TAG keyword."
  (pcase tag
    (:critical "tag-critical")
    (:regression "tag-regression")
    (:tigress "tag-tigress")
    (_ "tag-default")))

;; ============================================================================
;; HTML GENERATION
;; ============================================================================

(defun tibetan-bdd--generate-html (suites run-data)
  "Generate living documentation HTML from SUITES and RUN-DATA."
  (let ((result-map (plist-get run-data :map))
        (total-passed (plist-get run-data :passed))
        (total-failed (plist-get run-data :failed))
        (total-specs (+ (plist-get run-data :passed) (plist-get run-data :failed)))
        (timestamp (format-time-string "%Y-%m-%d %H:%M:%S")))
    (concat
     "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
     "<meta charset=\"UTF-8\">\n"
     "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
     "<title>Tibetan CAT Tool — Living Documentation</title>\n"
     (tibetan-bdd--generate-css)
     "</head>\n<body>\n"

     ;; Header
     "<header>\n"
     "<div class=\"header-content\">\n"
     "<h1>ༀ Tibetan CAT Tool</h1>\n"
     "<p class=\"subtitle\">Living Documentation — Specification by Example</p>\n"
     "<p class=\"meta\">Generated: " timestamp "</p>\n"
     "</div>\n</header>\n"

     ;; Summary dashboard
     "<div class=\"dashboard\">\n"
     "<div class=\"stat-card\">"
     "<div class=\"stat-number\">" (number-to-string (length suites)) "</div>"
     "<div class=\"stat-label\">Feature Areas</div></div>\n"
     "<div class=\"stat-card\">"
     "<div class=\"stat-number\">" (number-to-string total-specs) "</div>"
     "<div class=\"stat-label\">Specifications</div></div>\n"
     "<div class=\"stat-card stat-passed\">"
     "<div class=\"stat-number\">" (number-to-string total-passed) "</div>"
     "<div class=\"stat-label\">Passing</div></div>\n"
     (if (> total-failed 0)
         (concat "<div class=\"stat-card stat-failed\">"
                 "<div class=\"stat-number\">" (number-to-string total-failed) "</div>"
                 "<div class=\"stat-label\">Failing</div></div>\n")
       "")
     "<div class=\"stat-card\">"
     "<div class=\"stat-number\">"
     (format "%.0f%%" (* 100.0 (/ (float total-passed) (max 1 total-specs))))
     "</div>"
     "<div class=\"stat-label\">Coverage</div></div>\n"
     "</div>\n"

     ;; Progress bar
     "<div class=\"progress-container\">\n"
     "<div class=\"progress-bar\" style=\"width: "
     (format "%.1f" (* 100.0 (/ (float total-passed) (max 1 total-specs))))
     "%\"></div>\n</div>\n"

     ;; Table of contents
     "<nav class=\"toc\">\n"
     "<h2>Feature Areas</h2>\n<ul>\n"
     (mapconcat
      (lambda (suite)
        (let* ((name (alist-get 'name suite))
               (desc (alist-get 'description suite))
               (count (alist-get 'count suite)))
          (format "<li><a href=\"#%s\">%s</a> <span class=\"toc-count\">%d specs</span><br><span class=\"toc-desc\">%s</span></li>\n"
                  (symbol-name name)
                  (tibetan-bdd--html-escape (symbol-name name))
                  count
                  (tibetan-bdd--html-escape (or desc "")))))
      suites "")
     "</ul>\n</nav>\n"

     ;; Suite sections
     "<main>\n"
     (mapconcat
      (lambda (suite) (tibetan-bdd--generate-suite-html suite result-map))
      suites "\n")
     "</main>\n"

     ;; Footer
     "<footer>\n"
     "<p>Tibetan CAT Tool v2.1.0 — BDD Living Documentation</p>\n"
     "<p>Framework: tibetan-bdd.el (Specification by Example)</p>\n"
     "<p>Academic references: Bialek (2022), Hill (2010), Rangjung Yeshe, Hopkins</p>\n"
     "</footer>\n"

     "</body>\n</html>\n")))

(defun tibetan-bdd--generate-suite-html (suite result-map)
  "Generate HTML for a single SUITE section using RESULT-MAP for status."
  (let* ((name (alist-get 'name suite))
         (name-str (symbol-name name))
         (desc (alist-get 'description suite))
         (specs (alist-get 'specs suite))
         ;; Count pass/fail for this suite
         (suite-passed 0)
         (suite-failed 0))
    ;; Count
    (dolist (spec specs)
      (let* ((spec-name (alist-get 'name spec))
             (key (format "%s::%s" name-str spec-name))
             (result (gethash key result-map)))
        (if (eq result 'passed)
            (cl-incf suite-passed)
          (cl-incf suite-failed))))
    (concat
     "<section class=\"suite\" id=\"" name-str "\">\n"
     "<div class=\"suite-header\">\n"
     "<h2>" (tibetan-bdd--html-escape name-str) "</h2>\n"
     "<p class=\"suite-desc\">" (tibetan-bdd--html-escape (or desc "")) "</p>\n"
     "<div class=\"suite-stats\">"
     "<span class=\"badge badge-passed\">" (number-to-string suite-passed) " passed</span>"
     (if (> suite-failed 0)
         (concat "<span class=\"badge badge-failed\">" (number-to-string suite-failed) " failed</span>")
       "")
     "</div>\n"
     "</div>\n"

     ;; Specs
     "<div class=\"specs\">\n"
     (mapconcat
      (lambda (spec) (tibetan-bdd--generate-spec-html spec name-str result-map))
      specs "\n")
     "</div>\n"
     "</section>\n")))

(defun tibetan-bdd--generate-spec-html (spec suite-name result-map)
  "Generate HTML for a single SPEC in SUITE-NAME using RESULT-MAP."
  (let* ((spec-name (alist-get 'name spec))
         (given (alist-get 'given spec))
         (when-form (alist-get 'when spec))
         (then-forms (alist-get 'then spec))
         (example (alist-get 'example spec))
         (tags (alist-get 'tags spec))
         (key (format "%s::%s" suite-name spec-name))
         (result (gethash key result-map))
         (status (if (eq result 'passed) "passed" "failed"))
         (status-icon (if (eq result 'passed) "&#10003;" "&#10007;")))
    (concat
     "<div class=\"spec spec-" status "\">\n"

     ;; Spec header
     "<div class=\"spec-header\" onclick=\"this.parentElement.classList.toggle('expanded')\">\n"
     "<span class=\"status-icon " status "\">" status-icon "</span>\n"
     "<span class=\"spec-name\">" (tibetan-bdd--html-escape spec-name) "</span>\n"
     ;; Tags
     (if tags
         (concat "<span class=\"tags\">"
                 (mapconcat
                  (lambda (tag)
                    (format "<span class=\"tag %s\">%s</span>"
                            (tibetan-bdd--tag-class tag)
                            (substring (symbol-name tag) 1)))
                  tags " ")
                 "</span>")
       "")
     "</div>\n"

     ;; Spec body (Given/When/Then)
     "<div class=\"spec-body\">\n"

     ;; Example source
     (if example
         (format "<div class=\"example-source\">Example: %s</div>\n"
                 (tibetan-bdd--html-escape example))
       "")

     ;; Given
     (if given
         (concat "<div class=\"clause\">"
                 "<span class=\"keyword\">Given</span> "
                 "<code>" (tibetan-bdd--format-sexp given) "</code>"
                 "</div>\n")
       "")

     ;; When
     (if when-form
         (concat "<div class=\"clause\">"
                 "<span class=\"keyword\">When</span> "
                 "<code>" (tibetan-bdd--format-sexp when-form) "</code>"
                 "</div>\n")
       "")

     ;; Then
     (mapconcat
      (lambda (assertion)
        (concat "<div class=\"clause\">"
                "<span class=\"keyword\">Then</span> "
                "<code>" (tibetan-bdd--format-sexp assertion) "</code>"
                "</div>\n"))
      (or then-forms '()) "")

     ;; Failure message
     (when (and (listp result) (eq (car result) 'failed))
       (format "<div class=\"failure-msg\">%s</div>\n"
               (tibetan-bdd--html-escape (or (cadr result) "Unknown error"))))

     "</div>\n"
     "</div>\n")))

;; ============================================================================
;; CSS
;; ============================================================================

(defun tibetan-bdd--generate-css ()
  "Generate embedded CSS for the living documentation."
  "<style>
:root {
  --bg: #fafafa; --surface: #ffffff; --text: #1a1a2e;
  --text-muted: #6b7280; --border: #e5e7eb;
  --primary: #4338ca; --primary-light: #e0e7ff;
  --passed: #059669; --passed-bg: #ecfdf5;
  --failed: #dc2626; --failed-bg: #fef2f2;
  --accent: #d97706; --accent-bg: #fffbeb;
  --keyword: #7c3aed;
  --tibetan-gold: #b8860b; --tibetan-deep: #1a0a2e;
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

/* Dashboard */
.dashboard {
  display: flex; gap: 16px; margin-bottom: 8px; flex-wrap: wrap;
  justify-content: center;
}
.stat-card {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 8px; padding: 16px 24px; text-align: center;
  min-width: 120px; flex: 1; max-width: 180px;
}
.stat-number { font-size: 2rem; font-weight: 700; color: var(--primary); }
.stat-label { font-size: 0.85rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; }
.stat-passed .stat-number { color: var(--passed); }
.stat-failed .stat-number { color: var(--failed); }

/* Progress bar */
.progress-container {
  background: var(--border); border-radius: 8px; height: 8px;
  margin-bottom: 32px; overflow: hidden;
}
.progress-bar {
  background: linear-gradient(90deg, var(--passed), #34d399);
  height: 100%; border-radius: 8px; transition: width 0.5s;
}

/* Table of contents */
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

/* Suites */
.suite {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 8px; margin-bottom: 24px; overflow: hidden;
}
.suite-header {
  padding: 20px 24px; border-bottom: 1px solid var(--border);
  background: linear-gradient(to right, var(--primary-light), var(--surface));
}
.suite-header h2 { font-size: 1.25rem; color: var(--tibetan-deep); }
.suite-desc { color: var(--text-muted); margin-top: 4px; }
.suite-stats { margin-top: 8px; display: flex; gap: 8px; }
.badge {
  font-size: 0.8rem; padding: 2px 10px; border-radius: 12px;
  font-weight: 500;
}
.badge-passed { background: var(--passed-bg); color: var(--passed); }
.badge-failed { background: var(--failed-bg); color: var(--failed); }

/* Specs */
.specs { padding: 8px 0; }
.spec {
  border-left: 4px solid var(--passed);
  margin: 8px 16px; border-radius: 4px;
  background: var(--passed-bg);
}
.spec-failed {
  border-left-color: var(--failed);
  background: var(--failed-bg);
}
.spec-header {
  padding: 10px 16px; cursor: pointer; display: flex;
  align-items: center; gap: 10px; flex-wrap: wrap;
}
.spec-header:hover { opacity: 0.85; }
.status-icon {
  font-size: 1rem; font-weight: 700; width: 22px; text-align: center;
}
.status-icon.passed { color: var(--passed); }
.status-icon.failed { color: var(--failed); }
.spec-name { font-weight: 500; flex: 1; }

/* Tags */
.tags { display: flex; gap: 4px; flex-wrap: wrap; }
.tag {
  font-size: 0.7rem; padding: 1px 8px; border-radius: 10px;
  background: var(--border); color: var(--text-muted); font-weight: 500;
}
.tag-critical { background: #fce4ec; color: #c62828; }
.tag-regression { background: #e8eaf6; color: #283593; }
.tag-tigress { background: var(--accent-bg); color: var(--accent); }

/* Spec body (collapsed by default) */
.spec-body {
  max-height: 0; overflow: hidden; transition: max-height 0.3s ease;
  padding: 0 16px;
}
.spec.expanded .spec-body {
  max-height: 600px; padding: 12px 16px 16px;
  border-top: 1px solid rgba(0,0,0,0.08);
}
.clause { margin-bottom: 6px; }
.keyword {
  font-weight: 700; color: var(--keyword); text-transform: uppercase;
  font-size: 0.8rem; letter-spacing: 0.5px;
}
.clause code {
  font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.85rem;
  color: var(--text); word-break: break-all;
}
.example-source {
  font-size: 0.85rem; color: var(--tibetan-gold);
  font-style: italic; margin-bottom: 8px;
}
.failure-msg {
  background: var(--failed-bg); border: 1px solid #fca5a5;
  border-radius: 4px; padding: 8px 12px; margin-top: 8px;
  font-family: monospace; font-size: 0.85rem; color: var(--failed);
  white-space: pre-wrap;
}

/* Footer */
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
(defun tibetan-bdd-generate-living-doc ()
  "Generate living documentation HTML report.
Runs all specs and produces a browsable HTML report."
  (interactive)
  (let* ((suites (tibetan-bdd--extract-all-suites))
         (run-data (tibetan-bdd--run-and-collect))
         (html (tibetan-bdd--generate-html suites run-data))
         (output-file (expand-file-name "docs/living-documentation.html"
                        (or (getenv "PROJECT_ROOT") default-directory))))
    (with-temp-file output-file
      (insert html))
    (message "Living documentation generated: %s" output-file)
    (princ (format "\nLiving documentation: %s\n" output-file))
    (princ (format "Suites: %d | Specs: %d | Passed: %d | Failed: %d\n"
                   (length suites)
                   (+ (plist-get run-data :passed) (plist-get run-data :failed))
                   (plist-get run-data :passed)
                   (plist-get run-data :failed)))))

(provide 'generate-living-doc)
;;; generate-living-doc.el ends here
