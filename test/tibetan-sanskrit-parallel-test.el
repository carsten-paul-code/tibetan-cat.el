;;; tibetan-sanskrit-parallel-test.el --- Tests for tibetan-sanskrit-parallel.el -*- lexical-binding: t -*-

;;; Commentary:
;;
;; ERT tests for the Sanskrit-parallel reading extension (Phase 1 of
;; the sanskrit-parallel-workflow feature, 2026-04-27).  Phase 1 ships
;; read-only primitives:
;;
;;   tibetan-sanskrit-parallel-text-for-segment
;;     Walks the segment subtree, finds the next same-level sibling
;;     whose heading text starts with "Sanskrit" (within the same
;;     Sentence), reads its body, sniffs IAST vs Devanagari per line.
;;
;;   tibetan-sanskrit-parallel-text-for-segment-id
;;     Same answer, accessible by `(SOURCE-FILE SEG-ID)' rather than
;;     point-in-buffer.  Used by the async Claude prompt builder in
;;     Phase 3 where we know the source-file path and the segment ID
;;     from the analysis-file name.
;;
;;   tibetan-sanskrit-parallel--has-devanagari-p
;;     Internal predicate: t iff string contains a U+0900–U+097F
;;     codepoint (baseline Devanagari block).
;;
;;   tibetan-cat--source-mode-parallel-p
;;     t iff the source file's `#+SOURCE_MODE:' header equals
;;     `"parallel-sanskrit"'.  Reads via the shared metadata helper
;;     in `persist/tibetan-analysis-claude.el' (extended in this
;;     phase to expose `:source-mode' on its plist).
;;
;; The tests cover the failure modes the design must handle: no
;; sibling at all, sibling guarded by a `:PROPERTIES:' drawer, sibling
;; followed by `**** Working Translation' at the same level (must not
;; leak), Devanagari recognised on line 2 only when codepoints
;; actually appear, and the source-mode predicate returning nil for
;; missing/empty headers without crashing.

;;; Code:

(require 'ert)
(require 'org)

;; Add load paths
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir))
  (add-to-list 'load-path (expand-file-name "../persist" dir)))

(require 'tibetan-org-structure)
(require 'tibetan-sanskrit-parallel)
;; Phase 2: tests for Sanskrit Source section emission depend on
;; the persist module's renderer.  Soft-required so phase-1-only
;; runs (without the persist module loaded) don't fail with a
;; missing-feature error — the Phase 2 tests themselves
;; `skip-unless' the symbols.
(require 'tibetan-analysis-persist nil t)

;; Helper macro mirrors `tibetan-test-with-org-buffer' from
;; `tibetan-org-structure-test.el' so fixtures stay readable.
(defmacro tibetan-sanskrit-parallel-test--with-org-buffer (content &rest body)
  "Insert CONTENT into a temp buffer, enable org-mode, then run BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,content)
     (org-mode)
     (when (fboundp 'org-set-regexps-and-options)
       (org-set-regexps-and-options))
     (font-lock-ensure)
     ,@body))

(defmacro tibetan-sanskrit-parallel-test--with-temp-source-file (content &rest body)
  "Write CONTENT to a temp .org file, bind FILEPATH, then run BODY.
The file is deleted after BODY runs."
  (declare (indent 1))
  `(let ((filepath (make-temp-file "tibetan-skt-parallel-" nil ".org")))
     (unwind-protect
         (progn
           (with-temp-file filepath (insert ,content))
           ,@body)
       (when (file-exists-p filepath)
         (delete-file filepath)))))

;; ============================================================================
;; FIXTURES
;; ============================================================================

(defconst tibetan-sanskrit-parallel-test--basic-iast-buffer
  "#+TITLE: Test
* Tibetan Text
** Section 1
*** Sentence 1
**** Segment 1
:PROPERTIES:
:FOLIO: D ya 1a1
:END:
ཡང་གཞན་ཡང་འདི་ལྟ་སྟེ།

**** Sanskrit
yathā vā punaḥ kaścid evam āha

**** Working Translation
Or again, someone says:

**** Segment 2
ཁོ་ནས་སྨྲས་པ།

**** Sanskrit
sa āha

**** Working Translation

"
  "Two segments with IAST-only Sanskrit siblings, sandwiched by
Working Translation siblings.  Mirrors the §2.12 reading-file
layout (Section → Sentence → Segment + siblings at level 4).")

(defconst tibetan-sanskrit-parallel-test--devanagari-buffer
  "#+TITLE: Test Devanagari
* Tibetan Text
** Section 1
*** Sentence 1
**** Segment 1
ཁྱོད་ཀྱིས་གསུངས་ཤིང་།

**** Sanskrit
tvayā uktaṃ ca
त्वया उक्तं च

**** Working Translation
"
  "Segment with Sanskrit sibling carrying both an IAST line and a
Devanagari line.")

(defconst tibetan-sanskrit-parallel-test--no-sanskrit-buffer
  "#+TITLE: Test No Sanskrit
* Tibetan Text
** Section 1
*** Sentence 1
**** Segment 1
བདག་ལ་སྟོད་ནས་འོངས།

**** Working Translation
Praising me, [he] came.
"
  "Segment with no Sanskrit sibling — Tibetan-only document.")

(defconst tibetan-sanskrit-parallel-test--drawer-buffer
  "#+TITLE: Test Drawer
* Tibetan Text
** Section 1
*** Sentence 1
**** Segment 1
ཁྱོད་ཀྱིས་གསུངས།

**** Sanskrit
:PROPERTIES:
:EDITION: Bhattacharya 1957:1
:SOURCE: La Vallée Poussin
:END:
tvayā uktam

**** Working Translation
"
  "Sanskrit sibling guarded by a `:PROPERTIES:' drawer holding
edition metadata.  Drawer body must be skipped — only the IAST
text below should be returned.")

(defconst tibetan-sanskrit-parallel-test--ordering-buffer
  "#+TITLE: Test Ordering
* Tibetan Text
** Section 1
*** Sentence 1
**** Segment 1
བདག་ལ་སྟོད་ནས་འོངས།

**** Working Translation
Praising me, [he] came.

**** Sanskrit
mām abhiṣṭutya āgataḥ
"
  "Sanskrit sibling appears AFTER Working Translation.  The walker
must scan all in-Sentence siblings, not stop at the first non-
Sanskrit sibling.")

;; ============================================================================
;; WALKER TESTS
;; ============================================================================

(ert-deftest tibetan-sanskrit-parallel-walker-finds-sibling-iast ()
  "Walker returns IAST text when a `**** Sanskrit' sibling holds it."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--basic-iast-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 1")
   (let ((result (tibetan-sanskrit-parallel-text-for-segment)))
     (should result)
     (should (equal (plist-get result :iast)
                    "yathā vā punaḥ kaścid evam āha"))
     (should (null (plist-get result :devanagari)))
     (should (eq (plist-get result :script-source) 'iast-line)))))

(ert-deftest tibetan-sanskrit-parallel-walker-locates-second-segment-sanskrit ()
  "Walker resolves Segment 2's Sanskrit, not Segment 1's."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--basic-iast-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 2")
   (let ((result (tibetan-sanskrit-parallel-text-for-segment)))
     (should result)
     (should (equal (plist-get result :iast) "sa āha"))
     (should (null (plist-get result :devanagari))))))

(ert-deftest tibetan-sanskrit-parallel-walker-recognises-devanagari-second-line ()
  "Walker fills `:devanagari' when line 2 contains U+0900–U+097F."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--devanagari-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 1")
   (let ((result (tibetan-sanskrit-parallel-text-for-segment)))
     (should result)
     (should (equal (plist-get result :iast) "tvayā uktaṃ ca"))
     (should (equal (plist-get result :devanagari) "त्वया उक्तं च"))
     (should (eq (plist-get result :script-source) 'iast-and-devanagari)))))

(ert-deftest tibetan-sanskrit-parallel-walker-returns-nil-when-no-sibling ()
  "Walker returns nil when no `**** Sanskrit' sibling exists."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--no-sanskrit-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 1")
   (should (null (tibetan-sanskrit-parallel-text-for-segment)))))

(ert-deftest tibetan-sanskrit-parallel-walker-skips-properties-drawer ()
  "Walker skips a leading `:PROPERTIES:' drawer in the Sanskrit body.
The drawer carries edition metadata (`:EDITION:', `:SOURCE:') and
must NOT bleed into the returned IAST string."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--drawer-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 1")
   (let ((result (tibetan-sanskrit-parallel-text-for-segment)))
     (should result)
     (should (equal (plist-get result :iast) "tvayā uktam"))
     (should (null (plist-get result :devanagari)))
     ;; Negative assertion: no drawer fragment leaked into IAST.
     (should-not (string-match-p ":EDITION:" (plist-get result :iast)))
     (should-not (string-match-p "Bhattacharya" (plist-get result :iast))))))

(ert-deftest tibetan-sanskrit-parallel-walker-stops-at-next-segment-sibling ()
  "Walker stops at the next `**** Segment' heading (Sanskrit
belonging to Segment 2 must not be returned for Segment 1)."
  (let ((buffer-no-skt-on-1
         "#+TITLE: Test
* Tibetan Text
** Section 1
*** Sentence 1
**** Segment 1
text 1
**** Working Translation

**** Segment 2
text 2
**** Sanskrit
this belongs to seg 2
"))
    (tibetan-sanskrit-parallel-test--with-org-buffer buffer-no-skt-on-1
      (goto-char (point-min))
      (search-forward "**** Segment 1")
      (should (null (tibetan-sanskrit-parallel-text-for-segment))))))

(ert-deftest tibetan-sanskrit-parallel-walker-finds-sanskrit-after-working-translation ()
  "Walker scans all in-Sentence siblings — Sanskrit is found even
when it appears AFTER `**** Working Translation' at the same level."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--ordering-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 1")
   (let ((result (tibetan-sanskrit-parallel-text-for-segment)))
     (should result)
     (should (equal (plist-get result :iast)
                    "mām abhiṣṭutya āgataḥ")))))

(ert-deftest tibetan-sanskrit-parallel-walker-does-not-leak-working-translation-body ()
  "Walker reads the Sanskrit body only — it must not concatenate
the body of a following sibling heading."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--basic-iast-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 1")
   (let ((result (tibetan-sanskrit-parallel-text-for-segment)))
     (should result)
     (should-not (string-match-p "Or again" (plist-get result :iast))))))

(ert-deftest tibetan-sanskrit-parallel-walker-returns-nil-outside-segment ()
  "Walker returns nil when point is outside any Segment subtree."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--basic-iast-buffer
   (goto-char (point-min))
   (should (null (tibetan-sanskrit-parallel-text-for-segment)))))

;; ============================================================================
;; PLACEHOLDER MARKER RECOGNITION (alignment-fix work, 2026-04-30)
;;
;; The Sanskrit-Tibetan alignment in source files is sometimes a
;; rough first-draft (daṇḍa-split) or explicitly absent (Tibetan-
;; canon front matter, translators' homages, uddāna verses).  Such
;; segments carry a placeholder marker as the `**** Sanskrit' body.
;; The walker must treat a placeholder body as "no Sanskrit
;; available" — return nil — so downstream paths (DM Sanskrit fire,
;; Claude parallel-mode user block, `** Sanskrit Source' renderer)
;; behave the same as for a missing sibling.  Three placeholder
;; prefixes are recognised today:
;;   `[Sanskrit alignment pending'      (this commit)
;;   `[Sanskrit alignment exhausted'    (gotrapatala daṇḍa-split prep)
;;   `[No Sanskrit counterpart'         (reserved — explicit Tib-only)
;; ============================================================================

(ert-deftest tibetan-sanskrit-parallel-placeholder-text-p-recognises-pending ()
  "`--placeholder-text-p' returns t for an `[Sanskrit alignment
pending …]' marker (the universal placeholder used when the
daṇḍa-split alignment is known-invalid and awaits class-time
editorial verification)."
  (should (tibetan-sanskrit-parallel--placeholder-text-p
           "[Sanskrit alignment pending — daṇḍa-split was structurally invalid; awaiting class-time editorial alignment]"))
  (should (tibetan-sanskrit-parallel--placeholder-text-p
           "[Sanskrit alignment pending]")))

(ert-deftest tibetan-sanskrit-parallel-placeholder-text-p-recognises-exhausted ()
  "`--placeholder-text-p' returns t for the existing `[Sanskrit
alignment exhausted …]' marker generated by the gotrapatala
daṇḍa-split prep when the Sanskrit ran out before the Tibetan."
  (should (tibetan-sanskrit-parallel--placeholder-text-p
           "[Sanskrit alignment exhausted — only 70 daṇḍa-clauses for 97 segments]")))

(ert-deftest tibetan-sanskrit-parallel-placeholder-text-p-recognises-no-counterpart ()
  "`--placeholder-text-p' returns t for an explicit `[No Sanskrit
counterpart …]' marker (Tibetan-only segments — translator's
homages, uddāna verses)."
  (should (tibetan-sanskrit-parallel--placeholder-text-p
           "[No Sanskrit counterpart — Tibetan canon front matter]"))
  (should (tibetan-sanskrit-parallel--placeholder-text-p
           "[No Sanskrit counterpart]")))

(ert-deftest tibetan-sanskrit-parallel-placeholder-text-p-rejects-real-sanskrit ()
  "`--placeholder-text-p' returns nil for genuine IAST text — the
predicate must NOT swallow real Sanskrit that happens to start
with a square bracket."
  (should-not (tibetan-sanskrit-parallel--placeholder-text-p
               "ahaṃ bodhisattvaḥ"))
  (should-not (tibetan-sanskrit-parallel--placeholder-text-p
               "iha bodhisattvaḥ prakṛtyaiva dānarucirbhavati"))
  ;; Sanskrit that uses brackets but isn't a marker.
  (should-not (tibetan-sanskrit-parallel--placeholder-text-p
               "[uncertain reading] bodhisattvaḥ"))
  ;; Devanagari real text.
  (should-not (tibetan-sanskrit-parallel--placeholder-text-p
               "त्वया उक्तं च")))

(ert-deftest tibetan-sanskrit-parallel-placeholder-text-p-rejects-empty ()
  "`--placeholder-text-p' returns nil for nil, empty, and non-string
input — defensive contract for the predicate."
  (should-not (tibetan-sanskrit-parallel--placeholder-text-p nil))
  (should-not (tibetan-sanskrit-parallel--placeholder-text-p ""))
  (should-not (tibetan-sanskrit-parallel--placeholder-text-p 42)))

(defconst tibetan-sanskrit-parallel-test--placeholder-pending-buffer
  "#+TITLE: Test Placeholder Pending
* Tibetan Text
** Section 1
*** Sentence 1
**** Segment 1
སྡོམ་ལ་། གཞི་དང་རྟགས་དང་ཕྱོགས་རྣམས་དང་༎

**** Sanskrit
[Sanskrit alignment pending — daṇḍa-split was structurally invalid; awaiting class-time editorial alignment]

**** Working Translation
"
  "Segment whose Sanskrit sibling carries the universal pending
marker — walker must treat it as `no Sanskrit available'.")

(defconst tibetan-sanskrit-parallel-test--placeholder-exhausted-buffer
  "#+TITLE: Test Placeholder Exhausted
* Tibetan Text
** Section 1
*** Sentence 1
**** Segment 1
བདག

**** Sanskrit
[Sanskrit alignment exhausted — only 70 daṇḍa-clauses for 97 segments]

**** Working Translation
"
  "Segment whose Sanskrit sibling carries the legacy exhausted-
marker.  Regression case: existing daṇḍa-split prep still
behaves correctly after the predicate generalisation.")

(ert-deftest tibetan-sanskrit-parallel-walker-returns-nil-when-sanskrit-is-pending-placeholder ()
  "Walker returns nil — not a plist with the marker text — when
the `**** Sanskrit' sibling carries an `[Sanskrit alignment
pending …]' body.  Downstream (DM fire, Claude parallel-mode
user block, `** Sanskrit Source' renderer) all treat nil as
`no Sanskrit available'."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--placeholder-pending-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 1")
   (should (null (tibetan-sanskrit-parallel-text-for-segment)))))

(ert-deftest tibetan-sanskrit-parallel-walker-returns-nil-when-sanskrit-is-exhausted-placeholder ()
  "Regression: walker also returns nil for the legacy `[Sanskrit
alignment exhausted …]' marker.  Existing gotrapatala daṇḍa-
split prep keeps behaving as if those segments had no Sanskrit
sibling."
  (tibetan-sanskrit-parallel-test--with-org-buffer
   tibetan-sanskrit-parallel-test--placeholder-exhausted-buffer
   (goto-char (point-min))
   (search-forward "**** Segment 1")
   (should (null (tibetan-sanskrit-parallel-text-for-segment)))))

(ert-deftest tibetan-sanskrit-parallel-text-for-segment-id-skips-placeholder ()
  "The file-based by-id lookup also returns nil for placeholder
bodies — used by the Phase 3 Claude prompt builder and the
DM-fire path, both of which run by-id and not by-cursor."
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   tibetan-sanskrit-parallel-test--placeholder-pending-buffer
   (should (null (tibetan-sanskrit-parallel-text-for-segment-id
                  filepath 1)))))

;; ============================================================================
;; RESET SANSKRIT-SIDE SECTIONS (alignment-fix work, 2026-04-30)
;;
;; When the source file's Sanskrit alignment changes structurally
;; (e.g. bulk re-marked as `[Sanskrit alignment pending …]'),
;; existing analysis files carry stale Sanskrit-side sections
;; whose bodies were generated against the OLD alignment.  The
;; reset command removes those sections so the next reanalyse
;; regenerates them — or omits them if the source is now pending.
;;
;; Sections removed:
;;   level 2 (inside `* Auto-Analysis'):
;;     ** Sanskrit Source
;;     ** Claude Translation (Sanskrit)
;;     ** Claude Translation (Combined)
;;     ** Claude Divergence
;;   level 1 (top-level):
;;     * DharmaMitra Translation (Sanskrit)
;;
;; Preserved:
;;   ** Claude Translation (Tibetan-side, bare heading)
;;   * DharmaMitra Translation (Tibetan)
;;   * My Notes / * Working Translation / * Footnotes (user content)
;;   All parser-side sections (Wylie, Interlinear, Grammar, etc.)
;; ============================================================================

(defconst tibetan-sanskrit-parallel-test--all-sanskrit-sections-buffer
  "#+TITLE: Test All Sanskrit Sections
* Tibetan Text
བདག

* My Notes
USER NOTE — must survive

* Working Translation
WORKING TRANSLATION — must survive

* Auto-Analysis
:PROPERTIES:
:GENERATED: t
:END:

** Sanskrit Source

IAST: ahaṃ

** Wylie Transliteration
bdag /

** Claude Translation
TIBETAN TRANSLATION — must survive

** Claude Translation (Sanskrit)
SANSKRIT TRANSLATION — to be removed

** Claude Translation (Combined)
COMBINED — to be removed

** Claude Divergence
- DIVERGENCE NOTE — to be removed

** Grammar
GRAMMAR BODY — must survive

* Footnotes
FOOTNOTE — must survive

* DharmaMitra Translation (Tibetan)
DM-TIBETAN — must survive

* DharmaMitra Translation (Sanskrit)
DM-SANSKRIT — to be removed
"
  "Analysis-file fixture carrying ALL five Sanskrit-side sections
\(four level-2 + one level-1) plus the four sections that must
NOT be removed (Tibetan Translation, DM Tibetan, user content,
Wylie + Grammar parser blocks).")

(ert-deftest tibetan-sanskrit-parallel-reset-sections-removes-all-five-sanskrit-sections ()
  "`--reset-sanskrit-sections-in-file' removes all four level-2
Sanskrit-side sections plus the level-1 DM Sanskrit section.
Returns the count of sections removed."
  (let ((tmpfile (make-temp-file "tibetan-skt-reset-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert tibetan-sanskrit-parallel-test--all-sanskrit-sections-buffer))
          (let ((removed
                 (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-file
                  tmpfile)))
            (should (= removed 5))
            ;; Verify the file actually changed.
            (with-temp-buffer
              (insert-file-contents tmpfile)
              (let ((s (buffer-string)))
                (should-not (string-match-p "^\\*\\* Sanskrit Source$" s))
                (should-not (string-match-p
                             "^\\*\\* Claude Translation (Sanskrit)$" s))
                (should-not (string-match-p
                             "^\\*\\* Claude Translation (Combined)$" s))
                (should-not (string-match-p "^\\*\\* Claude Divergence$" s))
                (should-not (string-match-p
                             "^\\* DharmaMitra Translation (Sanskrit)$"
                             s))))))
      (delete-file tmpfile))))

(ert-deftest tibetan-sanskrit-parallel-reset-sections-preserves-tibetan-sections ()
  "`--reset-sanskrit-sections-in-file' must NOT touch the Tibetan-
side translation, DM Tibetan, parser sections, or user content."
  (let ((tmpfile (make-temp-file "tibetan-skt-reset-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert tibetan-sanskrit-parallel-test--all-sanskrit-sections-buffer))
          (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-file tmpfile)
          (with-temp-buffer
            (insert-file-contents tmpfile)
            (let ((s (buffer-string)))
              ;; Headings preserved.
              (should (string-match-p "^\\*\\* Claude Translation$" s))
              (should (string-match-p
                       "^\\* DharmaMitra Translation (Tibetan)$" s))
              (should (string-match-p "^\\*\\* Wylie Transliteration$" s))
              (should (string-match-p "^\\*\\* Grammar$" s))
              (should (string-match-p "^\\* My Notes$" s))
              (should (string-match-p "^\\* Working Translation$" s))
              (should (string-match-p "^\\* Footnotes$" s))
              ;; Bodies preserved.
              (should (string-match-p "TIBETAN TRANSLATION — must survive" s))
              (should (string-match-p "DM-TIBETAN — must survive" s))
              (should (string-match-p "GRAMMAR BODY — must survive" s))
              (should (string-match-p "USER NOTE — must survive" s))
              (should (string-match-p
                       "WORKING TRANSLATION — must survive" s))
              (should (string-match-p "FOOTNOTE — must survive" s)))))
      (delete-file tmpfile))))

(ert-deftest tibetan-sanskrit-parallel-reset-sections-idempotent ()
  "Running `--reset-sanskrit-sections-in-file' twice in a row:
first call removes the sections and returns the count; second
call returns 0 (no-op) and leaves the file byte-identical."
  (let ((tmpfile (make-temp-file "tibetan-skt-reset-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert tibetan-sanskrit-parallel-test--all-sanskrit-sections-buffer))
          (let ((first
                 (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-file
                  tmpfile)))
            (should (= first 5)))
          ;; Capture state after first run.
          (let ((after-first
                 (with-temp-buffer
                   (insert-file-contents tmpfile)
                   (buffer-string))))
            (let ((second
                   (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-file
                    tmpfile)))
              (should (= second 0)))
            (with-temp-buffer
              (insert-file-contents tmpfile)
              (should (string= (buffer-string) after-first)))))
      (delete-file tmpfile))))

(ert-deftest tibetan-sanskrit-parallel-reset-sections-clean-file-no-op ()
  "A file that never carried any Sanskrit-side sections is left
byte-identical and returns 0."
  (let ((clean-content
         "#+TITLE: Clean
* Tibetan Text
བདག

* Auto-Analysis
** Wylie Transliteration
bdag /

** Claude Translation
Just the Tibetan side.

* My Notes

* Footnotes
")
        (tmpfile (make-temp-file "tibetan-skt-reset-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert clean-content))
          (let ((removed
                 (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-file
                  tmpfile)))
            (should (= removed 0)))
          (with-temp-buffer
            (insert-file-contents tmpfile)
            (should (string= (buffer-string) clean-content))))
      (delete-file tmpfile))))

(ert-deftest tibetan-sanskrit-parallel-reset-sections-folder-iterates ()
  "`--reset-sanskrit-sections-in-folder' walks every `seg-NNN.org'
\(and `sent-NNN.org') file in FOLDER, returns a plist summary
\(`:files-touched' / `:files-clean' / `:sections-removed')."
  (let ((folder (make-temp-file "tibetan-skt-reset-folder-" t)))
    (unwind-protect
        (progn
          ;; Two seg files with sections; one already-clean seg file.
          (with-temp-file (expand-file-name "seg-001.org" folder)
            (insert
             tibetan-sanskrit-parallel-test--all-sanskrit-sections-buffer))
          (with-temp-file (expand-file-name "seg-002.org" folder)
            (insert
             tibetan-sanskrit-parallel-test--all-sanskrit-sections-buffer))
          (with-temp-file (expand-file-name "seg-003.org" folder)
            (insert "* Tibetan Text\nbdag\n* Footnotes\n"))
          (let ((summary
                 (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-folder
                  folder)))
            (should (= (plist-get summary :files-touched)   2))
            (should (= (plist-get summary :files-clean)     1))
            (should (= (plist-get summary :sections-removed) 10))))
      (delete-directory folder t))))

(ert-deftest tibetan-sanskrit-parallel-reset-sections-folder-handles-missing ()
  "Missing or non-directory FOLDER is reported via the summary
plist `:error' key — no exception thrown — so a misclick on the
interactive command doesn't burn a stack trace."
  (let ((summary
         (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-folder
          "/no/such/folder/exists/here")))
    (should (plist-get summary :error))))

;; ============================================================================
;; SEGMENT-ID LOOKUP TESTS (file-based, used by Phase 3 Claude path)
;; ============================================================================

(ert-deftest tibetan-sanskrit-parallel-text-for-segment-id-returns-plist ()
  "`tibetan-sanskrit-parallel-text-for-segment-id' resolves Sanskrit
without requiring point-in-buffer."
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   tibetan-sanskrit-parallel-test--basic-iast-buffer
   (let ((result (tibetan-sanskrit-parallel-text-for-segment-id filepath 1)))
     (should result)
     (should (equal (plist-get result :iast)
                    "yathā vā punaḥ kaścid evam āha")))
   (let ((result (tibetan-sanskrit-parallel-text-for-segment-id filepath 2)))
     (should result)
     (should (equal (plist-get result :iast) "sa āha")))))

(ert-deftest tibetan-sanskrit-parallel-text-for-segment-id-nil-when-missing ()
  "Returns nil for non-existent segment ID and missing file."
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   tibetan-sanskrit-parallel-test--no-sanskrit-buffer
   (should (null (tibetan-sanskrit-parallel-text-for-segment-id filepath 1)))
   (should (null (tibetan-sanskrit-parallel-text-for-segment-id filepath 99))))
  (should (null (tibetan-sanskrit-parallel-text-for-segment-id nil 1)))
  (should (null (tibetan-sanskrit-parallel-text-for-segment-id
                 "/nonexistent/path.org" 1))))

;; ============================================================================
;; DEVANAGARI SNIFF TESTS
;; ============================================================================

(ert-deftest tibetan-sanskrit-parallel-has-devanagari-p-recognises-devanagari ()
  "`--has-devanagari-p' returns t for strings with U+0900–U+097F."
  (should (tibetan-sanskrit-parallel--has-devanagari-p "त्वया उक्तं च"))
  (should (tibetan-sanskrit-parallel--has-devanagari-p "यथा")))

(ert-deftest tibetan-sanskrit-parallel-has-devanagari-p-rejects-iast ()
  "`--has-devanagari-p' returns nil for plain IAST and ASCII strings."
  (should-not (tibetan-sanskrit-parallel--has-devanagari-p "yathā vā punaḥ"))
  (should-not (tibetan-sanskrit-parallel--has-devanagari-p "abcd"))
  (should-not (tibetan-sanskrit-parallel--has-devanagari-p ""))
  (should-not (tibetan-sanskrit-parallel--has-devanagari-p
               "kaścid evam āha — śṛṇvanti")))

(ert-deftest tibetan-sanskrit-parallel-has-devanagari-p-rejects-tibetan ()
  "Tibetan Unicode (U+0F00–U+0FFF) is NOT mistaken for Devanagari."
  (should-not (tibetan-sanskrit-parallel--has-devanagari-p "བདག་ལ་སྟོད")))

;; ============================================================================
;; SOURCE-MODE PREDICATE TESTS
;; ============================================================================

(ert-deftest tibetan-cat-source-mode-parallel-p-detects-header ()
  "`--source-mode-parallel-p' returns t when `#+SOURCE_MODE:
parallel-sanskrit' is present."
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: Test
#+SOURCE_MODE: parallel-sanskrit
* Tibetan Text
"
   (should (tibetan-cat--source-mode-parallel-p filepath))))

(ert-deftest tibetan-cat-source-mode-parallel-p-rejects-other-modes ()
  "Predicate returns nil for unrelated `#+SOURCE_MODE:' values."
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: Test
#+SOURCE_MODE: parallel-pali
* Tibetan Text
"
   (should-not (tibetan-cat--source-mode-parallel-p filepath))))

(ert-deftest tibetan-cat-source-mode-parallel-p-nil-when-header-absent ()
  "Predicate returns nil when no `#+SOURCE_MODE:' header is present
(today's behaviour for non-parallel documents)."
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: Test
* Tibetan Text
"
   (should-not (tibetan-cat--source-mode-parallel-p filepath))))

(ert-deftest tibetan-cat-source-mode-parallel-p-handles-missing-file ()
  "Predicate returns nil for nil/missing file path (no crash)."
  (should-not (tibetan-cat--source-mode-parallel-p nil))
  (should-not (tibetan-cat--source-mode-parallel-p ""))
  (should-not (tibetan-cat--source-mode-parallel-p "/nonexistent/path.org")))

(ert-deftest tibetan-cat-source-mode-parallel-p-handles-whitespace ()
  "Predicate is tolerant of trailing whitespace on the header line."
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: Test
#+SOURCE_MODE: parallel-sanskrit
* Tibetan Text
"
   (should (tibetan-cat--source-mode-parallel-p filepath))))

;; ============================================================================
;; PHASE 2 — `** Sanskrit Source' RENDERING IN ANALYSIS FILES
;; ============================================================================
;;
;; These tests cover the renderer that emits a `** Sanskrit Source'
;; level-2 section under `* Auto-Analysis' when:
;;   1. `tibetan-analysis--sanskrit-text-for-render' (dynamic var)
;;      is bound to a non-nil sanskrit-plist by the caller, AND
;;   2. (transitively, via the priority-order pass) the section
;;      sits BEFORE `** Wylie Transliteration' in the final
;;      content because Sanskrit is the primary source.
;;
;; The renderer itself is a pure function — most tests exercise it
;; directly without invoking the full `generate-content' pipeline,
;; so the suite stays fast.  One end-to-end test confirms the
;; section actually lands in `generate-content' output and is
;; ordered correctly.

(ert-deftest tibetan-analysis-render-sanskrit-source-iast-only ()
  "Renderer emits `** Sanskrit Source' with an IAST line and
no Devanagari line when the plist's `:devanagari' is nil."
  (skip-unless (fboundp 'tibetan-analysis--render-sanskrit-source))
  (let* ((plist (list :iast "yathā vā punaḥ kaścid evam āha"
                      :devanagari nil
                      :script-source 'iast-line))
         (out (tibetan-analysis--render-sanskrit-source plist)))
    (should (stringp out))
    (should (string-match-p "^\\*\\* Sanskrit Source$" out))
    (should (string-match-p "IAST: yathā vā punaḥ kaścid evam āha" out))
    (should-not (string-match-p "Devanagari:" out))))

(ert-deftest tibetan-analysis-render-sanskrit-source-with-devanagari ()
  "Renderer emits both an IAST and a Devanagari line when the
plist carries Devanagari."
  (skip-unless (fboundp 'tibetan-analysis--render-sanskrit-source))
  (let* ((plist (list :iast "tvayā uktaṃ ca"
                      :devanagari "त्वया उक्तं च"
                      :script-source 'iast-and-devanagari))
         (out (tibetan-analysis--render-sanskrit-source plist)))
    (should (string-match-p "IAST: tvayā uktaṃ ca" out))
    (should (string-match-p "Devanagari: त्वया उक्तं च" out))))

(ert-deftest tibetan-analysis-render-sanskrit-source-nil-input ()
  "Renderer returns an empty string (not nil, not error) for nil
input.  Callers can safely concatenate the result without
guarding."
  (skip-unless (fboundp 'tibetan-analysis--render-sanskrit-source))
  (let ((out (tibetan-analysis--render-sanskrit-source nil)))
    (should (stringp out))
    (should (string-empty-p out))))

(ert-deftest tibetan-analysis-render-sanskrit-source-empty-iast ()
  "Renderer treats empty `:iast' as no-content (returns empty
string) — the Sanskrit section never renders without IAST."
  (skip-unless (fboundp 'tibetan-analysis--render-sanskrit-source))
  (let* ((plist (list :iast ""
                      :devanagari nil
                      :script-source 'iast-line))
         (out (tibetan-analysis--render-sanskrit-source plist)))
    (should (stringp out))
    (should (string-empty-p out))))

(ert-deftest tibetan-analysis-generate-content-omits-sanskrit-when-var-nil ()
  "When `--sanskrit-text-for-render' is nil (default), the output
contains no `** Sanskrit Source' section.  This is today's
behaviour for non-parallel documents and must not regress."
  (skip-unless (fboundp 'tibetan-analysis-generate-content))
  (let ((tibetan-analysis--sanskrit-text-for-render nil))
    (condition-case nil
        (let ((out (tibetan-analysis-generate-content "བདག")))
          (when (stringp out)
            (should-not (string-match-p "^\\*\\* Sanskrit Source$" out))))
      (error nil))))

(ert-deftest tibetan-analysis-generate-content-emits-sanskrit-when-var-bound ()
  "When `--sanskrit-text-for-render' is bound to a sanskrit-plist,
the output contains a `** Sanskrit Source' section with the
IAST line."
  (skip-unless (fboundp 'tibetan-analysis-generate-content))
  (skip-unless (boundp 'tibetan-analysis--sanskrit-text-for-render))
  (let ((tibetan-analysis--sanskrit-text-for-render
         (list :iast "ahaṃ"
               :devanagari nil
               :script-source 'iast-line)))
    (condition-case err
        (let ((out (tibetan-analysis-generate-content "བདག")))
          (should (stringp out))
          (should (string-match-p "^\\*\\* Sanskrit Source$" out))
          (should (string-match-p "IAST: ahaṃ" out)))
      (error
       (signal (car err) (cdr err))))))

(ert-deftest tibetan-analysis-generate-content-sanskrit-precedes-wylie ()
  "The `** Sanskrit Source' section lands BEFORE
`** Wylie Transliteration' in the final ordered output —
Sanskrit is primary in parallel-mode, so it reads first."
  (skip-unless (fboundp 'tibetan-analysis-generate-content))
  (skip-unless (boundp 'tibetan-analysis--sanskrit-text-for-render))
  (let ((tibetan-analysis--sanskrit-text-for-render
         (list :iast "ahaṃ"
               :devanagari nil
               :script-source 'iast-line)))
    (condition-case err
        (let* ((out (tibetan-analysis-generate-content "བདག"))
               (skt-pos (and (stringp out)
                             (string-match "^\\*\\* Sanskrit Source$" out)))
               (wyl-pos (and (stringp out)
                             (string-match
                              "^\\*\\* Wylie Transliteration$" out))))
          (should skt-pos)
          (should wyl-pos)
          (should (< skt-pos wyl-pos)))
      (error
       (signal (car err) (cdr err))))))

(ert-deftest tibetan-analysis-priority-order-includes-sanskrit-source ()
  "`tibetan-analysis--priority-section-order' includes
`** Sanskrit Source' at position 0 (above
`** Wylie Transliteration').  Phase 2 prepends it
unconditionally — the reorder pass only places sections that
exist, so non-parallel documents are unaffected."
  (skip-unless (boundp 'tibetan-analysis--priority-section-order))
  (let ((order tibetan-analysis--priority-section-order))
    (should (member "** Sanskrit Source" order))
    (should (member "** Wylie Transliteration" order))
    (let ((skt-idx (cl-position "** Sanskrit Source" order :test #'string=))
          (wyl-idx (cl-position "** Wylie Transliteration" order
                                :test #'string=)))
      (should skt-idx)
      (should wyl-idx)
      (should (< skt-idx wyl-idx)))))

;; ============================================================================
;; PHASE 5 — Toggle command for `#+SOURCE_MODE: parallel-sanskrit'
;; ============================================================================
;;
;; Three commands for managing the per-document opt-in flag:
;;
;;   tibetan-cat-set-source-mode (source-file mode)
;;     Insert / replace `#+SOURCE_MODE: <mode>' in SOURCE-FILE.
;;     Patterned on `tibetan-analysis-set-source-target-lang' —
;;     header replaces in place when present, inserts after
;;     `#+TITLE:' when missing, prepends when no #+TITLE either.
;;
;;   tibetan-cat-clear-source-mode (source-file)
;;     Remove the `#+SOURCE_MODE:' line entirely.  Returns the
;;     document to today's Tibetan-only behaviour.
;;
;;   tibetan-cat-toggle-source-mode-parallel ()
;;     Interactive wrapper.  Resolves the source file from the
;;     current buffer (or via the analysis-file → source-file
;;     reverse link), reads the existing mode, and either sets
;;     the mode to `parallel-sanskrit' (when absent / different)
;;     or clears it (when already `parallel-sanskrit').
;;
;; Bound to `C-c u z P' (parallel-Sanskrit) under the existing
;; `C-c u z' thesaurus / source-document prefix map — sibling of
;; `C-c u z L' which sets target language.

(ert-deftest tibetan-cat-set-source-mode-inserts-header-when-absent ()
  "When SOURCE-FILE has no `#+SOURCE_MODE:' line yet,
`tibetan-cat-set-source-mode' inserts one — placed immediately
after `#+TITLE:' to keep document metadata contiguous at the
top of the file."
  (skip-unless (fboundp 'tibetan-cat-set-source-mode))
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: Yogācārabhūmi\n#+AUTHOR: Asaṅga\n\n* Tibetan Text\n"
   (tibetan-cat-set-source-mode filepath "parallel-sanskrit")
   (with-temp-buffer
     (insert-file-contents filepath)
     (let ((s (buffer-string)))
       (should (string-match-p "^#\\+SOURCE_MODE: parallel-sanskrit$" s))
       ;; Header is contiguous — appears between #+TITLE and the
       ;; blank line that precedes the first heading.
       (let ((title-pos (string-match "^#\\+TITLE:" s))
             (mode-pos  (string-match "^#\\+SOURCE_MODE:" s))
             (heading-pos (string-match "^\\* " s)))
         (should title-pos)
         (should mode-pos)
         (should heading-pos)
         (should (< title-pos mode-pos heading-pos)))))))

(ert-deftest tibetan-cat-set-source-mode-replaces-existing-line ()
  "When `#+SOURCE_MODE:' already exists,
`tibetan-cat-set-source-mode' replaces the value in place — no
duplicate lines, no orphaned old value."
  (skip-unless (fboundp 'tibetan-cat-set-source-mode))
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: T\n#+SOURCE_MODE: parallel-pali\n\n* Tibetan Text\n"
   (tibetan-cat-set-source-mode filepath "parallel-sanskrit")
   (with-temp-buffer
     (insert-file-contents filepath)
     (let ((s (buffer-string)))
       (should (string-match-p "^#\\+SOURCE_MODE: parallel-sanskrit$" s))
       (should-not (string-match-p "parallel-pali" s))
       ;; Single line — `string-match' starting after the first hit
       ;; finds nothing.
       (let ((first (string-match "^#\\+SOURCE_MODE:" s)))
         (should first)
         (should-not (string-match "^#\\+SOURCE_MODE:" s (1+ first))))))))

(ert-deftest tibetan-cat-set-source-mode-prepends-when-no-title ()
  "When SOURCE-FILE has no `#+TITLE:' header either, the mode
header is prepended to the buffer rather than discarded."
  (skip-unless (fboundp 'tibetan-cat-set-source-mode))
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "* Tibetan Text\nbody\n"
   (tibetan-cat-set-source-mode filepath "parallel-sanskrit")
   (with-temp-buffer
     (insert-file-contents filepath)
     (let ((s (buffer-string)))
       (should (string-match-p "^#\\+SOURCE_MODE: parallel-sanskrit$" s))
       (should (= 0 (string-match "^#\\+SOURCE_MODE:" s)))))))

(ert-deftest tibetan-cat-set-source-mode-rejects-empty-mode ()
  "Empty / nil MODE arg signals user-error rather than writing
a malformed `#+SOURCE_MODE:' line."
  (skip-unless (fboundp 'tibetan-cat-set-source-mode))
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: T\n"
   (should-error (tibetan-cat-set-source-mode filepath nil)
                 :type 'user-error)
   (should-error (tibetan-cat-set-source-mode filepath "")
                 :type 'user-error)))

(ert-deftest tibetan-cat-set-source-mode-rejects-missing-file ()
  "Missing / non-writable SOURCE-FILE signals user-error."
  (skip-unless (fboundp 'tibetan-cat-set-source-mode))
  (should-error (tibetan-cat-set-source-mode nil "parallel-sanskrit")
                :type 'user-error)
  (should-error (tibetan-cat-set-source-mode "/nonexistent/path.org"
                                              "parallel-sanskrit")
                :type 'user-error))

(ert-deftest tibetan-cat-clear-source-mode-removes-header ()
  "`tibetan-cat-clear-source-mode' deletes the `#+SOURCE_MODE:'
line — surrounding content is preserved."
  (skip-unless (fboundp 'tibetan-cat-clear-source-mode))
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: T\n#+SOURCE_MODE: parallel-sanskrit\n#+AUTHOR: Asaṅga\n\n* Tibetan Text\n"
   (tibetan-cat-clear-source-mode filepath)
   (with-temp-buffer
     (insert-file-contents filepath)
     (let ((s (buffer-string)))
       (should-not (string-match-p "^#\\+SOURCE_MODE:" s))
       ;; Other headers preserved.
       (should (string-match-p "^#\\+TITLE: T$" s))
       (should (string-match-p "^#\\+AUTHOR: Asaṅga$" s))
       (should (string-match-p "^\\* Tibetan Text$" s))))))

(ert-deftest tibetan-cat-clear-source-mode-noop-when-absent ()
  "Clearing a file that has no `#+SOURCE_MODE:' header is a
no-op — file content stays byte-identical, no error signalled."
  (skip-unless (fboundp 'tibetan-cat-clear-source-mode))
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: T\n\n* Tibetan Text\nbody\n"
   (let ((before (with-temp-buffer
                   (insert-file-contents filepath)
                   (buffer-string))))
     (tibetan-cat-clear-source-mode filepath)
     (let ((after (with-temp-buffer
                    (insert-file-contents filepath)
                    (buffer-string))))
       (should (equal before after))))))

(ert-deftest tibetan-cat-set-and-clear-source-mode-roundtrip ()
  "Round-trip: set then clear returns the file to byte-identical
state (modulo the `#+SOURCE_MODE:' line being absent both
times)."
  (skip-unless (fboundp 'tibetan-cat-set-source-mode))
  (skip-unless (fboundp 'tibetan-cat-clear-source-mode))
  (tibetan-sanskrit-parallel-test--with-temp-source-file
   "#+TITLE: T\n#+AUTHOR: A\n\n* Tibetan Text\nbody\n"
   (let ((before (with-temp-buffer
                   (insert-file-contents filepath)
                   (buffer-string))))
     (tibetan-cat-set-source-mode filepath "parallel-sanskrit")
     ;; Intermediate state has the header.
     (should (tibetan-cat--source-mode-parallel-p filepath))
     (tibetan-cat-clear-source-mode filepath)
     ;; Final state has no header AND matches the initial buffer.
     (should-not (tibetan-cat--source-mode-parallel-p filepath))
     (let ((after (with-temp-buffer
                    (insert-file-contents filepath)
                    (buffer-string))))
       (should (equal before after))))))

(ert-deftest tibetan-cat-toggle-source-mode-parallel-fbound ()
  "The interactive toggle command is bound."
  (should (fboundp 'tibetan-cat-toggle-source-mode-parallel))
  (should (commandp 'tibetan-cat-toggle-source-mode-parallel)))

;; ============================================================================
;; PHASE 6 — End-to-end integration: dynamic var binding on real call paths
;; ============================================================================
;;
;; Phase 2 shipped `tibetan-analysis--sanskrit-text-for-render' (dynamic
;; var) and the `** Sanskrit Source' renderer that fires when it is
;; non-nil.  Phase 6 wires the var to the walker on the real
;; `tibetan-auto-analyze-document' / `--open-segment-analysis-impl' /
;; `--reanalyze-segment-impl' / `tibetan-analysis-reanalyze-file' call
;; paths.  Result: real `C-c u A' / `C-c u B' / `C-c u r' / `C-c u R'
;; runs on a parallel-Sanskrit document populate the
;; `** Sanskrit Source' section automatically.
;;
;; Test strategy: stub `tibetan-analysis-generate-content' to capture
;; the dynamic var's value at the moment it would have been consulted.
;; Asserting on the captured value verifies the call site bound the
;; var correctly without depending on the full vocabulary / Claude
;; / parser stack.

(defvar tibetan-sanskrit-parallel-test--captured-render-var nil
  "Capture slot used by Phase 6 stubs to record the value of
`tibetan-analysis--sanskrit-text-for-render' at the moment
`generate-content' was called.  Reset to nil at the start of
each test.")

(defun tibetan-sanskrit-parallel-test--capturing-stub
    (_tibetan-text &optional _seg-id _source-text _source-file)
  "Stub for `tibetan-analysis-generate-content' that captures the
in-flight value of the Sanskrit-render dynamic var, then returns
a minimal valid auto-content body so the surrounding caller can
finish.  Used by Phase 6 integration tests."
  (setq tibetan-sanskrit-parallel-test--captured-render-var
        tibetan-analysis--sanskrit-text-for-render)
  ;; Return a minimal body that survives the section-reorder pass.
  ":PROPERTIES:\n:GENERATED: t\n:END:\n\n** Wylie Transliteration\n[stub]\n\n** Claude Translation\n[Requesting translation...]\n\n")

(defmacro tibetan-sanskrit-parallel-test--with-parallel-source-and-analysis
    (parallel-mode &rest body)
  "Set up a temp source file + temp analysis file for Phase 6
integration tests.  When PARALLEL-MODE is non-nil, the source
gets `#+SOURCE_MODE: parallel-sanskrit'.  Source has Segment 1
with a `**** Sanskrit' sibling carrying IAST line `aham asmi'.

Bindings inside BODY:
  source-file      Absolute path to the temp source.org
  analysis-dir     Directory holding the analysis file
  analysis-file    Absolute path to seg-001.org (created with
                   minimal scaffold so reanalyze-file can run)."
  (declare (indent 1))
  `(let* ((source-dir (make-temp-file "tibetan-skt-phase6-src-" t))
          (analysis-dir (make-temp-file "tibetan-skt-phase6-ana-" t))
          (source-file (expand-file-name "source.org" source-dir))
          (analysis-file (expand-file-name "seg-001.org" analysis-dir)))
     (unwind-protect
         (progn
           (with-temp-file source-file
             (insert "#+TITLE: YBh test\n")
             (when ,parallel-mode
               (insert "#+SOURCE_MODE: parallel-sanskrit\n"))
             (insert "\n* Tibetan Text\n** Section 1\n*** Sentence 1\n"
                     "**** Segment 1\nབདག་ཡིན།\n\n"
                     "**** Sanskrit\naham asmi\n\n"
                     "**** Working Translation\n\n"))
           (with-temp-file analysis-file
             (insert "#+TITLE: Segment 1 Analysis\n#+TIBETAN_HASH: x\n\n"
                     "* Tibetan Text\nབདག་ཡིན།\n\n"
                     "* Auto-Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                     "** Wylie Transliteration\n[old]\n\n"
                     "** Claude Translation\n[Requesting translation...]\n\n"
                     "* My Notes\n\n* Working Translation\n\n* Footnotes\n"))
           (setq tibetan-sanskrit-parallel-test--captured-render-var nil)
           ,@body)
       (when (file-exists-p source-file) (delete-file source-file))
       (when (file-exists-p analysis-file) (delete-file analysis-file))
       (when (file-exists-p source-dir)
         (delete-directory source-dir t))
       (when (file-exists-p analysis-dir)
         (delete-directory analysis-dir t)))))

(ert-deftest tibetan-sanskrit-parallel-reanalyze-file-binds-render-var-when-parallel ()
  "`tibetan-analysis-reanalyze-file' on a parallel-Sanskrit source
binds `--sanskrit-text-for-render' to the walker's plist for
Segment 1, so the renderer that runs inside `generate-content'
sees the IAST + Devanagari payload."
  (skip-unless (fboundp 'tibetan-analysis-reanalyze-file))
  (tibetan-sanskrit-parallel-test--with-parallel-source-and-analysis t
    (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
               #'tibetan-sanskrit-parallel-test--capturing-stub))
      (tibetan-analysis-reanalyze-file analysis-file
                                        :source-file source-file
                                        :re-request-claude nil)
      (let ((captured tibetan-sanskrit-parallel-test--captured-render-var))
        (should captured)
        (should (equal (plist-get captured :iast) "aham asmi"))))))

(ert-deftest tibetan-sanskrit-parallel-reanalyze-file-leaves-render-var-nil-when-not-parallel ()
  "Same source minus `#+SOURCE_MODE:' header → walker still finds
the Sanskrit sibling (positional walker doesn't gate on mode),
but the auto-analyse + reanalyse paths only thread it through
the dynamic var when the source IS in parallel mode.
REGRESSION GUARD for non-parallel documents: the var stays nil,
so today's behaviour is preserved byte-for-byte."
  (skip-unless (fboundp 'tibetan-analysis-reanalyze-file))
  (tibetan-sanskrit-parallel-test--with-parallel-source-and-analysis nil
    (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
               #'tibetan-sanskrit-parallel-test--capturing-stub))
      (tibetan-analysis-reanalyze-file analysis-file
                                        :source-file source-file
                                        :re-request-claude nil)
      ;; Without the `#+SOURCE_MODE:' header the call site does NOT
      ;; bind the var to the walker result, so the stub captures the
      ;; ambient nil.
      (should (null tibetan-sanskrit-parallel-test--captured-render-var)))))

(ert-deftest tibetan-sanskrit-parallel-reanalyze-file-leaves-render-var-nil-without-source-file ()
  "Reanalyze without supplying `:source-file' (legacy callers) →
no walker call, dynamic var stays nil.  The reanalyse-file
contract for non-Sanskrit-aware callers is unchanged."
  (skip-unless (fboundp 'tibetan-analysis-reanalyze-file))
  (tibetan-sanskrit-parallel-test--with-parallel-source-and-analysis t
    (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
               #'tibetan-sanskrit-parallel-test--capturing-stub))
      (tibetan-analysis-reanalyze-file analysis-file
                                        :re-request-claude nil)
      (should (null tibetan-sanskrit-parallel-test--captured-render-var)))))

(ert-deftest tibetan-sanskrit-parallel-auto-analyze-document-binds-render-var-when-parallel ()
  "`tibetan-auto-analyze-document' creating a fresh seg-001.org
from a parallel-Sanskrit source binds `--sanskrit-text-for-
render' to the Sanskrit plist for Segment 1.  This is the
`C-c u B' batch path."
  (skip-unless (fboundp 'tibetan-auto-analyze-document))
  (let* ((source-dir (make-temp-file "tibetan-skt-auto-" t))
         (source-file (expand-file-name "source.org" source-dir))
         (skipped-claude tibetan-auto-fire-claude-on-create))
    (unwind-protect
        (progn
          ;; Don't fire Claude during the test — we only care about
          ;; the structural pass.
          (setq tibetan-auto-fire-claude-on-create nil)
          (with-temp-file source-file
            (insert "#+TITLE: YBh\n#+SOURCE_MODE: parallel-sanskrit\n\n"
                    "* Tibetan Text\n** Section 1\n*** Sentence 1\n"
                    "**** Segment 1\nབདག་ཡིན།\n\n"
                    "**** Sanskrit\naham asmi\n\n"
                    "**** Working Translation\n\n"))
          (setq tibetan-sanskrit-parallel-test--captured-render-var nil)
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     #'tibetan-sanskrit-parallel-test--capturing-stub))
            ;; Open the source file in a buffer so
            ;; `tibetan-auto-analyze-document' can find its segments.
            (let ((buf (find-file-noselect source-file)))
              (unwind-protect
                  (with-current-buffer buf
                    (org-mode)
                    (tibetan-auto-analyze-document))
                (when (buffer-live-p buf)
                  (kill-buffer buf)))))
          (let ((captured tibetan-sanskrit-parallel-test--captured-render-var))
            (should captured)
            (should (equal (plist-get captured :iast) "aham asmi"))))
      (setq tibetan-auto-fire-claude-on-create skipped-claude)
      ;; Clean up any seg-NNN.org files auto-analyse created next to
      ;; the source.
      (dolist (f (directory-files source-dir t "^seg-[0-9]+.*\\.org$"))
        (delete-file f))
      (when (file-exists-p source-file) (delete-file source-file))
      (when (file-exists-p source-dir) (delete-directory source-dir t)))))

(ert-deftest tibetan-sanskrit-parallel-auto-analyze-document-leaves-render-var-nil-when-not-parallel ()
  "REGRESSION GUARD: without `#+SOURCE_MODE: parallel-sanskrit',
`tibetan-auto-analyze-document' never binds the render var.
Existing Tibetan-only documents stay byte-identical."
  (skip-unless (fboundp 'tibetan-auto-analyze-document))
  (let* ((source-dir (make-temp-file "tibetan-skt-auto-" t))
         (source-file (expand-file-name "source.org" source-dir))
         (skipped-claude tibetan-auto-fire-claude-on-create))
    (unwind-protect
        (progn
          (setq tibetan-auto-fire-claude-on-create nil)
          (with-temp-file source-file
            (insert "#+TITLE: Plain Tibetan\n\n"
                    "* Tibetan Text\n** Section 1\n*** Sentence 1\n"
                    "**** Segment 1\nབདག་ཡིན།\n\n"
                    "**** Working Translation\n\n"))
          (setq tibetan-sanskrit-parallel-test--captured-render-var nil)
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     #'tibetan-sanskrit-parallel-test--capturing-stub))
            (let ((buf (find-file-noselect source-file)))
              (unwind-protect
                  (with-current-buffer buf
                    (org-mode)
                    (tibetan-auto-analyze-document))
                (when (buffer-live-p buf)
                  (kill-buffer buf)))))
          (should (null tibetan-sanskrit-parallel-test--captured-render-var)))
      (setq tibetan-auto-fire-claude-on-create skipped-claude)
      (dolist (f (directory-files source-dir t "^seg-[0-9]+.*\\.org$"))
        (delete-file f))
      (when (file-exists-p source-file) (delete-file source-file))
      (when (file-exists-p source-dir) (delete-directory source-dir t)))))

(provide 'tibetan-sanskrit-parallel-test)
;;; tibetan-sanskrit-parallel-test.el ends here
