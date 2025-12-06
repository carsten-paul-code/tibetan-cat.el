;;; tibetan-utils-test.el --- Tests for tibetan-utils.el -*- lexical-binding: t -*-

(require 'ert)
(require 'tibetan-utils)

;; ============================================================================
;; SEGMENT DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-utils-get-segment-new-format ()
  "Test detection of new format 〔seg〕...〔/seg〕."
  (with-temp-buffer
    (insert "〔seg〕བཀྲ་ཤིས་བདེ་ལེགས།〔/seg〕")
    (goto-char 15)  ; Inside the segment
    (let ((result (tibetan-get-current-segment)))
      (should result)
      (should (string-match-p "Line" (car result)))
      (should (string= "བཀྲ་ཤིས་བདེ་ལེགས།" (cdr result))))))

(ert-deftest tibetan-utils-get-segment-old-format ()
  "Test detection of old format 〔seg:ID〕...〔/seg〕."
  (with-temp-buffer
    (insert "〔seg:42〕བཀྲ་ཤིས་བདེ་ལེགས།〔/seg〕")
    (goto-char 18)  ; Inside the segment
    (let ((result (tibetan-get-current-segment)))
      (should result)
      (should (string= "42" (car result)))
      (should (string= "བཀྲ་ཤིས་བདེ་ལེགས།" (cdr result))))))

(ert-deftest tibetan-utils-get-segment-outside ()
  "Test that nil is returned when outside a segment."
  (with-temp-buffer
    (insert "Before 〔seg〕text〔/seg〕 After")
    (goto-char 3)  ; Before the segment
    (should-not (tibetan-get-current-segment))))

(ert-deftest tibetan-utils-get-all-segments-mixed ()
  "Test getting all segments with mixed formats."
  (with-temp-buffer
    (insert "〔seg〕First〔/seg〕\n")
    (insert "〔seg:2〕Second〔/seg〕\n")
    (insert "〔seg〕Third〔/seg〕\n")
    (let ((segments (tibetan-get-all-segments)))
      (should (= 3 (length segments)))
      (should (string= "First" (cdr (nth 0 segments))))
      (should (string= "2" (car (nth 1 segments))))
      (should (string= "Second" (cdr (nth 1 segments))))
      (should (string= "Third" (cdr (nth 2 segments)))))))

(ert-deftest tibetan-utils-get-segment-any-format-new ()
  "Test tibetan-get-current-segment-any-format with new markers."
  (with-temp-buffer
    (insert "〔seg〕བོད་སྐད།〔/seg〕")
    (goto-char 10)
    (let ((result (tibetan-get-current-segment-any-format)))
      (should result)
      (should (string= "བོད་སྐད།" (cdr result))))))

(provide 'tibetan-utils-test)
;;; tibetan-utils-test.el ends here
