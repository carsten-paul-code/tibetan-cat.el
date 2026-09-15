;;; tibetan-translation-doc.el --- Stitch the user's translation out of cascade files -*- lexical-binding: t -*-

;;; Commentary:
;; Masterarbeit three-view plan (2026-09-15), view 3:  Carsten's own
;; German translation lives SENTENCE-WISE in the cascade analysis
;; files — `* Working Translation' carries the prose (with named org
;; footnote anchors `[fn:name]'), `* Footnotes' the definitions (the
;; §184-handout convention).  This module GENERATES the deliverable
;; views out of those slots:
;;
;;   - `tibetan-translation-doc-build' — the continuous translation
;;     document (§-grouped, footnotes namespaced per sentence and
;;     collected at the end), e.g. §§182–186 for thesis appendix A.1.
;;   - `tibetan-translation-doc-section-view' — one compiled per-§
;;     view (Tibetan + gloss tables + Claude/DM suggestions + his
;;     translation) for consultations and reading classes.
;;
;; Both outputs are GENERATED artifacts: a marker line in the header
;; identifies them, regeneration overwrites only marked files (never
;; a hand-owned document), and they contain ONLY Carsten's own text
;; plus tool output — the Lopez / Wangjié&Mulligan reference
;; translations are copyright-restricted and never leave the
;; comparative documents (they reach Claude prompt-only; see
;; `tibetan-cascade--section-refs-block').

;;; Code:

(require 'cl-lib)
;; The L1 body reader (Working Translation / Footnotes) lives with
;; the cascade machinery.  Soft — callers are fboundp-guarded.
(require 'tibetan-cascade nil t)

(declare-function tibetan-cascade--read-l1-body "tibetan-cascade"
                  (file heading))
(declare-function tibetan-sentence--filepath "tibetan-sentence-persist"
                  (sent-num &optional folder source-file))
(declare-function tibetan-sentence--source-file-from-analysis
                  "tibetan-sentence-persist" (filepath))
(declare-function tibetan-sentence--read-l2-body "tibetan-sentence-persist"
                  (file heading))
(declare-function tibetan-cascade--read-gloss-tables "tibetan-cascade"
                  (file))

(defun tibetan-translation-doc--source-outline (source-file)
  "Ordered §-outline of the cascade SOURCE-FILE.
Returns a list of plists (:lopez N :sent-nums (N1 N2 …)) — one per
`** Section' heading, N from the section drawer's :LOPEZ_SECTION:
property (nil when the drawer lacks it), sentence numbers from the
child `*** Sentence N' headings in file order.  Sentences BEFORE
any Section land in a leading (:lopez nil …) group.  nil when the
file has no sentences."
  (when (and source-file (stringp source-file)
             (file-exists-p source-file))
    (with-temp-buffer
      (insert-file-contents source-file)
      (goto-char (point-min))
      (let ((groups nil)          ; reversed list of (LOPEZ . REV-SENTS)
            (current nil))        ; the open group, or nil before any
        (while (re-search-forward
                (concat "^\\(?:\\*\\{1,2\\} Section\\b.*\\)$"
                        "\\|^:LOPEZ_SECTION:[ \t]+\\([0-9]+\\)[ \t]*$"
                        "\\|^\\*\\{3\\} Sentence[ \t]+\\([0-9]+\\)\\b")
                nil t)
          (cond
           ((match-string 1)              ; drawer property of the
            (when current                 ; just-opened Section
              (setcar current (string-to-number (match-string 1)))))
           ((match-string 2)              ; a Sentence heading
            (unless current
              (setq current (cons nil nil))
              (push current groups))
            (setcdr current (cons (string-to-number (match-string 2))
                                  (cdr current))))
           (t                             ; a Section heading
            (setq current (cons nil nil))
            (push current groups))))
        (let (out)
          (dolist (g groups)
            (when (cdr g)                 ; drop sentence-less Sections
              (push (list :lopez (car g)
                          :sent-nums (nreverse (cdr g)))
                    out)))
          out)))))

(defun tibetan-translation-doc--working-translation (file)
  "FILE's `* Working Translation' body (trimmed), nil when empty."
  (and (fboundp 'tibetan-cascade--read-l1-body)
       (tibetan-cascade--read-l1-body file "Working Translation")))

(defun tibetan-translation-doc--footnote-definitions (file)
  "FILE's `* Footnotes' body verbatim (edge-trimmed), nil when empty."
  (and (fboundp 'tibetan-cascade--read-l1-body)
       (tibetan-cascade--read-l1-body file "Footnotes")))

(defun tibetan-translation-doc--namespace-footnotes (text prefix)
  "TEXT with every named org footnote label PREFIXed.
Rewrites `[fn:LABEL]' anchors, `[fn:LABEL] Definition' labels and
inline `[fn:LABEL:def]' forms to `[fn:PREFIXLABEL…]' — ONE regex
covers all three, because the label is always followed by `]' or
`:'.  Anonymous inline footnotes `[fn::…]' (empty label) stay
untouched.  Namespacing per sentence file (PREFIX like \"s012-\")
keeps labels collision-free when many files stitch into one
document."
  (replace-regexp-in-string
   "\\[fn:\\([-_[:alnum:]]+\\)\\([]:]\\)"
   (concat "[fn:" prefix "\\1\\2")
   (or text "") t))

(defconst tibetan-translation-doc-generated-marker
  "# GENERATED by tibetan-translation-doc — NICHT VON HAND EDITIEREN"
  "First line of every generated document.  The overwrite guard
refuses any existing target that lacks this marker, so a
hand-owned file can never be clobbered by a regeneration.")

(defconst tibetan-translation-doc-empty-placeholder "[Satz %d — noch keine Übersetzung]"
  "Visible placeholder for a sentence whose Working Translation is
still empty — gaps must be obvious in the stitched document.")

(defconst tibetan-translation-doc-missing-placeholder "[Satz %d — Analysedatei fehlt]"
  "Visible placeholder for a sentence without an analysis file.")

(defun tibetan-translation-doc--generated-file-p (file)
  "Non-nil when FILE starts with the GENERATED marker."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file nil 0 512)
      (goto-char (point-min))
      (looking-at-p (regexp-quote tibetan-translation-doc-generated-marker)))))

(defun tibetan-translation-doc-build (source-file output-file
                                                  &optional from-sec to-sec)
  "Stitch Carsten's translation out of SOURCE-FILE's sent files.
Walks the §-outline of the cascade SOURCE-FILE, reads each
sentence's `* Working Translation' and `* Footnotes' from its
analysis file (suffix-aware resolution), namespaces the footnotes
per sentence (s%03d-) and writes OUTPUT-FILE: a GENERATED,
§-grouped org document — flowing German under `* §NNN' headings,
one collected `* Footnotes' at the end.  FROM-SEC/TO-SEC restrict
to a §-range (e.g. 182–186 for thesis appendix A.1); the pre-§
group is included only without a range.  Empty slots render the
visible `[Satz N — noch keine Übersetzung]' placeholder, missing
files `[Satz N — Analysedatei fehlt]'.  Refuses to overwrite an
existing OUTPUT-FILE that lacks the GENERATED marker.  Contains
ONLY Carsten's own text — reference translations (Lopez / W&M)
never reach generated documents.  Returns OUTPUT-FILE."
  (let* ((outline (tibetan-translation-doc--source-outline source-file))
         (folder (expand-file-name "analysis"
                                   (file-name-directory source-file)))
         (range-p (or from-sec to-sec))
         (groups (cl-remove-if-not
                  (lambda (g)
                    (let ((l (plist-get g :lopez)))
                      (if range-p
                          (and l
                               (or (null from-sec) (>= l from-sec))
                               (or (null to-sec) (<= l to-sec)))
                        t)))
                  outline)))
    (unless groups
      (user-error "Keine Sätze im gewählten §-Bereich"))
    (when (and (file-exists-p output-file)
               (not (tibetan-translation-doc--generated-file-p
                     output-file)))
      (user-error
       "%s existiert und trägt keinen GENERATED-Marker — nicht überschrieben"
       (file-name-nondirectory output-file)))
    (let* ((secs (delq nil (mapcar (lambda (g) (plist-get g :lopez))
                                   groups)))
           (range-label
            (cond ((null secs) "")
                  ((= (apply #'min secs) (apply #'max secs))
                   (format "§%d" (car secs)))
                  (t (format "§§%d–%d"
                             (apply #'min secs) (apply #'max secs)))))
           (parts nil)
           (fn-blocks nil))
      (dolist (g groups)
        (push (format "* %s\n"
                      (if (plist-get g :lopez)
                          (format "§%d" (plist-get g :lopez))
                        "(ohne §-Zuordnung)"))
              parts)
        (dolist (n (plist-get g :sent-nums))
          (let* ((prefix (format "s%03d-" n))
                 (file (and (fboundp 'tibetan-sentence--filepath)
                            (tibetan-sentence--filepath
                             n folder source-file))))
            (if (or (null file) (not (file-exists-p file)))
                (push (concat (format
                               tibetan-translation-doc-missing-placeholder
                               n)
                              "\n\n")
                      parts)
              (let ((wt (tibetan-translation-doc--working-translation
                         file))
                    (fns (tibetan-translation-doc--footnote-definitions
                          file)))
                (push (concat
                       (if wt
                           (tibetan-translation-doc--namespace-footnotes
                            wt prefix)
                         (format
                          tibetan-translation-doc-empty-placeholder n))
                       "\n\n")
                      parts)
                (when fns
                  (push (tibetan-translation-doc--namespace-footnotes
                         fns prefix)
                        fn-blocks)))))))
      (with-temp-file output-file
        (insert tibetan-translation-doc-generated-marker "\n"
                (format "# Quelle: %s · regenerieren: M-x tibetan-translation-doc\n"
                        (file-name-nondirectory source-file))
                (format "# Generiert: %s\n"
                        (format-time-string "%Y-%m-%d"))
                (format "#+TITLE: Übersetzung %s\n"
                        (if (string-empty-p range-label)
                            (file-name-base source-file)
                          range-label))
                "#+LANGUAGE: de\n"
                "#+OPTIONS: toc:nil num:nil\n\n")
        (dolist (p (nreverse parts))
          (insert p))
        (when fn-blocks
          (insert "* Footnotes\n\n"
                  (string-join (nreverse fn-blocks) "\n\n")
                  "\n"))))
    output-file))

(defun tibetan-translation-doc-section-view (source-file par
                                                         &optional
                                                         output-file)
  "Compile the generated §-view for Lopez-§ PAR of SOURCE-FILE.
The consultation/reading-class sheet (par-184-handout spirit, but
GENERATED): one `* §PAR' with, per sentence, `** Satz N' carrying
`*** Tibetisch' (the sent file's Tibetan), `*** Glossentabellen'
\(the file's CURRENT `** Gloss Tables' body verbatim — Carsten's
edited tables flow into the view), `*** Vorschlag Claude' /
`*** Vorschlag DharmaMitra' (the suggestion bodies, omitted when
absent) and `*** Übersetzung CP' (his Working Translation, the
visible placeholder when empty).  Sentence footnotes are
namespaced and collected under one trailing `* Footnotes' so the
sheet exports cleanly.  Writes OUTPUT-FILE (default
`par-NNN-ansicht.org' beside the sent files — deliberately NOT
colliding with hand-owned par-NNN-handout files), guarded by the
GENERATED marker like `tibetan-translation-doc-build'.  Reference
translations (Lopez / W&M) never appear.  Returns the file."
  (let* ((outline (tibetan-translation-doc--source-outline source-file))
         (group (cl-find par outline
                         :key (lambda (g) (plist-get g :lopez))))
         (folder (expand-file-name "analysis"
                                   (file-name-directory source-file)))
         (out (or output-file
                  (expand-file-name (format "par-%03d-ansicht.org" par)
                                    folder))))
    (unless group
      (user-error "§%s hat keine Sätze in %s" par
                  (file-name-nondirectory source-file)))
    (when (and (file-exists-p out)
               (not (tibetan-translation-doc--generated-file-p out)))
      (user-error
       "%s existiert und trägt keinen GENERATED-Marker — nicht überschrieben"
       (file-name-nondirectory out)))
    (let ((machine-body-re "\\`\\[\\(?:Requesting\\|Awaiting\\)")
          (parts nil)
          (fn-blocks nil))
      (dolist (n (plist-get group :sent-nums))
        (let* ((prefix (format "s%03d-" n))
               (file (and (fboundp 'tibetan-sentence--filepath)
                          (tibetan-sentence--filepath
                           n folder source-file))))
          (push (format "** Satz %d\n" n) parts)
          (if (or (null file) (not (file-exists-p file)))
              (push (concat (format
                             tibetan-translation-doc-missing-placeholder
                             n)
                            "\n\n")
                    parts)
            (let* ((tib (and (fboundp 'tibetan-cascade--read-l1-body)
                             (tibetan-cascade--read-l1-body
                              file "Tibetan Text")))
                   (tables (and (fboundp 'tibetan-cascade--read-gloss-tables)
                                (car (tibetan-cascade--read-gloss-tables
                                      file))))
                   (claude (and (fboundp 'tibetan-sentence--read-l2-body)
                                (tibetan-sentence--read-l2-body
                                 file "Translation")))
                   (dm (and (fboundp 'tibetan-sentence--read-l2-body)
                            (tibetan-sentence--read-l2-body
                             file "DharmaMitra Translation")))
                   (wt (tibetan-translation-doc--working-translation
                        file))
                   (fns (tibetan-translation-doc--footnote-definitions
                         file)))
              (when tib
                (push (concat "*** Tibetisch\n" tib "\n\n") parts))
              (when (and tables (not (string-empty-p tables)))
                (push (concat "*** Glossentabellen\n" tables "\n\n")
                      parts))
              ;; Suggestions: only real content — the machine
              ;; placeholders ([Requesting…]/[Awaiting…]) are noise
              ;; on a consultation sheet.  Prefix-gated only (a real
              ;; rendering may open with an editorial bracket — the
              ;; §5.40 lesson).
              (when (and claude
                         (not (string-match-p machine-body-re claude)))
                (push (concat "*** Vorschlag Claude\n" claude "\n\n")
                      parts))
              (when (and dm (not (string-match-p machine-body-re dm)))
                (push (concat "*** Vorschlag DharmaMitra\n" dm "\n\n")
                      parts))
              (push (concat "*** Übersetzung CP\n"
                            (if wt
                                (tibetan-translation-doc--namespace-footnotes
                                 wt prefix)
                              (format
                               tibetan-translation-doc-empty-placeholder
                               n))
                            "\n\n")
                    parts)
              (when fns
                (push (tibetan-translation-doc--namespace-footnotes
                       fns prefix)
                      fn-blocks))))))
      (with-temp-file out
        (insert tibetan-translation-doc-generated-marker "\n"
                (format "# Quelle: %s · regenerieren: M-x tibetan-translation-doc-section\n"
                        (file-name-nondirectory source-file))
                (format "# Generiert: %s\n"
                        (format-time-string "%Y-%m-%d"))
                (format "#+TITLE: §%d — Ansicht\n" par)
                "#+LANGUAGE: de\n"
                "#+OPTIONS: toc:nil num:nil\n\n"
                (format "* §%d\n" par))
        (dolist (p (nreverse parts))
          (insert p))
        (when fn-blocks
          (insert "* Footnotes\n\n"
                  (string-join (nreverse fn-blocks) "\n\n")
                  "\n"))))
    out))

;;;###autoload
(defun tibetan-translation-doc-section (par)
  "Generate the §-view sheet for Lopez-§ PAR (with completion) and
open it — the consultation / reading-class artifact."
  (interactive
   (let* ((source (tibetan-translation-doc--context-source))
          (outline (tibetan-translation-doc--source-outline source))
          (pars (delq nil (mapcar (lambda (g) (plist-get g :lopez))
                                  outline))))
     (unless pars
       (user-error "Keine §§ in %s" (file-name-nondirectory source)))
     (list (string-to-number
            (completing-read "§: " (mapcar #'number-to-string pars)
                             nil t)))))
  (let ((out (tibetan-translation-doc-section-view
              (tibetan-translation-doc--context-source) par)))
    (find-file out)
    (message "§-Ansicht generiert: %s" (file-name-nondirectory out))
    out))

(defun tibetan-translation-doc--context-source ()
  "The cascade source for the current buffer: an analysis buffer
resolves via its #+SOURCE link, anything else is taken as the
source itself; no file → prompt."
  (let ((f (buffer-file-name)))
    (cond
     ((and f
           (string-match-p "\\`sent-[0-9]"
                           (file-name-nondirectory f))
           (fboundp 'tibetan-sentence--source-file-from-analysis))
      (or (tibetan-sentence--source-file-from-analysis f) f))
     (f f)
     (t (read-file-name "Quelldokument: ")))))

;;;###autoload
(defun tibetan-translation-doc (&optional from-sec to-sec)
  "Generate the stitched translation document for this corpus.
Interactively prompts for an optional §-range (empty = whole
corpus); works from the source buffer or any sent-analysis
buffer.  Output lands beside the analysis files as
`uebersetzung[-FROM-TO].org' and is opened for review; export via
\\[tibetan-export-any-org-to-pdf]."
  (interactive
   (let ((from (read-string "Von § (leer = alle): "))
         (to nil))
     (unless (string-empty-p from)
       (setq to (read-string (format "Bis § (leer = nur §%s): " from))))
     (list (and from (not (string-empty-p from))
                (string-to-number from))
           (cond ((and to (not (string-empty-p to)))
                  (string-to-number to))
                 ((and from (not (string-empty-p from)))
                  (string-to-number from))))))
  (let* ((source (tibetan-translation-doc--context-source))
         (folder (expand-file-name "analysis"
                                   (file-name-directory source)))
         (output (expand-file-name
                  (cond ((and from-sec to-sec (/= from-sec to-sec))
                         (format "uebersetzung-%d-%d.org"
                                 from-sec to-sec))
                        (from-sec (format "uebersetzung-%d.org" from-sec))
                        (t "uebersetzung.org"))
                  folder)))
    (tibetan-translation-doc-build source output from-sec to-sec)
    (find-file output)
    (message "Übersetzungsdokument generiert: %s"
             (file-name-nondirectory output))
    output))

(provide 'tibetan-translation-doc)

;;; tibetan-translation-doc.el ends here
