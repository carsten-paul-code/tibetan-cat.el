;;; tibetan-segment-migrate-test.el --- Tests for segment-migrate -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for tibetan-migrate-inline-segments-to-headings.

;;; Code:

(require 'ert)
(require 'tibetan-segment-migrate)

(ert-deftest tibetan-migrate-single-segment-with-translation ()
  "A basic 〔seg:1〕+〔trans:1〕 pair becomes a *** Segment 1 heading."
  (let* ((input "〔seg:1〕རྣལ་འབྱོར་གྱི་དབང་ཕྱུག་མིད་ལ་རས་པ་ནི།〔/seg〕
〔trans:1〕
Concerning the lord of the Yoga Mid la ras pa
〔/trans〕")
         (out (tibetan-migrate--convert-string input)))
    (should (string-match-p "^\\*\\*\\* Segment 1$" out))
    (should (string-match-p "རྣལ་འབྱོར་གྱི་དབང་ཕྱུག" out))
    (should (string-match-p "^\\*\\*\\*\\* Working Translation$" out))
    (should (string-match-p "Concerning the lord of the Yoga" out))
    ;; no inline tags remain
    (should-not (string-match-p "〔seg:" out))
    (should-not (string-match-p "〔trans:" out))))

(ert-deftest tibetan-migrate-empty-translation-keeps-heading ()
  "An empty 〔trans:N〕 block still yields a Working Translation heading."
  (let* ((input "〔seg:13〕ཤིན་དུ་ཁས་ཉེན་པར་བྱུང་བ་ལ།〔/seg〕
〔trans:13〕
〔/trans〕")
         (out (tibetan-migrate--convert-string input)))
    (should (string-match-p "^\\*\\*\\* Segment 13$" out))
    (should (string-match-p "^\\*\\*\\*\\* Working Translation$" out))
    ;; No spurious content after the heading
    (should-not (string-match-p "〔/trans〕" out))))

(ert-deftest tibetan-migrate-multiline-tibetan-preserved ()
  "Tibetan text with an embedded newline (OCR artefact) is preserved."
  (let* ((input "〔seg:40〕སྣུབས་ཆུང་གི་རྩར་སོང་ཟེར་ནས་འཕན་
ཆས་འགའ་ཞིག་དང་།〔/seg〕
〔trans:40〕
〔/trans〕")
         (out (tibetan-migrate--convert-string input)))
    (should (string-match-p "སྣུབས་ཆུང" out))
    (should (string-match-p "ཆས་འགའ་ཞིག" out))
    (should (string-match-p "^\\*\\*\\* Segment 40$" out))))

(ert-deftest tibetan-migrate-multiple-segments-in-sequence ()
  "Several consecutive segments all get converted."
  (let* ((input "〔seg:1〕FOO།〔/seg〕
〔trans:1〕
bar
〔/trans〕
〔seg:2〕BAZ།〔/seg〕
〔trans:2〕
qux
〔/trans〕")
         (out (tibetan-migrate--convert-string input)))
    (should (string-match-p "\\*\\*\\* Segment 1" out))
    (should (string-match-p "\\*\\*\\* Segment 2" out))
    (should (string-match-p "bar" out))
    (should (string-match-p "qux" out))
    (should-not (string-match-p "〔" out))))

(ert-deftest tibetan-migrate-preserves-file-header ()
  "Content before the first 〔seg:〕 tag is left untouched."
  (let* ((input "#+TITLE: Test
#+TIBETAN_CLAUDE_CONTEXT: sample

* Text

〔seg:1〕FOO།〔/seg〕
〔trans:1〕bar〔/trans〕")
         (out (tibetan-migrate--convert-string input)))
    (should (string-match-p "^#\\+TITLE: Test" out))
    (should (string-match-p "^#\\+TIBETAN_CLAUDE_CONTEXT: sample" out))
    (should (string-match-p "^\\* Text" out))
    (should (string-match-p "\\*\\*\\* Segment 1" out))))

(ert-deftest tibetan-migrate-idempotent ()
  "Running the migration on already-migrated text is a no-op."
  (let* ((input "#+TITLE: Test
* Text
*** Segment 1
FOO།

**** Working Translation
bar
")
         (out1 (tibetan-migrate--convert-string input))
         (out2 (tibetan-migrate--convert-string out1)))
    (should (string= input out1))
    (should (string= out1 out2))))

(ert-deftest tibetan-migrate-buffer-command-rewrites-buffer ()
  "The interactive command rewrites the current buffer in place."
  (with-temp-buffer
    (insert "〔seg:5〕TEST།〔/seg〕
〔trans:5〕
translated
〔/trans〕")
    (tibetan-migrate-inline-segments-to-headings)
    (let ((s (buffer-string)))
      (should (string-match-p "\\*\\*\\* Segment 5" s))
      (should (string-match-p "translated" s))
      (should-not (string-match-p "〔" s)))))

(ert-deftest tibetan-migrate-handles-trailing-shad-chars ()
  "Tibetan text ending in shad (།) is preserved verbatim, including multiple shads."
  (let* ((input "〔seg:7〕ཐུགས་དམ།།〔/seg〕
〔trans:7〕
thugs dam
〔/trans〕")
         (out (tibetan-migrate--convert-string input)))
    (should (string-match-p "ཐུགས་དམ།།" out))
    (should (string-match-p "thugs dam" out))))

;; ============================================================================
;; BARE-SEG MIGRATOR — for documents without 〔trans:N〕 pairs
;; ============================================================================
;;
;; The Thar-rgyan / Josefine pipeline produces a different inline format:
;; only 〔seg:N〕...〔/seg〕 (no translation wrapper).  In addition,
;; Tibetan-title headings carry an inline 〔/seg〕 at the end of the
;; heading line to close the previous segment:
;;
;;     〔seg:1〕metadata-inside-segment
;;     * མཚན་བྱང་།〔/seg〕       ← closes seg:1
;;     〔seg:2〕(Title)
;;
;;     ...
;;
;; The bare-seg migrator must:
;;   1. Split heading lines ending in 〔/seg〕 so that 〔/seg〕 is on its
;;      own line and the heading becomes a uniform `** Section'.
;;   2. Convert every 〔seg:N〕...〔/seg〕 block to `*** Segment M' with
;;      fresh numbering starting at 1 (the original N is discarded).
;;   3. Hoist document-level `#+KEYWORD:' lines that landed inside
;;      segment bodies (a quirk of the original pipeline where seg:1
;;      often contained all the document headers) to the top of the
;;      result.  Segments that become empty after hoisting are dropped.
;;   4. Leave structural headings (`* Document Info', `* Text', `* NOTES')
;;      alone — they are recognised by the ABSENCE of an inline 〔/seg〕
;;      on their line.

(ert-deftest tibetan-migrate-bare-single-block ()
  "Smallest well-formed case: one 〔seg:N〕...〔/seg〕 block."
  (let* ((input "〔seg:5〕Hello world.〔/seg〕\n")
         (out (tibetan-migrate--convert-bare-string input)))
    (should (string-match-p "^\\*\\*\\* Segment 1$" out))
    (should (string-match-p "Hello world\\." out))
    (should-not (string-match-p "〔seg:" out))
    (should-not (string-match-p "〔/seg〕" out))))

(ert-deftest tibetan-migrate-bare-renumbers-from-one ()
  "Numbering is fresh; original N values are discarded."
  (let* ((input "〔seg:5〕A〔/seg〕\n〔seg:7〕B〔/seg〕\n〔seg:42〕C〔/seg〕\n")
         (out (tibetan-migrate--convert-bare-string input)))
    (should (string-match-p "^\\*\\*\\* Segment 1$" out))
    (should (string-match-p "^\\*\\*\\* Segment 2$" out))
    (should (string-match-p "^\\*\\*\\* Segment 3$" out))
    (should-not (string-match-p "^\\*\\*\\* Segment 5$" out))))

(ert-deftest tibetan-migrate-bare-flattens-title-headings ()
  "Heading lines ending in 〔/seg〕 are split + flattened to `** Section'
regardless of original level (`*', `**', `***').

Real Josefine pattern: the inline `〔/seg〕' on a heading line closes
the PREVIOUS segment — the heading itself is NOT part of that segment,
it's a standalone title placed between segments in the source layout."
  (let* ((input
          (concat "〔seg:1〕metadata\n"
                  "* མཚན་བྱང་།〔/seg〕\n"
                  "〔seg:2〕first section body\n"
                  "with line 2\n"
                  "** རིགས་ལྔ།〔/seg〕\n"
                  "〔seg:3〕fives types body\n"
                  "*** ངོ་བོ།〔/seg〕\n"
                  "〔seg:4〕essence body〔/seg〕\n"))
         (out (tibetan-migrate--convert-bare-string input)))
    (should (string-match-p "^\\*\\* མཚན་བྱང་།$" out))
    (should (string-match-p "^\\*\\* རིགས་ལྔ།$" out))
    (should (string-match-p "^\\*\\* ངོ་བོ།$" out))
    ;; no original `*** ` Tibetan titles survived
    (should-not (string-match-p "^\\*\\*\\* ངོ་བོ།" out))
    ;; no stray 〔/seg〕 anywhere
    (should-not (string-match-p "〔/seg〕" out))))

(ert-deftest tibetan-migrate-bare-preserves-structural-headings ()
  "`* Document Info', `* Text', `* NOTES' (heading lines WITHOUT 〔/seg〕)
stay at their original level 1."
  (let* ((input
          (concat "* Document Info\n"
                  ":PROPERTIES:\n:KEY: value\n:END:\n\n"
                  "* Text\n\n"
                  "〔seg:1〕body〔/seg〕\n"
                  "* NOTES :editorial:\n"))
         (out (tibetan-migrate--convert-bare-string input)))
    (should (string-match-p "^\\* Document Info$" out))
    (should (string-match-p "^\\* Text$" out))
    (should (string-match-p "^\\* NOTES :editorial:$" out))))

(ert-deftest tibetan-migrate-bare-hoists-metadata-from-segments ()
  "`#+KEYWORD: value' lines inside a segment body move to the top."
  (let* ((input
          (concat "* Document Info\n\n"
                  "* Text\n\n"
                  "〔seg:1〕#+TITLE: The Book\n"
                  "#+AUTHOR: Someone\n"
                  "#+TIBETAN_CLAUDE_CONTEXT: Context line one.\n"
                  "#+TIBETAN_CLAUDE_CONTEXT: Context line two.\n"
                  "〔/seg〕\n"
                  "〔seg:2〕real body here\n"
                  "more text〔/seg〕\n"))
         (out (tibetan-migrate--convert-bare-string input)))
    ;; Metadata lines appear BEFORE * Document Info
    (let ((doc-info-pos (string-match "^\\* Document Info" out))
          (title-pos    (string-match "^#\\+TITLE: The Book" out))
          (author-pos   (string-match "^#\\+AUTHOR: Someone" out))
          (ctx1-pos     (string-match "^#\\+TIBETAN_CLAUDE_CONTEXT: Context line one\\." out))
          (ctx2-pos     (string-match "^#\\+TIBETAN_CLAUDE_CONTEXT: Context line two\\." out)))
      (should title-pos)
      (should author-pos)
      (should ctx1-pos)
      (should ctx2-pos)
      (should doc-info-pos)
      (should (< title-pos doc-info-pos))
      (should (< author-pos doc-info-pos))
      (should (< ctx1-pos doc-info-pos))
      (should (< ctx2-pos doc-info-pos)))))

(ert-deftest tibetan-migrate-bare-drops-emptied-segments ()
  "A segment whose body contains only `#+KEYWORD:' lines becomes empty
after hoisting and is dropped entirely — not emitted as `*** Segment M'."
  (let* ((input
          (concat "* Text\n\n"
                  "〔seg:1〕#+TITLE: X\n#+AUTHOR: Y\n〔/seg〕\n"
                  "〔seg:2〕real content〔/seg〕\n"))
         (out (tibetan-migrate--convert-bare-string input)))
    ;; Exactly one Segment heading in the output, and it's Segment 1.
    (let ((count 0))
      (with-temp-buffer
        (insert out)
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\*\\* Segment " nil t)
          (setq count (1+ count))))
      (should (= 1 count)))
    (should (string-match-p "^\\*\\*\\* Segment 1$" out))
    (should (string-match-p "real content" out))))

(ert-deftest tibetan-migrate-bare-keeps-non-metadata-body-around-hoist ()
  "If a segment has BOTH `#+KEYWORD:' lines and real body, hoist the
keywords and keep the rest as the segment body."
  (let* ((input
          (concat "* Text\n\n"
                  "〔seg:1〕#+STARTUP: showall\n"
                  "Some narrative body text.\n"
                  "#+OPTIONS: toc:nil\n"
                  "More narrative.〔/seg〕\n"))
         (out (tibetan-migrate--convert-bare-string input)))
    (should (string-match-p "^#\\+STARTUP: showall$" out))
    (should (string-match-p "^#\\+OPTIONS: toc:nil$" out))
    (should (string-match-p "^\\*\\*\\* Segment 1$" out))
    (should (string-match-p "Some narrative body text\\." out))
    (should (string-match-p "More narrative\\." out))
    ;; Hoisted `#+' lines are removed from the segment body —
    ;; they appear ONLY above `* Text', not after `Segment 1'.
    (let ((segment-pos (string-match "^\\*\\*\\* Segment 1$" out))
          (startup-pos (string-match "^#\\+STARTUP: showall$" out))
          (options-pos (string-match "^#\\+OPTIONS: toc:nil$" out)))
      (should (< startup-pos segment-pos))
      (should (< options-pos segment-pos)))))

(ert-deftest tibetan-migrate-bare-idempotent ()
  "Running the bare-seg migrator on an already-migrated buffer is a no-op."
  (let* ((once
          (tibetan-migrate--convert-bare-string
           "〔seg:1〕first\n* Section-Title〔/seg〕\n〔seg:2〕second〔/seg〕\n"))
         (twice (tibetan-migrate--convert-bare-string once)))
    (should (string= once twice))
    (should-not (string-match-p "〔" twice))))

(ert-deftest tibetan-migrate-bare-multiline-segment-body ()
  "Segment bodies can span paragraph breaks."
  (let* ((input
          (concat "〔seg:1〕line one ends with a shad།\n"
                  "\n"
                  "line two continues here།\n"
                  "line three final line༎〔/seg〕\n"))
         (out (tibetan-migrate--convert-bare-string input)))
    (should (string-match-p "^\\*\\*\\* Segment 1$" out))
    (should (string-match-p "line one ends with a shad" out))
    (should (string-match-p "line two continues here" out))
    (should (string-match-p "line three final line" out))))

(ert-deftest tibetan-migrate-bare-interactive-command ()
  "`tibetan-migrate-bare-segments-to-headings' operates on the current
buffer and leaves no inline seg markers."
  (skip-unless (fboundp 'tibetan-migrate-bare-segments-to-headings))
  (with-temp-buffer
    (insert "* Text\n\n"
            "〔seg:1〕#+TITLE: T\n"
            "* མཚན།〔/seg〕\n"
            "〔seg:2〕body〔/seg〕\n")
    (tibetan-migrate-bare-segments-to-headings)
    (let ((s (buffer-string)))
      (should (string-match-p "^#\\+TITLE: T" s))
      (should (string-match-p "^\\* Text$" s))
      (should (string-match-p "^\\*\\* མཚན།$" s))
      (should (string-match-p "^\\*\\*\\* Segment 1$" s))
      (should (string-match-p "body" s))
      (should-not (string-match-p "〔" s)))))

(provide 'tibetan-segment-migrate-test)
;;; tibetan-segment-migrate-test.el ends here
