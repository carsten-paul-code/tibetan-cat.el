;;; tibetan-dharmamitra-translation-test.el --- Tests for DM as a translator -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Phase A of the multi-translator-parallel-reading feature
;; (2026-04-30):  DharmaMitra alongside Claude as a translation
;; engine in the per-segment analysis files.  Each segment gets
;; a `** DharmaMitra Translation (Tibetan)' section (and, in
;; parallel-Sanskrit mode, a `** DharmaMitra Translation
;; (Sanskrit)' section) at level 2 — sibling of `** Claude
;; Translation (Tibetan)' / `** Claude Translation (Sanskrit)'.
;;
;; Tests stub `tibetan-dharmamitra-api-chat-translate' so no
;; network calls happen.  The writer is exercised against real
;; temp org files.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-dharmamitra-api)
(require 'tibetan-dharmamitra-translation)

;; ============================================================================
;; Fixture
;; ============================================================================

(defmacro tibetan-dm-trans-test--with-analysis-file (initial-content &rest body)
  "Write INITIAL-CONTENT to a temp seg-005.org and bind ANALYSIS-FILE."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-dm-trans-" t))
          (analysis-file (expand-file-name "seg-005.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file analysis-file (insert ,initial-content))
           ,@body)
       (delete-directory dir t))))

(defun tibetan-dm-trans-test--baseline-analysis ()
  "Return baseline analysis-file content for tests.

Uses the post-§5.18 layout:  `* Tibetan Analysis' parent + level-2
`** Translation' (Claude) + level-2 `** DharmaMitra Translation'
placeholder.  Tibetan-side DM writer (since 2026-05-19) targets
the placeholder under `* Tibetan Analysis', not the legacy
top-level `* DharmaMitra Translation (Tibetan)' section."
  (concat "#+TITLE: Segment 5 Analysis\n\n"
          "* My Notes\n\n* Working Translation\n\n"
          "* Tibetan Text\n"
          "བདག་གིས་ལས་བྱས།\n\n"
          "* Tibetan Analysis\n"
          ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
          "** Wylie Transliteration\nbdag gis las byas /\n\n"
          "** Translation\n[Requesting translation...]\n\n"
          "** DharmaMitra Translation\n[Awaiting DharmaMitra…]\n\n"
          "* Footnotes\n"))

;; ============================================================================
;; Writer — `--write-section'
;; ============================================================================

(ert-deftest tibetan-dm-trans-write-section-creates-tibetan-section ()
  "Writer places the Tibetan DharmaMitra translation under the
level-2 `** DharmaMitra Translation' heading inside `* Tibetan
Analysis' — peer of `** Translation' (Claude).  Layout revision
2026-05-19:  the legacy top-level `* DharmaMitra Translation
\(Tibetan)' is retired."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (let ((ok (tibetan-dharmamitra-translation--write-section
               analysis-file "By me, the work was done." "Tibetan")))
      (should ok)
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((s (buffer-string)))
          (should (string-match-p
                   "^\\*\\* DharmaMitra Translation$" s))
          (should (string-match-p "By me, the work was done\\." s))
          ;; The legacy top-level heading must NOT appear.
          (should-not (string-match-p
                       "^\\* DharmaMitra Translation (Tibetan)$" s))
          ;; The placeholder body is gone.
          (should-not (string-match-p "\\[Awaiting DharmaMitra" s)))))))

(ert-deftest tibetan-dm-trans-write-section-tibetan-deletes-legacy-toplevel ()
  "Migration:  when the analysis file has a LEGACY top-level
`* DharmaMitra Translation (Tibetan)' section (from before the
layout revision), the Tibetan writer deletes it and places the
new body under the nested `** DharmaMitra Translation' inside
`* Tibetan Analysis'."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (concat (tibetan-dm-trans-test--baseline-analysis)
              "\n* DharmaMitra Translation (Tibetan)\n"
              ":PROPERTIES:\n:LAST_TRANSLATED: 2026-04-30\n:END:\n\n"
              "LEGACY DM body (should be migrated away)\n")
    (tibetan-dharmamitra-translation--write-section
     analysis-file "MIGRATED FRESH BODY" "Tibetan")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        ;; Legacy top-level section gone.
        (should-not (string-match-p
                     "^\\* DharmaMitra Translation (Tibetan)$" s))
        (should-not (string-match-p "LEGACY DM body" s))
        ;; Fresh body present under nested heading.
        (should (string-match-p "MIGRATED FRESH BODY" s))
        (should (string-match-p "^\\*\\* DharmaMitra Translation$" s))))))

