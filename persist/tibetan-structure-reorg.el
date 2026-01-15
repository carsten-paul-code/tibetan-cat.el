;;; tibetan-structure-reorg.el --- Document structure reorganization -*- lexical-binding: t -*-

;;; Commentary:
;; Reorganizes analysis files when document structure changes.
;;
;; When a user edits their Tibetan document (adding, removing, or reordering
;; segments), this module detects the changes and reorganizes the analysis
;; files to match, preserving user notes and translations.
;;
;; Key features:
;; - Content-based matching (Tibetan text hash) to find moved segments
;; - Safe file renaming with internal link updates
;; - Orphan archiving (not deletion) for deleted segments
;; - Dry-run mode to preview changes
;;
;; Usage:
;;   C-c u O  - Reorganize analysis files to match document structure
;;   C-c u U  - Preview reorganization (dry run)

;;; Code:

(require 'cl-lib)
(require 'org)

(require 'tibetan-analysis-persist)
(require 'tibetan-org-structure nil t)

;; ============================================================================
;; CUSTOMIZATION
;; ============================================================================

(defcustom tibetan-reorg-archive-orphans t
  "If non-nil, archive orphaned analysis files instead of deleting.
Orphans are moved to analysis/.archive/ subdirectory."
  :type 'boolean
  :group 'tibetan-cat)

(defcustom tibetan-reorg-auto-create t
  "If non-nil, automatically create analysis for new segments during reorg."
  :type 'boolean
  :group 'tibetan-cat)

;; ============================================================================
;; INVENTORY: DOCUMENT SEGMENTS
;; ============================================================================

(defun tibetan-reorg--collect-document-segments ()
  "Collect inventory of all segments in current buffer.
Returns list of plists with :segment-num, :tibetan-text, :hash, :sentence-num."
  (save-excursion
    (goto-char (point-min))
    (let ((segments '())
          (current-sentence nil))
      (while (re-search-forward "^\\*\\*\\(\\*?\\) \\(Sentence\\|Segment\\) \\([0-9]+\\)" nil t)
        (let ((level (match-string 1))
              (type (match-string 2))
              (num (string-to-number (match-string 3))))
          (cond
           ;; Sentence heading (level 2)
           ((and (string= level "") (string= type "Sentence"))
            (setq current-sentence num))
           ;; Segment heading (level 3)
           ((and (string= level "*") (string= type "Segment"))
            (let ((text (tibetan-org-get-segment-text)))
              (when text
                (push (list :segment-num num
                            :sentence-num current-sentence
                            :tibetan-text text
                            :hash (tibetan-analysis-compute-hash text))
                      segments)))))))
      (nreverse segments))))

;; ============================================================================
;; INVENTORY: ANALYSIS FILES
;; ============================================================================

(defun tibetan-reorg--collect-analysis-files (directory)
  "Collect inventory of analysis files in DIRECTORY.
Returns list of plists with :filename, :filepath, :segment-num, :hash, :has-notes."
  (when (file-directory-p directory)
    (let ((files (directory-files directory nil "^seg-[0-9]+.*\\.org$"))
          (inventory '()))
      (dolist (file files)
        (let* ((filepath (expand-file-name file directory))
               (seg-num (when (string-match "seg-\\([0-9]+\\)" file)
                          (string-to-number (match-string 1 file))))
               (hash (tibetan-analysis-get-stored-hash filepath))
               (has-notes (tibetan-reorg--file-has-user-content filepath)))
          (push (list :filename file
                      :filepath filepath
                      :segment-num seg-num
                      :hash hash
                      :has-notes has-notes)
                inventory)))
      (nreverse inventory))))

(defun tibetan-reorg--file-has-user-content (filepath)
  "Check if analysis file at FILEPATH has user-added content.
Returns t if My Notes, Working Translation, or Footnotes have content."
  (when (file-exists-p filepath)
    (with-temp-buffer
      (insert-file-contents filepath)
      (let ((has-content nil))
        (dolist (section '("My Notes" "Working Translation" "Footnotes"))
          (goto-char (point-min))
          (when (re-search-forward (format "^\\* %s$" (regexp-quote section)) nil t)
            (forward-line 1)
            (let ((section-start (point))
                  (section-end (save-excursion
                                 (if (re-search-forward "^\\* " nil t)
                                     (line-beginning-position)
                                   (point-max)))))
              ;; Check if section has non-whitespace content
              (when (string-match-p "[^ \t\n]"
                                    (buffer-substring-no-properties section-start section-end))
                (setq has-content t)))))
        has-content))))

;; ============================================================================
;; HASH-BASED MATCHING
;; ============================================================================

(defun tibetan-reorg--find-analysis-by-hash (hash directory)
  "Find analysis file in DIRECTORY with matching HASH.
Returns filepath or nil if not found."
  (when (and hash directory (file-directory-p directory))
    (let ((files (directory-files directory t "^seg-[0-9]+.*\\.org$"))
          (found nil))
      (while (and files (not found))
        (let* ((file (car files))
               (file-hash (tibetan-analysis-get-stored-hash file)))
          (when (and file-hash (string= file-hash hash))
            (setq found file)))
        (setq files (cdr files)))
      found)))

;; ============================================================================
;; PLANNING: DETERMINE REQUIRED ACTIONS
;; ============================================================================

(defun tibetan-reorg--plan-actions (doc-segments file-inventory)
  "Plan reorganization actions based on DOC-SEGMENTS and FILE-INVENTORY.
Returns list of action plists with :action, :source, :target, :segment-num, etc.

Actions:
- keep: File matches document, no change needed
- rename: File content matches but segment number changed
- create: New segment needs analysis file
- orphan: Analysis file has no matching segment"
  (let ((actions '())
        (matched-files '())
        (matched-segments '()))

    ;; First pass: Match files to segments by hash
    (dolist (seg doc-segments)
      (let* ((seg-num (plist-get seg :segment-num))
             (seg-hash (plist-get seg :hash))
             (seg-text (plist-get seg :tibetan-text))
             ;; Find matching file
             (matching-file (cl-find-if
                             (lambda (f) (string= (plist-get f :hash) seg-hash))
                             file-inventory)))
        (if matching-file
            (let ((file-seg-num (plist-get matching-file :segment-num))
                  (filepath (plist-get matching-file :filepath)))
              (push (plist-get matching-file :filename) matched-files)
              (push seg-num matched-segments)
              (if (= file-seg-num seg-num)
                  ;; Perfect match - keep as is
                  (push (list :action 'keep
                              :segment-num seg-num
                              :filepath filepath)
                        actions)
                ;; Content matches but number changed - rename
                (push (list :action 'rename
                            :segment-num seg-num
                            :old-num file-seg-num
                            :source filepath
                            :hash seg-hash)
                      actions)))
          ;; No matching file - need to create
          (push (list :action 'create
                      :segment-num seg-num
                      :tibetan-text seg-text
                      :hash seg-hash)
                actions))))

    ;; Second pass: Find orphaned files
    (dolist (file file-inventory)
      (unless (member (plist-get file :filename) matched-files)
        (push (list :action 'orphan
                    :filepath (plist-get file :filepath)
                    :filename (plist-get file :filename)
                    :has-notes (plist-get file :has-notes)
                    :old-num (plist-get file :segment-num))
              actions)))

    (nreverse actions)))

;; ============================================================================
;; FILE OPERATIONS
;; ============================================================================

(defun tibetan-reorg--rename-analysis-file (old-path new-path new-segment-num)
  "Rename analysis file from OLD-PATH to NEW-PATH.
Updates internal references to NEW-SEGMENT-NUM."
  (when (and (file-exists-p old-path)
             (not (file-exists-p new-path)))
    ;; Rename file
    (rename-file old-path new-path)
    ;; Update internal references
    (tibetan-reorg--update-source-link new-path new-segment-num)
    (tibetan-reorg--update-title new-path new-segment-num)))

(defun tibetan-reorg--update-source-link (filepath new-segment-num)
  "Update the SOURCE link in FILEPATH to reference NEW-SEGMENT-NUM."
  (when (file-exists-p filepath)
    (with-current-buffer (find-file-noselect filepath)
      (save-excursion
        (goto-char (point-min))
        ;; Update #+SOURCE: line
        (when (re-search-forward "^#\\+SOURCE: \\[\\[file:\\([^:]+\\)::\\*Segment [0-9]+\\]\\[\\([^/]+\\) / Segment [0-9]+\\]\\]" nil t)
          (let ((file-ref (match-string 1))
                (file-name (match-string 2)))
            (replace-match (format "#+SOURCE: [[file:%s::*Segment %d][%s / Segment %d]]"
                                   file-ref new-segment-num file-name new-segment-num)))))
      (save-buffer)
      (kill-buffer))))

(defun tibetan-reorg--update-title (filepath new-segment-num)
  "Update the TITLE in FILEPATH to reference NEW-SEGMENT-NUM."
  (when (file-exists-p filepath)
    (with-current-buffer (find-file-noselect filepath)
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^#\\+TITLE: Segment [0-9]+" nil t)
          (replace-match (format "#+TITLE: Segment %d" new-segment-num))))
      (save-buffer)
      (kill-buffer))))

(defun tibetan-reorg--archive-orphan (filepath)
  "Move orphaned analysis file at FILEPATH to archive directory."
  (when (file-exists-p filepath)
    (let* ((dir (file-name-directory filepath))
           (filename (file-name-nondirectory filepath))
           (archive-dir (expand-file-name ".archive" dir)))
      ;; Create archive directory if needed
      (unless (file-exists-p archive-dir)
        (make-directory archive-dir t))
      ;; Move file to archive
      (let ((archive-path (expand-file-name filename archive-dir)))
        ;; Handle existing file in archive
        (when (file-exists-p archive-path)
          (let ((timestamp (format-time-string "%Y%m%d-%H%M%S")))
            (setq archive-path (expand-file-name
                                (format "%s.%s.org"
                                        (file-name-sans-extension filename)
                                        timestamp)
                                archive-dir))))
        (rename-file filepath archive-path)))))

(defun tibetan-reorg--generate-new-filename (segment-num source-file)
  "Generate filename for SEGMENT-NUM analysis.
SOURCE-FILE is used for the short suffix."
  (tibetan-analysis-segment-filename segment-num source-file))

;; ============================================================================
;; EXECUTION
;; ============================================================================

(defun tibetan-reorg--execute-actions (actions analysis-dir source-file &optional dry-run)
  "Execute reorganization ACTIONS in ANALYSIS-DIR.
SOURCE-FILE is used for generating new filenames.
If DRY-RUN is non-nil, only report what would be done.

Returns plist with :renamed, :created, :archived, :kept counts."
  (let ((renamed 0)
        (created 0)
        (archived 0)
        (kept 0)
        (messages '()))

    ;; Process renames first (to avoid conflicts)
    ;; Use temporary names to handle swaps
    (let ((renames (cl-remove-if-not
                    (lambda (a) (eq (plist-get a :action) 'rename))
                    actions))
          (temp-files '()))
      ;; First pass: rename to temp files
      (dolist (action renames)
        (let* ((old-path (plist-get action :source))
               (seg-num (plist-get action :segment-num))
               (temp-path (concat old-path ".reorg-temp")))
          (if dry-run
              (push (format "Would rename: %s -> segment %d"
                            (file-name-nondirectory old-path) seg-num)
                    messages)
            (when (file-exists-p old-path)
              (rename-file old-path temp-path)
              (push (cons temp-path action) temp-files)))))

      ;; Second pass: rename from temp to final
      (dolist (temp-action temp-files)
        (let* ((temp-path (car temp-action))
               (action (cdr temp-action))
               (seg-num (plist-get action :segment-num))
               (new-filename (tibetan-reorg--generate-new-filename seg-num source-file))
               (new-path (expand-file-name new-filename analysis-dir)))
          (unless dry-run
            (rename-file temp-path new-path)
            (tibetan-reorg--update-source-link new-path seg-num)
            (tibetan-reorg--update-title new-path seg-num))
          (setq renamed (1+ renamed)))))

    ;; Process orphans
    (dolist (action actions)
      (when (eq (plist-get action :action) 'orphan)
        (let ((filepath (plist-get action :filepath))
              (has-notes (plist-get action :has-notes)))
          (if dry-run
              (push (format "Would archive: %s%s"
                            (plist-get action :filename)
                            (if has-notes " (has user notes)" ""))
                    messages)
            (when tibetan-reorg-archive-orphans
              (tibetan-reorg--archive-orphan filepath)))
          (setq archived (1+ archived)))))

    ;; Process creates
    (dolist (action actions)
      (when (eq (plist-get action :action) 'create)
        (let ((seg-num (plist-get action :segment-num))
              (text (plist-get action :tibetan-text)))
          (if dry-run
              (push (format "Would create: segment %d analysis" seg-num) messages)
            (when tibetan-reorg-auto-create
              (let ((auto-content (tibetan-analysis-generate-content text)))
                (tibetan-analysis-create-file seg-num text source-file auto-content))))
          (setq created (1+ created)))))

    ;; Count keeps
    (setq kept (length (cl-remove-if-not
                        (lambda (a) (eq (plist-get a :action) 'keep))
                        actions)))

    (list :renamed renamed
          :created created
          :archived archived
          :kept kept
          :messages (nreverse messages))))

;; ============================================================================
;; MAIN COMMANDS
;; ============================================================================

(defun tibetan-reorganize-analysis-files (&optional dry-run)
  "Reorganize analysis files to match current document structure.

With prefix argument DRY-RUN, only show what would be done.

This command:
1. Collects segment inventory from the document
2. Collects analysis file inventory
3. Matches files to segments by content hash
4. Renames files whose segments moved
5. Archives files for deleted segments
6. Creates files for new segments (if enabled)

Returns plist with reorganization statistics."
  (interactive "P")
  (unless (buffer-file-name)
    (error "Buffer must be saved to a file first"))

  (let* ((source-file (buffer-file-name))
         (analysis-dir (tibetan-analysis-get-folder))
         (doc-segments (tibetan-reorg--collect-document-segments))
         (file-inventory (tibetan-reorg--collect-analysis-files analysis-dir)))

    (when (= 0 (length doc-segments))
      (error "No segments found in document. Run tibetan-prepare-document first"))

    ;; Plan actions
    (let* ((actions (tibetan-reorg--plan-actions doc-segments file-inventory))
           (changes (cl-remove-if
                     (lambda (a) (eq (plist-get a :action) 'keep))
                     actions)))

      (if (= 0 (length changes))
          (progn
            (message "Analysis files are in sync with document structure")
            (list :renamed 0 :created 0 :archived 0 :kept (length actions)))

        ;; Show summary and confirm
        (let ((renames (length (cl-remove-if-not
                                (lambda (a) (eq (plist-get a :action) 'rename))
                                changes)))
              (creates (length (cl-remove-if-not
                                (lambda (a) (eq (plist-get a :action) 'create))
                                changes)))
              (orphans (length (cl-remove-if-not
                                (lambda (a) (eq (plist-get a :action) 'orphan))
                                changes))))

          (if dry-run
              ;; Dry run - just report
              (let ((result (tibetan-reorg--execute-actions
                             actions analysis-dir source-file t)))
                (with-output-to-temp-buffer "*Reorganization Preview*"
                  (princ "=== Reorganization Preview ===\n\n")
                  (princ (format "Segments in document: %d\n" (length doc-segments)))
                  (princ (format "Analysis files found: %d\n\n" (length file-inventory)))
                  (princ "Planned actions:\n")
                  (dolist (msg (plist-get result :messages))
                    (princ (format "  - %s\n" msg)))
                  (princ (format "\nSummary: %d renames, %d creates, %d archives\n"
                                 renames creates orphans))
                  (princ "\nRun without C-u prefix to execute."))
                result)

            ;; Execute for real
            (when (yes-or-no-p
                   (format "Reorganize analysis files? (%d renames, %d creates, %d archives) "
                           renames creates orphans))
              (let ((result (tibetan-reorg--execute-actions
                             actions analysis-dir source-file nil)))
                (message "Reorganization complete: %d renamed, %d created, %d archived, %d unchanged"
                         (plist-get result :renamed)
                         (plist-get result :created)
                         (plist-get result :archived)
                         (plist-get result :kept))
                result))))))))

(defun tibetan-preview-reorganization ()
  "Preview what reorganization would do without making changes."
  (interactive)
  (tibetan-reorganize-analysis-files t))

;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

(global-set-key (kbd "C-c u O") 'tibetan-reorganize-analysis-files)
(global-set-key (kbd "C-c u U") 'tibetan-preview-reorganization)

(provide 'tibetan-structure-reorg)
;;; tibetan-structure-reorg.el ends here
