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

;; ============================================================================
;; Phase 3 — Auto-creation for <term>-tagged missing tokens (2026-04-24)
;; ============================================================================
;;
;; When U3's Buddhist Terms detector surfaces a token tagged `<term>' by
;; Steinert's 84000 tables AND no zettel yet exists for that token's
;; wylie, offer to create one.  The scaffold seeds the zettel with the
;; 84000 Definitions body (for the `* 84000 Definitions' cache section)
;; and a best-effort auto-populated `:preferred-en:' from the short
;; gloss — `:preferred-de:' stays empty (marked `[to be researched]')
;; per design decision #6 (user-curated German).
;;
;; Gated by `tibetan-zettel-auto-create-on-buddhist-term':
;;   `always' — create silently.
;;   `ask'    — prompt `y-or-n-p', naming the term + short gloss.  (default)
;;   nil      — never create, surface term in Buddhist Terms block only.

(defcustom tibetan-zettel-auto-create-on-buddhist-term 'ask
  "Behaviour when a `<term>'-tagged token has no zettel yet.
See module commentary for semantics.  Default `ask' surfaces every
opportunity as a y-or-n-p prompt; switch to `always' once the
<term>-tag heuristic has proven itself on your corpus (i.e. no
more rejections)."
  :type '(choice (const :tag "Always create silently" always)
                 (const :tag "Ask per term (y-or-n-p)" ask)
                 (const :tag "Never auto-create" nil))
  :group 'tibetan-zettel)

(defun tibetan-zettel--slug-from-wylie (wylie)
  "Return a Denote filename slug from WYLIE.
Rules: lowercase, apostrophes dropped, non-alphanumeric → dashes,
consecutive dashes collapsed, leading/trailing dashes trimmed.

Examples:
  `bdag'                 → `bdag'
  `tshad med bzhi po'    → `tshad-med-bzhi-po'
  `'khor ba'             → `khor-ba'
  `Byang Chub Kyi Sems'  → `byang-chub-kyi-sems'"
  (when (and wylie (stringp wylie))
    (let* ((s (downcase (string-trim wylie)))
           (s (replace-regexp-in-string "['’]" "" s))
           (s (replace-regexp-in-string "[^a-z0-9]+" "-" s))
           (s (replace-regexp-in-string "-+" "-" s))
           (s (replace-regexp-in-string "\\`-\\|-\\'" "" s)))
      s)))

(defun tibetan-zettel--denote-timestamp ()
  "Return the current time as a Denote-style `YYYYMMDDTHHMMSS' string."
  (format-time-string "%Y%m%dT%H%M%S"))

(defun tibetan-zettel--denote-filename (timestamp slug)
  "Assemble the canonical auto-created zettel filename.
`<TIMESTAMP>--<SLUG>__glossar__buddhist-term.org'

Matches the Denote convention so the file participates in
whatever Denote wiring the zettelkasten already has (search,
renaming, backlinks); carries both the `__glossar' translation-
relevant tag AND a `__buddhist-term' tag distinguishing auto-
created entries from hand-written ones."
  (format "%s--%s__glossar__buddhist-term.org" timestamp slug))

(defun tibetan-zettel--extract-term-gloss (body)
  "From an 84000Definitions body string BODY, pull the short gloss
immediately after the `<term>' tag.  Returns the trimmed gloss or
nil.

The 84000 body format is:

  <term> SHORT-GLOSS (Skt: ...): LONG-EXPLANATION...

We take everything between `<term> ' and the first `(' or `:' or
newline, trimmed — this is the short reference-translation that
the auto-created `:preferred-en:' field is seeded with."
  (when (and body (stringp body))
    (when (string-match "<term>[ \t]+\\([^(:\n]+?\\)[ \t]*\\(?:(\\|:\\|$\\)"
                        body)
      (string-trim (match-string 1 body)))))

(cl-defun tibetan-zettel--create-for-term
    (&key wylie script sanskrit 84000-body preferred-en
          preferred-de source-analysis-file)
  "Create a new Denote-format zettel for the Buddhist term with WYLIE.
Returns the created file's absolute path, or nil on failure (bad
args, unwritable directory).

Required:
  :WYLIE — the term's Wylie, used for both the PROPERTIES drawer
           and the filename slug.

Optional (any may be nil):
  :SCRIPT             — Tibetan script for the drawer.
  :SANSKRIT           — Skt lemma (e.g. `caturapramāṇa').
  :84000-BODY         — Steinert's 84000Definitions paragraph.
                        Written into the `* 84000 Definitions'
                        cache section; auto-derives a short gloss
                        for :preferred-en if PREFERRED-EN is nil.
  :PREFERRED-EN       — explicit English preferred translation.
                        Falls back to extracting the short gloss
                        from 84000-BODY; falls back further to
                        `[to be researched]'.
  :PREFERRED-DE       — explicit German (default `[to be researched]').
                        Per design decision #6, the German stays
                        empty for user curation — auto-populating
                        would defeat the translation-gaps report.
  :SOURCE-ANALYSIS-FILE — path of the segment whose analysis
                        triggered creation.  When given, a back-
                        link is written into the `* Back-links'
                        section pointing at that file.

On success, reloads the index so `tibetan-zettel-lookup' sees the
new entry immediately."
  (when (and wylie (stringp wylie) (not (string-empty-p wylie)))
    (let* ((dir (expand-file-name tibetan-zettel-directory))
           (slug (tibetan-zettel--slug-from-wylie wylie))
           (timestamp (tibetan-zettel--denote-timestamp))
           (filename (tibetan-zettel--denote-filename timestamp slug))
           (path (expand-file-name filename dir))
           (pref-en-final (or (and preferred-en
                                   (not (string-empty-p preferred-en))
                                   preferred-en)
                              (tibetan-zettel--extract-term-gloss 84000-body)
                              "[to be researched]"))
           (pref-de-final (or (and preferred-de
                                   (not (string-empty-p preferred-de))
                                   preferred-de)
                              "[to be researched]"))
           (title (if script
                      (format "%s — %s" wylie pref-en-final)
                    wylie)))
      (unless (file-directory-p dir)
        (make-directory dir t))
      (with-temp-file path
        (insert (format "#+TITLE: %s\n" title))
        (insert ":PROPERTIES:\n")
        (insert (format ":ID:             %s\n" timestamp))
        (insert (format ":wylie:          %s\n" wylie))
        (when script   (insert (format ":script:         %s\n" script)))
        (when sanskrit (insert (format ":sanskrit:       %s\n" sanskrit)))
        (insert (format ":preferred-de:   %s\n" pref-de-final))
        (insert (format ":preferred-en:   %s\n" pref-en-final))
        (when 84000-body
          (insert ":steinert-84000: yes\n"))
        (insert ":END:\n\n")
        (insert "* Notes\n\n\n")
        (when 84000-body
          (insert "* 84000 Definitions\n")
          (insert ":PROPERTIES:\n:TERM_CACHE: t\n:END:\n\n")
          (insert 84000-body)
          (insert "\n\n"))
        (insert "* Claude Explanation\n")
        (insert ":PROPERTIES:\n:TERM_CACHE: t\n:END:\n\n")
        (insert "[awaiting first analysis]\n\n")
        (insert "* Back-links\n")
        (insert ":PROPERTIES:\n:TERM_CACHE: t\n:END:\n\n")
        (when (and source-analysis-file
                   (stringp source-analysis-file)
                   (file-readable-p source-analysis-file))
          (let* ((source-id (tibetan-zettel--read-source-id
                             source-analysis-file))
                 (label (file-name-base source-analysis-file))
                 (link (if source-id
                           (format "[[id:%s][%s]]" source-id label)
                         (format "[[file:%s][%s]]"
                                 source-analysis-file label))))
            (insert (format "- %s\n" link)))))
      ;; Reload the index so the new zettel is immediately findable.
      (tibetan-zettel-reload)
      path)))

(defun tibetan-zettel--read-source-id (analysis-file)
  "Return the top-level `:ID:' property of ANALYSIS-FILE, or nil.
Used to build back-links from auto-created zettels to the segment
analysis file that triggered their creation."
  (when (and analysis-file (file-readable-p analysis-file))
    (with-temp-buffer
      (insert-file-contents analysis-file nil 0 4096)
      (when (re-search-forward "^:ID:[ \t]+\\(\\S-.*?\\)[ \t]*$" nil t)
        (match-string 1)))))

(cl-defun tibetan-zettel-maybe-create-for-buddhist-term
    (&key wylie script sanskrit 84000-body preferred-en
          preferred-de source-analysis-file)
  "If a zettel doesn't exist for WYLIE, create one per user prefs.
Behaviour dispatches on `tibetan-zettel-auto-create-on-buddhist-term':

  - nil      → return nil without prompting or writing.
  - `always' → create immediately.
  - `ask'    → prompt `y-or-n-p' showing WYLIE + the derived
               short gloss; create on y, skip on n.

Returns the created zettel's path, or nil when nothing was written.
Idempotent: if a zettel already exists for WYLIE (hit in the
current index), returns nil immediately without prompting.

See `tibetan-zettel--create-for-term' for the full argument list."
  (when (and wylie
             tibetan-zettel-auto-create-on-buddhist-term
             (not (tibetan-zettel-lookup wylie)))
    (let* ((short-gloss (or preferred-en
                            (tibetan-zettel--extract-term-gloss 84000-body)
                            "this term"))
           (proceed-p
            (cl-case tibetan-zettel-auto-create-on-buddhist-term
              (always t)
              (ask (y-or-n-p
                    (format "Create zettel for `%s' (%s)? "
                            wylie short-gloss)))
              (t nil))))
      (when proceed-p
        (tibetan-zettel--create-for-term
         :wylie wylie
         :script script
         :sanskrit sanskrit
         :84000-body 84000-body
         :preferred-en preferred-en
         :preferred-de preferred-de
         :source-analysis-file source-analysis-file)))))

