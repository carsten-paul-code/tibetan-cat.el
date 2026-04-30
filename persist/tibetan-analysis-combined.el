;;; tibetan-analysis-combined.el --- Combined-synthesis Claude pipeline -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Carsten Paul

;;; Commentary:
;;
;; Phase 4 of two-language-parallel-analysis (2026-04-30).
;;
;; The Combined-synthesis Claude call sits ABOVE the two
;; independent translations (Tibetan from
;; `persist/tibetan-analysis-claude.el', Sanskrit from
;; `persist/tibetan-analysis-sanskrit.el') and produces a single
;; justified translation drawing on BOTH sources, plus an
;; optional `## Divergence' note when there is a serious
;; Sanskrit-Tibetan difference.
;;
;; Smaller surface than the two raw-side modules:
;;
;;   tibetan-analysis-combined--build-prompts
;;       (SYSTEM . USER) for the combined call.  System block
;;       defines the comparative-reader role + target-lang;
;;       constant per document → caches.  User block carries
;;       both raw sources (Tib + Skt) AND both translations
;;       produced upstream by the two raw-side calls.
;;
;;   tibetan-analysis-combined--parse-claude-sections
;;       Splits a combined response on `## Translation' /
;;       `## Divergence'.  Both keys nullable; Divergence is
;;       opt-in (Claude emits it only when there is a serious
;;       difference).
;;
;;   tibetan-analysis-combined--insert-sections
;;       Writes parsed sections under `* Combined Analysis'
;;       (top-level).  Idempotent.
;;
;;   tibetan-analysis-combined--read-sections
;;   tibetan-analysis-combined--restore-sections
;;       Round-trip helpers for the reanalyse path.
;;
;;   tibetan-analysis-combined--needs-fire-p
;;       Predicate: both Tibetan and Sanskrit translations are
;;       present and non-empty.  Phase 5 dispatcher checks this
;;       before firing the Combined call.
;;
;;   tibetan-analysis-combined--request-synthesis
;;       Async fire.  Wired by Phase 5.
;;
;; Output goes under a TOP-LEVEL `* Combined Analysis' section
;; (peer of `* Auto-Analysis' / `* Sanskrit Analysis').  Same
;; independence pattern as the other two analyses.

;;; Code:

