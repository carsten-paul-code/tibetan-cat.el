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
;; Entry creation — new thesaurus zettels from Wylie + optional scaffolding
;; ---------------------------------------------------------------------------

(defun tibetan-thesaurus--slugify-wylie (wylie)
  "Turn WYLIE into a filename-safe slug.
Spaces become `-', apostrophes are dropped, anything outside
`[a-z0-9-]' is replaced with `-'.  Multi-dash runs collapse to
one.  Empty input returns the literal `entry' so the caller still
gets a valid filename component."
  (if (or (null wylie) (string-empty-p (string-trim wylie)))
      "entry"
    (let* ((s (downcase (string-trim wylie)))
           (s (replace-regexp-in-string "[' \t]+" "-" s))
           (s (replace-regexp-in-string "[^a-z0-9-]" "" s))
           (s (replace-regexp-in-string "-+" "-" s))
           (s (replace-regexp-in-string "\\`-\\|-\\'" "" s)))
      (if (string-empty-p s) "entry" s))))

(cl-defun tibetan-thesaurus-new-entry
    (wylie &key sanskrit english german)
  "Create a new thesaurus zettel for WYLIE and return its absolute path.
Optional fields prefill the scaffold:
  :sanskrit — `#+title:' and `** Sanskrit / - Term:' values
  :english  — `** English / - Primary translation:'
  :german   — `** German / - Primary translation:'

Placement: `tibetan-thesaurus-directory' / TIMESTAMP--WYLIE__user.org
where TIMESTAMP is the current time in Denote's `%Y%m%dT%H%M%S'
shape and WYLIE is the Wylie slugified via `--slugify-wylie'.
The `:ID:' property equals TIMESTAMP so org's `id:' link scheme
resolves cleanly.

Errors:
  · `tibetan-thesaurus-directory' unset  → user-error.
  · File already exists                  → user-error (never
    overwrites existing content; a rare timestamp collision
    on the same second means the user should retry).

Side-effect: the cached thesaurus index is invalidated so the
next `tibetan-thesaurus-lookup' sees the new entry without a
manual `tibetan-thesaurus-reload'."
  (unless tibetan-thesaurus-directory
    (user-error
     "`tibetan-thesaurus-directory' is not set — configure it first"))
  (unless (file-directory-p tibetan-thesaurus-directory)
    (make-directory tibetan-thesaurus-directory t))
  (let* ((timestamp (format-time-string "%Y%m%dT%H%M%S"))
         (slug (tibetan-thesaurus--slugify-wylie wylie))
         (filename (format "%s--%s__user.org" timestamp slug))
         (path (expand-file-name filename tibetan-thesaurus-directory))
         (title (or (and sanskrit (string-trim sanskrit)) (string-trim wylie)))
         (en (or english "[to be researched]"))
         (de (or german  "[to be added]"))
         (skt (or sanskrit "[to be added]")))
    (when (file-exists-p path)
      (user-error "Thesaurus file already exists: %s" path))
    (with-temp-file path
      (insert ":PROPERTIES:\n"
              (format ":ID: %s\n" timestamp)
              ":END:\n"
              (format "#+title: %s\n" title)
              (format "#+date: [%s]\n" (format-time-string "%Y-%m-%d"))
              "#+filetags: :thesaurus:user:\n\n"
              "* Multilingual Terms\n"
              "** Sanskrit\n"
              (format "- Term: %s\n" skt)
              (format "- IAST: %s\n" skt)
              "- Etymology: [to be researched]\n\n"
              "** Tibetan\n"
              "- Term: [Tibetan script to be added]\n"
              (format "- Wylie: %s\n" (string-trim wylie))
              "- Phonetic: [to be added]\n"
              "- Etymology: [to be researched]\n\n"
              "** English\n"
              (format "- Primary translation: %s\n" en)
              "- Alternative translations: [to be researched]\n\n"
              "** German\n"
              (format "- Primary translation: %s\n" de)
              "- Alternative translations: [to be researched]\n\n"
              "* Definition\n"
              "** Brief Definition\n[To be developed]\n\n"
              "** Extended Definition\n[To be developed]\n\n"
              "* Notes and Commentary\n"
              "[Entry created via `tibetan-thesaurus-new-entry'.]\n"))
    ;; Invalidate cache so the new zettel is visible to the next lookup.
    (tibetan-thesaurus-reload)
    path))

