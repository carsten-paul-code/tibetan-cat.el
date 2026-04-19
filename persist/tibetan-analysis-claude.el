;;; tibetan-analysis-claude.el --- Claude pipeline for segment analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Extracted from `persist/tibetan-analysis-persist.el' — the
;; entire Claude-side pipeline that turns a segment's parser output
;; into a three-section Claude response (`** Claude Translation',
;; `*** Claude Vocabulary', `*** Claude Grammar') and wires it back
;; into the analysis file.
;;
;; Public entry points consumed by the renderer / commands /
;; batch-reanalysis code in `tibetan-analysis-persist':
;;
;;   tibetan-analysis--request-claude-translation
;;       Kick off a throttled Claude request via
;;       `tibetan-claude-queue-submit', passing the segment text and
;;       the parser-grounding context.  Writes results back into the
;;       analysis file and falls back to a visible failure stub when
;;       the request is ultimately rejected.
;;
;;   tibetan-analysis--insert-claude-sections
;;       Parse a fresh Claude response and insert / merge the three
;;       sections into the analysis buffer, running the legacy
;;       `*** Claude' migration first if needed.
;;
;;   tibetan-analysis--parse-claude-sections
;;       Plist-style parser for the raw three-section response
;;       (`## Translation' / `## Vocabulary' / `## Grammar').  Tolerant
;;       of legacy `## Context' so older responses in sentence-level
;;       files still round-trip.
;;
;;   tibetan-analysis--ensure-claude-headings
;;   tibetan-analysis--migrate-legacy-claude-headings
;;       Org-structure migration:  earlier tool versions produced a
;;       single `*** Claude Translation' at level-3 inside
;;       `** Provided Translations'.  These helpers walk any such
;;       analysis file and promote it to the current layout
;;       non-destructively.
;;
;;   tibetan-analysis--read-claude-sections / --read-claude-translation
;;   tibetan-analysis--restore-claude-sections / --restore-claude-translation
;;       Round-trip helpers used by `tibetan-analysis-batch-reanalyze'
;;       to preserve existing Claude output across a reanalysis.
;;
;;   tibetan-analysis--merge-claude-vocabulary
;;       Merge a Claude `## Vocabulary' block into the existing
;;       `*** Claude Vocabulary' section, de-duplicating by lemma.
;;
;; Shared helpers still live in `tibetan-analysis-persist':
;;   tibetan-analysis--read-section-body    (generic org section reader)
;;   tibetan-analysis--seg-id-from-filename (shared with batch)
;;   tibetan-analysis--claude-heading-re / --claude-stop-re /
;;     --claude-segment-layout-p / --claude-effective-section-order /
;;     --replace-claude-section-body / --insert-claude-translation-heading
;;   are all Claude-specific and live here.
;;
;; This module soft-requires `tibetan-claude-queue' (the throttled
;; request queue) and `gptel' (the actual HTTP layer).  Both are
;; optional: when absent the request path short-circuits with a clear
;; message rather than erroring.

;;; Code:

(require 'cl-lib)
(require 'md5)
(require 'tibetan-claude-queue nil t)
(require 'gptel nil t)

;; External gptel symbols — declared so the byte-compiler doesn't warn
;; on fresh checkouts where gptel isn't installed.  Runtime guards
;; (`(fboundp 'gptel-request)') keep behaviour safe.
(defvar gptel-api-key)
(defvar gptel-backend)
(defvar gptel-model)
(declare-function gptel-request "gptel" (&optional prompt &rest args))
(declare-function gptel-make-anthropic "gptel" (name &rest args))

;; Forward declarations from the sibling render module
;; (`tibetan-analysis-persist').  Present at runtime once that module
;; is loaded.
(declare-function tibetan-analysis--read-section-body "tibetan-analysis-persist"
                  (filepath section-name))
(declare-function tibetan-analysis--seg-id-from-filename
                  "tibetan-analysis-persist" (filepath))
(declare-function tibetan-analysis--folder-analysis-files
                  "tibetan-analysis-persist" (folder))
(declare-function tibetan-analysis-get-folder "tibetan-analysis-persist" ())

;; ============================================================================
;; CLAUDE TRANSLATION (via gptel)
;; ============================================================================

(defvar tibetan-analysis--claude-system-prompt
  "You are a specialist in Classical Tibetan (chos skad) translation \
and philology, acting as a teaching assistant for a graduate classroom.

Produce THREE sections, separated by the exact markdown headings \
shown below, in this order and nothing else:

## Translation
A clear, idiomatic English rendering of the passage.
- Preserve technical Buddhist terminology (use Sanskrit where standard, \
e.g. dharma, bodhisattva, samādhi), with English gloss in parentheses \
on first occurrence only.
- Render particles and syntactic structures idiomatically, not literally.
- Honorific forms (zhu, gsol, mdzad, etc.) should be reflected in the \
register.
- Keep the translation fluent and readable, not word-for-word.
- When a glossary for this passage is provided in the user prompt, \
prefer those renderings for proper names and technical terms.
- When ±2 surrounding segments are provided, use them as context to \
resolve ambiguous pronouns, discourse particles, and sentence-internal \
reference — but translate ONLY the target passage.
- No commentary in this section.

## Vocabulary
Word-by-word analysis in DharmaMitra style.  For EACH word or \
compound in the passage, produce exactly one line with four fields \
separated by comma-space:

  wylie, grammatical-category, \"meaning\", contextual-note

Fields:
  1. wylie — EWTS romanisation, lowercase, e.g. \"mnyam med\".
  2. grammatical-category — one of: noun, proper noun, adjective, \
adverb, verb (hon.), verb, transitive verb, intransitive verb, \
converb, nominalizer, genitive, ergative/instrumental, terminative, \
ablative, locative, dative, particle, sentence-final particle, \
negation, conjunction, relative clause marker, or a similarly \
concise label.
  3. meaning — short English gloss in double quotes.  \
When a glossary entry is provided in the user prompt, prefer that \
rendering; otherwise give the contextually best fitting sense.
  4. contextual-note (optional) — e.g. \"epithet of ...\", \
\"honorific of byed pa\", \"marks the agent of mdzad\".  Omit \
the trailing comma when this field is absent.

Keep multi-word expressions (proper names, verb + nominaliser, \
particle compounds like \"pa'i\") together on one line.  \
Order follows the passage left-to-right.

Example:
  mnyam med, adjective, \"peerless\", epithet — literally \"without equal\"
  'gro ba'i, genitive, \"of beings\"
  mgon po, noun, \"protector\"

## Grammar
Explain the grammatical structure pedagogically for readers learning \
Classical Tibetan. Name the metalanguage explicitly (Ergativ, Ablativ, \
Dativ, Terminativ, Instrumental, Komitativ, Genitiv; converb type \
— ablative / causal / simultaneous / conditional / concessive / \
coordinative; nominalizer; finite verb; honorific stem). Reference the \
actual Tibetan forms in parentheses. If the passage is verse \
(consistent pāda-length lines bounded by shad), note the line structure \
and any recurring rhetorical formula spanning the stanza; if prose, \
focus on the clause chain and converb function within the narrative \
sequence. You will be given the parser's own analysis in the user \
prompt — treat it as ground truth for case and verb tagging; your \
job is to narrate it pedagogically, not to contradict it. If you \
disagree with a tag, flag the disagreement rather than silently \
overruling it.

Use only these three headings. No preamble, no closing remarks.

Genre, period and context hints (if any) are supplied below by the \
source file via `#+TIBETAN_CLAUDE_CONTEXT:' headers. Do NOT assume a \
specific genre unless such context is given."
  "System prompt sent to Claude for segment-level three-section analysis.
Produces a markdown response (Translation / Vocabulary / Grammar)
parsed by `tibetan-analysis--parse-claude-sections' and placed into
`** Claude Translation', `*** Claude Vocabulary', and
`*** Claude Grammar'.  Vocabulary uses DharmaMitra-style
word-by-word format as the second tier (after provided vocabulary,
before Steinert entries).  Genre-specific assumptions come from the
source file's `#+TIBETAN_CLAUDE_CONTEXT:' headers.")

;; ----------------------------------------------------------------------------
;; Source-aware prompt enrichment (workshop-ready)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--read-source-metadata (source-file)
  "Return a plist of prompt-relevant metadata extracted from SOURCE-FILE.
Keys:
  :title           value of the first `#+TITLE:' line
  :work            :WORK from the first :PROPERTIES: drawer
  :author          :AUTHOR from the first :PROPERTIES: drawer
  :sources         :SOURCES from the first :PROPERTIES: drawer
  :claude-context  list of all `#+TIBETAN_CLAUDE_CONTEXT:' values in order
  :vocab-file      value of `#+TIBETAN_VOCAB_FILE:' (relative to SOURCE-FILE)

Safe when SOURCE-FILE is nil or does not exist — returns an empty plist."
  (let (title work author sources ctx vocab)
    (when (and source-file (file-exists-p source-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents source-file)
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
              (setq title (string-trim (match-string 1))))
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TIBETAN_VOCAB_FILE:[ \t]*\\(.*\\)$" nil t)
              (setq vocab (string-trim (match-string 1))))
            (goto-char (point-min))
            (while (re-search-forward
                    "^#\\+TIBETAN_CLAUDE_CONTEXT:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (push val ctx))))
            (setq ctx (nreverse ctx))
            ;; First :PROPERTIES: drawer
            (goto-char (point-min))
            (when (re-search-forward "^:PROPERTIES:$" nil t)
              (let ((drawer-end (save-excursion
                                  (re-search-forward "^:END:$" nil t))))
                (when drawer-end
                  (save-restriction
                    (narrow-to-region (point) drawer-end)
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:WORK:[ \t]*\\(.*\\)$" nil t)
                      (setq work (string-trim (match-string 1))))
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:AUTHOR:[ \t]*\\(.*\\)$" nil t)
                      (setq author (string-trim (match-string 1))))
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:SOURCES:[ \t]*\\(.*\\)$" nil t)
                      (setq sources (string-trim (match-string 1)))))))))
        (error nil))) ;; close condition-case and outer `when source-file'
    (list :title title
          :work work
          :author author
          :sources sources
          :claude-context ctx
          :vocab-file vocab)))


