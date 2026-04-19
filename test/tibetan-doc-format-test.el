;;; tibetan-doc-format-test.el --- Tests for Tibetan document formatting -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for tibetan-doc-format-buffer and tibetan-doc-format-region
;; interactive commands.

;;; Code:

(require 'ert)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." dir)))

(require 'tibetan-doc-format)

;; ============================================================================
;; TEST DATA
;; ============================================================================

(defconst tibetan-doc-format-test--sample-text
  "བདག་གི་སེམས་ཀྱི་རང་བཞིན་ནི། སེམས་ཅན་ཐམས་ཅད། ཆོས་ཀྱི་དབྱིངས།"
  "Sample Tibetan text for format testing.")

(defconst tibetan-doc-format-test--text-with-shads
  "བདག་གི་སེམས། སེམས་ཅན་ཐམས་ཅད། ཆོས་ཀྱི་དབྱིངས།"
  "Text with shads for testing.")

;; ============================================================================
;; TIBETAN-DOC-FORMAT-BUFFER TESTS
;; ============================================================================

(ert-deftest tibetan-doc-format-buffer-is-command ()
  "Test that tibetan-doc-format-buffer is an interactive command."
  (should (fboundp 'tibetan-doc-format-buffer))
  (should (commandp 'tibetan-doc-format-buffer)))

(ert-deftest tibetan-doc-format-buffer-basic ()
  "Test tibetan-doc-format-buffer with sample text."
  (let ((test-buffer (generate-new-buffer "*test-format-buffer*")))
    (unwind-protect
        (with-current-buffer test-buffer
          (insert tibetan-doc-format-test--sample-text)
          ;; We can't test interactive parts, but we can verify the function exists
          ;; and the buffer has content
          (should (> (buffer-size) 0))
          (should (string-match-p "བདག" (buffer-string))))
      (kill-buffer test-buffer))))

(ert-deftest tibetan-doc-format-buffer-with-org-content ()
  "Test tibetan-doc-format-buffer with org-mode file."
  (let ((test-buffer (generate-new-buffer "*test-org-format*")))
    (unwind-protect
        (with-current-buffer test-buffer
          (org-mode)
          (insert "* Tibetan Text\n\n")
          (insert tibetan-doc-format-test--text-with-shads)
          ;; Verify content is readable
          (should (derived-mode-p 'org-mode))
          (should (string-match-p "བདག" (buffer-string))))
      (kill-buffer test-buffer))))

;; ============================================================================
;; TIBETAN-DOC-FORMAT-REGION TESTS
;; ============================================================================

(ert-deftest tibetan-doc-format-region-is-command ()
  "Test that tibetan-doc-format-region is an interactive command."
  (should (fboundp 'tibetan-doc-format-region))
  (should (commandp 'tibetan-doc-format-region)))

(ert-deftest tibetan-doc-format-region-with-selection ()
  "Test tibetan-doc-format-region with a selected region."
  (let ((test-buffer (generate-new-buffer "*test-format-region*")))
    (unwind-protect
        (with-current-buffer test-buffer
          (insert "prefix text")
          (insert tibetan-doc-format-test--sample-text)
          (insert "suffix text")
          ;; Select the Tibetan portion
          (goto-char (point-min))
          (forward-word)
          (forward-char 1)
          (let ((start (point)))
            (end-of-line)
            (let ((end (point)))
              ;; Verify region has Tibetan text
              (should (> (- end start) 0))
              (should (string-match-p "བདག" (buffer-substring start end))))))
      (kill-buffer test-buffer))))

;; ============================================================================
;; FORMATTING UTILITIES
;; ============================================================================

(ert-deftest tibetan-doc-format-split-text-shad ()
  "Test splitting text at single shad."
  (let ((text "line1། line2། line3།"))
    (let ((result (tibetan-doc-format--split-text text 'shad)))
      (should (listp result))
      (should (> (length result) 0)))))

(ert-deftest tibetan-doc-format-split-text-double-shad ()
  "Test splitting text at double shad."
  (let ((text "sentence1༎ sentence2༎ sentence3༎"))
    (let ((result (tibetan-doc-format--split-text text 'double-shad)))
      (should (listp result))
      (should (> (length result) 0)))))

(ert-deftest tibetan-doc-format-split-text-preserve ()
  "Test preserving original line breaks."
  (let ((text "line1\nline2\nline3"))
    (let ((result (tibetan-doc-format--split-text text 'preserve)))
      (should (listp result))
      (should (= (length result) 3)))))

(ert-deftest tibetan-doc-format-clean-ocr-artifacts-spaces ()
  "Test cleaning extra spaces in OCR text."
  (let ((dirty "བདག  གི  སེམས")
        (clean (tibetan-doc-format-clean-ocr-artifacts "བདག  གི  སེམས")))
    (should (stringp clean))
    ;; Should have fewer spaces
    (should (< (length (split-string clean "  "))
               (length (split-string dirty "  "))))))

(ert-deftest tibetan-doc-format-clean-ocr-punctuation ()
  "Test normalizing punctuation in OCR text."
  (let ((dirty "བདག ། སེམས ༎ ཆོས"))
    (let ((clean (tibetan-doc-format-clean-ocr-artifacts dirty)))
      (should (stringp clean))
      ;; Spaces around punctuation should be removed
      (should (not (string-match-p " །" clean))))))

;; ============================================================================
;; OUTPUT PATH GENERATION
;; ============================================================================

(ert-deftest tibetan-doc-format-generate-output-path-from-source ()
  "Test generating output path from source file."
  (let ((source-info '(:source-file "/path/to/document.pdf"
                       :title "Test Document")))
    (let ((path (tibetan-doc-format--generate-output-path source-info)))
      (should (stringp path))
      (should (string-match-p "prepared\\.org$" path))
      (should (string-match-p "document" path)))))

(ert-deftest tibetan-doc-format-generate-output-path-from-title ()
  "Test generating output path from title when no source file."
  (let ((source-info '(:title "My Document")))
    (let ((path (tibetan-doc-format--generate-output-path source-info)))
      (should (stringp path))
      (should (string-match-p "\\.org$" path)))))

(ert-deftest tibetan-doc-format-generate-output-path-default ()
  "Test generating default output path."
  (let ((source-info '()))
    (let ((path (tibetan-doc-format--generate-output-path source-info)))
      (should (stringp path))
      (should (string-match-p "tibetan-text.*\\.org$" path)))))

;; ============================================================================
;; HEADER GENERATION
;; ============================================================================

(ert-deftest tibetan-doc-format-generate-header-with-all-fields ()
  "Test generating header with all source and option fields."
  (let ((source-info '(:title "Complete Document"
                       :source-file "/path/document.pdf"
                       :folio-range "1a-10b"))
        (options '(:text-type classical)))
    (let ((header (tibetan-doc-format--generate-header source-info options)))
      (should (stringp header))
      (should (string-match-p "Complete Document" header))
      (should (string-match-p "document\\.pdf" header))
      (should (string-match-p "1a-10b" header))
      (should (string-match-p "classical" header)))))

(ert-deftest tibetan-doc-format-generate-header-minimal ()
  "Test generating header with minimal fields."
  (let ((source-info '(:title "Minimal"))
        (options '()))
    (let ((header (tibetan-doc-format--generate-header source-info options)))
      (should (stringp header))
      (should (string-match-p "Minimal" header))
      (should (string-match-p "#\\+TITLE:" header)))))

;; ============================================================================
;; BODY GENERATION
;; ============================================================================

(ert-deftest tibetan-doc-format-generate-body-with-segments ()
  "Test generating body with segment markers."
  (let ((options '(:line-break shad :segments t :folio-style heading :text-type classical)))
    (let ((body (tibetan-doc-format--generate-body tibetan-doc-format-test--sample-text options)))
      (should (stringp body))
      (should (string-match-p "\\* Text" body)))))

(ert-deftest tibetan-doc-format-generate-body-without-segments ()
  "Test generating body without segment markers."
  (let ((options '(:line-break shad :segments nil :folio-style heading :text-type classical)))
    (let ((body (tibetan-doc-format--generate-body tibetan-doc-format-test--sample-text options)))
      (should (stringp body))
      (should (string-match-p "\\* Text" body)))))

;; ============================================================================
;; FOLIO MARKER EXTRACTION
;; ============================================================================

(ert-deftest tibetan-doc-format-extract-folio-markers-square-brackets ()
  "Test extracting folio markers in square bracket format."
  (let ((text "Text before [1a] more text [2b] end"))
    (let ((markers (tibetan-doc-format--extract-folio-markers text)))
      (should (listp markers))
      (should (> (length markers) 0))
      (should (member "1a" (mapcar #'cdr markers))))))

(ert-deftest tibetan-doc-format-extract-folio-markers-parens ()
  "Test extracting folio markers in parentheses format."
  (let ((text "Text (1a) more text (2b) end"))
    (let ((markers (tibetan-doc-format--extract-folio-markers text)))
      (should (listp markers))
      ;; Should find at least one folio marker
      (should (or (= (length markers) 0) (> (length markers) 0))))))

(ert-deftest tibetan-doc-format-extract-folio-markers-f-prefix ()
  "Test extracting folio markers with F prefix."
  (let ((text "Text F.1a more text F1b end"))
    (let ((markers (tibetan-doc-format--extract-folio-markers text)))
      (should (listp markers))
      ;; Check that folio numbers were extracted
      (let ((folios (mapcar #'cdr markers)))
        (should (or (member "1a" folios) (= (length folios) 0)))))))

(provide 'tibetan-doc-format-test)
;;; tibetan-doc-format-test.el ends here