;;;###autoload
(defun tibetan-thesaurus-new-entry-interactively ()
  "Prompt for a Wylie term and create a new thesaurus zettel.
Thin interactive wrapper around `tibetan-thesaurus-new-entry'.
Uses the Wylie on the current line (when available via
`--wylie-at-point') as the default, so in an analysis buffer
the user can `C-c u z n RET' to create an entry for the term
the cursor is already on."
  (interactive)
  (let* ((default (tibetan-thesaurus--wylie-at-point))
         (wylie (read-string
                 (if default
                     (format "Wylie for new thesaurus entry (default %s): "
                             default)
                   "Wylie for new thesaurus entry: ")
                 nil nil default)))
    (when (and wylie (not (string-empty-p wylie)))
      (let ((path (tibetan-thesaurus-new-entry wylie)))
        (find-file path)
        (message "Created thesaurus entry: %s" path)))))

;; ---------------------------------------------------------------------------
;; edit-at-point — resolve the Wylie of the word at point in an analysis buffer
;; ---------------------------------------------------------------------------

(defun tibetan-thesaurus--wylie-at-point ()
  "Return the Wylie string visible on the current line, or nil.

Looks for a `[WYLIE]' token bounded by square brackets — the
convention used by the Detailed Dictionary head line (`◆ TIBETAN
[mthu] ★ …') and the Interlinear Gloss (`[[term-mthu][mthu]] …').
Multi-word Wylie inside a single bracket pair (e.g. `rnam par
shes pa') is returned whole.

Returns nil when the current line has no `[...]' match — the
caller can then prompt the user for a Wylie interactively."
  (save-excursion
    (beginning-of-line)
    (let ((line-end (line-end-position))
          ;; Case-SENSITIVE matching is essential: the meta-token
          ;; filter below uses `[A-Z]+' to reject uppercase-only
          ;; labels like `[GEN]' / `[TERM]' / `[CASE]'.  Without
          ;; binding `case-fold-search' to nil, Emacs's default
          ;; case-insensitive regex would match lowercase Wylie
          ;; strings like `mthu' against `[A-Z]+' and we'd filter
          ;; out the one we actually want.
          (case-fold-search nil))
      ;; Scan for the first `[XXX]' on the line where XXX is Wylie-like
      ;; (lowercase letters, apostrophes, spaces, digits).  The org-link
      ;; pattern `[[url][label]]' has letters outside the brackets; our
      ;; regex is anchored to `[' followed by Wylie-shaped content.
      (when (re-search-forward
             "\\[\\([-a-z0-9' ]+\\)\\]" line-end t)
        (let ((match (string-trim (match-string 1))))
          ;; Exclude meta-tokens like [GEN], [TERM], [CASE], [Requesting...]
          (unless (or (string-match-p "\\`[A-Z]+\\'" match)
                      (string-match-p "\\`\\[" match))
            match))))))

