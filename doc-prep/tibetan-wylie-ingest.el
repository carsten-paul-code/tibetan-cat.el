;;; tibetan-wylie-ingest.el --- Wylie → Tibetan Unicode ingest -*- lexical-binding: t -*-

;;; Commentary:
;; §5.27 Phase 2 (2026-05-26):  Elisp wrapper around
;; `doc-prep/tibetan-ybh-prep.py' so the Wylie-input route of the
;; document-preparation wizard can shell out to the existing Python
;; converter from Emacs without dropping the user into a terminal.
;;
;; Two public commands:
;;
;;   `tibetan-wylie-ingest-validate-input' — quick structural scan of
;;   a Wylie `.org' source.  Reports paragraph count, estimated
;;   segment count (count of `//' delimiters), and flags suspicious
;;   characters (embedded Tibetan Unicode, non-ASCII glyphs) BEFORE
;;   the converter is invoked.  Lightweight — no dictionary check.
;;
;;   `tibetan-wylie-ingest-file' — interactive wrapper for the Python
;;   converter.  Validates `pyewts' is installed, calls the script
;;   via `call-process', and either writes the Tibetan-Unicode output
;;   in place (with `--in-place') or returns it as a string.
;;
;; Both commands are pure orchestration — the conversion logic stays
;; in the Python script (`tibetan-ybh-prep.py') which is the
;; canonical implementation.  See the wizard module (Phase 6) for
;; the user-facing integration.

;;; Code:

(require 'cl-lib)

;; Forward declaration:  the post-ingest relocation is delegated to
;; `tibetan-doc-prep.el' (defined alongside us under doc-prep/).  We
;; only call it under `fboundp', so a missing module degrades to "no
;; move" rather than erroring.
(declare-function tibetan-doc-prep-move-to-work-in-progress
                  "tibetan-doc-prep" (source-path))

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defgroup tibetan-wylie-ingest nil
  "Wylie → Tibetan Unicode ingest settings."
  :group 'tibetan-doc-prep
  :prefix "tibetan-wylie-ingest-")

(defcustom tibetan-wylie-ingest-python-executable "python3"
  "Python interpreter used to run the Wylie ingest script.
Must have the `pyewts' package importable.  The path is resolved
via `executable-find' at call time, so a virtualenv-relative
name is fine."
  :type 'string
  :group 'tibetan-wylie-ingest)

(defcustom tibetan-wylie-ingest-script-path
  (let ((dir (file-name-directory
              (or load-file-name buffer-file-name default-directory))))
    (expand-file-name "tibetan-ybh-prep.py" dir))
  "Absolute path to the bundled `tibetan-ybh-prep.py' converter.
Defaults to the script that ships alongside this Elisp module
under `doc-prep/'.  Override only when running from a non-standard
checkout."
  :type 'file
  :group 'tibetan-wylie-ingest)

;; ============================================================================
;; PRE-FLIGHT  ----------------------------------------------------------------
;; ============================================================================

(defun tibetan-wylie-ingest--python-available-p ()
  "Return non-nil when the configured Python interpreter is on PATH."
  (and tibetan-wylie-ingest-python-executable
       (executable-find tibetan-wylie-ingest-python-executable)
       t))

(defun tibetan-wylie-ingest--pyewts-available-p ()
  "Return non-nil when `pyewts' is importable in the configured Python.
Runs `python3 -c \"import pyewts\"' and inspects the exit code.
Caches nothing — caller should bind the result once per wizard
run if the cost is a concern."
  (and (tibetan-wylie-ingest--python-available-p)
       (zerop (call-process tibetan-wylie-ingest-python-executable
                            nil nil nil "-c" "import pyewts"))))

(defun tibetan-wylie-ingest--require-pyewts-or-error ()
  "Signal a `user-error' when the Python prerequisites are missing.
Used by `tibetan-wylie-ingest-file' as its single pre-flight gate
so users see a clear hint instead of a stack trace from the
shelled-out script."
  (unless (tibetan-wylie-ingest--python-available-p)
    (user-error
     "Python interpreter `%s' not found on PATH — set `tibetan-wylie-ingest-python-executable'"
     tibetan-wylie-ingest-python-executable))
  (unless (tibetan-wylie-ingest--pyewts-available-p)
    (user-error
     "Python module `pyewts' not importable in `%s' — install with:  pip3 install --user pyewts"
     tibetan-wylie-ingest-python-executable))
  (unless (file-exists-p tibetan-wylie-ingest-script-path)
    (user-error
     "Wylie ingest script not found at `%s' — set `tibetan-wylie-ingest-script-path'"
     tibetan-wylie-ingest-script-path)))