(ert-deftest tibetan-dm-trans-write-section-creates-sanskrit-section ()
  "Writer parameterises the heading on SOURCE-LANG: `Sanskrit'
yields `** DharmaMitra Translation (Sanskrit)'."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (tibetan-dharmamitra-translation--write-section
     analysis-file "In this context, a Bodhisattva ..." "Sanskrit")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p
                 "^\\* DharmaMitra Translation (Sanskrit)$" s))
        (should (string-match-p "In this context, a Bodhisattva" s))))))

(ert-deftest tibetan-dm-trans-write-section-replaces-existing-section ()
  "Re-writing replaces the body in place; old content is gone."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (concat (tibetan-dm-trans-test--baseline-analysis)
              "\n* DharmaMitra Translation (Tibetan)\nOLD STALE\n")
    (tibetan-dharmamitra-translation--write-section
     analysis-file "FRESH NEW TRANSLATION" "Tibetan")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "FRESH NEW TRANSLATION" s))
        (should-not (string-match-p "OLD STALE" s))
        ;; My Notes etc still present.
        (should (string-match-p "* My Notes" s))))))

(ert-deftest tibetan-dm-trans-write-section-preserves-other-content ()
  "All other top-level sections + Auto-Analysis content are
untouched by the writer."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (concat "#+TITLE: T\n\n"
              "* Tibetan Text\nTIBETAN_BODY\n\n"
              "* Auto-Analysis\nAUTO_BODY\n** Wylie\nWYLIE_BODY\n\n"
              "* My Notes\nNOTES_BODY\n\n"
              "* Working Translation\nWT_BODY\n\n"
              "* Footnotes\nFOOTNOTES_BODY\n")
    (tibetan-dharmamitra-translation--write-section
     analysis-file "DM translation" "Tibetan")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "TIBETAN_BODY" s))
        (should (string-match-p "AUTO_BODY" s))
        (should (string-match-p "WYLIE_BODY" s))
        (should (string-match-p "NOTES_BODY" s))
        (should (string-match-p "WT_BODY" s))
        (should (string-match-p "FOOTNOTES_BODY" s))
        ;; New section also added.
        (should (string-match-p "DM translation" s))))))

(ert-deftest tibetan-dm-trans-write-section-nil-when-file-missing ()
  "Non-existent ANALYSIS-FILE returns nil without crashing."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (should-not (tibetan-dharmamitra-translation--write-section
               "/nonexistent/path/seg-005.org"
               "translation" "Tibetan")))

(ert-deftest tibetan-dm-trans-write-section-property-drawer-stamps-metadata ()
  "Section's property drawer carries `:DM_BACKEND:' /
`:LAST_TRANSLATED:' for provenance + freshness tracking."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (tibetan-dharmamitra-translation--write-section
     analysis-file "translation" "Tibetan")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p ":LAST_TRANSLATED:" s))))))

(ert-deftest tibetan-dm-trans-write-section-neutralises-heading-injection ()
  "A response body whose line begins with `*' must NOT become a
top-level org heading mid-file.  Untrusted DM / network text is
inserted into the analysis buffer; a `* ' line would silently
restructure the document (and later regenerate passes treat top-level
headings as section boundaries)."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (tibetan-dharmamitra-translation--write-section
     analysis-file
     "Legitimate translation line.\n* Injected Heading\nmore body text."
     "Tibetan")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        ;; The injected line must NOT appear as a top-level heading.
        (should-not (string-match-p "^\\* Injected Heading$" s))
        ;; The text content is still present (neutralised, not dropped).
        (should (string-match-p "Injected Heading" s))
        (should (string-match-p "Legitimate translation line\\." s))))))

;; ============================================================================
;; Fire function — orchestrates API call + write
;; ============================================================================

(ert-deftest tibetan-dm-trans-fire-tibetan-calls-chat-translate ()
  "`tibetan-dharmamitra-translation-fire-tibetan' calls
`tibetan-dharmamitra-api-chat-translate' once with the segment's
Tibetan text."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-tibetan))
  (let (translate-calls)
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (text &rest _)
                 (push text translate-calls)
                 "stub English translation")))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        (tibetan-dharmamitra-translation-fire-tibetan
         "བདག་གིས་ལས་བྱས།" analysis-file)
        (should (= (length translate-calls) 1))
        (should (equal (car translate-calls) "བདག་གིས་ལས་བྱས།"))))))

(ert-deftest tibetan-dm-trans-fire-tibetan-writes-result-to-section ()
  "After firing, the analysis file contains the translation under
the new nested `** DharmaMitra Translation' heading inside
`* Tibetan Analysis' (peer of `** Translation').  Layout
revision 2026-05-19."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-tibetan))
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
             (lambda (&rest _) "By me, the work was done.")))
    (tibetan-dm-trans-test--with-analysis-file
        (tibetan-dm-trans-test--baseline-analysis)
      (tibetan-dharmamitra-translation-fire-tibetan
       "བདག་གིས་ལས་བྱས།" analysis-file)
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((s (buffer-string)))
          (should (string-match-p
                   "^\\*\\* DharmaMitra Translation$" s))
          (should (string-match-p "By me, the work was done\\." s))
          (should-not (string-match-p
                       "^\\* DharmaMitra Translation (Tibetan)$" s)))))))