(require 'cl-lib)
(require 'tibetan-claude-queue nil t)
(require 'gptel nil t)

(defvar gptel-cache)
(declare-function gptel-request "gptel" (&optional prompt &rest args))
(declare-function tibetan-analysis--ensure-gptel-ready
                  "tibetan-analysis-claude" ())
(declare-function tibetan-analysis--read-source-metadata
                  "tibetan-analysis-claude" (source-file))

;; ============================================================================
;; PROMPT
;; ============================================================================

(defconst tibetan-analysis-combined--system-prompt-base
  "You are a comparative reader of parallel Sanskrit-Tibetan \
philological corpora, working with a graduate Yogācārabhūmi \
reading class.  You will receive both the Sanskrit (the canonical \
primary) and the Tibetan (the canonical translation) for one \
segment, plus the independent translations of each that another \
model produced.  Your job is to synthesise — produce a single \
best translation that honours both sources, and flag serious \
divergences.

Produce TWO sections (the second is conditional):

`## Translation'
  Your synthetic best reading.  When the two sources agree, \
  follow the agreed reading.  When they diverge, pick whichever \
  reading is better supported by the philological evidence and \
  the doctrinal context;  default to the Sanskrit when there is \
  no compelling reason otherwise.  This is the translation a \
  careful classroom reader would settle on after weighing both \
  sources — not a paraphrase, not a fusion, but a justified \
  single rendering.

`## Divergence'
  Emit ONLY when there is a SERIOUS Sanskrit-Tibetan difference \
  (the Tibetan translators glossed, collapsed, expanded, \
  reordered, or substituted in a way that matters for the \
  philosophical reading).  1–3 short bullets naming the \
  specific divergence(s); each names the Sanskrit term / \
  phrase, the Tibetan rendering, and the philological or \
  doctrinal consequence.  Omit the section entirely for \
  faithful renderings.  Do not invent divergences for trivial \
  word-order or particle-level differences.

Style notes:
  - Keep both sections terse;  this is a reference for a reader \
    who has the two raw translations already in front of them.
  - The user prompt below carries the two raw sources + the two \
    upstream translations.  Use them as the authoritative inputs.
"
  "Constant base for the Combined Claude system prompt.  Per-
document additions (target-lang directive, source genre) appended
at build time.  Constant per document → Anthropic-cache friendly.")

(defun tibetan-analysis-combined--build-prompts
    (tibetan-text sanskrit-plist tibetan-translation sanskrit-translation
                  source-file &optional _analysis-file)
  "Build (SYSTEM . USER) Claude prompts for the Combined call.

TIBETAN-TEXT, SANSKRIT-PLIST: the two raw sources for the segment.
TIBETAN-TRANSLATION, SANSKRIT-TRANSLATION: the bodies of the two
upstream Claude translations (strings).
SOURCE-FILE: source document (for metadata lookups).
ANALYSIS-FILE: reserved for future ±2 neighbour context.

Returns nil when any of:  tibetan-text empty, sanskrit-plist
nil / lacks IAST, either translation empty.  The Combined call
is meaningful only when all four inputs are present."
  (let* ((iast (and sanskrit-plist (plist-get sanskrit-plist :iast)))
         (devanagari (and sanskrit-plist
                          (plist-get sanskrit-plist :devanagari))))
    (when (and tibetan-text
               (stringp tibetan-text)
               (not (string-empty-p (string-trim tibetan-text)))
               iast (stringp iast) (not (string-empty-p (string-trim iast)))
               tibetan-translation
               (stringp tibetan-translation)
               (not (string-empty-p (string-trim tibetan-translation)))
               sanskrit-translation
               (stringp sanskrit-translation)
               (not (string-empty-p (string-trim sanskrit-translation))))
      (let* ((meta (and source-file
                        (fboundp 'tibetan-analysis--read-source-metadata)
                        (condition-case nil
                            (tibetan-analysis--read-source-metadata
                             source-file)
                          (error nil))))
             (target-lang-val (plist-get meta :target-lang))
             (target-lang-block
              (cond
               ((and target-lang-val (stringp target-lang-val)
                     (equal (downcase target-lang-val) "de"))
                (concat "\nTarget language for `## Translation': "
                        "GERMAN.  Divergence-note metalanguage stays "
                        "in English.\n"))
               (t "\nTarget language for `## Translation': English.\n")))
             (genre-blocks
              (and meta
                   (let ((claude-context
                          (plist-get meta :claude-context)))
                     (and claude-context
                          (concat
                           "\nDocument context (genre / register / "
                           "vocabulary):\n"
                           claude-context)))))
             (system (concat tibetan-analysis-combined--system-prompt-base
                             (or target-lang-block "")
                             (or genre-blocks "")))
             (user (concat
                    "Sanskrit (primary) — IAST:\n"
                    iast
                    "\n"
                    (when (and devanagari
                               (stringp devanagari)
                               (not (string-empty-p
                                     (string-trim devanagari))))
                      (format "Sanskrit (primary) — Devanagari:\n%s\n\n"
                              devanagari))
                    "\nTibetan (canonical translation):\n"
                    tibetan-text
                    "\n\n--- Upstream Sanskrit translation:\n"
                    sanskrit-translation
                    "\n\n--- Upstream Tibetan translation:\n"
                    tibetan-translation
                    "\n\nProduce the Combined-Analysis sections now.  "
                    "Skip `## Divergence' for faithful renderings.")))
        (cons system user)))))

;; ============================================================================
;; PARSER
;; ============================================================================

(defun tibetan-analysis-combined--parse-claude-sections (response)
  "Split a Combined Claude RESPONSE on `## Translation' /
`## Divergence' headings.

Returns a plist with `:translation' and `:divergence' keys.
Missing sections are nil; Divergence is opt-in (most segments
should have a faithful rendering and skip it)."
  (let ((result (list :translation nil :divergence nil))
        (re "^## \\(Translation\\|Divergence\\)[ \t]*$"))
    (when (and response (stringp response) (not (string-empty-p response)))
      (with-temp-buffer
        (insert response)
        (goto-char (point-min))
        (when (re-search-forward re nil t)
          (goto-char (point-min))
          (let ((matches '()))
            (while (re-search-forward re nil t)
              (push (list (intern (format ":%s"
                                          (downcase (match-string 1))))
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
                                         key
                                         (and (not (string-empty-p body))
                                              body))))))))
    result))

;; ============================================================================
;; SECTION ORDER + WRITER
;; ============================================================================

(defconst tibetan-analysis-combined--section-order
  '((:translation "Combined Translation" 2)
    (:divergence  "Divergence"            2))
  "Canonical order, heading names, levels for Combined sections
inside `* Combined Analysis'.  Both at level 2;  Divergence is
opt-in.")

(defun tibetan-analysis-combined--ensure-parent (buffer)
  "Ensure `* Combined Analysis' top-level heading exists in BUFFER.
Inserts at end of buffer when absent.  Idempotent."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (unless (re-search-forward "^\\* Combined Analysis$" nil t)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (unless (looking-back "\n\n" 2) (insert "\n"))
        (insert "* Combined Analysis\n"
                ":PROPERTIES:\n:GENERATED: t\n:END:\n\n")))))

(defun tibetan-analysis-combined--ensure-section (buffer heading)
  "Ensure HEADING (a level-2 string) exists inside `* Combined Analysis'
in BUFFER.  Idempotent."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((heading-re (format "^\\*\\* %s$" (regexp-quote heading))))
        (unless (re-search-forward heading-re nil t)
          (goto-char (point-min))
          (when (re-search-forward "^\\* Combined Analysis$" nil t)
            (forward-line 1)
            (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
              (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                (forward-line 1)))
            (if (re-search-forward "^\\* " nil t)
                (beginning-of-line)
              (goto-char (point-max)))
            (unless (looking-back "\n\n" 2) (insert "\n"))
            (insert "** " heading "\n\n\n")))))))

