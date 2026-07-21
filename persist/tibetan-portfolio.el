;;; tibetan-portfolio.el --- Portfolio-mode helpers (freeze draft) -*- lexical-binding: t -*-

;; Portfolio mode (2026-07-21).  The Tibetisch IV Portfolio assignment
;; (SoSe 2026) permits AI tools ONLY for revising a self-made
;; translation, with transparently documented changes.  Companion to the
;; `#+TIBETAN_DEFER_MT: t' header (see `tibetan-analysis--defer-mt-p'):
;; this module freezes the user's own drafts into a central revision
;; protocol BEFORE machine translation is enabled, so the protocol +
;; git history document the required before/after trail.

;;; Code:

(require 'cl-lib)

(defcustom tibetan-portfolio-protocol-file "revision-protocol.org"
  "Filename of the central revision protocol, relative to the source file
directory (an absolute path is used as-is)."
  :type 'string
  :group 'tibetan-analysis)

(defun tibetan-portfolio--protocol-path (source-file)
  "Absolute path of the revision protocol for SOURCE-FILE."
  (if (file-name-absolute-p tibetan-portfolio-protocol-file)
      tibetan-portfolio-protocol-file
    (expand-file-name tibetan-portfolio-protocol-file
                      (file-name-directory (expand-file-name source-file)))))

(defun tibetan-portfolio--collect-working-translations (source-file)
  "Collect Working Translation bodies per sentence from SOURCE-FILE.
Returns an ordered list of plists (:sent-num N :body STRING) — one per
`*** Sentence N' heading that has at least one non-empty
`**** Working Translation' body among its children.  Bodies of several
segments belonging to one sentence are joined with blank lines."
  (when (and source-file (file-exists-p source-file))
    (with-temp-buffer
      (insert-file-contents source-file)
      (goto-char (point-min))
      (let (result)
        (while (re-search-forward "^\\*\\*\\* Sentence \\([0-9]+\\)" nil t)
          (let* ((sent-num (string-to-number (match-string 1)))
                 (sent-end (save-excursion
                             (or (and (re-search-forward
                                       "^\\*\\{1,3\\} " nil t)
                                      (line-beginning-position))
                                 (point-max))))
                 bodies)
            (save-excursion
              (while (re-search-forward
                      "^\\*\\*\\*\\* Working Translation[ \t]*$" sent-end t)
                (let* ((body-start (progn (forward-line 1) (point)))
                       (body-end (or (and (re-search-forward
                                           "^\\*+ " sent-end t)
                                          (line-beginning-position))
                                     sent-end))
                       (body (string-trim
                              (buffer-substring-no-properties
                               body-start body-end))))
                  (unless (string-empty-p body)
                    (push body bodies))
                  (goto-char body-end))))
            (when bodies
              (push (list :sent-num sent-num
                          :body (mapconcat #'identity (nreverse bodies)
                                           "\n\n"))
                    result))))
        (nreverse result)))))

(defun tibetan-portfolio--frozen-p (protocol-file sent-num)
  "Non-nil when PROTOCOL-FILE already carries a frozen draft for SENT-NUM."
  (and (file-exists-p protocol-file)
       (with-temp-buffer
         (insert-file-contents protocol-file)
         (goto-char (point-min))
         (re-search-forward
          (format "^\\*\\* Own draft.*(Sentence %d)" sent-num) nil t))))

;;;###autoload
(defun tibetan-portfolio-freeze-draft (source-file)
  "Freeze SOURCE-FILE's Working Translation drafts into the protocol.

Appends, per sentence that has a non-empty draft, a timestamped
`** Own draft (frozen TIMESTAMP) (Sentence N)' block under a
`* Sentence N' heading in the revision protocol
(`tibetan-portfolio-protocol-file', created on first use).  A sentence
whose draft is ALREADY frozen is skipped — freezing is once-only per
sentence; the frozen text is the before-MT reference the assignment's
change documentation is built on.

Returns a plist (:frozen N :skipped N :protocol PATH).  Interactive
use prompts for the source file."
  (interactive
   (list (read-file-name "Source file: " nil nil t
                         (and buffer-file-name
                              (file-name-nondirectory buffer-file-name)))))
  (let* ((drafts (tibetan-portfolio--collect-working-translations
                  source-file))
         (protocol (tibetan-portfolio--protocol-path source-file))
         (stamp (format-time-string "%Y-%m-%d %H:%M"))
         (frozen 0) (skipped 0))
    (unless drafts
      (user-error "No non-empty Working Translation drafts in %s"
                  (file-name-nondirectory source-file)))
    (unless (file-exists-p protocol)
      (with-temp-buffer
        (insert "#+TITLE: Revision Protocol — "
                (file-name-nondirectory source-file) "\n"
                "#+STARTUP: showall\n\n"
                "# Own drafts are frozen here BEFORE machine translation is\n"
                "# enabled (removal of #+TIBETAN_DEFER_MT).  Per sentence:\n"
                "# Own draft (frozen) → MT versions → Final version →\n"
                "# Adopted changes with reasons.\n\n")
        (write-region (point-min) (point-max) protocol nil 'silent)))
    (dolist (d drafts)
      (let ((n (plist-get d :sent-num)))
        (if (tibetan-portfolio--frozen-p protocol n)
            (cl-incf skipped)
          (with-temp-buffer
            (insert (format "* Sentence %d\n** Own draft (frozen %s) (Sentence %d)\n%s\n\n** MT versions\n\n** Final version\n\n** Adopted changes\n\n"
                            n stamp n (plist-get d :body)))
            (append-to-file (point-min) (point-max) protocol))
          (cl-incf frozen))))
    (when (called-interactively-p 'any)
      (message "Frozen %d draft(s), %d already frozen — %s"
               frozen skipped protocol))
    (list :frozen frozen :skipped skipped :protocol protocol)))

(provide 'tibetan-portfolio)
;;; tibetan-portfolio.el ends here
