;;; tibetan-reading.el --- Decorated Wylie lines for the cascade Reading view -*- lexical-binding: t -*-

;;; Commentary:
;;
;; R3 of the READING VIEW redesign (approved 2026-08-12).  The cascade
;; sentence file opens with a `* Reading' section whose `** Wylie'
;; shows the whole sentence ONE LINE PER SHAD UNIT, decorated with
;; parts-of-speech markers:
;;
;;   =x=   case particle          (magenta — existing convention)
;;   ~x~   converb particle       (orange  — existing convention)
;;   !x!   any verb form          (blue,  R2 keywords)
;;   *x*   sentence-final main verb (red, R2 section-gated matcher)
;;   x★    curated wordlist token (existing ★ convention)
;;
;; Unlike the legacy `--render-particle-skeleton' (regex rewriting
;; over one whole-sentence Wylie string), these lines are built
;; TOKEN-WISE from `tibetan-extract-vocabulary' streams — the same
;; curated-first tokens the Interlinear uses (W1), so wordlist MWUs
;; appear as units and never get torn by word-boundary regexes.
;;
;; Pure module: no buffers, no files.  All dictionary probes are
;; fboundp-guarded so the module degrades to undecorated Wylie.

;;; Code:

(require 'cl-lib)

(declare-function tibetan-extract-vocabulary "tibetan-vocabulary" (text))
(declare-function tibetan-to-wylie-fixed "tibetan-wylie" (text))
(declare-function tibetan-verb-lookup "tibetan-verb-classifier" (word))
(declare-function tibetan-vocab--curated-exact-entry
                  "tibetan-vocabulary" (term))
(defvar tibetan-interlinear--particle-patterns)

(defconst tibetan-reading--converb-labels '("CONC")
  "Particle labels that always decorate as converbs (`~x~').
`CONV:'-prefixed labels are converbs by prefix test; the
position-dependent ནས / ན (ablative/locative after a noun,
converb after a verb) are resolved by `tibetan-reading--unit-tokens'
from the PRECEDING token's verb-ness.")

(defconst tibetan-reading--postverb-converbs '("ནས" "ན" "ལས")
  "Case-labelled particles that act as converbs after a verb
\(Bialek V+nas, V+na, V+las).")

(defun tibetan-reading--particle-label (tibetan)
  "The `tibetan-interlinear--particle-patterns' label for TIBETAN
when the whole token is a known particle form, else nil."
  (when (boundp 'tibetan-interlinear--particle-patterns)
    (cdr (assoc tibetan tibetan-interlinear--particle-patterns))))

(defun tibetan-reading--verb-p (tibetan)
  "Non-nil when TIBETAN resolves in the Hill verb DB."
  (and (fboundp 'tibetan-verb-lookup)
       (condition-case nil (tibetan-verb-lookup tibetan) (error nil))
       t))

(defun tibetan-reading--curated-p (tibetan)
  "Non-nil when TIBETAN is an exact curated wordlist key."
  (and (fboundp 'tibetan-vocab--curated-exact-entry)
       (condition-case nil
           (tibetan-vocab--curated-exact-entry tibetan)
         (error nil))
       t))

(defun tibetan-reading--wylie (tibetan)
  "Deterministic Wylie of TIBETAN (fallback: the input verbatim)."
  (or (and (fboundp 'tibetan-to-wylie-fixed)
           (condition-case nil
               (let ((w (tibetan-to-wylie-fixed tibetan)))
                 (and w (not (string-empty-p w)) (string-trim w)))
             (error nil)))
      tibetan))

(defconst tibetan-reading--merged-clitics '("འིས" "འང" "འི")
  "Merged clitics the READING builder splits letter-wise — the
འ-initial forms only, longest first.  Bare `ར' is deliberately
absent: `དེར' (de + terminative r) and `ཁྱེར' (root-final r) are
graphically IDENTICAL (vowel sign + ར), and unlike the interlinear
splitter this builder has no Bialek tag to confirm particle-ness —
splitting would tear real syllables (khyer → khye + =ra=).  A
missed `=r=' is a small display loss; a torn syllable is wrong.")

(defun tibetan-reading--split-merged-clitic (tibetan)
  "Split a trailing merged clitic off TIBETAN:
\(STEM . (CLITIC . LABEL)) or nil.  Only the graphically unambiguous
འ-initial clitics (`tibetan-reading--merged-clitics'); syllabic
particles are their own tokens in the `tibetan-extract-vocabulary'
stream.  Curated whole tokens are never split (W4b authority rule)."
  (when (and (boundp 'tibetan-interlinear--particle-patterns)
             (not (tibetan-reading--curated-p tibetan)))
    (cl-loop for clitic in tibetan-reading--merged-clitics
             when (and (string-suffix-p clitic tibetan)
                       (> (length tibetan) (length clitic)))
             return (cons (substring tibetan 0 (- (length tibetan)
                                                  (length clitic)))
                          (cons clitic
                                (cdr (assoc clitic
                                            tibetan-interlinear--particle-patterns)))))))

(defun tibetan-reading--decorate-particle (wylie label prev-verb-p tibetan)
  "Wrap WYLIE in `=…=' or `~…~' according to LABEL and context."
  (let ((converb-p (or (string-prefix-p "CONV" (or label ""))
                       (member label tibetan-reading--converb-labels)
                       (and prev-verb-p
                            (member tibetan
                                    tibetan-reading--postverb-converbs)))))
    (if converb-p (format "~%s~" wylie) (format "=%s=" wylie))))

(declare-function tibetan-interlinear--prefer-target-lang
                  "tibetan-interlinear" (meaning))
(declare-function tibetan-interlinear--truncate-gloss
                  "tibetan-interlinear" (gloss budget))
(declare-function tibetan-interlinear--sanitize-gloss
                  "tibetan-interlinear" (gloss))
(declare-function tibetan-steinert-available-p "tibetan-steinert" ())
(declare-function tibetan-steinert-url "tibetan-steinert" (wylie))

(defun tibetan-reading--unit-tokens (unit-text)
  "Classified token plists for one shad unit, in order.
Each: (:tibetan S :wylie W :kind particle|verb|word :label L
:meaning M :curated-p BOOL :clitic (CL-WYLIE . CL-LABEL)|nil).
:meaning is the ranked-lookup gloss the token cell carried
\(curated-first after W1) — the combined Reading line renders it
inline, so the layer IS the interlinear trot."
  (let ((cells (and (fboundp 'tibetan-extract-vocabulary)
                    (condition-case nil
                        (tibetan-extract-vocabulary unit-text)
                      (error nil))))
        (prev-verb-p nil)
        out)
    (dolist (cell cells)
      (let* ((tib (car cell))
             (label (tibetan-reading--particle-label tib))
             (clitic (unless label
                       (tibetan-reading--split-merged-clitic tib)))
             (stem (if clitic (car clitic) tib))
             (kind (cond (label 'particle)
                         ((tibetan-reading--verb-p stem) 'verb)
                         (t 'word))))
        (push (list :tibetan tib
                    :wylie (tibetan-reading--wylie stem)
                    :kind kind
                    :label label
                    :meaning (cdr cell)
                    :prev-verb-p prev-verb-p
                    ;; W6: a token whose clitic-stripped STEM is the
                    ;; curated key (mai tri'i → mai tri) is curated
                    ;; too — grouped by the vocabulary side, starred
                    ;; here, clitic displayed.
                    :curated-p (or (tibetan-reading--curated-p tib)
                                   (and clitic
                                        (tibetan-reading--curated-p
                                         stem)))
                    :clitic (when clitic
                              (cons (tibetan-reading--wylie
                                     (car (cdr clitic)))
                                    (cdr (cdr clitic)))))
              out)
        (setq prev-verb-p (eq kind 'verb))))
    (nreverse out)))

(defvar tibetan-analysis--target-lang)
(defvar tibetan-analysis--claude-vocabulary-for-render)

(defun tibetan-reading--claude-gloss (tok)
  "Claude's context gloss for TOK from the dynamic render var, or nil.
Consults `tibetan-analysis--claude-vocabulary-for-render' (the
parsed Claude Vocabulary alist a reanalyze binds from the
preserved section) with TOK's stem Wylie as an EXACT key — a bare
token never inherits an MWU entry's gloss (the M2 `mar'/`mar pas'
lesson).  Curated ★ tokens are excluded up front: the hand-written
wordlist outranks Claude (kuratiert > Claude > Wörterbuch).
Returns the first double-quoted field of the matched line
\(`wylie, POS, \"gloss\", note')."
  (when (and (boundp 'tibetan-analysis--claude-vocabulary-for-render)
             tibetan-analysis--claude-vocabulary-for-render
             (not (plist-get tok :curated-p)))
    (let* ((hit (assoc (plist-get tok :wylie)
                       tibetan-analysis--claude-vocabulary-for-render))
           (line (cdr hit)))
      (when (and (stringp line)
                 (string-match "\"\\([^\"]+\\)\"" line))
        (match-string 1 line)))))

(defconst tibetan-reading--sanskrit-sign-re
  "[ཱཻཽྲྀཷླྀཹཾཿྃཊཋཌཎཥ]"
  "Signs that occur only in Sanskrit transliteration (long-vowel
achung, ai/au ligatures, vocalic r/l, anusvāra, visarga, retroflex
letters).  A syllable carrying one can not be a native Tibetan word
— dictionary-lookup noise for it is suppressed (mai [(look up)],
the W6 Portfolio finding).")

(defun tibetan-reading--sanskrit-token-p (tok)
  "Non-nil when TOK's Tibetan carries a Sanskrit-only sign."
  (string-match-p tibetan-reading--sanskrit-sign-re
                  (or (plist-get tok :tibetan) "")))

(defun tibetan-reading--gloss (tok)
  "The display gloss for TOK, or nil: target-lang half selected,
budgeted (60 chars curated / 30 generic — the interlinear budgets),
sanitized.  nil for empty / whitespace meanings.

Language forms handled: `DE // EN' (the wordlist convention, via
the Pass-5c selector) AND `EN (DE: …)' — the shape
`tibetan-lookup-word' assembles from bilingual collection; without
the second branch a de-target document's combined Reading lines
would regress to English.

2026-09-15: a NON-curated token first consults the Claude
Vocabulary render var (`tibetan-reading--claude-gloss') — the
context-aware reading beats the dictionary first-sense; it gets
the curated 60-char budget since Claude glosses are already
short, deliberate, and in the document's target language."
  (let* ((claude (tibetan-reading--claude-gloss tok))
         (m (or claude (plist-get tok :meaning))))
    ;; W6: a Sanskrit-transliteration syllable with no real gloss
    ;; renders PLAIN — `mai [(look up)]' is noise, not information.
    (when (and m (stringp m)
               (string-prefix-p "[look up" m)
               (tibetan-reading--sanskrit-token-p tok))
      (setq m nil))
    (when (and m (stringp m) (not (string-empty-p (string-trim m))))
      (let* ((lang (and (boundp 'tibetan-analysis--target-lang)
                        tibetan-analysis--target-lang))
             (half (cond
                    ((and (equal lang "de")
                          (string-match "(DE: \\(.*\\))\\s-*\\'" m))
                     (match-string 1 m))
                    ((fboundp 'tibetan-interlinear--prefer-target-lang)
                     (tibetan-interlinear--prefer-target-lang m))
                    (t m)))
             (cut (if (fboundp 'tibetan-interlinear--truncate-gloss)
                      (tibetan-interlinear--truncate-gloss
                       half (if (or claude (plist-get tok :curated-p))
                                60 30))
                    half)))
        (if (fboundp 'tibetan-interlinear--sanitize-gloss)
            (tibetan-interlinear--sanitize-gloss cut)
          cut)))))

(defun tibetan-reading--linkify (wylie tok)
  "Wrap WYLIE in a Steinert web link for dictionary-worthy tokens
\(words and verbs; particles stay plain) when the Steinert module is
live — one-click lookup, same as the retired per-segment
interlinears."
  (if (and (memq (plist-get tok :kind) '(word verb))
           (fboundp 'tibetan-steinert-available-p)
           (condition-case nil (tibetan-steinert-available-p) (error nil))
           (fboundp 'tibetan-steinert-url))
      (let ((url (condition-case nil (tibetan-steinert-url wylie)
                   (error nil))))
        (if url (format "[[%s][%s]]" url wylie) wylie))
    wylie))

(defun tibetan-reading--render-token (tok &optional main-verb-p)
  "Render TOK as its COMBINED form: decorated Wylie + ★ + gloss.

  word:      wylie ★ [gloss]          (Steinert-linked when live)
  verb:      !wylie! ★ [gloss]        (*wylie* for the main verb)
  particle:  =wylie= [LABEL]          (~wylie~ converbs; curated
             homograph → [LABEL ‖ ★ gloss], the W3 convention)

The gloss carries the POS signal into exports, where the marker
colors vanish."
  (let* ((wylie (plist-get tok :wylie))
         (kind (plist-get tok :kind))
         (curated-p (plist-get tok :curated-p))
         (gloss (tibetan-reading--gloss tok))
         (clitic (plist-get tok :clitic))
         (linked (tibetan-reading--linkify wylie tok))
         (base (pcase kind
                 ('particle (tibetan-reading--decorate-particle
                             linked (plist-get tok :label)
                             (plist-get tok :prev-verb-p)
                             (plist-get tok :tibetan)))
                 ('verb (if main-verb-p
                            (format "*%s*" linked)
                          (format "!%s!" linked)))
                 (_ linked))))
    (concat
     base
     (when clitic (format "=%s=" (car clitic)))
     (pcase kind
       ('particle
        (let ((label (or (plist-get tok :label)
                         (and clitic (cdr clitic)))))
          (cond ((and label curated-p gloss)
                 (format " [%s ‖ ★ %s]" label gloss))
                (label (format " [%s]" label))
                (t ""))))
       (_ (concat (if curated-p " ★" "")
                  (if gloss (format " [%s]" gloss) ""))))
     ;; A non-particle token with a trailing clitic still shows the
     ;; clitic's label after its gloss (tri='i= [GEN] shape).
     (if (and clitic (not (eq kind 'particle)))
         (format " [%s]" (cdr clitic))
       ""))))

(defun tibetan-reading-decorated-unit-line (unit-text &optional last-unit-p)
  "One COMBINED Reading line for UNIT-TEXT (a shad unit, shads kept):
decorated Wylie + ★ + glosses per token (Carsten's 2026-08-12
decision — the Wylie skeleton and the interlinear trot are one
layer).  When LAST-UNIT-P, the unit's FINAL verb token is the
sentence's main verb (`*x*'); every other verb wears `!x!'.  The
line ends ` /' when the unit carries a trailing shad run."
  (let* ((toks (tibetan-reading--unit-tokens unit-text))
         (last-verb (when last-unit-p
                      (cl-find-if (lambda (tk) (eq (plist-get tk :kind)
                                                   'verb))
                                  toks :from-end t)))
         (parts (mapcar (lambda (tk)
                          (tibetan-reading--render-token
                           tk (and last-verb (eq tk last-verb))))
                        toks))
         (line (string-join parts " ")))
    (when (string-match-p "[།༎༏༐༑༔]\\s-*$" unit-text)
      (setq line (concat line " /")))
    line))

(defun tibetan-reading-decorated-lines (units)
  "Combined Reading lines for UNITS (ordered shad-unit strings).
The main verb is marked in the LAST unit only."
  (let ((n (length units)) (i 0) out)
    (dolist (u units)
      (cl-incf i)
      (push (tibetan-reading-decorated-unit-line u (= i n)) out))
    (nreverse out)))

(provide 'tibetan-reading)
;;; tibetan-reading.el ends here