(defun tibetan-analysis--source-file-from-analysis (analysis-file)
  "Return the absolute source file referenced by ANALYSIS-FILE.
Reads the `#+SOURCE:' header (an org link of the form
`[[file:../foo.org::*Segment N][…]]') and resolves it relative to
the directory of ANALYSIS-FILE.  Returns nil if nothing is found."
  (when (and analysis-file (file-exists-p analysis-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (goto-char (point-min))
          (when (re-search-forward
                 "^#\\+SOURCE:[ \t]*\\[\\[file:\\([^]:]+\\)" nil t)
            (let ((rel (match-string 1)))
              (expand-file-name rel (file-name-directory analysis-file)))))
      (error nil))))

(defun tibetan-analysis--match-resources-vocab (tibetan-text vocab-file)
  "Return a list of (TERM . GLOSS) from VOCAB-FILE that occur in TIBETAN-TEXT.
VOCAB-FILE is an org file containing a table whose first column is the
Tibetan term and second column is the gloss."
  (let (matches)
    (when (and tibetan-text vocab-file (file-exists-p vocab-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents vocab-file)
            (goto-char (point-min))
            (while (re-search-forward
                    "^[ \t]*|[ \t]*\\([^|\n]+?\\)[ \t]*|[ \t]*\\([^|\n]+?\\)[ \t]*|"
                    nil t)
              (let ((term (string-trim (match-string 1)))
                    (gloss (string-trim (match-string 2))))
                (when (and (not (string-empty-p term))
                           ;; Skip header separator / "Term" header row
                           (not (string-match-p "\\`-+\\'" term))
                           (not (string= term "Term"))
                           ;; Must contain at least one Tibetan char
                           (string-match-p "[\u0F00-\u0FFF]" term)
                           (string-match-p (regexp-quote term) tibetan-text))
                  (push (cons term gloss) matches)))))
        (error nil)))
    (nreverse matches)))

(defun tibetan-analysis--read-analysis-parser-sections (analysis-file)
  "Return a plist of parser-output sections extracted from ANALYSIS-FILE.
Used to give Claude the tool's own grammatical analysis as grounding
for the Grammar section of the three-section response.  Keys:
  :grammatical-markers   body of `** Grammatical Markers'
  :clause-structure      body of `** Clause Structure'
  :verb-classification   body of `** Verb Classification (Hill 2010)'
  :sentence-structure    body of `** Sentence Structure'
Any missing section is nil.  Safe when ANALYSIS-FILE is nil or absent."
  (let (markers clauses verbs sentences)
    (when (and analysis-file (file-exists-p analysis-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents analysis-file)
            (cl-labels
                ((body-of (heading-re)
                   (save-excursion
                     (goto-char (point-min))
                     (when (re-search-forward heading-re nil t)
                       (forward-line 1)
                       (let ((start (point))
                             (end (save-excursion
                                    (if (re-search-forward
                                         "^\\*\\* [^ \t\n]\\|^\\* [^ \t\n]"
                                         nil t)
                                        (line-beginning-position)
                                      (point-max)))))
                         (let ((body (string-trim
                                      (buffer-substring-no-properties
                                       start end))))
                           (unless (string-empty-p body) body)))))))
              (setq markers   (body-of "^\\*\\* Grammatical Markers$")
                    clauses   (body-of "^\\*\\* Clause Structure$")
                    verbs     (body-of
                               "^\\*\\* Verb Classification[^\n]*$")
                    sentences (body-of "^\\*\\* Sentence Structure$"))))
        (error nil)))
    (list :grammatical-markers markers
          :clause-structure    clauses
          :verb-classification verbs
          :sentence-structure  sentences)))

