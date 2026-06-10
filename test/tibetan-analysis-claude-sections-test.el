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

The third arg is named CLAUDE-CONTEXT for backwards-compat with
existing call sites;  §5.24 (2026-05-22) renames the heading to
`*** Concept Notes' at level 3 (the body content is independent
of the heading name).

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
   "*** Concept Notes\n"
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
                            (downcase (plist-get parsed :concepts))))))

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
    (should (null (plist-get parsed :concepts)))))

(ert-deftest tibetan-claude-sections-parse-only-translation ()
  "Only Translation present — Vocabulary, Grammar, and Context are nil."
  (let* ((response "## Translation\nFoo.\n")
         (parsed (tibetan-analysis--parse-claude-sections response)))
    (should (equal (plist-get parsed :translation) "Foo."))
    (should (null (plist-get parsed :vocabulary)))
    (should (null (plist-get parsed :grammar)))
    (should (null (plist-get parsed :concepts)))))

(ert-deftest tibetan-claude-sections-parse-legacy-fallback ()
  "A response with NO `## ' headings is treated as legacy translation."
  (let* ((response "By me, the work was done.\n\nThis is a translation.")
         (parsed (tibetan-analysis--parse-claude-sections response)))
    (should (string-match-p "By me" (plist-get parsed :translation)))
    (should (null (plist-get parsed :grammar)))
    (should (null (plist-get parsed :concepts)))))

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
      (should (null (plist-get parsed :concepts))))))

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
    (should (equal (plist-get parsed :concepts)     "C body."))))

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

(ert-deftest tibetan-claude-sections-should-fire-policy ()
  "§5.22 follow-up (2026-05-21):  `tibetan-analysis--should-fire-claude-p'
implements the three-way `re-request-claude' policy:

  · `nil'             → never fire (returns nil).
  · `t'               → always fire (returns t).
  · `:missing-only'   → fire only when `--claude-needs-request-p'
                         reports the file's Translation/Vocabulary
                         slots are missing or placeholders.

User feedback (2026-05-21):  \"if (Claude and DharmaMitra)
translation already exists it should only be renewed on
explicit request.\"  Default for batch reanalyze interactive
prompt is `:missing-only';  explicit `[a]lways' still available."
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\nbdag\n\n"
              "* Tibetan Analysis\n"
              "** Wylie Transliteration\nbdag /\n\n"
              "** Claude Vocabulary\nbdag, pronoun, \"I\"\n\n"
              "** Translation\nI did the work.\n\n")
    ;; File HAS populated Claude content.
    (should-not (tibetan-analysis--claude-needs-request-p analysis-file))
    ;; Policy: nil → nil, t → t, :missing-only → nil (populated).
    (should-not (tibetan-analysis--should-fire-claude-p nil analysis-file))
    (should (tibetan-analysis--should-fire-claude-p t analysis-file))
    (should-not (tibetan-analysis--should-fire-claude-p
                 :missing-only analysis-file)))
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\nbdag\n\n"
              "* Tibetan Analysis\n"
              "** Wylie Transliteration\nbdag /\n\n"
              "** Claude Vocabulary\n[Awaiting Claude…]\n\n"
              "** Translation\n[Requesting translation...]\n\n")
    ;; File has PLACEHOLDER content only.
    (should (tibetan-analysis--claude-needs-request-p analysis-file))
    ;; Policy: :missing-only → t (needs request).
    (should (tibetan-analysis--should-fire-claude-p
             :missing-only analysis-file))
    ;; nil still nil; t still t.
    (should-not (tibetan-analysis--should-fire-claude-p nil analysis-file))
    (should (tibetan-analysis--should-fire-claude-p t analysis-file))))

(ert-deftest tibetan-claude-sections-migrate-past-vocab-placeholder ()
  "BUG-FIX (2026-05-21):  when the file has BOTH:
  · `** Claude Vocabulary' at level 2 with the empty `[Awaiting
    Claude…]' placeholder (emitted by the new §5.21 scaffold), AND
  · `*** Claude Vocabulary' at level 3 under `** Provided
    Translations' with REAL content (from a pre-§5.21 Claude
    response stored at the legacy slot)
the migrator must MOVE the legacy content up to the level-2 slot.

