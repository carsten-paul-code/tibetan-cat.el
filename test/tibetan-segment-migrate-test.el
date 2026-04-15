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

(provide 'tibetan-segment-migrate-test)
;;; tibetan-segment-migrate-test.el ends here
