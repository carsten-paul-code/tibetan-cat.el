;;; tibetan-sanskrit-reading.el --- Sanskrit token provider for the cascade -*- lexical-binding: t -*-

;;; Commentary:
;; Sanskrit-Kaskade B3 (2026-09-24).  Token provider for Sanskrit
;; (`#+SOURCE_LANG: sa') cascade documents: the counterpart of the
;; Tibetan `tibetan-reading--unit-tokens' pipeline, WITHOUT any of
;; the Tibetan machinery — IAST words split on whitespace, never on
;; tsheg, and NEVER looked up in the Wylie-keyed dictionaries (short
;; IAST words like na/ca/ma/sa would hit Tibetan entries).
;;
;; The asymmetry this module absorbs: Tibetan words exist BEFORE any
;; Claude call (tsheg-separated); Sanskrit words only exist after
;; the sandhi resolution in Claude's response.  Pre-Claude, units
;; render with SURFACE tokens (whitespace-split IAST, no glosses,
;; label `?'); once the landed `** Word Analysis' section is parsed
;; and bound (text-keyed — the shared renderer signatures carry no
;; segment number), units render with PADAPĀṬHA tokens carrying
;; morphology labels (:morph) and, via the existing Claude-gloss
;; tier, German glosses.
;;
;; Token plists follow the `tibetan-reading--unit-tokens' contract
;; (:tibetan :wylie :kind :label :meaning :prev-verb-p :curated-p
;; :clitic) extended with :morph.  For Sanskrit, :tibetan and :wylie
;; both carry the IAST word — :wylie is the row-1 cell AND the
;; Claude-vocabulary key (text before the first comma of a
;; Vocabulary line), so the schema's contract "Vocabulary keys = the
;; padapāṭha words, identical spelling" makes the existing gloss
;; tier work unchanged.

;;; Code:

(require 'cl-lib)

(declare-function tibetan-reading--gloss "tibetan-reading" (tok))

(defvar tibetan-sanskrit-reading--word-analysis nil
  "Text-keyed word analysis for the unit renderers, or nil.
Alist ((UNIT-TEXT . (:pada (WORD…) :morph ((WORD . LABEL)…))) …),
UNIT-TEXT `string-trim'-med.  Bound by the cascade regenerate from
the file's preserved `** Word Analysis' body (never from window or
init state — §5.53 batch/interactive parity).")

(defconst tibetan-sanskrit-reading--punct-re "[।॥|/.,;:!?()\"'«»]+"
  "Punctuation stripped from token edges — daṇḍas (Unicode and the
romanized |/|| of many e-texts) plus Western sentence punctuation.")

(defun tibetan-sanskrit-reading--tokenize-surface (unit-text)
  "UNIT-TEXT (IAST) as a list of surface word strings.
Whitespace-split; daṇḍas (।/॥ and romanized |/||) and clinging
punctuation are stripped; empty results drop.  nil-safe.

NOTE: the avagraha apostrophe is IAST-meaningful (so \\='pi) — only
EDGE punctuation is stripped, and a leading apostrophe followed by
a letter survives via the word-character check."
  (when unit-text
    (delq nil
          (mapcar
           (lambda (raw)
             (let ((w raw))
               ;; Strip trailing punctuation runs.
               (setq w (replace-regexp-in-string
                        (concat tibetan-sanskrit-reading--punct-re "\\'")
                        "" w))
               ;; Strip leading punctuation, but keep an avagraha
               ;; apostrophe that introduces a word ('pi, 'sti).
               (unless (string-match-p "\\`'[[:alpha:]]" w)
                 (setq w (replace-regexp-in-string
                          (concat "\\`" tibetan-sanskrit-reading--punct-re)
                          "" w)))
               (and (not (string-empty-p w)) w)))
           (split-string unit-text "[ \t\n]+" t)))))

(defun tibetan-sanskrit-reading-parse-word-analysis (body)
  "Parse a `** Word Analysis' BODY into a seg-keyed alist.
Accepts both the landed org form (`*** Segment N' — after md-h3
conversion) and the raw markdown form (`### Segment N') — the
dual-format lesson of R5.  Per segment: the FIRST non-bullet line
is the padapāṭha (whitespace-separated word sequence); each
following `- WORD — LEMMA; MORPH' bullet contributes a morph
label.  Returns ((SEG-NUM . (:pada (W…) :morph ((W . LABEL)…))) …)
in file order; nil-safe."
  (when (and body (stringp body) (not (string-empty-p (string-trim body))))
    (let (result seg pada morph)
      (cl-flet ((flush ()
                  (when seg
                    (push (cons seg (list :pada (nreverse pada)
                                          :morph (nreverse morph)))
                          result))
                  (setq seg nil pada nil morph nil)))
        (dolist (line (split-string body "\n"))
          (let ((l (string-trim line)))
            (cond
             ((string-match "\\`\\(?:###\\|\\*\\*\\*\\)[ \t]+Segment[ \t]+\\([0-9]+\\)\\b" l)
              (flush)
              (setq seg (string-to-number (match-string 1 l))))
             ((null seg))                     ; preamble before first segment
             ((string-empty-p l))
             ((string-match "\\`-[ \t]+\\(.+?\\)[ \t]+—[ \t]+\\(.+\\)\\'" l)
              (let* ((word (match-string 1 l))
                     (rest (match-string 2 l))
                     (label (when (string-match ";[ \t]*\\([^;]+\\)\\'" rest)
                              (string-trim (match-string 1 rest)))))
                (when label
                  (push (cons word label) morph))))
             ((null pada)
              ;; First plain line of the segment = the padapāṭha.
              (setq pada (nreverse
                          (tibetan-sanskrit-reading--tokenize-surface l)))))))
        (flush))
      (nreverse result))))