Pre-fix behaviour:  the migrator's guard checked only whether
`** Claude Vocabulary' EXISTS at level 2, and skipped migration
because the placeholder body satisfied that check — stranding
the legacy content under Provided Translations forever.

Post-fix behaviour:  guard now treats placeholder body as
\"slot effectively empty, do migrate\".  Real-content body
still suppresses migration (idempotency)."
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\n"
              "བདག\n\n"
              "* Tibetan Analysis\n"
              "** Wylie Transliteration\n"
              "bdag /\n\n"
              "** Claude Vocabulary\n"
              "[Awaiting Claude…]\n\n"
              "** Translation\n"
              "[Requesting translation...]\n\n"
              "** Grammar\n"
              "*** Claude Grammar\n\n\n"
              "** Provided Translations\n"
              "*** Claude Vocabulary\n"
              "bdag, pronoun, \"I/self\", first-person honorific\n"
              "gis, ergative, \"by\", marks the agent\n\n"
              "*** Claude Translation\n"
              "I did the work.\n\n"
              "*** Reference Translations\n[none]\n")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--migrate-legacy-claude-headings (current-buffer))
      (let ((content (buffer-string)))
        ;; Level-2 Claude Vocabulary now has the real content.
        (should (string-match-p "bdag, pronoun" content))
        (should (string-match-p "gis, ergative" content))
        ;; Legacy level-3 Claude Vocabulary heading is gone.
        (should-not (string-match-p "^\\*\\*\\* Claude Vocabulary$"
                                    content))
        ;; Level-2 Vocabulary placeholder is gone — body has been replaced.
        (let* ((vocab-pos (string-match
                           "^\\*\\* Claude Vocabulary$" content))
               (after (and vocab-pos (substring content vocab-pos))))
          (should after)
          ;; Body following the level-2 heading is the real content,
          ;; not the [Awaiting…] placeholder.
          (should-not (string-match-p
                       "\\`\\*\\* Claude Vocabulary\n\\[Awaiting"
                       after)))
        ;; Translation:  same migration story.
        (should (string-match-p "I did the work" content))
        (should-not (string-match-p "^\\*\\*\\* Claude Translation$"
                                    content))))))

(ert-deftest tibetan-claude-sections-migrate-idempotent-on-real-content ()
  "Migration must NOT clobber a level-2 slot that already has REAL
content.  When the level-2 `** Claude Vocabulary' body is genuine
\(not a placeholder), the migrator leaves it alone — even if a
legacy level-3 slot also exists (precedence to the new slot).

Regression guard for the bug fix:  the placeholder-detection
must distinguish `[Awaiting Claude…]' (= empty) from real
content (= non-empty / authoritative)."
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\n"
              "བདག\n\n"
              "* Tibetan Analysis\n"
              "** Wylie Transliteration\n"
              "bdag /\n\n"
              "** Claude Vocabulary\n"
              "REAL-LEVEL-2-CONTENT: bdag = self\n\n"
              "** Grammar\n"
              "*** Claude Grammar\n\n\n"
              "** Provided Translations\n"
              "*** Claude Vocabulary\n"
              "STALE-LEGACY-CONTENT: bdag = ego\n\n"
              "*** Reference Translations\n[none]\n")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--migrate-legacy-claude-headings (current-buffer))
      (let ((content (buffer-string)))
        ;; Level-2 body preserved (NOT clobbered by stale legacy).
        (should (string-match-p "REAL-LEVEL-2-CONTENT" content))
        ;; Legacy level-3 heading either gone (cleaned up) OR present
        ;; with its content;  either way, level-2 was not touched.
        ;; Stale content does not bleed into level-2.
        (let* ((vocab-pos (string-match
                           "^\\*\\* Claude Vocabulary$" content))
               (next-l2 (string-match
                         "^\\*\\* [A-Z]"
                         (substring content (1+ vocab-pos))))
               (vocab-body (substring content
                                      vocab-pos
                                      (+ 1 vocab-pos next-l2))))
          (should-not (string-match-p "STALE-LEGACY-CONTENT"
                                      vocab-body)))))))

(ert-deftest tibetan-claude-sections-ensure-from-legacy ()
  "Legacy `*** Claude' under Provided Translations is migrated to
`** Translation' at level 2 (§5.18 rename) and §5.21 promotes
Claude Vocabulary to LEVEL 2 too (between Interlinear and
Translation).  Grammar stays at level 3 nested under `**
Grammar' (U4).  No Context in segment layout."
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
        (should (string-match-p "^\\*\\* Translation$"    content))
        ;; §5.21:  Claude Vocabulary lives at LEVEL 2 now.
        (should (string-match-p "^\\*\\* Claude Vocabulary$"     content))
        (should-not (string-match-p "^\\*\\*\\* Claude Vocabulary$" content))
        (should (string-match-p "^\\*\\* Grammar$"               content))
        (should (string-match-p "^\\*\\*\\* Claude Grammar$"     content))
        (should-not (string-match-p "^\\*\\* Claude Grammar$"    content))
        (should-not (string-match-p "^\\*\\*\\* Claude$"             content))
        (should-not (string-match-p "^\\*\\*\\* Claude Translation$" content))
        (should-not (string-match-p "^\\*\\*\\* Claude Context$" content))
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
          (should (= 1 (count-of "^\\*\\* Translation$")))
          ;; §5.21:  Claude Vocabulary at level 2, idempotent.
          (should (= 1 (count-of "^\\*\\* Claude Vocabulary$")))
          (should (= 0 (count-of "^\\*\\*\\* Claude Vocabulary$")))
          (should (= 1 (count-of "^\\*\\*\\* Claude Grammar$")))
          ;; No level-2 Grammar duplicates (U4 layout).
          (should (= 0 (count-of "^\\*\\* Claude Grammar$")))
          ;; Context must NOT have been spontaneously created.
          (should (= 0 (count-of "^\\*\\*\\* Claude Context$"))))))))