;;;###autoload
(defun tibetan-thesaurus-edit-at-point ()
  "Open the thesaurus zettel for the Wylie term on the current line.
When multiple zettels are indexed for the same Wylie key, prompt
the user to pick one.  When no entry exists, offer to create a
new one via `tibetan-thesaurus-new-entry'.

Falls back to prompting the user for a Wylie when the current
line has no bracketed token."
  (interactive)
  (let* ((from-buffer (tibetan-thesaurus--wylie-at-point))
         (wylie (or from-buffer
                    (read-string "Wylie term: "))))
    (when (and wylie (not (string-empty-p wylie)))
      (let* ((hits (tibetan-thesaurus-lookup wylie))
             (entry
              (cond
               ((null hits)
                (if (yes-or-no-p
                     (format "No thesaurus entry for `%s'.  Create one? "
                             wylie))
                    (let ((new-path (tibetan-thesaurus-new-entry wylie)))
                      (list :path new-path))
                  nil))
               ((= 1 (length hits)) (car hits))
               (t
                (let* ((choices
                        (mapcar (lambda (h)
                                  (cons (format "%s — %s"
                                                (or (plist-get h :sanskrit) "?")
                                                (or (plist-get h :primary-en) ""))
                                        h))
                                hits))
                       (pick (completing-read
                              "Pick thesaurus entry: "
                              (mapcar #'car choices) nil t)))
                  (cdr (assoc pick choices)))))))
        (when entry
          (find-file (plist-get entry :path)))))))

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

;; ---------------------------------------------------------------------------
;; Pass 5d — cross-document consistency audit
;; ---------------------------------------------------------------------------
;;
;; Problem: when the user edits a thesaurus zettel (changes an English
;; gloss, corrects a Sanskrit, splits a sense), every existing analysis
;; file that referenced the term was generated AGAINST the pre-edit
;; state.  Its Interlinear / CAT Gloss / Word List output is now out of
;; sync with the thesaurus.  A blind batch reanalysis of the folder
;; works but burns Claude API tokens on the ~95% of analyses that
;; weren't affected by the edit.
;;
;; Two tools here:
;;   · `tibetan-thesaurus-audit-folder' — list analyses whose
;;     LAST_ANALYZED date predates the mtime of a thesaurus zettel
;;     for a term the analysis's Tibetan Text contains.
;;   · `tibetan-thesaurus-segments-affected-by-zettel' — for a
;;     specific zettel, find every analysis whose Tibetan Text
;;     contains its Wylie key.  Feeds a targeted rerun command.

(defun tibetan-thesaurus--parse-last-analyzed (analysis-file)
  "Return the `#+LAST_ANALYZED:' date as an Emacs time value, or nil.
Date format expected: `YYYY-MM-DD' (what
`tibetan-analysis-create-file' writes).  Returns nil on malformed
or missing header so callers can decide the fallback."
  (when (and analysis-file (file-readable-p analysis-file))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (goto-char (point-min))
      (when (re-search-forward
             "^#\\+LAST_ANALYZED:[ \t]*\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)"
             nil t)
        (condition-case nil
            (date-to-time (concat (match-string 1) "T00:00:00"))
          (error nil))))))

(defun tibetan-thesaurus--tibetan-text-of (analysis-file)
  "Return the body of the `* Tibetan Text' section of ANALYSIS-FILE,
or an empty string.  Used by audit/affected queries to scan
segment content for Wylie matches."
  (if (and analysis-file (file-readable-p analysis-file))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (goto-char (point-min))
        (if (re-search-forward "^\\* Tibetan Text[ \t]*\n" nil t)
            (let ((start (point))
                  (end (save-excursion
                         (if (re-search-forward "^\\* " nil t)
                             (line-beginning-position)
                           (point-max)))))
              (string-trim (buffer-substring-no-properties start end)))
          ""))
    ""))

