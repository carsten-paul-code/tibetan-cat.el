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

(provide 'tibetan-handout)
;;; tibetan-handout.el ends here