(ert-deftest tibetan-claude-sections-ensure-grammar-placement ()
  "After migration/insertion the headings sit where the priority
order requires:
  - `** Translation' at level 2, after `** Wylie Transliteration'.
  - `** Claude Vocabulary' at level 2 (§5.21), after Wylie.
  - `** Grammar' at level 2, after Translation (U4 2026-04-24:
    `--ensure-claude-headings' synthesises this if missing so Claude
    Grammar always has a nested home).
  - `*** Claude Grammar' at level 3 inside `** Grammar'."
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
             (trans-pos    (string-match "^\\*\\* Translation$"    content))
             (vocab-pos    (string-match "^\\*\\* Claude Vocabulary$"  content))
             (gram-pos     (string-match "^\\*\\* Grammar$"               content))
             (cl-gram-pos  (string-match "^\\*\\*\\* Claude Grammar$"     content))
             (provided-pos (string-match "^\\*\\* Provided Translations$" content))
             (ref-pos      (string-match "^\\*\\*\\* Reference Translations$"
                                         content)))
        (should (and wylie-pos trans-pos vocab-pos gram-pos cl-gram-pos
                     provided-pos ref-pos))
        ;; §5.21 canonical order:
        ;;   Wylie → Claude Vocabulary → Translation → Grammar → Provided.
        ;; Claude Vocabulary lands right after Wylie (matches the
        ;; scaffold's render-order — annotations follow word-for-word
        ;; before the fluent translations).
        (should (< wylie-pos vocab-pos))
        (should (< vocab-pos trans-pos))
        (should (< trans-pos gram-pos))
        (should (< gram-pos provided-pos))
        ;; Claude Grammar (level 3) sits inside Grammar (between
        ;; Grammar heading and the next level-2 heading).
        (should (< gram-pos cl-gram-pos))
        (should (< cl-gram-pos provided-pos))))))

(ert-deftest tibetan-claude-sections-ensure-sentence-layout-keeps-level-3 ()
  "Sentence-layout buffers (no `** Wylie Transliteration') keep the
four-section level-3 layout and create Vocabulary / Concept Notes /
Grammar if missing.

§5.24 (2026-05-22):  the fourth heading is renamed from
`*** Claude Context' to `*** Concept Notes' (sentence files keep
L3;  legacy `Claude Context' migrates via Step 6 of
`--migrate-legacy-claude-headings')."
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
        (should     (string-match-p "^\\*\\*\\* Concept Notes$"      content))
        ;; NO level-2 Claude Translation heading must appear in sentence files.
        (should-not (string-match-p "^\\*\\* Translation$"    content))))))

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
      (should (null  (plist-get p :concepts))))))

(ert-deftest tibetan-claude-sections-read-sentence-layout-four-headings ()
  "Sentence-layout file: all four headings at level 3 are read into the plist."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--sentence-scaffold
       "Translation X" "Grammar Y" "Context Z" "Vocab W")
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Translation X"))
      (should (equal (plist-get p :vocabulary)  "Vocab W"))
      (should (equal (plist-get p :grammar)     "Grammar Y"))
      (should (equal (plist-get p :concepts)     "Context Z")))))

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
      (should (null  (plist-get p :concepts))))))

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
Grammar + Concept Notes back.

§5.24 (2026-05-22):  segment layout now has `** Concept Notes' at
LEVEL 2 (was previously absent for segment files).  Legacy
`## Context' heading in the response is still parsed and routed
to the same `:concepts' slot for migration."
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
        ;; §5.24:  segment layout now writes `** Concept Notes' L2.
        (should (equal (plist-get p :concepts)    "First-person reflection.")))
      ;; On disk:  `** Concept Notes' present at L2;  legacy
      ;; `*** Claude Context' NOT present.
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (should     (string-match-p "^\\*\\* Concept Notes$"     (buffer-string)))
        (should-not (string-match-p "^\\*\\*\\* Claude Context$" (buffer-string)))))))

