;;; tibetan-analysis-claude-sections-test.el --- Tests for the three-section Claude integration -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for the Claude response pipeline.
;;
;; As of 2026-04-16, the segment-level workflow is THREE-SECTION:
;;   Claude returns a markdown blob with `## Translation',
;;   `## Vocabulary' (DharmaMitra-style word-by-word), and
;;   `## Grammar' headings.  (The old `## Context' section was
;;   dropped for segment files — it added noise without helping the
;;   translation.)
;;
;; Layout in a per-segment analysis file (seg-NNN*.org):
;;   `** Claude Translation'  (level 2, right after Wylie Transliteration)
;;   `*** Claude Vocabulary'  (level 3, inside `** Provided Translations')
;;   `*** Claude Grammar'     (level 3, inside `** Provided Translations')
;;
;; The Claude parser (`--parse-claude-sections') still recognizes
;; `## Context' for backwards compatibility, and sentence-level
;; analysis files (sent-NNN*.org) still use the four-section layout
;; at level 3.  Those branches are exercised here too.
;;
;; Two adjacent helpers are also covered:
;;   * `tibetan-analysis--read-analysis-parser-sections' — extracts
;;     `** Grammatical Markers' / `** Clause Structure' /
;;     `** Verb Classification (Hill 2010)' from an analysis file.
;;   * `tibetan-analysis--format-parser-grounding' — wraps that plist
;;     into a text block for the user prompt.
;;
;; gptel is stubbed throughout: no network activity.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((root (expand-file-name ".." (file-name-directory
                                    (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path root)
  (add-to-list 'load-path (expand-file-name "core" root))
  (add-to-list 'load-path (expand-file-name "persist" root))
  (add-to-list 'load-path (expand-file-name "analysis" root))
  (add-to-list 'load-path (expand-file-name "data" root))
  (add-to-list 'load-path (expand-file-name "philology" root))
  (add-to-list 'load-path (expand-file-name "config" root)))

(require 'tibetan-analysis-persist)

;; ============================================================================
;; HELPERS
;; ============================================================================

(defun tibetan-sections-test--write (path text)
  "Write TEXT to PATH, creating parent directories."
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert text)))

(defmacro tibetan-sections-test--with-analysis (analysis-contents &rest body)
  "Write ANALYSIS-CONTENTS to a temp seg-001.org, bind ANALYSIS-FILE, eval BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-sections-" t))
          (analysis-file (expand-file-name "seg-001.org" dir)))
     (unwind-protect
         (progn
           (tibetan-sections-test--write analysis-file ,analysis-contents)
           ,@body)
       (delete-directory dir t))))

(defun tibetan-sections-test--scaffold
    (claude-translation claude-grammar &optional claude-vocabulary)
  "Return a realistic segment analysis-file body with the three-section
Claude layout:  `** Claude Translation' at level 2 right after
`** Wylie Transliteration', `*** Claude Vocabulary' and
`*** Claude Grammar' at level 3 inside `** Provided Translations'.
Pass nil for any arg to leave that body empty."
  (concat
   "#+TITLE: Segment 1 Analysis\n"
   "#+TIBETAN_HASH: deadbeef\n\n"
   "* Tibetan Text\n"
   "བདག་གིས་ལས་བྱས།\n\n"
   "* Auto-Analysis\n"
   ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
   "** Wylie Transliteration\n"
   "bdag gis las byas /\n\n"
   "** Claude Translation\n"
   (or claude-translation "")
   "\n\n"
   "** Grammatical Markers\n"
   "- གིས [gis] in «བདག་གིས [bdag gis]» → ERGATIVE (ERG): 'by [previous]'\n\n"
   "** Clause Structure\n"
   "Clause 1 [main]: verb བྱས [byas] — did/made\n\n"
   "** Verb Classification (Hill 2010)\n"
   "- བྱེད [byed] — to do, to make\n  CLASS: Volitional, Transitive, Erg-Abs\n\n"
   "** Sentence Structure\n"
   "- བྱེད [byed]: གིས(གིས) Ø(Ø)\n\n"
   "** Provided Translations\n"
   "*** DharmaMitra\n[stub]\n\n"
   "*** CAT Gloss\n[stub]\n\n"
   "*** Claude Vocabulary\n"
   (or claude-vocabulary "")
   "\n\n"
   "*** Claude Grammar\n"
   (or claude-grammar "")
   "\n\n"
   "*** Reference Translations\n[none]\n\n"
   "* My Notes\n\n\n"
   "* Working Translation\n\n\n"
   "* Footnotes\n\n"))

(defun tibetan-sections-test--sentence-scaffold
    (claude-translation claude-grammar claude-context
     &optional claude-vocabulary)
  "Return a sentence-layout analysis body (four Claude sections at level 3).
Pass nil for any of the CLAUDE-* args to leave that body empty.

The layout mirrors a real sent-NNN.org as produced by
`tibetan-sentence-persist': a `#+SEGMENTS:' header (the canonical
marker that distinguishes sentence files from segment files) and
`* Provided Translations' at org level 1 (top-level) wrapping the
Claude subsections at level 3."
  (concat
   "#+TITLE: Sentence 1 Analysis\n"
   "#+SEGMENTS: 1\n"
   "#+TIBETAN_HASH: cafebabe\n\n"
   "* Tibetan Text\n"
   "བདག་གིས་ལས་བྱས།\n\n"
   "* Provided Translations\n"
   "*** Roehrich\n[stub]\n\n"
   "*** Class Translation\n[stub]\n\n"
   "*** Claude Translation\n"
   (or claude-translation "")
   "\n\n"
   "*** Claude Vocabulary\n"
   (or claude-vocabulary "")
   "\n\n"
   "*** Claude Grammar\n"
   (or claude-grammar "")
   "\n\n"
   "*** Claude Context\n"
   (or claude-context "")
   "\n\n"
   "* Working Translation\n\n\n"
   "* My Notes\n\n\n"
   "* Footnotes\n\n"))

;; ============================================================================
;; --parse-claude-sections
;; ============================================================================

(ert-deftest tibetan-claude-sections-parse-all-four ()
  "Well-formed response with all four headings is split correctly.
The parser still recognizes `## Context' so legacy/sentence responses
parse the same way."
  (let* ((response (concat "## Translation\n"
                           "By me, the work was done.\n\n"
                           "## Vocabulary\n"
                           "bdag, noun, \"I/self\"\n"
                           "gis, ergative, \"by\"\n\n"
                           "## Grammar\n"
                           "གིས marks the agent (Ergative).\n\n"
                           "## Context\n"
                           "First-person reflective voice.\n"))
         (parsed (tibetan-analysis--parse-claude-sections response)))
    (should (equal (plist-get parsed :translation)
                   "By me, the work was done."))
    (should (string-match-p "bdag" (plist-get parsed :vocabulary)))
    (should (string-match-p "Ergative" (plist-get parsed :grammar)))
    (should (string-match-p "first-person reflective"
                            (downcase (plist-get parsed :context))))))

(ert-deftest tibetan-claude-sections-parse-partial ()
  "Missing sections come back nil, not empty string."
  (let* ((response (concat "## Translation\n"
                           "Done.\n\n"
                           "## Grammar\n"
                           "Ergative marker.\n"))
         (parsed (tibetan-analysis--parse-claude-sections response)))
    (should (equal (plist-get parsed :translation) "Done."))
    (should (equal (plist-get parsed :grammar) "Ergative marker."))
    (should (null (plist-get parsed :vocabulary)))
    (should (null (plist-get parsed :context)))))

(ert-deftest tibetan-claude-sections-parse-only-translation ()
  "Only Translation present — Vocabulary, Grammar, and Context are nil."
  (let* ((response "## Translation\nFoo.\n")
         (parsed (tibetan-analysis--parse-claude-sections response)))
    (should (equal (plist-get parsed :translation) "Foo."))
    (should (null (plist-get parsed :vocabulary)))
    (should (null (plist-get parsed :grammar)))
    (should (null (plist-get parsed :context)))))

(ert-deftest tibetan-claude-sections-parse-legacy-fallback ()
  "A response with NO `## ' headings is treated as legacy translation."
  (let* ((response "By me, the work was done.\n\nThis is a translation.")
         (parsed (tibetan-analysis--parse-claude-sections response)))
    (should (string-match-p "By me" (plist-get parsed :translation)))
    (should (null (plist-get parsed :grammar)))
    (should (null (plist-get parsed :context)))))

(ert-deftest tibetan-claude-sections-parse-empty-input ()
  "Nil or empty input returns plist with all nils.
Whitespace-only input is intentionally NOT covered: the legacy fallback
branch trims and stores it as `:translation' (yielding an empty string),
which is acceptable because such a response would have failed earlier in
the gptel pipeline."
  (dolist (input '(nil ""))
    (let ((parsed (tibetan-analysis--parse-claude-sections input)))
      (should (null (plist-get parsed :translation)))
      (should (null (plist-get parsed :vocabulary)))
      (should (null (plist-get parsed :grammar)))
      (should (null (plist-get parsed :context))))))

(ert-deftest tibetan-claude-sections-parse-out-of-order ()
  "Headings out of canonical order are still extracted into the right slot."
  (let* ((response (concat "## Grammar\n"
                           "G body.\n\n"
                           "## Context\n"
                           "C body.\n\n"
                           "## Translation\n"
                           "T body.\n"))
         (parsed (tibetan-analysis--parse-claude-sections response)))
    (should (equal (plist-get parsed :translation) "T body."))
    (should (equal (plist-get parsed :grammar)     "G body."))
    (should (equal (plist-get parsed :context)     "C body."))))

(ert-deftest tibetan-claude-sections-parse-trims-whitespace ()
  "Bodies are trimmed; leading/trailing blank lines are removed."
  (let* ((response (concat "## Translation\n"
                           "\n\nDone.\n\n\n"
                           "## Grammar\n"
                           "   Ergative.   \n"))
         (parsed (tibetan-analysis--parse-claude-sections response)))
    (should (equal (plist-get parsed :translation) "Done."))
    (should (equal (plist-get parsed :grammar) "Ergative."))))

;; ============================================================================
;; --ensure-claude-headings (segment layout)
;; ============================================================================

(ert-deftest tibetan-claude-sections-ensure-from-legacy ()
  "Legacy `*** Claude' under Provided Translations is migrated to
`** Claude Translation' at level 2 (after Wylie); `*** Claude
Vocabulary' lands at level 3 inside Provided Translations.

U4 (2026-04-24): `*** Claude Grammar' now lands at level 3 nested
under `** Grammar' (between Particle Map and Particles list when
present, or at end of Grammar when the scaffold is absent).  When
no `** Grammar' pre-exists, `--ensure-claude-headings' creates a
minimal one so Claude Grammar is always nested.

No Context in segment layout."
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\n"
              "བདག\n\n"
              "* Auto-Analysis\n"
              "** Wylie Transliteration\n"
              "bdag /\n\n"
              "** Provided Translations\n"
              "*** Claude\n"
              "Old translation body.\n\n"
              "*** Reference Translations\n[none]\n")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--ensure-claude-headings (current-buffer))
      (let ((content (buffer-string)))
        ;; Segment-layout target: Translation at level 2, Vocabulary
        ;; at level 3 inside Provided Translations, Grammar at level 3
        ;; inside Grammar (U4).
        (should (string-match-p "^\\*\\* Claude Translation$"    content))
        (should (string-match-p "^\\*\\*\\* Claude Vocabulary$"  content))
        (should (string-match-p "^\\*\\* Grammar$"               content))
        (should (string-match-p "^\\*\\*\\* Claude Grammar$"     content))
        ;; No stray level-2 Claude Grammar post-U4.
        (should-not (string-match-p "^\\*\\* Claude Grammar$"    content))
        ;; Legacy bare heading GONE, no level-3 Translation left over.
        (should-not (string-match-p "^\\*\\*\\* Claude$"             content))
        (should-not (string-match-p "^\\*\\*\\* Claude Translation$" content))
        ;; Context heading is not auto-created in segment layout.
        (should-not (string-match-p "^\\*\\*\\* Claude Context$" content))
        ;; Original body survives under the promoted Translation.
        (should (string-match-p "Old translation body" content))))))