(ert-deftest tibetan-dm-trans-fire-tibetan-skips-empty-text ()
  "Empty / nil Tibetan text → no API call, no write.  REGRESSION
GUARD against silent empty-translation writes."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-tibetan))
  (let ((translate-calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (&rest _) (cl-incf translate-calls) "x")))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        (tibetan-dharmamitra-translation-fire-tibetan "" analysis-file)
        (tibetan-dharmamitra-translation-fire-tibetan nil analysis-file)
        (should (= translate-calls 0))))))

(ert-deftest tibetan-dm-trans-fire-tibetan-skips-when-translation-nil ()
  "When chat-translate returns nil (HTTP error / empty response),
the writer is NOT called — analysis file unchanged.  Avoids
overwriting a previous good translation with a failed one."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-tibetan))
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
             (lambda (&rest _) nil)))
    (tibetan-dm-trans-test--with-analysis-file
        (concat (tibetan-dm-trans-test--baseline-analysis)
                "\n* DharmaMitra Translation (Tibetan)\nPRIOR GOOD TRANSLATION\n")
      (tibetan-dharmamitra-translation-fire-tibetan
       "བདག་གིས་ལས་བྱས།" analysis-file)
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (should (string-match-p "PRIOR GOOD TRANSLATION" (buffer-string)))))))

;; ============================================================================
;; PHASE A.1.5 — Predicate to gate auto-fire on existing-file open path
;; ============================================================================
;;
;; Phase A.1 wired DM into the create-new-file branch only.  When
;; the user runs `C-c u A' on an existing seg-NNN.org, the
;; existing-file branch ran instead and DM was skipped — leaving
;; the analysis file without a DM section.  Phase A.1.5 adds a
;; predicate so the existing-file branch can fire DM only when
;; the section is actually missing (idempotent re-runs).

(ert-deftest tibetan-dm-trans-needs-request-p-when-section-missing ()
  "Predicate returns t when the DM section is absent."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-request-p))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (should (tibetan-dharmamitra-translation-needs-request-p
             analysis-file "Tibetan"))))

(ert-deftest tibetan-dm-trans-needs-request-p-when-section-populated ()
  "Predicate returns nil when the NESTED `** DharmaMitra Translation'
section (the post-§5.20 Tibetan-side location the writer actually
populates) has a real body.

Regression for the DharmaMitra request storm:  the predicate searched
the OBSOLETE top-level `* DharmaMitra Translation (Tibetan)' heading,
never matched the nested section, and so always reported `needs
request' — re-firing DM on every file open even when the section was
full."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-request-p))
  (tibetan-dm-trans-test--with-analysis-file
      (replace-regexp-in-string
       "\\[Awaiting DharmaMitra…\\]" "A real translation."
       (tibetan-dm-trans-test--baseline-analysis))
    (should-not (tibetan-dharmamitra-translation-needs-request-p
                 analysis-file "Tibetan"))))