;; ============================================================================
;; VALIDATION  ----------------------------------------------------------------
;; ============================================================================

(defconst tibetan-wylie-ingest--tibetan-unicode-range
  (cons #x0F00 #x0FFF)
  "Inclusive codepoint range (U+0F00..U+0FFF) of the Tibetan block.
Used by the validator to flag bodies that already contain Tibetan
Unicode — typically a sign the user accidentally pasted a converted
file in place of the Wylie source.")

(defun tibetan-wylie-ingest--char-tibetan-unicode-p (ch)
  "Return non-nil when CH is in the Tibetan Unicode block."
  (and (<= (car tibetan-wylie-ingest--tibetan-unicode-range) ch)
       (<= ch (cdr tibetan-wylie-ingest--tibetan-unicode-range))))

(defun tibetan-wylie-ingest--extract-tibetan-text-body (path)
  "Return the body under the `* Tibetan Text' heading in PATH.
Returns nil when the heading is absent.  Mirrors the Python
script's `split_source' logic — body runs from the heading to the
next top-level heading (or EOF)."
  (when (and path (file-exists-p path))
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Text[ \t]*$" nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (save-excursion
                      (if (re-search-forward "^\\* " nil t)
                          (line-beginning-position)
                        (point-max)))))
          (buffer-substring-no-properties start end))))))

(defun tibetan-wylie-ingest--scan-body-for-issues (body)
  "Walk BODY one char at a time, returning a plist of findings.
Plist keys:
  :tibetan-unicode-count   — number of chars in U+0F00..U+0FFF
  :non-ascii-count         — number of non-ASCII, non-Tibetan chars
  :first-tibetan-unicode-pos  / :first-non-ascii-pos  — 1-based
                              char index into BODY of the FIRST
                              occurrence (for user-friendly error
                              snippets), or nil when absent."
  (let ((tib-count 0)
        (other-count 0)
        (first-tib nil)
        (first-other nil)
        (pos 0))
    (when body
      (mapc
       (lambda (ch)
         (cl-incf pos)
         (cond
          ((tibetan-wylie-ingest--char-tibetan-unicode-p ch)
           (cl-incf tib-count)
           (unless first-tib (setq first-tib pos)))
          ((> ch 127)
           (cl-incf other-count)
           (unless first-other (setq first-other pos)))))
       body))
    (list :tibetan-unicode-count tib-count
          :non-ascii-count       other-count
          :first-tibetan-unicode-pos first-tib
          :first-non-ascii-pos       first-other)))

(defun tibetan-wylie-ingest--count-paragraphs-and-units (body)
  "Return a plist `(:paragraph-count N :estimated-segment-count N)'.
Paragraphs are blank-line-separated non-empty blocks (same rule
the Python script uses).  Segment count = total `//' (double-shad)
occurrences across the body, mirroring `split_paragraph_into_
segments' — each `//' boundary becomes one segment.  Estimate
slightly understates when a paragraph's trailing text has no `//'
\(that residual becomes a final segment), so add 1 per paragraph."
  (let ((para-count 0)
        (segment-count 0))
    (when (and body (stringp body) (not (string-empty-p body)))
      (dolist (para (split-string body "\n[ \t]*\n" t))
        (let ((trimmed (string-trim para)))
          (unless (string-empty-p trimmed)
            (cl-incf para-count)
            ;; Normalise OCR shad variants before counting so `;;'
            ;; (single-byte shad-pair) and `//' are equivalent.
            (let* ((norm (replace-regexp-in-string ";;" "//" trimmed))
                   (units (split-string norm "//" t "[ \t\n]+")))
              (cl-incf segment-count (length units)))))))
    (list :paragraph-count para-count
          :estimated-segment-count segment-count)))