(ert-deftest tibetan-claude-sections-ensure-idempotent ()
  "Calling --ensure-claude-headings twice does not duplicate headings.
U4 (2026-04-24): Claude Grammar is now at level 3 nested under
`** Grammar'; the duplicate check moves accordingly."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "T body" "G body")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--ensure-claude-headings (current-buffer))
      (tibetan-analysis--ensure-claude-headings (current-buffer))
      (let* ((content (buffer-string)))
        (cl-flet ((count-of (re)
                    (cl-loop for start = 0 then (1+ pos)
                             for pos = (string-match re content start)
                             while pos
                             count pos)))
          (should (= 1 (count-of "^\\*\\* Claude Translation$")))
          (should (= 1 (count-of "^\\*\\*\\* Claude Vocabulary$")))
          (should (= 1 (count-of "^\\*\\*\\* Claude Grammar$")))
          ;; No level-2 Grammar duplicates (U4 layout).
          (should (= 0 (count-of "^\\*\\* Claude Grammar$")))
          ;; Context must NOT have been spontaneously created.
          (should (= 0 (count-of "^\\*\\*\\* Claude Context$"))))))))

(ert-deftest tibetan-claude-sections-ensure-grammar-placement ()
  "After migration/insertion the headings sit where the priority
order requires:
  - `** Claude Translation' at level 2, after `** Wylie Transliteration'.
  - `** Grammar' at level 2, after Claude Translation (U4 2026-04-24:
    `--ensure-claude-headings' synthesises this if missing so Claude
    Grammar always has a nested home).
  - `*** Claude Grammar' at level 3 inside `** Grammar'.
  - `*** Claude Vocabulary' at level 3 inside `** Provided Translations',
    before `*** Reference Translations'."
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\n"
              "བདག\n\n"
              "* Auto-Analysis\n"
              "** Wylie Transliteration\n"
              "bdag /\n\n"
              "** Provided Translations\n"
              "*** Claude\n"
              "Body.\n\n"
              "*** Reference Translations\n[none]\n")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--ensure-claude-headings (current-buffer))
      (let* ((content (buffer-string))
             (wylie-pos    (string-match "^\\*\\* Wylie Transliteration$" content))
             (trans-pos    (string-match "^\\*\\* Claude Translation$"    content))
             (gram-pos     (string-match "^\\*\\* Grammar$"               content))
             (cl-gram-pos  (string-match "^\\*\\*\\* Claude Grammar$"     content))
             (provided-pos (string-match "^\\*\\* Provided Translations$" content))
             (vocab-pos    (string-match "^\\*\\*\\* Claude Vocabulary$"  content))
             (ref-pos      (string-match "^\\*\\*\\* Reference Translations$"
                                         content)))
        (should (and wylie-pos trans-pos gram-pos cl-gram-pos
                     provided-pos vocab-pos ref-pos))
        ;; Translation, Grammar, Provided Translations all at level 2
        ;; in that order.
        (should (< wylie-pos trans-pos))
        (should (< trans-pos gram-pos))
        (should (< gram-pos provided-pos))
        ;; Claude Grammar (level 3) sits inside Grammar (between
        ;; Grammar heading and the next level-2 heading).
        (should (< gram-pos cl-gram-pos))
        (should (< cl-gram-pos provided-pos))
        ;; Vocabulary sits inside Provided, before Reference.
        (should (< provided-pos vocab-pos))
        (should (< vocab-pos ref-pos))))))

(ert-deftest tibetan-claude-sections-ensure-sentence-layout-keeps-level-3 ()
  "Sentence-layout buffers (no `** Wylie Transliteration') keep the
