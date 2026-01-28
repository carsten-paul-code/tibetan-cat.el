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

;; ============================================================================
;; LINE AS SEGMENT TESTS
;; ============================================================================

(ert-deftest tibetan-utils-get-current-line-as-segment-basic ()
  "Test getting current line as segment with Tibetan text."
  (with-temp-buffer
    (insert "བདག་གི་སེམས།")
    (goto-char 5)
    (let ((result (tibetan-get-current-line-as-segment)))
      (should result)
      (should (string-match-p "Line" (car result)))
      (should (string= "བདག་གི་སེམས།" (cdr result))))))

(ert-deftest tibetan-utils-get-current-line-as-segment-no-tibetan ()
  "Test that non-Tibetan lines return nil."
  (with-temp-buffer
    (insert "This is English text")
    (goto-char 5)
    (should (null (tibetan-get-current-line-as-segment)))))

(ert-deftest tibetan-utils-get-current-line-as-segment-org-heading ()
  "Test that org headings are excluded."
  (with-temp-buffer
    (insert "* བདག་གི་སེམས།")
    (goto-char 5)
    (should (null (tibetan-get-current-line-as-segment)))))

(ert-deftest tibetan-utils-get-current-line-as-segment-property ()
  "Test that property lines are excluded."
  (with-temp-buffer
    (insert ":PROPERTIES:\n:TIBETAN: བདག")
    (goto-char 20)
    (should (null (tibetan-get-current-line-as-segment)))))

(ert-deftest tibetan-utils-get-current-line-as-segment-keyword ()
  "Test that org keywords are excluded."
  (with-temp-buffer
    (insert "#+TITLE: བདག")
    (goto-char 5)
    (should (null (tibetan-get-current-line-as-segment)))))

(ert-deftest tibetan-utils-get-current-line-as-segment-empty ()
  "Test that empty lines return nil."
  (with-temp-buffer
    (insert "   \n")
    (goto-char 2)
    (should (null (tibetan-get-current-line-as-segment)))))

;; ============================================================================
;; STRING MANIPULATION TESTS
;; ============================================================================

(ert-deftest tibetan-normalize-text-basic ()
  "Test basic text normalization."
  (should (string= (tibetan-normalize-text "བདག གི") "བདག་གི")))

(ert-deftest tibetan-normalize-text-duplicate-tsheg ()
  "Test removal of duplicate tsheg."
  (should (string= (tibetan-normalize-text "བདག་་གི") "བདག་གི")))

(ert-deftest tibetan-normalize-text-whitespace ()
  "Test whitespace handling - spaces converted to tsheg."
  ;; Note: spaces are converted to tsheg, then duplicates removed
  (let ((result (tibetan-normalize-text "  བདག  ")))
    (should (stringp result))
    (should (string-match-p "བདག" result))))

(ert-deftest tibetan-normalize-text-nil ()
  "Test with nil input."
  (should (null (tibetan-normalize-text nil))))

(ert-deftest tibetan-normalize-text-empty ()
  "Test with empty string."
  (should (string= (tibetan-normalize-text "") "")))

(ert-deftest tibetan-split-into-syllables-basic ()
  "Test basic syllable splitting."
  (let ((result (tibetan-split-into-syllables "བདག་གི་སེམས")))
    (should (listp result))
    (should (= 3 (length result)))
    (should (string= "བདག" (nth 0 result)))
    (should (string= "གི" (nth 1 result)))
    (should (string= "སེམས" (nth 2 result)))))

(ert-deftest tibetan-split-into-syllables-spaces ()
  "Test splitting with spaces (converted to tsheg)."
  (let ((result (tibetan-split-into-syllables "བདག གི")))
    (should (= 2 (length result)))))

(ert-deftest tibetan-split-into-syllables-nil ()
  "Test with nil input."
  (should (null (tibetan-split-into-syllables nil))))

(ert-deftest tibetan-split-into-syllables-empty ()
  "Test with empty string."
  (let ((result (tibetan-split-into-syllables "")))
    (should (listp result))
    (should (= 0 (length result)))))

(ert-deftest tibetan-split-into-syllables-single ()
  "Test single syllable."
  (let ((result (tibetan-split-into-syllables "བདག")))
    (should (= 1 (length result)))
    (should (string= "བདག" (car result)))))

(ert-deftest tibetan-clean-text-shad ()
  "Test removing shad punctuation."
  (should (string= (tibetan-clean-text "བདག།") "བདག")))