(ert-deftest tibetan-dm-trans-needs-request-p-nested-placeholder-needs-request ()
  "The `[Awaiting DharmaMitra…]' placeholder in the nested section
counts as `needs request', so a freshly-rendered file still gets its
DM translation filled."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-request-p))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)   ; nested [Awaiting DharmaMitra…]
    (should (tibetan-dharmamitra-translation-needs-request-p
             analysis-file "Tibetan"))))

(ert-deftest tibetan-dm-trans-needs-request-p-legacy-toplevel-populated ()
  "A legacy file (pre-§5.20) with a populated TOP-LEVEL
`* DharmaMitra Translation (Tibetan)' and no nested section is still
recognised as populated (back-compat)."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-request-p))
  (tibetan-dm-trans-test--with-analysis-file
      (concat "#+TITLE: Seg\n\n* Tibetan Text\nབདག\n\n"
              "* DharmaMitra Translation (Tibetan)\nLegacy real translation.\n")
    (should-not (tibetan-dharmamitra-translation-needs-request-p
                 analysis-file "Tibetan"))))

(ert-deftest tibetan-dm-trans-needs-request-p-when-section-empty-body ()
  "Predicate returns t when the DM section exists but its body is
empty / whitespace — the section was created but never populated
with a real translation."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-request-p))
  (tibetan-dm-trans-test--with-analysis-file
      (concat (tibetan-dm-trans-test--baseline-analysis)
              "\n* DharmaMitra Translation (Tibetan)\n   \n")
    (should (tibetan-dharmamitra-translation-needs-request-p
             analysis-file "Tibetan"))))

(ert-deftest tibetan-dm-trans-needs-request-p-defaults-to-tibetan ()
  "SOURCE-LANG defaults to `Tibetan' when omitted."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-request-p))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (should (tibetan-dharmamitra-translation-needs-request-p analysis-file))))

(ert-deftest tibetan-dm-trans-needs-request-p-handles-missing-file ()
  "Non-existent ANALYSIS-FILE returns nil (no point firing into
a file that doesn't exist)."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-request-p))
  (should-not (tibetan-dharmamitra-translation-needs-request-p
               "/nonexistent/path/seg-005.org")))

;; ============================================================================
;; fire-for-segment — populated-section gating (the request-storm policy:
;; "renew a populated DM section only on explicit request")
;; ============================================================================

(ert-deftest tibetan-dm-trans-fire-for-segment-skips-populated-tibetan ()
  "fire-for-segment must NOT call the DM API when the Tibetan section
is already populated and no FORCE is given.  Regression for the
request storm — opening an already-translated segment re-fired DM
every time because the Tibetan path fired unconditionally."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
  (let ((calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (&rest _) (cl-incf calls) "X")))
      (tibetan-dm-trans-test--with-analysis-file
          (replace-regexp-in-string
           "\\[Awaiting DharmaMitra…\\]" "A real translation."
           (tibetan-dm-trans-test--baseline-analysis))
        (tibetan-dharmamitra-translation-fire-for-segment
         "བདག་གིས་ལས་བྱས།" analysis-file)
        (should (= calls 0))))))

