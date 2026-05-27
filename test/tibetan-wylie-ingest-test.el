;;; tibetan-wylie-ingest-test.el --- §5.27 Phase 2 — Wylie ingest wrapper -*- lexical-binding: t -*-

;;; Commentary:
;; ERT specs for `doc-prep/tibetan-wylie-ingest.el' — the Elisp
;; shim around `tibetan-ybh-prep.py'.
;;
;; Validator tests run pure-Emacs (no Python required).
;; Wrapper tests stub `call-process' via `cl-letf' so the suite
;; stays fast and runs without a working `pyewts' install.
;; A single end-to-end spec exercises the real Python script and
;; is guarded with `skip-unless' so the suite passes on a fresh
;; checkout without pyewts.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load path so we can require the module.
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../doc-prep" dir)))

(require 'tibetan-wylie-ingest)

;; ============================================================================
;; CONFIG / DEFAULTS
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-script-path-points-at-bundled-script ()
  "Default `--script-path' resolves to the `tibetan-ybh-prep.py'
shipped under `doc-prep/'.  Guards against accidental relocation
that would silently break the wrapper."
  (should (stringp tibetan-wylie-ingest-script-path))
  (should (file-exists-p tibetan-wylie-ingest-script-path))
  (should (string-match-p "tibetan-ybh-prep\\.py\\'"
                          tibetan-wylie-ingest-script-path)))

(ert-deftest tibetan-wylie-ingest-python-executable-defaults-to-python3 ()
  "`python3' is the default — most macOS / Linux installs alias
this to the system Python with the `pyewts' module installed via
`pip3 --user'.  Customisable for virtualenv users."
  (should (equal "python3" tibetan-wylie-ingest-python-executable)))

;; ============================================================================
;; VALIDATOR — body extraction
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-extract-body-reads-tibetan-text-section ()
  "`--extract-tibetan-text-body' returns the body between the
