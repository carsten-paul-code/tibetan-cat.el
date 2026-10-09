;;; tibetan-handout.el --- Printable reading-class handout from cascade files -*- lexical-binding: t -*-

;;; Commentary:
;; §5.59 (2026-10-09): Carsten works in the reading classes with a
;; printed sheet next to the class text — quick look-up plus room
;; for handwritten notes.  Per sentence of a § (or any org subtree of
;; a cascade source): the full Wylie (Uchen above it), the
;; translation, the vocabulary (★ class wordlist first, the context
;; gloss small behind it only where it differs) and the grammar
;; (only the labels Carsten reads in class).  Output is a GENERATED,
;; editable .org file (strike vocabulary before printing) exported
;; to PDF via LuaLaTeX.
;;
;; Layering: the DATA layer (`tibetan-handout--sentence-data') reads
;; the cascade sentence files; the RENDERER turns the data into org;
;; the COMMAND resolves the scope at point, writes the file and
;; builds the PDF.  Reference translations (Lopez / W&M), DharmaMitra
;; and Carsten's own Working Translation never appear — the handout
;; reads only the tool's Translation/Vocabulary/Grammar slots.

;;; Code:

(require 'cl-lib)
(require 'tibetan-wylie)
(require 'tibetan-vocabulary)
(require 'tibetan-analysis-claude)
(require 'tibetan-sanskrit-reading)
(require 'tibetan-cascade)
(require 'tibetan-translation-doc)

;; ============================================================================
;; B1 — data layer
;; ============================================================================

(defun tibetan-handout--vocab-fields (line)
  "Split a comma-format vocabulary LINE (`term, pos, \"gloss\", note').
Returns (:term :pos :gloss :skt) — of the note only the Sanskrit
equivalent (`Skt. *x*') survives; the handout is a look-up sheet.
A leading list bullet (C6a model drift) is tolerated; a line
without a quoted gloss takes the third comma field.  nil for blank,
`---' or comma-less lines."
  (let ((l (string-trim (replace-regexp-in-string
                         "\\`[ \t]*[-*][ \t]+" "" (or line "")))))
    (unless (or (string-empty-p l) (string-prefix-p "---" l)
                (not (string-match-p "," l)))
      (let (term pos gloss note)
        (if (string-match
             (concat "\\`\\([^,]+\\),[ \t]*\\(.*?\\),?[ \t]*[\"“]"
                     "\\([^\"”]*\\)[\"”]\\(?:[ \t]*,[ \t]*\\(.*\\)\\)?\\'")
             l)
            (setq term (match-string 1 l) pos (match-string 2 l)
                  gloss (match-string 3 l) note (match-string 4 l))
          (let ((fields (mapcar #'string-trim (split-string l ","))))
            (setq term (nth 0 fields)
                  pos (or (nth 1 fields) "")
                  gloss (mapconcat #'identity (nthcdr 2 fields) ", "))))
        (list :term (string-trim term)
              :pos (string-trim (or pos ""))
              :gloss (string-trim (or gloss ""))
              :skt (and note
                        (cond
                         ((string-match "Skt\\.[ \t]+\\*\\([^*]+\\)\\*" note)
                          (string-trim (match-string 1 note)))
                         ((string-match "Skt\\.[ \t]+\\([^;,()]+\\)" note)
                          (string-trim (match-string 1 note))))))))))

(defvar tibetan-handout--particle-syllables nil
  "Cache of `tibetan-handout--particle-syllables'.")

(defun tibetan-handout--particle-syllables ()
  "Wylie particle SYLLABLES a vocabulary term may end with (`yin pas').
Derived ONCE from the tool's case/converb tail list
\(`tibetan-extract-vocab--particle-tails') — no parallel list.  The
one-letter clitics come out as `ra'/`sa'/`'i' and are excluded: as
a syllable `sa' is the noun \"earth\"; the clitics are handled by
the part-of-speech-gated rules instead."
  (or tibetan-handout--particle-syllables
      (setq tibetan-handout--particle-syllables
            (cl-set-difference
             (delq nil (mapcar (lambda (p)
                                 (ignore-errors
                                   (string-trim (tibetan-to-wylie-fixed p))))
                               tibetan-extract-vocab--particle-tails))
             '("ra" "sa" "'i")
             :test #'equal))))

(defconst tibetan-handout--clitic-pos-rules
  '(("'ang" . "concessive\\|emphatic")
    ("'is" . "ergative\\|instrumental\\|agentive")
    ("'i" . "genitive")
    ("'o" . "final\\|declarative\\|assertive")
    ("s" . "ergative\\|instrumental\\|agentive")
    ("r" . "terminative\\|dative\\|locative"))
  "Merged clitics the ★ lookup may strip — each ONLY when Claude's
part of speech names its function (longest first).  `blos'
\(ergative/instrumental) → `blo'; `rgyas' as a verb never becomes
`rgya' — a blind s-strip would hand a wrong wordlist meaning.")

(defun tibetan-handout--curated-gloss (term pos)
  "The class-wordlist (★) entry for vocabulary TERM, or nil.
Probes `tibetan-vocab--curated-exact-entry' (Resources + Custom as
currently bound): TERM exactly; TERM minus a trailing particle
syllable (`yin pas' → `yin'); TERM minus a merged clitic licensed by
POS (`tibetan-handout--clitic-pos-rules').  Returns the entry
verbatim — the bilingual DE // EN pair is never collapsed."
  (let ((term (string-trim (or term "")))
        (pos (downcase (or pos ""))))
    (unless (string-empty-p term)
      (or (tibetan-vocab--curated-exact-entry term)
          (let ((syls (split-string term " " t)))
            (when (and (> (length syls) 1)
                       (member (car (last syls))
                               (tibetan-handout--particle-syllables)))
              (tibetan-vocab--curated-exact-entry
               (mapconcat #'identity (butlast syls) " "))))
          (cl-loop for (clitic . pos-re) in tibetan-handout--clitic-pos-rules
                   when (and (string-suffix-p clitic term)
                             (> (length term) (length clitic))
                             (string-match-p pos-re pos))
                   thereis (let ((base (string-trim-right
                                        (substring term 0 (- (length term)
                                                             (length clitic))))))
                             (and (not (string-empty-p base))
                                  (tibetan-vocab--curated-exact-entry base))))))))

(defun tibetan-handout--gloss-alternatives (gloss)
  "GLOSS split into normalized alternatives (both language halves)."
  (delete ""
          (mapcar (lambda (a)
                    (downcase (string-trim
                               (replace-regexp-in-string "[\"“”„…]" "" a))))
                  (split-string (or gloss "") "//\\|[/;,]"))))

(defun tibetan-handout--context-differs-p (context curated)
  "Non-nil when the CONTEXT gloss adds something to the ★ CURATED
entry: some alternative of CONTEXT is not among CURATED's
alternatives (Carsten 09.10.: the context gloss stands small behind
the ★ meaning, but only where it differs)."
  (and context curated
       (let ((cur (tibetan-handout--gloss-alternatives curated)))
         (cl-some (lambda (a) (not (member a cur)))
                  (tibetan-handout--gloss-alternatives context)))))

(defcustom tibetan-handout-grammar-labels
  '("Verb backbone" "Notable constructions")
  "Grammar bullet labels the handout keeps (case-insensitive).
A segment whose grammar carries NONE of them keeps all its bullets —
the filter never empties a segment (the Sanskrit schema has free
labels)."
  :type '(repeat string)
  :group 'tibetan-cat)

(defun tibetan-handout--grammar-bullets (text)
  "Labelled grammar bullets of one segment's TEXT: ((LABEL . BODY) …).
Bullets look like `- *Label:* body' (also `**Label:**'); indented
continuation lines join their bullet.  Only labels from
`tibetan-handout-grammar-labels' survive — unless NONE of them occurs,
then every bullet stays (the filter never empties a segment).  Text
without labelled bullets comes back as ((nil . PROSE))."
  (when (and text (not (string-empty-p (string-trim text))))
    (let ((items '()) (label nil) (body nil) (prose '()))
      (cl-flet ((flush ()
                  (when body
                    (push (cons label (string-trim body)) items))
                  (setq label nil body nil)))
        (dolist (line (split-string text "\n"))
          (cond
           ((string-match (concat "\\`[ \t]*[-+][ \t]+\\*\\{1,2\\}\\([^*\n]+?\\)"
                                  ":?\\*\\{1,2\\}:?[ \t]*\\(.*\\)\\'")
                          line)
            (flush)
            (setq label (string-trim (match-string 1 line) nil ":[ \t]*")
                  body (match-string 2 line)))
           ((string-match "\\`[ \t]*[-+][ \t]+\\(.*\\)\\'" line)
            (flush)
            (setq body (match-string 1 line)))
           ((string-empty-p (string-trim line))
            (flush))
           (body
            (setq body (concat body " " (string-trim line))))
           (t (push (string-trim line) prose))))
        (flush))
      (setq items (nreverse items))
      (if (null items)
          (and prose
               (list (cons nil (mapconcat #'identity (nreverse prose) " "))))
        (let* ((wanted (mapcar #'downcase tibetan-handout-grammar-labels))
               (kept (cl-remove-if-not
                      (lambda (it) (and (car it)
                                        (member (downcase (car it)) wanted)))
                      items)))
          (or kept items))))))

(defun tibetan-handout--load-curated (source-file)
  "The class wordlist (★) hash of SOURCE-FILE's Resources folder.
Loaded with `default-directory' = the source's directory under a
`let' on the vocabulary state, so nothing leaks into the session's
global lookup (§5.34 lesson: locate per-document assets from the
source path, never from the caller's buffer).  nil without
Resources."
  (let ((default-directory (file-name-directory
                            (expand-file-name source-file)))
        (tibetan-current-resources-vocab nil))
    (with-temp-buffer
      (tibetan-load-resources-vocab)
      tibetan-current-resources-vocab)))

(defconst tibetan-handout--machine-text-re
  (concat "\\`\\[\\(?:Requesting\\|Awaiting\\|Claude\\|Translation not"
          "\\|Antwort abgeschnitten\\)")
  "Machine placeholders / stubs — never content on a handout.
Prefix-anchored (§5.40 lesson: a real rendering may open with an
editorial bracket like `[He] spoke').")

(defun tibetan-handout--translation (file seg-nums sections)
  "The translation of the sentence FILE for the handout, or nil.
\(:by-seg ((N . TEXT) …)) when every segment of SEG-NUMS has a
landed ⟦N⟧ line — the handout numbers the pieces; else (:whole
TEXT) from the Translation slot of SECTIONS (machine label
`(Sentence N — …)' stripped); nil when only placeholders exist."
  (let ((rends (tibetan-translation-doc--renderings file)))
    (if (and seg-nums
             (cl-every (lambda (n)
                         (let ((r (cdr (assq n rends))))
                           (and r (not (string-match-p
                                        tibetan-handout--machine-text-re r)))))
                       seg-nums))
        (list :by-seg (mapcar (lambda (n) (cons n (cdr (assq n rends))))
                              seg-nums))
      (let ((tr (plist-get sections :translation)))
        (when (and tr (not (string-match-p tibetan-handout--machine-text-re tr)))
          (setq tr (string-trim
                    (replace-regexp-in-string
                     "\\`(Sentence[^)\n]*)[ \t]*\n" "" tr)))
          (unless (string-empty-p tr)
            (list :whole tr)))))))

(defun tibetan-handout--vocab (body sa word-analysis)
  "Per-segment vocabulary entries from the Claude Vocabulary BODY.
Returns ((SEG . ENTRIES) …), ENTRY = (:term :gloss :star :context
:info).  bo: the ★ wordlist entry replaces the gloss, the context
gloss stays only where it differs; info = part of speech (+ Skt.).
SA (Sanskrit): NO ★ lookup ever — the wordlist is Wylie-keyed and
`na'/`ca'/`ma' would hit Tibetan entries (§5.57 poison class); info
= \"lemma; MORPH\" from WORD-ANALYSIS (the parsed `** Word Analysis')
when the word is listed there."
  (let ((out '()))
    (dolist (g (tibetan-analysis--split-body-by-segment body))
      (let* ((wa (cdr (assq (car g) word-analysis)))
             (entries
              (delq nil
                    (mapcar
                     (lambda (line)
                       (let ((f (tibetan-handout--vocab-fields line)))
                         (when f
                           (let* ((term (plist-get f :term))
                                  (pos (plist-get f :pos))
                                  (star (and (not sa)
                                             (tibetan-handout--curated-gloss
                                              term pos)))
                                  (lemma (cdr (assoc term (plist-get wa :lemma))))
                                  (morph (cdr (assoc term (plist-get wa :morph)))))
                             (list :term term
                                   :gloss (or star (plist-get f :gloss))
                                   :star (and star t)
                                   :context (and star
                                                 (tibetan-handout--context-differs-p
                                                  (plist-get f :gloss) star)
                                                 (plist-get f :gloss))
                                   :info (cond
                                          ((and sa morph)
                                           (if lemma (format "%s; %s" lemma morph)
                                             morph))
                                          ((plist-get f :skt)
                                           (if (string-empty-p pos)
                                               (format "Skt. %s" (plist-get f :skt))
                                             (format "%s; Skt. %s" pos
                                                     (plist-get f :skt))))
                                          (t pos)))))))
                     (split-string (cdr g) "\n")))))
        (when entries
          (push (cons (car g) entries) out))))
    (nreverse out)))

(defun tibetan-handout--grammar (body)
  "Per-segment filtered grammar of the Claude Grammar BODY:
\((SEG . ((LABEL . TEXT) …)) …).  The cross-clause preamble is
dropped (Carsten 09.10.: only the configured labels) — unless the
body has no segment subsections at all, then the preamble is the
only grammar there is and goes through the same filter."
  (let* ((groups (tibetan-analysis--split-body-by-segment body))
         (segs (cl-remove-if-not #'car groups))
         (use (or segs groups))
         (out '()))
    (dolist (g use)
      (let ((bullets (tibetan-handout--grammar-bullets
                      ;; `**Cross-clause overview:**' prose and the
                      ;; L3 overview heading are no bullets anyway.
                      (cdr g))))
        (when bullets
          (push (cons (car g) bullets) out))))
    (nreverse out)))

(defun tibetan-handout--sentence-data (sent-num source-file)
  "Everything the handout needs for sentence SENT-NUM of SOURCE-FILE.
Plist: :sent-num :lang (\"bo\"/\"sa\") :segs ((:num :wylie :uchen) …)
— the source text itself, Uchen only for bo — and, when the cascade
file exists, :translation (`tibetan-handout--translation'), :vocab
\(`--vocab') and :grammar (`--grammar'); otherwise :missing t (a
visible gap, never an error).  ★ lookups use the wordlist state the
CALLER binds (`tibetan-handout--load-curated').  Reads only the
tool's Translation/Vocabulary/Grammar slots — Provided Translations
\(Lopez/W&M/DM) and the Working Translation never reach the handout."
  (let* ((lang (tibetan-analysis--resolve-source-lang source-file))
         (sa (equal lang "sa"))
         (segs (tibetan-cascade--segs-for-sentence source-file sent-num))
         (folder (file-name-as-directory
                  (expand-file-name "analysis"
                                    (file-name-directory source-file))))
         (file (tibetan-sentence--filepath sent-num folder source-file))
         (seg-list (mapcar (lambda (s)
                             (let ((text (string-trim (cdr s))))
                               (list :num (car s)
                                     :wylie (if sa text
                                              (string-trim
                                               (tibetan-to-wylie-fixed text)))
                                     :uchen (unless sa text))))
                           segs))
         (base (list :sent-num sent-num :lang lang :segs seg-list)))
    (if (not (file-exists-p file))
        (append base (list :missing t))
      (let ((sections (tibetan-analysis--read-claude-sections file))
            (wa (and sa (tibetan-sanskrit-reading-parse-word-analysis
                         (tibetan-sentence--read-l2-body file
                                                         "Word Analysis")))))
        (append base
                (list :translation (tibetan-handout--translation
                                    file (mapcar #'car segs) sections)
                      :vocab (tibetan-handout--vocab
                              (plist-get sections :vocabulary) sa wa)
                      :grammar (tibetan-handout--grammar
                                (plist-get sections :grammar))))))))

;; ============================================================================
;; B2 — renderer (pure: spec → org string)
;; ============================================================================

(defconst tibetan-handout-generated-marker
  "# GENERATED by tibetan-handout"
  "First line of every generated handout.  The overwrite guard
refuses an existing target without it (a hand-owned file is never
clobbered); a generated handout may be shortened before printing —
the next C-c u H regenerates it from the analysis files.")

(defcustom tibetan-handout-tibetan-font "Noto Serif Tibetan"
  "Font for the Uchen line of the handout (fontspec name, HarfBuzz)."
  :type 'string
  :group 'tibetan-cat)

(defun tibetan-handout--latex-escape (s)
  "S with the LaTeX special characters escaped (raw-LaTeX blocks)."
  (mapconcat (lambda (c)
               (pcase c
                 (?\\ "\\textbackslash{}")
                 (?~ "\\textasciitilde{}")
                 (?^ "\\textasciicircum{}")
                 ((or ?& ?% ?# ?_ ?$ ?{ ?}) (string ?\\ c))
                 (_ (string c))))
             (or s "") ""))

(defun tibetan-handout--emphasis (body org-marker latex-cmd prev next)
  "BODY as org emphasis with ORG-MARKER when org will recognise it
between the characters PREV and NEXT (nil = line edge); otherwise
an export snippet with LATEX-CMD — the output must be right even
where org's emphasis rules would leave the markers standing."
  (if (and (not (string-match-p "[/*\n]" body))
           (not (string-match-p "\\`[ \t]\\|[ \t]\\'" body))
           (or (null prev) (memq prev '(?\s ?\t ?\( ?- ?' ?\" ?{)))
           (or (null next) (memq next '(?\s ?\t ?. ?, ?\; ?: ?! ?? ?'
                                       ?\) ?} ?- ?\" ?\\))))
      (concat org-marker body org-marker)
    (format "@@latex:\\%s{@@%s@@latex:}@@" latex-cmd body)))

(defun tibetan-handout--md-to-org (s)
  "Claude's markdown emphasis in S as org: `**x**' → bold, `*x*' →
italic.  Lines that org would read as a heading, comment or table
are defused with an empty export snippet in front."
  (let ((out "") (pos 0) (s (or s "")))
    (while (string-match "\\*\\*\\([^*\n]+\\)\\*\\*\\|\\*\\([^*\n]+\\)\\*"
                         s pos)
      (let* ((beg (match-beginning 0)) (end (match-end 0))
             (bold (match-string 1 s)) (ital (match-string 2 s))
             (prev (and (> beg 0) (aref s (1- beg))))
             (next (and (< end (length s)) (aref s end))))
        (setq out (concat out (substring s pos beg)
                          (if bold
                              (tibetan-handout--emphasis bold "*" "textbf"
                                                         prev next)
                            (tibetan-handout--emphasis ital "/" "emph"
                                                       prev next)))
              pos end)))
    (setq out (concat out (substring s pos)))
    (mapconcat (lambda (line)
                 (if (string-match-p "\\`\\(?:\\*+ \\|#\\|[ \t]*|\\)" line)
                     (concat "@@latex:{}@@" line)
                   line))
               (split-string out "\n") "\n")))

(defun tibetan-handout--cell (s)
  "S as a single org table cell: one line, `|' as \\vert{}."
  (replace-regexp-in-string
   "|" "\\\\vert{}"
   (replace-regexp-in-string "[ \t]*\n[ \t]*" " "
                             (tibetan-handout--md-to-org (string-trim (or s ""))))
   t))

(defun tibetan-handout--macro-arg (s)
  "S safe as an org macro argument (commas escaped)."
  (replace-regexp-in-string "," "\\\\," (or s "") t))

(defun tibetan-handout--seg-range (segs)
  "\"1970–1974\" / \"1975\" for the :segs of a sentence."
  (let ((nums (mapcar (lambda (s) (plist-get s :num)) segs)))
    (if (cdr nums)
        (format "%d–%d" (car nums) (car (last nums)))
      (format "%d" (car nums)))))

(defun tibetan-handout--sentence-range (sentences)
  "\"Satz 654\" / \"Sätze 654–656\" for the handout's SENTENCES."
  (let ((first (plist-get (car sentences) :sent-num))
        (last (plist-get (car (last sentences)) :sent-num)))
    (if (equal first last)
        (format "Satz %d" first)
      (format "Sätze %d–%d" first last))))

(defun tibetan-handout--header (spec)
  "The org header (marker, keywords, LaTeX preamble, macros) of SPEC."
  (let* ((title (plist-get spec :title))
         (scope (plist-get spec :scope))
         (range (tibetan-handout--sentence-range (plist-get spec :sentences)))
         (head (mapconcat #'tibetan-handout--latex-escape
                          (delete-dups (delq nil (list scope range)))
                          " · ")))
    (concat
     tibetan-handout-generated-marker
     " — darf vor dem Druck gekürzt werden; C-c u H erzeugt neu\n"
     (format "# Quelle: %s · %s · generiert %s\n"
             (plist-get spec :source-name) scope (plist-get spec :date))
     (format "#+TITLE: %s — %s\n" title scope)
     "#+LANGUAGE: de\n"
     "#+OPTIONS: toc:nil num:nil title:nil author:nil date:nil ^:nil\n"
     "#+LATEX_COMPILER: lualatex\n"
     "#+LATEX_CLASS: article\n"
     "#+LATEX_CLASS_OPTIONS: [11pt,a4paper]\n"
     "#+LATEX_HEADER: \\usepackage[a4paper,left=2cm,right=6cm,top=2.2cm,bottom=2.2cm,headsep=8mm]{geometry}\n"
     "#+LATEX_HEADER: \\usepackage{fontspec}\n"
     "#+LATEX_HEADER: \\usepackage{libertinus}\n"
     (format "#+LATEX_HEADER: \\newfontfamily\\tibfont{%s}[Renderer=HarfBuzz,Script=Tibetan]\n"
             tibetan-handout-tibetan-font)
     "#+LATEX_HEADER: \\usepackage{xcolor,fancyhdr,setspace,needspace,newunicodechar,longtable,array,enumitem,titlesec}\n"
     "#+LATEX_HEADER: \\newunicodechar{★}{\\ensuremath{\\star}}\n"
     "#+LATEX_HEADER: \\definecolor{seg}{rgb}{0.55,0.10,0.10}\\definecolor{dim}{gray}{0.40}\n"
     "#+LATEX_HEADER: \\pagestyle{fancy}\\fancyhf{}\\renewcommand{\\headrulewidth}{0.4pt}\n"
     (format "#+LATEX_HEADER: \\fancyhead[L]{\\small\\textit{%s} · %s}\\fancyhead[R]{\\small\\thepage}\n"
             (tibetan-handout--latex-escape title) head)
     (format "#+LATEX_HEADER: \\fancyfoot[L]{\\scriptsize\\color{dim}Stand %s}\n"
             (plist-get spec :date))
     "#+LATEX_HEADER: \\setlength{\\parindent}{0pt}\n"
     "#+LATEX_HEADER: \\titleformat{\\section}{\\Needspace{6\\baselineskip}\\large\\bfseries}{}{0pt}{}\n"
     "#+LATEX_HEADER: \\titleformat{\\subsection}{\\Needspace{5\\baselineskip}\\normalsize\\bfseries\\color{seg}}{}{0pt}{}\n"
     "#+LATEX_HEADER: \\titlespacing*{\\section}{0pt}{2.2ex plus .5ex}{1ex}\\titlespacing*{\\subsection}{0pt}{1.4ex plus .3ex}{.5ex}\n"
     "#+LATEX_HEADER: \\setlist[description]{font=\\normalfont\\scshape\\color{seg}\\footnotesize,leftmargin=0pt,labelsep=0.5em,itemsep=2pt,topsep=2pt,parsep=0pt}\n"
     "#+LATEX_HEADER: \\newcommand{\\segno}[1]{\\noindent\\llap{\\color{seg}\\footnotesize #1\\hspace{3mm}}}\n"
     "#+LATEX_HEADER: \\newcommand{\\segsup}[1]{\\textsuperscript{\\color{seg}\\scriptsize #1}\\,}\n"
     "#+LATEX_HEADER: \\newcommand{\\ctx}[1]{{\\footnotesize\\color{dim}(#1)}}\n"
     "#+LATEX_HEADER: \\newcommand{\\luecke}[1]{{\\color{dim}\\textit{— #1 —}}}\n"
     "#+LATEX_HEADER: \\newcommand{\\seglabel}[1]{\\par\\smallskip\\Needspace{3\\baselineskip}{\\color{seg}\\footnotesize #1}\\par\\nopagebreak}\n"
     "#+MACRO: n @@latex:\\segsup{$1}@@\n"
     "#+MACRO: seg @@latex:\\seglabel{$1}@@\n"
     "#+MACRO: ctx @@latex:\\ctx{@@$1@@latex:}@@\n"
     "#+MACRO: luecke @@latex:\\luecke{@@$1@@latex:}@@\n\n")))

(defun tibetan-handout--text-part (sentences)
  "`* Text': every segment — Uchen above Wylie (bo) or the IAST (sa),
segment number in the margin, wide line spacing for handwriting."
  (concat
   "* Text\n#+BEGIN_EXPORT latex\n{\\setstretch{1.9}\n"
   (mapconcat
    (lambda (d)
      (concat
       (mapconcat
        (lambda (s)
          (let ((num (plist-get s :num))
                (wylie (tibetan-handout--latex-escape (plist-get s :wylie)))
                (uchen (plist-get s :uchen)))
            (if uchen
                (format "\\segno{%d}{\\tibfont\\large %s}\\par\n\\noindent{}%s\\par\\smallskip\n"
                        num (tibetan-handout--latex-escape uchen) wylie)
              (format "\\segno{%d}%s\\par\\smallskip\n" num wylie))))
        (plist-get d :segs) "")
       "\\medskip\n"))
    sentences "")
   ;; The passage stands on its own page(s) — it lies next to the
   ;; class text; the per-sentence look-up part starts fresh.
   "}\\clearpage\n#+END_EXPORT\n\n"))

(defun tibetan-handout--sentence-block (d)
  "`* Satz N (Seg. …)' for the sentence data D: compact Wylie,
Übersetzung, Vokabular, Grammatik — or the visible gap."
  (let* ((segs (plist-get d :segs))
         (multi (cdr segs))
         (tr (plist-get d :translation)))
    (concat
     (format "* Satz %d (Seg. %s)\n" (plist-get d :sent-num)
             (tibetan-handout--seg-range segs))
     "#+BEGIN_EXPORT latex\n{\\small\\itshape "
     (mapconcat (lambda (s)
                  (format "\\segsup{%d}%s" (plist-get s :num)
                          (tibetan-handout--latex-escape (plist-get s :wylie))))
                segs " ")
     "}\\par\n#+END_EXPORT\n\n"
     (if (plist-get d :missing)
         "{{{luecke(Analysedatei fehlt — C-c u A auf dem Satz)}}}\n\n"
       (concat
        "** Übersetzung\n"
        (cond
         ((plist-get tr :by-seg)
          (concat (mapconcat (lambda (p)
                               (format "{{{n(%d)}}}%s" (car p)
                                       (tibetan-handout--md-to-org (cdr p))))
                             (plist-get tr :by-seg) " ")
                  "\n\n"))
         ((plist-get tr :whole)
          (concat (replace-regexp-in-string
                   "\n" " \\\\\\\\\n"
                   (tibetan-handout--md-to-org (plist-get tr :whole)))
                  "\n\n"))
         (t "{{{luecke(noch nicht übersetzt)}}}\n\n"))
        "** Vokabular\n"
        (if (plist-get d :vocab)
            (mapconcat
             (lambda (g)
               (concat
                (if (and multi (car g)) (format "{{{seg(%d)}}}\n\n" (car g)) "")
                "#+ATTR_LATEX: :environment longtable :align "
                "@{}>{\\raggedright\\bfseries}p{3.0cm}>{\\raggedright}p{6.6cm}"
                ">{\\raggedright\\arraybackslash\\footnotesize\\leavevmode\\color{dim}}p{3.1cm}@{}\n"
                (mapconcat
                 (lambda (e)
                   (format "| %s | %s%s | %s |"
                           (tibetan-handout--cell (plist-get e :term))
                           (concat (if (plist-get e :star) "★ " "")
                                   (tibetan-handout--cell (plist-get e :gloss)))
                           (if (plist-get e :context)
                               (format " {{{ctx(%s)}}}"
                                       (tibetan-handout--macro-arg
                                        (tibetan-handout--cell
                                         (plist-get e :context))))
                             "")
                           (tibetan-handout--cell (plist-get e :info))))
                 (cdr g) "\n")
                "\n\n"))
             (plist-get d :vocab) "")
          "{{{luecke(noch kein Vokabular)}}}\n\n")
        "** Grammatik\n"
        (if (plist-get d :grammar)
            (mapconcat
             (lambda (g)
               (concat
                (if (and multi (car g)) (format "{{{seg(%d)}}}\n\n" (car g)) "")
                (mapconcat
                 (lambda (b)
                   (let ((text (replace-regexp-in-string
                                "[ \t]*\n[ \t]*" " "
                                (tibetan-handout--md-to-org (cdr b)))))
                     (if (car b)
                         (format "- %s :: %s" (car b) text)
                       text)))
                 (cdr g) "\n")
                "\n\n"))
             (plist-get d :grammar) "")
          "{{{luecke(noch keine Grammatik)}}}\n\n"))))))

(defun tibetan-handout-render (spec)
  "The handout org text for SPEC — a plist (:title :scope :source-name
:date :sentences), :sentences being `tibetan-handout--sentence-data'
plists.  Pure: no file access.  Layout (Carsten 09.10.): `* Text'
\(the whole passage: Uchen + Wylie per segment, room for handwriting,
6 cm free right margin on every page), then per sentence `* Satz N'
with Übersetzung / Vokabular / Grammatik.  The word \"Claude\" never
appears (headings are German; the slots are named by content)."
  (let ((sentences (plist-get spec :sentences)))
    (concat (tibetan-handout--header spec)
            (tibetan-handout--text-part sentences)
            (mapconcat #'tibetan-handout--sentence-block sentences ""))))

;; ============================================================================
;; B3 — scope, file, PDF, command
;; ============================================================================

(defun tibetan-handout--enclosing-sentence ()
  "Number of the `Sentence N' heading at or above point, or nil."
  (save-excursion
    (unless (org-before-first-heading-p)
      (org-back-to-heading t)
      (catch 'found
        (while t
          (let ((h (org-get-heading t t t t)))
            (when (and h (string-match "\\`Sentence \\([0-9]+\\)\\b" h))
              (throw 'found (string-to-number (match-string 1 h)))))
          (unless (org-up-heading-safe)
            (throw 'found nil)))))))

(defun tibetan-handout--scope-at-point ()
  "What the handout covers, from point: (:source :sent-nums :label
:lopez).  In a cascade SOURCE the scope follows the org outline
like C-c u A (§5.59 A1): Segment → its sentence, Sentence → it, any
higher heading → every sentence below (a Section with
`:LOPEZ_SECTION:' labels as \"§N\"), before the first heading → the
document.  In a `sent-NNN' analysis buffer: that sentence."
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "Puffer ohne Datei — Handout braucht eine Kaskaden-Quelle"))
    (if (string-match-p "\\`sent-[0-9]" (file-name-nondirectory file))
        (let ((n (tibetan-sentence--sent-id-from-filename file))
              (src (tibetan-sentence--source-file-from-analysis file)))
          (unless (and n src)
            (user-error "Satz/Quelle von %s nicht bestimmbar"
                        (file-name-nondirectory file)))
          (list :source src :sent-nums (list n)
                :label (format "Satz %d" n)))
      (unless (tibetan-analysis--cascade-p file)
        (user-error "%s ist kein Kaskaden-Dokument (#+TIBETAN_LAYOUT: cascade)"
                    (file-name-nondirectory file)))
      (let ((sent (tibetan-handout--enclosing-sentence)))
        (if sent
            (list :source file :sent-nums (list sent)
                  :label (format "Satz %d" sent))
          (let* ((sub (tibetan-cascade--subtree-sentences))
                 (lopez (save-excursion
                          (unless (org-before-first-heading-p)
                            (org-back-to-heading t)
                            (let ((v (org-entry-get (point) "LOPEZ_SECTION")))
                              (and v (string-match-p "\\`[0-9]+\\'" (string-trim v))
                                   (string-to-number v)))))))
            (unless (cdr sub)
              (user-error "Keine Sätze unter „%s“" (or (car sub) "Dokument")))
            (list :source file
                  :sent-nums (mapcar (lambda (s) (plist-get s :sent-num))
                                     (cdr sub))
                  :label (cond (lopez (format "§%d" lopez))
                               ((car sub) (string-remove-prefix
                                           "Section " (car sub)))
                               (t "gesamt"))
                  :lopez lopez)))))))

(defun tibetan-handout--output-file (scope)
  "`<source dir>/handouts/<short>-par-NNN.org' for a Lopez § SCOPE,
else `<short>-sent-N[-M].org'.  The source short name keeps
multi-source folders collision-free (§5.23 lesson)."
  (let* ((src (plist-get scope :source))
         (nums (plist-get scope :sent-nums))
         (short (tibetan-analysis-make-short-name src)))
    (expand-file-name
     (concat "handouts/" short "-"
             (cond ((plist-get scope :lopez)
                    (format "par-%d" (plist-get scope :lopez)))
                   ((cdr nums)
                    (format "sent-%03d-%03d" (car nums) (car (last nums))))
                   (t (format "sent-%03d" (car nums))))
             ".org")
     (file-name-directory src))))

(defun tibetan-handout--source-title (source-file)
  "The work title: SOURCE-FILE's #+TITLE before \" — \", or its base name."
  (or (with-temp-buffer
        (insert-file-contents source-file nil 0 4096)
        (goto-char (point-min))
        (when (re-search-forward "^#\\+TITLE:[ \t]*\\(.+\\)$" nil t)
          (string-trim (car (split-string (match-string 1) " — ")))))
      (file-name-base source-file)))

(defun tibetan-handout-build (scope &optional date)
  "Write the handout .org for SCOPE (`tibetan-handout--scope-at-point'
shape) and return its path.  The class wordlist (★) of the source's
Resources is bound for the whole build; DATE (default today) goes
into the footer.  An existing target WITHOUT the GENERATED marker is
never overwritten (user-error) — a generated one is regenerated."
  (let* ((src (plist-get scope :source))
         (out (tibetan-handout--output-file scope)))
    (when (and (file-exists-p out)
               (not (with-temp-buffer
                      (insert-file-contents out nil 0 512)
                      (string-prefix-p tibetan-handout-generated-marker
                                       (buffer-string)))))
      (user-error "%s existiert und trägt keinen GENERATED-Marker — nicht überschrieben"
                  (file-name-nondirectory out)))
    (let* ((tibetan-current-resources-vocab (tibetan-handout--load-curated src))
           (tibetan-current-custom-vocab nil)
           (spec (list :title (tibetan-handout--source-title src)
                       :scope (plist-get scope :label)
                       :source-name (file-name-nondirectory src)
                       :date (or date (format-time-string "%Y-%m-%d"))
                       :sentences (mapcar (lambda (n)
                                            (tibetan-handout--sentence-data n src))
                                          (plist-get scope :sent-nums)))))
      (make-directory (file-name-directory out) t)
      (with-temp-file out
        (insert (tibetan-handout-render spec)))
      out)))

(defvar org-latex-pdf-process)
(declare-function org-latex-export-to-pdf "ox-latex")

(defun tibetan-handout-export-pdf (org-file)
  "Export ORG-FILE to PDF beside it and return the PDF path.
LuaLaTeX (the file's #+LATEX_COMPILER), two runs for longtable —
bound locally, so the user's own `org-latex-pdf-process' (latexmk …)
neither breaks nor is changed."
  (require 'ox-latex)
  (let ((buf (find-file-noselect org-file)))
    (unwind-protect
        (with-current-buffer buf
          (let ((org-latex-pdf-process
                 '("%latex -interaction nonstopmode -output-directory %o %f"
                   "%latex -interaction nonstopmode -output-directory %o %f")))
            (expand-file-name (org-latex-export-to-pdf)
                              (file-name-directory org-file))))
      (unless (buffer-modified-p buf)
        (kill-buffer buf)))))

(defun tibetan-handout--generated-buffer-p ()
  "Non-nil when the current buffer is a generated handout."
  (save-excursion
    (goto-char (point-min))
    (looking-at-p (regexp-quote tibetan-handout-generated-marker))))

;;;###autoload
(defun tibetan-handout (&optional org-only)
  "Reading-class handout for the scope at point (C-c u H).
In a cascade source: the sentence at point, or every sentence under
the heading at point (a § …); in a sent-NNN analysis buffer: that
sentence.  Writes `handouts/<short>-….org' beside the source (may be
shortened before printing; regenerating overwrites it), exports it
to PDF and opens the PDF.  With ORG-ONLY (C-u): only the .org, which
is opened for editing.  INSIDE a generated handout the buffer is
saved and exported as it is — shortening before printing is never
undone by a regeneration.  No network, no API call."
  (interactive "P")
  (if (and (buffer-file-name) (tibetan-handout--generated-buffer-p))
      (progn
        (save-buffer)
        (let ((pdf (tibetan-handout-export-pdf (buffer-file-name))))
          (org-open-file pdf)
          (message "Handout: %s" (file-name-nondirectory pdf))
          pdf))
    (tibetan-handout--from-scope org-only)))

(defun tibetan-handout--from-scope (org-only)
  "Body of `tibetan-handout' outside a generated handout buffer."
  (let ((scope (tibetan-handout--scope-at-point)))
    (when (and (> (length (plist-get scope :sent-nums)) 50)
               (not (y-or-n-p (format "Handout über %d Sätze erzeugen? "
                                      (length (plist-get scope :sent-nums))))))
      (user-error "Abgebrochen"))
    (let ((org (tibetan-handout-build scope)))
      (if org-only
          (progn (find-file org)
                 (message "Handout (org): %s" (file-name-nondirectory org)))
        (let ((pdf (tibetan-handout-export-pdf org)))
          (org-open-file pdf)
          (message "Handout: %s" (file-name-nondirectory pdf))
          pdf)))))

(provide 'tibetan-handout)
;;; tibetan-handout.el ends here