(ert-deftest tibetan-dm-trans-fire-for-segment-fires-empty-tibetan ()
  "fire-for-segment DOES fire when the Tibetan section is still the
`[Awaiting DharmaMitra…]' placeholder (fresh file)."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
  (let ((calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (&rest _) (cl-incf calls) "X")))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        (tibetan-dharmamitra-translation-fire-for-segment
         "བདག་གིས་ལས་བྱས།" analysis-file)
        (should (= calls 1))))))

(ert-deftest tibetan-dm-trans-fire-for-segment-force-refires-populated ()
  "With FORCE non-nil (explicit C-c u R), fire-for-segment re-fires
even a populated Tibetan section."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
  (let ((calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (&rest _) (cl-incf calls) "X")))
      (tibetan-dm-trans-test--with-analysis-file
          (replace-regexp-in-string
           "\\[Awaiting DharmaMitra…\\]" "A real translation."
           (tibetan-dm-trans-test--baseline-analysis))
        (tibetan-dharmamitra-translation-fire-for-segment
         "བདག་གིས་ལས་བྱས།" analysis-file nil nil t)
        (should (= calls 1))))))

;; ============================================================================
;; PHASE A.2 — Sanskrit translation in parallel-mode docs
;; ============================================================================
;;
;; When the source has `#+SOURCE_MODE: parallel-sanskrit' AND the
;; segment has a `**** Sanskrit' sibling, also fire DM chat-translate
;; on the IAST and write `* DharmaMitra Translation (Sanskrit)' to
;; the analysis file.
;;
;; Plus:  umbrella function `fire-for-segment' that handles BOTH
;; languages so call sites don't have to.

;; ----------------------------------------------------------------------------
;; fire-sanskrit (focused; tested in isolation)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-dm-trans-fire-sanskrit-calls-chat-translate-with-iast ()
  "fire-sanskrit calls chat-translate once with the IAST text."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-sanskrit))
  (let (translate-calls)
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (text &rest _)
                 (push text translate-calls)
                 "stub Sanskrit translation")))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        (tibetan-dharmamitra-translation-fire-sanskrit
         "iha bodhisattvaḥ prakṛtyaiva" analysis-file)
        (should (= (length translate-calls) 1))
        (should (equal (car translate-calls) "iha bodhisattvaḥ prakṛtyaiva"))))))

(ert-deftest tibetan-dm-trans-fire-sanskrit-writes-to-sanskrit-section ()
  "Resulting translation lands in `* DharmaMitra Translation
(Sanskrit)' — NOT in the Tibetan section."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-sanskrit))
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
             (lambda (&rest _) "In this context, a Bodhisattva...")))
    (tibetan-dm-trans-test--with-analysis-file
        (tibetan-dm-trans-test--baseline-analysis)
      (tibetan-dharmamitra-translation-fire-sanskrit
       "iha bodhisattvaḥ prakṛtyaiva" analysis-file)
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((s (buffer-string)))
          (should (string-match-p
                   "^\\* DharmaMitra Translation (Sanskrit)$" s))
          (should (string-match-p "In this context, a Bodhisattva" s))
          ;; Tibetan section was NOT created.
          (should-not (string-match-p
                       "^\\* DharmaMitra Translation (Tibetan)$" s)))))))

(ert-deftest tibetan-dm-trans-fire-sanskrit-skips-empty-text ()
  "Empty / nil Sanskrit text → no API call."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-sanskrit))
  (let ((calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (&rest _) (cl-incf calls) "x")))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        (tibetan-dharmamitra-translation-fire-sanskrit "" analysis-file)
        (tibetan-dharmamitra-translation-fire-sanskrit nil analysis-file)
        (should (= calls 0))))))

(ert-deftest tibetan-dm-trans-fire-sanskrit-skips-placeholder-marker ()
  "When the IAST is a `[Sanskrit alignment exhausted...]'
placeholder (set during the gotrapatala daṇḍa-split prep), no
API call is made — we don't ask DM to translate our own
internal markers."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-sanskrit))
  (let ((calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (&rest _) (cl-incf calls) "x")))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        (tibetan-dharmamitra-translation-fire-sanskrit
         "[Sanskrit alignment exhausted — verify and edit; clause 95 of 69 requested]"
         analysis-file)
        (should (= calls 0))))))

;; ----------------------------------------------------------------------------
;; Umbrella fire-for-segment
;; ----------------------------------------------------------------------------

(defmacro tibetan-dm-trans-test--with-parallel-source-and-sibling (&rest body)
  "Bind SOURCE-FILE to a temp parallel-Sanskrit source with a
Sanskrit sibling on Segment 5; bind ANALYSIS-FILE to a temp seg-005.org."
  (declare (indent 0))
  `(let* ((sdir (make-temp-file "tibetan-dm-trans-src-" t))
          (adir (make-temp-file "tibetan-dm-trans-ana-" t))
          (source-file (expand-file-name "source.org" sdir))
          (analysis-file (expand-file-name "seg-005.org" adir)))
     (unwind-protect
         (progn
           (with-temp-file source-file
             (insert "#+TITLE: T\n"
                     "#+SOURCE_MODE: parallel-sanskrit\n\n"
                     "* Tibetan Text\n"
                     "** Section 1\n*** Sentence 1\n"
                     "**** Segment 5\nསྡོམ་ལ་\n\n"
                     "**** Sanskrit\nuddānam ādhāro liṅgam\n"))
           (with-temp-file analysis-file
             (insert (tibetan-dm-trans-test--baseline-analysis)))
           ,@body)
       (delete-directory sdir t)
       (delete-directory adir t))))

(ert-deftest tibetan-dm-trans-fire-for-segment-fires-tibetan-when-needed ()
  "fire-for-segment fires the Tibetan translation when the section
needs it — the baseline carries the `[Awaiting DharmaMitra…]'
placeholder, so it fires (and Sanskrit does not, lacking source/seg)."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
  (let ((tib-calls 0) (skt-calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-translation-fire-tibetan)
               (lambda (&rest _) (cl-incf tib-calls) t))
              ((symbol-function 'tibetan-dharmamitra-translation-fire-sanskrit)
               (lambda (&rest _) (cl-incf skt-calls) t)))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        ;; No source-file / seg-id given → only Tibetan fires.
        (tibetan-dharmamitra-translation-fire-for-segment
         "བདག་" analysis-file)
        (should (= tib-calls 1))
        (should (= skt-calls 0))))))

