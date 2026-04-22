;;; tibetan-thesaurus.el --- User-editable multilingual thesaurus -*- lexical-binding: t -*-

;;; Commentary:
;; Pass 5b: a user-editable glossary of multilingual Buddhist-studies
;; terms stored as org-mode zettels (one file per term).  Each zettel
;; carries a Sanskrit term, its Wylie transliteration, English primary
;; translation, and German primary translation — plus notes, etymology,
;; and references that the user expands over time.
;;
;; The thesaurus seeds from Jowita Kramer's Yogācāra glossary (342
;; entries) via `tibetan-thesaurus-initialize-from-kramer', then
;; becomes the authoritative source for the user's own translation
;; work — consistent across every analysis file in a document and
;; across related documents.
;;
;; Integration: `tibetan-thesaurus-lookup' is called by
;; `tibetan-vocab-multisource-entries' (`core/tibetan-vocabulary-
;; detailed.el') at rank 1 — thesaurus hits win over Resources (2),
;; corpus-specific Steinert (3), Hopkins (4), RY (6), and everything
;; below.  The student's chosen rendering surfaces in the Interlinear
;; Gloss and the Detailed Dictionary automatically.
;;
;; File format — a zettel zettel is a vanilla org-roam / Denote-style
;; org file with the following keys parsed by `-parse-file':
;;
;;   :PROPERTIES:
;;   :ID: 20250821T100000      ← org ID, used for back-link from analysis
;;   :END:
;;   #+title: citta            ← Sanskrit term (also used as :sanskrit)
;;
;;   ** Tibetan
;;   - Wylie: sems             ← THESAURUS KEY (what lookup matches on)
;;
;;   ** English
;;   - Primary translation: mind, consciousness
;;
;;   ** German
;;   - Primary translation: Geist
;;
;; Placeholder fields (`[to be added]', `[to be researched]') are
;; returned as nil so renderers can skip them cleanly.  A zettel
;; without a Wylie field is silently skipped from the index — no
;; crash, no corruption.

;;; Code:

(require 'cl-lib)

;; ---------------------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------------------

(defgroup tibetan-thesaurus nil
  "User-editable multilingual thesaurus for Tibetan translation work."
  :group 'tibetan-cat)

(defcustom tibetan-thesaurus-directory nil
  "Directory where the user's thesaurus zettels live.
Each `*.org' file under this directory is a single term entry in
the format described in the module commentary.  Set this to your
thesaurus location — typically a subdir of your Buddhist-studies
zettelkasten, separate from the original Kramer glossary source.

When nil or unset, `tibetan-thesaurus-lookup' returns nil for
every query and the multisource framework silently falls through
to the next-ranked source (Resources / Steinert / etc.)."
  :type '(choice (const :tag "No thesaurus configured" nil)
                 (directory :tag "Thesaurus directory"))
  :group 'tibetan-thesaurus)

(defcustom tibetan-thesaurus-file-pattern "*.org"
  "Glob pattern under `tibetan-thesaurus-directory' that matches
individual thesaurus zettel files.  Default `*.org' picks up every
org file in the directory."
  :type 'string
  :group 'tibetan-thesaurus)

(defcustom tibetan-thesaurus-kramer-source-directory nil
  "Source directory holding Jowita Kramer's Yogācāra glossary
zettels (seed for `tibetan-thesaurus-directory').  Used ONLY by
the one-shot `tibetan-thesaurus-initialize-from-kramer' command
to copy the Kramer files into a fresh thesaurus directory.  After
initialisation the thesaurus is the user's own — Kramer stays
intact at this path for reference.

This directory typically sits inside a larger zettelkasten holding
many non-Kramer files, so the copy step filters by
`tibetan-thesaurus-kramer-source-pattern' (default
`*kramer-glossary*.org') to avoid pulling in unrelated zettels."
  :type '(choice (const nil) directory)
  :group 'tibetan-thesaurus)

(defcustom tibetan-thesaurus-kramer-source-pattern "*kramer-glossary*.org"
  "Glob pattern matching Kramer-glossary zettel files inside
`tibetan-thesaurus-kramer-source-directory'.  Only files matching
this pattern are copied by
`tibetan-thesaurus-initialize-from-kramer'.  The default
`*kramer-glossary*.org' matches the filename convention of
Carsten's 342-entry Kramer zettel set while leaving the rest of
his zettelkasten untouched."
  :type 'string
  :group 'tibetan-thesaurus)

;; ---------------------------------------------------------------------------
;; Parser — single file → plist
;; ---------------------------------------------------------------------------

(defun tibetan-thesaurus--first-match (regexp)
  "Return the first `\\1' group match of REGEXP in the current buffer,
or nil if no match.  Search is from `point-min' forward; caller
guards buffer state."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward regexp nil t)
      (let ((m (match-string 1)))
        (and m (string-trim m))))))

(defun tibetan-thesaurus--placeholder-p (s)
  "Return non-nil if S looks like a Kramer placeholder field.
Placeholders are bracketed hints like `[to be added]', `[to be
researched]', or `[TBD]' — the parser treats them as unset."
  (and s (string-match-p "\\`\\[.*\\]\\'" (string-trim s))))

(defun tibetan-thesaurus--clean-value (s)
  "Return S trimmed, or nil if S is empty / placeholder."
  (cond
   ((null s) nil)
   ((tibetan-thesaurus--placeholder-p s) nil)
   ((string-empty-p (string-trim s)) nil)
   (t (string-trim s))))

(defun tibetan-thesaurus--parse-file (path)
  "Parse a thesaurus zettel at PATH into a plist, or return nil.

Returned plist keys:
  :id         — org ID string (from the `:ID:' property).
  :sanskrit   — Sanskrit term (from `#+title:'; the zettel's title
                also serves as the filename-style Sanskrit lemma).
  :wylie      — Wylie transliteration (from `- Wylie: ...' under
                the `** Tibetan' sub-heading).  This is the KEY
                the thesaurus indexes on.
  :primary-en — English primary translation (or nil if placeholder).
  :primary-de — German primary translation  (or nil if placeholder).
  :path       — absolute file path, used by editing commands.

Returns nil when PATH doesn't exist or has no `Wylie:' field —
the latter signals a malformed / stub zettel that should be
skipped from the index rather than crashing the indexer."
  (when (and path (file-readable-p path))
    (with-temp-buffer
      (insert-file-contents path)
      (let* ((id       (tibetan-thesaurus--first-match
                        "^:ID:[ \t]*\\(.+?\\)[ \t]*$"))
             (title    (tibetan-thesaurus--first-match
                        "^#\\+title:[ \t]*\\(.+?\\)[ \t]*$"))
             (wylie-raw (tibetan-thesaurus--first-match
                         "^[ \t]*-[ \t]*Wylie:[ \t]*\\(.+?\\)[ \t]*$"))
             (wylie    (tibetan-thesaurus--clean-value wylie-raw))
             (primary-en (tibetan-thesaurus--clean-value
                          (tibetan-thesaurus--extract-field
                           "English" "Primary translation")))
             (primary-de (tibetan-thesaurus--clean-value
                          (tibetan-thesaurus--extract-field
                           "German" "Primary translation")))
             (sanskrit (tibetan-thesaurus--clean-value title)))
        ;; Skip zettels without a Wylie key — can't index them.
        (when wylie
          (list :id         id
                :sanskrit   sanskrit
                :wylie      wylie
                :primary-en primary-en
                :primary-de primary-de
                :path       path))))))

(defun tibetan-thesaurus--extract-field (section-title field-label)
  "Return the FIELD-LABEL value inside the `** SECTION-TITLE' heading
of the current buffer, or nil.  E.g.
  SECTION-TITLE = \"English\", FIELD-LABEL = \"Primary translation\"
looks for:
  `** English' … `- Primary translation: <value>'
and returns <value>.  The search is bounded to the next level-2
heading so `- Primary translation:' lines in later sections don't
bleed into the result."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^\\*\\* %s[ \t]*$" (regexp-quote section-title))
           nil t)
      (let ((section-end (save-excursion
                           (if (re-search-forward "^\\*\\* " nil t)
                               (line-beginning-position)
                             (point-max)))))
        (when (re-search-forward
               (format "^[ \t]*-[ \t]*%s:[ \t]*\\(.+?\\)[ \t]*$"
                       (regexp-quote field-label))
               section-end t)
          (match-string 1))))))

;; ---------------------------------------------------------------------------
;; Indexer
;; ---------------------------------------------------------------------------

(defun tibetan-thesaurus--build-index (&optional dir)
  "Walk DIR (default: `tibetan-thesaurus-directory'), parse every
matching zettel, and return a hash keyed by Wylie string.

Values are LISTS of entry plists — the same Wylie can appear in
multiple zettels when the user wants to document distinct senses
or sources for the term.

Missing / unreadable directory → empty hash (not nil) so callers
can iterate safely in either state."
  (let ((table (make-hash-table :test 'equal))
        (target-dir (or dir tibetan-thesaurus-directory)))
    (when (and target-dir (file-directory-p target-dir))
      (let ((files (directory-files target-dir t
                                    (wildcard-to-regexp
                                     (or tibetan-thesaurus-file-pattern
                                         "*.org")))))
        (dolist (path files)
          (let ((entry (condition-case nil
                           (tibetan-thesaurus--parse-file path)
                         (error nil))))
            (when entry
              (let* ((k (plist-get entry :wylie))
                     (existing (gethash k table)))
                (puthash k (append existing (list entry)) table)))))))
    table))

;; ---------------------------------------------------------------------------
;; Cached lookup (public API)
;; ---------------------------------------------------------------------------

(defvar tibetan-thesaurus--index nil
  "Cached thesaurus index (hash, Wylie → list of entry plists).
Built lazily by `tibetan-thesaurus--ensure-index'; invalidated by
`tibetan-thesaurus-reload' when the user edits entries or changes
`tibetan-thesaurus-directory'.")

(defvar tibetan-thesaurus--index-dir nil
  "Directory the cached index was built from.  When
`tibetan-thesaurus-directory' changes (or any zettel file's mtime
postdates the cache), a re-index is triggered.")

(defvar tibetan-thesaurus--index-build-time nil
  "`current-time' value at which the cache was populated, used for
mtime-based invalidation.  A future refinement can compare this
against individual file modification stamps.")

(defun tibetan-thesaurus--ensure-index ()
  "Return the thesaurus index, building / rebuilding as needed."
  (unless (and tibetan-thesaurus--index
               (equal tibetan-thesaurus--index-dir
                      tibetan-thesaurus-directory))
    (setq tibetan-thesaurus--index
          (tibetan-thesaurus--build-index tibetan-thesaurus-directory))
    (setq tibetan-thesaurus--index-dir tibetan-thesaurus-directory)
    (setq tibetan-thesaurus--index-build-time (current-time)))
  tibetan-thesaurus--index)

(defun tibetan-thesaurus-reload ()
  "Clear the cached thesaurus index.  The next `tibetan-thesaurus-
lookup' call rebuilds it from disk.  Call this after editing a
zettel in the thesaurus directory or changing the directory path."
  (interactive)
  (setq tibetan-thesaurus--index nil)
  (setq tibetan-thesaurus--index-dir nil)
  (setq tibetan-thesaurus--index-build-time nil)
  (when (called-interactively-p 'any)
    (message "Thesaurus index cleared — rebuilt on next lookup.")))

(defun tibetan-thesaurus-lookup (wylie)
  "Return a list of thesaurus entries matching the WYLIE key.
Each entry is a plist as documented on
`tibetan-thesaurus--parse-file'.  When no thesaurus is configured
or no match exists, returns nil — the multisource framework then
falls through to the next-ranked source silently."
  (when (and wylie (stringp wylie)
             tibetan-thesaurus-directory)
    (let* ((clean (string-trim wylie))
           (index (tibetan-thesaurus--ensure-index)))
      (and index (gethash clean index)))))

;; ---------------------------------------------------------------------------
;; One-shot initialization — copy Kramer zettels into the user's thesaurus
;; ---------------------------------------------------------------------------

;;;###autoload
(defun tibetan-thesaurus-initialize-from-kramer ()
  "Seed `tibetan-thesaurus-directory' from the Kramer glossary.
Copies every `*.org' file under
`tibetan-thesaurus-kramer-source-directory' into
`tibetan-thesaurus-directory', preserving the original Kramer
source intact.  Destination files that ALREADY EXIST are skipped
— a user who has started editing their thesaurus will never lose
their work on a second init call.

Both paths must be configured in advance via
`M-x customize-group RET tibetan-thesaurus'; missing config
raises a user-error with guidance.

Returns a plist `(:copied N :skipped-existing M :source SRC-DIR
:dest DEST-DIR)' summarising the run."
  (interactive)
  (unless tibetan-thesaurus-kramer-source-directory
    (user-error
     "`tibetan-thesaurus-kramer-source-directory' is not set — \
point it at the directory holding `*kramer-glossary*.org' files"))
  (unless tibetan-thesaurus-directory
    (user-error
     "`tibetan-thesaurus-directory' is not set — point it at the \
destination thesaurus directory (created if absent)"))
  (unless (file-directory-p tibetan-thesaurus-kramer-source-directory)
    (user-error "Kramer source dir does not exist: %s"
                tibetan-thesaurus-kramer-source-directory))
  ;; Ensure destination exists.
  (unless (file-directory-p tibetan-thesaurus-directory)
    (make-directory tibetan-thesaurus-directory t))
  (let* ((src tibetan-thesaurus-kramer-source-directory)
         (dest tibetan-thesaurus-directory)
         ;; Filter source files by the Kramer-specific pattern so
         ;; non-Kramer zettels sharing the directory aren't copied.
         (sources (directory-files
                   src t
                   (wildcard-to-regexp
                    tibetan-thesaurus-kramer-source-pattern)))
         (copied 0)
         (skipped 0))
    (dolist (path sources)
      (let* ((name (file-name-nondirectory path))
             (target (expand-file-name name dest)))
        (cond
         ((file-exists-p target)
          ;; User may have edited this entry — skip.
          (setq skipped (1+ skipped)))
         (t
          (copy-file path target)
          (setq copied (1+ copied))))))
    ;; Invalidate cache so the next lookup picks up the newly-seeded
    ;; directory without requiring an explicit reload.
    (tibetan-thesaurus-reload)
    (when (called-interactively-p 'any)
      (message "Thesaurus initialised: %d copied, %d skipped (existing) — %s"
               copied skipped dest))
    (list :copied copied
          :skipped-existing skipped
          :source src
          :dest dest)))

(provide 'tibetan-thesaurus)
;;; tibetan-thesaurus.el ends here