(defun tibetan-analysis-combined--replace-section-body (buffer heading body)
  "Replace the body under HEADING (a level-2 string) inside
`* Combined Analysis' in BUFFER with BODY."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((heading-re (format "^\\*\\* %s$" (regexp-quote heading))))
        (when (re-search-forward heading-re nil t)
          (forward-line 1)
          (let ((start (point))
                (end (if (re-search-forward "^\\*\\{1,2\\}[^*\n]" nil t)
                         (line-beginning-position)
                       (point-max))))
            (delete-region start end)
            (goto-char start)
            (insert (format "%s\n\n" (string-trim body)))))))))

(defun tibetan-analysis-combined--insert-sections (response analysis-file)
  "Parse a Combined Claude RESPONSE and write its sections into
ANALYSIS-FILE under `* Combined Analysis' (top-level).

Returns t on successful write, nil when no sections were
parsed or ANALYSIS-FILE is missing."
  (when (and response analysis-file (file-exists-p analysis-file))
    (let* ((sections (tibetan-analysis-combined--parse-claude-sections
                      response))
           (buf (or (find-buffer-visiting analysis-file)
                    (find-file-noselect analysis-file))))
      (with-current-buffer buf
        (when (cl-some (lambda (entry)
                         (plist-get sections (nth 0 entry)))
                       tibetan-analysis-combined--section-order)
          (tibetan-analysis-combined--ensure-parent buf)
          (dolist (entry tibetan-analysis-combined--section-order)
            (let ((key (nth 0 entry))
                  (heading (nth 1 entry)))
              (when (plist-get sections key)
                (tibetan-analysis-combined--ensure-section buf heading)
                (tibetan-analysis-combined--replace-section-body
                 buf heading (plist-get sections key)))))
          (save-buffer)
          t)))))

;; ============================================================================
;; READ + RESTORE
;; ============================================================================