four-section level-3 layout and create Vocabulary/Context/Grammar if missing."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--sentence-scaffold "T body" nil nil)
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--ensure-claude-headings (current-buffer))
      (let ((content (buffer-string)))
        ;; Sentence layout keeps all four at level 3.
        (should     (string-match-p "^\\*\\*\\* Claude Translation$" content))
        (should     (string-match-p "^\\*\\*\\* Claude Vocabulary$"  content))
        (should     (string-match-p "^\\*\\*\\* Claude Grammar$"     content))
        (should     (string-match-p "^\\*\\*\\* Claude Context$"     content))
        ;; NO level-2 Claude Translation heading must appear in sentence files.
        (should-not (string-match-p "^\\*\\* Claude Translation$"    content))))))

;; ============================================================================
;; --read-claude-sections + legacy --read-claude-translation
;; ============================================================================

(ert-deftest tibetan-claude-sections-read-segment-layout ()
  "Segment-layout file: Translation at level 2, Vocabulary + Grammar at
level 3 — all are read into the plist.  Context is absent and therefore nil."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "Translation X" "Grammar Y" "Vocab Z")
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Translation X"))
      (should (equal (plist-get p :vocabulary)  "Vocab Z"))
      (should (equal (plist-get p :grammar)     "Grammar Y"))
      (should (null  (plist-get p :context))))))