(ert-deftest tibetan-claude-sections-insert-round-trip-sentence ()
  "Sentence layout: insert a four-section response and read all four back.

§5.24 (2026-05-22):  the fourth heading is now `*** Concept Notes'
at L3 (was `*** Claude Context');  legacy `## Context' heading
still parses and routes to the same `:concepts' slot."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--sentence-scaffold
       "[Requesting translation...]" nil nil)
    (let ((response (concat "## Translation\n"
                            "By me, the work was done.\n\n"
                            "## Vocabulary\n"
                            "bdag, noun, \"I/self\"\n\n"
                            "## Grammar\n"
                            "Ergative on agent.\n\n"
                            "## Concept Notes\n"
                            "First-person reflection.\n")))
      (tibetan-analysis--insert-claude-sections response analysis-file)
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
        (should (equal (plist-get p :translation) "By me, the work was done."))
        (should (string-match-p "bdag" (plist-get p :vocabulary)))
        (should (equal (plist-get p :grammar)     "Ergative on agent."))
        (should (equal (plist-get p :concepts)    "First-person reflection."))))))

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
the heading to `** Translation' (level 2, §5.18 rename), promotes
`*** Claude Vocabulary' to LEVEL 2 (§5.21 Commit 2/7, 2026-05-20),
creates `*** Claude Grammar' at level 3 under `** Grammar' (U4
2026-04-24)."
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
        (should     (string-match-p "^\\*\\* Translation$"    content))
        ;; §5.21:  Claude Vocabulary lives at LEVEL 2, not 3.
        (should     (string-match-p "^\\*\\* Claude Vocabulary$"     content))
        (should-not (string-match-p "^\\*\\*\\* Claude Vocabulary$"  content))
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
Vocabulary + Grammar + Concept Notes back faithfully.

§5.24 (2026-05-22):  segment layout now has `** Concept Notes' at
LEVEL 2 — `:concepts' is written to that slot, not dropped."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "[Requesting translation...]" nil)
    (tibetan-analysis--restore-claude-sections
     analysis-file
     (list :translation "Restored T"
           :vocabulary  "Restored V"
           :grammar     "Restored G"
           :concepts    "Restored C"))
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf (kill-buffer buf)))
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Restored T"))
      (should (equal (plist-get p :vocabulary)  "Restored V"))
      (should (equal (plist-get p :grammar)     "Restored G"))
      ;; §5.24:  :concepts now written at L2 `** Concept Notes'.
      (should (equal (plist-get p :concepts)    "Restored C")))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (should     (string-match-p "^\\*\\* Concept Notes$"     (buffer-string)))
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
           :concepts     "Restored C"))
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf (kill-buffer buf)))
    (let ((p (tibetan-analysis--read-claude-sections analysis-file)))
      (should (equal (plist-get p :translation) "Restored T"))
      (should (equal (plist-get p :vocabulary)  "Restored V"))
      (should (equal (plist-get p :grammar)     "Restored G"))
      (should (equal (plist-get p :concepts)     "Restored C")))))

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
      (should (equal (plist-get p0 :concepts) "Original C body."))
      (tibetan-analysis--restore-claude-sections
       analysis-file
       (list :translation (plist-get p0 :translation)
             :grammar     (plist-get p0 :grammar)
             :concepts     (plist-get p0 :concepts)))
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (let ((p1 (tibetan-analysis--read-claude-sections analysis-file)))
        (should (equal (plist-get p1 :concepts) "Original C body."))))))

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
      (should (null (plist-get p :concepts))))))

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
\(and Concept Notes) lands under the segment-layout headings —
`** Translation' at L2, `*** Claude Grammar' at L3 under `**
Grammar' (U4 2026-04-24), `** Claude Vocabulary' at L2 (§5.21
Commit 2/7), `** Concept Notes' at L2 (§5.24, 2026-05-22).
Legacy `## Context' in the response is parsed and routed to
the `:concepts' slot for migration."
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
      ;; §5.24:  segment layout now writes `** Concept Notes' L2;
      ;; legacy `## Context' response routes to `:concepts'.
      (should (equal (plist-get p :concepts)    "E2E context.")))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((content (buffer-string)))
        (should     (string-match-p "^\\*\\* Translation$"    content))
        ;; §5.21:  Claude Vocabulary at LEVEL 2.
        (should     (string-match-p "^\\*\\* Claude Vocabulary$"     content))
        (should-not (string-match-p "^\\*\\*\\* Claude Vocabulary$"  content))
        (should     (string-match-p "^\\*\\* Grammar$"               content))
        (should     (string-match-p "^\\*\\*\\* Claude Grammar$"     content))
        ;; Post-U4: Claude Grammar is NOT at level 2 any more.
        (should-not (string-match-p "^\\*\\* Claude Grammar$"        content))
        ;; §5.24:  `** Concept Notes' present;  legacy NOT.
        (should     (string-match-p "^\\*\\* Concept Notes$"         content))
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

;; Retired 2026-05-20 (§5.21 Commit 2/7):  the 4 tibetan-claude-
;; vocabulary-merge-* tests exercised
;; `tibetan-analysis--merge-claude-vocabulary' which merged Claude
;; Vocabulary entries as ◇ tier-2 lines into `** Word / Particle
;; List'.  §5.10 retired the Word/Particle List section in April —
;; the merge was a silent no-op for 7 months.  §5.21 promotes
;; Claude Vocabulary to its own level-2 section between Interlinear
;; and Translation;  the merge is finally deleted along with the
;; helper.  Coverage replaced by
;; `tibetan-analysis-claude-vocabulary-at-level-2' (in
;; `tibetan-analysis-persist-test.el').

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

;; ============================================================================
;; PHASE 4 — `### Tibetan Divergence' sub-heading round-trip
;; ============================================================================
;;
;; In sanskrit-parallel mode (Phase 3), the Claude system prompt
;; instructs the model to emit an optional `### Tibetan Divergence'
;; markdown sub-heading inside `## Translation' when the Tibetan
;; rendering diverges meaningfully from the Sanskrit.  These tests
;; prove the round-trip:
;;
;;   1. The parser passes the sub-heading through verbatim into the
;;      `:translation' body string — no fork of
;;      `--parse-claude-sections', no new top-level field.
;;
;;   2. The writer converts the markdown sub-heading to a real org
;;      heading nested under the parent Claude Translation heading,
;;      so the user can fold and navigate it.
;;       - Segment layout (parent at level 2) → divergence at level 3
;;       - Sentence layout (parent at level 3) → divergence at level 4
;;
;;   3. The reader returns the Translation body INCLUDING the
;;      converted sub-heading (because `--claude-stop-re' only stops
;;      at headings AT the parent level or shallower — deeper
;;      sub-headings are preserved as part of the body).
;;
;;   4. Backward compatibility:  Translations without `### ' lines
;;      are written and read back unchanged.

(ert-deftest tibetan-claude-sections-parser-preserves-divergence-subheading ()
  "The parser keeps `### Tibetan Divergence' verbatim inside the
:translation body.  The schema does not fork — Phase 3 only adds
content; the parser is unchanged."
  (let* ((response (concat "## Translation\n"
                           "From the Sanskrit: I came after praising.\n\n"
                           "### Tibetan Divergence\n"
                           "stod nas reads as a sequential converb here, "
                           "not the manner-clause scope a Sanskrit reader "
                           "would assume.\n\n"
                           "## Vocabulary\n"
                           "stod, verb, praise\n\n"
                           "## Grammar\n"
                           "ERG on agent.\n"))
         (sections (tibetan-analysis--parse-claude-sections response))
         (translation (plist-get sections :translation)))
    (should translation)
    (should (string-match-p "From the Sanskrit" translation))
    (should (string-match-p "### Tibetan Divergence" translation))
    (should (string-match-p "sequential converb" translation))
    ;; The Vocabulary block is correctly separated — divergence
    ;; doesn't leak into the next section.
    (should (equal (plist-get sections :vocabulary)
                   "stod, verb, praise"))
    (should (equal (plist-get sections :grammar)
                   "ERG on agent."))))

(ert-deftest tibetan-claude-sections-md-h3-to-org-helper-callable ()
  "The markdown-→-org conversion helper is fbound and accepts
(BODY PARENT-LEVEL) → STRING."
  (should (fboundp 'tibetan-analysis--claude-body-md-h3-to-org))
  (let ((out (tibetan-analysis--claude-body-md-h3-to-org
              "### foo\nbody\n" 2)))
    (should (stringp out))))

(ert-deftest tibetan-claude-sections-md-h3-to-org-converts-parent-level-2 ()
  "`### foo' under a level-2 parent becomes `*** foo' (level 3 —
one level deeper than the parent)."
  (let ((out (tibetan-analysis--claude-body-md-h3-to-org
              "Body line.\n### Tibetan Divergence\nNote text.\n" 2)))
    (should (string-match-p "^\\*\\*\\* Tibetan Divergence$" out))
    (should-not (string-match-p "^### Tibetan Divergence" out))
    (should (string-match-p "Body line" out))
    (should (string-match-p "Note text" out))))

(ert-deftest tibetan-claude-sections-md-h3-to-org-converts-parent-level-3 ()
  "`### foo' under a level-3 parent becomes `**** foo' (level 4)."
  (let ((out (tibetan-analysis--claude-body-md-h3-to-org
              "### Tibetan Divergence\nNote.\n" 3)))
    (should (string-match-p "^\\*\\*\\*\\* Tibetan Divergence$" out))
    (should-not (string-match-p "^\\*\\*\\* Tibetan Divergence$" out))))

(ert-deftest tibetan-claude-sections-md-h3-to-org-leaves-non-h3-alone ()
  "Body lines that do NOT start with `### ' (and even `## '
top-level headings — Claude shouldn't emit those inside a
section, but defensive) are returned unchanged."
  (let ((out (tibetan-analysis--claude-body-md-h3-to-org
              "Plain prose.\n## Not a sub-heading.\nMore prose.\n"
              2)))
    (should (string-match-p "Plain prose" out))
    (should (string-match-p "## Not a sub-heading" out))
    ;; No spurious `*** ' lines inserted.
    (should-not (string-match-p "^\\*+ Plain" out))
    (should-not (string-match-p "^\\*+ Not a" out))
    (should-not (string-match-p "^\\*+ More" out))))

(ert-deftest tibetan-claude-sections-md-h3-to-org-only-line-start ()
  "Only `### ' at the start of a line is converted.  Mid-line
`###' (e.g. inside prose) is preserved as-is."
  (let ((out (tibetan-analysis--claude-body-md-h3-to-org
              "He cited section ### 4.5 of the text.\n" 2)))
    (should (string-match-p "section ### 4\\.5" out))
    (should-not (string-match-p "^\\*\\*\\* 4" out))))

(ert-deftest tibetan-claude-sections-writer-emits-divergence-as-org-heading-segment ()
  "Segment layout (`** Claude Translation' at level 2):  the
writer dumps Translation body and converts `### Tibetan Divergence'
to a level-3 org sub-heading nested under the parent."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "[Requesting translation...]" nil)
    (let ((response (concat "## Translation\n"
                            "From the Sanskrit: I came after praising.\n\n"
                            "### Tibetan Divergence\n"
                            "stod nas: sequential converb scope.\n\n"
                            "## Vocabulary\n"
                            "stod, praise\n\n"
                            "## Grammar\n"
                            "ERG on agent.\n")))
      (tibetan-analysis--insert-claude-sections response analysis-file)
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((s (buffer-string)))
          ;; Original markdown form is gone.
          (should-not (string-match-p "^### Tibetan Divergence" s))
          ;; Real org sub-heading at level 3 is present.
          (should (string-match-p "^\\*\\*\\* Tibetan Divergence$" s))
          ;; Translation body preserved.
          (should (string-match-p "From the Sanskrit" s))
          ;; Divergence note text preserved.
          (should (string-match-p "sequential converb scope" s))
          ;; Translation parent is still level 2.
          (should (string-match-p "^\\*\\* Translation$" s)))))))

(ert-deftest tibetan-claude-sections-writer-emits-divergence-as-org-heading-sentence ()
  "Sentence layout (`*** Claude Translation' at level 3):  the
writer converts `### Tibetan Divergence' to a level-4 org
sub-heading nested under the parent."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--sentence-scaffold
       "[Requesting translation...]" nil nil)
    (let ((response (concat "## Translation\n"
                            "Sanskrit-driven translation.\n\n"
                            "### Tibetan Divergence\n"
                            "Tibetan glosses sandhied form.\n\n"
                            "## Grammar\nfine\n")))
      (tibetan-analysis--insert-claude-sections response analysis-file)
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((s (buffer-string)))
          (should (string-match-p "^\\*\\*\\*\\* Tibetan Divergence$" s))
          (should-not (string-match-p "^### Tibetan Divergence" s))
          (should-not (string-match-p "^\\*\\*\\* Tibetan Divergence$" s)))))))

(ert-deftest tibetan-claude-sections-writer-no-divergence-leaves-body-clean ()
  "Translation without `### ' lines is written verbatim — no
spurious org headings created.  REGRESSION GUARD: existing non-
parallel documents must keep producing today's body shape."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "[Requesting translation...]" nil)
    (let ((response (concat "## Translation\n"
                            "Plain English translation.\n"
                            "Continued prose with no sub-heading.\n"
                            "## Grammar\n"
                            "ERG on agent\n")))
      (tibetan-analysis--insert-claude-sections response analysis-file)
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((s (buffer-string)))
          (should (string-match-p "Plain English translation" s))
          (should (string-match-p "Continued prose" s))
          ;; No spurious sub-headings under Claude Translation.
          (should-not (string-match-p "^\\*\\*\\* Plain" s))
          (should-not (string-match-p "^\\*\\*\\* Continued" s)))))))

