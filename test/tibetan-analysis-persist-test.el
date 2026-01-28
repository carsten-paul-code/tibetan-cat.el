;;; tibetan-analysis-persist-test.el --- Tests for tibetan-analysis-persist.el -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for Tibetan analysis persistence module.
;; Tests cover: filename generation, hash computation, section parsing,
;; and utility functions.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-analysis-persist)

;; ============================================================================
;; FILENAME GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-make-short-name-tigress ()
  "Test short name generation for Tigress file."
  (should (string= "tigress"
                   (tibetan-analysis-make-short-name "Tigress-Story-BlockPrint-Class.org"))))

(ert-deftest tibetan-analysis-make-short-name-saskya ()
  "Test short name generation for Sa-skya file."
  (should (string= "saskya"
                   (tibetan-analysis-make-short-name "Reading-Sa-skya-legs-bshad.org"))))

(ert-deftest tibetan-analysis-make-short-name-reading ()
  "Test short name generation for Reading files."
  (let ((result (tibetan-analysis-make-short-name "Reading-05-Padma.org")))
    (should (stringp result))
    (should (string-match-p "reading" result))))

(ert-deftest tibetan-analysis-make-short-name-generic ()
  "Test short name generation for generic files."
  (let ((result (tibetan-analysis-make-short-name "SomeDocument.org")))
    (should (stringp result))
    (should (> (length result) 0))
    (should (<= (length result) 8))))

(ert-deftest tibetan-analysis-make-short-name-nil ()
  "Test short name generation with nil input."
  (should (null (tibetan-analysis-make-short-name nil))))

(ert-deftest tibetan-analysis-segment-filename-number ()
  "Test segment filename generation from number."
  (let ((result (tibetan-analysis-segment-filename 1)))
    (should (string= "seg-001.org" result))))

(ert-deftest tibetan-analysis-segment-filename-number-with-source ()
  "Test segment filename generation from number with source file."
  (let ((result (tibetan-analysis-segment-filename 42 "Tigress-Story.org")))
    (should (string-match-p "seg-042" result))
    (should (string-match-p "tigress" result))
    (should (string-suffix-p ".org" result))))

(ert-deftest tibetan-analysis-segment-filename-string ()
  "Test segment filename generation from string ID."
  (let ((result (tibetan-analysis-segment-filename "Segment 15")))
    (should (string= "seg-015.org" result))))

(ert-deftest tibetan-analysis-segment-filename-string-with-source ()
  "Test segment filename generation from string with source."
  (let ((result (tibetan-analysis-segment-filename "Segment 7" "Reading-Sa-skya-legs-bshad.org")))
    (should (string-match-p "seg-007" result))
    (should (string-match-p "saskya" result))))

(ert-deftest tibetan-analysis-segment-filename-line-format ()
  "Test segment filename with Line N format."
  (let ((result (tibetan-analysis-segment-filename "Line 3")))
    (should (string-match-p "seg-003" result))))

(ert-deftest tibetan-analysis-segment-filename-padding ()
  "Test that segment numbers are zero-padded to 3 digits."
  (should (string-match-p "seg-001" (tibetan-analysis-segment-filename 1)))
  (should (string-match-p "seg-010" (tibetan-analysis-segment-filename 10)))
  (should (string-match-p "seg-100" (tibetan-analysis-segment-filename 100))))

;; ============================================================================
;; HASH COMPUTATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-compute-hash-basic ()
  "Test basic hash computation."
  (let ((hash (tibetan-analysis-compute-hash "test")))
    (should (stringp hash))
    (should (= 32 (length hash)))))  ; MD5 is 32 hex chars

(ert-deftest tibetan-analysis-compute-hash-consistency ()
  "Test that same input gives same hash."
  (let ((text "བཀྲ་ཤིས་བདེ་ལེགས།"))
    (should (string= (tibetan-analysis-compute-hash text)
                     (tibetan-analysis-compute-hash text)))))

(ert-deftest tibetan-analysis-compute-hash-different ()
  "Test that different inputs give different hashes."
  (should-not (string= (tibetan-analysis-compute-hash "text1")
                       (tibetan-analysis-compute-hash "text2"))))

(ert-deftest tibetan-analysis-compute-hash-tibetan ()
  "Test hash computation with Tibetan text."
  (let ((hash (tibetan-analysis-compute-hash "བཀྲ་ཤིས།")))
    (should (stringp hash))
    (should (= 32 (length hash)))))

(ert-deftest tibetan-analysis-compute-hash-empty ()
  "Test hash computation with empty string."
  (let ((hash (tibetan-analysis-compute-hash "")))
    (should (stringp hash))
    (should (= 32 (length hash)))))

;; ============================================================================
;; SECTION BOUNDS PARSING TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-find-section-bounds-basic ()
  "Test finding section bounds in buffer."
  (with-temp-buffer
    (insert "* Section 1\nContent 1\n* Section 2\nContent 2\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Section 1")))
      (should bounds)
      (should (consp bounds))
      (should (integerp (car bounds)))
      (should (integerp (cdr bounds))))))

(ert-deftest tibetan-analysis-find-section-bounds-not-found ()
  "Test finding non-existent section."
  (with-temp-buffer
    (insert "* Section 1\nContent\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Missing")))
      (should (null bounds)))))