(ert-deftest tibetan-claude-sections-read-sentence-layout-four-headings ()
  "Sentence-layout file: all four headings at level 3 are read into the plist."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--sentence-scaffold
       "Translation X" "Grammar Y" "Context Z" "Vocab W")
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Translation X"))
      (should (equal (plist-get p :vocabulary)  "Vocab W"))
      (should (equal (plist-get p :grammar)     "Grammar Y"))
      (should (equal (plist-get p :context)     "Context Z")))))

(ert-deftest tibetan-claude-sections-read-legacy-claude-heading ()
  "A file with only `*** Claude' (no Translation/Grammar/Context) still
yields a translation via the legacy fallback."
  (tibetan-sections-test--with-analysis
      (concat "* Auto-Analysis\n"
              "** Provided Translations\n"
              "*** Claude\n"
              "Legacy body.\n\n"
              "*** Reference Translations\n[none]\n")
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Legacy body."))
      (should (null  (plist-get p :grammar)))
      (should (null  (plist-get p :context))))))

(ert-deftest tibetan-claude-sections-read-skips-placeholders ()
  "`[Requesting...]' / `[Claude unavailable...]' / `[Translation not available...]'
bodies count as nothing-to-preserve."
  (dolist (placeholder '("[Requesting translation...]"
                         "[Claude unavailable: foo]"
                         "[Translation not available]"))
    (tibetan-sections-test--with-analysis
        (tibetan-sections-test--scaffold placeholder nil)
      (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
        (should (null (plist-get p :translation)))))))

(ert-deftest tibetan-claude-sections-legacy-translation-wrapper ()
  "`--read-claude-translation' returns just the :translation slot."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "Just T" "Just G")
    (should (equal (tibetan-analysis--read-claude-translation analysis-file)
                   "Just T"))))

;; ============================================================================
;; --insert-claude-sections (writer)
;; ============================================================================

(ert-deftest tibetan-claude-sections-insert-round-trip-segment ()
  "Segment layout: insert a response and read Translation + Vocabulary +
Grammar back.  Any `## Context' in the response is parsed but dropped
\(no Context heading exists in segment layout)."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "[Requesting translation...]" nil)
    (let ((response (concat "## Translation\n"
                            "By me, the work was done.\n\n"
                            "## Vocabulary\n"
                            "bdag, noun, \"I/self\"\n\n"
                            "## Grammar\n"
                            "Ergative on agent.\n\n"
                            "## Context\n"
                            "First-person reflection.\n")))
      (tibetan-analysis--insert-claude-sections response analysis-file)
      ;; Drop any open buffer so the read happens off disk.
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
        (should (equal (plist-get p :translation) "By me, the work was done."))
        (should (string-match-p "bdag" (plist-get p :vocabulary)))
        (should (equal (plist-get p :grammar)     "Ergative on agent."))
        ;; No Context heading → :context nil.
        (should (null (plist-get p :context))))
      ;; And on disk, no `*** Claude Context' was silently created.
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (should-not (string-match-p "^\\*\\*\\* Claude Context$"
                                    (buffer-string)))))))

(ert-deftest tibetan-claude-sections-insert-round-trip-sentence ()
  "Sentence layout: insert a four-section response and read all four back."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--sentence-scaffold
       "[Requesting translation...]" nil nil)
    (let ((response (concat "## Translation\n"
                            "By me, the work was done.\n\n"
                            "## Vocabulary\n"
                            "bdag, noun, \"I/self\"\n\n"
                            "## Grammar\n"
                            "Ergative on agent.\n\n"
                            "## Context\n"
                            "First-person reflection.\n")))
      (tibetan-analysis--insert-claude-sections response analysis-file)
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
        (should (equal (plist-get p :translation) "By me, the work was done."))
        (should (string-match-p "bdag" (plist-get p :vocabulary)))
        (should (equal (plist-get p :grammar)     "Ergative on agent."))
        (should (equal (plist-get p :context)     "First-person reflection."))))))

(ert-deftest tibetan-claude-sections-insert-only-overwrites-present ()
  "Segment layout: if Claude returns only Translation, the existing Grammar
body is left untouched."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "old T" "PRESERVE THIS GRAMMAR")
    (let ((response "## Translation\nnew T body\n"))
      (tibetan-analysis--insert-claude-sections response analysis-file)
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
        (should (equal (plist-get p :translation) "new T body"))
        (should (equal (plist-get p :grammar)     "PRESERVE THIS GRAMMAR"))))))