(defun tibetan-sanskrit-reading--analysis-for-unit (unit-text)
  "The (:pada … :morph …) entry for UNIT-TEXT from the dynamic
text-keyed index, or nil."
  (and unit-text
       (boundp 'tibetan-sanskrit-reading--word-analysis)
       tibetan-sanskrit-reading--word-analysis
       (cdr (assoc (string-trim unit-text)
                   tibetan-sanskrit-reading--word-analysis))))

(defun tibetan-sanskrit-reading-unit-tokens (unit-text &optional word-analysis)
  "Token plists for the Sanskrit unit UNIT-TEXT.
WORD-ANALYSIS is one segment's (:pada … :morph …) plist; when nil
it is resolved from `tibetan-sanskrit-reading--word-analysis' by
UNIT-TEXT.  Without an analysis: surface tokens (degraded pre-
Claude form).  With one: padapāṭha tokens carrying :morph.  Never
consults the Tibetan tokenizer or the Wylie-keyed dictionaries."
  (let* ((wa (or word-analysis
                 (tibetan-sanskrit-reading--analysis-for-unit unit-text)))
         (words (or (plist-get wa :pada)
                    (tibetan-sanskrit-reading--tokenize-surface unit-text)))
         (morph (plist-get wa :morph)))
    (mapcar (lambda (w)
              (list :tibetan w :wylie w :kind 'word
                    :label nil :meaning nil
                    :morph (cdr (assoc w morph))
                    :prev-verb-p nil :curated-p nil :clitic nil))
            words)))

(defun tibetan-sanskrit-reading-unit-line (unit-text &optional word-analysis)
  "The `** Interlinear' line for the Sanskrit unit UNIT-TEXT.
Padapāṭha words, each as `word [gloss]' when the Claude-gloss tier
yields one (`tibetan-reading--gloss' — loaded by the dispatching
caller); degrades to the plain surface line.  No ` /' suffix —
IAST units carry no shad."
  (let ((toks (tibetan-sanskrit-reading-unit-tokens
               unit-text word-analysis)))
    (when toks
      (mapconcat
       (lambda (tok)
         (let ((gloss (and (fboundp 'tibetan-reading--gloss)
                           (tibetan-reading--gloss tok))))
           (if (and gloss (not (string-empty-p gloss)))
               (format "%s [%s]" (plist-get tok :wylie) gloss)
             (plist-get tok :wylie))))
       toks " "))))

(provide 'tibetan-sanskrit-reading)

;;; tibetan-sanskrit-reading.el ends here