(ert-deftest tibetan-claude-sections-divergence-roundtrips-through-reader ()
  "After insert, `--read-claude-sections' returns the Translation
body INCLUDING the converted org sub-heading and its prose.  The
reader's stop-re for level 2 only halts at level-2-or-shallower
headings, so deeper `***' children are preserved as part of the
body — exactly what reanalysis with `:re-request-claude nil'
needs to round-trip the divergence."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--scaffold "[Requesting translation...]" nil)
    (let ((response (concat "## Translation\n"
                            "Sanskrit-primary translation.\n\n"
                            "### Tibetan Divergence\n"
                            "Tibetan stod nas: sequential converb.\n\n"
                            "## Vocabulary\n"
                            "stod, praise\n\n"
                            "## Grammar\n"
                            "fine\n")))
      (tibetan-analysis--insert-claude-sections response analysis-file)
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf (kill-buffer buf)))
      (let* ((p (tibetan-analysis--read-claude-sections analysis-file))
             (translation (plist-get p :translation)))
        (should (stringp translation))
        ;; Translation prose preserved.
        (should (string-match-p "Sanskrit-primary translation" translation))
        ;; Org sub-heading preserved as part of the body.
        (should (string-match-p "^\\*\\*\\* Tibetan Divergence$" translation))
        ;; Divergence note text preserved.
        (should (string-match-p "sequential converb" translation))
        ;; Vocabulary correctly separated.
        (should (string-match-p "stod, praise"
                                (plist-get p :vocabulary)))))))

