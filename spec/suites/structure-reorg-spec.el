;;; structure-reorg-spec.el --- BDD specs for structure reorganization -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for document structure reorganization.
;; When a user changes the document structure (add/remove/reorder segments),
;; the analysis files should be reorganized to match while preserving notes.
;;
;; Key scenarios:
;; 1. Segment renumbering (insert new segment, others shift)
;; 2. Segment deletion (with orphaned analysis file handling)
;; 3. Sentence restructuring (segments move between sentences)
;; 4. Full document refresh after major edits

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; SEGMENT MATCHING SUITE
;; ============================================================================

(define-bdd-suite segment-matching
    "Match analysis files to document segments by content"

  (spec "Match analysis file by Tibetan text hash"
    :given (progn
             (setq test-tibetan "བཀྲ་ཤིས་བདེ་ལེགས།")
             (setq test-hash (tibetan-analysis-compute-hash test-tibetan)))
    :when test-hash
    :then ((should test-hash)
           (should (stringp test-hash))
           (should (= 32 (length test-hash))))
    :example "MD5 hash for content matching"
    :tags (:reorg :matching))

  (spec "Find analysis file for segment text"
    :given (let* ((temp-dir (make-temp-file "tibetan-test" t))
                  (analysis-dir (expand-file-name "analysis" temp-dir))
                  (test-tibetan "བཀྲ་ཤིས།")
                  (hash (tibetan-analysis-compute-hash test-tibetan)))
             (make-directory analysis-dir t)
             ;; Create a test analysis file
             (with-temp-file (expand-file-name "seg-001-test.org" analysis-dir)
               (insert "#+TITLE: Test\n")
               (insert (format "#+TIBETAN_HASH: %s\n" hash))
               (insert "* Tibetan Text\n")
               (insert test-tibetan))
             (setq result (tibetan-reorg--find-analysis-by-hash hash analysis-dir)))
    :when result
    :then ((should result)
           (should (string-match-p "seg-001-test\\.org" result)))
    :example "Locate analysis file by content hash"
    :tags (:reorg :matching :hash))

  (spec "Handle missing analysis file gracefully"
    :given (let* ((temp-dir (make-temp-file "tibetan-test" t)))
             ;; Create a file with different hash
             (with-temp-file (expand-file-name "seg-001.org" temp-dir)
               (insert "#+TIBETAN_HASH: different-hash\n"))
             (setq test-dir temp-dir))
    :when (tibetan-reorg--find-analysis-by-hash "nonexistent" test-dir)
    :then ((should-not result))
    :example "Return nil when no match found"
    :tags (:reorg :matching :edge-case)))

;; ============================================================================
;; SEGMENT INVENTORY SUITE
;; ============================================================================

(define-bdd-suite segment-inventory
    "Build inventory of document segments and analysis files"

  (spec "Collect document segment inventory"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Sentence 1\n*** Segment 1\nབཀྲ་ཤིས།\n*** Segment 2\nབདེ་ལེགས།\n")
             (setq result (tibetan-reorg--collect-document-segments)))
    :when result
    :then ((should result)
           (should (= 2 (length result)))
           ;; Each entry should have segment-num, tibetan-text, hash
           (should (plist-get (car result) :segment-num))
           (should (plist-get (car result) :tibetan-text))
           (should (plist-get (car result) :hash)))
    :example "Inventory document segments"
    :tags (:reorg :inventory))

  (spec "Collect analysis file inventory"
    :given (let* ((temp-dir (make-temp-file "tibetan-test" t))
                  (analysis-dir (expand-file-name "analysis" temp-dir)))
             (make-directory analysis-dir t)
             ;; Create test files
             (with-temp-file (expand-file-name "seg-001-test.org" analysis-dir)
               (insert "#+TIBETAN_HASH: abc123\n"))
             (with-temp-file (expand-file-name "seg-002-test.org" analysis-dir)
               (insert "#+TIBETAN_HASH: def456\n"))
             (setq result (tibetan-reorg--collect-analysis-files analysis-dir)))
    :when result
    :then ((should result)
           (should (= 2 (length result)))
           ;; Each entry should have filename, segment-num, hash
           (should (plist-get (car result) :filename))
           (should (plist-get (car result) :hash)))
    :example "Inventory analysis files"
    :tags (:reorg :inventory :files)))