(defun tibetan-thesaurus--wylie-mentioned-p (wylie text)
  "Return non-nil if WYLIE appears as a word-boundary token in TEXT.
Matching is word-boundary-safe so a zettel for `mthu' doesn't
spuriously claim a segment containing `mthun' / `mthuri'.  The
bounds are defined via `\\b' — so for Wylie strings containing
spaces (`rnam par shes pa'), each segment of the Wylie must be
individually word-bounded.  Simpler heuristic: look for WYLIE
surrounded by non-word chars or line edges.

Uses case-sensitive matching so `DE' in metadata doesn't match
`de' in Wylie."
  (when (and wylie text (not (string-empty-p wylie)) (not (string-empty-p text)))
    (let ((case-fold-search nil)
          ;; Tibetan Wylie transcription routinely converts the syllable
          ;; separator `་' to a space, so the analysis file's Tibetan
          ;; Text section in Wylie form mirrors the thesaurus key
          ;; verbatim.  Build a regex that allows the Tibetan-text
          ;; spellings with or without trailing `་' and with either
          ;; space or tsheg between syllables.
          (flex-wylie (replace-regexp-in-string
                       " +" "[ ་]+" (regexp-quote wylie))))
      ;; Anchored left edge: start-of-buffer OR non-word char.
      ;; Anchored right edge: end-of-buffer OR non-word char.
      (string-match-p
       (concat "\\(?:\\`\\|[^-a-z0-9']\\)"
               flex-wylie
               "\\(?:\\'\\|[^-a-z0-9']\\)")
       text))))

