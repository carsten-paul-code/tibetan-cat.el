;;; tibetan-org-structure-test.el --- Tests for tibetan-org-structure.el -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for Tibetan org-mode structure functions including:
;; - Segment detection (tibetan-org-at-segment-p)
;; - Segment text extraction (tibetan-org-get-segment-text)
;; - Document preparation (tibetan-prepare-document)
;; - Text segmentation (tibetan--segment-text)

;;; Code:

(require 'ert)
(require 'org)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir)))

(require 'tibetan-org-structure)

;; ============================================================================
;; TEST DATA
;; ============================================================================

(defconst tibetan-org-test--sample-org-buffer
  "#+TITLE: Test Document
#+STARTUP: fold

* Main Title

** Sentence 1

*** Segment 1
བཀྲ་ཤིས་བདེ་ལེགས།

*** Segment 2
སངས་རྒྱས་ཆོས་དང་ཚོགས་ཀྱི་མཆོག་རྣམས་ལ།

** Sentence 2

*** Segment 3
བྱང་ཆུབ་བར་དུ་བདག་ནི་སྐྱབས་སུ་མཆི།
"
  "Sample org buffer for testing segment detection.")

(defconst tibetan-org-test--sentence-org-buffer
  "#+TITLE: Sentence Format Test

* Title

** Sentence 1

*** Segment 1
First segment text།

*** Segment 2
Second segment text།

** Sentence 2

*** Segment 3
Third segment text།
"
  "Sample org buffer with Sentence format for testing.")

;; ============================================================================
;; SEGMENT DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-org-at-segment-p-on-heading ()
  "Test segment detection when cursor is on heading."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "*** Segment 1")
    (beginning-of-line)
    (should (tibetan-org-at-segment-p))))

(ert-deftest tibetan-org-at-segment-p-in-content ()
  "Test segment detection when cursor is in content below heading."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "བཀྲ་ཤིས")
    (should (tibetan-org-at-segment-p))))

(ert-deftest tibetan-org-at-segment-p-not-in-segment ()
  "Test that non-segment headings return nil."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 1")
    (beginning-of-line)
    (should-not (tibetan-org-at-segment-p))))

(ert-deftest tibetan-org-at-segment-p-level-2-heading ()
  "Test that level 2 headings are not detected as segments."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 2")
    (beginning-of-line)
    (should-not (tibetan-org-at-segment-p))))

;; ============================================================================
;; SEGMENT TEXT EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-org-get-segment-text-basic ()
  "Test basic segment text extraction."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "*** Segment 1")
    (let ((text (tibetan-org-get-segment-text)))
      (should text)
      (should (string-match-p "བཀྲ་ཤིས་བདེ་ལེགས" text)))))

(ert-deftest tibetan-org-get-segment-text-from-content ()
  "Test segment text extraction when cursor is in content."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "སངས་རྒྱས")
    (let ((text (tibetan-org-get-segment-text)))
      (should text)
      (should (string-match-p "སངས་རྒྱས" text)))))

(ert-deftest tibetan-org-get-segment-text-nil-outside ()
  "Test that nil is returned when not in a segment."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 1")
    (beginning-of-line)
    (should-not (tibetan-org-get-segment-text))))

;; ============================================================================
;; SEGMENT ID TESTS
;; ============================================================================

(ert-deftest tibetan-org-get-segment-id-basic ()
  "Test segment ID extraction."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "*** Segment 2")
    (should (= 2 (tibetan-org-get-segment-id)))))

(ert-deftest tibetan-org-get-segment-id-from-content ()
  "Test segment ID extraction from content."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "བྱང་ཆུབ")
    (should (= 3 (tibetan-org-get-segment-id)))))

;; ============================================================================
;; SENTENCE FUNCTIONS TESTS
;; ============================================================================

(ert-deftest tibetan-org-at-sentence-p-basic ()
  "Test sentence detection."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 1")
    (beginning-of-line)
    (should (tibetan-org-at-sentence-p))))

(ert-deftest tibetan-org-get-sentence-id-basic ()
  "Test sentence ID extraction."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 2")
    (beginning-of-line)
    (should (= 2 (tibetan-org-get-sentence-id)))))

(ert-deftest tibetan-org-get-sentence-id-from-segment ()
  "Test sentence ID extraction when in a segment."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "Third segment")
    (should (= 2 (tibetan-org-get-sentence-id)))))

;; ============================================================================
;; PARENT SECTION NAME TESTS
;; ============================================================================

(ert-deftest tibetan-org-get-parent-section-name-basic ()
  "Test parent section name extraction."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "*** Segment 1")
    (let ((name (tibetan-org-get-parent-section-name)))
      (should name)
      (should (string-match-p "Sentence 1" name)))))