(ert-deftest tibetan-claude-sections-insert-migrates-legacy-heading ()
  "Inserting into a segment file that still has `*** Claude' migrates
the heading to `** Claude Translation' (level 2), creates
`*** Claude Grammar' at level 3 under `** Grammar' (U4 2026-04-24 —
`** Grammar' is synthesised if not already present), and inserts
`*** Claude Vocabulary' at level 3 inside Provided Translations."
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\n"
              "བདག\n\n"
              "* Auto-Analysis\n"
              "** Wylie Transliteration\n"
              "bdag /\n\n"
              "** Provided Translations\n"
              "*** Claude\n"
              "Old body.\n\n"
              "*** Reference Translations\n[none]\n")
    (tibetan-analysis--insert-claude-sections
     "## Translation\nfresh T\n\n## Vocabulary\nfresh V\n\n## Grammar\nfresh G\n"
     analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((content (buffer-string)))
        (should     (string-match-p "^\\*\\* Claude Translation$"    content))
        (should     (string-match-p "^\\*\\*\\* Claude Vocabulary$"  content))
        (should     (string-match-p "^\\*\\* Grammar$"               content))
        (should     (string-match-p "^\\*\\*\\* Claude Grammar$"     content))
        ;; Post-U4: Claude Grammar is NOT at level 2 any more.
        (should-not (string-match-p "^\\*\\* Claude Grammar$"        content))
        (should-not (string-match-p "^\\*\\*\\* Claude$"             content))
        (should-not (string-match-p "^\\*\\*\\* Claude Translation$" content))
        ;; No spontaneous Context in segment layout.
        (should-not (string-match-p "^\\*\\*\\* Claude Context$"     content))
        (should     (string-match-p "fresh T" content))
        (should     (string-match-p "fresh V" content))
        (should     (string-match-p "fresh G" content))))))

(ert-deftest tibetan-claude-sections-insert-defalias-still-works ()
  "Old single-section name `--insert-claude-translation' is a defalias."
  (should (eq (symbol-function 'tibetan-analysis--insert-claude-translation)
              'tibetan-analysis--insert-claude-sections)))

;; ============================================================================
;; --restore-claude-sections (preserve path used by reanalyze)
;; ============================================================================

(ert-deftest tibetan-claude-sections-restore-round-trip-segment ()
  "Segment layout: `--restore-claude-sections' writes Translation +
Vocabulary + Grammar back faithfully.  A :context in the plist is
dropped (no heading)."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "[Requesting translation...]" nil)
    (tibetan-analysis--restore-claude-sections
     analysis-file
     (list :translation "Restored T"
           :vocabulary  "Restored V"
           :grammar     "Restored G"
           :context     "Discarded C"))
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf (kill-buffer buf)))
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Restored T"))
      (should (equal (plist-get p :vocabulary)  "Restored V"))
      (should (equal (plist-get p :grammar)     "Restored G"))
      ;; :context was not written anywhere — no heading exists.
      (should (null (plist-get p :context))))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (should-not (string-match-p "^\\*\\*\\* Claude Context$" (buffer-string))))))

(ert-deftest tibetan-claude-sections-restore-round-trip-sentence ()
  "Sentence layout: `--restore-claude-sections' writes all four sections."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--sentence-scaffold
       "[Requesting translation...]" nil nil)
    (tibetan-analysis--restore-claude-sections
     analysis-file
     (list :translation "Restored T"
           :vocabulary  "Restored V"
           :grammar     "Restored G"
           :context     "Restored C"))
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf (kill-buffer buf)))
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Restored T"))
      (should (equal (plist-get p :vocabulary)  "Restored V"))
      (should (equal (plist-get p :grammar)     "Restored G"))
      (should (equal (plist-get p :context)     "Restored C")))))

(ert-deftest tibetan-claude-sections-restore-partial-leaves-others ()
  "Segment layout: a partial plist (only :grammar) leaves :translation
body alone."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "Keep T" "Old G")
    (tibetan-analysis--restore-claude-sections
     analysis-file (list :grammar "Brand new G"))
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf (kill-buffer buf)))
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Keep T"))
      (should (equal (plist-get p :grammar)     "Brand new G")))))

(ert-deftest tibetan-claude-sections-restore-preserves-legacy-context ()
  "If a segment file happens to still carry a legacy `*** Claude Context'
heading, `--restore-claude-sections' must preserve its body (round-trip
safety for files migrated from older versions)."
  (tibetan-sections-test--with-analysis
      (concat (tibetan-sections-test--scaffold "T body" "G body")
              "\n*** Claude Context\n"
              "Original C body.\n\n")
    ;; Simulate reanalysis: read the file, then restore the same plist
    ;; we just read so the Context body should round-trip.
    (let* ((p0 (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p0 :context) "Original C body."))
      (tibetan-analysis--restore-claude-sections
       analysis-file
       (list :translation (plist-get p0 :translation)
             :grammar     (plist-get p0 :grammar)
             :context     (plist-get p0 :context)))
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (let ((p1 (tibetan-analysis--read-claude-sections analysis-file)))
        (should (equal (plist-get p1 :context) "Original C body."))))))

(ert-deftest tibetan-claude-sections-restore-legacy-wrapper ()
  "`--restore-claude-translation' wraps a string in {:translation STR}."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "[Requesting translation...]" nil)
    (tibetan-analysis--restore-claude-translation
     analysis-file "Wrapped translation only.")
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf (kill-buffer buf)))
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Wrapped translation only."))
      (should (null (plist-get p :grammar)))
      (should (null (plist-get p :context))))))

;; ============================================================================
;; --read-analysis-parser-sections + --format-parser-grounding
;; ============================================================================