(ert-deftest tibetan-clean-text-double-shad ()
  "Test removing double shad."
  (should (string= (tibetan-clean-text "བདག༎") "བདག")))

(ert-deftest tibetan-clean-text-multiple ()
  "Test removing multiple punctuation marks."
  (should (string= (tibetan-clean-text "བདག།གི༎སེམས༏") "བདགགིསེམས")))

(ert-deftest tibetan-clean-text-nil ()
  "Test with nil input."
  (should (null (tibetan-clean-text nil))))

(ert-deftest tibetan-clean-text-no-punctuation ()
  "Test text without punctuation."
  (should (string= (tibetan-clean-text "བདག་གི") "བདག་གི")))

;; ============================================================================
;; WINDOW MANAGEMENT TESTS
;; ============================================================================

(ert-deftest tibetan-display-in-side-window-creates-buffer ()
  "Test that side window function creates buffer."
  (let ((buf-name "*test-tibetan-side*"))
    (unwind-protect
        (progn
          (tibetan-display-in-side-window buf-name)
          (should (get-buffer buf-name)))
      (when (get-buffer buf-name)
        (kill-buffer buf-name)))))

(ert-deftest tibetan-display-in-side-window-returns-window ()
  "Test that side window function returns a window."
  (let ((buf-name "*test-tibetan-side2*"))
    (unwind-protect
        (let ((win (tibetan-display-in-side-window buf-name)))
          (should (windowp win)))
      (when (get-buffer buf-name)
        (tibetan-close-side-window buf-name)
        (kill-buffer buf-name)))))

(ert-deftest tibetan-close-side-window-nonexistent ()
  "Test closing nonexistent window doesn't error."
  (should-not (tibetan-close-side-window "*nonexistent-buffer*")))

;; ============================================================================
;; BUFFER CONTENT HELPER TESTS
;; ============================================================================

(ert-deftest tibetan-insert-section-default-level ()
  "Test inserting section with default level."
  (with-temp-buffer
    (tibetan-insert-section "Test Title")
    (should (string-match-p "^\\*\\* Test Title" (buffer-string)))))

(ert-deftest tibetan-insert-section-custom-level ()
  "Test inserting section with custom level."
  (with-temp-buffer
    (tibetan-insert-section "Test Title" 3)
    (should (string-match-p "^\\*\\*\\* Test Title" (buffer-string)))))

(ert-deftest tibetan-insert-section-level-1 ()
  "Test inserting section at level 1."
  (with-temp-buffer
    (tibetan-insert-section "Test Title" 1)
    (should (string-match-p "^\\* Test Title" (buffer-string)))))

(ert-deftest tibetan-insert-separator-basic ()
  "Test inserting separator line."
  (with-temp-buffer
    (tibetan-insert-separator)
    (should (string-match-p "─" (buffer-string)))
    (should (> (length (buffer-string)) 10))))

(ert-deftest tibetan-insert-separator-ends-with-newline ()
  "Test that separator ends with newline."
  (with-temp-buffer
    (tibetan-insert-separator)
    (should (string-suffix-p "\n" (buffer-string)))))

;; ============================================================================
;; EDGE CASE TESTS
;; ============================================================================

(ert-deftest tibetan-utils-segment-with-nested-markers ()
  "Test handling of text with other brackets inside segment."
  (with-temp-buffer
    (insert "〔seg〕བདག (note) གི〔/seg〕")
    (goto-char 15)
    (let ((result (tibetan-get-current-segment)))
      (should result)
      (should (string-match-p "བདག" (cdr result))))))

(ert-deftest tibetan-utils-multiple-segments-get-correct-one ()
  "Test that correct segment is returned when multiple exist."
  (with-temp-buffer
    (insert "〔seg〕First〔/seg〕 〔seg〕Second〔/seg〕 〔seg〕Third〔/seg〕")
    ;; Position in "Second" - search for it to find correct position
    (goto-char (point-min))
    (search-forward "Second")
    (backward-char 3)  ; Position inside "Second"
    (let ((result (tibetan-get-current-segment)))
      (should result)
      (should (string= "Second" (cdr result))))))

(ert-deftest tibetan-utils-segment-any-format-plain-text ()
  "Test tibetan-get-current-segment-any-format falls back to line."
  (with-temp-buffer
    (insert "བདག་གི་སེམས་ནི།")
    (goto-char 5)
    (let ((result (tibetan-get-current-segment-any-format)))
      (should result)
      (should (string-match-p "Line" (car result))))))

(provide 'tibetan-utils-test)
;;; tibetan-utils-test.el ends here