`* Tibetan Text' heading and the next top-level heading.  Trailing
sections (`* Document Info' etc.) are excluded."
  (let ((dir (make-temp-file "wylie-extract-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T\n\n"
                    "* Document Info\nmeta\n\n"
                    "* Tibetan Text\n"
                    "rgyal po //\nbtsun mo //\n\n"
                    "* Notes\nfooter\n"))
          (let ((body (tibetan-wylie-ingest--extract-tibetan-text-body src)))
            (should body)
            (should (string-match-p "rgyal po //" body))
            (should (string-match-p "btsun mo //" body))
            (should-not (string-match-p "footer" body))
            (should-not (string-match-p "meta" body))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-extract-body-handles-eof-section ()
  "When `* Tibetan Text' is the LAST top-level heading the body
runs to EOF without grabbing nonexistent trailing content."
  (let ((dir (make-temp-file "wylie-extract-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src
            (insert "* Tibetan Text\nrgyal po //\n"))
          (let ((body (tibetan-wylie-ingest--extract-tibetan-text-body src)))
            (should (string-match-p "rgyal po //" body))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-extract-body-returns-nil-when-section-missing ()
  "No `* Tibetan Text' heading → nil (validator surfaces this as
`:has-tibetan-text-section nil')."
  (let ((dir (make-temp-file "wylie-extract-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n* Notes\nfoo\n"))
          (should-not (tibetan-wylie-ingest--extract-tibetan-text-body src)))
      (delete-directory dir t))))

;; ============================================================================
;; VALIDATOR — character-class scan
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-scan-clean-wylie-zero-issues ()
  "Pure Wylie body (lowercase ASCII + `/' + `-' + spaces) yields
zero flagged characters — the validator's happy path."
  (let ((issues (tibetan-wylie-ingest--scan-body-for-issues
                 "rgyal po // btsun mo // 'di yang //")))
    (should (zerop (plist-get issues :tibetan-unicode-count)))
    (should (zerop (plist-get issues :non-ascii-count)))
    (should-not (plist-get issues :first-tibetan-unicode-pos))
    (should-not (plist-get issues :first-non-ascii-pos))))

(ert-deftest tibetan-wylie-ingest-scan-flags-tibetan-unicode ()
  "Tibetan Unicode (U+0F00-U+0FFF) embedded in a supposedly-Wylie
body is a strong red flag — the user likely fed a converted file
back in by mistake."
  (let ((issues (tibetan-wylie-ingest--scan-body-for-issues
                 "rgyal po རྒྱལ་པོ //")))
    ;; `རྒྱལ་པོ' = 7 codepoints (ར ྒ ྱ ལ ་ པ ོ).  The exact decomposition
    ;; depends on the input form;  the test asserts the body's
    ;; Tibetan-Unicode chars are detected (>=1) and the non-ASCII
    ;; counter is NOT also triggered by them.
    (should (> (plist-get issues :tibetan-unicode-count) 0))
    (should (plist-get issues :first-tibetan-unicode-pos))
    ;; Other-non-ASCII shouldn't be triggered for chars in the Tibetan range.
    (should (zerop (plist-get issues :non-ascii-count)))))

(ert-deftest tibetan-wylie-ingest-scan-flags-non-ascii-non-tibetan ()
  "Smart-quotes, em-dashes, NBSP — non-ASCII glyphs that aren't
Tibetan Unicode — are flagged via the second counter so the
wizard can warn before pyewts gets confused."
  (let ((issues (tibetan-wylie-ingest--scan-body-for-issues
                 "rgyal po — “smart” //")))
    (should (zerop (plist-get issues :tibetan-unicode-count)))
    (should (> (plist-get issues :non-ascii-count) 0))
    (should (plist-get issues :first-non-ascii-pos))))

(ert-deftest tibetan-wylie-ingest-scan-empty-body-zero-issues ()
  "Empty body → zero of everything (defensive — caller may pass
the empty string when the section is missing)."
  (let ((issues (tibetan-wylie-ingest--scan-body-for-issues "")))
    (should (zerop (plist-get issues :tibetan-unicode-count)))
    (should (zerop (plist-get issues :non-ascii-count)))))

;; ============================================================================
;; VALIDATOR — paragraph / segment counting
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-counts-paragraphs-blank-line-separated ()
  "Blank-line-separated blocks count as separate paragraphs.
Empty / whitespace-only blocks are skipped (matches the Python
script's `[p.strip() for p in re.split(...) if p.strip()]')."
  (let ((counts (tibetan-wylie-ingest--count-paragraphs-and-units
                 "rgyal po //\nbtsun mo //\n\nde nas //\n\n\ngsum pa //\n")))
    (should (= 3 (plist-get counts :paragraph-count)))))

(ert-deftest tibetan-wylie-ingest-counts-segments-via-double-shad ()
  "Segment count = total `//' (and `;;') units across the body.
The estimate is intentionally inclusive of the trailing post-//
residue so users see an upper bound."
  (let ((counts (tibetan-wylie-ingest--count-paragraphs-and-units
                 "rgyal po // btsun mo // de nas //")))
    ;; Three `//' boundaries; `split-string omit-nulls' drops the
    ;; empty trailing residue → 3 units.
    (should (= 3 (plist-get counts :estimated-segment-count)))))

(ert-deftest tibetan-wylie-ingest-counts-normalises-ocr-double-semicolon ()
  "`;;' (OCR variant of `//') counts as a segment delimiter — the
Python script normalises it before splitting, so the validator
must agree on the count."
  (let ((counts (tibetan-wylie-ingest--count-paragraphs-and-units
                 "rgyal po ;; btsun mo //")))
    (should (= 2 (plist-get counts :estimated-segment-count)))))

(ert-deftest tibetan-wylie-ingest-counts-empty-body ()
  "Empty body → zero paragraphs / zero segments (no signal, no
crash)."
  (let ((counts (tibetan-wylie-ingest--count-paragraphs-and-units "")))
    (should (zerop (plist-get counts :paragraph-count)))
    (should (zerop (plist-get counts :estimated-segment-count)))))

;; ============================================================================
;; VALIDATOR — public entry point
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-validate-input-clean-source ()
  "End-to-end:  clean Wylie source produces a report with
:has-tibetan-text-section t and zero flagged-char counts."
  (let ((dir (make-temp-file "wylie-validate-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T\n\n* Tibetan Text\n"
                    "rgyal po // btsun mo //\n\n"
                    "de nas dge slong //\n"))
          (let ((report (tibetan-wylie-ingest-validate-input src)))
            (should (equal src (plist-get report :path)))
            (should (plist-get report :has-tibetan-text-section))
            (should (= 2 (plist-get report :paragraph-count)))
            (should (= 3 (plist-get report :estimated-segment-count)))
            (should (zerop (plist-get report :tibetan-unicode-count)))
            (should (zerop (plist-get report :non-ascii-count)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-validate-input-no-tibetan-text-section ()
  "Source without `* Tibetan Text' returns the plist with
:has-tibetan-text-section nil and zero counts — wizard reads this
and refuses to fire the converter."
  (let ((dir (make-temp-file "wylie-validate-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n* Notes\nfoo\n"))
          (let ((report (tibetan-wylie-ingest-validate-input src)))
            (should-not (plist-get report :has-tibetan-text-section))
            (should (zerop (plist-get report :paragraph-count)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-validate-input-missing-file ()
  "Missing source path → `user-error' (caller never gets a stack
trace for a typo'd file argument)."
  (should-error
   (tibetan-wylie-ingest-validate-input "/nonexistent/path.org")
   :type 'user-error))

(ert-deftest tibetan-wylie-ingest-format-report-includes-key-counts ()
  "Report formatter mentions paragraph + segment counts and the
clean-body sentinel for the two issue counters.  Wizard relies on
the rendered string in the temp-buffer popup."
  (let* ((dir (make-temp-file "wylie-format-" t))
         (src (expand-file-name "source.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "* Tibetan Text\nrgyal po // btsun mo //\n"))
          (let* ((report (tibetan-wylie-ingest-validate-input src))
                 (txt (tibetan-wylie-ingest--format-validation-report
                       report)))
            (should (string-match-p "paragraphs:" txt))
            (should (string-match-p "estimated segments:" txt))
            (should (string-match-p "Tibetan Unicode chars:" txt))
            (should (string-match-p "non-ASCII" txt))
            (should (string-match-p "present" txt))))
      (delete-directory dir t))))

;; ============================================================================
;; INGEST — argv shape (no real Python invocation)
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-build-argv-default-no-in-place ()
  "Default argv = [SCRIPT, SOURCE].  No `--in-place' flag unless
the caller asks for it."
  (let ((argv (tibetan-wylie-ingest--build-argv "/tmp/src.org" nil)))
    (should (= 2 (length argv)))
    (should (equal tibetan-wylie-ingest-script-path (car argv)))
    (should (equal "/tmp/src.org" (cadr argv)))
    (should-not (member "--in-place" argv))))

(ert-deftest tibetan-wylie-ingest-build-argv-in-place-appends-flag ()
  "IN-PLACE non-nil → `--in-place' is appended to the argv tail."
  (let ((argv (tibetan-wylie-ingest--build-argv "/tmp/src.org" t)))
    (should (= 3 (length argv)))
    (should (equal "--in-place" (nth 2 argv)))))

(ert-deftest tibetan-wylie-ingest-build-argv-expands-relative-paths ()
  "Relative source paths are expanded so the Python script (which
runs in `default-directory') receives an absolute path."
  (let* ((default-directory "/tmp/")
         (argv (tibetan-wylie-ingest--build-argv "src.org" nil)))
    (should (file-name-absolute-p (cadr argv)))))

;; ============================================================================
;; INGEST — call-process wiring (stubbed)
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-file-errors-when-python-missing ()
  "Pre-flight gate:  `executable-find' returning nil → `user-error'
mentioning the Python executable.  Catches a missing `python3'
before the wizard wastes user time on a non-recoverable run."
  (let ((dir (make-temp-file "wylie-noop-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "* Tibetan Text\nrgyal po //\n"))
          (cl-letf (((symbol-function 'executable-find) (lambda (_) nil)))
            (should-error (tibetan-wylie-ingest-file src nil)
                          :type 'user-error)))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-file-errors-when-pyewts-missing ()
  "Pre-flight gate:  `python3 -c \"import pyewts\"' exiting non-zero
→ `user-error' with a `pip3 install' hint."
  (let ((dir (make-temp-file "wylie-noop-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "* Tibetan Text\nrgyal po //\n"))
          (cl-letf
              (((symbol-function 'executable-find) (lambda (_) "/usr/bin/python3"))
               ((symbol-function 'call-process)
                (lambda (&rest _args) 1)))
            (should-error (tibetan-wylie-ingest-file src nil)
                          :type 'user-error)))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-file-stdout-mode-returns-script-stdout ()
  "Happy path, no `--in-place':  the converter's stdout (the
Tibetan-Unicode body) is returned as a string."
  (let ((dir (make-temp-file "wylie-happy-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "* Tibetan Text\nrgyal po //\n"))
          (cl-letf
              (((symbol-function 'executable-find)
                (lambda (_) "/usr/bin/python3"))
               ((symbol-function 'tibetan-wylie-ingest--pyewts-available-p)
                (lambda () t))
               ((symbol-function 'tibetan-wylie-ingest--invoke-script)
                (lambda (_p _ip)
                  (list :exit-code 0
                        :stdout "* Tibetan Text\nརྒྱལ་པོ །།\n"
                        :stderr "[1 segments]"))))
            (let ((out (tibetan-wylie-ingest-file src nil)))
              (should (stringp out))
              (should (string-match-p "རྒྱལ" out)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-file-in-place-mode-returns-path ()
  "Happy path with IN-PLACE = t and the post-ingest relocation
disabled via SKIP-MOVE:  return value is the absolute path of the
overwritten source in its ORIGINAL location."
  (let ((dir (make-temp-file "wylie-happy-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "* Tibetan Text\nrgyal po //\n"))
          (cl-letf
              (((symbol-function 'executable-find)
                (lambda (_) "/usr/bin/python3"))
               ((symbol-function 'tibetan-wylie-ingest--pyewts-available-p)
                (lambda () t))
               ((symbol-function 'tibetan-wylie-ingest--invoke-script)
                (lambda (_p _ip)
                  (list :exit-code 0 :stdout "" :stderr "Wrote 1 segments"))))
            (let ((ret (tibetan-wylie-ingest-file src t t)))
              (should (equal (expand-file-name src) ret)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-file-in-place-relocates-to-work-in-progress ()
  "§5.27 Phase 2 follow-up:  IN-PLACE conversion (SKIP-MOVE nil)
fires `tibetan-doc-prep-move-to-work-in-progress' after a
successful run.  The prepared file ends up in the sibling
`work in progress/' folder;  return value points there."
  (require 'tibetan-doc-prep)
  (let ((dir (make-temp-file "wylie-relocate-" t)))
    (unwind-protect
        (let* ((raw-dir (expand-file-name "raw" dir))
               (src (expand-file-name "source.org" raw-dir))
               (tibetan-doc-prep-work-in-progress-folder "work in progress"))
          (make-directory raw-dir t)
          (with-temp-file src (insert "* Tibetan Text\nrgyal po //\n"))
          (cl-letf
              (((symbol-function 'executable-find)
                (lambda (_) "/usr/bin/python3"))
               ((symbol-function 'tibetan-wylie-ingest--pyewts-available-p)
                (lambda () t))
               ;; Stub the converter:  pretend it wrote Tibetan
               ;; Unicode in place (we leave the file untouched —
               ;; the relocator only cares about the path).
               ((symbol-function 'tibetan-wylie-ingest--invoke-script)
                (lambda (_p _ip)
                  (list :exit-code 0 :stdout "" :stderr "Wrote 1 segments"))))
            (let ((ret (tibetan-wylie-ingest-file src t)))
              ;; Source no longer in `raw/'.
              (should-not (file-exists-p src))
              ;; Landed in sibling `work in progress/'.
              (should (file-exists-p ret))
              (should (string-match-p
                       "work in progress/source\\.org\\'" ret)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-file-errors-when-script-nonzero-exit ()
  "Converter exit-code ≠ 0 → `user-error' carrying the stderr tail
so the user sees Python's diagnostic without consulting `*Messages*'."
  (let ((dir (make-temp-file "wylie-fail-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "* Tibetan Text\nrgyal po //\n"))
          (cl-letf
              (((symbol-function 'executable-find)
                (lambda (_) "/usr/bin/python3"))
               ((symbol-function 'tibetan-wylie-ingest--pyewts-available-p)
                (lambda () t))
               ((symbol-function 'tibetan-wylie-ingest--invoke-script)
                (lambda (_p _ip)
                  (list :exit-code 1
                        :stdout ""
                        :stderr "ValueError: no `* Tibetan Text' heading"))))
            (let ((err (should-error (tibetan-wylie-ingest-file src nil)
                                     :type 'user-error)))
              (should (string-match-p "ValueError" (cadr err))))))
      (delete-directory dir t))))

;; ============================================================================
;; SHAD NORMALISATION
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-normalize-shads-grammar-double-space ()
  "Grammar mode:  `| |' (standard Wylie double-shad) collapses
to `//' so the Python script splits the paragraph at each
sentence boundary."
  (should (equal "phyag tshal//de ngan"
                 (tibetan-wylie-ingest--normalize-shads-string
                  "phyag tshal| |de ngan" 'grammar))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-reading-double-space ()
  "Reading mode (default):  `| |' becomes `/ /' (two shads + space)
so the paragraph stays as ONE segment — one reading chunk = one
paragraph."
  (should (equal "phyag tshal/ /de ngan"
                 (tibetan-wylie-ingest--normalize-shads-string
                  "phyag tshal| |de ngan" 'reading)))
  ;; Default is reading-mode.
  (should (equal "phyag tshal/ /de ngan"
                 (tibetan-wylie-ingest--normalize-shads-string
                  "phyag tshal| |de ngan"))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-grammar-multi-space ()
  "Grammar:  multiple spaces between the two pipes collapse to `//'."
  (should (equal "phyag tshal//de ngan"
                 (tibetan-wylie-ingest--normalize-shads-string
                  "phyag tshal|   |de ngan" 'grammar))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-reading-multi-space ()
  "Reading:  multiple spaces between the two pipes still collapse
to `/ /' (single normalised space) so the script doesn't see `//'."
  (let ((out (tibetan-wylie-ingest--normalize-shads-string
              "phyag tshal|   |de ngan" 'reading)))
    (should (equal "phyag tshal/ /de ngan" out))
    (should-not (string-match-p "//" out))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-grammar-adjacent-double ()
  "Grammar:  `||' (no space) → `//'."
  (should (equal "phyag tshal//de ngan"
                 (tibetan-wylie-ingest--normalize-shads-string
                  "phyag tshal||de ngan" 'grammar))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-reading-adjacent-double ()
  "Reading:  `||' (no space — no whitespace was consumed by step 1)
maps each `|' to `/' individually → `//' which DOES split.

This is an intentional design choice — `||' (no space) is an
unambiguous segment-boundary signal even in reading-class Wylie
sources;  the user-friendly `| |' form (with space) is what
gets preserved as a within-paragraph double-shad."
  (let ((out (tibetan-wylie-ingest--normalize-shads-string
              "phyag tshal||de ngan" 'reading)))
    (should (equal "phyag tshal//de ngan" out))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-lone-pipe-both-modes ()
  "Lone `|' (no adjacent partner) maps to `/' in both modes."
  (should (equal "phyag tshal/ sangs rgyas/"
                 (tibetan-wylie-ingest--normalize-shads-string
                  "phyag tshal| sangs rgyas|" 'reading)))
  (should (equal "phyag tshal/ sangs rgyas/"
                 (tibetan-wylie-ingest--normalize-shads-string
                  "phyag tshal| sangs rgyas|" 'grammar))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-idempotent-both-modes ()
  "Body with no `|' is unchanged (idempotent re-run) in both modes."
  (let ((body "phyag tshal// sangs rgyas/"))
    (should (equal body
                   (tibetan-wylie-ingest--normalize-shads-string
                    body 'reading)))
    (should (equal body
                   (tibetan-wylie-ingest--normalize-shads-string
                    body 'grammar)))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-end-to-end-grammar ()
  "`tibetan-wylie-ingest-normalize-shads PATH 'grammar' rewrites
the body for sentence-level segments — `| |' → `//' so the
script splits at each sentence boundary."
  (let ((dir (make-temp-file "shad-norm-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T\n\n* Tibetan Text\n"
                    "phyag tshal| |de ngan|\n"))
          (let ((n (tibetan-wylie-ingest-normalize-shads src 'grammar)))
            (should (= 3 n))
            (let ((out (with-temp-buffer (insert-file-contents src)
                                         (buffer-string))))
              (should (string-match-p "phyag tshal//de ngan/" out)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-end-to-end-reading ()
  "`tibetan-wylie-ingest-normalize-shads PATH 'reading' (or no
class-mode) preserves paragraph-level segmentation — `| |' →
`/ /' which the Python script does NOT split at."
  (let ((dir (make-temp-file "shad-norm-r-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T\n\n* Tibetan Text\n"
                    "phyag tshal| |de ngan|\n"))
          (let ((n (tibetan-wylie-ingest-normalize-shads src 'reading)))
            (should (= 3 n))
            (let ((out (with-temp-buffer (insert-file-contents src)
                                         (buffer-string))))
              ;; Reading-mode output contains `/ /' (two shads + space),
              ;; NOT `//' (which would trigger script-level split).
              (should (string-match-p "phyag tshal/ /de ngan/" out))
              (should-not (string-match-p "phyag tshal//" out)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-normalize-shads-preserves-title-and-notes ()
  "Title / metadata + post-body sections are untouched even when
they contain `|' characters."
  (let ((dir (make-temp-file "shad-preserve-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T (note | inside)\n\n"
                    "* Tibetan Text\nphyag tshal|\n"
                    "\n* Notes\nA note with | inside\n"))
          (tibetan-wylie-ingest-normalize-shads src 'reading)
          (let ((out (with-temp-buffer (insert-file-contents src)
                                       (buffer-string))))
            (should (string-match-p
                     "#\\+TITLE: T (note | inside)" out))
            (should (string-match-p
                     "A note with | inside" out))))
      (delete-directory dir t))))

;; ============================================================================
;; FOLIO-MARKER NORMALISATION
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-normalize-folio-string-with-dot ()
  "`[141a.6]' → `[F:D141a6]'."
  (should (equal "bla ma [F:D141a6] sangs rgyas"
                 (tibetan-wylie-ingest--normalize-folio-markers-string
                  "bla ma [141a.6] sangs rgyas"))))

(ert-deftest tibetan-wylie-ingest-normalize-folio-string-no-dot ()
  "`[141a6]' (no separator dot) → `[F:D141a6]'."
  (should (equal "bla ma [F:D141a6] sangs rgyas"
                 (tibetan-wylie-ingest--normalize-folio-markers-string
                  "bla ma [141a6] sangs rgyas"))))

(ert-deftest tibetan-wylie-ingest-normalize-folio-string-b-side ()
  "B-side folios match the same regex."
  (should (equal "[F:D141b1] foo [F:D143b4]"
                 (tibetan-wylie-ingest--normalize-folio-markers-string
                  "[141b.1] foo [143b.4]"))))

(ert-deftest tibetan-wylie-ingest-normalize-folio-string-skips-citation ()
  "Bibliographic ranges with dashes / semicolons (e.g. the
`[141a.5–143b.4; pp. 285.5–290.4]' header line) are NOT touched
— the regex requires a pure `[digits<ab>.?digits]' shape."
  (let ((cite "[141a.5–143b.4; pp. 285.5–290.4]"))
    (should (equal cite
                   (tibetan-wylie-ingest--normalize-folio-markers-string
                    cite)))))

(ert-deftest tibetan-wylie-ingest-normalize-folio-string-skips-pp ()
  "Bracketed page references (`[pp. 285.5]') are skipped."
  (should (equal "[pp. 285.5]"
                 (tibetan-wylie-ingest--normalize-folio-markers-string
                  "[pp. 285.5]"))))

(ert-deftest tibetan-wylie-ingest-normalize-folio-end-to-end ()
  "End-to-end:  helper rewrites body markers + returns the
conversion count.  Bracketed citations OUTSIDE the body are
untouched."
  (let ((dir (make-temp-file "folio-norm-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T\n\n* Tibetan Text\n"
                    "[141a.5–143b.4; pp. 285.5–290.4] bla ma\n"
                    "phyag tshal [141a.6] de ngan [141b.1] song\n"))
          (let ((n (tibetan-wylie-ingest-normalize-folio-markers src)))
            (should (= 2 n))
            (let ((out (with-temp-buffer (insert-file-contents src)
                                         (buffer-string))))
              ;; Citation header preserved.
              (should (string-match-p
                       "\\[141a\\.5–143b\\.4; pp\\. 285\\.5–290\\.4\\]" out))
              ;; Folio markers reshaped.
              (should (string-match-p "\\[F:D141a6\\]" out))
              (should (string-match-p "\\[F:D141b1\\]" out)))))
      (delete-directory dir t))))

;; ============================================================================
;; VALIDATOR — pipe-shad + folio counters
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-validate-counts-pipe-shads ()
  "Validator reports the body's `|' character count via
`:pipe-shad-count'."
  (let ((dir (make-temp-file "val-pipe-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "* Tibetan Text\nphyag tshal| |de ngan|\n"))
          (let ((report (tibetan-wylie-ingest-validate-input src)))
            (should (= 3 (plist-get report :pipe-shad-count)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-validate-counts-non-standard-folios ()
  "Validator reports the body's non-standard folio-marker count
via `:non-standard-folio-count'.  Already-canonical `[F:D...]'
markers are NOT counted."
  (let ((dir (make-temp-file "val-folio-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "* Tibetan Text\n"
                    "[141a.6] foo [141b.1] bar [F:D142a3] baz\n"))
          (let ((report (tibetan-wylie-ingest-validate-input src)))
            ;; Two `[NNNa.M]' markers (counted) + one `[F:D...]'
            ;; (NOT counted — already canonical).
            (should (= 2 (plist-get report :non-standard-folio-count)))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-validate-clean-body-zero-counts ()
  "Clean ASCII Wylie body with `//' shads + `[F:D...]' folios →
both counters are 0 (no normalisation suggestions surface)."
  (let ((dir (make-temp-file "val-clean-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "* Tibetan Text\n"
                    "[F:D141a6] phyag tshal // de ngan //\n"))
          (let ((report (tibetan-wylie-ingest-validate-input src)))
            (should (zerop (plist-get report :pipe-shad-count)))
            (should (zerop
                     (plist-get report :non-standard-folio-count)))))
      (delete-directory dir t))))

;; ============================================================================
;; AUTO-WRAP — bare Wylie file gets canonical org structure
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-wrap-bare-source-adds-title-and-heading ()
  "Bare Wylie file (no `#+TITLE:', no `* Tibetan Text') → wrap adds
both, with the basename as title and original content as body."
  (let ((dir (make-temp-file "wylie-wrap-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "bla ma dam pa rnams la phyag 'tshal lo|\n"))
          (tibetan-wylie-ingest-wrap-bare-source src)
          (let ((out (with-temp-buffer (insert-file-contents src)
                                       (buffer-string))))
            (should (string-match-p "^#\\+TITLE: foo$" out))
            (should (string-match-p "^\\* Tibetan Text$" out))
            ;; Original body content is preserved verbatim.
            (should (string-match-p
                     "bla ma dam pa rnams la phyag 'tshal lo|"
                     out))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-wrap-bare-source-keeps-existing-title ()
  "When the file already has `#+TITLE:' but no `* Tibetan Text',
the wrap inserts ONLY the heading — no duplicate `#+TITLE:'."
  (let ((dir (make-temp-file "wylie-wrap-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: My Wylie Doc\n\n"
                    "bla ma|\n"))
          (tibetan-wylie-ingest-wrap-bare-source src)
          (let ((out (with-temp-buffer (insert-file-contents src)
                                       (buffer-string))))
            (should (string-match-p "^\\* Tibetan Text$" out))
            ;; Only ONE #+TITLE: line.
            (should (= 1 (cl-count "#+TITLE:" (split-string out "\n")
                                   :test
                                   (lambda (needle line)
                                     (string-match-p
                                      (regexp-quote needle) line)))))))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-wrap-bare-source-errors-when-already-wrapped ()
  "File that already has `* Tibetan Text' → `user-error' (wrap is
not idempotent — caller should skip the wrap step)."
  (let ((dir (make-temp-file "wylie-wrap-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T\n* Tibetan Text\nbla ma|\n"))
          (should-error (tibetan-wylie-ingest-wrap-bare-source src)
                        :type 'user-error))
      (delete-directory dir t))))

(ert-deftest tibetan-wylie-ingest-wrap-then-validate-roundtrip ()
  "End-to-end:  wrap a bare file, then `--validate-input' sees the
heading and returns a positive plist."
  (let ((dir (make-temp-file "wylie-wrap-rt-" t)))
    (unwind-protect
        (let ((src (expand-file-name "foo.org" dir)))
          (with-temp-file src
            (insert "[fol] bla ma dam pa| sangs rgyas|\n"))
          ;; Validator sees no section.
          (let ((before (tibetan-wylie-ingest-validate-input src)))
            (should-not (plist-get before :has-tibetan-text-section)))
          ;; Wrap, then re-validate.
          (tibetan-wylie-ingest-wrap-bare-source src)
          (let ((after (tibetan-wylie-ingest-validate-input src)))
            (should (plist-get after :has-tibetan-text-section))
            (should (> (plist-get after :paragraph-count) 0))))
      (delete-directory dir t))))

;; ============================================================================
;; END-TO-END — real Python invocation (skip-unless pyewts)
;; ============================================================================

(ert-deftest tibetan-wylie-ingest-real-python-roundtrip ()
  "Smoke test against the actual `tibetan-ybh-prep.py' converter
when pyewts is installed.  Verifies the wrapper composes
correctly with the script:  small Wylie input → in-place write →
post-ingest relocation into the sibling `work in progress/' folder
\(SKIP-MOVE = t suppresses the relocation so the test only
exercises the conversion path)."
  (skip-unless (tibetan-wylie-ingest--pyewts-available-p))
  (let ((dir (make-temp-file "wylie-e2e-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T\n\n* Tibetan Text\n"
                    "rgyal po dgyes // btsun mo dgyes //\n"))
          ;; SKIP-MOVE = t → file stays at SRC, no relocation.
          (tibetan-wylie-ingest-file src t t)
          (let ((out (with-temp-buffer
                       (insert-file-contents src)
                       (buffer-string))))
            (should (string-match-p "\\*\\*\\* Segment 1" out))
            (should (string-match-p "\\*\\*\\* Segment 2" out))
            ;; Tibetan Unicode for `rgyal po' (U+0F62 U+0F92...).
            (should (string-match-p "རྒྱལ" out))))
      (delete-directory dir t))))

(provide 'tibetan-wylie-ingest-test)
;;; tibetan-wylie-ingest-test.el ends here