(ert-deftest tibetan-org-get-parent-section-name-from-content ()
  "Test parent section name extraction from segment content."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "བྱང་ཆུབ")
    (let ((name (tibetan-org-get-parent-section-name)))
      (should name)
      (should (string-match-p "Sentence 2" name)))))

;; ============================================================================
;; TEXT SEGMENTATION TESTS
;; ============================================================================

(ert-deftest tibetan--segment-text-by-lines ()
  "Test segmentation by line breaks."
  (let ((text "First line།
Second line།
Third line།"))
    (let ((segments (tibetan--segment-text text)))
      (should (= 3 (length segments)))
      (should (string-match-p "First" (nth 0 segments)))
      (should (string-match-p "Second" (nth 1 segments)))
      (should (string-match-p "Third" (nth 2 segments))))))

(ert-deftest tibetan--segment-text-by-shad ()
  "Test segmentation by shad when no line breaks."
  (let ((text "First།Second།Third།"))
    (let ((segments (tibetan--segment-text text)))
      (should (= 3 (length segments)))
      (should (string-match-p "First" (nth 0 segments)))
      (should (string-match-p "Second" (nth 1 segments)))
      (should (string-match-p "Third" (nth 2 segments))))))

(ert-deftest tibetan--segment-text-by-double-shad ()
  "Test segmentation by double shad."
  (let ((text "First།།Second།།Third"))
    (let ((segments (tibetan--segment-text text)))
      (should (>= (length segments) 2)))))

(ert-deftest tibetan--segment-text-empty ()
  "Test segmentation of empty text."
  (let ((segments (tibetan--segment-text "")))
    (should (= 0 (length segments)))))

(ert-deftest tibetan--segment-text-single-line ()
  "Test that single line without shad is not split."
  (let ((text "Single line without punctuation"))
    (let ((segments (tibetan--segment-text text)))
      ;; Should still create at least one segment
      (should (>= (length segments) 1)))))

(ert-deftest tibetan--segment-text-preserves-tibetan ()
  "Test that Tibetan text is preserved in segments."
  (let ((text "བཀྲ་ཤིས།བདེ་ལེགས།"))
    (let ((segments (tibetan--segment-text text)))
      (should (= 2 (length segments)))
      (should (string-match-p "བཀྲ་ཤིས" (nth 0 segments)))
      (should (string-match-p "བདེ་ལེགས" (nth 1 segments))))))

(ert-deftest tibetan--segment-text-lines-with-tibetan ()
  "Test line-based segmentation with Tibetan text."
  (let ((text "ཡང་སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་པའི་ཚེ།
ཡུལ་དེའི་ཚོང་པ་ལྔ་བརྒྱ།
དགེ་བསྙེན་ཁྲིམས་ལྔ་པ།"))
    (let ((segments (tibetan--segment-text text)))
      (should (= 3 (length segments)))
      (should (string-match-p "སྟོན་པ" (nth 0 segments)))
      (should (string-match-p "ཚོང་པ" (nth 1 segments)))
      (should (string-match-p "དགེ་བསྙེན" (nth 2 segments))))))

;; ============================================================================
;; DOCUMENT PREPARATION TESTS
;; Note: Full tibetan-prepare-document tests are slow due to org-mode loading.
;; These tests focus on the core segmentation logic.
;; Full integration tests are in spec/suites/document-prep-spec.el
;; ============================================================================

;; Skip slow document preparation tests in batch mode
;; Run them interactively with M-x ert RET tibetan-prepare RET
(ert-deftest tibetan-prepare-document-creates-structure ()
  "Test that document preparation creates proper org structure."
  :tags '(:slow :interactive)
  (skip-unless (not noninteractive))
  (with-temp-buffer
    (insert "First།Second།Third།")
    (tibetan-prepare-document "Test Title")
    (goto-char (point-min))
    ;; Check headers
    (should (search-forward "#+TITLE: Test Title" nil t))
    (should (search-forward "#+STARTUP: fold" nil t))
    ;; Check structure
    (goto-char (point-min))
    (should (search-forward "*** Segment 1" nil t))
    (should (search-forward "*** Segment 2" nil t))
    (should (search-forward "*** Segment 3" nil t))))

(ert-deftest tibetan-prepare-document-creates-sentences ()
  "Test that document preparation groups segments into sentences."
  :tags '(:slow :interactive)
  (skip-unless (not noninteractive))
  (with-temp-buffer
    (insert "First།Second།Third།")
    (tibetan-prepare-document "Test")
    (goto-char (point-min))
    (should (search-forward "** Sentence 1" nil t))))

(ert-deftest tibetan-prepare-document-creates-vocabulary-section ()
  "Test that document preparation adds vocabulary section."
  :tags '(:slow :interactive)
  (skip-unless (not noninteractive))
  (with-temp-buffer
    (insert "Test།")
    (tibetan-prepare-document "Test")
    (goto-char (point-min))
    (should (search-forward "* Vocabulary" nil t))
    (should (search-forward "| Tibetan | Wylie | English |" nil t))))

(ert-deftest tibetan-prepare-document-creates-notes-section ()
  "Test that document preparation adds notes section."
  :tags '(:slow :interactive)
  (skip-unless (not noninteractive))
  (with-temp-buffer
    (insert "Test།")
    (tibetan-prepare-document "Test")
    (goto-char (point-min))
    (should (search-forward "* Notes" nil t))))

(ert-deftest tibetan-prepare-document-handles-lines ()
  "Test document preparation with line-based input."
  :tags '(:slow :interactive)
  (skip-unless (not noninteractive))
  (with-temp-buffer
    (insert "Line one
Line two
Line three")
    (tibetan-prepare-document "Lines Test")
    (goto-char (point-min))
    (should (search-forward "*** Segment 1" nil t))
    (should (search-forward "Line one" nil t))
    (should (search-forward "*** Segment 2" nil t))
    (should (search-forward "Line two" nil t))))

;; ============================================================================
;; NAVIGATION TESTS
;; ============================================================================

(ert-deftest tibetan-org-next-segment-basic ()
  "Test moving to next segment."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "*** Segment 1")
    (beginning-of-line)
    (tibetan-org-next-segment)
    (should (looking-at-p "\\*\\*\\* Segment 2"))))

(ert-deftest tibetan-org-next-segment-at-last ()
  "Test next segment at last segment returns nil or stays."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "*** Segment 3")
    (beginning-of-line)
    (let ((pos (point)))
      (tibetan-org-next-segment)
      ;; Either stays at same position or returns nil
      (should (or (= (point) pos)
                  (not (looking-at-p "\\*\\*\\* Segment")))))))

(ert-deftest tibetan-org-previous-segment-basic ()
  "Test moving to previous segment."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "*** Segment 2")
    (beginning-of-line)
    (tibetan-org-previous-segment)
    (should (looking-at-p "\\*\\*\\* Segment 1"))))