(defun tibetan-analysis--format-parser-grounding (parser-sections)
  "Format PARSER-SECTIONS (plist from `--read-analysis-parser-sections')
as a single text block suitable for embedding in the Claude user
prompt.  Returns nil when every section is empty."
  (let ((parts '())
        (markers (plist-get parser-sections :grammatical-markers))
        (clauses (plist-get parser-sections :clause-structure))
        (verbs   (plist-get parser-sections :verb-classification)))
    (when markers
      (push (concat "Grammatical markers (parser output):\n" markers)
            parts))
    (when clauses
      (push (concat "Clause structure (parser output):\n" clauses)
            parts))
    (when verbs
      (push (concat "Verb classification (parser output):\n" verbs)
            parts))
    (when parts
      (concat "\n\nParser analysis (ground truth for case and verb "
              "tagging — narrate this pedagogically, flag disagreements "
              "rather than silently overruling):\n\n"
              (mapconcat #'identity (nreverse parts) "\n\n")))))

;; ----------------------------------------------------------------------------
;; Per-segment vocabulary matches (from the analysis file itself)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--read-word-particle-list (analysis-file)
  "Return the body of `** Word / Particle List' in ANALYSIS-FILE, or nil.
This is the compact, numbered vocabulary list the tool generates for
each segment: `N. Tibetan [wylie]  [tag] — short gloss'.  Safe when
ANALYSIS-FILE is nil or does not exist."
  (when (and analysis-file (file-exists-p analysis-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (goto-char (point-min))
          (when (re-search-forward
                 "^\\*\\* Word / Particle List$" nil t)
            (forward-line 1)
            (let* ((start (point))
                   (end (save-excursion
                          (if (re-search-forward
                               (tibetan-analysis--claude-stop-re 2) nil t)
                              (line-beginning-position)
                            (point-max))))
                   (body (string-trim
                          (buffer-substring-no-properties start end))))
              (unless (or (string-empty-p body)
                          ;; Skip obvious placeholders
                          (string-match-p "\\`\\[" body))
                body))))
      (error nil))))

(defun tibetan-analysis--format-segment-vocabulary (analysis-file)
  "Return the per-segment vocabulary block for the Claude user prompt.
Draws from the `** Word / Particle List' section of ANALYSIS-FILE (the
tool's own per-segment matches, already enriched with Hill morphology
and Resources entries).  Returns nil when the section is missing or
empty so the prompt builder can skip it cleanly."
  (let ((body (tibetan-analysis--read-word-particle-list analysis-file)))
    (when body
      (concat "\n\nPer-segment vocabulary matches (from the analysis "
              "file — the tool's own layered lookup across Resources, "
              "Hopkins, Bialek, and bundled glossaries).  Prefer these "
              "glosses when they clearly fit; treat particle tags as "
              "authoritative.\n\n" body))))

;; ----------------------------------------------------------------------------
;; Surrounding-segments context (±2 neighbors from the same analysis folder)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--neighbor-analysis-file (analysis-file seg-id)
  "Return the existing `seg-SEG-ID*.org' neighbor of ANALYSIS-FILE, or nil.
Looks in the same directory; if multiple variants exist (e.g. with a
short-title suffix), picks the one whose basename matches the exact
`seg-NNN' prefix first, otherwise falls back to directory-files
ordering.  SEG-ID is an integer."
  (when (and analysis-file seg-id)
    (let* ((dir (file-name-directory analysis-file))
           (prefix (format "seg-%03d" seg-id))
           ;; Accept either `seg-012.org' or `seg-012-short-title.org'.
           (candidates
            (and (file-directory-p dir)
                 (directory-files
                  dir t
                  (concat "\\`"
                          (regexp-quote prefix)
                          "\\(\\.org\\'\\|-\\)")))))
      (car candidates))))

(defun tibetan-analysis--format-neighbor-segment
    (analysis-file seg-id offset)
  "Return a text block describing ANALYSIS-FILE's neighbor at OFFSET.
Reads `* Tibetan Text' (required) and `* Working Translation'
(optional) from the neighbor file.  OFFSET is the signed distance
(e.g. -1 for preceding, +1 for following).  Returns nil when the
neighbor does not exist or has no Tibetan text."
  (let* ((neighbor-id (+ seg-id offset))
         (neighbor (tibetan-analysis--neighbor-analysis-file
                    analysis-file neighbor-id)))
    (when (and neighbor (file-exists-p neighbor))
      (let* ((tibetan (tibetan-analysis--read-section-body
                       neighbor "Tibetan Text"))
             (working (tibetan-analysis--read-section-body
                       neighbor "Working Translation"))
             (label (format "Segment %d (%s %d)"
                            neighbor-id
                            (if (< offset 0) "−" "+")
                            (abs offset))))
        (when (and tibetan (not (string-empty-p (string-trim tibetan))))
          (concat label "\n"
                  "  Tibetan: " (string-trim tibetan)
                  (when (and working
                             (not (string-empty-p (string-trim working))))
                    (concat "\n  Working translation: "
                            (string-trim working)))))))))

