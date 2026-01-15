;;; document-prep-spec.el --- BDD specs for document preparation -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for the Tibetan document preparation feature.
;; Tests the workflow of:
;; - Pasting raw Tibetan text
;; - Running tibetan-prepare-document (C-c u P)
;; - Getting a properly structured org document ready for C-c u A analysis

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; DOCUMENT PREPARATION SUITE
;; ============================================================================

(define-bdd-suite document-preparation
    "Document preparation (C-c u P)"

  ;; --- Basic Segmentation ---
  (spec "Segment text by shad punctuation"
    :given (setq test-text "བཀྲ་ཤིས།བདེ་ལེགས།སངས་རྒྱས།")
    :when (tibetan--segment-text test-text)
    :then ((should (= 3 (length result)))
           (should (string-match-p "བཀྲ་ཤིས" (nth 0 result)))
           (should (string-match-p "བདེ་ལེགས" (nth 1 result)))
           (should (string-match-p "སངས་རྒྱས" (nth 2 result))))
    :example "Three clauses separated by shad"
    :tags (:segmentation :basic))

  (spec "Segment text by line breaks"
    :given (setq test-text "First line།
Second line།
Third line།")
    :when (tibetan--segment-text test-text)
    :then ((should (= 3 (length result)))
           (should (string-match-p "First" (nth 0 result)))
           (should (string-match-p "Second" (nth 1 result)))
           (should (string-match-p "Third" (nth 2 result))))
    :example "Three lines of text"
    :tags (:segmentation :lines))

  (spec "Prioritize line breaks over shad"
    :given (setq test-text "Line one།with shad།
Line two།also shad།")
    :when (tibetan--segment-text test-text)
    :then ((should (= 2 (length result)))
           (tibetan-bdd-assert-contains (nth 0 result) "Line one"
            "First segment should be first line"))
    :example "Lines with internal shads"
    :tags (:segmentation :priority))

  (spec "Handle empty text gracefully"
    :given (setq test-text "")
    :when (tibetan--segment-text test-text)
    :then ((should (= 0 (length result))))
    :tags (:segmentation :edge-cases))

  (spec "Handle whitespace-only text"
    :given (setq test-text "   \n\n   ")
    :when (tibetan--segment-text test-text)
    :then ((should (= 0 (length result))))
    :tags (:segmentation :edge-cases))

  ;; --- Tibetan Text Handling ---
  (spec "Preserve Tibetan Unicode in segments"
    :given (setq test-text "ཡང་སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་པའི་ཚེ།
ཡུལ་དེའི་ཚོང་པ་ལྔ་བརྒྱ།")
    :when (tibetan--segment-text test-text)
    :then ((should (= 2 (length result)))
           (should (string-match-p "སྟོན་པ" (nth 0 result)))
           (should (string-match-p "ཚོང་པ" (nth 1 result))))
    :example "Padma rnam-rgyal opening"
    :tags (:segmentation :tibetan))

  (spec "Handle double-shad as sentence boundary"
    :given (setq test-text "First sentence།།Second sentence།")
    :when (tibetan--segment-text test-text)
    :then ((should (>= (length result) 2)))
    :example "Sentences with double shad"
    :tags (:segmentation :double-shad))

  ;; --- Full Document Preparation ---
  (spec "Create org headers"
    :given (with-temp-buffer
             (insert "Test text།")
             (tibetan-prepare-document "My Document")
             (setq result (buffer-string)))
    :when result
    :then ((tibetan-bdd-assert-contains result "#+TITLE: My Document"
            "Should have title header")
           (tibetan-bdd-assert-contains result "#+STARTUP: fold"
            "Should have startup header")
           (tibetan-bdd-assert-contains result "#+DATE:"
            "Should have date header"))
    :example "Document with custom title"
    :tags (:document :headers))

  (spec "Create segment headings"
    :given (with-temp-buffer
             (insert "First།Second།Third།")
             (tibetan-prepare-document "Test")
             (setq result (buffer-string)))
    :when result
    :then ((tibetan-bdd-assert-contains result "*** Segment 1"
            "Should have Segment 1")
           (tibetan-bdd-assert-contains result "*** Segment 2"
            "Should have Segment 2")
           (tibetan-bdd-assert-contains result "*** Segment 3"
            "Should have Segment 3"))
    :example "Three segments"
    :tags (:document :structure))

  (spec "Create sentence groupings"
    :given (with-temp-buffer
             (insert "Test།")
             (tibetan-prepare-document "Test")
             (setq result (buffer-string)))
    :when result
    :then ((tibetan-bdd-assert-contains result "** Sentence 1"
            "Should group segments under sentences"))
    :example "Sentence-structured document"
    :tags (:document :sentences))

  (spec "Create vocabulary table"
    :given (with-temp-buffer
             (insert "Test།")
             (tibetan-prepare-document "Test")
             (setq result (buffer-string)))
    :when result
    :then ((tibetan-bdd-assert-contains result "* Vocabulary"
            "Should have Vocabulary section")
           (tibetan-bdd-assert-contains result "| Tibetan | Wylie | English |"
            "Should have vocabulary table header"))
    :example "Vocabulary section"
    :tags (:document :vocabulary))

  (spec "Create notes section"
    :given (with-temp-buffer
             (insert "Test།")
             (tibetan-prepare-document "Test")
             (setq result (buffer-string)))
    :when result
    :then ((tibetan-bdd-assert-contains result "* Notes"
            "Should have Notes section"))
    :example "Notes section"
    :tags (:document :notes))

  ;; --- Real-World Text Tests ---
  (spec "Prepare Ocean Deity text (Padma rnam-rgyal)"
    :given (with-temp-buffer
             (insert "ཡང་སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་པའི་ཚེ།
ཡུལ་དེའི་ཚོང་པ་ལྔ་བརྒྱ་རྒྱ་མཚོར་རིན་པོ་ཆེ་ལེན་དུ་འགྲོ་བ་དག་གིས།
བདག་ཅག་གིས་མིའི་ནང་ནས་མཁས་ཤིང་ཤེས་པ་ཞིག་དེད་དཔོན་དུ་བཀྲིའོ།")
             (tibetan-prepare-document "Ocean Deity")
             (setq result (buffer-string)))
    :when result
    :then ((tibetan-bdd-assert-contains result "*** Segment 1"
            "Should create first segment")
           (tibetan-bdd-assert-contains result "*** Segment 2"
            "Should create second segment")
           (tibetan-bdd-assert-contains result "*** Segment 3"
            "Should create third segment")
           (tibetan-bdd-assert-contains result "སྟོན་པ"
            "Should preserve Tibetan text"))
    :example "Padma rnam-rgyal opening verses"
    :tags (:document :real-world :padma-rnam-rgyal))

  (spec "Segments are ready for C-c u A analysis"
    :given (with-temp-buffer
             (org-mode)
             (insert "Test།Text།Here།")
             (tibetan-prepare-document "Analysis Test")
             (goto-char (point-min))
             (search-forward "*** Segment 1")
             (setq result (tibetan-org-at-segment-p)))
    :when result
    :then ((should result))
    :example "Prepared segment is detectable"
    :tags (:document :integration :critical)))

;; ============================================================================
;; ORG STRUCTURE DETECTION SUITE
;; ============================================================================

(define-bdd-suite org-structure-detection
    "Org structure detection for segment analysis"

  (spec "Detect segment at heading"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Section\n*** Segment 1\nText here")
             (goto-char (point-min))
             (search-forward "*** Segment 1")
             (beginning-of-line)
             (setq result (tibetan-org-at-segment-p)))
    :when result
    :then ((should result))
    :example "Cursor on segment heading"
    :tags (:detection :heading))

  (spec "Detect segment in content"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Section\n*** Segment 1\nText here")
             (goto-char (point-min))
             (search-forward "Text here")
             (setq result (tibetan-org-at-segment-p)))
    :when result
    :then ((should result))
    :example "Cursor in segment content"
    :tags (:detection :content))

  (spec "Not detect at section heading"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Section\n*** Segment 1\nText")
             (goto-char (point-min))
             (search-forward "** Section")
             (beginning-of-line)
             (setq result (tibetan-org-at-segment-p)))
    :when result
    :then ((should-not result))
    :example "Cursor on section heading"
    :tags (:detection :negative))

  (spec "Get segment text from heading"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Section\n*** Segment 1\nབཀྲ་ཤིས།\n*** Segment 2")
             (goto-char (point-min))
             (search-forward "*** Segment 1")
             (setq result (tibetan-org-get-segment-text)))
    :when result
    :then ((should result)
           (should (string-match-p "བཀྲ་ཤིས" result)))
    :example "Extract Tibetan text from segment"
    :tags (:extraction :text))

  (spec "Get segment ID"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Section\n*** Segment 42\nText")
             (goto-char (point-min))
             (search-forward "*** Segment 42")
             (setq result (tibetan-org-get-segment-id)))
    :when result
    :then ((should (= 42 result)))
    :example "Extract segment number"
    :tags (:extraction :id))

  (spec "Get parent section name"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** [30] Introduction\n*** Segment 1\nText")
             (goto-char (point-min))
             (search-forward "*** Segment 1")
             (setq result (tibetan-org-get-parent-section-name)))
    :when result
    :then ((should result)
           (should (string-match-p "\\[30\\]" result))
           (should (string-match-p "Introduction" result)))
    :example "Padma rnam-rgyal section format"
    :tags (:extraction :section :padma-format)))

(provide 'document-prep-spec)
;;; document-prep-spec.el ends here
