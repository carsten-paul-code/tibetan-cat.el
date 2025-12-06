;;; tibetan-compound-analysis-test.el --- Tests for compound detection -*- lexical-binding: t -*-

(require 'ert)

;; Load just the detection functions we need to test
(defvar tibetan-compound--detect-block-markers-fn nil)

;; ============================================================================
;; BLOCK MARKER DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-detect-sent-block ()
  "Test detection of 〔sent〕...〔/sent〕 blocks."
  (with-temp-buffer
    (insert "〔sent〕\n")
    (insert "〔seg〕First segment།〔/seg〕\n")
    (insert "〔seg〕Second segment།〔/seg〕\n")
    (insert "〔/sent〕\n")
    (goto-char 20)  ; Inside the sent block
    (let ((result (tibetan-compound--detect-block-markers "sent")))
      (should result)
      (should (= 1 (car result)))  ; Start line
      (should (= 4 (cdr result))))))  ; End line

(ert-deftest tibetan-compound-detect-verse-block ()
  "Test detection of 〔verse :num N〕...〔/verse〕 blocks."
  (with-temp-buffer
    (insert "〔verse :num 1〕\n")
    (insert "རིགས་ཅན་གསུམ་གྱི་གདུལ་བྱ།༎\n")
    (insert "〔/verse〕\n")
    (goto-char 25)  ; Inside the verse block
    (let ((result (tibetan-compound--detect-block-markers "verse")))
      (should result)
      (should (= 1 (car result)))
      (should (= 3 (cdr result))))))

(ert-deftest tibetan-compound-detect-prose-block ()
  "Test detection of 〔prose :comment-on N〕...〔/prose〕 blocks."
  (with-temp-buffer
    (insert "〔prose :comment-on 1〕\n")
    (insert "〔seg〕ཞེས་པ་སྟེ། commentary text〔/seg〕\n")
    (insert "〔/prose〕\n")
    (goto-char 30)  ; Inside the prose block
    (let ((result (tibetan-compound--detect-block-markers "prose")))
      (should result)
      (should (= 1 (car result)))
      (should (= 3 (cdr result))))))

(ert-deftest tibetan-compound-detect-outside-block ()
  "Test that nil is returned when outside any block."
  (with-temp-buffer
    (insert "Some text before\n")
    (insert "〔sent〕\n")
    (insert "〔seg〕Inside〔/seg〕\n")
    (insert "〔/sent〕\n")
    (insert "Some text after\n")
    (goto-char 5)  ; Before the block
    (should-not (tibetan-compound--detect-block-markers "sent"))))

(provide 'tibetan-compound-analysis-test)
;;; tibetan-compound-analysis-test.el ends here