(ert-deftest tibetan-claude-sections-parser-sections-extracted ()
  "All four parser sections in an analysis file land in the plist."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "T" "G")
    (let ((p (tibetan-analysis--read-analysis-parser-sections analysis-file)))
      (should (string-match-p "ERGATIVE" (plist-get p :grammatical-markers)))
      (should (string-match-p "Clause 1" (plist-get p :clause-structure)))
      (should (string-match-p "Volitional"
                              (plist-get p :verb-classification)))
      (should (string-match-p "གིས" (plist-get p :sentence-structure))))))

(ert-deftest tibetan-claude-sections-parser-sections-missing-file-safe ()
  "Nil or non-existent analysis file returns plist of all nils, no error."
  (dolist (path (list nil "/nonexistent/analysis.org"))
    (let ((p (tibetan-analysis--read-analysis-parser-sections path)))
      (should (null (plist-get p :grammatical-markers)))
      (should (null (plist-get p :clause-structure)))
      (should (null (plist-get p :verb-classification)))
      (should (null (plist-get p :sentence-structure))))))

(ert-deftest tibetan-claude-sections-format-parser-grounding-empty ()
  "Plist with all nils returns nil (no empty block in the prompt)."
  (should (null (tibetan-analysis--format-parser-grounding
                 '(:grammatical-markers nil
                   :clause-structure nil
                   :verb-classification nil
                   :sentence-structure nil)))))

(ert-deftest tibetan-claude-sections-format-parser-grounding-renders ()
  "Non-empty plist produces a block that mentions each provided section
and tells Claude to treat it as ground truth."
  (let ((block (tibetan-analysis--format-parser-grounding
                '(:grammatical-markers "ERG body"
                  :clause-structure    "Clause body"
                  :verb-classification "Verb body"
                  :sentence-structure  nil))))
    (should (stringp block))
    (should (string-match-p "ground truth" block))
    (should (string-match-p "ERG body"     block))
    (should (string-match-p "Clause body"  block))
    (should (string-match-p "Verb body"    block))))

;; ============================================================================
;; --build-claude-prompts honours analysis-file (parser-grounding integration)
;; ============================================================================

(ert-deftest tibetan-claude-sections-build-prompt-includes-grounding ()
  "When --build-claude-prompts is given an analysis-file with parser
sections, the user prompt contains the grounding block."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "T" "G")
    (let* ((prompts (tibetan-analysis--build-claude-prompts
                     "བདག་གིས་ལས་བྱས།" nil analysis-file))
           (user (cdr prompts)))
      (should (string-match-p "ground truth" user))
      (should (string-match-p "ERGATIVE"     user))
      (should (string-match-p "Clause 1"     user)))))

(ert-deftest tibetan-claude-sections-build-prompt-no-grounding-without-file ()
  "Without an analysis-file, the user prompt has no parser-grounding block."
  (let* ((prompts (tibetan-analysis--build-claude-prompts
                   "བདག་གིས་ལས་བྱས།" nil))
         (user (cdr prompts)))
    (should-not (string-match-p "ground truth" user))))

;; ============================================================================
;; END-TO-END through --request-claude-translation (gptel stubbed)
;; ============================================================================

(defvar tibetan-sections-test--captured-callback nil)

(ert-deftest tibetan-claude-sections-request-end-to-end ()
  "Stubbed Claude call: a response with Translation + Vocabulary + Grammar
\(and a Context we expect to be dropped) lands under the segment-layout
headings — `** Claude Translation' at level 2, `*** Claude Grammar' at
level 3 under `** Grammar' (U4 2026-04-24), `*** Claude Vocabulary' at
level 3 inside Provided Translations — on the analysis file."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "[Requesting translation...]" nil)
    (setq tibetan-sections-test--captured-callback nil)
    (cl-letf*
        (((symbol-function 'gptel-request)
          (lambda (_prompt &rest args)
            (setq tibetan-sections-test--captured-callback
                  (plist-get args :callback))
            nil))
         ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
          (lambda () t))
         ((symbol-function 'featurep)
          (lambda (feat &rest _) (eq feat 'gptel)))
         ((symbol-function 'fboundp)
          (lambda (sym) (memq sym '(gptel-request
                                    tibetan-analysis--ensure-gptel-ready
                                    tibetan-to-wylie-fixed))))
         ((symbol-function 'tibetan-to-wylie-fixed)
          (lambda (_s) "bdag gis las byas")))
      (tibetan-analysis--request-claude-translation
       "བདག་གིས་ལས་བྱས།" analysis-file nil))
    ;; Simulate Claude's async response (including a Context that must
    ;; be silently discarded in segment layout).
    (should (functionp tibetan-sections-test--captured-callback))
    (funcall tibetan-sections-test--captured-callback
             (concat "## Translation\nE2E translation.\n\n"
                     "## Vocabulary\nE2E vocabulary.\n\n"
                     "## Grammar\nE2E grammar.\n\n"
                     "## Context\nE2E context.\n")
             nil)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf (kill-buffer buf)))
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "E2E translation."))
      (should (equal (plist-get p :vocabulary)  "E2E vocabulary."))
      (should (equal (plist-get p :grammar)     "E2E grammar."))
      (should (null (plist-get p :context))))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((content (buffer-string)))
        (should     (string-match-p "^\\*\\* Claude Translation$"    content))
        (should     (string-match-p "^\\*\\*\\* Claude Vocabulary$"  content))
        (should     (string-match-p "^\\*\\* Grammar$"               content))
        (should     (string-match-p "^\\*\\*\\* Claude Grammar$"     content))
        ;; Post-U4: Claude Grammar is NOT at level 2 any more.
        (should-not (string-match-p "^\\*\\* Claude Grammar$"        content))
        (should-not (string-match-p "^\\*\\*\\* Claude Context$"     content))))))