(defun tibetan-analysis--format-surrounding-segments (analysis-file)
  "Return a ±2 surrounding-segments block for the Claude user prompt.
For each of offsets -2, -1, +1, +2 that resolves to an existing
neighbor file (see `--neighbor-analysis-file'), include its Tibetan
text and Working Translation (if non-empty).  Returns nil when no
neighbors could be resolved so the prompt stays lean for isolated
segments."
  (when analysis-file
    (let ((seg-id (tibetan-analysis--seg-id-from-filename analysis-file)))
      (when seg-id
        (let ((parts '()))
          (dolist (offset '(-2 -1 1 2))
            (let ((block (tibetan-analysis--format-neighbor-segment
                          analysis-file seg-id offset)))
              (when block (push block parts))))
          (when parts
            (concat "\n\nSurrounding segments (±2) — context only; "
                    "translate ONLY the target passage.  Use these to "
                    "resolve pronouns, discourse particles, and "
                    "sentence-internal reference across segment "
                    "boundaries.\n\n"
                    (mapconcat #'identity (nreverse parts) "\n\n"))))))))

(defun tibetan-analysis--build-claude-prompts
    (tibetan-text source-file &optional analysis-file)
  "Build (SYSTEM . USER) Claude prompts for TIBETAN-TEXT.
SOURCE-FILE, if non-nil, supplies genre/author/context metadata and a
Resources vocabulary file.  ANALYSIS-FILE, if non-nil, supplies four
forms of grounding:
  1. the parser's own output (grammatical markers, clause structure,
     verb classification) for the Grammar section;
  2. the tool's per-segment `** Word / Particle List' matches as a
     vocabulary hint for the Translation section;
  3. ±2 surrounding segments (Tibetan + Working Translation if present)
     from the same analysis folder so Claude can resolve anaphora and
     discourse without over-interpreting an isolated line;
  4. the file's own seg-id (used to resolve the neighbors in (3))."
  (let* ((meta   (tibetan-analysis--read-source-metadata source-file))
         (title  (plist-get meta :title))
         (work   (plist-get meta :work))
         (author (plist-get meta :author))
         (ctx    (plist-get meta :claude-context))
         (vocab-rel (plist-get meta :vocab-file))
         (vocab-file (and vocab-rel source-file
                          (expand-file-name
                           vocab-rel (file-name-directory source-file))))
         (glossary (and vocab-file
                        (tibetan-analysis--match-resources-vocab
                         tibetan-text vocab-file)))
         (wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed tibetan-text))
                  (error nil)))
         (src-block
          (let (parts)
            (when work   (push (format "Work: %s" work) parts))
            (when (and author (not (and work (string= work author))))
              (push (format "Author: %s" author) parts))
            (when (and title (not work)) (push (format "Title: %s" title) parts))
            (when ctx
              (push "Context from source file:" parts)
              (dolist (line ctx)
                (push (format "  - %s" line) parts)))
            (when parts
              (concat "\n\nSource metadata for this passage:\n"
                      (mapconcat #'identity (nreverse parts) "\n")))))
         (system (concat tibetan-analysis--claude-system-prompt
                         (or src-block "")))
         (glossary-block
          (when glossary
            (concat
             "\n\nGlossary for this passage — authoritative. "
             "Prefer these renderings in the Translation section; "
             "treat proper names and epithets as single tokens in the "
             "Grammar section.\n"
             (mapconcat (lambda (kv)
                          (format "  - %s = %s" (car kv) (cdr kv)))
                        glossary "\n"))))
         (vocab-block
          (tibetan-analysis--format-segment-vocabulary analysis-file))
         (surrounding-block
          (tibetan-analysis--format-surrounding-segments analysis-file))
         (grounding-block
          (tibetan-analysis--format-parser-grounding
           (tibetan-analysis--read-analysis-parser-sections analysis-file)))
         (user (concat "Classical Tibetan passage:\n\n"
                       tibetan-text
                       (if wylie (format "\n\nWylie: %s" wylie) "")
                       (or glossary-block "")
                       (or vocab-block "")
                       (or surrounding-block "")
                       (or grounding-block "")
                       "\n\nProduce the three sections now.")))
    (cons system user)))

(defun tibetan-analysis--read-authinfo-key (host)
  "Read password for HOST from ~/.authinfo or ~/.authinfo.gpg.
Parses the file directly for reliability.
Returns the password string or nil."
  (let ((authinfo-files (list (expand-file-name "~/.authinfo")
                              (expand-file-name "~/.authinfo.gpg"))))
    (cl-loop for file in authinfo-files
             when (file-exists-p file)
             do (condition-case nil
                    (with-temp-buffer
                      (insert-file-contents file)
                      (goto-char (point-min))
                      (when (re-search-forward
                             (format "machine %s.*?password \\(\\S-+\\)"
                                     (regexp-quote host))
                             nil t)
                        (cl-return (match-string 1))))
                  (error nil)))))

(defun tibetan-analysis--ensure-gptel-ready ()
  "Ensure gptel is configured with Anthropic backend and API key.
Sets up the backend if claude-integration.el was not loaded.
Reads the API key from ~/.authinfo or environment.
Returns non-nil if gptel is ready to use."
  (when (featurep 'gptel)
    ;; Step 1: Ensure API key is set
    (unless (and (boundp 'gptel-api-key)
                 gptel-api-key
                 (stringp gptel-api-key)
                 (not (string-empty-p gptel-api-key)))
      ;; Read directly from ~/.authinfo (most reliable)
      (let ((key (tibetan-analysis--read-authinfo-key "api.anthropic.com")))
        (when key
          (setq gptel-api-key key)))
      ;; Fallback: environment variable
      (unless (and (boundp 'gptel-api-key) gptel-api-key)
        (let ((env-key (getenv "ANTHROPIC_API_KEY")))
          (when (and env-key (not (string-empty-p env-key)))
            (setq gptel-api-key env-key)))))

    ;; Step 2: Ensure Anthropic backend is configured
    (when (and (boundp 'gptel-api-key)
               gptel-api-key
               (stringp gptel-api-key))
      (unless (and (boundp 'gptel-backend)
                   gptel-backend
                   ;; Check name field for Anthropic/Claude
                   (ignore-errors
                     (string-match-p "Claude\\|Anthropic"
                                     (format "%s" gptel-backend))))
        ;; Configure Anthropic backend
        (when (fboundp 'gptel-make-anthropic)
          (setq gptel-backend (gptel-make-anthropic "Claude"
                                :stream t
                                :key gptel-api-key))
          (unless (and (boundp 'gptel-model) gptel-model)
            (setq gptel-model "claude-sonnet-4-20250514"))))
      t)))

(defun tibetan-analysis--write-claude-failure-stub (analysis-file msg)
  "Write MSG into the *** Claude Translation section of ANALYSIS-FILE.
Only writes if that section is currently empty, missing, or already
holds a prior failure stub — never overwrites a real Claude response.
This is what callers should do from a queue :on-fail handler so the
user can see at a glance which segments still need a real Claude pass."
  (when (and analysis-file (file-exists-p analysis-file))
    (let* ((existing (ignore-errors
                       (tibetan-analysis--read-claude-sections
                        analysis-file)))
           (translation (and existing (plist-get existing :translation)))
           (trimmed (and translation (string-trim translation))))
      (when (or (null trimmed)
                (string-empty-p trimmed)
                (string-prefix-p "[Claude" trimmed)
                (string-prefix-p "[Requesting translation" trimmed))
        (let ((buf (or (find-buffer-visiting analysis-file)
                       (find-file-noselect analysis-file))))
          (with-current-buffer buf
            (when (fboundp 'tibetan-analysis--ensure-claude-headings)
              (tibetan-analysis--ensure-claude-headings buf))
            (when (fboundp 'tibetan-analysis--replace-claude-section-body)
              (tibetan-analysis--replace-claude-section-body
               buf "Claude Translation" msg))
            (save-buffer)))))))

(defun tibetan-analysis--claude-status-rate-limited-p (info)
  "Non-nil when gptel callback INFO indicates HTTP 429 (rate limited)."
  (let ((s (and (listp info) (plist-get info :status))))
    (and s (stringp s) (string-match-p "\\b429\\b" s))))

(defun tibetan-analysis--request-claude-translation
    (tibetan-text analysis-file &optional source-file)
  "Request a Claude translation of TIBETAN-TEXT asynchronously.
When the response arrives, insert it into ANALYSIS-FILE under the
*** Claude heading in the Provided Translations section.

If SOURCE-FILE is given (or can be derived from ANALYSIS-FILE's
`#+SOURCE:' link), its `#+TIBETAN_CLAUDE_CONTEXT:' headers,
:WORK/:AUTHOR properties and a Resources vocabulary file are folded
into the prompts so Claude gets genre / author / glossary context.

Requests go through `tibetan-claude-queue' so concurrent requests
are capped (see `tibetan-claude-queue-concurrency') and HTTP 429
responses are retried with exponential backoff (see
`tibetan-claude-queue-max-retries').  When retries are exhausted, a
visible placeholder is written into the *** Claude Translation
section so the segment is easy to find and re-run later via C-c u R.

Requires gptel and a configured Anthropic API key.  Never signals —
failures are reported via `message' and the placeholder."
  (require 'tibetan-claude-queue)
  (let ((label (and analysis-file
                    (file-name-nondirectory analysis-file))))
    (tibetan-claude-queue-submit
     (lambda (done)
       (condition-case err
           (progn
             (unless (and (featurep 'gptel) (fboundp 'gptel-request))
               (error "gptel not loaded"))
             (tibetan-analysis--ensure-gptel-ready)
             (let* ((src (or source-file
                             (tibetan-analysis--source-file-from-analysis
                              analysis-file)))
                    (prompts (tibetan-analysis--build-claude-prompts
                              tibetan-text src analysis-file))
                    (system-prompt (car prompts))
                    (user-prompt   (cdr prompts)))
               (gptel-request
                user-prompt
                :system system-prompt
                :callback
                (lambda (response info)
                  (cond
                   ;; Success: have a non-empty response body.
                   ((and response (stringp response)
                         (not (string-empty-p response)))
                    (condition-case e
                        (tibetan-analysis--insert-claude-translation
                         response analysis-file)
                      (error
                       (message "Claude insert failed for %s: %s"
                                (or label "<file>")
                                (error-message-string e))))
                    (funcall done '(:status ok)))
                   ;; HTTP 429 — let the queue retry.
                   ((tibetan-analysis--claude-status-rate-limited-p info)
                    (funcall done '(:status rate-limited)))
                   ;; Anything else — non-retryable from our point of view.
                   (t
                    (funcall done
                             (list :status 'error
                                   :error (format "%s"
                                                  (or (and (listp info)
                                                           (plist-get info :status))
                                                      "no response")))))))) ))
         (error
          (funcall done (list :status 'error
                              :error (error-message-string err))))))
     :label label
     :on-fail
     (lambda (status)
       (let* ((kind (plist-get status :status))
              (msg (cond
                    ((eq kind 'rate-limited)
                     "[Claude request failed: rate-limited (HTTP 429) after retries — re-run C-c u R later]")
                    (t (format "[Claude request failed: %s — re-run C-c u R later]"
                               (or (plist-get status :error) "unknown"))))))
         (tibetan-analysis--write-claude-failure-stub
          analysis-file msg))))))

(defun tibetan-analysis--parse-claude-sections (response)
  "Split RESPONSE on `## Translation/Vocabulary/Grammar/Context' markdown headings.
Returns a plist `(:translation STR :vocabulary STR :grammar STR :context STR)'.
Missing sections are nil (not empty string) so the writer can leave
the old org body in place when Claude omitted a section.  When
RESPONSE contains no recognised heading, the whole (trimmed) string is
returned as `:translation' — this keeps backwards compatibility with
legacy single-translation responses."
  (let ((result (list :translation nil :vocabulary nil :grammar nil :context nil))
        (re "^## \\(Translation\\|Vocabulary\\|Grammar\\|Context\\)[ \t]*$"))
    (when (and response (stringp response) (not (string-empty-p response)))
      (with-temp-buffer
        (insert response)
        (goto-char (point-min))
        (if (not (re-search-forward re nil t))
            ;; Legacy response — whole thing is the translation.
            (setq result (plist-put result :translation
                                    (string-trim response)))
          ;; Structured response — walk the headings.
          (goto-char (point-min))
          (let ((matches '()))
            (while (re-search-forward re nil t)
              (push (list (intern (downcase (match-string 1)))
                          (match-end 0))
                    matches))
            (setq matches (nreverse matches))
            (cl-loop for (cell . rest) on matches
                     for key = (car cell)
                     for start = (cadr cell)
                     for end = (if rest
                                   (save-excursion
                                     (goto-char (cadr (car rest)))
                                     (beginning-of-line)
                                     (point))
                                 (point-max))
                     for body = (string-trim
                                 (buffer-substring-no-properties
                                  start end))
                     do (setq result
                              (plist-put result
                                         (intern (format ":%s" key))
                                         (and (not (string-empty-p body))
                                              body))))))))
    result))

(defconst tibetan-analysis--claude-section-order
  '((:translation "Claude Translation" 2)
    (:vocabulary  "Claude Vocabulary"  3)
    (:grammar     "Claude Grammar"     2))
  "Canonical order, heading names, and org levels for Claude sections.
Each entry is (KEY HEADING LEVEL).  Translation and Grammar both
sit at level 2 so they can take their workshop-agreed slots in the
priority order (positions 6 and 7 in the per-segment auto-analysis
view).  Vocabulary stays at level 3 inside `** Provided
Translations' (it's a DharmaMitra-style word-by-word tier the
reader consults alongside the provided glosses).  The writer,
reader, scaffolding, and migration all consult this list so levels
stay consistent everywhere.")

(defun tibetan-analysis--claude-heading-re (heading level)
  "Regexp that anchors `HEADING' at org LEVEL at beginning-of-line."
  (format "^%s %s$"
          (regexp-quote (make-string level ?*))
          (regexp-quote heading)))

(defun tibetan-analysis--claude-stop-re (level)
  "Regexp matching the start of any heading at org LEVEL or shallower."
  ;; `*\\{1,N\\}' plus a mandatory non-`*' follower so `**' doesn't
  ;; match inside `***'.
  (format "^\\*\\{1,%d\\}[^*\n]" level))

(defun tibetan-analysis--claude-segment-layout-p (buffer)
  "Return non-nil if BUFFER uses the segment-level analysis layout.
The distinguishing marker is `** Wylie Transliteration' at org
level 2 — present in per-segment analysis files (seg-NNN*.org) but
not in sentence-level files (sent-NNN*.org), which use `* Wylie' at
level 1.  Empty / brand-new buffers default to segment layout so
fresh scaffolds get Translation promoted to level 2."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (or (re-search-forward "^\\*\\* Wylie Transliteration$" nil t)
          ;; Fresh scaffold not yet populated — treat as segment.
          (= (buffer-size) 0)))))

(defun tibetan-analysis--migrate-legacy-claude-headings (buffer)
  "Migrate legacy `*** Claude' / `*** Claude Translation' in BUFFER.
Segment-layout buffers (with `** Wylie Transliteration'):
1. Rename bare `*** Claude' → `*** Claude Translation'.
2. Move `*** Claude Translation' (level-3, legacy placement under
   `** Provided Translations') to a new `** Claude Translation'
   (level-2) directly after `** Wylie Transliteration', preserving
   its body.

Sentence-layout buffers (no `** Wylie Transliteration'):
1. Rename bare `*** Claude' → `*** Claude Translation'.
No level promotion — the sentence layout keeps Claude at level 3.

Both branches are no-ops when nothing to migrate."
  (with-current-buffer buffer
    (save-excursion
      ;; Step 1 (both layouts): bare `*** Claude' → `*** Claude Translation'
      (goto-char (point-min))
      (when (re-search-forward "^\\*\\*\\* Claude$" nil t)
        (replace-match "*** Claude Translation" t t))
      ;; Step 2 (segment only): promote level-3 Translation → level-2
      (when (tibetan-analysis--claude-segment-layout-p buffer)
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\* Claude Translation$" nil t))
          (goto-char (point-min))
          (when (re-search-forward "^\\*\\*\\* Claude Translation$" nil t)
            (let* ((heading-start (line-beginning-position))
                   (body-start (progn (forward-line 1) (point)))
                   (body-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 3) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (body (string-trim
                          (buffer-substring-no-properties body-start body-end))))
              (delete-region heading-start body-end)
              (tibetan-analysis--insert-claude-translation-heading
               (current-buffer) body))))))))

(defun tibetan-analysis--insert-claude-translation-heading (buffer body)
  "Insert `** Claude Translation' with BODY into BUFFER at the top.
Placement rule: right after `** Wylie Transliteration' and its body
if that heading exists; otherwise right after the first `* ' top-level
heading; otherwise at point-max.  BODY may be empty — the heading is
still created with two trailing newlines."
  (with-current-buffer buffer
    (save-excursion
      (let ((content (if (and body (not (string-empty-p (string-trim body))))
                         (format "** Claude Translation\n%s\n\n"
                                 (string-trim body))
                       "** Claude Translation\n\n\n")))
        (goto-char (point-min))
        (cond
         ;; Prefer: end of the ** Wylie Transliteration section
         ((re-search-forward "^\\*\\* Wylie Transliteration$" nil t)
          (forward-line 1)
          (if (re-search-forward
               (tibetan-analysis--claude-stop-re 2) nil t)
              (beginning-of-line)
            (goto-char (point-max)))
          (insert content))
         ;; Fallback: after the first top-level heading's opening line
         ((re-search-forward "^\\* " nil t)
          (forward-line 1)
          (insert content))
         (t
          (goto-char (point-max))
          (insert content)))))))

(defun tibetan-analysis--ensure-claude-headings (buffer)
  "Ensure the Claude Translation / Vocabulary / Grammar headings exist in BUFFER.

Segment-layout target (detected via `** Wylie Transliteration'):
  - `** Claude Translation'   at org level 2, right after Wylie.
  - `*** Claude Vocabulary'   at org level 3, inside
    `** Provided Translations' (after `*** DharmaMitra' if present).
  - `** Claude Grammar'       at org level 2, placed after
    `** Claude Translation' (the workshop-agreed priority order
    puts it at position 7 as a peer of Claude Translation).

Sentence-layout target (no `** Wylie Transliteration'):
  - `*** Claude Translation' at org level 3 (siblings under whatever
    parent the sentence scaffold provides).
  - `*** Claude Vocabulary'  at org level 3.
  - `*** Claude Grammar'     at org level 3.
  - `*** Claude Context'     at org level 3 — preserved for sentence
    files which still use the three/four-section layout.

Performs legacy-layout migration first (via
`tibetan-analysis--migrate-legacy-claude-headings'), then creates
whichever target heading is still missing.  Idempotent."
  (with-current-buffer buffer
    ;; Step 1 — migrate legacy layouts into the target shape.
    (tibetan-analysis--migrate-legacy-claude-headings buffer)
    (save-excursion
      (cond
       ;; -------------------------------------------------------------
       ;; SEGMENT LAYOUT: Translation at level 2, Vocab/Grammar at 3.
       ;; -------------------------------------------------------------
       ((tibetan-analysis--claude-segment-layout-p buffer)
        ;; Ensure `** Claude Translation' exists.
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\* Claude Translation$" nil t))
          (tibetan-analysis--insert-claude-translation-heading
           buffer nil))
        ;; Ensure `*** Claude Vocabulary' exists (before Grammar).
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\*\\* Claude Vocabulary$" nil t))
          (goto-char (point-min))
          (cond
           ;; Prefer: inside `** Provided Translations', after
           ;; `*** DharmaMitra' if present, else before Grammar.
           ((re-search-forward "^\\*\\* Provided Translations$" nil t)
            (let* ((section-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 2) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (mitra-end
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* DharmaMitra$" section-end t)
                        (forward-line 1)
                        (if (re-search-forward
                             (tibetan-analysis--claude-stop-re 3)
                             section-end t)
                            (line-beginning-position)
                          section-end))))
                   (grammar-pos
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* Claude Grammar$" section-end t)
                        (line-beginning-position))))
                   (ref-pos
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* Reference Translations$"
                             section-end t)
                        (line-beginning-position)))))
              (goto-char (or mitra-end grammar-pos ref-pos section-end))
              (insert "*** Claude Vocabulary\n\n\n")))
           ;; Fallback: after the Translation heading.
           (t
            (goto-char (point-min))
            (if (re-search-forward "^\\*\\* Claude Translation$" nil t)
                (progn
                  (forward-line 1)
                  (if (re-search-forward
                       (tibetan-analysis--claude-stop-re 2) nil t)
                      (beginning-of-line)
                    (goto-char (point-max)))
                  (insert "*** Claude Vocabulary\n\n\n"))
              (goto-char (point-max))
              (insert "\n*** Claude Vocabulary\n\n")))))
        ;; Ensure `** Claude Grammar' exists at level 2.  If a legacy
        ;; `*** Claude Grammar' is still present (file not yet
        ;; regenerated under the new layout), migrate it: promote the
        ;; heading to level 2 and move the body to sit right after
        ;; `** Claude Translation'.  Idempotent: if both exist, the
        ;; level-3 one is removed and its body folded into the level-2
        ;; one (last-writer wins — the usual Claude-response path).
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^\\*\\*\\* Claude Grammar$" nil t)
            (let* ((legacy-heading-start (line-beginning-position))
                   (legacy-body-start (progn (forward-line 1) (point)))
                   (legacy-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 3) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (legacy-body
                    (string-trim
                     (buffer-substring-no-properties legacy-body-start
                                                     legacy-end))))
              (delete-region legacy-heading-start legacy-end)
              ;; Stash body for the level-2 insertion below.
              (unless (save-excursion
                        (goto-char (point-min))
                        (re-search-forward "^\\*\\* Claude Grammar$" nil t))
                (goto-char (point-min))
                (if (re-search-forward "^\\*\\* Claude Translation$" nil t)
                    (progn
                      (forward-line 1)
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 2) nil t)
                          (beginning-of-line)
                        (goto-char (point-max)))
                      (insert "** Claude Grammar\n"
                              (if (string-empty-p legacy-body) "\n\n"
                                (concat legacy-body "\n\n"))))
                  (goto-char (point-max))
                  (insert "\n** Claude Grammar\n"
                          (if (string-empty-p legacy-body) "\n\n"
                            (concat legacy-body "\n\n"))))))))
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\* Claude Grammar$" nil t))
          (goto-char (point-min))
          ;; Place after `** Claude Translation' (the priority-ordered
          ;; position is right after it); fall back to end-of-buffer.
          (if (re-search-forward "^\\*\\* Claude Translation$" nil t)
              (progn
                (forward-line 1)
                (if (re-search-forward
                     (tibetan-analysis--claude-stop-re 2) nil t)
                    (beginning-of-line)
                  (goto-char (point-max)))
                (insert "** Claude Grammar\n\n\n"))
            (goto-char (point-max))
            (insert "\n** Claude Grammar\n\n"))))
       ;; -------------------------------------------------------------
       ;; SENTENCE / LEGACY LAYOUT: all four headings at level 3.
       ;; -------------------------------------------------------------
       (t
        (let ((prev "Claude Translation"))
          (dolist (heading '("Claude Translation" "Claude Vocabulary" "Claude Grammar" "Claude Context"))
            (unless (save-excursion
                      (goto-char (point-min))
                      (re-search-forward
                       (format "^\\*\\*\\* %s$" (regexp-quote heading))
                       nil t))
              (goto-char (point-min))
              (cond
               ;; Place after previous sibling if it exists.
               ((re-search-forward
                 (format "^\\*\\*\\* %s$" (regexp-quote prev)) nil t)
                (forward-line 1)
                (if (re-search-forward
                     (tibetan-analysis--claude-stop-re 3) nil t)
                    (beginning-of-line)
                  (goto-char (point-max)))
                (insert (format "*** %s\n\n\n" heading)))
               ;; No previous sibling — append at end of buffer.
               (t
                (goto-char (point-max))
                (insert (format "\n*** %s\n\n" heading)))))
            (setq prev heading))))))))

(defun tibetan-analysis--replace-claude-section-body
    (buffer heading body &optional level)
  "Replace the body under `HEADING' at org LEVEL in BUFFER with BODY.
LEVEL defaults to 3 for backwards compatibility.  Leaves the heading
itself in place; body is trimmed + terminated with one trailing blank
line."
  (let ((level (or level 3)))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward
               (tibetan-analysis--claude-heading-re heading level)
               nil t)
          (forward-line 1)
          (let ((start (point))
                (end (if (re-search-forward
                          (tibetan-analysis--claude-stop-re level) nil t)
                         (line-beginning-position)
                       (point-max))))
            (delete-region start end)
            (goto-char start)
            (insert (format "%s\n\n" (string-trim body)))))))))

(defun tibetan-analysis--claude-effective-section-order (buffer)
  "Return the layout-appropriate Claude section-order for BUFFER.

Segment layout (per-segment analysis files):
  `** Claude Translation' and `** Claude Grammar' both at level 2
  (the workshop-agreed priority slots), plus `*** Claude
  Vocabulary' at level 3 inside `** Provided Translations'.
  Context is dropped — the segment workflow is three-section only.

Sentence / legacy layout (sentence analysis files, or any buffer
without the segment-layout marker):
  Translation / Grammar / Context all at level 3 — preserves the
  existing sentence-level three-section workflow unchanged.

Callers that write Claude output (insert, restore) use this list so
a single buffer's layout drives heading levels consistently."
  (if (tibetan-analysis--claude-segment-layout-p buffer)
      tibetan-analysis--claude-section-order
    '((:translation "Claude Translation" 3)
      (:vocabulary  "Claude Vocabulary"  3)
      (:grammar     "Claude Grammar"     3)
      (:context     "Claude Context"     3))))

(defun tibetan-analysis--insert-claude-sections (response analysis-file)
  "Parse RESPONSE and write its sections into ANALYSIS-FILE.
RESPONSE is the raw markdown returned by Claude; it is split by
`tibetan-analysis--parse-claude-sections'.  Each section named in
the buffer's effective section-order (see
`tibetan-analysis--claude-effective-section-order') that the parser
filled in is written under its corresponding org heading at the
configured level.  Legacy `*** Claude' and `*** Claude Translation'
placements are migrated to the current two-section segment layout on
first write; sentence files keep the legacy three-section layout."
  (when (and response (file-exists-p analysis-file))
    (let* ((sections (tibetan-analysis--parse-claude-sections response))
           (buf (or (find-buffer-visiting analysis-file)
                    (find-file-noselect analysis-file))))
      (with-current-buffer buf
        (tibetan-analysis--ensure-claude-headings buf)
        (dolist (entry (tibetan-analysis--claude-effective-section-order buf))
          (let ((key (nth 0 entry))
                (heading (nth 1 entry))
                (level (nth 2 entry)))
            (when (plist-get sections key)
              (tibetan-analysis--replace-claude-section-body
               buf heading (plist-get sections key) level))))
        ;; Merge Claude Vocabulary into the Word / Particle List as
        ;; ◇ tier-2 lines beneath each matching entry.
        (when (plist-get sections :vocabulary)
          (tibetan-analysis--merge-claude-vocabulary
           buf (plist-get sections :vocabulary)))
        (save-buffer))
      (message "Claude sections inserted into %s"
               (file-name-nondirectory analysis-file)))))

;; ---------------------------------------------------------------------------
;; Claude Vocabulary → Word / Particle List merge
;; ---------------------------------------------------------------------------

(defun tibetan-analysis--parse-claude-vocabulary (vocab-text)
  "Parse VOCAB-TEXT (the `## Vocabulary' body) into an alist.
Each entry is (WYLIE-KEY . FULL-LINE) where WYLIE-KEY is the
lowercase, trimmed first field (before the first comma) and
FULL-LINE is the original line.  Blank lines and lines starting
with `---' are skipped."
  (let ((result '()))
    (when (and vocab-text (stringp vocab-text)
               (not (string-empty-p vocab-text)))
      (dolist (line (split-string vocab-text "\n" t))
        (let ((trimmed (string-trim line)))
          (unless (or (string-empty-p trimmed)
                      (string-prefix-p "---" trimmed))
            (when (string-match "\\`\\([^,]+\\)," trimmed)
              (let ((key (downcase (string-trim (match-string 1 trimmed)))))
                (push (cons key trimmed) result)))))))
    (nreverse result)))

(defun tibetan-analysis--merge-claude-vocabulary (buffer vocab-text)
  "Merge parsed Claude vocabulary lines into `** Word / Particle List' in BUFFER.
For each entry in the word list, looks up a matching Claude vocabulary
line (by Wylie key) and inserts it as a `    ◇ ...' tier-2 line
right after the existing gloss.  Existing ◇ lines are removed first
for idempotency.

VOCAB-TEXT is the raw body of the `## Vocabulary' / `*** Claude Vocabulary'
section.  When nil or empty, this function is a no-op."
  (when (and vocab-text (stringp vocab-text)
             (not (string-empty-p (string-trim vocab-text))))
    (let ((entries (tibetan-analysis--parse-claude-vocabulary vocab-text)))
      (when entries
        (with-current-buffer buffer
          (save-excursion
            (goto-char (point-min))
            (when (re-search-forward "^\\*\\* Word / Particle List$" nil t)
              (forward-line 1)
              (let ((section-end
                     (save-excursion
                       (if (re-search-forward
                            (tibetan-analysis--claude-stop-re 2) nil t)
                           (line-beginning-position)
                         (point-max)))))
                ;; Pass 1: strip existing ◇ lines (idempotent re-merge).
                (save-excursion
                  (while (re-search-forward "^    ◇ .*\n?" section-end t)
                    (replace-match "")
                    ;; Recalculate end after deletion.
                    (setq section-end
                          (save-excursion
                            (goto-char (point-min))
                            (if (and (re-search-forward
                                      "^\\*\\* Word / Particle List$" nil t)
                                     (forward-line 1)
                                     (re-search-forward
                                      (tibetan-analysis--claude-stop-re 2)
                                      nil t))
                                (line-beginning-position)
                              (point-max))))))
                ;; Pass 2: insert ◇ lines after matching entries.
                ;; Each word-list entry starts with " N." and has
                ;; a Wylie key in [brackets].  We use a marker for
                ;; section-end so insertions don't invalidate it.
                (goto-char (point-min))
                (re-search-forward "^\\*\\* Word / Particle List$" nil t)
                (forward-line 1)
                (let ((end-marker
                       (let ((pos (save-excursion
                                    (if (re-search-forward
                                         (tibetan-analysis--claude-stop-re 2)
                                         nil t)
                                        (line-beginning-position)
                                      (point-max)))))
                         (copy-marker pos))))
                  (while (re-search-forward
                          "^[ \t]*[0-9]+\\..*\\[\\([^]]+\\)\\]"
                          end-marker t)
                    (let* ((wylie-key (downcase
                                       (string-trim (match-string 1))))
                           (match (assoc wylie-key entries)))
                      (when match
                        ;; Find the end of this entry (next numbered
                        ;; line or section boundary).
                        (let ((entry-end
                               (save-excursion
                                 (forward-line 1)
                                 ;; Skip continuation lines (indented,
                                 ;; starting with spaces + text).
                                 (while (and (< (point) end-marker)
                                             (looking-at "^    "))
                                   (forward-line 1))
                                 (point))))
                          (goto-char entry-end)
                          (insert (format "    ◇ %s\n" (cdr match)))))))
                  (set-marker end-marker nil))))))))))

;; Backwards-compatible alias — callers outside this module may still
;; refer to the old one-section name.  New code should use
;; `tibetan-analysis--insert-claude-sections'.
(defalias 'tibetan-analysis--insert-claude-translation
  'tibetan-analysis--insert-claude-sections)
(defun tibetan-analysis--read-claude-section-body (filepath heading &optional level)
  "Return the non-placeholder body under `HEADING' in FILEPATH, or nil.
LEVEL is the org heading level to look for (defaults to 3 for
backwards compatibility).  When nil is passed explicitly as LEVEL,
the reader tries level 2 first and falls back to level 3 — this is
useful during the Claude Translation migration, when an old file may
still carry a level-3 heading.  Skips placeholder `[Requesting …]'
and known error markers so we don't re-persist dead content."
  (when (file-exists-p filepath)
    (let ((levels (cond
                   ((null level) '(2 3))
                   ((listp level) level)
                   (t (list level)))))
      (cl-loop for lvl in levels
               for body = (with-temp-buffer
                            (insert-file-contents filepath)
                            (goto-char (point-min))
                            (when (re-search-forward
                                   (tibetan-analysis--claude-heading-re
                                    heading lvl)
                                   nil t)
                              (forward-line 1)
                              (let* ((start (point))
                                     (end (save-excursion
                                            (if (re-search-forward
                                                 (tibetan-analysis--claude-stop-re
                                                  lvl)
                                                 nil t)
                                                (line-beginning-position)
                                              (point-max))))
                                     (b (string-trim
                                         (buffer-substring-no-properties
                                          start end))))
                                (unless
                                    (or (string-empty-p b)
                                        (string-match-p "\\`\\[Requesting" b)
                                        (string-match-p "\\`\\[Claude unavailable" b)
                                        (string-match-p "\\`\\[Claude request failed" b)
                                        (string-match-p "\\`\\[Translation not available" b))
                                  b))))
               when body return body))))

