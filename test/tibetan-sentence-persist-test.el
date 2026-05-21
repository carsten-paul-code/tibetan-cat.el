;;; tibetan-sentence-persist-test.el --- Tests for tibetan-sentence-persist.el -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for the sentence-level persistence module.
;;
;; Coverage:
;; - Path / filename helpers       (sent-NNN.org generation, id extraction)
;; - Hash computation              (consistency, change detection)
;; - Source-file sentence scanner  (bounds, child collection, both layouts)
;; - Scaffold structure            (required headers and section headings)
;; - Regenerate idempotency        (user content preservation)
;; - Section / metadata helpers    (#+SEGMENTS, #+TIBETAN_HASH, #+SOURCE)
;;
;; The Claude request path (`tibetan-sentence--request-claude') and the
;; interactive `tibetan-sentence-open-analysis' / `…-reanalyze' commands
;; are NOT exercised here — they require a live `gptel' backend and a
;; real source buffer with `org-mode' enabled.  We do test their
;; underlying helpers (prompt builder, source-file resolution) where
;; possible without a network call.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add module directories to load path so the require below resolves.
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-sentence-persist)

;; ============================================================================
;; PATH / FILENAME HELPER TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-filename-padding ()
  "`tibetan-sentence--filename' zero-pads to 3 digits."
  (should (string= "sent-001.org" (tibetan-sentence--filename 1)))
  (should (string= "sent-010.org" (tibetan-sentence--filename 10)))
  (should (string= "sent-100.org" (tibetan-sentence--filename 100)))
  (should (string= "sent-999.org" (tibetan-sentence--filename 999))))

(ert-deftest tibetan-sentence-filename-zero ()
  "`tibetan-sentence--filename' handles 0."
  (should (string= "sent-000.org" (tibetan-sentence--filename 0))))

(ert-deftest tibetan-sentence-filepath-honors-folder ()
  "`tibetan-sentence--filepath' joins folder + basename."
  (let ((folder "/tmp/someproject/analysis"))
    (should (string= (expand-file-name "sent-007.org" folder)
                     (tibetan-sentence--filepath 7 folder)))))

(ert-deftest tibetan-sentence-sent-id-from-basename ()
  "`tibetan-sentence--sent-id-from-filename' extracts numeric id."
  (should (= 1   (tibetan-sentence--sent-id-from-filename "sent-001.org")))
  (should (= 42  (tibetan-sentence--sent-id-from-filename "sent-042.org")))
  (should (= 144 (tibetan-sentence--sent-id-from-filename "sent-144.org"))))

(ert-deftest tibetan-sentence-sent-id-from-fullpath ()
  "`tibetan-sentence--sent-id-from-filename' works on absolute paths."
  (should (= 7
             (tibetan-sentence--sent-id-from-filename
              "/some/abs/path/analysis/sent-007.org"))))

(ert-deftest tibetan-sentence-sent-id-rejects-non-sent ()
  "`tibetan-sentence--sent-id-from-filename' returns nil for non-sent file."
  (should (null (tibetan-sentence--sent-id-from-filename "seg-001.org")))
  (should (null (tibetan-sentence--sent-id-from-filename "anything-else.org"))))

(ert-deftest tibetan-sentence-seg-id-from-basename ()
  "`tibetan-sentence--seg-id-from-filename' extracts numeric id."
  (should (= 1  (tibetan-sentence--seg-id-from-filename "seg-001.org")))
  (should (= 42 (tibetan-sentence--seg-id-from-filename "seg-042.org"))))

(ert-deftest tibetan-sentence-seg-id-rejects-non-seg ()
  "`tibetan-sentence--seg-id-from-filename' returns nil for non-seg file."
  (should (null (tibetan-sentence--seg-id-from-filename "sent-001.org"))))

;; ============================================================================
;; HASH FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-compute-hash-shape ()
  "Hash returns a 32-char hex string (md5)."
  (let ((h (tibetan-sentence--compute-hash "test")))
    (should (stringp h))
    (should (= 32 (length h)))
    (should (string-match-p "\\`[0-9a-f]+\\'" h))))

(ert-deftest tibetan-sentence-compute-hash-deterministic ()
  "Same input produces same hash."
  (should (string= (tibetan-sentence--compute-hash "བྱང་ཆུབ་")
                   (tibetan-sentence--compute-hash "བྱང་ཆུབ་"))))

(ert-deftest tibetan-sentence-compute-hash-distinguishes-edits ()
  "Different inputs produce different hashes."
  (should-not (string= (tibetan-sentence--compute-hash "foo")
                       (tibetan-sentence--compute-hash "foo "))))

(ert-deftest tibetan-sentence-compute-hash-tibetan ()
  "Hash works on Tibetan unicode."
  (let ((h (tibetan-sentence--compute-hash "བཀྲ་ཤིས་བདེ་ལེགས།")))
    (should (stringp h))
    (should (= 32 (length h)))))