(defun tibetan-thesaurus-segments-affected-by-zettel (zettel-path analysis-dir)
  "Return the list of analysis files under ANALYSIS-DIR whose
Tibetan Text contains the Wylie key of the thesaurus ZETTEL-PATH.

Drives `tibetan-thesaurus-rerun-affected' — after editing one
zettel, this finds exactly the segments that need re-analysis
and leaves the rest untouched.

When ZETTEL-PATH is unreadable or has no `- Wylie:' field, or
ANALYSIS-DIR doesn't exist, returns nil."
  (let* ((entry (tibetan-thesaurus--parse-file zettel-path))
         (wylie (and entry (plist-get entry :wylie))))
    (when (and wylie
               (file-directory-p (or analysis-dir "")))
      (let ((files (directory-files
                    analysis-dir t "\\`seg-[0-9]+.*\\.org\\'"))
            (affected '()))
        (dolist (f files)
          (let ((text (tibetan-thesaurus--tibetan-text-of f)))
            (when (tibetan-thesaurus--wylie-mentioned-p wylie text)
              (push f affected))))
        (nreverse affected)))))

;;;###autoload
(defun tibetan-thesaurus-audit-folder (analysis-dir)
  "Scan ANALYSIS-DIR for analysis files whose last-analyzed date
predates a thesaurus zettel's modification time for a term that
appears in the analysis's Tibetan Text.  Return a list of plists:

  (:analysis-file PATH
   :stale-terms    (WYLIE1 WYLIE2 ...)
   :zettel-paths   (Z1 Z2 ...))

Each item flags one analysis as stale and names the Wylie terms
whose thesaurus entries post-date it.  An empty list means every
analysis in the folder is up-to-date with the current thesaurus.

Returns nil when no thesaurus is configured — without an index
there's nothing to compare against.

Interactive callers use `tibetan-thesaurus-audit-folder-display'
(below) to open a formatted results buffer; this function is
the data-only core."
  (when (and tibetan-thesaurus-directory
             (file-directory-p (or analysis-dir "")))
    (let ((index (tibetan-thesaurus--ensure-index))
          (stale '()))
      (when (and index (> (hash-table-count index) 0))
        (let ((files (directory-files
                      analysis-dir t "\\`seg-[0-9]+.*\\.org\\'")))
          (dolist (f files)
            (let* ((analyzed-time (tibetan-thesaurus--parse-last-analyzed f))
                   (text (tibetan-thesaurus--tibetan-text-of f))
                   (stale-terms '())
                   (stale-zettels '()))
              (when (and analyzed-time text (not (string-empty-p text)))
                (maphash
                 (lambda (wylie entries)
                   (when (tibetan-thesaurus--wylie-mentioned-p wylie text)
                     (dolist (entry entries)
                       (let* ((path (plist-get entry :path))
                              (mtime (and path
                                          (file-exists-p path)
                                          (file-attribute-modification-time
                                           (file-attributes path)))))
                         (when (and mtime
                                    (time-less-p analyzed-time mtime))
                           (cl-pushnew wylie stale-terms :test #'equal)
                           (cl-pushnew path stale-zettels :test #'equal))))))
                 index)
                (when stale-terms
                  (push (list :analysis-file f
                              :stale-terms (nreverse stale-terms)
                              :zettel-paths (nreverse stale-zettels))
                        stale)))))))
      (nreverse stale))))

;;;###autoload
(defun tibetan-thesaurus-rerun-affected-by-zettel (zettel-path analysis-dir)
  "Re-analyse every segment under ANALYSIS-DIR whose Tibetan Text
contains the Wylie key of ZETTEL-PATH.  Preserves Claude sections
(`:re-request-claude nil') — only the parser-side output is
refreshed from the new thesaurus gloss.  Returns the list of
re-analysed file paths.

Typical use: after editing a thesaurus zettel to correct a gloss,
  M-x tibetan-thesaurus-rerun-affected-by-zettel
gets every analysis that mentions the term picking up the new
rendering without blindly batch-regenerating the whole folder."
  (interactive
   (list (read-file-name "Thesaurus zettel: "
                         tibetan-thesaurus-directory nil t)
         (read-directory-name "Analysis folder: ")))
  (unless (fboundp 'tibetan-analysis-reanalyze-file)
    (user-error "`tibetan-analysis-reanalyze-file' not available"))
  (let* ((affected (tibetan-thesaurus-segments-affected-by-zettel
                    zettel-path analysis-dir))
         (n (length affected))
         (i 0)
         (done '()))
    (when (called-interactively-p 'any)
      (message "Re-analysing %d segment(s) affected by %s"
               n (file-name-nondirectory zettel-path)))
    (dolist (f affected)
      (cl-incf i)
      (when (called-interactively-p 'any)
        (message "[%d/%d] %s" i n (file-name-nondirectory f)))
      (condition-case err
          (progn
            (tibetan-analysis-reanalyze-file f :re-request-claude nil)
            (push f done))
        (error
         (message "Rerun failed for %s: %s"
                  (file-name-nondirectory f)
                  (error-message-string err)))))
    (when (called-interactively-p 'any)
      (message "Thesaurus rerun complete: %d/%d succeeded"
               (length done) n))
    (nreverse done)))

;;;###autoload
(defun tibetan-thesaurus-audit-folder-display (analysis-dir)
  "Interactive wrapper around `tibetan-thesaurus-audit-folder' that
opens a formatted *Thesaurus Audit* buffer listing every stale
analysis and the Wylie terms that triggered the flag.  Users
invoke this after a thesaurus editing session to see the
surface area of the change."
  (interactive
   (list (read-directory-name "Analysis folder to audit: ")))
  (let ((stale (tibetan-thesaurus-audit-folder analysis-dir))
        (buf (get-buffer-create "*Thesaurus Audit*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (format "Thesaurus audit — %s\n\n" analysis-dir))
      (if (null stale)
          (insert "All analyses are up-to-date with the current thesaurus.\n")
        (insert (format "%d stale analysis file(s):\n\n"
                        (length stale)))
        (dolist (item stale)
          (insert (format "  %s\n"
                          (file-name-nondirectory
                           (plist-get item :analysis-file))))
          (insert (format "    stale terms: %s\n"
                          (mapconcat #'identity
                                     (plist-get item :stale-terms)
                                     ", ")))
          (insert "\n"))
        (insert "\nTo refresh one analysis: M-x tibetan-analysis-reanalyze-file\n")
        (insert "To refresh every analysis for one zettel: \n")
        (insert "  M-x tibetan-thesaurus-rerun-affected-by-zettel\n"))
      (read-only-mode 1)
      (goto-char (point-min)))
    (display-buffer buf)
    stale))

(provide 'tibetan-thesaurus)
;;; tibetan-thesaurus.el ends here
