;;; generate-func-overview.el --- Generate function overview with test mapping -*- lexical-binding: t -*-

;;; Commentary:
;; Generates an HTML function overview that maps all public functions to their
;; tests.  Extracts function metadata (name, docstring, module, interactive
;; status, parameters) from source files and maps tests in two passes:
;;
;;   1. Longest-prefix name match (fast, strict).  A test named
;;      `tibetan-steinert-sanskrit-for-bodhisattva' maps to the
;;      function `tibetan-steinert-sanskrit-for' (the longest function
;;      name that is a word-prefix of the test name).
;;
;;   2. Body reference scan (fallback).  For every public function
;;      that picked up zero tests in pass 1, search the source of each
;;      test file for a `\\_<function-name\\_>' token.  Tests that
;;      reference the function get attributed to it with a
;;      `(referenced)' hint so the coverage count reflects real usage
;;      even when the naming conventions diverge — e.g. the
;;      `tibetan-text-classifier-test' suite uses names like
;;      `tibetan-classifier-*' rather than the `tibetan-text-*' prefix
;;      shared by the functions.
;;
;; Usage:
;;   emacs --batch -L . -L core -L analysis -L persist -L workspace \
;;     -L philology -L config -L data -L doc-prep -L setup -L spec -L test \
;;     -l tibetan-cat.el -l test/run-all-tests.el \
;;     -l test/generate-func-overview.el \
;;     -f tibetan-func-overview-generate

;;; Code:

(require 'cl-lib)
(require 'ert)

;; ============================================================================
;; SOURCE FILE PARSING — extract function metadata
;; ============================================================================

(defvar tibetan-func-overview--source-dirs
  '("core" "analysis" "persist" "philology" "config" "data" "doc-prep" "setup")
  "Subdirectories containing source files.")

(defun tibetan-func-overview--parse-source-file (filepath)
  "Parse FILEPATH to extract all defun metadata.
Returns list of alists, each with keys: name, docstring, params, interactive,
file, module, private."
  (let ((filename (file-name-nondirectory filepath))
        (module (replace-regexp-in-string
                 "\\.el$" ""
                 (replace-regexp-in-string "^tibetan-" ""
                   (file-name-nondirectory filepath))))
        (functions '()))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (while (re-search-forward
              "^(defun \\([^ ]+\\) (\\([^)]*\\))" nil t)
        (let* ((name (match-string 1))
               (params (match-string 2))
               (private (string-match-p "--" name))
               (docstring nil)
               (interactive nil))
          ;; Extract docstring
          (save-excursion
            (forward-line 1)
            (when (looking-at "^  \"\\(.*\\)")
              (setq docstring (match-string 1))
              ;; Handle multi-line docstrings — get first line
              (when (string-match "\\\\n" docstring)
                (setq docstring (substring docstring 0 (match-beginning 0))))))
          ;; Check for interactive
          (save-excursion
            (let ((start (point))
                  (end (save-excursion
                         (goto-char (match-beginning 0))
                         (forward-sexp 1) (point))))
              (when (re-search-forward "(interactive" end t)
                (setq interactive t))))
          (push `((name . ,name)
                  (docstring . ,(or docstring ""))
                  (params . ,params)
                  (interactive . ,interactive)
                  (file . ,filename)
                  (module . ,module)
                  (private . ,private))
                functions))))
    (nreverse functions)))

(defun tibetan-func-overview--collect-all-functions (project-root)
  "Collect all function definitions from source directories under PROJECT-ROOT.
Returns list of function alists."
  (let ((all-funcs '()))
    ;; Root tibetan-cat.el
    (let ((root-file (expand-file-name "tibetan-cat.el" project-root)))
      (when (file-exists-p root-file)
        (setq all-funcs (append all-funcs
                                (tibetan-func-overview--parse-source-file root-file)))))
    ;; Module directories
    (dolist (dir tibetan-func-overview--source-dirs)
      (let ((full-dir (expand-file-name dir project-root)))
        (when (file-directory-p full-dir)
          (dolist (file (directory-files full-dir t "\\.el$"))
            (unless (string-match-p "-test\\.el$" file)
              (setq all-funcs
                    (append all-funcs
                            (tibetan-func-overview--parse-source-file file))))))))
    all-funcs))

;; ============================================================================
;; TEST MAPPING — two passes: longest-prefix match, then body reference scan
;; ============================================================================

(defun tibetan-func-overview--collect-test-sources (project-root)
  "Read every `test/*-test.el' file and return a list of (file . source)."
  (let ((test-dir (expand-file-name "test" project-root))
        (sources '()))
    (when (file-directory-p test-dir)
      (dolist (file (directory-files test-dir t "-test\\.el$"))
        (ignore-errors
          (with-temp-buffer
            (insert-file-contents file)
            (push (cons (file-name-nondirectory file)
                        (buffer-substring-no-properties (point-min) (point-max)))
                  sources)))))
    sources))

(defun tibetan-func-overview--parse-test-defs (source)
  "Return a list of (test-name . body-substring) from a test-file SOURCE.
BODY-SUBSTRING is everything between `(ert-deftest NAME ())' and the
matching closing paren; used for function-reference scanning."
  (let ((defs '())
        (start 0))
    (while (string-match
            "(ert-deftest[ \t\n]+\\([a-zA-Z0-9/_:?!*+=<>-]+\\)[ \t\n]+()"
            source start)
      (let* ((name (match-string 1 source))
             (body-start (match-end 0))
             (depth 1)
             (i body-start))
        ;; Walk forward tracking paren depth until we close the deftest.
        (while (and (< i (length source)) (> depth 0))
          (let ((c (aref source i)))
            (cond
             ((= c ?\() (setq depth (1+ depth)))
             ((= c ?\)) (setq depth (1- depth)))
             ;; Skip string literals
             ((= c ?\")
              (setq i (1+ i))
              (while (and (< i (length source))
                          (/= (aref source i) ?\")
                          ;; skip escaped quotes
                          (or (> (- i body-start) 0)
                              (/= (aref source (1- i)) ?\\)))
                (if (= (aref source i) ?\\) (setq i (+ i 2))
                  (setq i (1+ i))))))
            (setq i (1+ i))))
        (push (cons name (substring source body-start (max body-start (1- i))))
              defs)
        (setq start i)))
    (nreverse defs)))

(defun tibetan-func-overview--body-references-p (body func-name)
  "Return non-nil if BODY contains a symbol-boundary reference to FUNC-NAME."
  (let ((case-fold-search nil)
        (re (concat "\\_<" (regexp-quote func-name) "\\_>")))
    (string-match-p re body)))

(defun tibetan-func-overview--build-test-map (all-funcs result-map
                                                         &optional project-root)
  "Map tests to functions.
ALL-FUNCS is the list of function alists.
RESULT-MAP is the ERT result hash table (test-name -> status).
PROJECT-ROOT, if non-nil, enables the fallback body-reference pass.
Returns hash table: function-name -> list of (test-name . status) cons,
or (test-name . (referenced . status)) when the mapping was inferred
from the body scan rather than the name prefix."
  (let ((func-test-map (make-hash-table :test 'equal))
        (sorted-names (sort (mapcar (lambda (f) (alist-get 'name f)) all-funcs)
                            (lambda (a b) (> (length a) (length b)))))
        (unmatched '()))
    ;; ------------------------------------------------------------------
    ;; Pass 1: longest-prefix name match.
    ;; ------------------------------------------------------------------
    (maphash
     (lambda (test-name status)
       (let ((matched nil))
         (cl-dolist (func-name sorted-names)
           (when (and (string-prefix-p func-name test-name)
                      (or (= (length func-name) (length test-name))
                          (= (aref test-name (length func-name)) ?-)))
             (let ((existing (gethash func-name func-test-map)))
               (puthash func-name
                        (append existing (list (cons test-name status)))
                        func-test-map))
             (setq matched t)
             (cl-return)))
         (unless matched
           (push (cons test-name status) unmatched))))
     result-map)
    ;; ------------------------------------------------------------------
    ;; Pass 2: body-reference scan for functions with zero hits so far.
    ;; Only runs when PROJECT-ROOT is provided and the unmatched test
    ;; source can be read.
    ;; ------------------------------------------------------------------
    (when (and project-root unmatched)
      (let* ((test-sources
              (tibetan-func-overview--collect-test-sources project-root))
             (all-defs
              (mapcan (lambda (src)
                        (tibetan-func-overview--parse-test-defs (cdr src)))
                      test-sources))
             ;; Map test-name -> body for O(1) lookup.
             (body-index (make-hash-table :test 'equal)))
        (dolist (def all-defs)
          (puthash (car def) (cdr def) body-index))
        (dolist (func all-funcs)
          (let ((name (alist-get 'name func)))
            (unless (gethash name func-test-map)
              ;; This function has no prefix-matched tests.  Look for
              ;; any unmatched test whose body mentions the function.
              (let ((hits '()))
                (dolist (pair unmatched)
                  (let* ((test-name (car pair))
                         (status (cdr pair))
                         (body (gethash test-name body-index)))
                    (when (and body
                               (tibetan-func-overview--body-references-p
                                body name))
                      (push (cons test-name
                                  (cons 'referenced status))
                            hits))))
                (when hits
                  (puthash name (nreverse hits) func-test-map))))))))
    (when unmatched
      (puthash "__unmatched__" unmatched func-test-map))
    func-test-map))

;; ============================================================================
;; HTML GENERATION — standalone function overview
;; ============================================================================

(defun tibetan-func-overview--html-escape (str)
  "Escape HTML special characters in STR."
  (if (not (stringp str)) ""
    (let ((s str))
      (setq s (replace-regexp-in-string "&" "&amp;" s))
      (setq s (replace-regexp-in-string "<" "&lt;" s))
      (setq s (replace-regexp-in-string ">" "&gt;" s))
      (setq s (replace-regexp-in-string "\"" "&quot;" s))
      s)))

(defun tibetan-func-overview--unwrap-status (status)
  "Return the underlying ERT status from STATUS.
Pass-2 references are wrapped as `(referenced . real-status)' — this
helper unwraps them so the status icon rendering stays uniform."
  (if (and (consp status) (eq (car status) 'referenced))
      (cdr status)
    status))

(defun tibetan-func-overview--status-icon (status)
  "Return HTML icon for test STATUS.
When STATUS is the wrapped `(referenced . real)' form emitted by the
body-reference pass, a small ↗ badge is appended so the reader can
tell the mapping was inferred rather than prefix-matched."
  (let* ((referenced (and (consp status) (eq (car status) 'referenced)))
         (real (tibetan-func-overview--unwrap-status status))
         (icon (cond
                ((eq real 'passed) "<span class=\"st st-pass\">&#10003;</span>")
                ((eq real 'skipped) "<span class=\"st st-skip\">&#9711;</span>")
                ((and (consp real) (eq (car real) 'failed))
                 "<span class=\"st st-fail\">&#10007;</span>")
                (t "<span class=\"st st-skip\">?</span>"))))
    (if referenced
        (concat icon " <span class=\"st st-ref\" title=\"matched by body reference, not name prefix\">&#8599;</span>")
      icon)))

(defun tibetan-func-overview--generate-html (all-funcs func-test-map)
  "Generate standalone HTML function overview.
ALL-FUNCS is list of function alists, FUNC-TEST-MAP maps func -> tests."
  (let* ((public-funcs (cl-remove-if (lambda (f) (alist-get 'private f)) all-funcs))
         ;; Group by module
         (module-map (make-hash-table :test 'equal))
         (total-funcs 0)
         (tested-funcs 0)
         (total-tests 0)
         (timestamp (format-time-string "%Y-%m-%d %H:%M:%S")))
    ;; Group functions by module
    (dolist (func public-funcs)
      (let ((mod (alist-get 'module func)))
        (puthash mod (append (gethash mod module-map) (list func)) module-map)))
    ;; Count stats
    (dolist (func public-funcs)
      (cl-incf total-funcs)
      (let ((tests (gethash (alist-get 'name func) func-test-map)))
        (when tests
          (cl-incf tested-funcs)
          (cl-incf total-tests (length tests)))))

    (concat
     "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
     "<meta charset=\"UTF-8\">\n"
     "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
     "<title>Tibetan CAT Tool — Function Overview</title>\n"
     (tibetan-func-overview--generate-css)
     "</head>\n<body>\n"

     ;; Header
     "<header>\n"
     "<div class=\"header-content\">\n"
     "<h1>ༀ Tibetan CAT Tool</h1>\n"
     "<p class=\"subtitle\">Function Overview — Test Coverage Map</p>\n"
     "<p class=\"meta\">Generated: " timestamp "</p>\n"
     "</div>\n</header>\n"

     ;; Dashboard
     "<div class=\"dashboard\">\n"
     (tibetan-func-overview--stat-card
      (number-to-string (hash-table-count module-map)) "Modules" "")
     (tibetan-func-overview--stat-card
      (number-to-string total-funcs) "Public Functions" "")
     (tibetan-func-overview--stat-card
      (number-to-string tested-funcs) "Tested" " stat-passed")
     (tibetan-func-overview--stat-card
      (number-to-string (- total-funcs tested-funcs)) "Untested" " stat-untested")
     (tibetan-func-overview--stat-card
      (number-to-string total-tests) "Tests" "")
     (tibetan-func-overview--stat-card
      (format "%.0f%%" (* 100.0 (/ (float tested-funcs) (max 1 total-funcs))))
      "Coverage" "")
     "</div>\n"

     ;; Coverage bar
     "<div class=\"progress-container\">\n"
     "<div class=\"progress-bar\" style=\"width: "
     (format "%.1f" (* 100.0 (/ (float tested-funcs) (max 1 total-funcs))))
     "%\"></div>\n</div>\n"

     ;; TOC
     "<nav class=\"toc\">\n<h2>Modules</h2>\n<ul>\n"
     (let ((sorted-modules (sort (hash-table-keys module-map) #'string<)))
       (mapconcat
        (lambda (mod)
          (let* ((funcs (gethash mod module-map))
                 (tested (cl-count-if
                          (lambda (f) (gethash (alist-get 'name f) func-test-map))
                          funcs)))
            (format "<li><a href=\"#mod-%s\">%s</a> <span class=\"toc-count\">%d/%d tested</span></li>\n"
                    mod (tibetan-func-overview--html-escape mod) tested (length funcs))))
        sorted-modules ""))
     "</ul>\n</nav>\n"

     ;; Module sections
     "<main>\n"
     (let ((sorted-modules (sort (hash-table-keys module-map) #'string<)))
       (mapconcat
        (lambda (mod)
          (tibetan-func-overview--generate-module-section
           mod (gethash mod module-map) func-test-map))
        sorted-modules "\n"))
     "</main>\n"

     ;; Unmatched tests section
     (let ((unmatched (gethash "__unmatched__" func-test-map)))
       (if unmatched
           (concat
            "<section class=\"module\" id=\"mod-unmatched\">\n"
            "<div class=\"module-header\">\n"
            "<h2>Unmatched Tests</h2>\n"
            "<p class=\"module-desc\">"
            (number-to-string (length unmatched))
            " tests that could not be mapped to a specific function</p>\n"
            "</div>\n<div class=\"func-list\">\n"
            (mapconcat
             (lambda (t-pair)
               (format "<div class=\"test-item\">%s %s</div>\n"
                       (tibetan-func-overview--status-icon (cdr t-pair))
                       (tibetan-func-overview--html-escape
                        (replace-regexp-in-string "^tibetan-" "" (car t-pair)))))
             unmatched "")
            "</div>\n</section>\n")
         ""))

     ;; Footer
     "<footer>\n"
     "<p>Tibetan CAT Tool v2.1.0 — Function Overview &amp; Test Coverage</p>\n"
     "</footer>\n"
     "</body>\n</html>\n")))

(defun tibetan-func-overview--stat-card (number label extra-class)
  "Generate stat card with NUMBER, LABEL, EXTRA-CLASS."
  (format "<div class=\"stat-card%s\"><div class=\"stat-number\">%s</div><div class=\"stat-label\">%s</div></div>\n"
          extra-class number label))

(defun tibetan-func-overview--generate-module-section (module funcs func-test-map)
  "Generate HTML for MODULE with FUNCS list and FUNC-TEST-MAP."
  (let* ((tested (cl-count-if
                  (lambda (f) (gethash (alist-get 'name f) func-test-map))
                  funcs))
         (interactive-count (cl-count-if
                             (lambda (f) (alist-get 'interactive f))
                             funcs))
         ;; Sort: interactive first, then alphabetically
         (sorted-funcs (sort (copy-sequence funcs)
                             (lambda (a b)
                               (let ((ia (alist-get 'interactive a))
                                     (ib (alist-get 'interactive b)))
                                 (if (eq ia ib)
                                     (string< (alist-get 'name a)
                                              (alist-get 'name b))
                                   ia))))))
    (concat
     "<section class=\"module\" id=\"mod-" module "\">\n"
     "<div class=\"module-header\">\n"
     "<h2>" (tibetan-func-overview--html-escape module) "</h2>\n"
     "<div class=\"module-stats\">"
     (format "<span class=\"badge badge-total\">%d functions</span>" (length funcs))
     (format "<span class=\"badge badge-tested\">%d tested</span>" tested)
     (if (> interactive-count 0)
         (format "<span class=\"badge badge-interactive\">%d interactive</span>"
                 interactive-count)
       "")
     "</div>\n</div>\n"

     ;; Function cards
     "<div class=\"func-list\">\n"
     (mapconcat
      (lambda (func)
        (tibetan-func-overview--generate-func-card func func-test-map))
      sorted-funcs "\n")
     "</div>\n</section>\n")))

(defun tibetan-func-overview--generate-func-card (func func-test-map)
  "Generate HTML card for FUNC with its tests from FUNC-TEST-MAP."
  (let* ((name (alist-get 'name func))
         (docstring (alist-get 'docstring func))
         (params (alist-get 'params func))
         (interactive (alist-get 'interactive func))
         (file (alist-get 'file func))
         (tests (gethash name func-test-map))
         (test-count (length tests))
         (pass-count (cl-count-if (lambda (tp) (eq (cdr tp) 'passed)) tests))
         (has-tests (> test-count 0))
         (coverage-class (cond
                          ((not has-tests) "untested")
                          ((= pass-count test-count) "fully-tested")
                          (t "partially-tested"))))
    (concat
     "<div class=\"func-card " coverage-class "\">\n"
     "<div class=\"func-header\" onclick=\"this.parentElement.classList.toggle('expanded')\">\n"

     ;; Coverage indicator
     "<span class=\"coverage-dot " coverage-class "\"></span>\n"

     ;; Function signature
     "<div class=\"func-sig\">\n"
     "<span class=\"func-name\">"
     (tibetan-func-overview--html-escape
      (replace-regexp-in-string "^tibetan-" "" name))
     "</span>"
     (if interactive " <span class=\"interactive-badge\">interactive</span>" "")
     (when (and params (not (string-empty-p params)))
       (format " <span class=\"func-params\">(%s)</span>"
               (tibetan-func-overview--html-escape params)))
     ;; Inline docstring (visible without expanding)
     (if (and docstring (not (string-empty-p docstring)))
         (format "\n<span class=\"func-desc\">%s</span>"
                 (tibetan-func-overview--html-escape docstring))
       "")
     "\n</div>\n"

     ;; Test count badge
     (if has-tests
         (format "<span class=\"test-count-badge\">%d test%s</span>"
                 test-count (if (= test-count 1) "" "s"))
       "<span class=\"test-count-badge no-tests\">untested</span>")
     "\n</div>\n"

     ;; Expandable body
     "<div class=\"func-body\">\n"
     ;; Docstring
     (if (and docstring (not (string-empty-p docstring)))
         (format "<div class=\"func-doc\">%s</div>\n"
                 (tibetan-func-overview--html-escape docstring))
       "")
     ;; Source file
     (format "<div class=\"func-source\">Source: %s</div>\n"
             (tibetan-func-overview--html-escape file))
     ;; Tests
     (if has-tests
         (concat
          "<div class=\"func-tests\">\n"
          "<div class=\"tests-header\">Tests:</div>\n"
          (mapconcat
           (lambda (t-pair)
             (format "<div class=\"test-item\">%s %s</div>\n"
                     (tibetan-func-overview--status-icon (cdr t-pair))
                     (tibetan-func-overview--html-escape
                      (replace-regexp-in-string "^tibetan-" "" (car t-pair)))))
           tests "")
          "</div>\n")
       "<div class=\"no-tests-msg\">No tests found for this function.</div>\n")
     "</div>\n</div>\n")))

;; ============================================================================
;; CSS
;; ============================================================================

(defun tibetan-func-overview--generate-css ()
  "Generate CSS for function overview."
  "<style>
:root {
  --bg: #fafafa; --surface: #ffffff; --text: #1a1a2e;
  --text-muted: #6b7280; --border: #e5e7eb;
  --primary: #1e40af; --primary-light: #dbeafe;
  --passed: #059669; --passed-bg: #ecfdf5;
  --failed: #dc2626; --failed-bg: #fef2f2;
  --skipped: #d97706; --skipped-bg: #fffbeb;
  --untested: #9ca3af; --untested-bg: #f3f4f6;
  --tibetan-deep: #0f172a;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: var(--bg); color: var(--text); line-height: 1.6;
  max-width: 1100px; margin: 0 auto; padding: 0 24px 48px;
}
header {
  background: linear-gradient(135deg, var(--tibetan-deep), #4338ca);
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
.stat-untested .stat-number { color: var(--untested); }

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

.module {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 8px; margin-bottom: 24px; overflow: hidden;
}
.module-header {
  padding: 20px 24px; border-bottom: 1px solid var(--border);
  background: linear-gradient(to right, var(--primary-light), var(--surface));
}
.module-header h2 { font-size: 1.25rem; color: var(--tibetan-deep); }
.module-stats { margin-top: 8px; display: flex; gap: 8px; }
.module-desc { color: var(--text-muted); margin-top: 4px; }
.badge {
  font-size: 0.8rem; padding: 2px 10px; border-radius: 12px; font-weight: 500;
}
.badge-total { background: var(--primary-light); color: var(--primary); }
.badge-tested { background: var(--passed-bg); color: var(--passed); }
.badge-interactive { background: #ede9fe; color: #7c3aed; }

.func-list { padding: 8px 16px; }

.func-card {
  border-left: 4px solid var(--passed); margin: 6px 0;
  border-radius: 4px; background: var(--passed-bg);
}
.func-card.untested {
  border-left-color: var(--untested); background: var(--untested-bg);
}
.func-card.partially-tested {
  border-left-color: var(--skipped); background: var(--skipped-bg);
}
.func-header {
  padding: 8px 14px; cursor: pointer; display: flex;
  align-items: center; gap: 8px; flex-wrap: wrap;
}
.func-header:hover { opacity: 0.85; }

.coverage-dot {
  width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0;
}
.coverage-dot.fully-tested { background: var(--passed); }
.coverage-dot.untested { background: var(--untested); }
.coverage-dot.partially-tested { background: var(--skipped); }

.func-sig { flex: 1; }
.func-name { font-weight: 600; font-size: 0.95rem; font-family: monospace; }
.func-params { color: var(--text-muted); font-size: 0.85rem; font-family: monospace; }
.func-desc {
  display: block; font-size: 0.82rem; color: var(--text-muted);
  font-style: italic; margin-top: 2px; font-family: sans-serif;
}
.interactive-badge {
  font-size: 0.7rem; background: #ede9fe; color: #7c3aed;
  padding: 1px 6px; border-radius: 8px; vertical-align: middle;
}
.test-count-badge {
  font-size: 0.75rem; color: var(--text-muted);
  background: var(--border); padding: 1px 8px; border-radius: 10px;
}
.test-count-badge.no-tests {
  background: var(--untested-bg); color: var(--untested);
}

.func-body {
  max-height: 0; overflow: hidden; transition: max-height 0.4s ease;
  padding: 0 14px;
}
.func-card.expanded .func-body {
  max-height: 600px; padding: 10px 14px 14px;
  border-top: 1px solid rgba(0,0,0,0.08);
}
.func-doc { font-style: italic; color: var(--text-muted); margin-bottom: 6px; }
.func-source { font-size: 0.8rem; color: var(--text-muted); font-family: monospace; margin-bottom: 8px; }

.func-tests { margin-top: 4px; }
.tests-header { font-size: 0.85rem; font-weight: 600; margin-bottom: 4px; }
.test-item { font-size: 0.9rem; padding: 2px 0; font-family: monospace; }
.st { font-weight: 700; margin-right: 4px; }
.st-pass { color: var(--passed); }
.st-fail { color: var(--failed); }
.st-skip { color: var(--skipped); }
.st-ref  { color: var(--untested); font-size: 0.85em; }
.no-tests-msg { font-style: italic; color: var(--untested); font-size: 0.9rem; }

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
(defun tibetan-func-overview-generate ()
  "Generate function overview with test coverage mapping.
Produces a standalone HTML report at docs/function-overview.html."
  (interactive)
  (let* ((project-root (or (getenv "PROJECT_ROOT") default-directory)))

    ;; Collect all functions
    (princ "Collecting function definitions...\n")
    (let ((all-funcs (tibetan-func-overview--collect-all-functions project-root)))
      (princ (format "Found %d functions (%d public)\n"
                     (length all-funcs)
                     (cl-count-if-not (lambda (f) (alist-get 'private f)) all-funcs)))

      ;; Run tests
      (princ "Running all ERT tests...\n")
      (let* ((result-map (tibetan-func-overview--run-all-tests))
             (func-test-map (tibetan-func-overview--build-test-map
                             all-funcs result-map project-root))
             (html (tibetan-func-overview--generate-html all-funcs func-test-map))
             (output-file (expand-file-name "docs/function-overview.html" project-root)))

        (with-temp-file output-file
          (insert html))

        ;; Summary
        (let ((public-count (cl-count-if-not (lambda (f) (alist-get 'private f)) all-funcs))
              (tested-count 0))
          (dolist (func all-funcs)
            (unless (alist-get 'private func)
              (when (gethash (alist-get 'name func) func-test-map)
                (cl-incf tested-count))))
          (princ (format "\nFunction overview: %s\n" output-file))
          (princ (format "Functions: %d | Tested: %d | Coverage: %.0f%%\n"
                         public-count tested-count
                         (* 100.0 (/ (float tested-count) (max 1 public-count))))))))))

;; Re-use the test runner from generate-test-doc if available, otherwise define our own
(defun tibetan-func-overview--run-all-tests ()
  "Run all ERT tests, return hash table of name -> status."
  (if (fboundp 'tibetan-ert-doc--run-all-tests)
      (tibetan-ert-doc--run-all-tests)
    ;; Fallback implementation
    (let ((result-map (make-hash-table :test 'equal)))
      (mapatoms
       (lambda (sym)
         (when (ert-test-boundp sym)
           (let* ((test-name (symbol-name sym))
                  (test-obj (ert-get-test sym)))
             (condition-case err
                 (ert-run-test test-obj)
               (error nil))
             (let ((result (ert-test-most-recent-result test-obj)))
               (cond
                ((null result)
                 (puthash test-name (cons 'failed "No result") result-map))
                ((ert-test-passed-p result)
                 (puthash test-name 'passed result-map))
                ((or (ert-test-result-type-p result :skipped)
                     (and (fboundp 'ert-test-skipped-p)
                          (ert-test-skipped-p result)))
                 (puthash test-name 'skipped result-map))
                (t
                 (puthash test-name (cons 'failed "") result-map))))))))
      result-map)))

(provide 'generate-func-overview)
;;; generate-func-overview.el ends here