;; ============================================================================
;; Phase 1.3 of layout-revision §5.18 (2026-05-04):
;;
;; Segment-layout: `** Claude Translation' → `** Translation'.  Parent
;; context (`* Tibetan Analysis') makes the language-attribution clear,
;; so the redundant `Claude' qualifier on the sub-heading drops.  Level-3
;; `*** Claude Vocabulary' / `*** Claude Particles' / `*** Claude Grammar'
;; KEEP their `Claude' prefix — they sit under `** Grammar' or
;; `** Provided Translations' where the prefix still disambiguates.
;;
;; Sentence-layout (`*** Claude Translation' at level 3): keeps the legacy
;; name as a carve-out — sentence files are not in the parallel-Sanskrit
;; pipeline.
;; ============================================================================

(ert-deftest tibetan-analysis-claude-segment-emits-translation-heading-not-claude-translation ()
  "Phase 1.3 of layout-revision §5.18 (2026-05-04):  on a fresh
segment-layout file (with `** Wylie Transliteration', i.e. the
segment marker), `--ensure-claude-headings' emits the level-2
heading `** Translation' (was `** Claude Translation')."
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\nbdag\n\n"
              "* Tibetan Analysis\n"
              "** Wylie Transliteration\nbdag /\n\n")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--ensure-claude-headings (current-buffer))
      (let ((content (buffer-string)))
        (should (string-match-p "^\\*\\* Translation$" content))
        (should-not (string-match-p "^\\*\\* Claude Translation$" content))))))