(ert-deftest tibetan-dm-trans-fire-for-segment-fires-sanskrit-when-parallel-and-sibling ()
  "fire-for-segment fires Sanskrit when source is parallel-mode AND
the segment has a `**** Sanskrit' sibling."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
  (let ((tib-calls 0) (skt-calls 0) skt-text)
    (cl-letf (((symbol-function 'tibetan-dharmamitra-translation-fire-tibetan)
               (lambda (&rest _) (cl-incf tib-calls) t))
              ((symbol-function 'tibetan-dharmamitra-translation-fire-sanskrit)
               (lambda (text _file &rest _)
                 (cl-incf skt-calls)
                 (setq skt-text text)
                 t)))
      (tibetan-dm-trans-test--with-parallel-source-and-sibling
        (tibetan-dharmamitra-translation-fire-for-segment
         "སྡོམ་ལ་" analysis-file source-file 5)
        (should (= tib-calls 1))
        (should (= skt-calls 1))
        (should (equal skt-text "uddānam ādhāro liṅgam"))))))

(ert-deftest tibetan-dm-trans-fire-for-segment-skips-sanskrit-when-not-parallel ()
  "Non-parallel-mode source → only Tibetan fires; Sanskrit
skipped even if a `**** Sanskrit' sibling somehow exists."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
  (let ((tib-calls 0) (skt-calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-translation-fire-tibetan)
               (lambda (&rest _) (cl-incf tib-calls) t))
              ((symbol-function 'tibetan-dharmamitra-translation-fire-sanskrit)
               (lambda (&rest _) (cl-incf skt-calls) t)))
      (let* ((sdir (make-temp-file "tibetan-dm-trans-nonpar-" t))
             (adir (make-temp-file "tibetan-dm-trans-ana-" t))
             (source-file (expand-file-name "source.org" sdir))
             (analysis-file (expand-file-name "seg-005.org" adir)))
        (unwind-protect
            (progn
              (with-temp-file source-file
                ;; No #+SOURCE_MODE: parallel-sanskrit header.
                (insert "#+TITLE: T\n\n"
                        "* Tibetan Text\n*** Sentence 1\n"
                        "**** Segment 5\nསྡོམ་ལ་\n\n"
                        "**** Sanskrit\nshould not be sent\n"))
              (with-temp-file analysis-file
                (insert (tibetan-dm-trans-test--baseline-analysis)))
              (tibetan-dharmamitra-translation-fire-for-segment
               "སྡོམ་ལ་" analysis-file source-file 5)
              (should (= tib-calls 1))
              (should (= skt-calls 0)))
          (delete-directory sdir t)
          (delete-directory adir t))))))

