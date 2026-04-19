;;; tibetan-ocr-correct-test.el --- Tests for Claude AI OCR correction -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for AI-based OCR correction using Claude.
;; Tests cover both the function availability and graceful
;; handling when gptel is not configured.

;;; Code:

(require 'ert)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." dir)))

(require 'tibetan-ocr-correct)

;; ============================================================================
;; TEST DATA
;; ============================================================================

(defconst tibetan-ocr-correct-test--sample-text
  "བདག་གི་སེམས་ཀྱི་རང་བཞིན་ནི་སེམས་ཅན་ཐམས་ཅད་ཆོས་ཀྱི་དབྱིངས།"
  "Sample Tibetan text for correction testing.")

(defconst tibetan-ocr-correct-test--validation-result
  '(:total 12
    :valid ("བདག" "སེམས" "ཆོས")
    :unknown ("སེམཀྱི")
    :suspicious ("རང་བཞིན")
    :details ((:syllable "སེམཀྱི" :suggestions ("སེམ་ཀྱི"))))
  "Sample validation result for testing.")

;; ============================================================================
;; COMMAND AVAILABILITY TESTS
;; ============================================================================

(ert-deftest tibetan-ocr-correct-is-command ()
  "Test that tibetan-ocr-correct is callable."
  (should (fboundp 'tibetan-ocr-correct)))

(ert-deftest tibetan-ocr-correct-buffer-is-command ()
  "Test that tibetan-ocr-correct-buffer is an interactive command."
  (should (fboundp 'tibetan-ocr-correct-buffer))
  (should (commandp 'tibetan-ocr-correct-buffer)))

(ert-deftest tibetan-ocr-correct-region-is-command ()
  "Test that tibetan-ocr-correct-region is an interactive command."
  (should (fboundp 'tibetan-ocr-correct-region))
  (should (commandp 'tibetan-ocr-correct-region)))

;; ============================================================================
;; PROMPT CONSTRUCTION
;; ============================================================================

(ert-deftest tibetan-ocr-correct-format-flagged-with-unknown ()
  "Test formatting flagged items with unknown syllables."
  (let ((validation '(:unknown ("སེམཀྱི" "བདག་")
                      :suspicious ()
                      :details ())))
    (let ((result (tibetan-ocr-correct--format-flagged validation)))
      (should (stringp result))
      (should (string-match-p "Unknown" result)))))

(ert-deftest tibetan-ocr-correct-format-flagged-with-suspicious ()
  "Test formatting flagged items with suspicious syllables."
  (let ((validation '(:unknown ()
                      :suspicious ("རང་བཞིན" "ཆོས་ཀྱི")
                      :details ())))
    (let ((result (tibetan-ocr-correct--format-flagged validation)))
      (should (stringp result))
      (should (string-match-p "Suspicious" result)))))

(ert-deftest tibetan-ocr-correct-format-flagged-empty ()
  "Test formatting when no flagged items."
  (let ((validation '(:unknown () :suspicious () :details ())))
    (let ((result (tibetan-ocr-correct--format-flagged validation)))
      (should (stringp result)))))

(ert-deftest tibetan-ocr-correct-build-prompt-returns-string ()
  "Test that prompt building returns a string."
  (let ((text tibetan-ocr-correct-test--sample-text)
        (validation tibetan-ocr-correct-test--validation-result))
    (let ((prompt (tibetan-ocr-correct--build-prompt text validation)))
      (should (stringp prompt))
      (should (string-match-p "Original Text" prompt))
      (should (string-match-p "Validation Summary" prompt))
      (should (string-match-p "Flagged Syllables" prompt)))))

(ert-deftest tibetan-ocr-correct-build-prompt-includes-text ()
  "Test that prompt includes the original text."
  (let ((text "test text")
        (validation '(:total 2 :valid () :unknown ("test") :suspicious () :details ())))
    (let ((prompt (tibetan-ocr-correct--build-prompt text validation)))
      (should (string-match-p "test text" prompt)))))

;; ============================================================================
;; RESPONSE PARSING
;; ============================================================================

(ert-deftest tibetan-ocr-correct-parse-response-with-corrected-text ()
  "Test parsing Claude response with corrected text."
  (let ((response "CORRECTED_TEXT_START
བདག་གི་སེམས་ཀྱི་རང་བཞིན།
CORRECTED_TEXT_END

CHANGES_START
སེམཀྱི → སེམ་ཀྱི: missing tsheg
CHANGES_END"))
    (let ((result (tibetan-ocr-correct--parse-response response)))
      (should (plistp result))
      (should (plist-member result :text))
      (should (plist-member result :changes))
      (should (string-match-p "བདག" (plist-get result :text)))
      (should (listp (plist-get result :changes))))))

(ert-deftest tibetan-ocr-correct-parse-response-with-single-change ()
  "Test parsing response with a single change."
  (let ((response "CORRECTED_TEXT_START
རང་བཞིན།
CORRECTED_TEXT_END

CHANGES_START
སེམཀྱི → སེམ་ཀྱི: missing tsheg
CHANGES_END"))
    (let ((result (tibetan-ocr-correct--parse-response response)))
      (let ((changes (plist-get result :changes)))
        (should (= (length changes) 1))
        (should (string= "སེམཀྱི" (plist-get (car changes) :original)))
        (should (string= "སེམ་ཀྱི" (plist-get (car changes) :corrected)))
        (should (string-match-p "tsheg" (plist-get (car changes) :reason)))))))

(ert-deftest tibetan-ocr-correct-parse-response-with-multiple-changes ()
  "Test parsing response with multiple changes."
  (let ((response "CORRECTED_TEXT_START
བདག་གི་སེམས། སེམ་ཅན་ཐམས་ཅད།
CORRECTED_TEXT_END

CHANGES_START
སེམཀྱི → སེམ་ཀྱི: missing tsheg
རང་བཞིན → རང་བཞིན: verified
CHANGES_END"))
    (let ((result (tibetan-ocr-correct--parse-response response)))
      (let ((changes (plist-get result :changes)))
        (should (= (length changes) 2))))))

(ert-deftest tibetan-ocr-correct-parse-response-no-markers ()
  "Test parsing response without required markers."
  (let ((response "བདག་གི་སེམས། This is plain text without markers."))
    (let ((result (tibetan-ocr-correct--parse-response response)))
      (should (plistp result))
      ;; Should fall back to returning original response as text
      (should (string-match-p "plain text" (plist-get result :text))))))

;; ============================================================================
;; GPTEL INTEGRATION
;; ============================================================================

(ert-deftest tibetan-ocr-correct-gptel-available-p-returns-boolean ()
  "Test that gptel availability check returns boolean."
  (let ((result (tibetan-ocr-correct--gptel-available-p)))
    (should (booleanp result))))

;; ============================================================================
;; CONFIGURATION TESTS
;; ============================================================================

(ert-deftest tibetan-ocr-correct-model-customization ()
  "Test that OCR correction model is customizable."
  (should (boundp 'tibetan-ocr-correct-model))
  (should (stringp tibetan-ocr-correct-model)))

(ert-deftest tibetan-ocr-correct-show-diff-customization ()
  "Test that show-diff is customizable."
  (should (boundp 'tibetan-ocr-correct-show-diff)))

(ert-deftest tibetan-ocr-correct-auto-accept-customization ()
  "Test that auto-accept is customizable."
  (should (boundp 'tibetan-ocr-correct-auto-accept)))

;; ============================================================================
;; SYSTEM PROMPT
;; ============================================================================

(ert-deftest tibetan-ocr-correct-system-prompt-exists ()
  "Test that system prompt is defined."
  (should (boundp 'tibetan-ocr-correct--system-prompt))
  (should (stringp tibetan-ocr-correct--system-prompt))
  (should (> (length tibetan-ocr-correct--system-prompt) 0))
  (should (string-match-p "Tibetan" tibetan-ocr-correct--system-prompt))
  (should (string-match-p "OCR" tibetan-ocr-correct--system-prompt)))

;; ============================================================================
;; DIFF DISPLAY
;; ============================================================================

(ert-deftest tibetan-ocr-correct-show-diff-function-exists ()
  "Test that diff display function exists."
  (should (fboundp 'tibetan-ocr-correct--show-diff)))

(provide 'tibetan-ocr-correct-test)
;;; tibetan-ocr-correct-test.el ends here