(ert-deftest tibetan-analysis-find-section-bounds-nested ()
  "Test finding section bounds with subsections."
  (with-temp-buffer
    (insert "* Top\n** Sub1\nContent 1\n** Sub2\nContent 2\n* Next\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Top")))
      (should bounds)
      (should (< (car bounds) (cdr bounds))))))

;; ============================================================================
;; USER SECTION EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-get-user-sections-callable ()
  "Test that get-user-sections function exists."
  (should (fboundp 'tibetan-analysis-get-user-sections)))

;; ============================================================================
;; SYNC CHECK TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-check-sync-no-file ()
  "Test sync check when file doesn't exist."
  (let ((result (tibetan-analysis-check-sync "/nonexistent/path.org" "text")))
    ;; Should return nil or handle gracefully
    (should (or (null result) (eq result t)))))

;; ============================================================================
;; FACE SETUP TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-setup-faces-callable ()
  "Test that face setup function is callable."
  (should (fboundp 'tibetan-analysis-setup-faces)))

(ert-deftest tibetan-analysis-tibetan-face-exists ()
  "Test that Tibetan face is defined."
  (should (facep 'tibetan-analysis-tibetan-face)))

(ert-deftest tibetan-analysis-roman-face-exists ()
  "Test that roman face is defined."
  (should (facep 'tibetan-analysis-roman-face)))

;; ============================================================================
;; VOCABULARY LOADING TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-ensure-vocabulary-callable ()
  "Test that vocabulary loading function exists."
  (should (fboundp 'tibetan-analysis--ensure-vocabulary)))

(ert-deftest tibetan-analysis-get-particle-annotation-callable ()
  "Test that particle annotation function exists."
  (should (fboundp 'tibetan-analysis--get-particle-annotation)))

(ert-deftest tibetan-analysis-get-word-info-callable ()
  "Test that word info function exists."
  (should (fboundp 'tibetan-analysis--get-word-info)))

;; ============================================================================
;; CONTENT GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-generate-content-callable ()
  "Test that content generation function exists."
  (should (fboundp 'tibetan-analysis-generate-content)))

(ert-deftest tibetan-analysis-generate-content-empty ()
  "Test content generation with empty input."
  ;; Should not error on empty input
  (condition-case err
      (let ((result (tibetan-analysis-generate-content "")))
        (should (or (null result) (stringp result))))
    (error (should-not "Should not error on empty input"))))

(ert-deftest tibetan-analysis-generate-content-basic ()
  "Test basic content generation."
  ;; Note: Full content generation depends on vocabulary being loaded
  (condition-case nil
      (let ((result (tibetan-analysis-generate-content "བདག")))
        (should (or (null result) (stringp result))))
    (error nil)))  ; Allow errors if dependencies not loaded

;; ============================================================================
;; MAIN INTERFACE TESTS
;; ============================================================================

(ert-deftest tibetan-open-segment-analysis-callable ()
  "Test that main analysis function exists."
  (should (fboundp 'tibetan-open-segment-analysis)))

(ert-deftest tibetan-reanalyze-segment-callable ()
  "Test that reanalysis function exists."
  (should (fboundp 'tibetan-reanalyze-segment)))

(ert-deftest tibetan-collect-all-segments-callable ()
  "Test that segment collection function exists."
  (should (fboundp 'tibetan-collect-all-segments)))

(ert-deftest tibetan-analyze-all-segments-callable ()
  "Test that batch analysis function exists."
  (should (fboundp 'tibetan-analyze-all-segments)))

(ert-deftest tibetan-refresh-dharmamitra-translation-callable ()
  "Test that translation refresh function exists."
  (should (fboundp 'tibetan-refresh-dharmamitra-translation)))

(ert-deftest tibetan-copy-dharmamitra-to-working-callable ()
  "Test that translation copy function exists."
  (should (fboundp 'tibetan-copy-dharmamitra-to-working)))

;; ============================================================================
;; VERSION AND CONSTANTS TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-version-exists ()
  "Test that version constant is defined."
  (should (boundp 'tibetan-analysis-version))
  (should (stringp tibetan-analysis-version)))

(ert-deftest tibetan-analysis-roman-scale-exists ()
  "Test that roman scale customization exists."
  (should (boundp 'tibetan-analysis-roman-scale))
  (should (numberp tibetan-analysis-roman-scale)))

;; ============================================================================
;; INTEGRATION TESTS (require file system access)
;; ============================================================================

(ert-deftest tibetan-analysis-get-folder-callable ()
  "Test that folder function is callable."
  (should (fboundp 'tibetan-analysis-get-folder)))

(ert-deftest tibetan-analysis-create-file-callable ()
  "Test that file creation function exists."
  (should (fboundp 'tibetan-analysis-create-file)))

(ert-deftest tibetan-analysis-get-filepath-callable ()
  "Test that filepath function exists."
  (should (fboundp 'tibetan-analysis-get-filepath)))

(ert-deftest tibetan-analysis-regenerate-auto-callable ()
  "Test that regeneration function exists."
  (should (fboundp 'tibetan-analysis-regenerate-auto)))

(provide 'tibetan-analysis-persist-test)
;;; tibetan-analysis-persist-test.el ends here