(ert-deftest tibetan-analysis-claude-restore-reads-old-claude-translation-and-rewrites-as-translation ()
  "Phase 1.3 migration:  a fixture with `** Claude Translation'
\(legacy level-2 heading) round-trips through
`--ensure-claude-headings' into `** Translation' with the body
preserved verbatim.  This is the on-disk migration that lets
existing seg-NNN.org files transition cleanly on first reanalyse."
  (tibetan-sections-test--with-analysis
      (concat "* Tibetan Text\nbdag\n\n"
              "* Tibetan Analysis\n"
              "** Wylie Transliteration\nbdag /\n\n"
              "** Claude Translation\n"
              "LEGACY-BODY-MUST-SURVIVE\n\n"
              "** Provided Translations\n"
              "*** DharmaMitra\n[stub]\n\n"
              "*** Reference Translations\n[none]\n")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--ensure-claude-headings (current-buffer))
      (let ((content (buffer-string)))
        (should (string-match-p "^\\*\\* Translation$" content))
        (should-not (string-match-p "^\\*\\* Claude Translation$" content))
        (should (string-match-p "LEGACY-BODY-MUST-SURVIVE" content))))))

(ert-deftest tibetan-analysis-claude-sentence-layout-keeps-claude-translation ()
  "Phase 1.3 carve-out:  sentence-layout files keep the legacy
`*** Claude Translation' (level 3) heading.  Sentence layout is
not in the parallel-Sanskrit pipeline; only segment-layout
\(detected by the `** Wylie Transliteration' marker) renames."
  (tibetan-sections-test--with-analysis
      (tibetan-sections-test--sentence-scaffold "T body" nil nil)
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (tibetan-analysis--ensure-claude-headings (current-buffer))
      (let ((content (buffer-string)))
        (should (string-match-p "^\\*\\*\\* Claude Translation$" content))
        ;; And NO bare level-2 `** Translation' that would belong only
        ;; to the segment layout.
        (should-not (string-match-p "^\\*\\* Translation$" content))))))

;; ============================================================================
;; §5.25 (2026-05-24) — Thesaurus zettel cross-link helpers
;; ============================================================================

(ert-deftest tibetan-claude-zettel-format-block-empty ()
  "`--format-zettel-references-block' with nil/empty input returns
the empty string so the caller can unconditionally concat."
  (should (equal "" (tibetan-analysis--format-zettel-references-block nil)))
  (should (equal "" (tibetan-analysis--format-zettel-references-block '()))))

(ert-deftest tibetan-claude-zettel-format-block-with-zettels ()
  "`--format-zettel-references-block' renders zettel plists into a
prompt-injectable block with a header and one bullet per zettel."
  (let* ((zettels (list (list :id "abc-123"
                              :wylie "bdag"
                              :sanskrit "ātman"
                              :primary-en "self, I"
                              :primary-de nil)
                        (list :id "xyz-789"
                              :wylie "mthu"
                              :sanskrit nil
                              :primary-en nil
                              :primary-de "Macht, Zauber")))
         (block (tibetan-analysis--format-zettel-references-block zettels)))
    (should (stringp block))
    ;; Header is present and instructs Claude to cite via org-link.
    (should (string-match-p "Concept Notes" block))
    (should (string-match-p "\\[\\[id:ZID\\]\\[zettel" block))
    ;; Bullets include ZID + Wylie + (Skt. or DE) + EN/DE primary.
    (should (string-match-p "bdag (ZID:abc-123).*ātman.*self, I" block))
    ;; German fallback when no English primary.
    (should (string-match-p "mthu (ZID:xyz-789).*Macht, Zauber" block))))

(ert-deftest tibetan-claude-zettel-cross-link-no-thesaurus-noop ()
  "`--cross-link-zettels-in-body' is a no-op when the thesaurus
module isn't loaded — returns BODY unchanged."
  (cl-letf (((symbol-function 'tibetan-thesaurus-lookup) nil))
    ;; fmakunbound-style: not fboundp, so the helper bails early.
    (fmakunbound 'tibetan-thesaurus-lookup)
    (unwind-protect
        (let ((body "- **bdag** — self, I\n- **mthu** — power\n"))
          (should (equal body
                         (tibetan-analysis--cross-link-zettels-in-body body))))
      (defun tibetan-thesaurus-lookup (_) nil))))

(ert-deftest tibetan-claude-zettel-cross-link-appends-link ()
  "`--cross-link-zettels-in-body' appends `[[id:ZID][zettel ↗]]'
to bolded Tibetan-term lines that match a thesaurus zettel."
  (cl-letf (((symbol-function 'tibetan-thesaurus-lookup)
             (lambda (wylie)
               (cond
                ((equal (string-trim wylie) "bdag")
                 (list (list :id "abc-123" :wylie "bdag")))
                (t nil))))
            ((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (s) s)))
    (let* ((body (concat "- **bdag** — self, I (Skt. ātman)\n"
                         "- **mthu** — power, sorcery\n"))
           (out (tibetan-analysis--cross-link-zettels-in-body body)))
      ;; bdag has a zettel → link appended.
      (should (string-match-p "bdag\\*\\*.*\\[\\[id:abc-123\\]\\[zettel" out))
      ;; mthu has no zettel → no link.
      (should-not (string-match-p "mthu\\*\\*.*\\[\\[id:" out)))))

(ert-deftest tibetan-claude-zettel-cross-link-idempotent-existing-link ()
  "`--cross-link-zettels-in-body' does NOT re-append a link when
the line already carries one (idempotent for double-runs)."
  (cl-letf (((symbol-function 'tibetan-thesaurus-lookup)
             (lambda (wylie)
               (cond
                ((equal (string-trim wylie) "bdag")
                 (list (list :id "abc-123" :wylie "bdag")))
                (t nil))))
            ((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (s) s)))
    (let* ((body "- **bdag** — self [[id:abc-123][zettel ↗]]\n")
           (out (tibetan-analysis--cross-link-zettels-in-body body)))
      ;; Still exactly ONE link on the bdag line (not two).
      (should (= 1 (let ((count 0)
                         (start 0))
                     (while (string-match "\\[\\[id:abc-123\\]" out start)
                       (setq count (1+ count))
                       (setq start (match-end 0)))
                     count))))))

(ert-deftest tibetan-claude-zettel-collect-references-no-thesaurus-nil ()
  "`--collect-zettel-references' returns nil when the thesaurus
module isn't loaded — silent fall-through."
  (cl-letf (((symbol-function 'tibetan-thesaurus-lookup) nil))
    (fmakunbound 'tibetan-thesaurus-lookup)
    (unwind-protect
        (should-not (tibetan-analysis--collect-zettel-references "བདག"))
      (defun tibetan-thesaurus-lookup (_) nil))))

;; ============================================================================
;; C1 (Fable-5 audit, 2026-06-04): section-body bounds must not stop at
;; markdown-bold / org-emphasis lines.  `^\*{1,N}[^*\n]' matched `**Bold:'
;; and `*emphasis*', truncating every preserve-side reader at the first
;; such body line — preserve-mode reanalyze then destroyed the tail
;; (the §5.26 data-loss class; live trigger: MA Reading sent-001.org).
;; ============================================================================

(ert-deftest tibetan-claude-stop-re-ignores-bold-and-emphasis-lines ()
  "The stop regexp matches real org headings (stars + space) only —
never `**bold' or `*emphasis' body lines."
  (let ((re (tibetan-analysis--claude-stop-re 2)))
    ;; Real headings match.
    (should (string-match-p re "* My Notes"))
    (should (string-match-p re "** Translation"))
    ;; A deeper heading must NOT match a level-2 stop.
    (should-not (string-match-p re "*** Claude Grammar"))
    ;; Markdown-bold / org-emphasis body lines must NOT match.
    (should-not (string-match-p re "**Clause 1 (subordinate):** text"))
    (should-not (string-match-p re "*correction* maybe"))))

(ert-deftest tibetan-claude-sections-roundtrip-body-with-bold-lines ()
  "A Claude Translation body containing `**bold' and `*emphasis' lines
is read back IN FULL by --read-claude-sections (no truncation)."
  (let ((f (make-temp-file "seg-bold" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert "#+TITLE: Segment 1 Analysis\n\n"
                    "* Tibetan Analysis\n"
                    "** Translation\n"
                    "First line of the translation.\n"
                    "**Register note:** honorific throughout.\n"
                    "*sic* in the manuscript.\n"
                    "Last line after the bold.\n"
                    "** Grammar\n"
                    "grammar body\n"))
          (let* ((p (tibetan-analysis--read-claude-sections f))
                 (tr (plist-get p :translation)))
            (should tr)
            (should (string-match-p "Register note" tr))
            (should (string-match-p "Last line after the bold" tr))
            ;; And the next section was not swallowed.
            (should-not (string-match-p "grammar body" tr))))
      (delete-file f))))

(ert-deftest tibetan-claude-body-writer-sanitizes-line-leading-stars ()
  "C1b: Claude bodies are LLM text — a line-leading `*' run would
become an org heading mid-file (restructuring the document and, before
the C1a bound fix, truncating preserve readers).  The writer
space-prefixes such lines, exactly like the §5.28 DharmaMitra
sanitizer.  Markdown `### ' sub-headings must still convert to org
headings (the md-h3-to-org path runs AFTER sanitization)."
  (with-temp-buffer
    (insert "* Tibetan Analysis\n** Translation\n[Awaiting Claude…]\n\n** Grammar\ng\n")
    (tibetan-analysis--replace-claude-section-body
     (current-buffer) "Translation"
     "Line one.\n**Bold note:** stays body text.\n* would-be heading\n### Divergence\nnote body"
     2)
    (let ((s (buffer-string)))
      ;; Star-leading lines neutralised (space-prefixed) — no new headings.
      (should (string-match-p "^ \\*\\*Bold note:\\*\\*" s))
      (should (string-match-p "^ \\* would-be heading" s))
      ;; The md ### still becomes a real org heading at level+1.
      (should (string-match-p "^\\*\\*\\* Divergence" s))
      ;; Grammar section untouched.
      (should (string-match-p "^\\*\\* Grammar\ng" s)))))

(provide 'tibetan-analysis-claude-sections-test)
;;; tibetan-analysis-claude-sections-test.el ends here