(defun tibetan-analysis-combined--read-section-body (filepath heading)
  "Return the body under `** HEADING' inside `* Combined Analysis'
in FILEPATH."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Combined Analysis$" nil t)
        (let ((parent-end (save-excursion
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max)))))
          (when (re-search-forward
                 (format "^\\*\\* %s$" (regexp-quote heading))
                 parent-end t)
            (forward-line 1)
            (let* ((body-start (point))
                   (body-end
                    (or (save-excursion
                          (when (re-search-forward
                                 "^\\*\\{1,2\\}[^*\n]" parent-end t)
                            (line-beginning-position)))
                        parent-end))
                   (body (string-trim
                          (buffer-substring-no-properties
                           body-start body-end))))
              (and (not (string-empty-p body)) body))))))))

(defun tibetan-analysis-combined--read-sections (filepath)
  "Return preserved Combined-Claude content as a plist with
`:translation' / `:divergence' keys."
  (list :translation
        (tibetan-analysis-combined--read-section-body
         filepath "Combined Translation")
        :divergence
        (tibetan-analysis-combined--read-section-body
         filepath "Divergence")))

(defun tibetan-analysis-combined--restore-sections (filepath sections)
  "Write SECTIONS (a plist) back into FILEPATH's `* Combined
Analysis' section."
  (when (and sections (file-exists-p filepath))
    (let ((buf (find-file-noselect filepath)))
      (with-current-buffer buf
        (when (cl-some (lambda (entry)
                         (plist-get sections (nth 0 entry)))
                       tibetan-analysis-combined--section-order)
          (tibetan-analysis-combined--ensure-parent buf)
          (dolist (entry tibetan-analysis-combined--section-order)
            (let ((key (nth 0 entry))
                  (heading (nth 1 entry)))
              (when (plist-get sections key)
                (tibetan-analysis-combined--ensure-section buf heading)
                (tibetan-analysis-combined--replace-section-body
                 buf heading (plist-get sections key)))))
          (save-buffer)
          t)))))

;; ============================================================================
;; PREDICATES + ASYNC FIRE
;; ============================================================================

(defun tibetan-analysis-combined--needs-fire-p
    (tibetan-text sanskrit-plist tibetan-translation sanskrit-translation)
  "Return non-nil when the Combined call has all four inputs and
should be fired.  All four must be non-empty strings (with
SANSKRIT-PLIST carrying a non-empty `:iast')."
  (and tibetan-text
       (stringp tibetan-text)
       (not (string-empty-p (string-trim tibetan-text)))
       sanskrit-plist
       (let ((iast (plist-get sanskrit-plist :iast)))
         (and iast (stringp iast)
              (not (string-empty-p (string-trim iast)))))
       tibetan-translation
       (stringp tibetan-translation)
       (not (string-empty-p (string-trim tibetan-translation)))
       sanskrit-translation
       (stringp sanskrit-translation)
       (not (string-empty-p (string-trim sanskrit-translation)))
       t))

;;;###autoload
(defun tibetan-analysis-combined--request-synthesis
    (tibetan-text sanskrit-plist tibetan-translation sanskrit-translation
                  source-file analysis-file &optional callback)
  "Fire an async Combined Claude call.

On response, parses sections + writes them under `* Combined
Analysis' in ANALYSIS-FILE.  CALLBACK (if non-nil) is called
with one arg — the parsed plist — after the write.

No-op when `--needs-fire-p' returns nil or gptel is missing."
  (when (and (tibetan-analysis-combined--needs-fire-p
              tibetan-text sanskrit-plist
              tibetan-translation sanskrit-translation)
             (fboundp 'gptel-request)
             (fboundp 'tibetan-analysis--ensure-gptel-ready))
    (tibetan-analysis--ensure-gptel-ready)
    (let ((prompts (tibetan-analysis-combined--build-prompts
                    tibetan-text sanskrit-plist
                    tibetan-translation sanskrit-translation
                    source-file analysis-file)))
      (when prompts
        (let ((gptel-cache '(system)))
          (gptel-request
           (cdr prompts)
           :system (car prompts)
           :callback
           (lambda (response _info)
             (when (and response (stringp response))
               (let ((parsed
                      (tibetan-analysis-combined--parse-claude-sections
                       response)))
                 (tibetan-analysis-combined--insert-sections
                  response analysis-file)
                 (when callback (funcall callback parsed)))))))))))

(provide 'tibetan-analysis-combined)
;;; tibetan-analysis-combined.el ends here