(ert-deftest tibetan-dm-trans-fire-for-segment-skips-sanskrit-when-no-sibling ()
  "Parallel-mode but no `**** Sanskrit' sibling on the segment →
only Tibetan fires."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
  (let ((tib-calls 0) (skt-calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-translation-fire-tibetan)
               (lambda (&rest _) (cl-incf tib-calls) t))
              ((symbol-function 'tibetan-dharmamitra-translation-fire-sanskrit)
               (lambda (&rest _) (cl-incf skt-calls) t)))
      (let* ((sdir (make-temp-file "tibetan-dm-trans-nosib-" t))
             (adir (make-temp-file "tibetan-dm-trans-ana-" t))
             (source-file (expand-file-name "source.org" sdir))
             (analysis-file (expand-file-name "seg-005.org" adir)))
        (unwind-protect
            (progn
              (with-temp-file source-file
                (insert "#+TITLE: T\n#+SOURCE_MODE: parallel-sanskrit\n\n"
                        "* Tibetan Text\n*** Sentence 1\n"
                        "**** Segment 5\nསྡོམ་ལ་\n\n"
                        ;; No **** Sanskrit sibling.
                        "**** Working Translation\n\n"))
              (with-temp-file analysis-file
                (insert (tibetan-dm-trans-test--baseline-analysis)))
              (tibetan-dharmamitra-translation-fire-for-segment
               "སྡོམ་ལ་" analysis-file source-file 5)
              (should (= tib-calls 1))
              (should (= skt-calls 0)))
          (delete-directory sdir t)
          (delete-directory adir t))))))

;; ----------------------------------------------------------------------------
;; §5.40 Phase 4a — sentence-level DM fire (one call, multi-write)
;; ----------------------------------------------------------------------------

(defun tdmt--scaffold (dir name &optional populated)
  "Minimal segment-layout scaffold with a nested DM slot."
  (let ((f (expand-file-name name dir)))
    (with-temp-file f
      (insert "#+TITLE: X\n\n* Tibetan Text\nབདག\n\n"
              "* Tibetan Analysis\n** Translation\nt\n\n"
              "** DharmaMitra Translation\n"
              (if populated "ALREADY POPULATED\n" "[Awaiting DharmaMitra…]\n")
              "\n* Footnotes\n"))
    f))

(ert-deftest tibetan-dm-sentence-fire-one-call-writes-all ()
  "ONE API call; every child + the sent file carry the sentence label
and the translation; populated children survive non-FORCE."
  (let ((dir (make-temp-file "tdm-sent" t))
        (calls 0))
    (unwind-protect
        (let ((c1 (tdmt--scaffold dir "seg-033.org"))
              (c2 (tdmt--scaffold dir "seg-034.org" 'populated))
              (sf (tdmt--scaffold dir "sent-012.org")))
          (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
                     (lambda (&rest _) (cl-incf calls)
                       "The guru spoke thus.")))
            (tibetan-dharmamitra-translation-fire-tibetan-sentence
             "བདག ཆོས" 12 '(33 34) (list c1 c2) sf nil))
          (should (= 1 calls))
          (let ((s1 (with-temp-buffer (insert-file-contents c1) (buffer-string)))
                (s2 (with-temp-buffer (insert-file-contents c2) (buffer-string)))
                (ss (with-temp-buffer (insert-file-contents sf) (buffer-string))))
            (should (string-match-p "(Sentence 12 — segments 33–34)" s1))
            (should (string-match-p "The guru spoke thus" s1))
            ;; Populated child untouched without FORCE.
            (should (string-match-p "ALREADY POPULATED" s2))
            (should-not (string-match-p "guru spoke" s2))
            ;; Sent file written too.
            (should (string-match-p "The guru spoke thus" ss))))
      (delete-directory dir t))))

(ert-deftest tibetan-dm-sentence-fire-force-and-empty-response ()
  "FORCE overwrites a populated child; an empty API response writes
NOTHING (preserve pattern)."
  (let ((dir (make-temp-file "tdm-sent2" t)))
    (unwind-protect
        (let ((c (tdmt--scaffold dir "seg-040.org" 'populated)))
          ;; FORCE overwrites.
          (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
                     (lambda (&rest _) "Fresh.")))
            (tibetan-dharmamitra-translation-fire-tibetan-sentence
             "བདག" 9 '(40) (list c) nil t))
          (should (string-match-p "Fresh"
                                  (with-temp-buffer (insert-file-contents c)
                                                    (buffer-string))))
          ;; Empty response → nothing written (Fresh stays).
          (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
                     (lambda (&rest _) nil)))
            (tibetan-dharmamitra-translation-fire-tibetan-sentence
             "བདག" 9 '(40) (list c) nil t))
          (should (string-match-p "Fresh"
                                  (with-temp-buffer (insert-file-contents c)
                                                    (buffer-string)))))
      (delete-directory dir t))))

(provide 'tibetan-dharmamitra-translation-test)
;;; tibetan-dharmamitra-translation-test.el ends here