;; ============================================================================
;; Phase 4 — Claude-cache write path (2026-04-24)
;; ============================================================================
;;
;; When `tibetan-analysis--insert-claude-sections' parses a `## Vocabulary'
;; block from a Claude response, each line whose Wylie key matches a
;; zettel can have its gloss text cached into that zettel's `* Claude
;; Explanation' section.  Cache writes:
;;   · only fill EMPTY sections — never overwrite user edits or a
;;     prior cache (that's what Phase 5's prompt-version-hash check
;;     handles when a refresh IS warranted).
;;   · stamp three properties (`:claude-cached:' / `:claude-model:' /
;;     `:prompt-version:') so Phase 5 can detect stale entries when
;;     the system prompt has changed since the cache was written.
;;
;; The Phase-4 writer ONLY writes; the Phase-5 reader will use the
;; stamped properties to decide when to bypass the cache and refetch.

(defun tibetan-zettel--prompt-version-hash (prompt)
  "Return a 12-char SHA-256 hex prefix of PROMPT, suitable as the
`:prompt-version:' property value.

Short enough to fit on a property line, long enough that
collisions across realistic prompt revisions are negligible.  When
Phase 5 reads this property and compares against the current
prompt's hash, mismatch → bypass cache, fetch fresh from Claude,
overwrite the cached entry with the new response and stamps."
  (substring (secure-hash 'sha256 (or prompt "")) 0 12))

(defun tibetan-zettel--claude-explanation-empty-p (content)
  "Return non-nil if CONTENT's `* Claude Explanation' section body
is empty / placeholder (`[awaiting first analysis]' or just
whitespace).  Used to gate cache writes — a populated section is
left strictly alone.

Searches for the Phase-3 scaffold marker line, since the Claude
Explanation heading itself can appear anywhere; the body region
is what we inspect."
  (and content
       (or (string-match-p "\\[awaiting first analysis\\]" content)
           ;; The section exists with nothing under it (just the
           ;; :TERM_CACHE: drawer + whitespace until the next
           ;; top-level heading).
           (string-match-p "^\\* Claude Explanation\n\\(?::PROPERTIES:\n[^*]*?:END:\n\\)?[ \t\n]*\\(\\*\\|\\'\\)"
                           content))))

(cl-defun tibetan-zettel--cache-claude-explanation
    (path explanation &key model prompt-version)
  "Write EXPLANATION into PATH's `* Claude Explanation' section.
No-op when the section is already populated (writer is idempotent
and respects user / prior-cache content).

Stamps the zettel's PROPERTIES drawer with `:claude-cached:'
(today's date), `:claude-model:' (MODEL or `(unknown)') and
`:prompt-version:' (PROMPT-VERSION or `unknown') for Phase 5's
freshness check.

Returns t when an update was written, nil when skipped (already
populated)."
  (when (and path (file-readable-p path)
             explanation (stringp explanation)
             (not (string-empty-p (string-trim explanation))))
    (let ((content (with-temp-buffer
                     (insert-file-contents path)
                     (buffer-string))))
      (when (tibetan-zettel--claude-explanation-empty-p content)
        ;; Atomically rewrite the file.
        (with-temp-file path
          (insert content)
          ;; 1. Update PROPERTIES drawer with the three stamps.
          (goto-char (point-min))
          (when (re-search-forward "^:END:[ \t]*$" nil t)
            (let ((end-of-drawer (match-beginning 0)))
              (goto-char end-of-drawer)
              ;; Remove existing stamps so we can re-emit them
              ;; (idempotent re-stamp on same prompt-version).
              (dolist (key '("claude-cached" "claude-model" "prompt-version"))
                (save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward
                         (format "^:%s:.*$\n" (regexp-quote key))
                         end-of-drawer t)
                    (replace-match ""))))
              ;; Re-locate :END: (the previous deletes shifted it).
              (goto-char (point-min))
              (re-search-forward "^:END:[ \t]*$")
              (beginning-of-line)
              (insert (format ":claude-cached:   %s\n"
                              (format-time-string "%Y-%m-%d")))
              (insert (format ":claude-model:    %s\n"
                              (or model "(unknown)")))
              (insert (format ":prompt-version:  %s\n"
                              (or prompt-version "unknown")))))
          ;; 2. Replace the placeholder body of `* Claude Explanation'.
          (goto-char (point-min))
          (when (re-search-forward "^\\* Claude Explanation[ \t]*$" nil t)
            ;; Skip past any :PROPERTIES: drawer that follows the heading.
            (forward-line 1)
            (when (looking-at-p "^:PROPERTIES:")
              (re-search-forward "^:END:[ \t]*\n" nil t))
            (let ((body-start (point))
                  (body-end (save-excursion
                              (if (re-search-forward "^\\* " nil t)
                                  (line-beginning-position)
                                (point-max)))))
              (delete-region body-start body-end)
              (goto-char body-start)
              (insert "\n" (string-trim explanation) "\n\n"))))
        ;; Reload index so subsequent reads see the new stamps.
        (tibetan-zettel-reload)
        t))))

(defun tibetan-zettel--extract-claude-vocab-gloss (line)
  "Return the QUOTED gloss field from a Claude Vocabulary LINE.
Format Claude emits is

  wylie-key, part-of-speech, \"gloss\", commentary

Only the third field (between the first pair of double quotes)
is the cacheable short explanation.  Returns nil when the line
lacks a quoted field."
  (when (and line (stringp line) (string-match "\"\\([^\"]+\\)\"" line))
    (string-trim (match-string 1 line))))

(cl-defun tibetan-zettel--cache-claude-vocabulary
    (vocab-alist &key model prompt-version)
  "Walk VOCAB-ALIST (parsed `## Vocabulary' from a Claude response —
each entry is (WYLIE-KEY . FULL-LINE)) and update zettels in place.

For each entry whose WYLIE-KEY hits an existing zettel, calls
`--cache-claude-explanation' with the line's quoted gloss field.
Skips entries with no matching zettel and entries whose gloss
field can't be extracted.

MODEL and PROMPT-VERSION are passed through to the writer for the
property stamps.  When the caller doesn't know either, default
values are used.

Returns the count of zettels actually updated (excludes skipped
and no-match entries)."
  (let ((updated 0)
        (effective-model (or model
                             (and (boundp 'gptel-model)
                                  (format "%s" gptel-model))
                             "(unknown)"))
        (effective-version
         (or prompt-version
             (and (boundp 'tibetan-analysis--claude-system-prompt)
                  (tibetan-zettel--prompt-version-hash
                   tibetan-analysis--claude-system-prompt))
             "unknown")))
    (dolist (pair vocab-alist)
      (let* ((wylie (car pair))
             (line (cdr pair))
             (entry (and wylie (tibetan-zettel-lookup wylie)))
             (gloss (tibetan-zettel--extract-claude-vocab-gloss line)))
        (when (and entry gloss)
          (when (tibetan-zettel--cache-claude-explanation
                 (plist-get entry :path)
                 gloss
                 :model effective-model
                 :prompt-version effective-version)
            (cl-incf updated)))))
    updated))

;; ============================================================================
;; Phase 3 — Interactive walker over the current analysis buffer's
;; `*** Buddhist Terms' subsection.  This is the user-facing hook: after
;; opening or regenerating a segment analysis file, run this to offer
;; zettel creation for every term under the Buddhist Terms section.
;; ============================================================================

(defconst tibetan-zettel--buddhist-terms-heading-re
  "^\\*\\*\\* Buddhist Terms[ \t]*$"
  "Regex for the U3-emitted Buddhist Terms subsection heading.")

(defconst tibetan-zettel--buddhist-term-line-re
  "^- \\(.+?\\) \\[\\(.+?\\)\\][ \t]*$"
  "Regex for a `- SCRIPT [wylie]' entry inside Buddhist Terms.
Capture 1: Tibetan script.  Capture 2: Wylie.  The body line(s)
follow on subsequent lines indented by at least two spaces; see
`tibetan-zettel--parse-buddhist-term-body' for extraction.")

(defun tibetan-zettel--parse-buddhist-term-body (line-end section-end)
  "Return the body excerpt following a `- SCRIPT [wylie]' line.
Starts at LINE-END (end of the header line) and reads following
indented lines until the next `- ' bullet or SECTION-END, joining
them with spaces.  Trimmed."
  (save-excursion
    (goto-char line-end)
    (forward-line 1)
    (let ((start (point))
          (end section-end))
      (while (and (< (point) section-end)
                  (looking-at "^[ \t]+[^-]"))
        (forward-line 1))
      (when (< (point) section-end)
        (setq end (point)))
      (string-trim (buffer-substring-no-properties start end)))))

;;;###autoload
(defun tibetan-zettel-auto-create-from-current-analysis ()
  "Walk the current analysis buffer's `*** Buddhist Terms' section and
offer to create a zettel for every term that doesn't already have
one.  Gated by `tibetan-zettel-auto-create-on-buddhist-term' — see
that defcustom for per-term prompt behaviour.

Signals a `user-error' when the current buffer has no
`*** Buddhist Terms' heading (either the analysis hasn't been
generated yet or the segment has no <term>-tagged tokens).

Back-links on created zettels point at the current analysis
file's `:ID:' (if present) or path."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (unless (re-search-forward tibetan-zettel--buddhist-terms-heading-re
                               nil t)
      (user-error "No `*** Buddhist Terms' section in this buffer — \
run `C-c u R' to regenerate, or there are no <term>-tagged tokens"))
    (let* ((section-end
            (save-excursion
              (if (re-search-forward "^\\*\\*\\* \\|^\\*\\* " nil t)
                  (line-beginning-position)
                (point-max))))
           (analysis-file (buffer-file-name))
           (created 0)
           (skipped 0)
           (declined 0))
      (while (re-search-forward tibetan-zettel--buddhist-term-line-re
                                section-end t)
        (let* ((script (match-string 1))
               (wylie (match-string 2))
               (body (tibetan-zettel--parse-buddhist-term-body
                      (match-end 0) section-end)))
          (cond
           ((tibetan-zettel-lookup wylie)
            (cl-incf skipped))
           ((tibetan-zettel-maybe-create-for-buddhist-term
             :wylie wylie
             :script script
             :84000-body body
             :source-analysis-file analysis-file)
            (cl-incf created))
           (t
            (cl-incf declined)))))
      (message "tibetan-zettel: %d created, %d already existed, %d declined"
               created skipped declined))))

(provide 'tibetan-zettel)
;;; tibetan-zettel.el ends here