;; ============================================================================
;; REORGANIZATION PLANNING SUITE
;; ============================================================================

(define-bdd-suite reorg-planning
    "Plan reorganization actions based on inventory comparison"

  (spec "Detect segment number change"
    :given (progn
             ;; Document has segments 1, 2 with hashes A, B
             ;; Analysis files exist for segments 1, 2 with hashes B, A (swapped)
             (setq doc-segments '((:segment-num 1 :hash "hash-A")
                                  (:segment-num 2 :hash "hash-B")))
             (setq file-inventory '((:filename "seg-001.org" :segment-num 1 :hash "hash-B")
                                    (:filename "seg-002.org" :segment-num 2 :hash "hash-A")))
             (setq result (tibetan-reorg--plan-actions doc-segments file-inventory)))
    :when result
    :then ((should result)
           ;; Should detect that files need renaming
           (should (cl-find-if (lambda (a) (eq (plist-get a :action) 'rename)) result)))
    :example "Detect swapped segments"
    :tags (:reorg :planning))

  (spec "Identify orphaned analysis files"
    :given (progn
             ;; Document has 1 segment, but 2 analysis files exist
             (setq doc-segments '((:segment-num 1 :hash "hash-A")))
             (setq file-inventory '((:filename "seg-001.org" :segment-num 1 :hash "hash-A")
                                    (:filename "seg-002.org" :segment-num 2 :hash "hash-B")))
             (setq result (tibetan-reorg--plan-actions doc-segments file-inventory)))
    :when result
    :then ((should result)
           ;; Should mark seg-002.org as orphaned
           (should (cl-find-if (lambda (a) (eq (plist-get a :action) 'orphan)) result)))
    :example "Detect deleted segments"
    :tags (:reorg :planning :orphan))

  (spec "Identify new segments needing analysis"
    :given (progn
             ;; Document has 2 segments, but only 1 analysis file
             (setq doc-segments '((:segment-num 1 :hash "hash-A")
                                  (:segment-num 2 :hash "hash-B")))
             (setq file-inventory '((:filename "seg-001.org" :segment-num 1 :hash "hash-A")))
             (setq result (tibetan-reorg--plan-actions doc-segments file-inventory)))
    :when result
    :then ((should result)
           ;; Should mark segment 2 as needing creation
           (should (cl-find-if (lambda (a) (eq (plist-get a :action) 'create)) result)))
    :example "Detect new segments"
    :tags (:reorg :planning :new)))

;; ============================================================================
;; FILE OPERATIONS SUITE
;; ============================================================================

(define-bdd-suite reorg-file-ops
    "Execute reorganization file operations"

  (spec "Rename analysis file preserving content"
    :given (let* ((temp-dir (make-temp-file "tibetan-test" t))
                  (old-file (expand-file-name "seg-001.org" temp-dir))
                  (new-file (expand-file-name "seg-002.org" temp-dir)))
             (with-temp-file old-file
               (insert "#+TITLE: Segment 1\n")
               (insert "#+SOURCE: [[file:../test.org::*Segment 1][Segment 1]]\n")
               (insert "* My Notes\nImportant note here\n"))
             (tibetan-reorg--rename-analysis-file old-file new-file 2)
             (setq result (and (file-exists-p new-file)
                               (not (file-exists-p old-file)))))
    :when result
    :then ((should result))
    :example "Rename and update internal references"
    :tags (:reorg :file-ops :rename))

  (spec "Update SOURCE link after rename"
    :given (let* ((temp-dir (make-temp-file "tibetan-test" t))
                  (test-file (expand-file-name "seg-002.org" temp-dir)))
             (with-temp-file test-file
               (insert "#+TITLE: Segment 1\n")
               (insert "#+SOURCE: [[file:../test.org::*Segment 1][test.org / Segment 1]]\n"))
             (tibetan-reorg--update-source-link test-file 2)
             (with-temp-buffer
               (insert-file-contents test-file)
               (setq result (buffer-string))))
    :when result
    :then ((should (string-match-p "\\*Segment 2\\]" result))
           ;; Source link should be updated, TITLE is separate
           (should (string-match-p "\\[test\\.org / Segment 2\\]" result)))
    :example "Update SOURCE link to new segment number"
    :tags (:reorg :file-ops :link))

  (spec "Move orphan to archive folder"
    :given (let* ((temp-dir (make-temp-file "tibetan-test" t))
                  (analysis-dir (expand-file-name "analysis" temp-dir))
                  (orphan-file (expand-file-name "seg-099.org" analysis-dir))
                  (archive-dir (expand-file-name "analysis/.archive" temp-dir)))
             (make-directory analysis-dir t)
             (with-temp-file orphan-file
               (insert "* My Notes\nUser notes to preserve\n"))
             (tibetan-reorg--archive-orphan orphan-file)
             (setq result (file-exists-p
                           (expand-file-name "seg-099.org" archive-dir))))
    :when result
    :then ((should result))
    :example "Archive orphaned files instead of deleting"
    :tags (:reorg :file-ops :archive)))

;; ============================================================================
;; INTEGRATION SUITE
;; ============================================================================

(define-bdd-suite reorg-integration
    "Full reorganization workflow"

  (spec "Reorganize after segment insertion"
    :given (let* ((temp-dir (make-temp-file "tibetan-test" t))
                  (analysis-dir (expand-file-name "analysis" temp-dir))
                  (source-file (expand-file-name "test.org" temp-dir)))
             (make-directory analysis-dir t)
             ;; Create source with 3 segments
             (with-temp-file source-file
               (insert "* Title\n** Sentence 1\n")
               (insert "*** Segment 1\nསངས་རྒྱས།\n")
               (insert "*** Segment 2\nཆོས།\n")
               (insert "*** Segment 3\nདགེ་འདུན།\n"))
             ;; Create analysis files for original 2 segments (before insertion)
             (let ((hash-1 (tibetan-analysis-compute-hash "སངས་རྒྱས།"))
                   (hash-3 (tibetan-analysis-compute-hash "དགེ་འདུན།")))
               (with-temp-file (expand-file-name "seg-001-test.org" analysis-dir)
                 (insert (format "#+TIBETAN_HASH: %s\n" hash-1))
                 (insert "* My Notes\nNote for Buddha\n"))
               (with-temp-file (expand-file-name "seg-002-test.org" analysis-dir)
                 (insert (format "#+TIBETAN_HASH: %s\n" hash-3))
                 (insert "* My Notes\nNote for Sangha\n")))
             ;; Test the planning functions directly (avoid interactive prompt)
             (with-current-buffer (find-file-noselect source-file)
               (let* ((doc-segments (tibetan-reorg--collect-document-segments))
                      (file-inventory (tibetan-reorg--collect-analysis-files analysis-dir))
                      (actions (tibetan-reorg--plan-actions doc-segments file-inventory)))
                 ;; Count action types
                 (setq result
                       (list :renamed (length (cl-remove-if-not
                                               (lambda (a) (eq (plist-get a :action) 'rename))
                                               actions))
                             :created (length (cl-remove-if-not
                                               (lambda (a) (eq (plist-get a :action) 'create))
                                               actions))
                             :kept (length (cl-remove-if-not
                                            (lambda (a) (eq (plist-get a :action) 'keep))
                                            actions)))))))
    :when result
    :then ((should result)
           ;; seg-002 (hash-3) should be renamed to seg-003
           (should (>= (plist-get result :renamed) 1))
           ;; segment 2 (ཆོས།) needs new analysis
           (should (>= (plist-get result :created) 1)))
    :example "Handle segment insertion"
    :tags (:reorg :integration :insert)))

(provide 'structure-reorg-spec)
;;; structure-reorg-spec.el ends here