;; ============================================================================
;; --parse-claude-vocabulary
;; ============================================================================

(ert-deftest tibetan-claude-vocabulary-parse-basic ()
  "Standard DharmaMitra-style lines are parsed into (key . line) alist."
  (let* ((text (concat "bdag, noun, \"I/self\", first-person pronoun\n"
                       "gis, ergative, \"by\", agentive case marker\n"
                       "las, noun, \"action/karma\", direct object here\n"
                       "byas, verb-past, \"did/made\", main verb\n"))
         (result (tibetan-analysis--parse-claude-vocabulary text)))
    (should (= (length result) 4))
    (should (equal (car (nth 0 result)) "bdag"))
    (should (equal (car (nth 1 result)) "gis"))
    (should (equal (car (nth 2 result)) "las"))
    (should (equal (car (nth 3 result)) "byas"))
    ;; Full line is preserved
    (should (string-match-p "^bdag, noun" (cdr (nth 0 result))))))

(ert-deftest tibetan-claude-vocabulary-parse-skips-blanks-and-separators ()
  "Blank lines and `---' separators are skipped."
  (let* ((text (concat "\n"
                       "bdag, noun, \"I/self\"\n"
                       "\n"
                       "---\n"
                       "gis, ergative, \"by\"\n"
                       "\n"))
         (result (tibetan-analysis--parse-claude-vocabulary text)))
    (should (= (length result) 2))
    (should (equal (car (nth 0 result)) "bdag"))
    (should (equal (car (nth 1 result)) "gis"))))

(ert-deftest tibetan-claude-vocabulary-parse-nil-and-empty ()
  "Nil and empty strings return empty list."
  (should (null (tibetan-analysis--parse-claude-vocabulary nil)))
  (should (null (tibetan-analysis--parse-claude-vocabulary "")))
  (should (null (tibetan-analysis--parse-claude-vocabulary "   "))))

(ert-deftest tibetan-claude-vocabulary-parse-key-normalisation ()
  "Keys are lowercased and trimmed."
  (let* ((text "  Bdag Gis , noun-phrase, \"by me\"\n")
         (result (tibetan-analysis--parse-claude-vocabulary text)))
    (should (= (length result) 1))
    (should (equal (car (nth 0 result)) "bdag gis"))))

(ert-deftest tibetan-claude-vocabulary-parse-no-comma-line ()
  "A line without a comma is skipped (no Wylie key extractable)."
  (let* ((text "this line has no comma\nbdag, noun, \"I\"\n")
         (result (tibetan-analysis--parse-claude-vocabulary text)))
    (should (= (length result) 1))
    (should (equal (car (nth 0 result)) "bdag"))))

;; ============================================================================
;; --merge-claude-vocabulary
;; ============================================================================

(defun tibetan-merge-test--word-list-scaffold ()
  "Return a minimal seg-analysis body with a Word / Particle List."
  (concat
   "#+TITLE: Segment 1 Analysis\n"
   "#+TIBETAN_HASH: deadbeef\n\n"
   "* Tibetan Text\n"
   "བདག་གིས་ལས་བྱས།\n\n"
   "* Auto-Analysis\n"
   ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
   "** Wylie Transliteration\n"
   "bdag gis las byas /\n\n"
   "** Claude Translation\n"
   "By me, the work was done.\n\n"
   "** Grammatical Markers\n"
   "- གིས [gis] → ERGATIVE\n\n"
   "** Clause Structure\n"
   "Clause 1 [main]\n\n"
   "** Verb Classification (Hill 2010)\n"
   "- བྱེད [byed]\n\n"
   "** Sentence Structure\n"
   "- བྱེད: གིས(གིས) Ø(Ø)\n\n"
   "** Provided Translations\n"
   "*** DharmaMitra\n[stub]\n\n"
   "*** CAT Gloss\n[stub]\n\n"
   "*** Claude Vocabulary\n\n"
   "*** Claude Grammar\n[stub]\n\n"
   "*** Reference Translations\n[none]\n\n"
   "** Word / Particle List\n"
   " 1. བདག [bdag] — self\n"
   "    ★ Resources: I, myself\n"
   " 2. གིས [gis] — ERGATIVE\n"
   "    ★ Resources: by (case marker)\n"
   " 3. ལས [las] — action\n"
   "    ★ Resources: karma; action\n"
   " 4. བྱས [byas] — did\n"
   "    ★ Resources: past of byed\n\n"
   "* My Notes\n\n\n"
   "* Footnotes\n\n"))

(ert-deftest tibetan-claude-vocabulary-merge-basic ()
  "Matching Claude vocabulary lines are inserted as ◇ tier-2 entries."
  (let* ((scaffold (tibetan-merge-test--word-list-scaffold))
         (vocab-text (concat "bdag, noun, \"I/self\", first-person pronoun\n"
                             "byas, verb-past, \"did/made\", main verb\n")))
    (with-temp-buffer
      (insert scaffold)
      (tibetan-analysis--merge-claude-vocabulary (current-buffer) vocab-text)
      (let ((content (buffer-string)))
        ;; ◇ lines present after matching entries
        (should (string-match-p
                 " 1\\. བདག \\[bdag\\].*\n    ★.*\n    ◇ bdag, noun"
                 content))
        (should (string-match-p
                 " 4\\. བྱས \\[byas\\].*\n    ★.*\n    ◇ byas, verb-past"
                 content))
        ;; Non-matching entries have no ◇ line
        (should-not (string-match-p "gis.*\n.*◇" content))
        (should-not (string-match-p "las.*\n.*◇ las," content))))))