(ert-deftest tibetan-org-previous-segment-at-first ()
  "Test previous segment at first segment."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "*** Segment 1")
    (beginning-of-line)
    (let ((pos (point)))
      (tibetan-org-previous-segment)
      ;; Should stay at same position or move to start
      (should (<= (point) pos)))))

(ert-deftest tibetan-org-next-sentence-basic ()
  "Test moving to next sentence."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 1")
    (beginning-of-line)
    (tibetan-org-next-sentence)
    (should (looking-at-p "\\*\\* Sentence 2"))))

(ert-deftest tibetan-org-previous-sentence-basic ()
  "Test moving to previous sentence."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 2")
    (beginning-of-line)
    (tibetan-org-previous-sentence)
    (should (looking-at-p "\\*\\* Sentence 1"))))

;; ============================================================================
;; SENTENCE DATA EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-org-get-sentence-segments-basic ()
  "Test getting all segments in a sentence."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 1")
    (beginning-of-line)  ; Ensure we're at the heading
    (let ((segments (tibetan-org-get-sentence-segments)))
      (should (listp segments))
      (should (= 2 (length segments))))))

(ert-deftest tibetan-org-get-sentence-text-basic ()
  "Test getting combined text of a sentence."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 1")
    (beginning-of-line)  ; Ensure we're at the heading
    (let ((text (tibetan-org-get-sentence-text)))
      (should (stringp text))
      (should (string-match-p "First segment" text))
      (should (string-match-p "Second segment" text)))))

(ert-deftest tibetan-org-get-sentence-data-basic ()
  "Test getting sentence metadata."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 1")
    (let ((data (tibetan-org-get-sentence-data)))
      (should data)
      (should (listp data)))))

;; ============================================================================
;; INFO DISPLAY TESTS
;; ============================================================================