(defun tibetan-wylie-ingest--count-pipe-shads (body)
  "Return the count of `|' characters in BODY.  Used by the
validator to flag Wylie sources that use the pipe-shad
convention and would benefit from `--normalize-shads' before
ingest."
  (cl-count ?| body))

(defun tibetan-wylie-ingest--count-non-standard-folios (body)
  "Return the count of bracket-style folio markers in BODY that
are NOT already in the canonical `[F:D...]' form the Python
ingest script recognises.  Matches `[141a.6]' and `[141a6]'
variants."
  (let ((count 0)
        (idx 0))
    (while (string-match
            tibetan-wylie-ingest--folio-regex body idx)
      (cl-incf count)
      (setq idx (match-end 0)))
    count))

(defun tibetan-wylie-ingest-validate-input (path)
  "Scan the Wylie source at PATH for structural issues.
Returns a plist suitable for the wizard's pre-conversion report:

  :path                          absolute source path
  :has-tibetan-text-section      t  when `* Tibetan Text' is present
  :paragraph-count               number of blank-line paragraphs in body
  :estimated-segment-count       count of `//' (+ trailing) units in body
  :tibetan-unicode-count         0 for a clean Wylie source
  :non-ascii-count               0 for a clean Wylie source
  :first-tibetan-unicode-pos  / :first-non-ascii-pos  — see scanner
  :pipe-shad-count               count of `|' chars (suggests need for
                                 `--normalize-shads' before ingest)
  :non-standard-folio-count      count of `[NNNa.M]' markers that are
                                 NOT in the script's `[F:D...]' form
                                 (suggests `--normalize-folio-markers')

Signals a `user-error' when PATH does not exist or is unreadable.
Other-issue counts of zero indicate the file is structurally sound
for the converter;  any non-zero count is advisory — the user can
still proceed (the converter passes non-Wylie chars through to
pyewts which may emit replacement characters or simply skip them)."
  (unless (and path (file-exists-p path))
    (user-error "Wylie source file not found:  %s" path))
  (let* ((body (tibetan-wylie-ingest--extract-tibetan-text-body path))
         (has-section (not (null body)))
         (body-str (or body ""))
         (issues (tibetan-wylie-ingest--scan-body-for-issues body-str))
         (counts (tibetan-wylie-ingest--count-paragraphs-and-units
                  body-str))
         (pipe-count (tibetan-wylie-ingest--count-pipe-shads body-str))
         (folio-count
          (tibetan-wylie-ingest--count-non-standard-folios body-str)))
    (append (list :path path
                  :has-tibetan-text-section has-section)
            counts
            issues
            (list :pipe-shad-count pipe-count
                  :non-standard-folio-count folio-count))))

(defun tibetan-wylie-ingest--format-validation-report (report)
  "Render REPORT (the plist from `--validate-input') as a string."
  (let ((path (plist-get report :path)))
    (mapconcat
     #'identity
     (list
      (format "Wylie validation report for %s"
              (abbreviate-file-name path))
      (format "  * Tibetan Text section:  %s"
              (if (plist-get report :has-tibetan-text-section)
                  "present"
                "MISSING — converter will refuse to run"))
      (format "  paragraphs:              %d"
              (plist-get report :paragraph-count))
      (format "  estimated segments:      %d  (count of `//' units)"
              (plist-get report :estimated-segment-count))
      (format "  Tibetan Unicode chars:   %d%s"
              (plist-get report :tibetan-unicode-count)
              (if (zerop (plist-get report :tibetan-unicode-count))
                  ""
                "  ⚠  body may already be converted"))
      (format "  non-ASCII (non-Tibetan): %d%s"
              (plist-get report :non-ascii-count)
              (if (zerop (plist-get report :non-ascii-count))
                  ""
                "  ⚠  smart-quotes / em-dashes / etc."))
      (format "  pipe-shad characters:    %d%s"
              (plist-get report :pipe-shad-count)
              (if (zerop (plist-get report :pipe-shad-count))
                  ""
                "  ⚠  script expects `//' — run `--normalize-shads'"))
      (format "  non-standard folios:     %d%s"
              (plist-get report :non-standard-folio-count)
              (if (zerop (plist-get report :non-standard-folio-count))
                  ""
                "  ⚠  script expects `[F:D...]' — run `--normalize-folio-markers'")))
     "\n")))

;;;###autoload
(defun tibetan-wylie-ingest-validate-input-interactive (path)
  "Interactive wrapper around `tibetan-wylie-ingest-validate-input'.
Pops a `*Wylie Validate*' buffer with the report."
  (interactive
   (list (read-file-name "Wylie source: " nil nil t)))
  (let ((report (tibetan-wylie-ingest-validate-input path)))
    (with-output-to-temp-buffer "*Wylie Validate*"
      (princ (tibetan-wylie-ingest--format-validation-report report)))
    report))

;; ============================================================================
;; BODY-REGION HELPER  --------------------------------------------------------
;; ============================================================================

(defun tibetan-wylie-ingest--apply-to-body (path fn)
  "Read PATH, apply FN to its `* Tibetan Text' body, write back.

FN is a one-argument function taking the body string (everything
between the `* Tibetan Text' heading and the next top-level `* '
heading) and returning a modified string.  Metadata headers,
title, and any post-body sections are untouched.

No-op (returns nil) when PATH has no `* Tibetan Text' heading.
Returns t when the body was actually rewritten."
  (unless (and path (file-exists-p path))
    (user-error "File not found:  %s" path))
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (when (re-search-forward "^\\* Tibetan Text[ \t]*$" nil t)
      (forward-line 1)
      (let* ((start (point))
             (end (save-excursion
                    (if (re-search-forward "^\\* " nil t)
                        (line-beginning-position)
                      (point-max))))
             (body (buffer-substring-no-properties start end))
             (transformed (funcall fn body)))
        (unless (equal body transformed)
          (delete-region start end)
          (goto-char start)
          (insert transformed)
          (write-region (point-min) (point-max) path)
          t)))))

;; ============================================================================
;; SHAD NORMALISATION  --------------------------------------------------------
;; ============================================================================

(defun tibetan-wylie-ingest--normalize-shads-string (body &optional class-mode)
  "Return BODY with Wylie pipe-shads normalised.

CLASS-MODE controls how the standard-Wylie double-shad `| |' is
treated;  it directly drives segment granularity downstream:

  · `reading' (default) — `| |' → `/ /' (two single shads with a
                          space).  The Python script's segment
                          splitter (`text.split(\"//\")') doesn't
                          fire on `/ /', so the surrounding
                          paragraph stays as ONE segment.  Pyewts
                          still renders the two-shad sequence as
                          a Tibetan double-shad (`།  །') in the
                          output.  Right for reading-class flow
                          where one segment = one paragraph.

  · `grammar'           — `| |' → `//'.  The script splits at
                          every `//' boundary, so each `| |'-
                          delimited sentence becomes its own
                          segment.  Right for grammar-class
                          flow where one segment = one sentence.

Lone `|' (no adjacent partner) always maps to `/' in both modes —
within-segment shad, cosmetic at the pyewts level.

Pure-string operation;  used by `tibetan-wylie-ingest-normalize-
shads' on the body region and by the validator's counter."
  (let* ((mode (or class-mode 'reading))
         ;; Step 1: collapse `| {space(s)} |' to a canonical token so
         ;; downstream substitutions can hit it as one unit.
         (step1 (replace-regexp-in-string
                 "|[ \t]+|"
                 (if (eq mode 'grammar) "||" "PARA-DOUBLE-SHAD")
                 body))
         ;; Step 2: `||' (adjacent or merged from step 1) → `//'.
         ;; Only fires when we collapsed in step 1 (grammar mode).
         (step2 (replace-regexp-in-string "||" "//" step1 nil t))
         ;; Step 3: lone `|' → `/'.
         (step3 (replace-regexp-in-string "|" "/" step2 nil t))
         ;; Step 4: in reading mode, restore the placeholder to `/ /'
         ;; (two single shads separated by a space — pyewts renders
         ;; the standard Tibetan double-shad, but the script's
         ;; segment splitter ignores it).
         (step4 (if (eq mode 'grammar)
                    step3
                  (replace-regexp-in-string
                   "PARA-DOUBLE-SHAD" "/ /" step3 nil t))))
    step4))

(defun tibetan-wylie-ingest-normalize-shads (path &optional class-mode)
  "Normalise Wylie pipe-shads in PATH's `* Tibetan Text' body.

CLASS-MODE (`reading' default, or `grammar') controls how the
double-shad `| |' is rewritten — see
`tibetan-wylie-ingest--normalize-shads-string' for the details.

Returns the count of `|' characters that were converted.
Idempotent — re-running on a body that no longer contains `|'
returns 0."
  (let ((count 0))
    (tibetan-wylie-ingest--apply-to-body
     path
     (lambda (body)
       (setq count (cl-count ?| body))
       (tibetan-wylie-ingest--normalize-shads-string body class-mode)))
    count))

;; ============================================================================
;; FOLIO-MARKER NORMALISATION  ------------------------------------------------
;; ============================================================================

(defconst tibetan-wylie-ingest--folio-regex
  "\\[\\([0-9]+\\)\\([ab]\\)\\.?\\([0-9]+\\)\\]"
  "Match `[<digits><ab>.?<digits>]' — the common bracket-folio
convention in academic Tibetan transcriptions (e.g. `[141a.6]'
= folio 141a, line 6).  Pure-digit / pure-letter runs only, so
bibliographic ranges like `[141a.5–143b.4; pp. 285.5–290.4]'
\(which contain dashes / semicolons) do NOT match and are left
intact.")

(defun tibetan-wylie-ingest--normalize-folio-markers-string (body)
  "Return BODY with bracket-style folio markers reshaped to
`[F:D<digits><ab><digits>]' so the Python script's
`FOLIO_RE = r\"\\[F:D(\\d+[ab]\\d+)\\]\"' regex picks them up."
  (replace-regexp-in-string
   tibetan-wylie-ingest--folio-regex
   "[F:D\\1\\2\\3]"
   body))

(defun tibetan-wylie-ingest-normalize-folio-markers (path)
  "Reshape inline folio markers in PATH's `* Tibetan Text' body
from `[141a.6]' to `[F:D141a6]' so the Python script extracts
them as `:FOLIO:' org properties instead of leaving them
embedded in the Wylie body (where pyewts would garble them).

Returns the count of markers rewritten."
  (let ((count 0))
    (tibetan-wylie-ingest--apply-to-body
     path
     (lambda (body)
       (let ((c 0))
         (let ((idx 0))
           (while (string-match
                   tibetan-wylie-ingest--folio-regex body idx)
             (cl-incf c)
             (setq idx (match-end 0))))
         (setq count c))
       (tibetan-wylie-ingest--normalize-folio-markers-string body)))
    count))

;; ============================================================================
;; AUTO-WRAP — make a bare Wylie file ingestable
;; ============================================================================

(defun tibetan-wylie-ingest-wrap-bare-source (path)
  "Wrap PATH (a bare Wylie source) in the canonical org structure
required by `tibetan-ybh-prep.py'.

A `bare Wylie source' is a `.org' file that contains Wylie body
content but has no `* Tibetan Text' heading — typically the
result of pasting raw Wylie into a fresh file or downloading a
plain-text Wylie transcription.

Mutates the file in place:
  #+TITLE: <basename-without-extension>

  * Tibetan Text
  <existing content unchanged>

Returns PATH on success.  Idempotent — a file that ALREADY has
`* Tibetan Text' is left untouched and the function signals a
`user-error' so callers know to skip the wrap step."
  (unless (and path (file-exists-p path))
    (user-error "File not found:  %s" path))
  (let ((existing
         (with-temp-buffer
           (insert-file-contents path)
           (buffer-string))))
    (when (string-match-p "^\\* Tibetan Text[ \t]*$" existing)
      (user-error
       "File already has `* Tibetan Text' heading — wrap not needed:  %s"
       path))
    (let* ((title (file-name-base path))
           (already-has-title-p
            (string-match-p "^#\\+TITLE:" existing))
           (header (concat (unless already-has-title-p
                             (format "#+TITLE: %s\n\n" title))
                           "* Tibetan Text\n")))
      (with-temp-file path
        (insert header)
        (insert existing))))
  path)

;; ============================================================================
;; INGEST  --------------------------------------------------------------------
;; ============================================================================

(defun tibetan-wylie-ingest--build-argv (path in-place)
  "Return the argv list for the Python converter.
PATH is the source `.org' file (absolute), IN-PLACE non-nil
threads the `--in-place' flag."
  (let ((args (list tibetan-wylie-ingest-script-path
                    (expand-file-name path))))
    (when in-place
      (setq args (append args (list "--in-place"))))
    args))

(defun tibetan-wylie-ingest--invoke-script (path in-place)
  "Run the converter on PATH.  Return a plist with :exit-code,
:stdout, :stderr.  Stubbed by tests via `cl-letf' on
`call-process'."
  (let* ((argv (tibetan-wylie-ingest--build-argv path in-place))
         (stderr-file (make-temp-file "tibetan-wylie-stderr-")))
    (unwind-protect
        (with-temp-buffer
          (let ((exit
                 (apply #'call-process
                        tibetan-wylie-ingest-python-executable
                        nil
                        (list (current-buffer) stderr-file)
                        nil
                        argv)))
            (list :exit-code exit
                  :stdout (buffer-string)
                  :stderr (with-temp-buffer
                            (when (file-exists-p stderr-file)
                              (insert-file-contents stderr-file))
                            (buffer-string)))))
      (when (file-exists-p stderr-file) (delete-file stderr-file)))))

;;;###autoload
(defun tibetan-wylie-ingest-file (path &optional in-place skip-move)
  "Convert PATH from Wylie to Tibetan Unicode via the bundled script.

PATH is a source `.org' file carrying Wylie under `* Tibetan
Text'.  When IN-PLACE is non-nil the file is overwritten with the
converted content;  otherwise the converter's stdout is returned
as a string.

After a successful IN-PLACE conversion, the prepared file is
relocated into the configured work-in-progress folder via
`tibetan-doc-prep-move-to-work-in-progress' (sibling of the
source's parent dir, default name `work in progress').  Passing
SKIP-MOVE non-nil disables the relocation — useful from tests or
when the caller orchestrates the move itself.

Signals a `user-error' when `python3' or `pyewts' aren't
available, or when the script exits non-zero (stderr is included
in the error message for diagnosis).

Return value:
  IN-PLACE  → absolute path of the prepared file (post-move).
  stdout    → converter's stdout body as a string.

Interactive callers receive a prefix-arg → IN-PLACE."
  (interactive
   (list (read-file-name "Wylie source: " nil nil t)
         current-prefix-arg))
  (tibetan-wylie-ingest--require-pyewts-or-error)
  (unless (and path (file-exists-p path))
    (user-error "Wylie source file not found:  %s" path))
  (let* ((result (tibetan-wylie-ingest--invoke-script path in-place))
         (code   (plist-get result :exit-code))
         (stdout (plist-get result :stdout))
         (stderr (plist-get result :stderr)))
    (unless (zerop code)
      (user-error
       "Wylie ingest script exited %s%s"
       code
       (if (and stderr (not (string-empty-p stderr)))
           (concat ":\n" (string-trim stderr))
         "")))
    (cond
     (in-place
      (let ((final-path
             (if (and (not skip-move)
                      (fboundp 'tibetan-doc-prep-move-to-work-in-progress))
                 (tibetan-doc-prep-move-to-work-in-progress path)
               (expand-file-name path))))
        (when (called-interactively-p 'interactive)
          (message "Wylie ingest:  wrote %s  (%s)"
                   (abbreviate-file-name final-path)
                   (string-trim (or stderr ""))))
        final-path))
     (t
      (when (called-interactively-p 'interactive)
        (message "Wylie ingest:  captured to stdout  (%s)"
                 (string-trim (or stderr ""))))
      stdout))))

(provide 'tibetan-wylie-ingest)
;;; tibetan-wylie-ingest.el ends here
