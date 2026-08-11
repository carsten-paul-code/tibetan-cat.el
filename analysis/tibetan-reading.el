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

(defun tibetan-reading--unit-tokens (unit-text)
  "Classified token plists for one shad unit, in order.
Each: (:tibetan S :wylie W :kind particle|verb|word :label L
:curated-p BOOL :clitic (CL-WYLIE . CL-LABEL)|nil)."
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
                    :prev-verb-p prev-verb-p
                    :curated-p (tibetan-reading--curated-p tib)
                    :clitic (when clitic
                              (cons (tibetan-reading--wylie
                                     (car (cdr clitic)))
                                    (cdr (cdr clitic)))))
              out)
        (setq prev-verb-p (eq kind 'verb))))
    (nreverse out)))

(defun tibetan-reading--render-token (tok &optional main-verb-p)
  "Render one classified TOK plist into its decorated Wylie string."
  (let* ((wylie (plist-get tok :wylie))
         (kind (plist-get tok :kind))
         (star (if (plist-get tok :curated-p) "★" ""))
         (base (pcase kind
                 ('particle (tibetan-reading--decorate-particle
                             wylie (plist-get tok :label)
                             (plist-get tok :prev-verb-p)
                             (plist-get tok :tibetan)))
                 ('verb (if main-verb-p
                            (format "*%s*" wylie)
                          (format "!%s!" wylie)))
                 (_ wylie)))
         (clitic (plist-get tok :clitic)))
    (concat base
            (when clitic (format "=%s=" (car clitic)))
            star)))

(defun tibetan-reading-decorated-unit-line (unit-text &optional last-unit-p)
  "One decorated Wylie line for UNIT-TEXT (a shad unit, shads kept).
When LAST-UNIT-P, the unit's FINAL verb token is the sentence's main
verb (`*x*'); every other verb wears `!x!'.  The line ends ` /' when
the unit carries a trailing shad run."
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
  "Decorated Wylie lines for UNITS (ordered shad-unit strings).
The main verb is marked in the LAST unit only."
  (let ((n (length units)) (i 0) out)
    (dolist (u units)
      (cl-incf i)
      (push (tibetan-reading-decorated-unit-line u (= i n)) out))
    (nreverse out)))

(provide 'tibetan-reading)
;;; tibetan-reading.el ends here