(ert-deftest tibetan-claude-vocabulary-merge-idempotent ()
  "Running merge twice produces the same result (no duplicate ◇ lines)."
  (let* ((scaffold (tibetan-merge-test--word-list-scaffold))
         (vocab-text "bdag, noun, \"I/self\", first-person pronoun\n"))
    (with-temp-buffer
      (insert scaffold)
      (tibetan-analysis--merge-claude-vocabulary (current-buffer) vocab-text)
      (let ((after-first (buffer-string)))
        (tibetan-analysis--merge-claude-vocabulary (current-buffer) vocab-text)
        (should (equal (buffer-string) after-first))))))

(ert-deftest tibetan-claude-vocabulary-merge-nil-noop ()
  "Nil or empty vocab-text is a no-op."
  (let ((scaffold (tibetan-merge-test--word-list-scaffold)))
    (with-temp-buffer
      (insert scaffold)
      (let ((before (buffer-string)))
        (tibetan-analysis--merge-claude-vocabulary (current-buffer) nil)
        (should (equal (buffer-string) before))
        (tibetan-analysis--merge-claude-vocabulary (current-buffer) "")
        (should (equal (buffer-string) before))))))

(ert-deftest tibetan-claude-vocabulary-merge-replaces-stale ()
  "Re-merging with different vocab replaces old ◇ lines."
  (let* ((scaffold (tibetan-merge-test--word-list-scaffold))
         (vocab-v1 "bdag, noun, \"I/self\", first-person pronoun\n")
         (vocab-v2 "bdag, pronoun, \"self/I\", updated gloss\n"))
    (with-temp-buffer
      (insert scaffold)
      (tibetan-analysis--merge-claude-vocabulary (current-buffer) vocab-v1)
      (should (string-match-p "◇ bdag, noun" (buffer-string)))
      (tibetan-analysis--merge-claude-vocabulary (current-buffer) vocab-v2)
      (let ((content (buffer-string)))
        (should (string-match-p "◇ bdag, pronoun" content))
        (should-not (string-match-p "◇ bdag, noun" content))))))

(ert-deftest tibetan-claude-sections-auto-regen-on-particles-arrival ()
  "Pass 6c: when Claude's response includes a `## Particles' block,
`--insert-claude-sections' automatically calls `reanalyze-file'
(without re-requesting Claude) so the Grammar section picks up
the new tuples and re-renders with Portfolio snippets inline.

Gated by `tibetan-analysis-auto-regen-on-claude-arrival' (default
t).  Test asserts the regen is invoked when Particles arrives, AND
skipped when the customvar is nil, AND skipped when the response
has no Particles block (even with the customvar default on)."
  (let* ((tmp (make-temp-file "tibetan-auto-regen-" t))
         (file (expand-file-name "seg-009.org" tmp))
         (regen-calls '()))
    (unwind-protect
        (progn
          ;; Minimal file with the required heading scaffolding so
          ;; `--insert-claude-sections' doesn't trip on missing heads
          ;; before it reaches the auto-regen branch.
          (with-temp-file file
            (insert "#+TITLE: Seg 9\n\n* Tibetan Text\nfoo\n\n"
                    "* Auto-Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie Transliteration\nfoo /\n\n"
                    "** Provided Translations\n"
                    "*** DharmaMitra\n[stub]\n\n"
                    "*** Claude Vocabulary\n\n\n"
                    "* Footnotes\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-reanalyze-file)
                     (lambda (fp &rest args)
                       (push (cons fp args) regen-calls)
                       `(:file ,fp :ok t))))
            ;; 1. Default on — particles arrival triggers regen.
            (let ((tibetan-analysis-auto-regen-on-claude-arrival t)
                  (response (concat
                             "## Translation\nX.\n\n"
                             "## Grammar\nY.\n\n"
                             "## Particles\n"
                             "mthu'i, 'i, 1.1.1, attributive\n")))
              (tibetan-analysis--insert-claude-sections response file))
            (should (= 1 (length regen-calls)))
            ;; Regen called with `:re-request-claude nil' to prevent
            ;; an infinite Claude-arrival → regen → Claude-arrival loop.
            (let ((args (cdr (car regen-calls))))
              (should (equal (plist-get args :re-request-claude) nil)))
            ;; 2. Opt-out: customvar nil → no regen.
            (setq regen-calls '())
            (let ((tibetan-analysis-auto-regen-on-claude-arrival nil)
                  (response (concat
                             "## Translation\nX.\n\n"
                             "## Particles\n"
                             "mthu'i, 'i, 1.1.1, attributive\n")))
              (tibetan-analysis--insert-claude-sections response file))
            (should (zerop (length regen-calls)))
            ;; 3. No Particles block → no regen even with customvar on.
            (setq regen-calls '())
            (let ((tibetan-analysis-auto-regen-on-claude-arrival t)
                  (response "## Translation\nNo particles block.\n"))
              (tibetan-analysis--insert-claude-sections response file))
            (should (zerop (length regen-calls)))))
      (when (file-exists-p file) (delete-file file))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(provide 'tibetan-analysis-claude-sections-test)
;;; tibetan-analysis-claude-sections-test.el ends here
