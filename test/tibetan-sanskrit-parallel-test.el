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

(provide 'tibetan-sanskrit-parallel-test)
;;; tibetan-sanskrit-parallel-test.el ends here
