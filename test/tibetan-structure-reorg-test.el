;;; tibetan-structure-reorg-test.el --- Tests for structure reorganization -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for document structure reorganization functions.
;; Tests cover:
;; - Segment inventory collection
;; - Analysis file inventory
;; - Hash-based matching
;; - Reorganization planning
;; - File operations (rename, archive)

;;; Code:

(require 'ert)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir)))

(require 'tibetan-analysis-persist)
(require 'tibetan-structure-reorg nil t)

;; ============================================================================
;; HASH COMPUTATION TESTS
;; ============================================================================

(ert-deftest tibetan-reorg-hash-consistent ()
  "Test that hash computation is consistent."
  (let* ((text "བཀྲ་ཤིས།")
         (hash1 (tibetan-analysis-compute-hash text))
         (hash2 (tibetan-analysis-compute-hash text)))
    (should (string= hash1 hash2))))

(ert-deftest tibetan-reorg-hash-unique ()
  "Test that different texts produce different hashes."
  (let* ((text1 "བཀྲ་ཤིས།")
         (text2 "བདེ་ལེགས།")
         (hash1 (tibetan-analysis-compute-hash text1))
         (hash2 (tibetan-analysis-compute-hash text2)))
    (should-not (string= hash1 hash2))))

;; ============================================================================
;; DOCUMENT INVENTORY TESTS
;; ============================================================================

(ert-deftest tibetan-reorg-collect-segments-basic ()
  "Test basic segment collection from document."
  (skip-unless (fboundp 'tibetan-reorg--collect-document-segments))
  (with-temp-buffer
    (insert "* Title\n\n** Sentence 1\n\n*** Segment 1\nབཀྲ་ཤིས།\n\n*** Segment 2\nབདེ་ལེགས།\n")
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((result (tibetan-reorg--collect-document-segments)))
      (should result)
      (should (= 2 (length result)))
      (should (= 1 (plist-get (car result) :segment-num)))
      (should (= 2 (plist-get (cadr result) :segment-num))))))

(ert-deftest tibetan-reorg-collect-segments-empty ()
  "Test segment collection on empty document."
  (skip-unless (fboundp 'tibetan-reorg--collect-document-segments))
  (with-temp-buffer
    (insert "* Title\n\n** Notes\nNo segments here\n")
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((result (tibetan-reorg--collect-document-segments)))
      (should (null result)))))

(ert-deftest tibetan-reorg-collect-segments-with-content ()
  "Test that segment collection captures Tibetan text."
  (skip-unless (fboundp 'tibetan-reorg--collect-document-segments))
  (with-temp-buffer
    (insert "* Title\n\n** Sentence 1\n\n*** Segment 1\nསངས་རྒྱས།\n")
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((result (tibetan-reorg--collect-document-segments)))
      (should result)
      (should (string-match-p "སངས་རྒྱས" (plist-get (car result) :tibetan-text))))))

(ert-deftest tibetan-reorg-collect-segments-nested-layout ()
  "Collects segments from the canonical §2.12 reading layout — Sentence
at level 3, Segment at level 4 (with a `**** Working Translation'
sibling).  Regression: the collector's regex matched only heading
levels 2-3, so it found ZERO segments in this layout and
`tibetan-reorganize-analysis-files' errored \"No segments found\"."
  (skip-unless (fboundp 'tibetan-reorg--collect-document-segments))
  (with-temp-buffer
    (insert "* Tibetan Text\n\n** Section 1\n\n*** Sentence 1\n\n"
            "**** Segment 1\nབཀྲ་ཤིས།\n\n"
            "**** Working Translation\n\n"
            "**** Segment 2\nབདེ་ལེགས།\n\n")
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((result (tibetan-reorg--collect-document-segments)))
      (should (= 2 (length result)))
      (should (= 1 (plist-get (car result) :segment-num)))
      (should (= 1 (plist-get (car result) :sentence-num)))
      (should (string-match-p "བཀྲ་ཤིས"
                              (plist-get (car result) :tibetan-text))))))

;; ============================================================================
;; FILE INVENTORY TESTS
;; ============================================================================

(ert-deftest tibetan-reorg-collect-files-basic ()
  "Test analysis file inventory collection."
  (skip-unless (fboundp 'tibetan-reorg--collect-analysis-files))
  (let* ((temp-dir (make-temp-file "tibetan-test" t))
         (analysis-dir (expand-file-name "analysis" temp-dir)))
    (unwind-protect
        (progn
          (make-directory analysis-dir t)
          (with-temp-file (expand-file-name "seg-001-test.org" analysis-dir)
            (insert "#+TIBETAN_HASH: abc123\n"))
          (with-temp-file (expand-file-name "seg-002-test.org" analysis-dir)
            (insert "#+TIBETAN_HASH: def456\n"))
          (let ((result (tibetan-reorg--collect-analysis-files analysis-dir)))
            (should result)
            (should (= 2 (length result)))))
      (delete-directory temp-dir t))))

(ert-deftest tibetan-reorg-collect-files-empty-dir ()
  "Test file inventory on empty directory."
  (skip-unless (fboundp 'tibetan-reorg--collect-analysis-files))
  (let ((temp-dir (make-temp-file "tibetan-test" t)))
    (unwind-protect
        (let ((result (tibetan-reorg--collect-analysis-files temp-dir)))
          (should (null result)))
      (delete-directory temp-dir t))))

(ert-deftest tibetan-reorg-collect-files-extracts-hash ()
  "Test that file inventory extracts hashes correctly."
  (skip-unless (fboundp 'tibetan-reorg--collect-analysis-files))
  (let* ((temp-dir (make-temp-file "tibetan-test" t))
         (expected-hash "abc123def456"))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "seg-001.org" temp-dir)
            (insert (format "#+TIBETAN_HASH: %s\n" expected-hash)))
          (let* ((result (tibetan-reorg--collect-analysis-files temp-dir))
                 (file-info (car result)))
            (should file-info)
            (should (string= expected-hash (plist-get file-info :hash)))))
      (delete-directory temp-dir t))))

;; ============================================================================
;; HASH-BASED MATCHING TESTS
;; ============================================================================

(ert-deftest tibetan-reorg-find-by-hash-found ()
  "Test finding analysis file by hash."
  (skip-unless (fboundp 'tibetan-reorg--find-analysis-by-hash))
  (let* ((temp-dir (make-temp-file "tibetan-test" t))
         (target-hash "target-hash-123"))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "seg-001.org" temp-dir)
            (insert "#+TIBETAN_HASH: other-hash\n"))
          (with-temp-file (expand-file-name "seg-002.org" temp-dir)
            (insert (format "#+TIBETAN_HASH: %s\n" target-hash)))
          (let ((result (tibetan-reorg--find-analysis-by-hash target-hash temp-dir)))
            (should result)
            (should (string-match-p "seg-002\\.org" result))))
      (delete-directory temp-dir t))))

(ert-deftest tibetan-reorg-find-by-hash-not-found ()
  "Test hash search when no match exists."
  (skip-unless (fboundp 'tibetan-reorg--find-analysis-by-hash))
  (let ((temp-dir (make-temp-file "tibetan-test" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "seg-001.org" temp-dir)
            (insert "#+TIBETAN_HASH: some-hash\n"))
          (let ((result (tibetan-reorg--find-analysis-by-hash "nonexistent" temp-dir)))
            (should-not result)))
      (delete-directory temp-dir t))))

;; ============================================================================
;; PLANNING TESTS
;; ============================================================================

(ert-deftest tibetan-reorg-plan-no-changes ()
  "Test planning when no changes needed."
  (skip-unless (fboundp 'tibetan-reorg--plan-actions))
  (let ((doc-segments '((:segment-num 1 :hash "hash-A")
                        (:segment-num 2 :hash "hash-B")))
        (file-inventory '((:filename "seg-001.org" :segment-num 1 :hash "hash-A")
                          (:filename "seg-002.org" :segment-num 2 :hash "hash-B"))))
    (let ((result (tibetan-reorg--plan-actions doc-segments file-inventory)))
      ;; Should have no actions or only 'keep' actions
      (should-not (cl-find-if (lambda (a)
                                (memq (plist-get a :action) '(rename create orphan)))
                              result)))))

(ert-deftest tibetan-reorg-plan-rename-needed ()
  "Test planning when segments are swapped."
  (skip-unless (fboundp 'tibetan-reorg--plan-actions))
  (let ((doc-segments '((:segment-num 1 :hash "hash-B")
                        (:segment-num 2 :hash "hash-A")))
        (file-inventory '((:filename "seg-001.org" :segment-num 1 :hash "hash-A")
                          (:filename "seg-002.org" :segment-num 2 :hash "hash-B"))))
    (let ((result (tibetan-reorg--plan-actions doc-segments file-inventory)))
      ;; Should detect renames needed
      (should (cl-find-if (lambda (a) (eq (plist-get a :action) 'rename)) result)))))

(ert-deftest tibetan-reorg-plan-orphan-detected ()
  "Test planning detects orphaned files."
  (skip-unless (fboundp 'tibetan-reorg--plan-actions))
  (let ((doc-segments '((:segment-num 1 :hash "hash-A")))
        (file-inventory '((:filename "seg-001.org" :segment-num 1 :hash "hash-A")
                          (:filename "seg-002.org" :segment-num 2 :hash "hash-B"))))
    (let ((result (tibetan-reorg--plan-actions doc-segments file-inventory)))
      ;; Should mark seg-002 as orphan
      (should (cl-find-if (lambda (a) (eq (plist-get a :action) 'orphan)) result)))))

(ert-deftest tibetan-reorg-plan-create-needed ()
  "Test planning detects new segments."
  (skip-unless (fboundp 'tibetan-reorg--plan-actions))
  (let ((doc-segments '((:segment-num 1 :hash "hash-A")
                        (:segment-num 2 :hash "hash-B")))
        (file-inventory '((:filename "seg-001.org" :segment-num 1 :hash "hash-A"))))
    (let ((result (tibetan-reorg--plan-actions doc-segments file-inventory)))
      ;; Should mark segment 2 as needing creation
      (should (cl-find-if (lambda (a) (eq (plist-get a :action) 'create)) result)))))

(ert-deftest tibetan-reorg-generate-new-filename-suffixed-multisource ()
  "`tibetan-reorg--generate-new-filename' honours the §5.23 per-source
short-name suffix when given a source file, so a reorg run in a
multi-source folder does not rename files back to a bare seg-NNN.org
\(which collides across sources)."
  (skip-unless (fboundp 'tibetan-reorg--generate-new-filename))
  ;; With a source file → suffixed name.
  (let ((name (tibetan-reorg--generate-new-filename
               1 "/tmp/gal-chen-nyi-shu.org")))
    (should (string-match-p "^seg-001-.+\\.org$" name))
    (should-not (string= name "seg-001.org")))
  ;; Different source → different suffix (no collision).
  (let ((a (tibetan-reorg--generate-new-filename 1 "/tmp/gal-chen-nyi-shu.org"))
        (b (tibetan-reorg--generate-new-filename 1 "/tmp/lam-rim-thun-cig.org")))
    (should-not (string= a b)))
  ;; No source file → bare name (back-compat).
  (should (string= (tibetan-reorg--generate-new-filename 1 nil)
                   "seg-001.org")))

;; ============================================================================
;; FILE OPERATION TESTS
;; ============================================================================

(ert-deftest tibetan-reorg-rename-file ()
  "Test file renaming."
  (skip-unless (fboundp 'tibetan-reorg--rename-analysis-file))
  (let* ((temp-dir (make-temp-file "tibetan-test" t))
         (old-file (expand-file-name "seg-001.org" temp-dir))
         (new-file (expand-file-name "seg-002.org" temp-dir)))
    (unwind-protect
        (progn
          (with-temp-file old-file
            (insert "Original content\n"))
          (tibetan-reorg--rename-analysis-file old-file new-file 2)
          (should (file-exists-p new-file))
          (should-not (file-exists-p old-file)))
      (delete-directory temp-dir t))))

(ert-deftest tibetan-reorg-update-source-link ()
  "Test SOURCE link update."
  (skip-unless (fboundp 'tibetan-reorg--update-source-link))
  (let* ((temp-dir (make-temp-file "tibetan-test" t))
         (test-file (expand-file-name "seg-002.org" temp-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "#+TITLE: Segment 1\n")
            (insert "#+SOURCE: [[file:../test.org::*Segment 1][test.org / Segment 1]]\n"))
          (tibetan-reorg--update-source-link test-file 2)
          (with-temp-buffer
            (insert-file-contents test-file)
            (should (string-match-p "Segment 2" (buffer-string)))
            (should-not (string-match-p "\\*Segment 1\\]" (buffer-string)))))
      (delete-directory temp-dir t))))

(ert-deftest tibetan-reorg-archive-orphan ()
  "Test orphan archiving."
  (skip-unless (fboundp 'tibetan-reorg--archive-orphan))
  (let* ((temp-dir (make-temp-file "tibetan-test" t))
         (analysis-dir (expand-file-name "analysis" temp-dir))
         (orphan-file (expand-file-name "seg-099.org" analysis-dir))
         (archive-dir (expand-file-name ".archive" analysis-dir)))
    (unwind-protect
        (progn
          (make-directory analysis-dir t)
          (with-temp-file orphan-file
            (insert "* My Notes\nUser notes\n"))
          (tibetan-reorg--archive-orphan orphan-file)
          (should (file-exists-p (expand-file-name "seg-099.org" archive-dir)))
          (should-not (file-exists-p orphan-file)))
      (delete-directory temp-dir t))))

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(defun tibetan-structure-reorg-run-tests ()
  "Run all structure reorganization tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-reorg-"))

(provide 'tibetan-structure-reorg-test)
;;; tibetan-structure-reorg-test.el ends here