(ert-deftest tibetan-org-show-segment-info-callable ()
  "Test that show-segment-info is callable."
  (should (fboundp 'tibetan-org-show-segment-info)))

(ert-deftest tibetan-org-show-sentence-info-callable ()
  "Test that show-sentence-info is callable."
  (should (fboundp 'tibetan-org-show-sentence-info)))

;; ============================================================================
;; ANALYSIS HELPERS TESTS
;; ============================================================================

(ert-deftest tibetan-org-segment-for-analysis-basic ()
  "Test getting segment data for analysis."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sample-org-buffer)
    (goto-char (point-min))
    (search-forward "བཀྲ་ཤིས")
    (let ((data (tibetan-org-segment-for-analysis)))
      ;; Function returns segment text (string), not a list
      (should data)
      (should (stringp data))
      (should (string-match-p "བཀྲ་ཤིས" data)))))

(ert-deftest tibetan-org-segments-for-workspace-basic ()
  "Test getting segments for workspace creation."
  (with-temp-buffer
    (org-mode)
    (insert tibetan-org-test--sentence-org-buffer)
    (goto-char (point-min))
    (search-forward "** Sentence 1")
    (let ((segments (tibetan-org-segments-for-workspace)))
      (should (listp segments)))))

;; ============================================================================
;; SENTENCE GROUPING TESTS
;; Note: tibetan--group-into-sentences expects TEXT (string), not a list.
;; It internally calls tibetan--segment-text to split the text.
;; ============================================================================

(ert-deftest tibetan--group-into-sentences-basic ()
  "Test grouping segments into sentences."
  ;; Pass text, not list - function internally segments
  (let ((text "First།Second།Third།།Fourth།"))
    (let ((sentences (tibetan--group-into-sentences text)))
      (should (listp sentences))
      ;; Double shad should end a sentence
      (should (>= (length sentences) 1)))))

(ert-deftest tibetan--group-into-sentences-empty ()
  "Test grouping with empty input."
  (let ((sentences (tibetan--group-into-sentences "")))
    (should (or (null sentences)
                (and (listp sentences) (= 0 (length sentences)))))))

(ert-deftest tibetan--group-into-sentences-single ()
  "Test grouping single segment."
  (let ((sentences (tibetan--group-into-sentences "Only one།")))
    (should (listp sentences))
    (should (= 1 (length sentences)))))

;; ============================================================================
;; PREPARE FROM REGION TESTS
;; ============================================================================

(ert-deftest tibetan-prepare-document-from-region-callable ()
  "Test that prepare-document-from-region is callable."
  (should (fboundp 'tibetan-prepare-document-from-region)))

(ert-deftest tibetan-prepare-new-document-callable ()
  "Test that prepare-new-document is callable."
  (should (fboundp 'tibetan-prepare-new-document)))

;; ============================================================================
;; MAIN VERB DETECTION TESTS (clause analysis integration)
;; ============================================================================

(ert-deftest tibetan--segment-has-main-verb-p-copula ()
  "Test main verb detection for copula ཡིན།"
  (should (tibetan--segment-has-main-verb-p "དེ་ནི་ཆོས་ཡིན།")))

(ert-deftest tibetan--segment-has-main-verb-p-existential ()
  "Test main verb detection for existential ཡོད།"
  (should (tibetan--segment-has-main-verb-p "དེ་ཡོད་དོ།")))

(ert-deftest tibetan--segment-has-main-verb-p-final-particle ()
  "Test main verb detection by final particle."
  (should (tibetan--segment-has-main-verb-p "བྱས་སོ།")))

(ert-deftest tibetan--segment-has-main-verb-p-double-shad ()
  "Test main verb detection by double shad."
  (should (tibetan--segment-has-main-verb-p "བྱས།།")))

(ert-deftest tibetan--segment-is-converb-only-p-coordinative ()
  "Test converb-only detection for coordinative -ste."
  (should (tibetan--segment-is-converb-only-p "བྱས་ནས་སྟེ")))

(ert-deftest tibetan--segment-is-converb-only-p-false-for-main-verb ()
  "Test that main verb segments are not converb-only."
  (should-not (tibetan--segment-is-converb-only-p "བྱས་སོ།")))

(ert-deftest tibetan--segment-ends-sentence-p-double-shad ()
  "Test sentence ending detection by double shad."
  (should (tibetan--segment-ends-sentence-p "བྱས།།")))

(ert-deftest tibetan--segment-ends-sentence-p-final-particle ()
  "Test sentence ending detection by final particle."
  (should (tibetan--segment-ends-sentence-p "བྱས་སོ།")))

(ert-deftest tibetan--segment-ends-sentence-p-not-converb ()
  "Test that converb doesn't end sentence."
  (should-not (tibetan--segment-ends-sentence-p "བྱས་ནས")))

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(defun tibetan-org-structure-run-tests ()
  "Run all tibetan-org-structure tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-org-"))

(provide 'tibetan-org-structure-test)
;;; tibetan-org-structure-test.el ends here
