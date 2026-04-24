;;; tibetan-zettel.el --- Zettel integration for Tibetan translation workflow -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Phase 1 of the zettel-in-translation-workflow feature (v1 design
;; approved 2026-04-24; see `docs/feature-zettel-workflow.org' for the
;; full spec).
;;
;; This module builds and queries an index of translation-relevant
;; zettels in `tibetan-zettel-directory' (defaults to the post-reorg
;; ~/buddhist-studies/knowledge/zettelkasten/).
;;
;; A zettel is "translation-relevant" when at least one of:
;;
;;   (a) its Denote filename carries the `__glossar' tag, OR
;;   (b) its org PROPERTIES drawer has a `:wylie:' field.
;;
;; This is the first of seven phases; later phases (see the design
;; doc) wire the index into the Interlinear renderer (Phase 2),
;; auto-create zettels for <term>-tagged Buddhist concepts (Phase
;; 3), cache Claude explanations in zettels (Phases 4–5), and
;; migrate legacy Pass-5b Thesaurus zettels (Phase 6).
;;
;; Phase 1 deliverables: index + reader + lookup.  NO integration
;; with the multisource ranker yet (that's Phase 2).
;;
;; Schemas supported:
;;
;; v2 (canonical post-2026-04-24):
;;   :PROPERTIES:
;;   :ID:       <org-id>
;;   :wylie:    <lowercase Wylie, trimmed>
;;   :script:   <Tibetan script>
;;   :sanskrit: <Skt if one-to-one; optional>
;;   :preferred-de: <user-curated German; empty or [to be researched]>
;;   :preferred-en: <user-curated English; may auto-populate from 84000>
;;   :steinert-84000: yes     ; optional flag
;;   :claude-cached: YYYY-MM-DD ; optional
;;   :END:
;;
;; v1 (Pass-5b Kramer-format, for back-compat during Phase 1–5):
;;   #+title: <Sanskrit>
;;   ** Tibetan
;;   - Wylie: <wylie>
;;   ** English
;;   - Primary translation: <en>
;;   ** German
;;   - Primary translation: <de>
;;
;; Both schemas produce the same plist shape on parse:
;;
;;   (:id :path :wylie :script :sanskrit
;;    :preferred-de :preferred-de-placeholder-p
;;    :preferred-en :preferred-en-placeholder-p
;;    :steinert-84000 :claude-cached-p)

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; Configuration
;; ============================================================================

(defgroup tibetan-zettel nil
  "Integration of the zettelkasten into the CAT translation workflow."
  :group 'tibetan-cat
  :prefix "tibetan-zettel-")

(defcustom tibetan-zettel-directory
  "~/buddhist-studies/knowledge/zettelkasten/"
  "Directory holding the zettelkasten's translation-relevant zettels.
Default points at the post-reorg location (2026-04-24); older
configurations with the bare `~/buddhist-studies/zettelkasten/'
path should update after the buddhist-studies reorg.

The indexer walks this directory recursively, parses each .org
file passing `tibetan-zettel--translation-relevant-p', and keys
entries on their `:wylie:' field (or `- Wylie:' for legacy
Pass-5b zettels)."
  :type 'directory
  :group 'tibetan-zettel)

;; ============================================================================
;; File classification
;; ============================================================================

(defconst tibetan-zettel--glossar-tag-re
  "__glossar\\(__\\|\\.org\\'\\)"
  "Regex matching the Denote `__glossar' file tag.
The trailing alternation (`__' or `.org' end-anchor) prevents
`__glossary' / `__glossar-archive' from matching as the exact tag.")

(defun tibetan-zettel--glossar-tagged-p (path)
  "Return non-nil when PATH's filename carries the Denote `__glossar' tag.
Checks the filename base (with extension); matches the tag in
any position of the Denote tag chain — first (`...__glossar.org'),
middle (`...__glossar__buddhist-term.org'), or last."
  (when (and path (stringp path))
    (string-match-p tibetan-zettel--glossar-tag-re
                    (file-name-nondirectory path))))

(defconst tibetan-zettel--wylie-property-re
  "^[ \t]*:wylie:[ \t]+\\(\\S-.*?\\)[ \t]*$"
  "Regex matching a `:wylie: VALUE' property line.
Leading whitespace tolerated (org's PROPERTIES drawers indent);
trailing whitespace trimmed by the capture group's `.*?'.")

(defun tibetan-zettel--has-wylie-property-p (content)
  "Return non-nil when CONTENT has a `:wylie:' property with a value.
CONTENT is a string (typically the first N bytes of a zettel file).
A bare `:wylie:' line with no value does NOT count — we need the
lookup key."
  (and content (stringp content)
       (string-match-p tibetan-zettel--wylie-property-re content)))

(defun tibetan-zettel--translation-relevant-p (path)
  "Return non-nil when PATH is a translation-relevant zettel.
Detection: `__glossar' filename tag OR `:wylie:' property (OR
semantics).  Reads only the first 4096 bytes of the file for the
property check so huge files don't pathologically slow the
indexer."
  (when (and path (file-readable-p path))
    (or (tibetan-zettel--glossar-tagged-p path)
        (with-temp-buffer
          (insert-file-contents path nil 0 4096)
          (tibetan-zettel--has-wylie-property-p (buffer-string))))))

;; ============================================================================
;; Property & field extraction helpers
;; ============================================================================

(defun tibetan-zettel--extract-property (content key)
  "Return the value of `:KEY:' property from CONTENT, or nil.
Case-insensitive match on KEY.  Returns the first match; zettels
are expected to have at most one PROPERTIES drawer.  Whitespace
is trimmed from the value."
  (when (and content (stringp content) (stringp key))
    (let ((re (format "^[ \t]*:%s:[ \t]+\\(\\S-.*?\\)[ \t]*$"
                      (regexp-quote key)))
          (case-fold-search t))
      (when (string-match re content)
        (match-string 1 content)))))

(defun tibetan-zettel--has-heading-p (content heading)
  "Return non-nil when CONTENT has a heading matching HEADING.
HEADING is the literal text after the stars (e.g. `Claude
Explanation').  Matches any level of heading (`*' to `*****')."
  (and content heading
       (string-match-p (format "^\\*+[ \t]+%s[ \t]*$"
                               (regexp-quote heading))
                       content)))

(defconst tibetan-zettel--v1-wylie-re
  "^[ \t]*-[ \t]*Wylie:[ \t]*\\(.+?\\)[ \t]*$"
  "Regex matching the `- Wylie: VALUE' line in Pass-5b Kramer format.")

(defconst tibetan-zettel--v1-primary-re
  "^\\*\\*[ \t]+%s[ \t]*$\\([^*]*?\\)^\\*\\*"
  "Template: regex for a `** SECTION' body, bounded to the next `**'.
Used to scope `- Primary translation:' lookups to the correct
section (English vs German).")

(defun tibetan-zettel--v1-extract-primary (content section)
  "In CONTENT, find `** SECTION' and return the `- Primary translation:'
value within it, or nil.  SECTION is e.g. \"English\" / \"German\"."
  (when (and content section)
    (let ((re (format "^\\*\\*[ \t]+%s[ \t]*\n\\(\\(?:[^*]\\|\\*[^*]\\)*?\\)\\(?:\\*\\*\\|\\'\\)"
                      (regexp-quote section))))
      (when (string-match re content)
        (let ((section-body (match-string 1 content)))
          (when (string-match
                 "^[ \t]*-[ \t]*Primary translation:[ \t]*\\(.+?\\)[ \t]*$"
                 section-body)
            (string-trim (match-string 1 section-body))))))))

;; ============================================================================
;; Parsing — dispatches between v1 and v2 schemas
;; ============================================================================

(defun tibetan-zettel--parse-v2 (content path)
  "Parse CONTENT at PATH as a v2 (properties-drawer) zettel.
Returns a plist, or nil if no `:wylie:' property is found (can't
index without a key)."
  (let ((wylie (tibetan-zettel--extract-property content "wylie")))
    (when (and wylie (not (string-empty-p wylie)))
      (let* ((pref-de (tibetan-zettel--extract-property content "preferred-de"))
             (pref-en (tibetan-zettel--extract-property content "preferred-en"))
             (de-placeholder-p (and pref-de
                                    (string= pref-de "[to be researched]")))
             (en-placeholder-p (and pref-en
                                    (string= pref-en "[to be researched]")))
             (steinert-84000-raw
              (tibetan-zettel--extract-property content "steinert-84000"))
             (claude-cached-raw
              (tibetan-zettel--extract-property content "claude-cached")))
        (list :id             (tibetan-zettel--extract-property content "ID")
              :path           path
              :wylie          (downcase (string-trim wylie))
              :script         (tibetan-zettel--extract-property content "script")
              :sanskrit       (tibetan-zettel--extract-property content "sanskrit")
              :preferred-de   pref-de
              :preferred-de-placeholder-p de-placeholder-p
              :preferred-en   pref-en
              :preferred-en-placeholder-p en-placeholder-p
              :steinert-84000 (and steinert-84000-raw
                                   (member (downcase steinert-84000-raw)
                                           '("yes" "y" "true" "t")))
              :claude-cached-p (and claude-cached-raw
                                    (not (string-empty-p claude-cached-raw))))))))

(defun tibetan-zettel--parse-v1 (content path)
  "Parse CONTENT at PATH as a Pass-5b Kramer-format zettel.
Returns a plist with the same shape as the v2 parser, or nil if
no `- Wylie:' field is found."
  (when (string-match tibetan-zettel--v1-wylie-re content)
    (let* ((wylie (string-trim (match-string 1 content)))
           (id-re "^[ \t]*:ID:[ \t]*\\(.+?\\)[ \t]*$")
           (id (when (string-match id-re content)
                 (match-string 1 content)))
           (title-re "^#\\+title:[ \t]*\\(.+?\\)[ \t]*$")
           (title (when (let ((case-fold-search t))
                          (string-match title-re content))
                    (match-string 1 content)))
           (pref-en (tibetan-zettel--v1-extract-primary content "English"))
           (pref-de (tibetan-zettel--v1-extract-primary content "German")))
      (when (and wylie (not (string-empty-p wylie)))
        (list :id             id
              :path           path
              :wylie          (downcase wylie)
              :script         nil
              :sanskrit       title
              :preferred-de   pref-de
              :preferred-de-placeholder-p nil
              :preferred-en   pref-en
              :preferred-en-placeholder-p nil
              :steinert-84000 nil
              :claude-cached-p nil)))))

(defun tibetan-zettel--parse-file (path)
  "Parse the zettel at PATH into a plist, or return nil.
Tries the v2 (properties) schema first; falls back to the v1
(Kramer sections) schema.  Returns nil when neither parses — e.g.
the file is not translation-relevant (no `:wylie:' property AND
no `- Wylie:' line) or is unreadable.

The returned plist has the shape documented in the module
commentary."
  (when (and path (file-readable-p path))
    (let ((content (with-temp-buffer
                     (insert-file-contents path)
                     (buffer-string))))
      (or (tibetan-zettel--parse-v2 content path)
          (tibetan-zettel--parse-v1 content path)))))

;; ============================================================================
;; Indexer
;; ============================================================================

(defvar tibetan-zettel--index nil
  "Hash: normalised Wylie key → entry plist.
See `tibetan-zettel--parse-file' for the plist shape.  Built lazily
on first `tibetan-zettel-lookup' via `tibetan-zettel--ensure-index',
or force-rebuilt via `tibetan-zettel-reload'.")

(defvar tibetan-zettel--index-dir nil
  "Directory the current `tibetan-zettel--index' was built from.
When this differs from the current `tibetan-zettel-directory', the
cache is invalidated on next access.")

(defun tibetan-zettel--build-index (&optional dir)
  "Walk DIR (default `tibetan-zettel-directory') and return a fresh
hash: Wylie → plist.

Non-translation-relevant files are skipped silently.  When the
same Wylie appears in multiple zettels, the LAST one wins — the
user is expected to merge duplicates; Phase 6's migration pass
surfaces conflicts."
  (let ((target-dir (expand-file-name (or dir tibetan-zettel-directory)))
        (index (make-hash-table :test 'equal)))
    (when (file-directory-p target-dir)
      (dolist (path (directory-files target-dir t "\\.org\\'"))
        (when (and (file-regular-p path)
                   (tibetan-zettel--translation-relevant-p path))
          (let ((entry (tibetan-zettel--parse-file path)))
            (when (and entry (plist-get entry :wylie))
              (puthash (plist-get entry :wylie) entry index))))))
    index))

(defun tibetan-zettel--ensure-index ()
  "Build the index lazily on first use, OR when the directory changed."
  (when (or (null tibetan-zettel--index)
            (not (equal tibetan-zettel--index-dir
                        (expand-file-name tibetan-zettel-directory))))
    (setq tibetan-zettel--index (tibetan-zettel--build-index)
          tibetan-zettel--index-dir (expand-file-name tibetan-zettel-directory)))
  tibetan-zettel--index)

;;;###autoload
(defun tibetan-zettel-reload ()
  "Force a fresh index build of `tibetan-zettel-directory'.
Call after edits that happened outside Emacs (git pull, external
tooling).  In-Emacs edits via the Phase 2+ commands should
invalidate the cache automatically."
  (interactive)
  (setq tibetan-zettel--index (tibetan-zettel--build-index)
        tibetan-zettel--index-dir (expand-file-name tibetan-zettel-directory))
  (when (called-interactively-p 'any)
    (message "tibetan-zettel: %d zettels indexed from %s"
             (hash-table-count tibetan-zettel--index)
             tibetan-zettel-directory))
  tibetan-zettel--index)

;; ============================================================================
;; Lookup
;; ============================================================================

(defun tibetan-zettel-lookup (wylie)
  "Return the zettel plist for WYLIE, or nil.
WYLIE is normalised (trimmed, lowercased) before lookup.  The
returned plist shape matches `tibetan-zettel--parse-file' — see
the module commentary."
  (when (and wylie (stringp wylie) (not (string-empty-p wylie)))
    (let ((key (downcase (string-trim wylie)))
          (index (tibetan-zettel--ensure-index)))
      (gethash key index))))

(provide 'tibetan-zettel)
;;; tibetan-zettel.el ends here