(defun tibetan-analysis--read-claude-sections (filepath)
  "Return preserved Claude content in FILEPATH as a plist.
Keys: `:translation', `:vocabulary', `:grammar', each a non-empty
string or nil.  Reads from the current layout (Translation and
Grammar at level 2; Vocabulary at level 3 inside Provided
Translations) and falls back to the legacy level-3 placements so
old analysis files do not lose their work on reanalysis.  A legacy
`*** Claude Context' body is still read when present and returned
as `:context' for round-trip safety, but it is never written back."
  (let ((translation
         (or
          ;; Current layout: level 2.
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Translation" 2)
          ;; Legacy level-3 placement.
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Translation" 3)
          ;; Pre-three-section legacy heading.
          (tibetan-analysis--read-claude-section-body
           filepath "Claude" 3)))
        (vocabulary (tibetan-analysis--read-claude-section-body
                     filepath "Claude Vocabulary" 3))
        (grammar
         (or
          ;; Current layout: level 2 (promoted out of Provided
          ;; Translations so it can take the priority slot).
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Grammar" 2)
          ;; Legacy level-3 placement inside Provided Translations.
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Grammar" 3)))
        ;; Preserve legacy Context body for round-trip safety; the
        ;; writer never emits a Context heading so this only surfaces
        ;; when an older analysis file still has one.
        (context (tibetan-analysis--read-claude-section-body
                  filepath "Claude Context" 3)))
    (list :translation translation
          :vocabulary  vocabulary
          :grammar     grammar
          :context     context)))

;; Backwards-compatible single-section reader — returns just the
;; translation body so legacy callers keep working.
(defun tibetan-analysis--read-claude-translation (filepath)
  "Return the preserved Claude translation in FILEPATH, or nil.
Legacy wrapper around `tibetan-analysis--read-claude-sections' that
returns only the `:translation' slot for callers that have not been
migrated yet."
  (plist-get (tibetan-analysis--read-claude-sections filepath) :translation))

(defun tibetan-analysis--restore-claude-sections (filepath sections)
  "Write SECTIONS (a plist) back into FILEPATH's Claude headings.
SECTIONS has keys :translation, :vocabulary, :grammar, and optionally
:context (legacy); any nil slot leaves the corresponding org body
untouched.  Creates the target headings (`** Claude Translation',
`*** Claude Vocabulary', `*** Claude Grammar') if they are missing,
migrating legacy layouts on first encounter.  A :context value is
only written when a `*** Claude Context' heading is already present
in the file — legacy files keep their Context body intact, but the
restore path will not create a new Context heading."
  (when (and sections (file-exists-p filepath))
    (let ((buf (find-file-noselect filepath)))
      (with-current-buffer buf
        (tibetan-analysis--ensure-claude-headings buf)
        (dolist (entry (tibetan-analysis--claude-effective-section-order buf))
          (let ((key (nth 0 entry))
                (heading (nth 1 entry))
                (level (nth 2 entry)))
            (when (plist-get sections key)
              (tibetan-analysis--replace-claude-section-body
               buf heading (plist-get sections key) level))))
        ;; Backwards-compatible :context round-trip for segment layout:
        ;; the effective section order drops :context for segment buffers,
        ;; but if a legacy `*** Claude Context' heading is present on disk
        ;; we preserve the body round-trip instead of silently dropping it.
        (when (and (plist-get sections :context)
                   (tibetan-analysis--claude-segment-layout-p buf))
          (save-excursion
            (goto-char (point-min))
            (when (re-search-forward "^\\*\\*\\* Claude Context$" nil t)
              (tibetan-analysis--replace-claude-section-body
               buf "Claude Context" (plist-get sections :context) 3))))
        ;; Merge Claude Vocabulary into the Word / Particle List as
        ;; ◇ tier-2 lines (same as the insert path).
        (when (plist-get sections :vocabulary)
          (tibetan-analysis--merge-claude-vocabulary
           buf (plist-get sections :vocabulary)))
        (save-buffer)))))

;; Backwards-compatible single-section restore — wraps the translation
;; string in a plist so old callers keep working.
(defun tibetan-analysis--restore-claude-translation (filepath translation)
  "Write TRANSLATION back under `*** Claude Translation' in FILEPATH.
Legacy wrapper around `tibetan-analysis--restore-claude-sections'."
  (tibetan-analysis--restore-claude-sections
   filepath (list :translation translation)))

(provide 'tibetan-analysis-claude)
;;; tibetan-analysis-claude.el ends here