(ert-deftest tibetan-sentence-compute-hash-membership-change ()
  "Adding a child segment changes the concatenated-text hash.
This is the invariant that catches sentence membership changes."
  (let* ((children-1 (string-join '("seg1 text" "seg2 text") "\n"))
         (children-2 (string-join '("seg1 text" "seg2 text" "seg3 text") "\n")))
    (should-not (string= (tibetan-sentence--compute-hash children-1)
                         (tibetan-sentence--compute-hash children-2)))))

(ert-deftest tibetan-sentence-get-stored-hash-reads-header ()
  "`--get-stored-hash' returns the value of the #+TIBETAN_HASH header."
  (let ((tmp (make-temp-file "sent-test-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+TITLE: Foo\n")
            (insert "#+TIBETAN_HASH: deadbeef0123456789abcdef00112233\n")
            (insert "* Tibetan Text\n"))
          (should (string= "deadbeef0123456789abcdef00112233"
                           (tibetan-sentence--get-stored-hash tmp))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-sentence-get-stored-hash-missing ()
  "`--get-stored-hash' returns nil when the header is absent."
  (let ((tmp (make-temp-file "sent-test-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+TITLE: No hash here\n* Tibetan Text\n"))
          (should (null (tibetan-sentence--get-stored-hash tmp))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-sentence-check-sync-hit ()
  "`--check-sync' is non-nil when stored hash matches text."
  (let* ((text "བྱང་ཆུབ་སེམས་དཔའ།")
         (h    (tibetan-sentence--compute-hash text))
         (tmp  (make-temp-file "sent-test-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert (format "#+TIBETAN_HASH: %s\n" h)))
          (should (tibetan-sentence--check-sync tmp text)))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-sentence-check-sync-miss ()
  "`--check-sync' is nil when text changed since hash was stored."
  (let* ((text-old "བྱང་ཆུབ།")
         (text-new "བྱང་ཆུབ་སེམས་དཔའ།")
         (h-old    (tibetan-sentence--compute-hash text-old))
         (tmp      (make-temp-file "sent-test-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert (format "#+TIBETAN_HASH: %s\n" h-old)))
          (should-not (tibetan-sentence--check-sync tmp text-new)))
      (when (file-exists-p tmp) (delete-file tmp)))))

;; ============================================================================
;; SOURCE-FILE SCANNER — fixtures + tests
;; ============================================================================
;;
;; We build temp buffers in `org-mode' to exercise the scanner without
;; needing a real source file on disk.

(defvar tibetan-sentence-test--section-wrap-buffer
  "* Milarepa rnam-thar
** Introduction
*** Sentence 1
**** Segment 1
First clause
**** Segment 2
Second clause
*** Sentence 2
**** Segment 3
Third clause — second sentence
"
  "Layout B fixture: Section + Sentence-wrap.
This is what `tibetan-add-sentence-structure' produces.")

(defvar tibetan-sentence-test--fresh-prep-buffer
  "* Milarepa rnam-thar
** Sentence 1
*** Segment 1
First clause
*** Segment 2
Second clause
** Sentence 2
*** Segment 3
Third clause — second sentence
"
  "Layout A fixture: fresh-prep, no Section wrapper.
This is what `tibetan-prepare-document' produces directly.")

(defun tibetan-sentence-test--with-buffer (text fn)
  "Insert TEXT into a temp `org-mode' buffer, then call FN."
  (with-temp-buffer
    (insert text)
    (org-mode)
    (goto-char (point-min))
    (funcall fn)))

(ert-deftest tibetan-sentence-scanner-bounds-from-segment ()
  "From cursor on a Segment heading, bounds resolve to the parent Sentence."
  (tibetan-sentence-test--with-buffer
   tibetan-sentence-test--section-wrap-buffer
   (lambda ()
     (re-search-forward "^\\*\\*\\*\\* Segment 1" nil t)
     (let ((bounds (tibetan-sentence--current-sentence-bounds)))
       (should bounds)
       (goto-char (car bounds))
       (should (looking-at "^\\*\\*\\* Sentence 1"))))))

(ert-deftest tibetan-sentence-scanner-bounds-from-sentence ()
  "From cursor on a Sentence heading, bounds resolve to that sentence."
  (tibetan-sentence-test--with-buffer
   tibetan-sentence-test--section-wrap-buffer
   (lambda ()
     (re-search-forward "^\\*\\*\\* Sentence 2" nil t)
     (beginning-of-line)
     (let ((bounds (tibetan-sentence--current-sentence-bounds)))
       (should bounds)
       (goto-char (car bounds))
       (should (looking-at "^\\*\\*\\* Sentence 2"))))))

(ert-deftest tibetan-sentence-scanner-bounds-fresh-prep ()
  "Layout A (Sentence at L2, Segment at L3) is also recognized."
  (tibetan-sentence-test--with-buffer
   tibetan-sentence-test--fresh-prep-buffer
   (lambda ()
     (re-search-forward "^\\*\\*\\* Segment 2" nil t)
     (let ((bounds (tibetan-sentence--current-sentence-bounds)))
       (should bounds)
       (goto-char (car bounds))
       (should (looking-at "^\\*\\* Sentence 1"))))))

(ert-deftest tibetan-sentence-scanner-bounds-no-sentence ()
  "Returns nil when point is in a heading-less / non-sentence area."
  (tibetan-sentence-test--with-buffer
   "* Top
Just some prose, no sentence headings here.
"
   (lambda ()
     (goto-char (point-max))
     (should (null (tibetan-sentence--current-sentence-bounds))))))

(ert-deftest tibetan-sentence-scanner-num-from-segment ()
  "`--current-sentence-num' returns the Sentence N number."
  (tibetan-sentence-test--with-buffer
   tibetan-sentence-test--section-wrap-buffer
   (lambda ()
     (re-search-forward "^\\*\\*\\*\\* Segment 2" nil t)
     (should (= 1 (tibetan-sentence--current-sentence-num)))
     (re-search-forward "^\\*\\*\\*\\* Segment 3" nil t)
     (should (= 2 (tibetan-sentence--current-sentence-num))))))

(ert-deftest tibetan-sentence-scanner-collect-children ()
  "`--collect-current-sentence' returns expected segment numbers and text."
  (tibetan-sentence-test--with-buffer
   tibetan-sentence-test--section-wrap-buffer
   (lambda ()
     (re-search-forward "^\\*\\*\\* Sentence 1" nil t)
     (beginning-of-line)
     (let* ((data (tibetan-sentence--collect-current-sentence))
            (seg-nums (plist-get data :seg-nums))
            (text (plist-get data :tibetan-text)))
       (should (= 1 (plist-get data :sent-num)))
       (should (equal '(1 2) seg-nums))
       (should (string-match-p "First clause" text))
       (should (string-match-p "Second clause" text))
       ;; Sentence 1 must NOT include the third clause.
       (should-not (string-match-p "Third clause" text))))))

(ert-deftest tibetan-sentence-scanner-collect-fresh-prep ()
  "Scanner works on Layout A (no section wrapper)."
  (tibetan-sentence-test--with-buffer
   tibetan-sentence-test--fresh-prep-buffer
   (lambda ()
     (re-search-forward "^\\*\\* Sentence 2" nil t)
     (beginning-of-line)
     (let ((data (tibetan-sentence--collect-current-sentence)))
       (should (= 2 (plist-get data :sent-num)))
       (should (equal '(3) (plist-get data :seg-nums)))
       (should (string-match-p "Third clause"
                               (plist-get data :tibetan-text)))))))

(ert-deftest tibetan-sentence-scanner-collect-from-source-buffer ()
  "`--collect-from-source-buffer' is driven by SENT-NUM, not point."
  (tibetan-sentence-test--with-buffer
   tibetan-sentence-test--section-wrap-buffer
   (lambda ()
     ;; Move point somewhere in sentence 1 — then ask for sentence 2.
     (re-search-forward "^\\*\\*\\*\\* Segment 1" nil t)
     (let ((data (tibetan-sentence--collect-from-source-buffer 2)))
       (should data)
       (should (= 2 (plist-get data :sent-num)))
       (should (equal '(3) (plist-get data :seg-nums)))))))

(ert-deftest tibetan-sentence-scanner-collect-missing-sentence ()
  "`--collect-from-source-buffer' returns nil when SENT-NUM is absent."
  (tibetan-sentence-test--with-buffer
   tibetan-sentence-test--section-wrap-buffer
   (lambda ()
     (should (null (tibetan-sentence--collect-from-source-buffer 99))))))

;; ============================================================================
;; SCAFFOLD STRUCTURE TESTS
;; ============================================================================
;;
;; The scaffold is a pure string builder — we can call it directly and
;; assert on the produced text.  This guards the body shape contract
;; documented in the module commentary AND in
;; project_sentence_architecture.md.

(ert-deftest tibetan-sentence-scaffold-required-headers ()
  "Scaffold contains all the persistence-critical org-mode headers."
  (let ((body (tibetan-sentence--scaffold
               5 '(7 8 9) "བྱང་ཆུབ་" "byang chub" "/tmp/foo.org")))
    (should (string-match-p "^#\\+TITLE: Sentence 5 Analysis$" body))
    (should (string-match-p "^#\\+STARTUP: showall$" body))
    (should (string-match-p "^#\\+SEGMENTS: 7, 8, 9$" body))
    (should (string-match-p "^#\\+TIBETAN_HASH: [0-9a-f]\\{32\\}$" body))
    (should (string-match-p "^#\\+ANALYSIS_VERSION: 1\\.0$" body))
    (should (string-match-p "^#\\+CREATED: " body))
    (should (string-match-p "^#\\+LAST_ANALYZED: " body))))

(ert-deftest tibetan-sentence-scaffold-disables-toc-and-section-numbering ()
  "§5.22 follow-up (2026-05-21):  sentence scaffold emits
`#+OPTIONS: toc:nil num:nil' so HTML / PDF / LaTeX export of the
file does NOT include an auto-generated table of contents AND
does NOT prefix headings with section numbers (`1. My Notes' /
`1.1. …').  Class-presentation clean — the on-disk org-mode
headings already structure the document, and a numbered TOC on
top of that is visual noise when the file is projected in class."
  (let ((body (tibetan-sentence--scaffold
               1 '(1) "བདུད།" "bdud" "/tmp/foo.org")))
    (should (string-match-p "^#\\+OPTIONS:.*toc:nil" body))
    (should (string-match-p "^#\\+OPTIONS:.*num:nil" body))))

(ert-deftest tibetan-sentence-scaffold-source-link ()
  "Scaffold encodes the source-file link with sentence anchor."
  (let ((body (tibetan-sentence--scaffold
               3 '(4 5) "བྱང་ཆུབ་" nil "/abs/Milarepa-prepared.org")))
    (should (string-match-p
             "^#\\+SOURCE: \\[\\[file:\\.\\./Milarepa-prepared\\.org::\\*Sentence 3\\]\\[Milarepa-prepared\\.org / Sentence 3\\]\\]$"
             body))))

(ert-deftest tibetan-sentence-scaffold-no-source-link-when-nil ()
  "Scaffold omits #+SOURCE header when source-file is nil."
  (let ((body (tibetan-sentence--scaffold 1 '(1) "x" nil nil)))
    (should-not (string-match-p "^#\\+SOURCE:" body))))

(ert-deftest tibetan-sentence-scaffold-section-headings ()
  "Scaffold mirrors the segment layout (§5.18 alignment, 2026-05-18).
Top-level shape:

  * My Notes
  * Working Translation
  * Tibetan Text
  * Tibetan Analysis           (was `* Auto-Analysis')
    ** … segment renderer body …
    ** Provided Translations   (nested, NOT top-level)
      *** Roehrich
      *** Class Translation
      *** Claude Context
      *** Claude Vocabulary / *** Claude Particles
  * Footnotes

The sentence-specific Roehrich / Class Translation / Claude Context
level-3 entries live INSIDE the nested `** Provided Translations',
matching the segment file shape.  No top-level `* Provided
Translations'.  My Notes / Working Translation are AT THE TOP
\(matches segment §5.18 ordering)."
  (let ((body (tibetan-sentence--scaffold 1 '(1) "x" "x" "/tmp/f.org")))
    (should (string-match-p "^\\* Tibetan Text$"           body))
    ;; New parent name (alignment with segment §5.18).
    ;; The fallback `* Wylie' (when renderer unavailable) is acceptable too.
    (should (or (string-match-p "^\\* Tibetan Analysis$" body)
                (string-match-p "^\\* Wylie$"            body)))
    ;; Legacy `* Auto-Analysis' name must NOT appear in fresh scaffolds.
    (should-not (string-match-p "^\\* Auto-Analysis$" body))
    ;; No more TOP-LEVEL `* Provided Translations'.  It's a nested
    ;; level-2 inside `* Tibetan Analysis' (segment shape).
    (should-not (string-match-p "^\\* Provided Translations$" body))
    ;; Sentence-specific level-3 entries.
    (should (string-match-p "^\\*\\*\\* Roehrich$"          body))
    (should (string-match-p "^\\*\\*\\* Class Translation$" body))
    (should (string-match-p "^\\*\\*\\* Claude Context$"    body))
    ;; User sections + Footnotes.
    (should (string-match-p "^\\* Working Translation$"     body))
    (should (string-match-p "^\\* My Notes$"                body))
    (should (string-match-p "^\\* Footnotes$"               body))))

(ert-deftest tibetan-sentence-scaffold-user-sections-at-top ()
  "My Notes / Working Translation are emitted ABOVE Tibetan Text
\(segment §5.18 ordering).  Footnotes stays at the BOTTOM."
  (let* ((body (tibetan-sentence--scaffold 1 '(1) "x" "x" "/tmp/f.org"))
         (my-notes-pos     (string-match "^\\* My Notes$"            body))
         (working-pos      (string-match "^\\* Working Translation$" body))
         (tibetan-text-pos (string-match "^\\* Tibetan Text$"        body))
         (footnotes-pos    (string-match "^\\* Footnotes$"           body)))
    (should my-notes-pos)
    (should working-pos)
    (should tibetan-text-pos)
    (should footnotes-pos)
    ;; My Notes and Working Translation precede Tibetan Text.
    (should (< my-notes-pos tibetan-text-pos))
    (should (< working-pos tibetan-text-pos))
    ;; Footnotes is last (after everything else).
    (should (> footnotes-pos tibetan-text-pos))))

(ert-deftest tibetan-sentence-scaffold-tibetan-text-embedded ()
  "Scaffold embeds the tibetan-text payload under * Tibetan Text."
  (let ((body (tibetan-sentence--scaffold
               1 '(1) "བཀྲ་ཤིས།" nil "/tmp/f.org")))
    (should (string-match-p "\\* Tibetan Text\nབཀྲ་ཤིས།" body))))

(ert-deftest tibetan-sentence-scaffold-tibetan-analysis-on-tibetan-input ()
  "A Tibetan-containing sentence gets a `* Tibetan Analysis' block
with the segment-level renderer output embedded.  The sentence
scaffold no longer STRIPS the renderer's `** Translation' or
`** Provided Translations' subtrees — those slots now hold the
sentence-level Claude content (matching segment §5.18 layout).
What used to be the top-level `* Provided Translations' block is
nested inside `* Tibetan Analysis' as `** Provided Translations'."
  (skip-unless (fboundp 'tibetan-analysis-generate-content))
  (let ((body (tibetan-sentence--scaffold
               1 '(1) "བཀྲ་ཤིས་བདེ་ལེགས།" nil "/tmp/f.org")))
    (should (string-match-p "^\\* Tibetan Analysis$" body))
    ;; Segment-level renderer section MUST come through.
    (should (string-match-p "^\\*\\* Wylie Transliteration$" body))
    ;; The legacy `* Auto-Analysis' name must NOT appear (parent
    ;; renamed for §5.18 alignment).
    (should-not (string-match-p "^\\* Auto-Analysis$" body))))

(ert-deftest tibetan-sentence-main-clause-rendered-for-transitive ()
  "An Erg-Abs transitive sentence (subject ERG + honorific verb
present in the classifier DB) produces a `** Main Clause' section
with a MAIN VERB line and the honorific verb's lemma.
Uses `བཀའ་སྩལ' (present in the verb DB) to keep the assertion
independent of the verb-extractor's past-stem resolution path."
  (skip-unless (fboundp 'tibetan-analyze-round2))
  (let* ((text "བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ།")
         (body (tibetan-sentence--render-main-clause text)))
    (should body)
    (should (string-match-p "^- MAIN VERB:" body))
    (should (string-match-p "བཀའ་སྩལ" body))))

(ert-deftest tibetan-sentence-main-clause-nil-for-no-text ()
  "Empty / nil input returns nil (caller omits the section)."
  (should (null (tibetan-sentence--render-main-clause nil)))
  (should (null (tibetan-sentence--render-main-clause ""))))

(ert-deftest tibetan-sentence-main-clause-nil-when-no-finite-verb ()
  "Text with no finite verb (pure NP) returns nil — no main clause."
  (skip-unless (fboundp 'tibetan-analyze-round2))
  (should (null (tibetan-sentence--render-main-clause "ཆོས"))))

(ert-deftest tibetan-sentence-main-clause-appears-in-auto-analysis ()
  "The `** Main Clause' section is appended to the auto-analysis
body emitted by `tibetan-sentence--render-auto-analysis' for a real
Tibetan sentence with a recognised verb."
  (skip-unless (fboundp 'tibetan-analyze-round2))
  (let ((content (tibetan-sentence--render-auto-analysis
                  "བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ།")))
    (should content)
    (should (string-match-p "^\\*\\* Main Clause$" content))
    (should (string-match-p "MAIN VERB" content))))

(ert-deftest tibetan-sentence-scaffold-includes-provided-translations-nested ()
  "After §5.18 sentence alignment (2026-05-18), the scaffold's
embedded auto-analysis CONTAINS `** Provided Translations'
\(nested under `* Tibetan Analysis').  The legacy assertion
\(that it must NOT contain such a heading) is retired because the
sentence file no longer carries a competing top-level
`* Provided Translations'."
  (skip-unless (fboundp 'tibetan-analysis-generate-content))
  (let* ((body (tibetan-sentence--scaffold
                1 '(1) "བཀྲ་ཤིས་བདེ་ལེགས།" nil "/tmp/f.org")))
    (should (string-match-p "^\\*\\* Provided Translations$" body))
    (should-not (string-match-p "^\\* Provided Translations$" body))))

(ert-deftest tibetan-sentence-scaffold-wylie-fallback ()
  "Scaffold falls back to a nested `** Wylie' block inside
`* Tibetan Analysis' when the segment renderer returns no useful
output (no Tibetan content in the input, renderer unavailable,
etc.).  The Wylie body shows the
`[Wylie transliteration not available]' placeholder when wylie is
nil or empty.

§5.18 sentence alignment (2026-05-18):  the fallback used to emit
a top-level `* Wylie' block;  it now emits a level-2 `** Wylie'
nested under `* Tibetan Analysis' so the outer shape stays
identical to the renderer-active path."
  (let ((body-nil   (tibetan-sentence--scaffold 1 '(1) "x" nil "/t.org"))
        (body-empty (tibetan-sentence--scaffold 1 '(1) "x" "" "/t.org")))
    ;; No Tibetan in "x" → auto-analysis empty → fallback Wylie block.
    (should (string-match-p "^\\*\\* Wylie$" body-nil))
    (should (string-match-p "\\[Wylie transliteration not available\\]"
                            body-nil))
    (should (string-match-p "^\\*\\* Wylie$" body-empty))
    (should (string-match-p "\\[Wylie transliteration not available\\]"
                            body-empty))
    ;; The fallback uses level-2 inside `* Tibetan Analysis', not
    ;; top-level `* Wylie' anymore.
    (should-not (string-match-p "^\\* Wylie$" body-nil))))

(ert-deftest tibetan-sentence-scaffold-empty-segments ()
  "Scaffold accepts empty seg-nums list (degenerate but valid)."
  (let ((body (tibetan-sentence--scaffold 1 '() "" nil "/tmp/f.org")))
    (should (string-match-p "^#\\+SEGMENTS: $" body))))

(ert-deftest tibetan-sentence-scaffold-hash-matches-text ()
  "The #+TIBETAN_HASH header in the scaffold equals hash(text)."
  (let* ((text "བྱང་ཆུབ་སེམས་དཔའ།")
         (body (tibetan-sentence--scaffold 1 '(1) text nil "/t.org"))
         (expected (tibetan-sentence--compute-hash text)))
    (should (string-match (format "^#\\+TIBETAN_HASH: %s$" expected)
                          body))))

;; ============================================================================
;; CREATE-FILE TESTS (write to a real temp dir)
;; ============================================================================

(defmacro tibetan-sentence-test--with-source-buffer (text &rest body)
  "Insert TEXT into a temp org file, visit it, then run BODY in that buffer.
Cleans up the temp file and any analysis/ siblings on exit."
  (declare (indent 1) (debug t))
  `(let* ((tmp-dir  (make-temp-file "sent-test-" t))
          (src-file (expand-file-name "src.org" tmp-dir)))
     (unwind-protect
         (progn
           (with-temp-file src-file (insert ,text))
           (let ((buf (find-file-noselect src-file)))
             (unwind-protect
                 (with-current-buffer buf
                   ,@body)
               (when (buffer-live-p buf)
                 (with-current-buffer buf (set-buffer-modified-p nil))
                 (kill-buffer buf)))))
       (when (file-directory-p tmp-dir)
         (delete-directory tmp-dir t)))))

(ert-deftest tibetan-sentence-create-file-writes-scaffold ()
  "`--create-file' produces a real file with scaffold content."
  (tibetan-sentence-test--with-source-buffer
   tibetan-sentence-test--section-wrap-buffer
   (re-search-forward "^\\*\\*\\* Sentence 1" nil t)
   (let* ((data (tibetan-sentence--collect-current-sentence))
          (path (tibetan-sentence--create-file
                 (plist-get data :sent-num)
                 (plist-get data :seg-nums)
                 (plist-get data :tibetan-text)
                 (buffer-file-name))))
     (should (file-exists-p path))
     (should (string= "sent-001.org" (file-name-nondirectory path)))
     (with-temp-buffer
       (insert-file-contents path)
       (goto-char (point-min))
       (should (re-search-forward "^#\\+SEGMENTS: 1, 2$" nil t))
       (should (re-search-forward "^\\* Tibetan Text$" nil t))
       (should (re-search-forward "First clause" nil t))
       (should (re-search-forward "Second clause" nil t))))))

(ert-deftest tibetan-sentence-create-file-respects-folder ()
  "Created file lands in <src-dir>/analysis/."
  (tibetan-sentence-test--with-source-buffer
   tibetan-sentence-test--section-wrap-buffer
   (re-search-forward "^\\*\\*\\* Sentence 2" nil t)
   (let* ((data (tibetan-sentence--collect-current-sentence))
          (path (tibetan-sentence--create-file
                 (plist-get data :sent-num)
                 (plist-get data :seg-nums)
                 (plist-get data :tibetan-text)
                 (buffer-file-name))))
     (should (string-match-p "/analysis/sent-002\\.org\\'" path)))))

;; ============================================================================
;; SECTION-BODY READING TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-find-section-bounds-basic ()
  "Returns (START . END) covering one * SECTION block."
  (with-temp-buffer
    (insert "* Tibetan Text\nfoo\n\n* Wylie\nbar\n\n* My Notes\nnotes\n")
    (let ((bounds (tibetan-sentence--find-section-bounds
                   (current-buffer) "Wylie")))
      (should bounds)
      (goto-char (car bounds))
      (should (looking-at "^\\* Wylie$"))
      (goto-char (cdr bounds))
      (should (or (looking-at "^\\* My Notes")
                  (eobp))))))

(ert-deftest tibetan-sentence-find-section-bounds-missing ()
  "Returns nil for a missing section."
  (with-temp-buffer
    (insert "* Tibetan Text\nfoo\n")
    (should (null (tibetan-sentence--find-section-bounds
                   (current-buffer) "Footnotes")))))

(ert-deftest tibetan-sentence-read-section-body-trims ()
  "Returns trimmed body of a top-level section, or nil when empty."
  (let ((tmp (make-temp-file "sent-rs-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "* Tibetan Text\n  hello world  \n\n"
                    "* My Notes\n\n\n"
                    "* Wylie\nfoo bar\n"))
          (should (string= "hello world"
                           (tibetan-sentence--read-section-body
                            tmp "Tibetan Text")))
          (should (null (tibetan-sentence--read-section-body
                         tmp "My Notes")))
          (should (string= "foo bar"
                           (tibetan-sentence--read-section-body
                            tmp "Wylie"))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-sentence-read-third-level-skips-placeholders ()
  "`--read-third-level-body' returns nil for known placeholder patterns."
  (let ((tmp (make-temp-file "sent-rs3-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "* Provided Translations\n"
                    "*** Roehrich\n"
                    "[Hand-paste the published Roehrich English here]\n\n"
                    "*** Class Translation\n"
                    "Real class translation here.\n\n"
                    "*** Claude Translation\n"
                    "[Awaiting Claude…]\n\n"))
          (should (null (tibetan-sentence--read-third-level-body
                         tmp "Roehrich")))
          (should (string= "Real class translation here."
                           (tibetan-sentence--read-third-level-body
                            tmp "Class Translation")))
          (should (null (tibetan-sentence--read-third-level-body
                         tmp "Claude Translation"))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-sentence-read-translation-bodies-shape ()
  "`--read-translation-bodies' returns plist with both keys."
  (let ((tmp (make-temp-file "sent-rt-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "*** Roehrich\nfoo\n\n*** Class Translation\nbar\n"))
          (let ((tr (tibetan-sentence--read-translation-bodies tmp)))
            (should (string= "foo" (plist-get tr :roehrich)))
            (should (string= "bar" (plist-get tr :class)))))
      (when (file-exists-p tmp) (delete-file tmp)))))

;; ============================================================================
;; #+SOURCE / #+SEGMENTS HEADER ROUNDTRIP TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-source-file-from-analysis ()
  "Resolves the absolute source-file path from the #+SOURCE link."
  (let* ((tmp-dir  (make-temp-file "sent-src-" t))
         (src      (expand-file-name "Milarepa-prepared.org" tmp-dir))
         (analysis (expand-file-name "analysis" tmp-dir))
         (sentf    (expand-file-name "sent-001.org" analysis)))
    (unwind-protect
        (progn
          (make-directory analysis)
          (with-temp-file src      (insert "stub source\n"))
          (with-temp-file sentf
            (insert "#+SOURCE: [[file:../Milarepa-prepared.org::*Sentence 1][Milarepa-prepared.org / Sentence 1]]\n"))
          (should (string= (expand-file-name "Milarepa-prepared.org" tmp-dir)
                           (tibetan-sentence--source-file-from-analysis
                            sentf))))
      (when (file-directory-p tmp-dir) (delete-directory tmp-dir t)))))

(ert-deftest tibetan-sentence-source-file-from-analysis-missing ()
  "Returns nil when no #+SOURCE header is present."
  (let ((tmp (make-temp-file "sent-nos-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert "no source header here\n"))
          (should (null (tibetan-sentence--source-file-from-analysis tmp))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-sentence-seg-nums-from-file-csv ()
  "Parses #+SEGMENTS: csv into a list of integers."
  (let ((tmp (make-temp-file "sent-segs-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert "#+SEGMENTS: 7, 8, 9\n"))
          (should (equal '(7 8 9)
                         (tibetan-sentence--seg-nums-from-file tmp))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-sentence-seg-nums-from-file-single ()
  "Parses single-segment #+SEGMENTS: into a one-element list."
  (let ((tmp (make-temp-file "sent-segs-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert "#+SEGMENTS: 42\n"))
          (should (equal '(42)
                         (tibetan-sentence--seg-nums-from-file tmp))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-sentence-seg-nums-from-file-empty ()
  "Returns nil when #+SEGMENTS: header is absent."
  (let ((tmp (make-temp-file "sent-segs-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert "no header\n"))
          (should (null (tibetan-sentence--seg-nums-from-file tmp))))
      (when (file-exists-p tmp) (delete-file tmp)))))

;; ============================================================================
;; FOLDER FILE-LIST TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-folder-sentence-files-sorted ()
  "Returns sent-NNN.org files sorted by numeric sentence-id."
  (let ((tmp-dir (make-temp-file "sent-folder-" t)))
    (unwind-protect
        (progn
          ;; Create files out of order, plus some non-sentence files.
          (dolist (n '(10 1 5 100 2))
            (with-temp-file (expand-file-name
                             (format "sent-%03d.org" n) tmp-dir)
              (insert "stub\n")))
          ;; Non-sentence files that must be filtered out.
          (with-temp-file (expand-file-name "seg-001.org" tmp-dir)
            (insert "stub\n"))
          (with-temp-file (expand-file-name "README.org" tmp-dir)
            (insert "stub\n"))
          (let ((files (tibetan-sentence--folder-sentence-files tmp-dir)))
            (should (= 5 (length files)))
            (should (equal '(1 2 5 10 100)
                           (mapcar #'tibetan-sentence--sent-id-from-filename
                                   files)))
            ;; No seg- or README files present.
            (should-not (cl-some (lambda (f)
                                   (string-match-p "seg-\\|README"
                                                   (file-name-nondirectory f)))
                                 files))))
      (when (file-directory-p tmp-dir)
        (delete-directory tmp-dir t)))))

(ert-deftest tibetan-sentence-folder-sentence-files-empty ()
  "Returns nil for an empty folder."
  (let ((tmp-dir (make-temp-file "sent-empty-" t)))
    (unwind-protect
        (should (null (tibetan-sentence--folder-sentence-files tmp-dir)))
      (when (file-directory-p tmp-dir)
        (delete-directory tmp-dir t)))))

;; ============================================================================
;; REGENERATE — preservation contract
;; ============================================================================
;;
;; This is the most important behavioural test in the file: re-analysis
;; MUST update the structural sections (#+SEGMENTS, #+TIBETAN_HASH,
;; * Tibetan Text, * Wylie) and MUST preserve the user-owned ones
;; (My Notes, Working Translation, Footnotes) and the third-level
;; translation bodies (Roehrich, Class Translation, Claude *).

(ert-deftest tibetan-sentence-regenerate-preserves-user-content ()
  "Re-analysing replaces the Tibetan/Wylie text but keeps user sections."
  (tibetan-sentence-test--with-source-buffer
   tibetan-sentence-test--section-wrap-buffer
   ;; Step 1: create the sent-001 analysis file.
   (re-search-forward "^\\*\\*\\* Sentence 1" nil t)
   (let* ((data1 (tibetan-sentence--collect-current-sentence))
          (path  (tibetan-sentence--create-file
                  (plist-get data1 :sent-num)
                  (plist-get data1 :seg-nums)
                  (plist-get data1 :tibetan-text)
                  (buffer-file-name))))
     ;; Step 2: simulate user edits — overwrite the placeholders.
     (with-temp-file path
       (insert-file-contents path)
       (goto-char (point-min))
       ;; My Notes
       (when (re-search-forward "^\\* My Notes$" nil t)
         (forward-line 1)
         (insert "These are my notes — keep me.\n"))
       ;; Working Translation
       (goto-char (point-min))
       (when (re-search-forward "^\\* Working Translation$" nil t)
         (forward-line 1)
         (insert "Draft translation — keep me.\n"))
       ;; Roehrich (3rd-level)
       (goto-char (point-min))
       (when (re-search-forward "^\\*\\*\\* Roehrich$" nil t)
         (forward-line 1)
         ;; Replace the placeholder line.
         (delete-region (point) (line-end-position))
         (insert "Roehrich English text — keep me.")))

     ;; Step 3: edit source — change the second segment's text.
     (goto-char (point-min))
     (re-search-forward "^Second clause$" nil t)
     (replace-match "Second clause REVISED")
     (set-buffer-modified-p nil)
     ;; Re-collect post-edit and regenerate the sent file.  Compute the
     ;; expected hash NOW, while we're still in the source buffer with
     ;; the post-edit data2 in hand.
     (goto-char (point-min))
     (re-search-forward "^\\*\\*\\* Sentence 1" nil t)
     (let* ((data2 (tibetan-sentence--collect-current-sentence))
            (expected-hash
             (tibetan-sentence--compute-hash
              (plist-get data2 :tibetan-text))))
       (tibetan-sentence--regenerate
        path
        (plist-get data2 :sent-num)
        (plist-get data2 :seg-nums)
        (plist-get data2 :tibetan-text))

       ;; Close the buffer that --regenerate opened, then read fresh.
       (let ((open-buf (get-file-buffer path)))
         (when open-buf
           (with-current-buffer open-buf (set-buffer-modified-p nil))
           (kill-buffer open-buf)))
       (with-temp-buffer
         (insert-file-contents path)
         (let ((all (buffer-string)))
           ;; Structural updates landed:
           (should (string-match-p "Second clause REVISED" all))
           ;; User content preserved:
           (should (string-match-p "These are my notes — keep me\\." all))
           (should (string-match-p "Draft translation — keep me\\." all))
           (should (string-match-p "Roehrich English text — keep me\\." all))
           ;; #+TIBETAN_HASH was refreshed (must match new concatenated text).
           (should (string-match-p
                    (format "^#\\+TIBETAN_HASH: %s$" expected-hash)
                    all))))))))

;; ============================================================================
;; Layout migration — old `* Auto-Analysis' shape → new `* Tibetan Analysis'
;; (2026-05-18, segment-§5.18 alignment for sentence files)
;; ============================================================================
;;
;; Existing sent-NNN.org files were generated before the alignment.
;; They carry the legacy shape:
;;
;;   * Tibetan Text
;;   * Auto-Analysis
;;     ** … parser body …
;;   * Provided Translations              (top-level — sentence-only design)
;;     *** Roehrich
;;     *** Class Translation
;;     *** Claude Translation             (sentence-level Claude lived here)
;;     *** Claude Grammar
;;     *** Claude Context
;;   * Working Translation                (at BOTTOM)
;;   * My Notes                           (at BOTTOM)
;;   * Footnotes                          (at BOTTOM)
;;
;; On first regenerate post-alignment, the file should be rewritten
;; into the new shape:
;;
;;   * My Notes                           (moved to TOP)
;;   * Working Translation                (moved to TOP)
;;   * Tibetan Text
;;   * Tibetan Analysis                   (parent renamed)
;;     ** … parser body …
;;     ** Translation                     (was *** Claude Translation)
;;     ** Grammar
;;       *** Claude Grammar               (preserved)
;;     ** Provided Translations           (NESTED now, was top-level)
;;       *** Roehrich                     (preserved body)
;;       *** Class Translation            (preserved body)
;;       *** Claude Context               (preserved body)
;;   * Footnotes                          (stays at bottom)
;;
;; Preservation invariant:  user-written bodies (Roehrich / Class
;; Translation / Claude Context / My Notes / Working Translation /
;; Footnotes) survive verbatim across the migration.

(ert-deftest tibetan-sentence-regenerate-migrates-auto-analysis-heading ()
  "Legacy `* Auto-Analysis' parent → new `* Tibetan Analysis'.
The rename is idempotent (re-running on already-migrated file is
a no-op for this assertion)."
  (skip-unless (fboundp 'tibetan-sentence--regenerate))
  (let* ((dir (make-temp-file "ttest-sent-migrate-" t))
         (path (expand-file-name "sent-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file path
            (insert "#+TITLE: Sentence 1 Analysis\n"
                    "#+SEGMENTS: 1\n"
                    "#+TIBETAN_HASH: oldhash\n"
                    "#+CREATED: 2026-01-01\n"
                    "#+LAST_ANALYZED: 2026-01-01\n\n"
                    "* Tibetan Text\nold text\n\n"
                    "* Auto-Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie Transliteration\nold wylie\n\n"
                    "* Working Translation\nWT body\n"
                    "* My Notes\nMN body\n"
                    "* Footnotes\nFN body\n"))
          (tibetan-sentence--regenerate path 1 '(1) "བདག")
          ;; Close the buffer regenerate opened.
          (let ((b (get-file-buffer path)))
            (when b
              (with-current-buffer b (set-buffer-modified-p nil))
              (kill-buffer b)))
          (with-temp-buffer
            (insert-file-contents path)
            (let ((s (buffer-string)))
              (should (string-match-p "^\\* Tibetan Analysis$" s))
              (should-not (string-match-p "^\\* Auto-Analysis$" s)))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-regenerate-moves-user-sections-to-top ()
  "Legacy layout has * Working Translation / * My Notes at the
BOTTOM (after * Provided Translations).  After regenerate they
appear ABOVE * Tibetan Text (matching segment §5.18 ordering),
with their bodies preserved verbatim."
  (skip-unless (fboundp 'tibetan-sentence--regenerate))
  (let* ((dir (make-temp-file "ttest-sent-top-" t))
         (path (expand-file-name "sent-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file path
            (insert "#+TITLE: Sentence 1 Analysis\n"
                    "#+SEGMENTS: 1\n"
                    "#+TIBETAN_HASH: oldhash\n"
                    "#+CREATED: 2026-01-01\n"
                    "#+LAST_ANALYZED: 2026-01-01\n\n"
                    "* Tibetan Text\nold text\n\n"
                    "* Auto-Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie\nold wylie\n\n"
                    "* Provided Translations\n"
                    "*** Roehrich\nRoehrich body\n"
                    "*** Class Translation\nClass body\n"
                    "*** Claude Translation\nClaude trans body\n\n"
                    "* Working Translation\nUSER-WT keep me\n\n"
                    "* My Notes\nUSER-MN keep me\n\n"
                    "* Footnotes\nUSER-FN keep me\n"))
          (tibetan-sentence--regenerate path 1 '(1) "བདག")
          (let ((b (get-file-buffer path)))
            (when b
              (with-current-buffer b (set-buffer-modified-p nil))
              (kill-buffer b)))
          (with-temp-buffer
            (insert-file-contents path)
            (let* ((s (buffer-string))
                   (mn-pos (string-match "^\\* My Notes$" s))
                   (wt-pos (string-match "^\\* Working Translation$" s))
                   (tt-pos (string-match "^\\* Tibetan Text$" s))
                   (fn-pos (string-match "^\\* Footnotes$" s)))
              ;; Both moved ABOVE Tibetan Text.
              (should (and mn-pos wt-pos tt-pos))
              (should (< mn-pos tt-pos))
              (should (< wt-pos tt-pos))
              ;; Footnotes is below everything else.
              (should (and fn-pos (> fn-pos tt-pos)))
              ;; User content preserved.
              (should (string-match-p "USER-WT keep me" s))
              (should (string-match-p "USER-MN keep me" s))
              (should (string-match-p "USER-FN keep me" s)))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-regenerate-nests-provided-translations ()
  "Legacy top-level `* Provided Translations' → nested
`** Provided Translations' inside `* Tibetan Analysis'.  No more
top-level Provided Translations block."
  (skip-unless (fboundp 'tibetan-sentence--regenerate))
  (let* ((dir (make-temp-file "ttest-sent-nest-" t))
         (path (expand-file-name "sent-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file path
            (insert "#+TITLE: Sentence 1 Analysis\n"
                    "#+SEGMENTS: 1\n"
                    "#+TIBETAN_HASH: oldhash\n"
                    "#+CREATED: 2026-01-01\n"
                    "#+LAST_ANALYZED: 2026-01-01\n\n"
                    "* Tibetan Text\nold\n\n"
                    "* Auto-Analysis\n** Wylie\nx\n\n"
                    "* Provided Translations\n"
                    "*** Roehrich\nROEHRICH-BODY\n\n"
                    "*** Class Translation\nCLASS-BODY\n\n"
                    "*** Claude Context\nCONTEXT-BODY\n\n"
                    "* Working Translation\n\n* My Notes\n\n* Footnotes\n"))
          (tibetan-sentence--regenerate path 1 '(1) "བདག")
          (let ((b (get-file-buffer path)))
            (when b
              (with-current-buffer b (set-buffer-modified-p nil))
              (kill-buffer b)))
          (with-temp-buffer
            (insert-file-contents path)
            (let ((s (buffer-string)))
              ;; No top-level Provided Translations.
              (should-not (string-match-p "^\\* Provided Translations$" s))
              ;; Nested Provided Translations exists (level-2).
              (should (string-match-p "^\\*\\* Provided Translations$" s))
              ;; Level-3 entries with their bodies preserved.
              (should (string-match-p "ROEHRICH-BODY" s))
              (should (string-match-p "CLASS-BODY" s))
              (should (string-match-p "CONTEXT-BODY" s)))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-regenerate-promotes-claude-translation-to-level-2 ()
  "Legacy `*** Claude Translation' (level-3 under top-level
* Provided Translations) → `** Translation' (level-2 under
* Tibetan Analysis), body preserved verbatim.

This matches the segment §5.18 layout where the Claude
translation is the primary level-2 slot directly under the
analysis parent."
  (skip-unless (fboundp 'tibetan-sentence--regenerate))
  (let* ((dir (make-temp-file "ttest-sent-promote-" t))
         (path (expand-file-name "sent-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file path
            (insert "#+TITLE: Sentence 1 Analysis\n"
                    "#+SEGMENTS: 1\n"
                    "#+TIBETAN_HASH: oldhash\n"
                    "#+CREATED: 2026-01-01\n"
                    "#+LAST_ANALYZED: 2026-01-01\n\n"
                    "* Tibetan Text\nold\n\n"
                    "* Auto-Analysis\n** Wylie\nx\n\n"
                    "* Provided Translations\n"
                    "*** Roehrich\nR\n\n"
                    "*** Claude Translation\n"
                    "CLAUDE-TRANS-BODY: real sentence translation here.\n\n"
                    "*** Claude Grammar\nGRAMMAR-BODY\n\n"
                    "* Working Translation\n\n* My Notes\n\n* Footnotes\n"))
          (tibetan-sentence--regenerate path 1 '(1) "བདག")
          (let ((b (get-file-buffer path)))
            (when b
              (with-current-buffer b (set-buffer-modified-p nil))
              (kill-buffer b)))
          (with-temp-buffer
            (insert-file-contents path)
            (let ((s (buffer-string)))
              ;; Body preserved (regardless of which heading carries it).
              (should (string-match-p "CLAUDE-TRANS-BODY" s))
              ;; Promoted to level-2 `** Translation' under
              ;; `* Tibetan Analysis'.
              (should (string-match-p "^\\*\\* Translation$" s))
              ;; The body lives under `** Translation' now (not
              ;; only as a leftover level-3 entry).
              (with-temp-buffer
                (insert s)
                (goto-char (point-min))
                (re-search-forward "^\\*\\* Translation$" nil t)
                (let ((trans-start (point))
                      (next-h2 (save-excursion
                                 (or (and (re-search-forward
                                           "^\\*\\* " nil t)
                                          (line-beginning-position))
                                     (point-max)))))
                  (let ((trans-body
                         (buffer-substring-no-properties
                          trans-start next-h2)))
                    (should (string-match-p "CLAUDE-TRANS-BODY" trans-body))))))))
      (delete-directory dir t))))

;; ============================================================================
;; CREATE-OPEN ROUNDTRIP — open-analysis happy path (no Claude)
;; ============================================================================
;;
;; We can't realistically run the interactive command end-to-end (it
;; opens a side window and dispatches gptel), but we can verify that
;; calling `tibetan-sentence-open-analysis' on a fresh buffer creates
;; the analysis file on disk.

(ert-deftest tibetan-sentence-open-analysis-creates-file ()
  "First call to `tibetan-sentence-open-analysis' creates sent-NNN.org.
We stub the gptel side effects and side-window display."
  (cl-letf* (((symbol-function 'display-buffer-in-side-window)
              (lambda (&rest _) nil))
             ((symbol-function 'tibetan-sentence--request-claude)
              (lambda (&rest _) nil)))
    (tibetan-sentence-test--with-source-buffer
     tibetan-sentence-test--section-wrap-buffer
     (re-search-forward "^\\*\\*\\*\\* Segment 1" nil t)
     (tibetan-sentence-open-analysis)
     (let ((path (tibetan-sentence--filepath 1)))
       (should (file-exists-p path))
       (with-temp-buffer
         (insert-file-contents path)
         (should (re-search-forward "^#\\+SEGMENTS: 1, 2$" nil t))))
     ;; Cleanup the buffer that open-analysis spawned.
     (let ((buf (get-file-buffer (tibetan-sentence--filepath 1))))
       (when buf
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf))))))

(ert-deftest tibetan-sentence-open-analysis-warns-on-stale-hash ()
  "Opening an existing file whose stored hash no longer matches emits a warning.
We capture the message via `current-message' after the call."
  (cl-letf* (((symbol-function 'display-buffer-in-side-window)
              (lambda (&rest _) nil))
             ((symbol-function 'tibetan-sentence--request-claude)
              (lambda (&rest _) nil)))
    (tibetan-sentence-test--with-source-buffer
     tibetan-sentence-test--section-wrap-buffer
     ;; Step 1: create the analysis file.
     (re-search-forward "^\\*\\*\\* Sentence 1" nil t)
     (tibetan-sentence-open-analysis)
     (let ((path (tibetan-sentence--filepath 1)))
       ;; Step 2: corrupt the source so hash will mismatch.
       (let ((buf (get-file-buffer path)))
         (when buf
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (goto-char (point-min))
       (re-search-forward "^Second clause$" nil t)
       (replace-match "Second clause MUTATED")
       (set-buffer-modified-p nil)
       ;; Step 3: re-open and look for the warning message.
       (let ((messages '()))
         (cl-letf (((symbol-function 'message)
                    (lambda (fmt &rest args)
                      (push (apply #'format fmt args) messages))))
           (goto-char (point-min))
           (re-search-forward "^\\*\\*\\* Sentence 1" nil t)
           (tibetan-sentence-open-analysis))
         (should (cl-some (lambda (m)
                            (string-match-p "WARNING.*has changed" m))
                          messages)))
       ;; Cleanup again.
       (let ((buf (get-file-buffer path)))
         (when buf
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))))))

;; ============================================================================
;; HEADLESS REANALYSIS DRY-RUN
;; ============================================================================

(ert-deftest tibetan-sentence-reanalyze-file-dry-run ()
  "Dry-run reports :ok t :dry-run t with the resolved seg-nums."
  (tibetan-sentence-test--with-source-buffer
   tibetan-sentence-test--section-wrap-buffer
   ;; Stub Claude to be safe.
   (cl-letf (((symbol-function 'display-buffer-in-side-window)
              (lambda (&rest _) nil))
             ((symbol-function 'tibetan-sentence--request-claude)
              (lambda (&rest _) nil)))
     ;; First create the file via the public command.
     (re-search-forward "^\\*\\*\\* Sentence 2" nil t)
     (tibetan-sentence-open-analysis)
     (let* ((path (tibetan-sentence--filepath 2))
            (result (tibetan-sentence-reanalyze-file
                     path
                     :source-file (buffer-file-name)
                     :dry-run t)))
       (should (plist-get result :ok))
       (should (plist-get result :dry-run))
       (should (= 2 (plist-get result :sent-id)))
       (should (equal '(3) (plist-get result :seg-nums))))
     (let ((buf (get-file-buffer (tibetan-sentence--filepath 2))))
       (when buf
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf))))))

(ert-deftest tibetan-sentence-reanalyze-file-bad-filename ()
  "Returns :ok nil with an :error string for a non-sentence filename."
  (let ((tmp (make-temp-file "not-a-sent-" nil ".org")))
    (unwind-protect
        (let ((r (tibetan-sentence-reanalyze-file tmp :dry-run t)))
          (should (null (plist-get r :ok)))
          (should (stringp (plist-get r :error))))
      (when (file-exists-p tmp) (delete-file tmp)))))

;; ============================================================================
;; RE-SEGMENTATION WORKFLOW TESTS
;; ============================================================================
;;
;; Coverage for the three commands behind `C-c s Z' (resegment):
;;
;;   - tibetan-sentence-archive-analysis-folder  moves sent-*.org
;;   - tibetan-sentence-create-all               scaffolds per sentence
;;   - tibetan-sentence-resegment                orchestrator
;;
;; All tests work in a freshly-created temp directory so we don't
;; touch the user's real `analysis/' folder.  `yes-or-no-p' is
;; stubbed where needed so the commands run unattended.

(defmacro tibetan-sentence-test--with-source-and-analysis
    (source-buf-var source-file-var folder-var &rest body)
  "Bind SOURCE-BUF-VAR, SOURCE-FILE-VAR and FOLDER-VAR for tests.

Creates:
  - A temp directory $TMPDIR/tibetan-resegment-XXXX/
  - A minimal source .org file at SOURCE-FILE-VAR inside that dir
  - An empty `analysis/' subdirectory at FOLDER-VAR
  - An open buffer on the source file bound to SOURCE-BUF-VAR

BODY runs with those bindings live; the fixture is cleaned up
afterwards (buffer killed, directory recursively deleted)."
  (declare (indent 3))
  `(let* ((root (make-temp-file "tibetan-resegment-" t))
          (,source-file-var (expand-file-name "source.org" root))
          (,folder-var (file-name-as-directory
                        (expand-file-name "analysis" root))))
     (make-directory ,folder-var t)
     (with-temp-file ,source-file-var
       (insert "#+TITLE: Test Source\n\n"
               "** Section\n"
               "*** Sentence 1\n"
               "**** Segment 1\n"
               "བདག་ནི་རྣལ་འབྱོར་པ།\n"
               "*** Sentence 2\n"
               "**** Segment 2\n"
               "མི་ལ་རས་པ།\n"
               "**** Segment 3\n"
               "ཞེས་གསུངས།\n"))
     (let ((,source-buf-var (find-file-noselect ,source-file-var)))
       (unwind-protect
           (progn ,@body)
         (when (buffer-live-p ,source-buf-var)
           (with-current-buffer ,source-buf-var
             (set-buffer-modified-p nil))
           (kill-buffer ,source-buf-var))
         ;; Kill any sent-NNN buffers the commands opened.
         (dolist (b (buffer-list))
           (when (and (buffer-file-name b)
                      (string-prefix-p root (buffer-file-name b)))
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b)))
         (delete-directory root t)))))

;; ---------------------------------------------------------------------------
;; archive-analysis-folder
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-sentence-archive-moves-all-sent-files ()
  "Every sent-*.org is moved into `archive/<stamp>/'; seg-*.org is left alone."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (with-temp-file (expand-file-name "sent-001.org" folder)
      (insert "sent-001 stub\n"))
    (with-temp-file (expand-file-name "sent-002.org" folder)
      (insert "sent-002 stub\n"))
    (with-temp-file (expand-file-name "seg-001.org" folder)
      (insert "seg-001 stub — must be preserved\n"))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (let ((archive (tibetan-sentence-archive-analysis-folder folder)))
        (should (stringp archive))
        (should (file-directory-p archive))
        (should-not (file-exists-p (expand-file-name "sent-001.org"
                                                     folder)))
        (should-not (file-exists-p (expand-file-name "sent-002.org"
                                                     folder)))
        (should (file-exists-p (expand-file-name "seg-001.org" folder)))
        (should (file-exists-p (expand-file-name "sent-001.org"
                                                 archive)))
        (should (file-exists-p (expand-file-name "sent-002.org"
                                                 archive)))))))

(ert-deftest tibetan-sentence-archive-empty-folder ()
  "Folder with no sent-*.org returns nil without creating archive/."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (let ((result (tibetan-sentence-archive-analysis-folder folder)))
      (should (null result))
      (should-not (file-directory-p (expand-file-name "archive" folder))))))

(ert-deftest tibetan-sentence-archive-cancel ()
  "User says no → sent-*.org files stay in place."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (with-temp-file (expand-file-name "sent-001.org" folder)
      (insert "sent-001\n"))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (let ((result (tibetan-sentence-archive-analysis-folder folder)))
        (should (null result))
        (should (file-exists-p (expand-file-name "sent-001.org"
                                                 folder)))))))

(ert-deftest tibetan-sentence-archive-timestamp-format ()
  "Archive subdir is `archive/YYYY-MM-DD-HHMMSS/'."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (with-temp-file (expand-file-name "sent-001.org" folder)
      (insert "sent-001\n"))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (let* ((archive (tibetan-sentence-archive-analysis-folder folder))
             (leaf (file-name-nondirectory
                    (directory-file-name archive))))
        (should (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}-[0-9]\\{6\\}\\'"
                                leaf))))))

;; ---------------------------------------------------------------------------
;; create-all
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-sentence-create-all-scaffolds-every-sentence ()
  "One sent-NNN.org per `*** Sentence N' heading."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (with-current-buffer source-buf
      (let ((result (tibetan-sentence-create-all)))
        (should (= 2 (plist-get result :total)))
        (should (= 2 (plist-get result :created)))
        (should (= 0 (plist-get result :skipped)))
        (should (= 0 (plist-get result :failed)))
        (should (file-exists-p (expand-file-name "sent-001.org"
                                                 folder)))
        (should (file-exists-p (expand-file-name "sent-002.org"
                                                 folder)))))))

(ert-deftest tibetan-sentence-create-all-skips-existing ()
  "Pre-existing sent-NNN.org is not clobbered; counts as skipped."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (let ((existing (expand-file-name "sent-001.org" folder)))
      (with-temp-file existing
        (insert "HAND-EDITED MARKER\n"))
      (with-current-buffer source-buf
        (let ((result (tibetan-sentence-create-all)))
          (should (= 2 (plist-get result :total)))
          (should (= 1 (plist-get result :created)))
          (should (= 1 (plist-get result :skipped)))))
      ;; Untouched.
      (with-temp-buffer
        (insert-file-contents existing)
        (should (string-match-p "HAND-EDITED MARKER" (buffer-string)))))))

(ert-deftest tibetan-sentence-create-all-errors-without-structure ()
  "Without `*** Sentence N' headings the command errors out."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (with-current-buffer source-buf
      (erase-buffer)
      (insert "* Bare file with no sentence headings\n"
              "*** Segment 1\nfoo\n")
      (save-buffer)
      (should-error (tibetan-sentence-create-all) :type 'user-error))))

(ert-deftest tibetan-sentence-create-all-seg-nums-match-children ()
  "Each created sent-NNN.org embeds the correct child segment numbers."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (with-current-buffer source-buf
      (tibetan-sentence-create-all))
    ;; sent-001 should cover Segment 1; sent-002 should cover 2 + 3.
    (let ((s1 (with-temp-buffer
                (insert-file-contents (expand-file-name "sent-001.org"
                                                        folder))
                (buffer-string)))
          (s2 (with-temp-buffer
                (insert-file-contents (expand-file-name "sent-002.org"
                                                        folder))
                (buffer-string))))
      ;; `#+SEGMENTS:' header is the sentence-layout marker.
      (should (string-match-p "#\\+SEGMENTS:[[:space:]]*1\\b" s1))
      (should (string-match-p "#\\+SEGMENTS:[[:space:]]*2[,[:space:]]+3" s2)))))

(ert-deftest tibetan-sentence--fire-claude-on-new-files-stubbed ()
  "`tibetan-sentence--fire-claude-on-new-files' calls
`tibetan-sentence--request-claude' once per non-empty plist.

Stubs `run-at-time' to execute the lambda immediately and
`tibetan-sentence--request-claude' to record its (tibetan, seg-nums,
filepath, source-file) arguments, then asserts all three calls happened
with the expected contents."
  (skip-unless (fboundp 'tibetan-sentence--fire-claude-on-new-files))
  (let ((captured '()))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_delay _repeat fn) (funcall fn)))
              ((symbol-function 'tibetan-sentence--request-claude)
               (lambda (tibetan seg-nums filepath source-file)
                 (push (list :tibetan tibetan
                             :seg-nums seg-nums
                             :filepath filepath
                             :source-file source-file)
                       captured))))
      (tibetan-sentence--fire-claude-on-new-files
       (list (list :sent-num 1 :seg-nums '(1 2) :tibetan "text one"
                   :filepath "/tmp/sent-001.org")
             (list :sent-num 2 :seg-nums '(3) :tibetan "text two"
                   :filepath "/tmp/sent-002.org"))
       "/tmp/source.org"))
    (setq captured (nreverse captured))
    (should (= 2 (length captured)))
    (should (equal "text one"           (plist-get (nth 0 captured) :tibetan)))
    (should (equal '(1 2)               (plist-get (nth 0 captured) :seg-nums)))
    (should (equal "/tmp/sent-001.org"  (plist-get (nth 0 captured) :filepath)))
    (should (equal "/tmp/source.org"    (plist-get (nth 0 captured) :source-file)))
    (should (equal "text two"           (plist-get (nth 1 captured) :tibetan)))))

(ert-deftest tibetan-sentence-create-all-fires-claude-on-new-files ()
  "After creating new sent-*.org, `create-all' queues a Claude request
for each one when `tibetan-auto-fire-claude-on-create' is non-nil.

Stubs `tibetan-sentence--fire-claude-on-new-files' directly so the
fixture doesn't need to reach into gptel.  Asserts:
  1. The fire helper was called exactly once (per create-all run).
  2. The plist list length matches the number of newly-created files.
  3. Pre-existing files are NOT passed to the fire helper."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    ;; Pre-create sent-001.org to force a skip; sent-002 will be new.
    (with-temp-file (expand-file-name "sent-001.org" folder)
      (insert "pre-existing sent-001\n"))
    (let ((fire-calls '()))
      (cl-letf (((symbol-function 'tibetan-sentence--fire-claude-on-new-files)
                 (lambda (plists _source)
                   (push plists fire-calls))))
        (with-current-buffer source-buf
          (tibetan-sentence-create-all))
        (should (= 1 (length fire-calls)))
        (let ((plists (car fire-calls)))
          (should (= 1 (length plists)))
          (should (equal 2 (plist-get (car plists) :sent-num))))))))

(ert-deftest tibetan-sentence-create-all-skips-claude-when-gated-off ()
  "With `tibetan-auto-fire-claude-on-create' set to nil the fire
helper is NOT called — preserving the old structure-only behaviour
for users who want a two-step flow."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (let ((fire-calls 0))
      (cl-letf (((symbol-function 'tibetan-sentence--fire-claude-on-new-files)
                 (lambda (&rest _) (setq fire-calls (1+ fire-calls))))
                (tibetan-auto-fire-claude-on-create nil))
        (with-current-buffer source-buf
          (tibetan-sentence-create-all))
        (should (zerop fire-calls))))))

(ert-deftest tibetan-sentence-create-all-skips-segment-subsections ()
  "Sibling subsections like `**** Working Translation' inside a segment
must NOT leak into the sentence's concatenated Tibetan text.

Regression for a bug spotted on Milarepa 2026-04-20: the body-end
detector was anchored on the next `**** Segment' heading, so any
`**** Working Translation' or similar sibling under a segment would
be scooped into the segment's body.  The fix stops at any Org
heading (`^\\*+ ')."
  (let* ((root (make-temp-file "tibetan-wt-leak-" t))
         (source-file (expand-file-name "source.org" root))
         (folder (file-name-as-directory
                  (expand-file-name "analysis" root))))
    (make-directory folder t)
    (with-temp-file source-file
      (insert "#+TITLE: WT leak test\n\n"
              "** Section\n"
              "*** Sentence 1\n"
              "**** Segment 1\n"
              "TIBETAN-SEG-1\n"
              "\n"
              "**** Working Translation\n"
              "ENGLISH-WT-1\n"
              "\n"
              "**** Segment 2\n"
              "TIBETAN-SEG-2\n"
              "\n"
              "**** Working Translation\n"
              "ENGLISH-WT-2\n"))
    (let ((buf (find-file-noselect source-file)))
      (unwind-protect
          (with-current-buffer buf
            (tibetan-sentence-create-all)
            (let ((s (with-temp-buffer
                       (insert-file-contents
                        (expand-file-name "sent-001.org" folder))
                       (buffer-string))))
              (should (string-match-p "TIBETAN-SEG-1" s))
              (should (string-match-p "TIBETAN-SEG-2" s))
              ;; Working-Translation body lines must NOT be part of
              ;; the sentence's Tibetan text.
              (should-not (string-match-p "ENGLISH-WT-1" s))
              (should-not (string-match-p "ENGLISH-WT-2" s))
              ;; And the subheading itself must not show up in the
              ;; Tibetan Text section either.
              (should-not (string-match-p "^\\*\\*\\*\\* Working Translation"
                                          s))))
        (when (buffer-live-p buf)
          (with-current-buffer buf (set-buffer-modified-p nil))
          (kill-buffer buf))
        (dolist (b (buffer-list))
          (when (and (buffer-file-name b)
                     (string-prefix-p root (buffer-file-name b)))
            (with-current-buffer b (set-buffer-modified-p nil))
            (kill-buffer b)))
        (delete-directory root t)))))

;; ---------------------------------------------------------------------------
;; resegment orchestrator
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-sentence-resegment-cancellation-is-noop ()
  "If the top-level yes-or-no-p returns nil nothing changes."
  (tibetan-sentence-test--with-source-and-analysis
      source-buf source-file folder
    (with-temp-file (expand-file-name "sent-001.org" folder)
      (insert "OLD\n"))
    (with-current-buffer source-buf
      (let ((snapshot (buffer-string)))
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
          (tibetan-sentence-resegment))
        ;; Source buffer unchanged.
        (should (string= snapshot (buffer-string)))
        ;; sent-001.org still there in the folder root (not archived).
        (should (file-exists-p (expand-file-name "sent-001.org" folder)))))))

(ert-deftest tibetan-sentence-resegment-requires-source-file ()
  "Running in a buffer without `buffer-file-name' errors out."
  (with-temp-buffer
    (insert "no file here\n")
    (should-error (tibetan-sentence-resegment) :type 'user-error)))

;; ----------------------------------------------------------------------------
;; §5.22 Commit 2/5 (2026-05-21):  dynamic strip-list extension.
;; `tibetan-sentence--segment-claude-sections' converts from defconst
;; to a defun accessor that consults the dynamic var
;; `tibetan-sentence--compressed-for-render'.  When the var is non-nil
;; the accessor returns the compressed strip-list (7 heavy/reference
;; sections to drop);  when nil it returns the empty list (existing
;; backwards-compatible behaviour).
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-sentence-segment-claude-sections-full-mode-list ()
  "§5.22 follow-up (2026-05-21):  with `--compressed-for-render'
unset (full-layout default), the accessor returns the always-
strip list — `(\"** Detailed Dictionary\")'.  DD is dropped
from sentence files regardless of compressed flag (DD bloats
multi-segment sentence files;  per-segment seg-NNN.org files
keep it as the dictionary reference).

Pre-§5.22-follow-up:  accessor returned `'()' in full mode."
  (should (fboundp 'tibetan-sentence--segment-claude-sections))
  (let ((tibetan-sentence--compressed-for-render nil))
    (should (equal (tibetan-sentence--segment-claude-sections)
                   '("** Detailed Dictionary")))))

(ert-deftest tibetan-sentence-segment-claude-sections-compressed-list ()
  "With `tibetan-sentence--compressed-for-render' bound to a truthy
value, the accessor returns the compressed strip-list:  7 heavy /
reference level-2 sections that get dropped from the embedded
segment output before the sentence file is written.

Sections that STAY in compressed mode (kept implicitly by NOT being
in the strip list):
  · ** Claude Vocabulary
  · ** Translation
  · ** Grammar
  · ** Provided Translations
  · (any other future section a renderer might emit)"
  (let ((tibetan-sentence--compressed-for-render t))
    (let ((strip (tibetan-sentence--segment-claude-sections)))
      (should (listp strip))
      (should (= 7 (length strip)))
      (should (member "** Wylie Transliteration" strip))
      (should (member "** Phonetics" strip))
      (should (member "** Interlinear Gloss" strip))
      (should (member "** DharmaMitra Translation" strip))
      (should (member "** Sentence Structure" strip))
      (should (member "** Verb Classification (Hill 2010)" strip))
      (should (member "** Detailed Dictionary" strip))
      ;; Kept sections must NOT be in the strip list.
      (should-not (member "** Claude Vocabulary" strip))
      (should-not (member "** Translation" strip))
      (should-not (member "** Grammar" strip))
      (should-not (member "** Provided Translations" strip)))))

(ert-deftest tibetan-sentence-toggle-source-compressed-adds-and-removes ()
  "`tibetan-sentence-toggle-source-compressed' adds the header on a
file that doesn't have it (or has a falsy value) and removes it
on a file that has a truthy value.  Idempotent — running the
toggle twice returns the file to its original state."
  (should (fboundp 'tibetan-sentence-toggle-source-compressed))
  (let* ((dir (make-temp-file "sent-toggle-" t))
         (source-file (expand-file-name "source.org" dir)))
    (unwind-protect
        (progn
          ;; Initial state:  no header.
          (with-temp-file source-file
            (insert "#+TITLE: T\n#+ANALYSIS_VERSION: 1.0\n\n* Tibetan Text\n"))
          ;; First toggle:  header added with value `t'.
          (tibetan-sentence-toggle-source-compressed source-file)
          (let ((post (with-temp-buffer
                        (insert-file-contents source-file)
                        (buffer-string))))
            (should (string-match-p
                     "^#\\+TIBETAN_SENTENCE_COMPRESSED: t$" post))
            ;; Metadata reader sees it as truthy.
            (should (plist-get
                     (tibetan-analysis--read-source-metadata source-file)
                     :sentence-compressed)))
          ;; Second toggle:  header removed.
          (tibetan-sentence-toggle-source-compressed source-file)
          (let ((post (with-temp-buffer
                        (insert-file-contents source-file)
                        (buffer-string))))
            (should-not (string-match-p
                         "^#\\+TIBETAN_SENTENCE_COMPRESSED:" post))
            (should-not (plist-get
                         (tibetan-analysis--read-source-metadata source-file)
                         :sentence-compressed))
            ;; Other headers unaffected — `#+TITLE:' and
            ;; `#+ANALYSIS_VERSION:' survive the toggle.
            (should (string-match-p "^#\\+TITLE: T$" post))
            (should (string-match-p "^#\\+ANALYSIS_VERSION: 1\\.0$"
                                    post)))
          ;; Third toggle:  header added again.  Confirms idempotent
          ;; round-trip.
          (tibetan-sentence-toggle-source-compressed source-file)
          (let ((post (with-temp-buffer
                        (insert-file-contents source-file)
                        (buffer-string))))
            (should (plist-get
                     (tibetan-analysis--read-source-metadata source-file)
                     :sentence-compressed))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-create-file-honours-compressed-header ()
  "End-to-end:  source file carries `#+TIBETAN_SENTENCE_COMPRESSED: t';
`tibetan-sentence--create-file' writes a sent-NNN.org whose
`* Tibetan Analysis' body has ONLY the 4 kept level-2 sections
plus the 3 sentence-only L3 extras under `** Provided
Translations'.

Stubs `tibetan-analysis-generate-content' to return a fixed
11-section blob so the test doesn't depend on the renderer's
real output (which varies with vocab DB state)."
  (let* ((dir (make-temp-file "sent-compressed-" t))
         (source-file (expand-file-name "source.org" dir))
         (analysis-folder (expand-file-name "analysis" dir)))
    (unwind-protect
        (progn
          (make-directory analysis-folder)
          (with-temp-file source-file
            (insert "#+TITLE: T\n#+TIBETAN_SENTENCE_COMPRESSED: t\n"))
          (cl-letf
              (((symbol-function 'tibetan-analysis-generate-content)
                (lambda (&rest _args)
                  (concat
                   "** Wylie Transliteration\nfoo\n\n"
                   "** Phonetics\nfu\n\n"
                   "** Interlinear Gloss\nfoo bar\n\n"
                   "** Claude Vocabulary\nfoo = thing\n\n"
                   "** Translation\nThe thing.\n\n"
                   "** DharmaMitra Translation\nThe thing (DM).\n\n"
                   "** Grammar\n*** Particles\n=ERG=\n\n"
                   "** Sentence Structure\n[clauses]\n\n"
                   "** Verb Classification (Hill 2010)\n[verbs]\n\n"
                   "** Provided Translations\n\n\n"
                   "** Detailed Dictionary\n[deep]\n")))
               ((symbol-function 'tibetan-analysis--filter-to-tibetan-lines)
                (lambda (text) text))
               ((symbol-function 'tibetan-sentence--filepath)
                (lambda (n)
                  (expand-file-name
                   (format "sent-%03d.org" n) analysis-folder))))
            (tibetan-sentence--create-file 1 '(1) "བདུད།" source-file))
          (let ((out (with-temp-buffer
                       (insert-file-contents
                        (expand-file-name "sent-001.org" analysis-folder))
                       (buffer-string))))
            ;; Kept sections present.
            (should (string-match-p "^\\*\\* Claude Vocabulary$" out))
            (should (string-match-p "^\\*\\* Translation$" out))
            (should (string-match-p "^\\*\\* Grammar$" out))
            (should (string-match-p "^\\*\\* Provided Translations$" out))
            ;; Dropped sections absent.
            (should-not (string-match-p "^\\*\\* Wylie Transliteration$" out))
            (should-not (string-match-p "^\\*\\* Phonetics$" out))
            (should-not (string-match-p "^\\*\\* Interlinear Gloss$" out))
            (should-not (string-match-p "^\\*\\* DharmaMitra Translation$"
                                        out))
            (should-not (string-match-p "^\\*\\* Sentence Structure$" out))
            (should-not (string-match-p
                         "^\\*\\* Verb Classification (Hill 2010)$" out))
            (should-not (string-match-p "^\\*\\* Detailed Dictionary$" out))
            ;; Sentence-only L3 extras still injected under PT.
            (should (string-match-p "^\\*\\*\\* Roehrich$" out))
            (should (string-match-p "^\\*\\*\\* Class Translation$" out))
            (should (string-match-p "^\\*\\*\\* Claude Context$" out))
            ;; Top-level user + footer sections survive.
            (should (string-match-p "^\\* My Notes$" out))
            (should (string-match-p "^\\* Working Translation$" out))
            (should (string-match-p "^\\* Tibetan Text$" out))
            (should (string-match-p "^\\* Tibetan Analysis$" out))
            (should (string-match-p "^\\* Footnotes$" out))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-create-file-leaves-full-layout-without-header ()
  "Source file WITHOUT the `#+TIBETAN_SENTENCE_COMPRESSED:' header
produces the FULL sent-NNN.org layout — all the segment-renderer
level-2 sections survive EXCEPT `** Detailed Dictionary'.

§5.22 follow-up (2026-05-21):  DD is now always-stripped from
sentence files regardless of the compressed flag.  Rationale:
sentence files aggregate multiple segments → DD bloats to 20+
entries on a typical multi-segment sentence;  the per-segment
seg-NNN.org files already carry those entries for prep-time
lookup, and the sentence file is for flow reading not deep
dictionary work.

Per-segment seg-NNN.org files are UNAFFECTED — they still carry
the full DD as the bottom section of `* Tibetan Analysis'."
  (let* ((dir (make-temp-file "sent-full-" t))
         (source-file (expand-file-name "source.org" dir))
         (analysis-folder (expand-file-name "analysis" dir)))
    (unwind-protect
        (progn
          (make-directory analysis-folder)
          ;; No `#+TIBETAN_SENTENCE_COMPRESSED:' header at all.
          (with-temp-file source-file
            (insert "#+TITLE: T\n"))
          (cl-letf
              (((symbol-function 'tibetan-analysis-generate-content)
                (lambda (&rest _args)
                  (concat
                   "** Wylie Transliteration\nfoo\n\n"
                   "** Phonetics\nfu\n\n"
                   "** Interlinear Gloss\nfoo bar\n\n"
                   "** Claude Vocabulary\nfoo = thing\n\n"
                   "** Translation\nThe thing.\n\n"
                   "** DharmaMitra Translation\nThe thing (DM).\n\n"
                   "** Grammar\n*** Particles\n=ERG=\n\n"
                   "** Sentence Structure\n[clauses]\n\n"
                   "** Verb Classification (Hill 2010)\n[verbs]\n\n"
                   "** Provided Translations\n\n\n"
                   "** Detailed Dictionary\n[deep]\n")))
               ((symbol-function 'tibetan-analysis--filter-to-tibetan-lines)
                (lambda (text) text))
               ((symbol-function 'tibetan-sentence--filepath)
                (lambda (n)
                  (expand-file-name
                   (format "sent-%03d.org" n) analysis-folder))))
            (tibetan-sentence--create-file 2 '(2) "བདུད།" source-file))
          (let ((out (with-temp-buffer
                       (insert-file-contents
                        (expand-file-name "sent-002.org" analysis-folder))
                       (buffer-string))))
            ;; All segment-renderer level-2 sections survive EXCEPT
            ;; `** Detailed Dictionary' — always-stripped from
            ;; sentence files per §5.22 follow-up (2026-05-21).
            (should (string-match-p "^\\*\\* Wylie Transliteration$" out))
            (should (string-match-p "^\\*\\* Phonetics$" out))
            (should (string-match-p "^\\*\\* Interlinear Gloss$" out))
            (should (string-match-p "^\\*\\* Claude Vocabulary$" out))
            (should (string-match-p "^\\*\\* Translation$" out))
            (should (string-match-p "^\\*\\* DharmaMitra Translation$" out))
            (should (string-match-p "^\\*\\* Grammar$" out))
            (should (string-match-p "^\\*\\* Sentence Structure$" out))
            (should (string-match-p
                     "^\\*\\* Verb Classification (Hill 2010)$" out))
            (should (string-match-p "^\\*\\* Provided Translations$" out))
            ;; Detailed Dictionary is ALWAYS dropped from sentence
            ;; files — even in non-compressed (full) mode.
            (should-not (string-match-p "^\\*\\* Detailed Dictionary$" out))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-strip-always-drops-detailed-dictionary ()
  "§5.22 follow-up (2026-05-21):  `** Detailed Dictionary' is in the
sentence-stripper's filter list regardless of the compressed
flag — sentence files never carry DD.  Per-segment seg-NNN.org
files keep DD;  this is a sentence-renderer behaviour only.

Asserts the accessor returns DD on the list in BOTH modes."
  (let ((tibetan-sentence--compressed-for-render nil))
    (should (member "** Detailed Dictionary"
                    (tibetan-sentence--segment-claude-sections))))
  (let ((tibetan-sentence--compressed-for-render t))
    (should (member "** Detailed Dictionary"
                    (tibetan-sentence--segment-claude-sections)))))

(ert-deftest tibetan-sentence-strip-compresses-when-flag-set ()
  "`tibetan-sentence--strip-segment-claude-sections' filters the heavy
sections out of segment-renderer content when the compressed flag is
set, and drops only `** Detailed Dictionary' in full mode (§5.22
follow-up, 2026-05-21:  DD is always-stripped from sentence files).

Compressed-mode test:  build a content blob with all 11 level-2
sections, assert post-filter only 4 remain (Vocab + Translation +
Grammar + Provided Translations).  Full-mode test:  same input,
assert all 11 EXCEPT `** Detailed Dictionary' still present."
  (let ((content
         (concat
          "** Wylie Transliteration\nfoo\n\n"
          "** Phonetics\nfu\n\n"
          "** Interlinear Gloss\nfoo bar\n\n"
          "** Claude Vocabulary\nfoo = thing\n\n"
          "** Translation\nThe thing.\n\n"
          "** DharmaMitra Translation\nThe thing (DM).\n\n"
          "** Grammar\n*** Particles\n=ERG=\n\n"
          "** Sentence Structure\n[clauses]\n\n"
          "** Verb Classification (Hill 2010)\n[verbs]\n\n"
          "** Provided Translations\n\n\n"
          "** Detailed Dictionary\n[deep]\n")))
    ;; Compressed mode — only the 4 kept sections survive.
    (let* ((tibetan-sentence--compressed-for-render t)
           (out (tibetan-sentence--strip-segment-claude-sections content)))
      (should (string-match-p "^\\*\\* Claude Vocabulary$" out))
      (should (string-match-p "^\\*\\* Translation$" out))
      (should (string-match-p "^\\*\\* Grammar$" out))
      (should (string-match-p "^\\*\\* Provided Translations$" out))
      (should-not (string-match-p "^\\*\\* Wylie Transliteration$" out))
      (should-not (string-match-p "^\\*\\* Phonetics$" out))
      (should-not (string-match-p "^\\*\\* Interlinear Gloss$" out))
      (should-not (string-match-p "^\\*\\* DharmaMitra Translation$" out))
      (should-not (string-match-p "^\\*\\* Sentence Structure$" out))
      (should-not (string-match-p
                   "^\\*\\* Verb Classification (Hill 2010)$" out))
      (should-not (string-match-p "^\\*\\* Detailed Dictionary$" out)))
    ;; Full mode (default) — all 11 sections pass through EXCEPT
    ;; `** Detailed Dictionary' (always-stripped per §5.22 follow-up).
    (let* ((tibetan-sentence--compressed-for-render nil)
           (out (tibetan-sentence--strip-segment-claude-sections content)))
      (should (string-match-p "^\\*\\* Wylie Transliteration$" out))
      (should (string-match-p "^\\*\\* Phonetics$" out))
      (should (string-match-p "^\\*\\* Interlinear Gloss$" out))
      (should (string-match-p "^\\*\\* Claude Vocabulary$" out))
      (should (string-match-p "^\\*\\* Translation$" out))
      (should (string-match-p "^\\*\\* DharmaMitra Translation$" out))
      (should (string-match-p "^\\*\\* Grammar$" out))
      (should (string-match-p "^\\*\\* Sentence Structure$" out))
      (should (string-match-p
               "^\\*\\* Verb Classification (Hill 2010)$" out))
      (should (string-match-p "^\\*\\* Provided Translations$" out))
      (should-not (string-match-p "^\\*\\* Detailed Dictionary$" out)))))

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(defun tibetan-sentence-persist-run-tests ()
  "Run all Tibetan sentence-persist tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-sentence-"))

(provide 'tibetan-sentence-persist-test)
;;; tibetan-sentence-persist-test.el ends here
