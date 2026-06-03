;;; tibetan-analysis-persist.el --- Persistent segment analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Persists segment analysis to individual files, allowing users to add
;; notes, translations, and footnotes that survive re-analysis.
;;
;; Usage:
;;   C-c u A - Open/create analysis for current segment (side window)
;;   C-c u R - Re-analyze (regenerate auto section, keep notes)
;;
;; File structure:
;;   your-text.org
;;   analysis/
;;     seg-001.org
;;     seg-002.org
;;     ...

;;; Code:

(require 'cl-lib)
;; Only require org when not in batch mode (can hang in batch)
(unless noninteractive
  (require 'org))
(require 'md5)

;; Require modules for verb analysis (soft load - main loading via tibetan-cat.el)
(require 'tibetan-verb-classifier nil t)
(require 'tibetan-enhanced-display nil t)
(require 'tibetan-particles-bialek nil t)
;; §5.21 Commit 4/7 (2026-05-20):  Bialek 2022 published-textbook
;; section references on the merged `*** Particles' bullets.
;; Soft-required so a missing table degrades gracefully — bracket
;; falls back to Portfolio-only when the lookup returns nil.
(require 'tibetan-bialek-textbook-refs nil t)
(require 'tibetan-interlinear nil t)
;; Round-2 (clauses + NPs + argument structure) — used by the
;; `** Clause Structure' section.  Soft-required so a missing module
;; does not break analysis-file generation; the renderer falls back
;; to a placeholder line in that case.
(require 'tibetan-clause-segmenter nil t)
;; gptel for Claude translation (soft load - optional)
(require 'gptel nil t)

;; Forward declaration: `tibetan-vocab--corpus' is defined as a
;; `defvar-local' in `core/tibetan-vocabulary-detailed.el'.  Declared
;; here so the byte-compiler treats it as a special (dynamic) variable
;; when `tibetan-analysis-generate-content' let-binds it to thread the
;; `#+TIBETAN_CORPUS:' header through the dictionary ranker.
(defvar tibetan-vocab--corpus)

;; Forward declaration: `tibetan-analysis--sanskrit-text-for-render'
;; is the dynamic var carrying the segment's `**** Sanskrit' walker
;; plist (see Phase 2 of sanskrit-parallel-workflow, 2026-04-27).
;; Phase 3 of two-language-parallel-analysis (2026-04-30):
;; `tibetan-analysis-create-file' (defined far above the var's main
;; defvar) consults the var to decide whether to emit a top-level
;; `* Sanskrit Text' section.  Forward-declare here so the byte-
;; compiler doesn't warn about the early reference; the actual
;; defvar lives near the renderer further down the file.
(defvar tibetan-analysis--sanskrit-text-for-render)

(defvar tibetan-analysis--target-lang nil
  "Primary-visible translation language for the current analysis.
Two canonical values:
  `\"de\"' — prefer German half of bilingual `DE // EN' glosses,
            produce German Claude translation.
  `\"en\"' — prefer English (same as nil — backward compat).
nil   — unset, defaults to English-preferred behaviour throughout.

Dynamically bound by `tibetan-analysis-generate-content' based on
the source document's `#+TIBETAN_TARGET_LANG:' header, so every
downstream renderer (Interlinear Gloss, CAT Gloss, Claude prompt
builder) can consult a single value without receiving an explicit
argument.  Set per-buffer via `setq-local' to override the header
for ad-hoc analyses.")


(defconst tibetan-analysis-version "1.0"
  "Version of the analysis file format.")

;; ============================================================================
;; TOKEN NORMALISATION
;; ============================================================================

(defun tibetan-analysis--clean-word-token (word)
  "Normalise a single Tibetan word token for dictionary lookup / display.
Strips surrounding whitespace, then removes every shad glyph
`།༎༏༐༑༔' plus its Wylie stand-in `/' (anywhere in the token —
a shad inside a single word is always upstream-tokenizer noise).

Matches the character class already used by
`tibetan-analysis--get-grammatical-role' (≈line 1068) and
`tibetan-analysis--build-cat-translation' (≈line 1390).  Extracted
2026-04-24 after live review of seg-16 of gal-chen-nyi-shu.org
showed a third sibling site (the `enriched-vocab-pairs' loop in
`tibetan-analysis-generate-content') stripped only TRAILING shads,
letting verse-start `།བྱང་ཆུབ་...' tokens leak into the Interlinear
link label as `/byang chub ...'."
  (replace-regexp-in-string "[།༎༏༐༑༔/]" "" (string-trim (or word ""))))

;; ============================================================================
;; CLAUDE-BASED SENSE OVERRIDE FOR INTERLINEAR — B1 + B2 (2026-04-24)
;; ============================================================================
;;
;; Problem (live review of seg-16 of gal-chen-nyi-shu.org, 2026-04-24):
;;
;;   B1: `blo sbyangs' (verb phrase, "having trained the mind") was
;;       glossed `<person> Cīrṇabuddhi, Trained Mind'.  Steinert's
;;       84000Dict only knows this two-syllable phrase as the name of
;;       the 547th buddha; there is no lexical verb-phrase entry to
;;       fall back to.  Claude correctly analyses the phrase as a verb
;;       in the clause `blo sbyangs na' ("if one trains the mind").
;;
;;   B2: standalone `na' (wylie) was glossed `(1) to' (the locative
;;       reading).  Claude Particles correctly tagged it as a
;;       conditional converb (Portfolio §2.8).  Bialek's standalone-`ན'
;;       rule ordering gives LOCATIVE before CONDITIONAL, so even when
;;       tokenised as a single particle the wrong label wins.
;;
;; Both bugs share a root cause: the Interlinear renderer only
;; consulted the dictionary stack, never Claude's own per-word output,
;; even when Claude had already delivered the correct disambiguation.
;; These helpers let the builder loop pull Claude's verdict in as a
;; final sense-picking step.  The dynamic variables
;; `tibetan-analysis--claude-vocabulary-for-render' and
;; `tibetan-analysis--claude-particles-for-render' are bound by
;; `tibetan-analysis-reanalyze-file' from the preserved on-disk Claude
;; sections; first-time generation runs with both nil and the helpers
;; degrade to no-ops.

(defun tibetan-analysis--token-wylie (word)
  "Return lowercase, trimmed Wylie for a single Tibetan WORD token.
Returns nil when `tibetan-to-wylie-fixed' is unavailable or the
conversion raises; the caller should fall back to dictionary-only
behaviour in that case.  Used by the Claude-override helpers that
need a canonical comparison key against Claude's Wylie-keyed data."
  (when (and word (stringp word) (not (string-empty-p word))
             (fboundp 'tibetan-to-wylie-fixed))
    (condition-case nil
        (let ((w (downcase (string-trim (tibetan-to-wylie-fixed word)))))
          (and (not (string-empty-p w)) w))
      (error nil))))

(defun tibetan-analysis--claude-particle-label-for-token (word particles)
  "Return a short Claude-derived particle label for WORD, or nil.
WORD is a Tibetan token (shad-stripped).  PARTICLES is the parsed
Claude Particles list returned by
`tibetan-analysis--parse-claude-particles' — each entry is a plist
`(:word W :particle P :sub-id ID :label L)'.

Matches the token's Wylie exactly against the `:particle' field
(verse particles are always single-word).  When found, returns a
formatted string `LABEL (§SUB-ID)' suitable for use as the
Interlinear's `short-meaning'.  When not found, or when PARTICLES
is nil / empty, returns nil — the caller keeps its current gloss."
  (when (and particles (listp particles))
    (let ((wylie (tibetan-analysis--token-wylie word)))
      (when wylie
        (let ((hit (cl-find-if
                    (lambda (entry)
                      (let ((p (plist-get entry :particle)))
                        (and p (string= (downcase (string-trim p)) wylie))))
                    particles)))
          (when hit
            (let ((label (plist-get hit :label))
                  (sub-id (plist-get hit :sub-id)))
              (cond
               ((and label sub-id) (format "%s (§%s)" label sub-id))
               (label label)
               (t nil)))))))))

(defun tibetan-analysis--claude-vocab-gloss-for-token (word vocab-alist)
  "Return the Claude-provided gloss for WORD from VOCAB-ALIST, or nil.
WORD is a Tibetan token.  VOCAB-ALIST is the parsed Claude
Vocabulary alist returned by `tibetan-analysis--parse-claude-vocabulary'
— each element is (WYLIE-KEY . FULL-LINE).  The line format produced
by Claude's system prompt is

    wylie-key, part-of-speech, \"gloss\", commentary

so the helper extracts the first double-quoted substring as the
short gloss.  Matches the token's Wylie as either equal to the
key or a space-bounded prefix of the key (so a stem-only token
matches a stem+particle MWU entry — `blo sbyangs' matches
`blo sbyangs na').  Returns nil when no match or no quoted gloss
field present."
  (when (and vocab-alist (listp vocab-alist))
    (let ((wylie (tibetan-analysis--token-wylie word)))
      (when wylie
        (let ((hit (cl-find-if
                    (lambda (pair)
                      (let ((key (car pair)))
                        (or (string= key wylie)
                            (string-prefix-p (concat wylie " ") key))))
                    vocab-alist)))
          (when hit
            (let ((line (cdr hit)))
              (when (string-match "\"\\([^\"]+\\)\"" line)
                (match-string 1 line)))))))))

(defun tibetan-analysis--claude-vocab-proper-noun-p (word vocab-alist)
  "Return Claude's proper-noun gloss (the name) for WORD, or nil.
VOCAB-ALIST is the parsed Claude Vocabulary alist — each element
is (WYLIE-KEY . FULL-LINE) with the line shaped

    wylie-key, part-of-speech, \"gloss\", commentary

When Claude's part-of-speech field (everything BEFORE the first
double-quoted gloss) classifies the token as a proper noun /
proper name — it contains the word `proper' — the helper returns
the quoted gloss (the name).  Otherwise nil.

Used to override a dictionary common-noun gloss that masks a
proper name with no Steinert `<person>'/`<place>' tag (e.g. `rngog'
glossed \"mane\" by Rangjung-Yeshe but named rNgog in context —
Milarepa Segment 110).  Examining only the pre-quote prefix keeps
a comma inside the gloss (`\"I, me\"') from being mistaken for the
POS field."
  (when (and vocab-alist (listp vocab-alist))
    (let ((wylie (tibetan-analysis--token-wylie word)))
      (when wylie
        (let ((hit (cl-find-if
                    (lambda (pair)
                      (let ((key (car pair)))
                        (or (string= key wylie)
                            (string-prefix-p (concat wylie " ") key))))
                    vocab-alist)))
          (when hit
            (let* ((line (cdr hit))
                   (pre (if (string-match "\"" line)
                            (substring line 0 (match-beginning 0))
                          line)))
              (when (string-match-p "\\bproper\\b" (downcase pre))
                (when (string-match "\"\\([^\"]+\\)\"" line)
                  (match-string 1 line))))))))))

(defun tibetan-analysis--apply-claude-vocab-override (word dict-gloss vocab-alist)
  "Override a proper-noun DICT-GLOSS with Claude's reading.

Two override paths, both gated on Claude Vocabulary having an entry
for WORD:

1. DICT-GLOSS begins with `<person>' or `<place>' — the Steinert
   84000Dict proper-noun tag markers — → prefer Claude's gloss.
   The 84000 data indexes buddha-names and place-names under short
   Tibetan phrases that double as common words (`blo sbyangs' =
   \"trained mind\" but also the 547th buddha); Claude, which sees
   full-clause context, recovers the lexical reading.

2. DICT-GLOSS is an UNTAGGED common-noun reading but Claude
   classifies WORD as a proper noun → prefer Claude's name.  This
   catches homographs whose dictionary entry carries no tag — e.g.
   `rngog' glossed \"mane\" by Rangjung-Yeshe but named rNgog
   (Mar pa's disciple) in context (Milarepa Segment 110).

Otherwise DICT-GLOSS is returned unchanged.  The `<term>' tag
(84000's canonical-term marker) is left intact — it IS the right
gloss when present."
  (let ((trimmed (and (stringp dict-gloss) (string-trim dict-gloss))))
    (cond
     ;; Path 1: Steinert proper-noun tag.
     ((and trimmed
           (or (string-prefix-p "<person>" trimmed)
               (string-prefix-p "<place>" trimmed)))
      (or (tibetan-analysis--claude-vocab-gloss-for-token word vocab-alist)
          dict-gloss))
     ;; Path 2: untagged common-noun gloss masking a Claude proper noun.
     (t
      (or (tibetan-analysis--claude-vocab-proper-noun-p word vocab-alist)
          dict-gloss)))))

(defvar tibetan-analysis--claude-vocabulary-for-render nil
  "Dynamic binding: parsed Claude-vocabulary alist for the in-flight render.
Parallel to `tibetan-analysis--claude-particles-for-render'.  Set by
callers that have just read the preserved `*** Claude Vocabulary'
body — `tibetan-analysis-reanalyze-file' does so before calling
`tibetan-analysis-generate-content'.  Consumed by the
enriched-vocab-pairs loop via
`tibetan-analysis--apply-claude-vocab-override' to rescue
polysemous tokens whose dictionary stack only offers proper-noun
glosses.  Nil → override is a no-op (first-time generate before
Claude has responded).")

;; ============================================================================
;; DISPLAY SETTINGS - Smaller roman text
;; ============================================================================

(defcustom tibetan-analysis-roman-scale 0.65
  "Scale factor for non-Tibetan (roman) text in analysis buffers.
Values less than 1.0 make text smaller, e.g. 0.65 = 65% size."
  :type 'float
  :group 'tibetan-cat)

(defcustom tibetan-analysis-show-clause-structure t
  "When non-nil, the generated analysis file includes a `** Clause
Structure' section populated from `tibetan-analyze-round2'.

The section lists, per clause, the clause type (main vs. dependent
+ the converb that makes it dependent), the clause's main verb,
the NPs found inside it with their case tags (ERG/ABS/DAT/LOC/
TERM/GEN/INST/COM), and any semantic-role assignments derivable
from the verb's Hill-DB case frame (agent, patient, goal, …).

Set to nil to suppress the section; existing analysis files are
only affected the next time they are regenerated."
  :type 'boolean
  :group 'tibetan-cat)

(defface tibetan-analysis-tibetan-face
  '((((class color) (background light)) :foreground "#1a237e")   ; deep indigo
    (((class color) (background dark))  :foreground "#aeb6ff")
    (t :inherit default))
  "Face applied to Tibetan script across analysis buffers so the
Tibetan words stand out from the Latin Wylie / glosses / English
labels — faster to find while reading aloud in class.  Applied via
font-lock with `append', so the more specific case-particle / converb
/ verb / gloss faces (which `prepend') still win on their own tokens.
Customise the colour to taste."
  :group 'tibetan-cat)

(defface tibetan-analysis-roman-face
  '((t :inherit default))
  "Face for roman (non-Tibetan) text in analysis buffers."
  :group 'tibetan-cat)

(defface tibetan-analysis-verb-face
  '((((class color) (background light)) :foreground "DodgerBlue3" :weight bold)
    (((class color) (background dark))  :foreground "DodgerBlue1" :weight bold)
    (t :inherit bold))
  "Face for the verb in Sentence Structure clause headers
\(`Clause N [...]: verb LEMMA').  A distinct blue makes each clause's
predicate jump out from its arguments.  Customise to taste."
  :group 'tibetan-cat)

(defface tibetan-analysis-structure-role-face
  '((((class color) (background light)) :foreground "DarkGreen" :weight bold)
    (((class color) (background dark))  :foreground "PaleGreen2" :weight bold)
    (t :inherit bold))
  "Face for the SUBJECT / OBJECT / oblique role labels in the Sentence
Structure section, so the argument skeleton is scannable at a glance.
Customise to taste."
  :group 'tibetan-cat)

(defface tibetan-analysis-case-particle-face
  '((((class color) (background light)) :foreground "magenta3" :weight bold)
    (((class color) (background dark))  :foreground "magenta1" :weight bold)
    (t :inherit org-verbatim))
  "Face for case-particle markers in the Particle Map.
Applied by remapping `org-verbatim' in analysis buffers so that
`=CASE=' wrappings used for genitive / ergative / terminative /
dative / locative / topic / comitative particles stand out visually
(magenta, bold) alongside the orange `~CONVERB~' wrappings.
Customise to taste — the default magenta matches common Buddhist-
studies classroom convention for case marking."
  :group 'tibetan-cat)

(defface tibetan-analysis-converb-particle-face
  '((((class color) (background light)) :foreground "dark orange" :weight bold)
    (((class color) (background dark))  :foreground "orange1" :weight bold)
    (t :inherit org-code))
  "Face for converb markers in the Particle Map.
Applied by remapping `org-code' in analysis buffers so that
`~CONVERB~' wrappings (ablative, coordinative, simultaneous,
causal, concessive converbs) are visually distinct from case
markers.  Customise to taste."
  :group 'tibetan-cat)

(defface tibetan-analysis-interlinear-gloss-face
  '((((class color) (background light)) :foreground "DarkCyan")
    (((class color) (background dark))  :foreground "PaleTurquoise2")
    (t :inherit font-lock-doc-face))
  "Face for the gloss content following each Wylie link in the
Interlinear Gloss section (U5, 2026-04-24).

The Interlinear renders `[[term-xxx][wylie]] [gloss]' per token;
the second bracket-pair carries the English / German translation
the reader is scanning for.  Without colour, students' eyes had
to parse identical-looking bracket structures (link text vs.
gloss) to find the translation.  A distinct cyan / turquoise
foreground makes the gloss pop without shouting — complements
the magenta / orange of the Particle Map faces above."
  :group 'tibetan-cat)

(defvar-local tibetan-analysis--faces-setup nil
  "Non-nil if faces have already been set up for this buffer.")

(defconst tibetan-analysis--particle-map-font-lock-keywords
  ;; Each regex has THREE capture groups:
  ;;   1. opening delimiter  (`=' or `~') — face + invisible
  ;;   2. particle content   (`'i' / `nas' / ...)   — face only
  ;;   3. closing delimiter  — face + invisible
  ;; The delimiters get `invisible' set to a namespaced symbol that
  ;; `tibetan-analysis-setup-faces' adds to the buffer-invisibility-
  ;; spec.  Result: students see a clean `'i' in magenta and `nas'
  ;; in orange, with no surrounding `=' / `~' characters — same UX
  ;; as `org-hide-emphasis-markers' for clean-boundary tokens but
  ;; extended to compound-embedded markers where org's emphasis
  ;; parser doesn't fire.
  '(("\\(=\\)\\([^=\n]+\\)\\(=\\)"
     (1 '(face tibetan-analysis-case-particle-face
          invisible tibetan-analysis-particle-marker)
        prepend)
     (2 'tibetan-analysis-case-particle-face prepend)
     (3 '(face tibetan-analysis-case-particle-face
          invisible tibetan-analysis-particle-marker)
        prepend))
    ("\\(~\\)\\([^~\n]+\\)\\(~\\)"
     (1 '(face tibetan-analysis-converb-particle-face
          invisible tibetan-analysis-particle-marker)
        prepend)
     (2 'tibetan-analysis-converb-particle-face prepend)
     (3 '(face tibetan-analysis-converb-particle-face
          invisible tibetan-analysis-particle-marker)
        prepend)))
  "Font-lock keywords for Particle Map markers in analysis buffers.

`=X=' → magenta (`tibetan-analysis-case-particle-face')
`~X~' → orange  (`tibetan-analysis-converb-particle-face')
Delimiters are rendered invisible; content stays visible.

Why font-lock rather than relying on `org-mode's emphasis parser:
org's emphasis regexp requires a word-boundary PRE character before
the opening marker.  The Particle Map renders compact Wylie
compounds like `mthu='i='' and `bslabs ~nas~' where the leading `='
or `~' is embedded in the token — preceded by a letter, not
whitespace.  Org silently skips emphasis parsing there; students
see plain-color markers instead of the intended magenta / orange,
and org's own `org-hide-emphasis-markers' feature doesn't hide
them either (same reason: no emphasis parse, nothing to hide).

Font-lock bypasses the PRE requirement entirely, applying the
face wherever the regex matches AND marking the delimiters
invisible — the three-group structure lets us treat the content
(group 2) and the wrapping (groups 1 + 3) differently.  The
`prepend' face-combining puts our explicit face ahead of any
org-verbatim / org-code the emphasis parser DID add for clean
word-boundary tokens, so rendering stays uniform across both
forms.")

(defconst tibetan-analysis--interlinear-gloss-font-lock-keywords
  ;; Match the gloss that follows each Wylie link in the Interlinear.
  ;; Pattern produced by `tibetan-interlinear--format-gloss-entry':
  ;;     [[term-xxx][wylie]] [gloss]
  ;;     [[term-xxx][wylie]] ★ [gloss]     ← curated Resources entry
  ;; The opening `]]' (close of the org link) followed by optional
  ;; `★ ' and then `[gloss]' is unique to the Interlinear — the
  ;; Detailed Dictionary uses bracketed source tags like
  ;; `[Steinert/43-84000Dict]' but never preceded by `]]', so the
  ;; face won't leak across sections.
  ;;
  ;; Single capture group: the gloss content.  The enclosing `[' `]'
  ;; stay plain so the reader still sees the bracket structure.
  '(("\\]\\] \\(?:★ \\)?\\[\\([^]\n]+\\)\\]"
     (1 'tibetan-analysis-interlinear-gloss-face prepend)))
  "Font-lock keywords for the Interlinear Gloss translation tier
\(U5, 2026-04-24).  Applies `tibetan-analysis-interlinear-gloss-face'
to the content inside the second bracket-pair following each Wylie
link — i.e. the English / German / target-language gloss — so it
visually pops from the surrounding Wylie and punctuation.")

(defconst tibetan-analysis--term-anchor-font-lock-keywords
  ;; Match `<<term-foo-bar>>' radio-target markers used as anchors
  ;; for the Detailed Dictionary entries the Interlinear links point
  ;; to.  Makes the markers invisible (display-only; the anchor is
  ;; still present in buffer for link resolution).
  ;;
  ;; Why bother hiding them: the renderer emits one `<<term-xxx>>'
  ;; line before every Detailed Dictionary `◆' entry.  Noisy on first
  ;; view — the reader's eye lands on `<<term-...>>' before the
  ;; Tibetan / Wylie it's actually trying to find.  Invisible
  ;; property drops them from display while keeping the anchor
  ;; functional, parallel to how the Particle Map's `=' / `~'
  ;; delimiters are hidden (U6, 2026-04-24).
  '(("<<\\(term-[a-z0-9-]+\\)>>"
     (0 '(face nil
          invisible tibetan-analysis-term-anchor)
        prepend)))
  "Font-lock keywords hiding `<<term-xxx>>' radio-target markers in
the Detailed Dictionary section (U6, 2026-04-24).  The markers
remain in the buffer text so `[[term-xxx][...]]' links still
resolve; they are simply not rendered — parallel to the
particle-map delimiter hiding in
`tibetan-analysis--particle-map-font-lock-keywords'.")

(defun tibetan-analysis--tibetan-script-matcher (limit)
  "Font-lock matcher: move point over the next run of Tibetan script
\(U+0F00–U+0FFF) up to LIMIT, setting match data.  Used instead of a
string matcher because a `[ༀ-࿿]' char-range as a STRING in
`font-lock-keywords' is silently dropped when other keywords are
present;  the same range works in this runtime `re-search-forward'."
  (re-search-forward "[ༀ-࿿]+" limit t))

(defconst tibetan-analysis--tibetan-script-font-lock-keywords
  ;; Colour every run of Tibetan script so the Tibetan words pop from
  ;; the surrounding Latin Wylie / glosses / labels.  Override `t' +
  ;; installed as the FIRST (base) keyword in
  ;; `tibetan-analysis-setup-faces';  the more specific verb /
  ;; case-particle / converb / gloss faces are added AFTER with
  ;; `prepend', so they still win on their own tokens.
  '((tibetan-analysis--tibetan-script-matcher
     (0 'tibetan-analysis-tibetan-face t)))
  "Font-lock keywords colouring Tibetan script across analysis buffers
\(2026-06-02) — the core \"highlight the Tibetan words\" aid.")

(defconst tibetan-analysis--structure-font-lock-keywords
  ;; Role-based highlighting for the Sentence Structure section.
  '(;; SUBJECT / OBJECT / oblique role labels (+ leading NP fallback).
    ("^    \\(SUBJECT\\|DIRECT OBJECT\\|INDIRECT OBJECT\\|LOCATIVE\\|GOAL\\|SOURCE\\|INSTRUMENT\\|COMITATIVE\\|NP\\)[^:\n]*:"
     (0 'tibetan-analysis-structure-role-face prepend))
    ;; The verb in a clause header: `Clause N [...]: verb LEMMA'.
    ;; Capture the lemma as a non-space run (NOT a `[ༀ-࿿]' char-range,
    ;; which font-lock drops as a string matcher) up to the ` [wylie]'.
    ("Clause [0-9]+ \\[[^]]*\\]: verb \\([^ \n]+\\)"
     (1 'tibetan-analysis-verb-face prepend)))
  "Font-lock keywords for the Sentence Structure section (2026-06-02):
SUBJECT / OBJECT / oblique labels in green-bold, the clause verb in
blue-bold, so the argument skeleton is scannable in class.")

(defun tibetan-analysis-setup-faces ()
  "Setup faces for analysis buffers.
Ensures Tibetan text remains readable at all heading levels and in
verbatim/code blocks which otherwise might use smaller fonts.
Also differentiates case particles (magenta) from converbs (orange)
in the Particle Map via font-lock — bypassing org's emphasis
parser which doesn't fire for compound-embedded markers like
`mthu='i='.  Only applies once per buffer to prevent accumulation."
  (unless tibetan-analysis--faces-setup
    ;; Ensure headings don't get too small (level 3+ used for dictionary entries)
    (face-remap-add-relative 'org-level-1 :height 1.1)
    (face-remap-add-relative 'org-level-2 :height 1.05)
    (face-remap-add-relative 'org-level-3 :height 1.0)  ; Keep readable for Tibetan headings

    ;; Height-only remap on org emphasis faces so verbatim / code text
    ;; stays readable regardless of theme; color is applied below via
    ;; font-lock so it works even for compound-embedded markers that
    ;; org's emphasis parser would skip.
    (face-remap-add-relative 'org-verbatim :height 1.0)
    (face-remap-add-relative 'org-code :height 1.0)

    ;; Register the namespaced invisibility symbols:
    ;;   · `tibetan-analysis-particle-marker' — hides `=' / `~' in
    ;;     Particle Map (Pass 6b polish, 2026-04-22).
    ;;   · `tibetan-analysis-term-anchor' — hides `<<term-xxx>>'
    ;;     radio targets in Detailed Dictionary (U6, 2026-04-24).
    ;; Using namespaced symbols (rather than `t') means only OUR
    ;; markers become invisible — org's own invisibility regions
    ;; (drawers, folded headings, other link targets) are unaffected.
    (add-to-invisibility-spec 'tibetan-analysis-particle-marker)
    (add-to-invisibility-spec 'tibetan-analysis-term-anchor)

    ;; Install buffer-local font-lock rules for the Particle Map markers,
    ;; the Interlinear gloss colour (U5), and the term-anchor hiding
    ;; (U6).  Done buffer-locally via `font-lock-add-keywords' with
    ;; `nil' mode so only this buffer picks them up.  Re-run
    ;; `font-lock-flush' immediately so existing content gets the face
    ;; on first render.
    ;; Role-based highlighting (2026-06-02).  The Tibetan-script base
    ;; layer is added FIRST (override `t') so every later keyword that
    ;; uses `prepend' (particle map, structure verb, gloss) layers its
    ;; more-specific colour ON TOP of the base Tibetan colour on shared
    ;; tokens.
    (font-lock-add-keywords
     nil tibetan-analysis--tibetan-script-font-lock-keywords 'append)
    (font-lock-add-keywords
     nil tibetan-analysis--particle-map-font-lock-keywords 'append)
    (font-lock-add-keywords
     nil tibetan-analysis--interlinear-gloss-font-lock-keywords 'append)
    (font-lock-add-keywords
     nil tibetan-analysis--term-anchor-font-lock-keywords 'append)
    ;; Sentence Structure role labels (green-bold) + clause verbs (blue).
    (font-lock-add-keywords
     nil tibetan-analysis--structure-font-lock-keywords 'append)
    (when (fboundp 'font-lock-flush)
      (font-lock-flush))

    (setq tibetan-analysis--faces-setup t)))

;; Hook to apply faces when buffer is displayed
(defun tibetan-analysis-mode-hook ()
  "Hook to run when entering an analysis buffer."
  (when (and (buffer-file-name)
             (string-match "analysis/seg-[0-9]+\\.org$" (buffer-file-name)))
    (tibetan-analysis-setup-faces)))

(add-hook 'org-mode-hook 'tibetan-analysis-mode-hook)

;; ============================================================================
;; PATH AND FILENAME FUNCTIONS
;; ============================================================================

(defun tibetan-analysis-get-folder ()
  "Get the analysis folder path for current buffer.
Creates the folder if it doesn't exist.
Returns the folder path."
  (let* ((source-file (buffer-file-name))
         (source-dir (file-name-directory source-file))
         (analysis-dir (expand-file-name "analysis" source-dir)))
    (unless (file-exists-p analysis-dir)
      (make-directory analysis-dir t)
      (message "Created analysis folder: %s" analysis-dir))
    analysis-dir))

(defun tibetan-analysis--extract-segment-number (seg-id)
  "Extract segment number from SEG-ID.
SEG-ID can be:
- A number: 5
- A simple string: \"5\" or \"seg-005\"
- A compound string: \"Segment 5\" or \"Sentence 1, Segment 5\"
Returns the segment number as an integer."
  (cond
   ((numberp seg-id) seg-id)
   ((stringp seg-id)
    (cond
     ;; "Segment N" or "Sentence X, Segment N" - extract N after "Segment"
     ((string-match "Segment \\([0-9]+\\)" seg-id)
      (string-to-number (match-string 1 seg-id)))
     ;; "seg-NNN" format
     ((string-match "seg-\\([0-9]+\\)" seg-id)
      (string-to-number (match-string 1 seg-id)))
     ;; Plain number string
     ((string-match "^\\([0-9]+\\)$" seg-id)
      (string-to-number (match-string 1 seg-id)))
     ;; Any number as fallback
     ((string-match "\\([0-9]+\\)" seg-id)
      (string-to-number (match-string 1 seg-id)))
     (t 1)))
   (t 1)))

(defun tibetan-analysis-segment-filename (seg-id)
  "Generate analysis filename for SEG-ID.
SEG-ID can be a number or string like \\='1\\=' or \\='seg-001\\='.
Returns filename like \\='seg-001.org\\='."
  (let ((num (tibetan-analysis--extract-segment-number seg-id)))
    (format "seg-%03d.org" num)))

(defun tibetan-analysis-get-filepath (seg-id &optional source-file)
  "Get full filepath for analysis of SEG-ID.
If SOURCE-FILE is provided, includes short name suffix."
  (let* ((folder (tibetan-analysis-get-folder))
         (short-name (when source-file
                       (tibetan-analysis-make-short-name source-file)))
         (num (tibetan-analysis--extract-segment-number seg-id))
         (filename (if short-name
                       (format "seg-%03d-%s.org" num short-name)
                     (format "seg-%03d.org" num))))
    (expand-file-name filename folder)))

(defun tibetan-analysis-paragraph-filename (par-id)
  "Generate analysis filename for paragraph PAR-ID.
PAR-ID can be an integer (131), a bare numeric string (\"131\"),
or a §-prefixed string (\"§131\").  Returns `par-NNN.org' with
three-digit zero padding."
  (let ((num (cond
              ((numberp par-id) par-id)
              ((and (stringp par-id)
                    (string-match "\\([0-9]+\\)" par-id))
               (string-to-number (match-string 1 par-id)))
              (t (error "Invalid paragraph id: %S" par-id)))))
    (format "par-%03d.org" num)))

(defun tibetan-analysis-get-paragraph-filepath (par-id)
  "Return full filepath for paragraph analysis PAR-ID."
  (expand-file-name (tibetan-analysis-paragraph-filename par-id)
                    (tibetan-analysis-get-folder)))

(defun tibetan-analysis-make-short-name (source-file)
  "Generate a short name suffix from SOURCE-FILE for analysis filenames.
E.g., \\='Tigress-Story-BlockPrint-Class.org\\=' -> \\='tigress\\='
      \\='Reading-Sa-skya-legs-bshad.org\\=' -> \\='saskya\\='
      \\='Reading-05-Padma.org\\=' -> \\='padma\\='."
  (when source-file
    (let* ((basename (file-name-sans-extension
                      (file-name-nondirectory source-file)))
           ;; Remove common prefixes
           (name (replace-regexp-in-string "^Reading-[0-9]*-?" "" basename))
           (name (replace-regexp-in-string "^Tigress-Story-" "" name))
           ;; Take first meaningful word
           (parts (split-string name "[-_]" t))
           (first-word (car parts)))
      (when first-word
        (downcase (substring first-word 0 (min 8 (length first-word))))))))

;; ============================================================================
;; HASH FUNCTIONS
;; ============================================================================

(defun tibetan-analysis-compute-hash (text)
  "Compute MD5 hash of TEXT for change detection."
  (md5 (encode-coding-string text 'utf-8)))

;; ============================================================================
;; FILE CREATION
;; ============================================================================

(defun tibetan-analysis-create-paragraph-file
    (par-id tibetan-text source-file auto-content &optional references)
  "Create a new paragraph analysis file for PAR-ID.
TIBETAN-TEXT is the paragraph body.  SOURCE-FILE is the path of the
comparative document.  AUTO-CONTENT is generated analysis content
(string).  REFERENCES, if non-nil, is an alist of (heading . body)
pairs from sibling translation sub-sections in the source paragraph
(e.g. `((\"Lopez 2006\" . \"...\") (\"Wangjié & Mulligan\" . \"...\"))');
they are written into a `* Reference Translations' top-level section
between `* Working Translation' and `* Auto-Analysis'.  Returns the
written filepath."
  (let* ((num (cond ((numberp par-id) par-id)
                    ((and (stringp par-id)
                          (string-match "\\([0-9]+\\)" par-id))
                     (string-to-number (match-string 1 par-id)))
                    (t (error "Invalid paragraph id: %S" par-id))))
         (filepath (tibetan-analysis-get-paragraph-filepath num))
         (hash (tibetan-analysis-compute-hash tibetan-text))
         (date (format-time-string "%Y-%m-%d"))
         (source-name (if source-file
                          (file-name-nondirectory source-file)
                        "")))
    (with-temp-file filepath
      (insert (format "#+TITLE: Paragraph %d Analysis\n" num))
      (insert "#+STARTUP: showall\n")
      ;; §5.22 follow-up (2026-05-21):  no TOC / no section numbering
      ;; on export — see segment scaffold comment.
      (insert "#+OPTIONS: toc:nil num:nil\n")
      (when source-file
        (insert (format "#+SOURCE: [[file:../%s::*§%d][%s / §%d]]\n"
                        source-name num source-name num)))
      (insert (format "#+TIBETAN_HASH: %s\n" hash))
      (insert (format "#+ANALYSIS_VERSION: %s\n" tibetan-analysis-version))
      (insert (format "#+CREATED: %s\n" date))
      (insert (format "#+LAST_ANALYZED: %s\n" date))
      (insert "\n")
      (insert "* Tibetan Text\n")
      (insert tibetan-text)
      (insert "\n\n")
      (insert "* My Notes\n\n\n")
      (insert "* Working Translation\n\n\n")
      (when references
        (insert "* Reference Translations\n")
        (insert "# Imported from the comparative source document.  ")
        (insert "Read-only by convention — edit only in the source.\n\n")
        (dolist (ref references)
          (insert (format "** %s\n%s\n\n" (car ref) (cdr ref)))))
      ;; Carve-out (Phase 1.2 of layout-revision §5.18, 2026-05-04):
      ;; paragraph files (`par-NNN.org') keep `* Auto-Analysis'.
      ;; Paragraph layout is not in the parallel-Sanskrit pipeline;
      ;; only segment files (`seg-NNN.org') receive the rename.
      (insert "* Auto-Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert auto-content)
      (insert "\n\n")
      (insert "* Apparatus\n")
      (insert "# Variants, philological notes, cross-references to "
              "Lopez/H/G/K/R/L footnotes.  Lives here (in the analysis "
              "file) rather than in the comparative source so the "
              "philological work is co-located with the translation "
              "work; the comparative source stays read-only.\n\n\n")
      (insert "* Footnotes\n\n")
      ;; Export safety (2026-05-18) — see segment create-file.
      (tibetan-analysis--strip-dangling-term-links-in-buffer))
    filepath))

(defun tibetan-analysis-create-file
    (seg-id tibetan-text source-file auto-content &optional folio)
  "Create a new analysis file for SEG-ID.
TIBETAN-TEXT is the Tibetan content.
SOURCE-FILE is the path to the source document.
AUTO-CONTENT is the generated analysis content (string).

FOLIO (optional) is a folio reference (e.g. \"D3a3\" for
Yogācārabhūmi sources).  When non-nil, written as a `:PROPERTIES:'
drawer under the `* Tibetan Text' heading so the reader can see
which folio they're on.  P6 (CLAUDE.md §6, addressed 2026-05-05)
restores the folio that §5.8.2's drawer-aware extractor was
correctly stripping from the source segment body.

§5.23 (2026-05-22):  threads SOURCE-FILE through
`tibetan-analysis-get-filepath' so writes go to the SUFFIXED
path `seg-NNN-SHORT.org' (e.g. `seg-006-gal.org' for
`gal-chen-nyi-shu.org').  Was previously UNSUFFIXED — that
worked for single-source folders but caused silent overwrites
when multiple source files shared one analysis/ folder (MA
Readings: gal-chen / lam-rim / title-colophon all collided on
seg-1..seg-21).  The §5.8.3 fix that originally dropped this
argument was symmetric — to keep the skip-check + create-path
matching, the skip-check in
`tibetan-auto-analyze-document' has the matching change."
  (let* ((filepath (tibetan-analysis-get-filepath seg-id source-file))
         (hash (tibetan-analysis-compute-hash tibetan-text))
         (date (format-time-string "%Y-%m-%d"))
         (source-name (file-name-nondirectory source-file))
         (seg-num (if (numberp seg-id) seg-id
                    (if (string-match "\\([0-9]+\\)" seg-id)
                        (string-to-number (match-string 1 seg-id))
                      1))))
    (with-temp-file filepath
      (insert (format "#+TITLE: Segment %d Analysis\n" seg-num))
      (insert "#+STARTUP: showall\n")
      ;; §5.22 follow-up (2026-05-21):  HTML / PDF / LaTeX export of
      ;; the analysis file does NOT carry an auto-generated table of
      ;; contents AND does NOT prefix headings with section numbers
      ;; (`1. My Notes' / `1.1. …').  The on-disk org headings already
      ;; structure the document — class-presentation is cleaner without
      ;; the numbered TOC overlay.
      (insert "#+OPTIONS: toc:nil num:nil\n")
      (insert (format "#+SOURCE: [[file:../%s::*Segment %d][%s / Segment %d]]\n"
                      source-name seg-num source-name seg-num))
      (insert (format "#+TIBETAN_HASH: %s\n" hash))
      (insert (format "#+ANALYSIS_VERSION: %s\n" tibetan-analysis-version))
      (insert (format "#+CREATED: %s\n" date))
      (insert (format "#+LAST_ANALYZED: %s\n" date))
      (insert "\n")
      ;; Phase 2.1 of layout-revision §5.18 (2026-05-04): Sanskrit-
      ;; first canonical order at create time — matches the class
      ;; workflow.  My Notes / Working Translation up top, Sanskrit
      ;; Text + Analysis above the Tibetan pair (Sanskrit Analysis
      ;; itself arrives via async Claude callback after create), then
      ;; Footnotes at the bottom.
      (insert "* My Notes\n\n\n")
      (insert "* Working Translation\n\n\n")
      ;; Phase 3 of two-language-parallel-analysis (2026-04-30):
      ;; emit `* Sanskrit Text' top-level when the dynamic var
      ;; `tibetan-analysis--sanskrit-text-for-render' is bound to a
      ;; non-nil walker plist (parallel mode + non-placeholder
      ;; `**** Sanskrit' sibling).  When nil the renderer returns
      ;; "" and nothing is inserted (non-parallel default).
      (insert (tibetan-analysis--render-sanskrit-source
               tibetan-analysis--sanskrit-text-for-render))
      ;; Tibetan Text follows the Sanskrit pair (Phase 2.1 reorder).
      (insert "* Tibetan Text\n")
      ;; P6 (2026-05-05):  preserve the source segment's `:FOLIO:'
      ;; reference as a `:PROPERTIES:' drawer under `* Tibetan Text'
      ;; when the caller threads one through.  Backwards-compatible:
      ;; without FOLIO the heading stays plain.
      (when (and folio (stringp folio)
                 (not (string-empty-p (string-trim folio))))
        (insert ":PROPERTIES:\n")
        (insert (format ":FOLIO: %s\n" (string-trim folio)))
        (insert ":END:\n"))
      (insert tibetan-text)
      (insert "\n\n")
      ;; Phase 1.2 of layout-revision (2026-05-04):  the parent
      ;; heading of the auto-content is `* Tibetan Analysis' (was
      ;; `* Auto-Analysis').
      (insert "* Tibetan Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert auto-content)
      (insert "\n\n")
      (insert "* Footnotes\n\n")
      ;; Export safety (2026-05-18):  strip Interlinear→DD dangling
      ;; term-* links from the freshly-built file so `org-export'
      ;; doesn't abort on the first broken anchor.  See
      ;; `tibetan-analysis--strip-dangling-term-links-in-buffer'.
      (tibetan-analysis--strip-dangling-term-links-in-buffer))
    filepath))

;; ============================================================================
;; FILE PARSING
;; ============================================================================

(defun tibetan-analysis-get-stored-hash (filepath)
  "Get the stored Tibetan hash from analysis file at FILEPATH."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+TIBETAN_HASH: \\(.+\\)$" nil t)
        (match-string 1)))))

(defun tibetan-analysis-check-sync (filepath tibetan-text)
  "Check if analysis at FILEPATH is in sync with TIBETAN-TEXT.
Returns t if in sync, nil if source has changed."
  (let ((stored-hash (tibetan-analysis-get-stored-hash filepath))
        (current-hash (tibetan-analysis-compute-hash tibetan-text)))
    (string= stored-hash current-hash)))

(defun tibetan-analysis-find-section-bounds (buffer section-name)
  "Find the start and end positions of SECTION-NAME in BUFFER.
Returns (START . END) or nil if not found."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward (format "^\\* %s$" (regexp-quote section-name)) nil t)
        (let ((start (line-beginning-position))
              (end (save-excursion
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (cons start end))))))

(defun tibetan-analysis-get-user-sections (filepath)
  "Extract user-content + machine-generated top-level sections from
analysis file at FILEPATH.

Returns alist of (section-name . content) for sections present.
Sections that don't exist in the file are simply omitted.

Sections collected:
  - User-edited:  My Notes, Working Translation, Reference
    Translations, Translation Comparison, Apparatus, Footnotes.
  - Machine-generated, top-level (preserved across reanalyse
    when not re-firing the underlying Claude / DM call):
    * Sanskrit Text                    (Phase 3 of two-language-
                                       parallel-analysis, 2026-04-30)
    * Sanskrit Analysis                (Phase 2)
    * Combined Analysis                (Phase 4)
    * DharmaMitra Translation (Tibetan)   (Phase A.1)
    * DharmaMitra Translation (Sanskrit)  (Phase A.2)
    * Sanskrit (DharmaMitra)           (realign feature, 2026-04-30)

Caller (typically `tibetan-analysis-regenerate-auto') re-emits
these in canonical order; preservation prevents reanalyse from
silently destroying the upstream-Claude / DM artefacts."
  (when (file-exists-p filepath)
    (with-temp-buffer
      (insert-file-contents filepath)
      (let ((sections '()))
        (dolist (section-name '("My Notes"
                                "Working Translation"
                                "Reference Translations"
                                "Translation Comparison"
                                "Apparatus"
                                "Footnotes"
                                ;; Phase 5 of two-language-parallel-
                                ;; analysis (2026-04-30): top-level
                                ;; analysis sections that must
                                ;; survive reanalyse-without-refire.
                                "Sanskrit Text"
                                "Sanskrit Analysis"
                                "Combined Analysis"
                                ;; Phase 1.1 of layout-revision
                                ;; (2026-05-04): the rename of
                                ;; `* Auto-Analysis' → `* Tibetan
                                ;; Analysis' for Sanskrit-first
                                ;; reading.  Listed here so the
                                ;; regenerator's alist consumer
                                ;; sees the new heading on already-
                                ;; migrated files.  Auto-content
                                ;; bodies are always regenerated
                                ;; (never preserved verbatim), so
                                ;; this is a discoverability hook
                                ;; rather than a content-preservation
                                ;; hook.
                                "Tibetan Analysis"
                                "DharmaMitra Translation (Tibetan)"
                                "DharmaMitra Translation (Sanskrit)"
                                "Sanskrit (DharmaMitra)"))
          (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) section-name)))
            (when bounds
              (let* ((start (car bounds))
                     (end (cdr bounds))
                     (content (buffer-substring-no-properties start end)))
                (push (cons section-name content) sections)))))
        (nreverse sections)))))

;; ============================================================================
;; Dangling [[term-X][...]] link stripper (export safety, 2026-05-18)
;; ============================================================================
;;
;; The Interlinear Gloss and Detailed Dictionary use independent MWU
;; tokenization paths.  When they disagree on how to group syllables
;; (e.g. Interlinear treats `zla ba' + `bzhin' as two stems while DD
;; joins them into `zla ba bzhin'), the Interlinear emits links like
;; `[[term-zla-ba][zla ba]]' whose `<<term-zla-ba>>' anchor DD never
;; produces.  `org-export-dispatch' aborts on the first such broken
;; link, blocking PDF / HTML export of analysis files for class
;; handout.
;;
;; This is a defensive post-pass:  scan the buffer for term-* links,
;; replace any whose anchor is absent with the plain label text.
;; The root cause — divergent MWU tokenization between Interlinear
;; and DD — is left for follow-up;  this guard makes the export
;; class crash-safe regardless of how the divergence happens.

;; ============================================================================
;; §5.23 (2026-05-22) — Migration: unsuffixed → suffixed analysis filenames
;; ============================================================================
;;
;; Older analysis folders (pre-§5.23) carry `seg-NNN.org' /
;; `sent-NNN.org' filenames without the per-source short-name suffix.
;; That worked for single-source folders (Milarepa) but caused silent
;; overwrites in multi-source folders (MA Reading:  gal-chen, lam-rim,
;; title-colophon all colliding on seg-001..seg-021).
;;
;; This helper walks a folder, reads each file's `#+SOURCE:' link to
;; identify its source-doc, derives the short-name via
;; `tibetan-analysis-make-short-name', and renames the file in place:
;;   `seg-006.org'  →  `seg-006-gal.org' (if source = gal-chen-nyi-shu.org)
;;
;; Idempotent — already-suffixed filenames are left alone.  Skips files
;; with no `#+SOURCE:' link (the short-name can't be derived).

;;;###autoload
(defun tibetan-analysis-migrate-suffix-in-folder (&optional folder)
  "Walk FOLDER and rename unsuffixed analysis files to suffixed form.

For each `seg-NNN.org' or `sent-NNN.org' in FOLDER that lacks a
short-name suffix, reads the file's `#+SOURCE:' header to identify
the source document, derives a short-name via
`tibetan-analysis-make-short-name', and renames the file in place
to `seg-NNN-SHORT.org' / `sent-NNN-SHORT.org'.

Already-suffixed filenames are skipped (idempotent).  Files
without a `#+SOURCE:' link are skipped (no source to derive
short-name from).  Returns a plist summary:
  (:folder F :total N :renamed N-ren :skipped N-skip :failed N-bad)

FOLDER defaults to the analysis folder of the current buffer
\(via `tibetan-analysis-get-folder', falling back to
`default-directory').  Interactive callers get a final-state
`message'.

§5.23 (2026-05-22) — companion to the create-file fix that
restored per-source filename suffixes.  Existing pre-§5.23
folders need a one-shot run of this command to migrate;  newly-
created files after the fix are already suffixed at creation."
  (interactive)
  (let* ((folder (or folder
                     (and (buffer-file-name)
                          (tibetan-analysis-get-folder))
                     (read-directory-name "Analysis folder: " nil nil t)))
         (all (and (file-directory-p folder)
                   (directory-files folder t
                                    "\\`\\(seg\\|sent\\)-[0-9]+\\.org\\'")))
         (renamed 0) (skipped 0) (failed 0)
         (results '()))
    (unless all
      (user-error "No unsuffixed analysis files in %s" folder))
    (dolist (path all)
      (let* ((base (file-name-nondirectory path))
             (prefix (if (string-prefix-p "sent-" base) "sent" "seg"))
             (num (and (string-match "\\`\\(?:seg\\|sent\\)-\\([0-9]+\\)\\.org\\'" base)
                       (match-string 1 base)))
             (source-rel (with-temp-buffer
                           (insert-file-contents path)
                           (goto-char (point-min))
                           (when (re-search-forward
                                  "^#\\+SOURCE:[ \t]*\\[\\[file:\\([^]:]+\\)"
                                  nil t)
                             (match-string 1))))
             (source-abs (and source-rel
                              (expand-file-name
                               source-rel (file-name-directory path))))
             (short (and source-abs
                         (tibetan-analysis-make-short-name source-abs)))
             (new-base (and short num
                            (format "%s-%s-%s.org" prefix num short)))
             (new-path (and new-base
                            (expand-file-name new-base
                                              (file-name-directory path)))))
        (cond
         ((null short)
          (cl-incf skipped)
          (push (list :file base :status :no-source) results))
         ((file-exists-p new-path)
          ;; Target already exists — don't clobber.
          (cl-incf skipped)
          (push (list :file base :status :target-exists :target new-base)
                results))
         (t
          (condition-case e
              (progn
                (rename-file path new-path)
                (cl-incf renamed)
                (push (list :file base :status :renamed :to new-base)
                      results))
            (error
             (cl-incf failed)
             (push (list :file base :status :error
                         :error (error-message-string e))
                   results)))))))
    (let ((summary `(:folder ,folder
                     :total ,(length all)
                     :renamed ,renamed
                     :skipped ,skipped
                     :failed ,failed
                     :results ,(nreverse results))))
      (message
       "Suffix migration:  %d renamed / %d skipped / %d failed of %d files in %s"
       renamed skipped failed (length all)
       (file-name-nondirectory (directory-file-name folder)))
      summary)))

;;;###autoload
(defun tibetan-analysis-strip-dangling-term-links-in-folder (&optional folder)
  "Walk FOLDER (default: analysis/ next to current source) and strip
dangling `[[term-X][...]]' links from every `seg-*.org' /
`sent-*.org' / `par-*.org' / `compound-*.org' analysis file.

Saves files that changed; leaves files with no dangles untouched.
Reports the total per-file dangle count + how many files were
modified.

Useful one-shot recovery for analysis files generated before
the 2026-05-18 dangling-link guard landed — without this command
the user would have to re-run `C-c u r' (batch reanalyse) on the
folder, which is much slower and re-fires Claude requests."
  (interactive)
  (let* ((folder (or folder
                     (when (buffer-file-name)
                       (expand-file-name
                        "analysis"
                        (file-name-directory (buffer-file-name))))
                     (read-directory-name "Analysis folder: ")))
         (files
          (and (file-directory-p folder)
               (directory-files
                folder t
                "^\\(seg\\|sent\\|par\\|compound\\)-.*\\.org\\'")))
         (modified 0)
         (total-stripped 0))
    (unless files
      (user-error "No analysis files found in %s" folder))
    (dolist (file files)
      (with-current-buffer (find-file-noselect file)
        (let ((n (tibetan-analysis--strip-dangling-term-links-in-buffer)))
          (when (> n 0)
            (cl-incf modified)
            (cl-incf total-stripped n)
            (save-buffer))
          (set-buffer-modified-p nil))))
    (message "Stripped %d dangling link(s) across %d file(s) (of %d)."
             total-stripped modified (length files))
    (list :files (length files) :modified modified :stripped total-stripped)))

(defun tibetan-analysis--strip-dangling-term-links-in-buffer ()
  "Strip dangling `[[term-X][label]]' links from the current buffer.

For each `[[term-X][label]]' org link whose `<<term-X>>' anchor
is absent from the SAME buffer, replace the link with just the
plain LABEL text.  Anchored links — those whose target exists —
are left untouched, as are non-`term-*' links (id:, file:, http:,
arbitrary internal anchors).

Returns the number of links stripped (for telemetry / tests).

Defensive post-pass run by `tibetan-analysis-create-file' and
`tibetan-analysis-regenerate-auto' so generated analysis files
are export-safe.  The root cause of the divergence — Interlinear
and Detailed Dictionary using independent MWU tokenization paths
that can disagree — is tracked separately."
  (save-excursion
    (let* ((anchors
            (let ((set (make-hash-table :test 'equal)))
              (goto-char (point-min))
              (while (re-search-forward
                      "<<\\(term-[^>]+\\)>>" nil t)
                (puthash (match-string-no-properties 1) t set))
              set))
           (stripped 0))
      (goto-char (point-min))
      (while (re-search-forward
              "\\[\\[\\(term-[^]]+\\)\\]\\[\\([^]]*\\)\\]\\]" nil t)
        (let ((target (match-string-no-properties 1))
              (label (match-string-no-properties 2)))
          (unless (gethash target anchors)
            ;; LITERAL = t — `label' is inserted verbatim, so a `\\1'
            ;; or similar inside the label can't be misinterpreted as
            ;; a replacement-string backreference.
            (replace-match label t t)
            (cl-incf stripped))))
      stripped)))

;; ============================================================================
;; REGENERATE AUTO-ANALYSIS
;; ============================================================================

(defun tibetan-analysis-regenerate-auto (filepath tibetan-text auto-content)
  "Regenerate the Auto-Analysis section in FILEPATH.
Preserves user sections (My Notes, Working Translation, Footnotes)
and reshapes the file into the canonical section order:

  * Tibetan Text
  * My Notes                     — user-edited (above Auto-Analysis
  * Working Translation            so notes sit beside the Tibetan
                                   during class-prep reading)
  * Auto-Analysis                — regenerated
  * Footnotes                    — user-edited, footnote-like tail

Any pre-existing section content for My Notes / Working Translation
/ Footnotes is preserved verbatim; only its position in the file
may change.  Files already in canonical order are left untouched
except for Auto-Analysis + header metadata.  Idempotent: repeated
runs produce identical output.

Updates `#+TIBETAN_HASH' and `#+LAST_ANALYZED' as a side-effect."
  (let* ((user-sections (tibetan-analysis-get-user-sections filepath))
         (my-notes
          (cdr (assoc "My Notes" user-sections)))
         (working-translation
          (cdr (assoc "Working Translation" user-sections)))
         (reference-translations
          (cdr (assoc "Reference Translations" user-sections)))
         (translation-comparison
          (cdr (assoc "Translation Comparison" user-sections)))
         (apparatus
          (cdr (assoc "Apparatus" user-sections)))
         (footnotes
          (cdr (assoc "Footnotes" user-sections)))
         ;; Phase 5 of two-language-parallel-analysis (2026-04-30):
         ;; preserve the new top-level analysis sections.  The
         ;; Sanskrit Text body is regenerable from the walker, but
         ;; we read the existing one as a fallback; Sanskrit /
         ;; Combined Analysis are Claude-authored and must round-
         ;; trip verbatim when not re-firing.  DM sections
         ;; similarly preserved (latent regression — DM previously
         ;; got dropped on every reanalyse without `:re-request-
         ;; claude t').
         (existing-sanskrit-text
          (cdr (assoc "Sanskrit Text" user-sections)))
         (sanskrit-text-fresh
          (and (boundp 'tibetan-analysis--sanskrit-text-for-render)
               tibetan-analysis--sanskrit-text-for-render
               (tibetan-analysis--render-sanskrit-source
                tibetan-analysis--sanskrit-text-for-render)))
         (sanskrit-text
          (or (and sanskrit-text-fresh
                   (not (string-empty-p sanskrit-text-fresh))
                   sanskrit-text-fresh)
              existing-sanskrit-text))
         (sanskrit-analysis
          (cdr (assoc "Sanskrit Analysis" user-sections)))
         (combined-analysis
          (cdr (assoc "Combined Analysis" user-sections)))
         (dm-tibetan
          (cdr (assoc "DharmaMitra Translation (Tibetan)" user-sections)))
         ;; Read the NESTED `** DharmaMitra Translation' body from
         ;; the CURRENT file state BEFORE the buffer is erased.  See
         ;; the post-save migration block for how this is restored
         ;; into the regenerated file's new nested location.
         (dm-tibetan-nested-body
          (and (file-exists-p filepath)
               (tibetan-analysis--read-dharmamitra-tibetan-nested-body
                filepath)))
         ;; §5.21 Commit 6/7 (2026-05-20):  read the NESTED `**
         ;; Provided Translations' body BEFORE buffer erase so the
         ;; user's hand-pasted reference translations survive
         ;; regenerate verbatim.  Renderer emits an empty PT
         ;; placeholder;  the post-save block below re-injects this
         ;; body into the freshly-regenerated location.
         (pt-nested-body
          (and (file-exists-p filepath)
               (tibetan-analysis--read-provided-translations-nested-body
                filepath)))
         (dm-sanskrit
          (cdr (assoc "DharmaMitra Translation (Sanskrit)" user-sections)))
         (sanskrit-dharmamitra
          (cdr (assoc "Sanskrit (DharmaMitra)" user-sections)))
         (hash (tibetan-analysis-compute-hash tibetan-text))
         (date (format-time-string "%Y-%m-%d"))
         ;; Capture the existing file header (everything before the
         ;; first `* ' heading) so we keep `#+TITLE', `#+SOURCE' etc.
         (header
          (with-temp-buffer
            (insert-file-contents filepath)
            (goto-char (point-min))
            (if (re-search-forward "^\\* " nil t)
                (buffer-substring-no-properties
                 (point-min) (line-beginning-position))
              ""))))
    (with-current-buffer (find-file-noselect filepath)
      ;; Full rewrite into canonical order.  We read everything we
      ;; want to preserve into local vars above, erase the buffer,
      ;; then re-emit in the canonical shape — cleaner than trying
      ;; to splice with in-place edits when sections may be in any
      ;; pre-existing order.
      (erase-buffer)
      (insert header)
      ;; Ensure header ends with a blank line before `* '
      (unless (or (string-empty-p header)
                  (string-suffix-p "\n\n" header))
        (insert "\n"))
      ;; Update hash + date in the re-emitted header
      (goto-char (point-min))
      (if (re-search-forward "^#\\+TIBETAN_HASH: .+$" nil t)
          (replace-match (format "#+TIBETAN_HASH: %s" hash))
        ;; Insert missing hash line just after #+TITLE
        (goto-char (point-min))
        (when (re-search-forward "^#\\+TITLE:.+$" nil t)
          (end-of-line)
          (insert (format "\n#+TIBETAN_HASH: %s" hash))))
      (goto-char (point-min))
      (if (re-search-forward "^#\\+LAST_ANALYZED: .+$" nil t)
          (replace-match (format "#+LAST_ANALYZED: %s" date))
        (goto-char (point-max))
        (when (re-search-backward "^#\\+" nil t)
          (end-of-line)
          (insert (format "\n#+LAST_ANALYZED: %s" date))))
      ;; Phase 2.1 of layout-revision §5.18 (2026-05-04): Sanskrit-
      ;; first canonical order for the per-segment file.  Ordering
      ;; below matches the class workflow that reads the Sanskrit
      ;; first, translates it, then checks the Tibetan against it.
      ;;
      ;;   * My Notes                            user-edited (top)
      ;;   * Working Translation                 user-edited
      ;;   * Reference Translations              optional, paragraph-mode only
      ;;   * Translation Comparison              optional, paragraph-mode only
      ;;   * Sanskrit Text                       parallel-mode only
      ;;   * Sanskrit Analysis                   parallel-mode only
      ;;   * Tibetan Text                        ← was first; now slot 6
      ;;   * Tibetan Analysis                    regenerated content
      ;;   * Combined Analysis                   parallel-mode only
      ;;   * Apparatus                           optional, paragraph-mode only
      ;;   * Footnotes                           user-edited (always present)
      ;;   * DharmaMitra Translation (Sanskrit)  ← Sanskrit-first
      ;;   * DharmaMitra Translation (Tibetan)
      ;;   * Sanskrit (DharmaMitra)              legacy realign output

      (goto-char (point-max))
      ;; My Notes — preserved.  If not present before, emit an empty
      ;; placeholder so the section exists for the user to edit into.
      (insert (or my-notes "* My Notes\n\n\n"))
      (unless (string-suffix-p "\n\n" (or my-notes ""))
        (insert "\n"))
      (insert (or working-translation "* Working Translation\n\n\n"))
      (unless (string-suffix-p "\n\n" (or working-translation ""))
        (insert "\n"))
      ;; Reference Translations — paragraph-only, preserved verbatim
      ;; if present.  Only emitted when the original file had it
      ;; (avoids polluting seg-NNN.org with an empty section).
      (when reference-translations
        (insert reference-translations)
        (unless (string-suffix-p "\n\n" reference-translations)
          (insert "\n")))
      ;; Translation Comparison — paragraph-only, refreshed by an
      ;; explicit `C-c u T' (NOT by reanalyze).  Preserved verbatim.
      (when translation-comparison
        (insert translation-comparison)
        (unless (string-suffix-p "\n\n" translation-comparison)
          (insert "\n")))
      ;; Phase 3 of two-language-parallel-analysis (2026-04-30) +
      ;; Phase 2.1 of layout-revision §5.18 (2026-05-04): emit
      ;; `* Sanskrit Text' BEFORE `* Tibetan Text' for the Sanskrit-
      ;; first reading order.
      (when (and sanskrit-text (not (string-empty-p sanskrit-text)))
        (insert sanskrit-text)
        (unless (string-suffix-p "\n\n" sanskrit-text)
          (insert "\n")))
      ;; Phase 2 of two-language-parallel-analysis (2026-04-30) +
      ;; Phase 2.1 of layout-revision §5.18 (2026-05-04): preserve
      ;; `* Sanskrit Analysis' verbatim, emit BEFORE Tibetan pair
      ;; for the Sanskrit-first reading order.
      (when sanskrit-analysis
        (insert sanskrit-analysis)
        (unless (string-suffix-p "\n\n" sanskrit-analysis)
          (insert "\n")))
      ;; Tibetan Text + Tibetan Analysis (Phase 1.2 + 2.1):  emitted
      ;; AFTER the Sanskrit pair so the reader can compare them
      ;; side-by-side after working out the Sanskrit translation.
      (insert "* Tibetan Text\n")
      (insert tibetan-text)
      (insert "\n\n")
      (insert "* Tibetan Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert auto-content)
      (insert "\n\n")
      ;; Phase 4 of two-language-parallel-analysis (2026-04-30):
      ;; preserve `* Combined Analysis' verbatim when not re-firing.
      (when combined-analysis
        (insert combined-analysis)
        (unless (string-suffix-p "\n\n" combined-analysis)
          (insert "\n")))
      ;; Apparatus — paragraph-only section, preserved verbatim if
      ;; present.  Conditional emission keeps segment-reanalyze
      ;; backwards-compatible.
      (when apparatus
        (insert apparatus)
        (unless (string-suffix-p "\n\n" apparatus)
          (insert "\n")))
      (insert (or footnotes "* Footnotes\n\n"))
      (unless (string-suffix-p "\n\n" (or footnotes ""))
        (insert "\n"))
      ;; Phase A.1 / A.2 of multi-translator-parallel-reading
      ;; (2026-04-30) + Phase 2.1 of layout-revision §5.18
      ;; (2026-05-04):  Sanskrit-side DharmaMitra emitted FIRST,
      ;; matching the Sanskrit-first reading order.
      (when dm-sanskrit
        (insert dm-sanskrit)
        (unless (string-suffix-p "\n\n" dm-sanskrit)
          (insert "\n")))
      ;; Tibetan-side DharmaMitra is NO LONGER emitted at top-level
      ;; (2026-05-19 layout revision).  The captured `dm-tibetan'
      ;; body is migrated into `** DharmaMitra Translation' (level-2
      ;; inside `* Tibetan Analysis') via the post-save migration
      ;; helper below — see comment after `save-buffer'.
      (when sanskrit-dharmamitra
        (insert sanskrit-dharmamitra)
        (unless (string-suffix-p "\n\n" sanskrit-dharmamitra)
          (insert "\n")))
      ;; Export safety (2026-05-18):  strip Interlinear→DD dangling
      ;; term-* links before save so `org-export' doesn't abort on
      ;; the first broken anchor.  See
      ;; `tibetan-analysis--strip-dangling-term-links-in-buffer'
      ;; for the divergence root cause.
      (tibetan-analysis--strip-dangling-term-links-in-buffer)
      (save-buffer)
      ;; Tibetan DharmaMitra preservation + migration (2026-05-19):
      ;; the legacy top-level `* DharmaMitra Translation (Tibetan)'
      ;; section has been retired in favour of `** DharmaMitra
      ;; Translation' nested under `* Tibetan Analysis' (peer of
      ;; `** Translation').  Body is preserved across regenerate
      ;; by reading from EITHER location and restoring at the new
      ;; nested location:
      ;;   - First regenerate of a legacy file:  `dm-tibetan' has
      ;;     the top-level body;  read + extract + restore.
      ;;   - Subsequent regenerates:  `dm-tibetan' is nil (top-level
      ;;     section already gone);  read body from the new nested
      ;;     location (saved by prior regenerate or by the async DM
      ;;     writer) and restore it again after auto-content rewrite.
      ;; Placeholder / awaiting stubs are skipped — they're already
      ;; emitted by the auto-content renderer.
      (when (fboundp 'tibetan-dharmamitra-translation--write-nested-tibetan-section)
        (let ((body (or dm-tibetan-nested-body
                        (and dm-tibetan
                             (tibetan-analysis--extract-section-body
                              dm-tibetan)))))
          (when (and body
                     (not (string-empty-p body))
                     (not (string-match-p "\\`\\[Awaiting" body))
                     (not (string-match-p "\\`\\[Requesting" body))
                     (not (string-match-p "\\`\\[Translation not available" body)))
            (tibetan-dharmamitra-translation--write-nested-tibetan-section
             filepath body))))
      ;; §5.21 Commit 6/7 (2026-05-20):  re-inject the preserved
      ;; `** Provided Translations' body into the freshly-regenerated
      ;; file.  The renderer emitted an empty placeholder above; if
      ;; the user had any hand-pasted reference translations in the
      ;; previous file state, write them back now.
      (when (and pt-nested-body
                 (not (string-empty-p pt-nested-body)))
        (tibetan-analysis--write-nested-provided-translations-body
         filepath pt-nested-body))
      (message "Re-analyzed segment. User notes preserved and reshaped."))))

(defun tibetan-analysis--read-dharmamitra-tibetan-nested-body (filepath)
  "Return the trimmed body of `** DharmaMitra Translation' inside
`* Tibetan Analysis' in FILEPATH, or nil when absent / empty /
a placeholder.

Used by `tibetan-analysis-regenerate-auto' to preserve the
DharmaMitra Tibetan body across regenerates (the body sits
inside the auto-content region and would otherwise be erased
by the rewrite pass)."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Analysis$" nil t)
        (let ((parent-end (save-excursion
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max)))))
          (when (re-search-forward
                 "^\\*\\* DharmaMitra Translation[ \t]*$" parent-end t)
            (forward-line 1)
            ;; Skip property drawer if present.
            (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
              (when (re-search-forward "^[ \t]*:END:[ \t]*$" parent-end t)
                (forward-line 1)))
            (let* ((body-start (point))
                   (body-end (save-excursion
                               (if (re-search-forward
                                    "^\\*\\{1,2\\}[^*\n]\\|^\\* " parent-end t)
                                   (line-beginning-position)
                                 parent-end)))
                   (body (string-trim
                          (buffer-substring-no-properties
                           body-start body-end))))
              (and (not (string-empty-p body)) body))))))))

(defun tibetan-analysis--read-provided-translations-nested-body (filepath)
  "Return the trimmed body of `** Provided Translations' inside
`* Tibetan Analysis' in FILEPATH, or nil when absent / empty.

§5.21 Commit 6/7 (2026-05-20):  used by
`tibetan-analysis-regenerate-auto' to preserve the user's hand-
pasted reference translations (Roehrich, Lopez, published English
versions, …) across regenerates.  Pattern modelled on the §5.20
`--read-dharmamitra-tibetan-nested-body' helper.

On legacy files (where the body still carries the now-retired
auto-children `*** CAT Gloss' / `*** Claude Vocabulary' / `***
Reference Translations'), this returns the body verbatim
including those subtrees;  the renderer no longer emits them,
so on subsequent regenerates they sit harmlessly in the user-
content slot.  Carsten can manually delete them on first inspect
if desired (one-shot manual sweep)."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Analysis$" nil t)
        (let ((parent-end (save-excursion
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max)))))
          (when (re-search-forward
                 "^\\*\\* Provided Translations[ \t]*$" parent-end t)
            (forward-line 1)
            ;; Skip property drawer if present.
            (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
              (when (re-search-forward "^[ \t]*:END:[ \t]*$" parent-end t)
                (forward-line 1)))
            (let* ((body-start (point))
                   (body-end (save-excursion
                               (if (re-search-forward
                                    "^\\*\\{1,2\\}[^*\n]\\|^\\* " parent-end t)
                                   (line-beginning-position)
                                 parent-end)))
                   (body (string-trim
                          (buffer-substring-no-properties
                           body-start body-end))))
              (and (not (string-empty-p body)) body))))))))

(defun tibetan-analysis--write-nested-provided-translations-body
    (filepath body)
  "Write BODY into the nested `** Provided Translations' section of
FILEPATH (inside `* Tibetan Analysis'), replacing whatever empty
placeholder the renderer emitted.

§5.21 Commit 6/7 (2026-05-20):  called by
`tibetan-analysis-regenerate-auto' AFTER `save-buffer' to re-
inject the user's preserved Provided Translations body into the
freshly-regenerated file at the new nested location.  Mirror of
the §5.20 DM-Tibetan nested writer in
`tibetan-dharmamitra-translation.el'.

Pre-conditions:
  · FILEPATH exists and is in the §5.21 on-disk layout (carries
    `* Tibetan Analysis' parent + nested `** Provided
    Translations' placeholder).  No-op when the section is absent.
  · BODY is a non-empty string (caller skips the call when no
    preserved body exists)."
  (when (and filepath (file-exists-p filepath)
             body (stringp body) (not (string-empty-p body)))
    (with-current-buffer (find-file-noselect filepath)
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^\\* Tibetan Analysis$" nil t)
          (let ((parent-end (save-excursion
                              (if (re-search-forward "^\\* " nil t)
                                  (line-beginning-position)
                                (point-max)))))
            (when (re-search-forward
                   "^\\*\\* Provided Translations[ \t]*$"
                   parent-end t)
              (forward-line 1)
              ;; Skip a property drawer if present.
              (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
                (when (re-search-forward "^[ \t]*:END:[ \t]*$"
                                         parent-end t)
                  (forward-line 1)))
              (let ((body-start (point))
                    (body-end (save-excursion
                                (if (re-search-forward
                                     "^\\*\\{1,2\\}[^*\n]\\|^\\* "
                                     parent-end t)
                                    (line-beginning-position)
                                  parent-end))))
                (delete-region body-start body-end)
                (goto-char body-start)
                (insert (string-trim-right body) "\n\n"))
              (save-buffer))))))))

(defun tibetan-analysis--extract-section-body (section-text)
  "Extract just the body of a captured org section.

SECTION-TEXT is the full section text including heading line +
optional property drawer + body, as captured by
`tibetan-analysis-get-user-sections'.  Returns the trimmed body
\(everything after the heading line and an optional `:PROPERTIES:
… :END:' drawer);  nil when SECTION-TEXT is nil / empty.

Used by the regenerate-auto migration path to extract just the
body of a captured top-level section so it can be re-inserted
at a different location (e.g. legacy `* DharmaMitra Translation
\(Tibetan)' body → nested `** DharmaMitra Translation' under
`* Tibetan Analysis')."
  (when (and section-text (stringp section-text)
             (not (string-empty-p section-text)))
    (with-temp-buffer
      (insert section-text)
      (goto-char (point-min))
      ;; Skip the heading line.
      (forward-line 1)
      ;; Skip an optional property drawer.
      (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
        (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
          (forward-line 1)))
      (let ((body (string-trim
                   (buffer-substring-no-properties (point) (point-max)))))
        (and (not (string-empty-p body)) body)))))

;; ============================================================================
;; GENERATE AUTO-CONTENT - Improved format with inline annotations
;; ============================================================================

;; ============================================================================
;; REFERENCE TRANSLATION EXTRACTION
;; ============================================================================

(defun tibetan-analysis--find-resources-dir ()
  "Find the Resources directory for the current document.
Walks up from the source file directory, checking each ancestor
for a Resources/ subfolder (up to 5 levels).  This handles typical
layouts where the analysis file lives several levels below the
Resources folder, e.g.
  Tibetisch IV/Resources/
  Tibetisch IV/work in progress/analysis/seg-004.org"
  (let ((source-file (or (buffer-file-name)
                         (when (boundp 'tibetan-current-source-file)
                           tibetan-current-source-file))))
    (when source-file
      (let ((dir (file-name-directory source-file))
            (found nil)
            (levels 0))
        (while (and dir (not found) (< levels 5))
          (let ((candidate (expand-file-name "Resources/" dir)))
            (if (file-directory-p candidate)
                (setq found candidate)
              (let ((parent (file-name-directory (directory-file-name dir))))
                (if (or (not parent) (string= parent dir))
                    (setq dir nil)           ; reached filesystem root
                  (setq dir parent)))))
          (setq levels (1+ levels)))
        found))))

(defun tibetan-analysis--extract-pdf-text (pdf-path)
  "Extract text from a PDF file.
First checks for a cached .txt version (same name, .txt extension).
If no cache exists, tries pdftotext, then python3 + pymupdf.
Caches the result for future use.
Returns the full text as a string, or nil if extraction fails."
  (let* ((txt-cache (concat (file-name-sans-extension pdf-path) ".txt"))
         ;; Try cached text file first
         (cached-text (when (file-exists-p txt-cache)
                        (condition-case nil
                            (with-temp-buffer
                              (insert-file-contents txt-cache)
                              (let ((text (string-trim (buffer-string))))
                                (unless (string-empty-p text)
                                  text)))
                          (error nil)))))
    (or cached-text
        ;; No cache — try extraction methods
        (let ((text
               (or
                ;; Method 1: pdftotext (poppler-utils, commonly available on macOS)
                (condition-case nil
                    (when (executable-find "pdftotext")
                      (with-temp-buffer
                        (when (= 0 (call-process "pdftotext" nil t nil
                                                  "-layout" pdf-path "-"))
                          (let ((result (string-trim (buffer-string))))
                            (unless (string-empty-p result) result)))))
                  (error nil))
                ;; Method 2: python3 + pymupdf.  Pass the PDF path as
                ;; sys.argv[1] rather than interpolating it into the
                ;; script literal — a path containing a quote, backslash
                ;; or newline would otherwise break out of the Python
                ;; string (the old `replace-regexp-in-string "'" …' only
                ;; escaped single quotes).
                (condition-case nil
                    (let ((script "
import sys
try:
    import fitz
    doc = fitz.open(sys.argv[1])
    text = []
    for page in doc:
        text.append(page.get_text())
    doc.close()
    print('\\n'.join(text))
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
"))
                      (with-temp-buffer
                        (when (= 0 (call-process "python3" nil t nil
                                                 "-c" script pdf-path))
                          (let ((result (string-trim (buffer-string))))
                            (unless (string-empty-p result) result)))))
                  (error nil)))))
          ;; Cache result for next time
          (when text
            (condition-case nil
                (with-temp-file txt-cache
                  (insert text))
              (error nil)))
          text))))

(defun tibetan-analysis--extract-segment-block (text seg-num)
  "Return only the block for SEG-NUM from multi-segment TEXT.
Recognizes org/markdown headings like `## Segment 4`, `** Segment 4`,
`# Segment 4`.  Matches up to the next heading at the same level, or
end of text.  Returns nil if no matching segment heading is found."
  (when (and text seg-num)
    (let ((case-fold-search t)
          (pattern (format "^\\(#+\\|\\*+\\)[ \t]+Segment[ \t]+%d\\b"
                           seg-num)))
      (when (string-match pattern text)
        (let* ((block-start (match-end 0))
               ;; Find next heading of any kind to bound the block
               (tail (substring text block-start))
               (next-heading
                (when (string-match "\n\\(#+\\|\\*+\\)[ \t]+Segment[ \t]+[0-9]+\\b"
                                    tail)
                  (match-beginning 0)))
               (block (if next-heading
                          (substring tail 0 next-heading)
                        tail)))
          (string-trim block))))))

(defun tibetan-analysis--filename-segment-number (basename)
  "Return the segment number encoded in BASENAME, or nil.
Recognises markers like Segment-04, segment_4, seg-4."
  (when (string-match
         "\\b\\(segment\\|seg\\)[-_ ]\\([0-9]+\\)"
         (downcase basename))
    (string-to-number (match-string 2 basename))))

(defun tibetan-analysis--find-reference-translations (_tibetan-text &optional seg-num source-text)
  "Search for reference translations for the current segment.

Two sources are consulted:
  (a) Inline 〔trans:N〕 … 〔/trans〕 blocks in SOURCE-TEXT (the raw
      class file), when it and SEG-NUM are provided.  These are the
      translations the user typed directly into the source file
      alongside each segment, and they take precedence because they
      represent the most current teaching/working translation for
      the passage.
  (b) External files in the Resources folder (.txt/.org/.md) and
      OCR'd PDFs whose filename hints at translation content.

If SEG-NUM is non-nil, Resources files are segment-scoped:
- Filenames containing `Segment-NN` / `seg-NN` are only included when NN
  matches SEG-NUM.
- Multi-segment files (like `Class-Translations.txt`) with `## Segment N`
  headings inside are narrowed to the matching block.
Files with neither filename marker nor internal segment heading are
included whole (e.g. the Blue Annals OCR).

Returns list of (source-name . translation-text) pairs."
  (let ((resources-dir (tibetan-analysis--find-resources-dir))
        (translations '()))
    ;; (a) Inline 〔trans:N〕 block from the source file.  Added first
    ;; so it ends up at the top of the list after `nreverse' below.
    (when (and source-text seg-num
               (fboundp 'tibetan-doc-format-get-translation))
      (condition-case nil
          (let ((inline (tibetan-doc-format-get-translation
                         source-text seg-num)))
            (when (and inline (not (string-empty-p inline)))
              (push (cons "Class Translation (inline)" inline)
                    translations)))
        (error nil)))
    (when resources-dir
      ;; Check for any text-based translation files
      (let ((files (directory-files resources-dir t "\\.\\(txt\\|org\\|md\\)$")))
        (dolist (file files)
          (let* ((basename (file-name-nondirectory file))
                 (file-seg (tibetan-analysis--filename-segment-number basename)))
            ;; Skip the wordlist (vocabulary, not translation)
            (unless (string-match-p "wordlist\\|wortliste\\|vocab" basename)
              (when (or (string-match-p "translat\\|übersetz\\|blue.?annals\\|class"
                                        (downcase basename))
                        file-seg)
                ;; Segment-scoped filenames: skip if wrong segment
                (unless (and seg-num file-seg (/= file-seg seg-num))
                  (condition-case nil
                      (with-temp-buffer
                        (insert-file-contents file nil 0 8000)
                        (let* ((full (string-trim (buffer-string)))
                               ;; If multi-segment file, narrow to current
                               ;; segment block; otherwise use the whole text.
                               (block (or (and seg-num
                                               (tibetan-analysis--extract-segment-block
                                                full seg-num))
                                          full))
                               (label (file-name-sans-extension basename))
                               (label (if (and seg-num
                                               (not file-seg)
                                               (tibetan-analysis--extract-segment-block
                                                full seg-num))
                                          (format "%s — Segment %d" label seg-num)
                                        label)))
                          (when (and block (not (string-empty-p block)))
                            (push (cons label block) translations))))
                    (error nil))))))))
      ;; Check for OCR'd PDFs (contain extractable text)
      (let ((pdfs (directory-files resources-dir t "\\.pdf$")))
        (dolist (pdf pdfs)
          (let ((basename (downcase (file-name-nondirectory pdf))))
            (cond
             ;; OCR'd Blue Annals extract
             ((string-match-p "ocr" basename)
              (let ((text (tibetan-analysis--extract-pdf-text pdf)))
                (when text
                  ;; Clean up OCR artifacts: normalize whitespace, strip headers
                  (let ((cleaned (replace-regexp-in-string
                                  "THE BLUE ANNALS\\s*\n" ""
                                  (replace-regexp-in-string
                                   "\\([0-9]+\\)\n" ""
                                   text))))
                    (push (cons (cond
                                 ((string-match-p "blue.?annals" basename)
                                  "Blue Annals (Roerich 1949)")
                                 (t (file-name-sans-extension
                                     (file-name-nondirectory pdf))))
                                (string-trim cleaned))
                          translations)))))
             ;; Large scanned PDFs without OCR — just note them
             ((and (> (file-attribute-size (file-attributes pdf)) 10000000)
                   (not (string-match-p "ocr" basename))
                   (string-match-p "blue\\|annals\\|deb.ther" basename))
              (push (cons "Blue Annals (Roerich 1949)"
                          "[Scanned PDF available — use BlueAnnals-Milarepa-OCR.pdf for extracted text]")
                    translations))
             ;; Other reference works could be detected here
             )))))
    (nreverse translations)))


;; Claude pipeline (prompt, request, parsing, migration, insertion,
;; vocabulary merge, Claude-specific readers / restorers) lives in
;; the sibling module.  Required here so the renderer and batch
;; code below can call it.
(require 'tibetan-analysis-claude)

(defun tibetan-analysis--ensure-vocabulary ()
  "Ensure vocabulary is loaded before analysis.

Short-circuits on the canonical `tibetan-glossaries-loaded' flag so a
batch reanalysis never re-emits the `Loading glossaries...' message
or replays the underlying I/O.  The hash-table-count fallback is
kept for sessions where the flag is not bound (older loaders).

§5.22 follow-up (2026-05-21):  also primes the per-document
Resources vocabulary (auto-detected from `Resources/' next to
the source buffer) and Custom vocabulary (pointed to by
`#+TIBETAN_VOCAB_FILE:').  Without these explicit loads, the
Interlinear Gloss's multisource ranker found
`tibetan-current-resources-vocab' / `tibetan-current-custom-vocab'
nil and silently fell through to rank 3 (Steinert) — surfacing
generic dictionary glosses where the user expected their curated
Resources entries.  Both loaders cache per-file, so repeated
calls are cheap.  Wrapped in `ignore-errors' because the loaders
read `(buffer-file-name)' and may signal in edge cases (e.g.
indirect or temp buffers)."
  (cond
   ;; Fast path: the loader already ran and recorded its success.
   ((and (boundp 'tibetan-glossaries-loaded) tibetan-glossaries-loaded)
    nil)
   ;; Hash already populated by some other path — trust it.
   ((and (boundp 'tibetan-comprehensive-vocabulary)
         tibetan-comprehensive-vocabulary
         (> (hash-table-count tibetan-comprehensive-vocabulary) 0))
    nil)
   (t
    (when (fboundp 'load-all-glossaries)
      (load-all-glossaries))
    (unless (and (boundp 'tibetan-comprehensive-vocabulary)
                 tibetan-comprehensive-vocabulary)
      ;; Try loading from file
      (let ((glossary-file "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el"))
        (when (file-exists-p (expand-file-name glossary-file))
          (load-file (expand-file-name glossary-file)))))))
  ;; Always (after the general-glossary short-circuit) prime the
  ;; per-document Resources + Custom vocab so the Interlinear ranker
  ;; sees them at rank 1/2.  Idempotent and cached internally.
  (when (fboundp 'tibetan-load-resources-vocab)
    (ignore-errors (tibetan-load-resources-vocab)))
  (when (fboundp 'tibetan-load-custom-vocab)
    (ignore-errors (tibetan-load-custom-vocab))))

(defun tibetan-analysis--get-particle-annotation (word)
  "Get compact particle annotation for WORD.
Returns string like \\='(ERG)\\=' or \\='(LOC: if/when)\\=' or nil."
  (cond
   ;; Ergative
   ((member word '("ས" "གིས" "ཀྱིས" "གྱིས" "ཡིས"))
    "(ERG: by)")
   ;; Genitive
   ((member word '("འི" "གི" "ཀྱི" "གྱི" "ཡི"))
    "(GEN: of)")
   ;; Locative/Conditional
   ((string= word "ན")
    "(LOC: in/if/when)")
   ;; Dative
   ((string= word "ལ")
    "(DAT: to/at)")
   ;; Allative
   ((member word '("ར" "སུ" "ཏུ" "དུ"))
    "(ALL: toward)")
   ;; Ablative
   ((string= word "ནས")
    "(ABL: from/after)")
   ((string= word "ལས")
    "(ABL: from/than)")
   ;; Comitative
   ((string= word "དང")
    "(COM: and/with)")
   ;; Converbs
   ((member word '("སྟེ" "ཏེ" "དེ"))
    "(CONV: and then)")
   ((member word '("ཅིང" "ཞིང" "ཤིང"))
    "(CONV: while)")
   ;; Nominalizers
   ((member word '("པ" "བ"))
    "(NOM)")
   ((member word '("པོ" "བོ"))
    "(AGT: one who)")
   ;; Imperative
   ((member word '("ཅིག" "ཤིག" "ཞིག"))
    "(IMP)")
   ;; Topic
   ((string= word "ནི")
    "(TOP: as for)")
   (t nil)))

(defun tibetan-analysis--format-word-with-wylie (word)
  "Return WORD in the canonical `SCRIPT [wylie]' display form.

Used by every generated-analysis section that mentions a Tibetan
word except the top-level `* Tibetan Text' section (which is kept
script-only by design).  Centralises the format so all sections
stay in lock-step; do NOT emit `script  wylie' pairs ad-hoc from
call sites.

Behaviour:
- If WORD is nil or empty, returns an empty string.
- If a Wylie conversion via `tibetan-to-wylie-fixed' is available
  and yields a non-empty string distinct from WORD, returns
  \"WORD [wylie]\".
- Otherwise returns WORD unchanged (e.g. WORD already Wylie, or
  converter unavailable, or converter echoes WORD)."
  (cond
   ((or (null word) (not (stringp word)) (string-empty-p word)) "")
   (t
    (let* ((w (string-trim word))
           (wylie (and (fboundp 'tibetan-to-wylie-fixed)
                       (condition-case nil
                           (tibetan-to-wylie-fixed w)
                         (error nil))))
           (wylie (and wylie (stringp wylie) (string-trim wylie))))
      (if (and wylie
               (not (string-empty-p wylie))
               (not (string= wylie w)))
          (format "%s [%s]" w wylie)
        w)))))

(defun tibetan-analysis--bialek-type (word)
  "Return the Bialek classification type string for WORD, or nil.

Single source of truth for particle / converb terminology in this
module.  Delegates to `tibetan-analyze-grammar-bialek' so the
Word/Particle List and the Grammatical Markers section stay in
lock-step.

Because bialek splits its input on tsheg (`་'), a tsheg-joined
compound like `བྱས་པས' gets split into (`བྱས' `པས') and neither
half alone carries enough context for the causal-converb detector
to fire.  We therefore try BOTH the original word and the
tsheg-removed form before giving up — so the full compound can
still be classified as a whole.  Returns the `type' field (index
2) of the first matching tuple."
  (when (and word (stringp word) (not (string-empty-p word))
             (fboundp 'tibetan-analyze-grammar-bialek))
    (let* ((try (lambda (s)
                  (car (condition-case nil
                           (tibetan-analyze-grammar-bialek s)
                         (error nil)))))
           (hit (or (funcall try word)
                    (funcall try (replace-regexp-in-string
                                  "་" "" word)))))
      (and hit (nth 2 hit)))))

(defconst tibetan-analysis--role-order
  '(agent subject patient recipient location goal source instrument comitative)
  "Display order for clause arguments — subject → object → obliques.")

(defconst tibetan-analysis--role-labels
  '((agent      . "SUBJECT (ERG)")
    (subject    . "SUBJECT (ABS)")
    (patient    . "DIRECT OBJECT (ABS)")
    (recipient  . "INDIRECT OBJECT (DAT)")
    (location   . "LOCATIVE (LOC)")
    (goal       . "GOAL (TERM)")
    (source     . "SOURCE (ABL)")
    (instrument . "INSTRUMENT (INST)")
    (comitative . "COMITATIVE (COM)"))
  "Map Round-2 semantic roles to class-facing SUBJECT/OBJECT labels.")

(defun tibetan-analysis--role-label (role)
  "Return the class-facing label for semantic ROLE (a symbol)."
  (or (cdr (assq role tibetan-analysis--role-labels))
      (and role (upcase (symbol-name role)))))

(defun tibetan-analysis--render-clause-structure (words verbs multiword-units)
  "Return a string rendering of Round-2 clause structure for insertion
into the `** Clause Structure' section, or an empty string when no
analysis is available.

Uses `tibetan-analyze-round2' (clauses + NPs + argument structure).
Compact per-clause layout:

  Clause N [main|dependent · PARTICLE]: verb LEMMA [wylie] — meaning
    NPs: HEAD1 [wylie] (CASE), HEAD2 [wylie] (CASE), …
    Roles: role1 → HEAD1, role2 → HEAD2, …   (only when resolvable)

Every Tibetan token is routed through
`tibetan-analysis--format-word-with-wylie' so the output stays in
lock-step with the rest of the generated file."
  (if (not (and words verbs
                (fboundp 'tibetan-analyze-round2)))
      ""
    ;; Uddāna-verse fix (2026-04-30): drop `vocab-fallback' minimal
    ;; entries before clause segmentation.  These low-confidence
    ;; hits — produced when Hill-DB has nothing and the dictionary
    ;; gloss happens to start with `to X' — are how `སྡོམ' /
    ;; `རྣམས' / similar non-verbs slipped in as clause heads while
    ;; the user-visible Verb Classification block (which already
    ;; filters minimal entries) correctly reported `[No Hill-DB
    ;; verbs detected]'.  Curated closed-set minimal entries
    ;; (`གསོལ', `མཛད', `བྱུང', …) are KEPT — they legitimately
    ;; drive clauses.
    (let* ((reliable-verbs
            (cl-remove-if (lambda (v)
                            (eq (alist-get 'source v) 'vocab-fallback))
                          verbs))
           (r2 (condition-case nil
                   (tibetan-analyze-round2
                    words reliable-verbs multiword-units)
                 (error nil)))
           (clauses (alist-get 'clauses r2))
           (nps     (alist-get 'nps r2))
           (args    (alist-get 'argument-structure r2)))
      (if (not clauses)
          "[No clause structure detected]\n"
        (with-temp-buffer
          (let ((clause-idx 0))
            (dolist (clause clauses)
              (cl-incf clause-idx)
              (let* ((ctype (alist-get 'type clause))
                     (cv-type (alist-get 'converb-type clause))
                     (cv-part (alist-get 'converb-particle clause))
                     (verb    (alist-get 'verb clause))
                     (lemma   (and verb (alist-get 'lemma verb)))
                     (meaning (and verb (alist-get 'meaning verb)))
                     (c-start (alist-get 'start clause))
                     (c-end   (alist-get 'end clause))
                     (clause-nps
                      (cl-remove-if-not
                       (lambda (np)
                         (let ((s (alist-get 'start np))
                               (e (alist-get 'end np)))
                           (and s e c-start c-end
                                (>= s c-start) (<= e c-end))))
                       nps))
                     (clause-args (cl-find-if
                                   (lambda (a)
                                     (eq (alist-get 'clause a) clause))
                                   args)))
                (insert (format "Clause %d [%s" clause-idx
                                (if (eq ctype 'main) "main" "dependent")))
                (when (and (not (eq ctype 'main))
                           (or cv-type cv-part))
                  (insert " · ")
                  (when cv-part
                    (insert (tibetan-analysis--format-word-with-wylie
                             cv-part)))
                  (when (and cv-type
                             (not (and cv-part
                                       (string-match-p
                                        (regexp-quote (format "%s" cv-type))
                                        ""))))
                    (insert (format " (%s)" cv-type))))
                (insert "]")
                (when lemma
                  (insert (format ": verb %s"
                                  (tibetan-analysis--format-word-with-wylie
                                   lemma)))
                  (when (and meaning (not (string-empty-p meaning)))
                    (insert (format " — %s"
                                    (car (split-string meaning "," t))))))
                (insert "\n")
                ;; Argument structure — one labelled line per role, in
                ;; SUBJECT → OBJECT → oblique order, each showing the
                ;; full noun phrase (its glued head).  Any NP with no
                ;; resolved role is still listed so the structure is
                ;; complete.
                (let* ((arg-list (and clause-args
                                      (alist-get 'arguments clause-args)))
                       (covered (mapcar (lambda (a) (alist-get 'np a))
                                        arg-list)))
                  (dolist (role-sym tibetan-analysis--role-order)
                    (dolist (a arg-list)
                      (when (eq (alist-get 'role a) role-sym)
                        (insert
                         (format "    %s: %s\n"
                                 (tibetan-analysis--role-label role-sym)
                                 (tibetan-analysis--format-word-with-wylie
                                  (alist-get 'head (alist-get 'np a))))))))
                  (dolist (np clause-nps)
                    (unless (memq np covered)
                      (insert
                       (format "    NP: %s (%s)\n"
                               (tibetan-analysis--format-word-with-wylie
                                (alist-get 'head np))
                               (or (alist-get 'case np) "—")))))))))
          (buffer-string))))))

(defun tibetan-analysis--get-grammatical-role (word root-form verb-table)
  "Determine grammatical role description for WORD with ROOT-FORM.

Uses VERB-TABLE for verb detection.  For particle / converb
classification, delegates to `tibetan-analyze-grammar-bialek' via
`tibetan-analysis--bialek-type' so the terminology matches the
Grammatical Markers section exactly (e.g. \\='GENITIVE (GEN)\\=',
\\='CONVERBIAL: CAUSAL CONVERB\\=').

Return value is a string such as \\='Transitive verb, CONVERBIAL:
CAUSAL CONVERB\\=', \\='GENITIVE (GEN)\\=', or \\='Noun\\=' — or
nil when nothing informative is available."
  ;; Strip Tibetan punctuation (shad, etc.) before comparison
  (let* ((word (replace-regexp-in-string "[།༎༏༐༑༔/]" "" word))
         (root-form (when root-form (replace-regexp-in-string "[།༎༏༐༑༔/]" "" root-form)))
         ;; Double-strip: for forms like sleb pa'i, strip-particles gives
         ;; `sleb pa` — we also need `sleb` so the verb DB lookup hits.
         (root-form-2 (when (and root-form (fboundp 'tibetan-strip-particles))
                        (let ((r2 (tibetan-strip-particles root-form)))
                          (and (not (string= r2 root-form))
                               (not (string-empty-p r2))
                               r2))))
         ;; Third strip: `tibetan-strip-particles' does not descend
         ;; through the bare nominaliser `པ'/`བ'.  Without this, a
         ;; verb-nominalised form like `སླེབ་པའི' resolves to
         ;; `སླེབ་པ' and the Hill-DB lookup never sees `སླེབ'.  Strip
         ;; a trailing `་པ'/`་བ'/`་པོ'/`་བོ' so the final verb lemma
         ;; surfaces for transitivity classification.
         (root-form-3 (let ((r (or root-form-2 root-form)))
                        (and r
                             (string-match-p "་\\(པོ\\|བོ\\|པ\\|བ\\)\\'" r)
                             (replace-regexp-in-string
                              "་\\(པོ\\|བོ\\|པ\\|བ\\)\\'" "" r))))
         (verb-info
          (or (and verb-table (gethash word verb-table))
              (and verb-table (gethash root-form verb-table))
              (and verb-table root-form-2 (gethash root-form-2 verb-table))
              (and verb-table root-form-3 (gethash root-form-3 verb-table))
              ;; Fallback: Hill 2010 verb database directly, so
              ;; forms like pham/'thon/sleb get tagged as verbs
              ;; even when the text-level verb extractor missed
              ;; them.  Use an alist shape compatible with the
              ;; (alist-get 'transitivity ...) accessor below.
              (and (fboundp 'tibetan-verb-lookup)
                   (or (tibetan-verb-lookup word)
                       (and root-form (tibetan-verb-lookup root-form))
                       (and root-form-2 (tibetan-verb-lookup root-form-2))
                       (and root-form-3 (tibetan-verb-lookup root-form-3))))))
         (bialek-type (tibetan-analysis--bialek-type word)))
    (cond
     ;; Recognised verb — combine transitivity with any bialek
     ;; classification carried by the word's particle tail.
     (verb-info
      (let* ((trans-raw (or (alist-get 'transitivity verb-info) ""))
             (trans (if (stringp trans-raw) trans-raw ""))
             ;; "Intransitive" contains "Transitive" as a substring —
             ;; check for "Intransitive" FIRST so pham/'thon/sleb etc.
             ;; aren't mislabelled as transitive.
             (verb-kind (cond
                         ((string-match-p "[Ii]ntransitive" trans) "Verb")
                         ((string-match-p "[Tt]ransitive" trans)
                          "Transitive verb")
                         (t "Verb"))))
        (if bialek-type
            (concat verb-kind ", " bialek-type)
          verb-kind)))
     ;; Non-verb: bialek classified it → use that label directly.
     (bialek-type bialek-type)
     ;; Last resort: treat as a noun.
     (t "Noun"))))

(defun tibetan-analysis--detect-verb-suffix (word _root-form)
  "Return a Bialek-terminology suffix label for WORD, or nil.

Thin adapter over `tibetan-analysis--bialek-type' so the suffix
label attached to a verb in the Sentence Structure / Word list
stays in lock-step with the Grammatical Markers section.  The
returned string, when non-nil, is prefixed with \", \" so callers
can concatenate it directly after a verb-kind label, e.g.
\\='Transitive verb, CONVERBIAL: CAUSAL CONVERB\\='.  Returns nil
when bialek has no classification for the word's particle tail
(e.g. a bare nominaliser on a verb stem, or an unusual suffix
bialek does not cover)."
  (let ((type (tibetan-analysis--bialek-type word)))
    (and type (concat ", " type))))

(defun tibetan-analysis--verb-morphology-gloss (root-form)
  "If ROOT-FORM (Tibetan script, particles stripped) is a verb in the
Hill 2010 database, return a morphology-aware English gloss.

Returned format, depending on whether ROOT-FORM is the lemma or an
inflected stem:

  Lemma form:        \"to do, to make\"
  Past stem:         \"pf. of byed — to do, to make\"
  Future stem:       \"ft. of byed — to do, to make\"
  Imperative stem:   \"imp. of byed — to do, to make\"
  Present stem:      (same as lemma when equal)

Returns nil if ROOT-FORM is not a verb. Used by the Word/Particle List
to make byas/byas pas/bstugs type entries show their underlying lemma
and canonical meaning, rather than falling back to dictionary glosses
like \"verb: do\" that hide the morphology."
  (when (and root-form
             (stringp root-form)
             (not (string-empty-p root-form))
             (fboundp 'tibetan-verb-lookup))
    (let* ((nom-stripped
            (replace-regexp-in-string "་?[པབ]$" "" root-form))
           ;; Which form did we actually find a verb for?
           (lookup-form
            (cond
             ((tibetan-verb-lookup root-form) root-form)
             ((and (not (string= nom-stripped root-form))
                   (not (string-empty-p nom-stripped))
                   (tibetan-verb-lookup nom-stripped))
              nom-stripped)
             (t nil)))
           (entry (and lookup-form (tibetan-verb-lookup lookup-form)))
           (lemma (and entry (cdr (assoc 'lemma entry))))
           (meaning (and entry (cdr (assoc 'meaning entry)))))
      (when (and lemma meaning)
        (let* ((past (cdr (assoc 'past_stem entry)))
               (future (cdr (assoc 'future_stem entry)))
               (imp (cdr (assoc 'imperative_stem entry)))
               (pres (cdr (assoc 'present_stem entry)))
               (lemma-wylie (when (fboundp 'tibetan-to-wylie-fixed)
                              (condition-case nil
                                  (string-trim (tibetan-to-wylie-fixed lemma))
                                (error nil))))
               ;; Which inflection is LOOKUP-FORM?
               (stem-label
                (cond
                 ((string= lookup-form lemma) nil)           ; lemma itself
                 ((and pres (string= lookup-form pres)) nil) ; present = lemma
                 ((and past (string= lookup-form past)) "pf.")
                 ((and future (string= lookup-form future)) "ft.")
                 ((and imp (string= lookup-form imp)) "imp.")
                 (t nil))))
          (if stem-label
              ;; Two-line format so the Word/Particle List renderer
              ;; puts the stem reference on line 1 after " — " and
              ;; the lemma gloss on an indented line 2, matching
              ;; Resources-style entries (e.g. "Pf. von X;\nmeaning").
              (format "%s of %s;\n%s"
                      stem-label
                      (or lemma-wylie lemma)
                      (string-trim meaning))
            (string-trim meaning)))))))

(defun tibetan-analysis--wylie-like-token-p (tok)
  "Return non-nil if TOK looks like a bare Wylie syllable rather than
a natural English/German word.  Used to strip compound-reference
tails that leak out of user wordlists, e.g. \"dice kha phung la thong\"
→ only \"dice\" is the real gloss."
  (and (stringp tok)
       (not (string-empty-p tok))
       (let ((lc (downcase tok)))
         (or
          ;; Wylie tokens often start with an apostrophe (e.g. 'dzugs, 'thon).
          (string-prefix-p "'" tok)
          ;; Closed set of short Wylie particles / very common syllables
          ;; that are unlikely to appear as content words in an English or
          ;; German gloss.
          (member lc
                  '("pa" "ba" "ma" "la" "na" "ra" "su" "du" "tu" "ru"
                    "nas" "las" "kyi" "kyis" "gyi" "gyis" "gi" "gis"
                    "yi" "ni" "te" "ste" "de" "so" "to" "no" "po" "bo"
                    "par" "bar" "cig" "zhig" "shig" "cing" "zhing" "shing"
                    "kyang" "yang" "dang" "dpe" "zhes" "ces" "ste"
                    "kha" "phung" "thong" "thub" "gyur" "sleb" "byed"
                    "pham" "rgyal" "dzugs" "dgon" "kho" "khos" "khyed"
                    "nga" "nyid" "gang" "khri" "mkha" "rig" "rigs"
                    "ko" "ron" "sa" "yul" "las" "rgyud" "brgyud"))
          ;; Wylie-distinctive digraphs at start or as whole token.
          (string-match-p "\\`\\(bzh\\|rdz\\|brts\\|bcu\\|bsk\\|bgy\\|mkh\\|'kh\\|sgr\\|rgy\\|brt\\)" lc)))))

(defun tibetan-analysis--strip-wylie-tail (gloss)
  "Remove trailing Wylie-only example tokens from GLOSS.
Some user wordlists embed compound cross-references directly after
the actual gloss (e.g. \"dice kha phung la thong\" where only
\"dice\" is the English meaning).  Walks tokens from the end, strips
consecutive Wylie-like tokens, and returns the trimmed gloss — but
only if at least one plain content token remains."
  (if (not (and gloss (stringp gloss) (not (string-empty-p gloss))))
      gloss
    (let* ((tokens (split-string (string-trim gloss) "[ \t]+" t))
           (n (length tokens))
           (i (1- n))
           (tail-count 0))
      (while (and (>= i 0)
                  (tibetan-analysis--wylie-like-token-p (nth i tokens)))
        (setq tail-count (1+ tail-count))
        (setq i (1- i)))
      (if (and (>= tail-count 2)
               (> (- n tail-count) 0))
          (string-join (cl-subseq tokens 0 (- n tail-count)) " ")
        gloss))))


(defun tibetan-analysis--render-particle-skeleton (tibetan-text _particles verbs)
  "Generate a visual particle map for TIBETAN-TEXT.
PARTICLES is the parsed particles list, VERBS is the verb list.
Returns an org-formatted string with particles highlighted:
- =PARTICLE= for case markers (genitive, dative, etc.)
- ~CONVERB~ for converb particles
- *PARTICLE* for sentence-final particles
- [Ø ROLE] for zero-marked arguments

The particle keeps its natural lowercase Wylie spelling inside the
markup (`='i='`, not `='I='`) since the magenta / orange face
remap in `tibetan-analysis-setup-faces' already makes it stand
out visually.  Earlier versions upcased for plain-text / PDF
fallback visibility; the face remap + customizable colours cover
those cases, and lowercase reads cleaner for apostrophe-prefixed
particles like `'i' / `'o'."
  (let* ((wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed tibetan-text))
                  (error tibetan-text)))
         ;; Define particle patterns to mark.
         ;;
         ;; `nas' lives ONLY in converb-particles (primary use is
         ;; V+nas — the bare ablative-case `N+nas' reading is rare
         ;; enough that the Particle Map is content to paint all
         ;; `nas' occurrences as converbs in orange; the per-
         ;; particle section below gives the precise grammatical
         ;; role anyway.  Without this, both the converb pass AND
         ;; the case pass would match `nas' in succession,
         ;; producing the `~=nas=~' soup students saw 2026-04-22.
         ;; `las' stays in case-particles — it's almost always the
         ;; ablative case marker, rarely a converb.
         (case-particles '("'i" "gi" "kyi" "gyi" "yi"      ; genitive
                          "s" "gis" "kyis" "gyis" "yis"    ; ergative
                          "la" "r" "du" "tu" "su" "ru"     ; dative/terminative
                          "las"                             ; ablative
                          "dang"                            ; comitative
                          "ni"))                            ; topic marker
         (converb-particles '("cing" "zhing" "shing"       ; simultaneous
                             "ste" "te" "de"               ; sequential
                             "nas"))                        ; after-converb / ablative
         (final-particles '("ro" "so" "to" "no" "do" "'o" "ngo"))
         (result wylie)
         ;; Force case-sensitive matching for the particle passes.
         ;; Without this, the lowercase regex `\bnas\b' (case-
         ;; particle pass) also matches the already-uppercased `NAS'
         ;; produced by the converb pass (or vice versa) and wraps
         ;; the result into nonsense `=~NAS~=' soup.  Case-folding
         ;; defaults to t in batch; explicitly binding nil here
         ;; keeps the passes independent.
         (case-fold-search nil))

    ;; Mark converb particles first (`~PARTICLE~').  Converbs are
    ;; more functionally salient for V+nas / V+ste chains; doing
    ;; them first means a bare `nas' is never mis-wrapped as a
    ;; case particle before the converb pass sees it.
    (dolist (p converb-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\b" (regexp-quote p))
                    (format "~%s~" p)
                    result)))

    ;; Mark case particles with `=PARTICLE='.
    (dolist (p case-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\b" (regexp-quote p))
                    (format "=%s=" p)
                    result)))

    ;; Mark sentence-final particles with *PARTICLE*
    (dolist (p final-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\(/\\|$\\)" (regexp-quote p))
                    (format "*%s*\\1" p)
                    result)))

    ;; Embed zero-markers (Ø) inline before transitive verbs that expect
    ;; an unmarked agent.  Replaces earlier behaviour of appending
    ;; `[Ø AGENT expected before V]' lines below the Wylie — having
    ;; the Ø sit at the verb's position keeps the particle markup +
    ;; argument-structure on one visual line, which reads better
    ;; alongside the Particle Map's case-particle highlighting.
    ;;
    ;; "Intransitive" contains "Transitive" as substring — check
    ;; Intransitive first so we don't add Ø for intransitive verbs
    ;; like pham/'thon/sleb.
    (let ((case-fold-search nil))
      (dolist (verb verbs)
        (when (and verb (listp verb) (consp (car verb)))
          (let* ((lemma (alist-get 'lemma verb))
                 (trans (alist-get 'transitivity verb))
                 (frame (alist-get 'case_frame verb)))
            (when (and lemma
                       (not (string-match-p "[Ii]ntransitive" (or trans "")))
                       (or (string-match-p "[Tt]ransitive" (or trans ""))
                           (string-match-p "Erg" (or frame ""))))
              (let* ((verb-wylie (condition-case nil
                                     (tibetan-to-wylie-fixed lemma)
                                   (error lemma)))
                     ;; Replace the FIRST whole-word occurrence only;
                     ;; if a verb appears twice in the segment we don't
                     ;; want two Ø markers cluttering the line.  The
                     ;; first occurrence is typically the canonical
                     ;; argument site; later occurrences are usually
                     ;; nominalised re-references.
                     (re (format "\\b%s\\b" (regexp-quote verb-wylie))))
                (when (and verb-wylie
                           (not (string-empty-p verb-wylie))
                           (string-match re result))
                  ;; Only stamp Ø when the immediately-preceding token is a
                  ;; BARE content word — a genuinely zero-marked argument.
                  ;; Suppress it when that token is already markup: a
                  ;; case marker (`=…=`, e.g. an overt ergative subject),
                  ;; a converb boundary (`~…~`), or a final particle
                  ;; (`*…*`).  Stamping Ø there wrongly marks an
                  ;; already-cased argument as zero — the §5.21-deferred
                  ;; "spurious Ø on transitive subjects" bug.
                  (let* ((before (substring result 0 (match-beginning 0)))
                         (prev (car (last (split-string
                                           (string-trim-right before)
                                           "[ \t]+" t)))))
                    (when (and prev
                               (not (string-match-p "\\`[=~*]" prev))
                               ;; split-string clobbered the match data.
                               (string-match re result))
                      (setq result
                            (replace-match (concat "Ø " verb-wylie)
                                           t t result)))))))))))

    result))

(defun tibetan-analysis--strip-folio-markers (text)
  "Strip folio markers like (12a2), (16b5) etc. from TEXT.
These are editorial annotations from the Tibetan block print and
should not be processed as Tibetan text.  Also removes extra
whitespace left behind."
  (let ((cleaned (replace-regexp-in-string
                  "([0-9]+[ab][0-9]*)" ""
                  text)))
    ;; Clean up multiple spaces left by removal
    (replace-regexp-in-string "  +" " " (string-trim cleaned))))

(defun tibetan-analysis--filter-to-tibetan-lines (text)
  "Return TEXT with non-Tibetan content lines dropped.

Source files often interleave the Tibetan body with editorial
material that the analyser must NOT treat as input:
  - Parenthetical English descriptions on their own line,
    e.g. `(Homage / author's dedication verses)'.
  - Org-mode comment lines starting with `#'.
  - Blank separator lines.
  - Folio-marker-only lines.

Lines that contain no Tibetan character (anywhere in the U+0F00
block) are dropped entirely; lines that contain ANY Tibetan
character are kept verbatim.  The surviving lines are joined with
a single tsheg (U+0F0B) so that:
  1. `tibetan-parse-enhanced' — which splits on tsheg — tokenises
     the first word of each continuation line cleanly (a raw
     newline does NOT split, producing spurious compound tokens
     like `ལོ༎\\nརྒྱལ').
  2. `tibetan-to-wylie-fixed' emits a space between the two words
     (instead of the bare `lo//rgyal' it produces when the source
     contains only a newline, which looks like a typo to readers
     of the Wylie transliteration).

Without this filter, `tibetan-to-wylie-fixed' renders the
non-Tibetan portion as leading whitespace (producing a ~30-space
indent on sections like Wylie Transliteration) and
`tibetan-extract-vocabulary' tokenises the English words, matching
some of them against Wylie glossary entries (the English word
\"on\", for instance, matches the Wylie hash key and produces a
bogus \"set\" gloss)."
  (if (and text (stringp text))
      (let ((tibetan-char-re "[ༀ-࿿]")
            (kept '()))
        (dolist (line (split-string text "\n"))
          (when (string-match-p tibetan-char-re line)
            (push (string-trim line) kept)))
        (mapconcat #'identity (nreverse kept) "་"))
    text))

(defun tibetan-analysis--format-bilingual-gloss (gloss)
  "Reformat a German//English GLOSS for easy reading.
If GLOSS has the shape
  \"{DE-stem-ref}; {DE-meaning} // {EN-stem-ref}; {EN-meaning}\"
where both sides start with a matching verb-stem reference
(\"Pf. von ...\" + \"pf. of ...\", etc.), returns a two-line string
  \"{DE-stem-ref};\\n{DE-meaning} // {EN-meaning}\"
with the redundant English stem reference removed.
Plain \"German // English\" entries without a stem reference are
returned unchanged, since they're already compact.
Falls back to the original string when the pattern doesn't fit.

The stem-reference detection is deliberately conservative so we do
not mangle entries that happen to contain a period or semicolon for
unrelated reasons."
  (if (or (null gloss) (not (stringp gloss)) (not (string-match-p "//" gloss)))
      gloss
    (let* ((parts (split-string gloss "//"))
           (de (string-trim (nth 0 parts)))
           (en (string-trim (mapconcat #'identity (cdr parts) "//")))
           (stem-re "^\\(\\(?:[Pp]f\\|[Pp]res\\|[Ff]t\\|[Ff]ut\\|[Ii]mp\\)\\.[ \t]+\\(?:of\\|von\\|zu\\)[ \t]+[^;]+?\\)[ \t]*;[ \t]*\\(.*\\)$")
           (de-ref nil) (de-rest nil) (en-rest en))
      (when (and de (string-match stem-re de))
        (setq de-ref (string-trim (match-string 1 de)))
        (setq de-rest (string-trim (match-string 2 de))))
      (when (and de-ref en (string-match stem-re en))
        (setq en-rest (string-trim (match-string 2 en))))
      (cond
       ;; Resources-style stem-reference entry: split stem ref onto
       ;; its own line, drop redundant English stem ref.
       ((and de-ref de-rest (not (string-empty-p de-rest))
             en-rest (not (string-empty-p en-rest)))
        (format "%s;\n%s // %s" de-ref de-rest en-rest))
       (t gloss)))))

(defun tibetan-analysis--detailed-dict-is-particle-p (tibetan)
  "Return non-nil when TIBETAN is a pure case / converb particle.
Matches a single-syllable token (no tsheg / word break) whose text
appears in `tibetan-extract-vocab--particle-tails' — the same list
used by the MWU loop and vocabulary extractor.  Particle entries in
the Detailed Dictionary get a compact one-line rendering pointing
at the Particle Overview section instead of a verbose multi-source
dump."
  (and (stringp tibetan)
       (boundp 'tibetan-extract-vocab--particle-tails)
       (not (string-match-p "་" tibetan))
       (member (string-trim tibetan)
               tibetan-extract-vocab--particle-tails)))

(defun tibetan-analysis--render-detailed-dictionary
    (tibetan-text vocab-pairs &optional bialek-analysis)
  "Render the `** Detailed Dictionary' section for TIBETAN-TEXT.
Inserts into the current buffer.  TIBETAN-TEXT is the raw input
string; VOCAB-PAIRS is the segmentation's (word . gloss) alist used
as a legacy fallback when the multi-source helper is unavailable.
BIALEK-ANALYSIS, if non-nil, is the output of
`tibetan-analyze-grammar-bialek'; its grammatical tags let the
renderer split stem+particle compounds the same way the Interlinear
Gloss does, so a click on `[[term-mthu][mthu]]' in the Interlinear
lands on the `<<term-mthu>>' anchor emitted here (not a separate
`<<term-mthu-i>>' for the inflected form).  When the analysis is
omitted the renderer falls back to `tibetan-strip-particles' for a
narrower (unambiguous-particles-only) strip.

The section body is produced by `tibetan-vocab-extract-detailed'
when present, enriched via `tibetan-vocab-multisource-entries' for
the per-source breakdown (Resources / Steinert / Rangjung Yeshe /
DharmaMitra).  Entries backed by a curated Resources list get a
`★' marker on the head line.  Sanskrit is only emitted when the
source entry itself carries it.  The bilingual gloss formatter
keeps German // English pairs side by side."
  (insert "** Detailed Dictionary\n")
  (let ((vocab-list (condition-case nil
                        (when (fboundp 'tibetan-vocab-extract-detailed)
                          (tibetan-vocab-extract-detailed tibetan-text))
                      (error nil)))
        ;; Index bialek grammar tags so we can reuse the Interlinear's
        ;; stem/particle splitter.  (WORD → TAG-STRING), same shape the
        ;; Interlinear builds in `tibetan-interlinear-generate-gloss'.
        (bialek-by-word (make-hash-table :test 'equal))
        ;; Dedupe: track anchors already rendered this section so two
        ;; vocab entries that normalise to the same stem (e.g. a
        ;; segment containing both `mthu' and `mthu'i') only produce
        ;; one Detailed Dictionary block.
        (seen-anchors (make-hash-table :test 'equal)))
    (dolist (a bialek-analysis)
      (let ((word (nth 1 a))
            (type (nth 2 a)))
        (when (and word type)
          (puthash word type bialek-by-word))))
    (if vocab-list
        (progn
          (dolist (entry vocab-list)
            (let* ((raw-tibetan (plist-get entry :tibetan))
                   ;; Stem/particle split.  Two paths:
                   ;;   1. Prefer the Interlinear's splitter when we
                   ;;      have a bialek tag for this word — identical
                   ;;      semantics to the Interlinear anchor, so
                   ;;      `term-xxx' links round-trip correctly.
                   ;;   2. Fall back to `tibetan-strip-particles' when
                   ;;      no tag exists — conservative multi-char
                   ;;      particle strip keeps pre-existing behaviour.
                   (bialek-tag (gethash raw-tibetan bialek-by-word))
                   (stem-tibetan
                    (cond
                     ((and bialek-tag
                           (fboundp 'tibetan-interlinear--split-word-particle))
                      (car (tibetan-interlinear--split-word-particle
                            raw-tibetan bialek-tag)))
                     ((fboundp 'tibetan-strip-particles)
                      (let ((s (tibetan-strip-particles raw-tibetan)))
                        (if (and s (not (string-empty-p s))) s raw-tibetan)))
                     (t raw-tibetan)))
                   ;; Canonical tsheg-trim for the tibetan display — the
                   ;; stripper occasionally leaves a trailing `་'.
                   (tibetan
                    (replace-regexp-in-string "[་ \t]+$" ""
                                              (or stem-tibetan raw-tibetan)))
                   ;; Wylie for the stem.  Recompute from the stripped
                   ;; Tibetan rather than reusing the entry's `:wylie'
                   ;; (which was built from the particle-bearing form).
                   (wylie
                    (condition-case nil
                        (when (and tibetan (fboundp 'tibetan-to-wylie-fixed))
                          (downcase (string-trim
                                     (tibetan-to-wylie-fixed tibetan))))
                      (error (plist-get entry :wylie))))
                   ;; Multi-source lookup: already ranked (Thesaurus →
                   ;; Resources/Custom → corpus-specific → Hopkins2015
                   ;; → 84000Dict → RangjungYeshe → others → Bundled/
                   ;; DharmaMitra) and capped so the head of the list
                   ;; is the best-quality entry.  Sanskrit is emitted
                   ;; only when the source entry carries it natively
                   ;; AND it passes the real-Sanskrit filter.
                   (sources
                    (condition-case nil
                        (when (fboundp 'tibetan-vocab-multisource-entries)
                          (tibetan-vocab-multisource-entries tibetan))
                      (error nil)))
                   ;; `★' marker fires when a CURATED source is
                   ;; available — either a per-document Resources /
                   ;; Custom list OR a Thesaurus zettel.  Both indicate
                   ;; the gloss is under user control rather than auto-
                   ;; extracted from a generic dictionary, so they
                   ;; share the visual emphasis.
                   (has-curated
                    (cl-some (lambda (s)
                               (let ((src (plist-get s :source)))
                                 (and src
                                      (or (string-prefix-p "Resources" src)
                                          (string-prefix-p "Custom" src)
                                          (string-prefix-p "Thesaurus" src)))))
                             sources))
                   ;; Thesaurus zettel id, if a Thesaurus entry is in
                   ;; the source list.  Drives the `[[id:XYZ]
                   ;; [Thesaurus ↗]]' back-link on the head line.
                   (thesaurus-zettel-id
                    (cl-some (lambda (s)
                               (and (stringp (plist-get s :source))
                                    (string-prefix-p "Thesaurus"
                                                     (plist-get s :source))
                                    (plist-get s :zettel-id)))
                             sources))
                   ;; Genuine Sanskrit (if any source carries it) —
                   ;; displayed on the head line for instant visibility.
                   (sanskrit-on-head
                    (and (fboundp 'tibetan-vocab-find-sanskrit)
                         (tibetan-vocab-find-sanskrit sources)))
                   ;; Internal link target (matches the Interlinear
                   ;; Gloss's `[[term-xxx][wylie]]' link above).
                   (anchor
                    (and wylie (fboundp 'tibetan-vocab-term-anchor)
                         (tibetan-vocab-term-anchor wylie)))
                   ;; External Steinert URL — moved here from the
                   ;; Interlinear Gloss so the two-tier navigation is
                   ;; clear: Interlinear → Detailed Dictionary (shallow,
                   ;; same file); Detailed Dictionary → Steinert web
                   ;; (deep, external).
                   (steinert-url
                    (and wylie (fboundp 'tibetan-steinert-url-org)
                         (condition-case nil
                             (tibetan-steinert-url-org wylie)
                           (error nil)))))
              ;; Skip duplicates: a segment that contains `mthu' and
              ;; `mthu'i' both normalise to `term-mthu', render once.
              (unless (and anchor (gethash anchor seen-anchors))
                (when anchor (puthash anchor t seen-anchors))
              ;; Anchor target — invisible radio anchor that the
              ;; Interlinear link jumps to.  Kept on its own line so
              ;; it doesn't interfere with the visible head line.
              (when anchor
                (insert (format "<<%s>>\n" anchor)))
              ;; Dictionary-style head line:
              ;;   ◆ Tibetan [wylie] · Sanskrit ★ (Steinert ↗)
              (insert (format "◆ %s"
                              (if (and wylie (stringp wylie)
                                       (not (string-empty-p wylie))
                                       (not (string= wylie tibetan)))
                                  (format "%s [%s]" tibetan wylie)
                                (tibetan-analysis--format-word-with-wylie
                                 tibetan))))
              (when sanskrit-on-head
                (insert (format " · %s" sanskrit-on-head)))
              (when has-curated (insert " ★"))
              ;; Thesaurus zettel back-link — `[[id:XYZ][Thesaurus ↗]]'
              ;; clickable from the analysis buffer to the user's
              ;; thesaurus entry (org-id resolver opens the zettel).
              ;; Positioned before the Steinert link so the curated
              ;; source is reached first when scanning left-to-right.
              (when thesaurus-zettel-id
                (insert (format " ([[id:%s][Thesaurus ↗]])"
                                thesaurus-zettel-id)))
              ;; External Steinert link as a small ↗ marker.  Clickable
              ;; org link syntax, kept short so the head line stays
              ;; scannable.
              (when steinert-url
                (if (string-match "\\[\\[\\([^]]+\\)\\]\\[" steinert-url)
                    (insert (format " ([[%s][Steinert ↗]])"
                                    (match-string 1 steinert-url)))))
              (if (tibetan-analysis--detailed-dict-is-particle-p tibetan)
                  ;; Particle: short compact entry, skip the multi-source dump.
                  ;; See `** Particle Overview' earlier in the file for
                  ;; the grammatical function.
                  (insert " — particle (see ** Grammar above)\n")
                (insert "\n")
                (if sources
                  (dolist (src sources)
                    (let* ((source-name (plist-get src :source))
                           (gloss (or (plist-get src :detailed)
                                      (plist-get src :primary)
                                      "[no gloss]"))
                           (skt (plist-get src :sanskrit))
                           (formatted
                            (tibetan-analysis--format-bilingual-gloss
                             gloss))
                           (lines (split-string formatted "\n")))
                      (insert (format "  [%s]\n" source-name))
                      (dolist (ln lines)
                        (insert (format "    %s\n" ln)))
                      ;; Sanskrit only when the entry itself supplied it.
                      (when (and skt
                                 (not (string-empty-p (string-trim skt))))
                        (insert (format "    Skt: %s\n" skt)))))
                ;; Fallback: legacy single-entry path if the
                ;; multi-source helper is unavailable.
                (let* ((detailed (plist-get entry :detailed))
                       (primary (plist-get entry :primary))
                       (sanskrit (plist-get entry :sanskrit))
                       (source (plist-get entry :source))
                       (meaning (or detailed primary "[not found]"))
                       (formatted
                        (tibetan-analysis--format-bilingual-gloss
                         meaning))
                       (lines (split-string formatted "\n")))
                  (dolist (ln lines)
                    (insert (format "  %s\n" ln)))
                  (when sanskrit
                    (insert (format "  Skt: %s\n" sanskrit)))
                  (when source
                    (insert (format "  [%s]\n" source))))))
              (insert "\n"))))
          (insert "\n"))
      ;; Fallback: use vocab-pairs if detailed system not available.
      (if vocab-pairs
          (progn
            (dolist (pair vocab-pairs)
              (let* ((word (car pair))
                     (meaning (cdr pair))
                     (root-form (tibetan-strip-particles word))
                     (head (if (and root-form
                                    (not (string-empty-p root-form))
                                    (not (string= root-form word)))
                               root-form
                             word)))
                (insert (format "◆ %s\n"
                                (tibetan-analysis--format-word-with-wylie
                                 head)))
                (insert (format "  %s\n\n" (or meaning "[not found]")))))
            (insert "\n"))
        (insert "[No dictionary entries available]\n\n")))))

(defun tibetan-analysis--particle-wylie-equivalent-p (a b)
  "Return non-nil if particle Wylie strings A and B denote the same
particle modulo the inherent-vowel representation.

Tibetan consonants carry an implicit `a' in their syllable form:
`ར' can be Wylie'd as either `r' (consonant alone, as Claude emits
when asked for the `particle' part of a compound like `der') or
`ra' (consonant + inherent vowel, as `tibetan-to-wylie-fixed'
produces when given the bare Tibetan syllable).  Without a
normaliser, the Grammar renderer's match `equal' loop considers
the two strings distinct and silently drops the Portfolio snippet
for every `ར' occurrence.

Normalisation: lowercase, trim, strip a trailing `a' when the
preceding char is a consonant (so `ra' → `r', `sa' → `s', `da' →
`d'; `la' stays `la' because `l' alone is ambiguous with the
ablative converb `la' vs the suffix `l' case — and Claude emits
`la' for the dative, matching bialek).  Compare the normalised
forms for equality."
  (when (and a b (stringp a) (stringp b))
    (let ((na (tibetan-analysis--particle-wylie-normalise a))
          (nb (tibetan-analysis--particle-wylie-normalise b)))
      (equal na nb))))

(defun tibetan-analysis--particle-wylie-normalise (s)
  "Normalise particle Wylie S for equivalence matching.
Lowercase, trim, and strip trailing `a' when preceded by a single
consonant so `ra' and `r' both map to `r'.  Multi-char particles
like `la', `ni', `dang' are preserved verbatim."
  (let ((x (downcase (string-trim s))))
    (cond
     ;; Single-consonant + a → single consonant.  Specifically the
     ;; mono-consonantal case particles whose inherent-a form shows
     ;; up in `tibetan-to-wylie-fixed' output but NOT in Claude's
     ;; per-particle field.
     ((member x '("ra" "sa" "da" "ga")) (substring x 0 1))
     (t x))))

(defun tibetan-analysis--buddhist-term-entry-p (entry)
  "Return non-nil when ENTRY is an 84000 `<term>'-tagged Buddhist term.
ENTRY is a plist from `tibetan-vocab-multisource-entries'.  The
check matches on (a) `:source' containing `84000' (either 43-84000Dict
or 44-84000Definitions — both carry the canonical-term marker) AND
(b) `:primary' or `:detailed' starting with the literal `<term>' tag
that Steinert's 84000 tables emit for canonical Buddhist terminology.

`<person>' and `<place>' tags are intentionally NOT treated as
Buddhist terms here — those surface via B1's rename-override path
(commit e82e817), and the user-facing `*** Buddhist Terms' section
is reserved for terms the reader would look up in an encyclopaedia
of Buddhism (Four Immeasurables, Bodhicitta, Skandha, etc.)."
  (let ((source (plist-get entry :source))
        (primary (or (plist-get entry :primary) ""))
        (detailed (or (plist-get entry :detailed) "")))
    (and (stringp source)
         (string-match-p "84000" source)
         (or (string-prefix-p "<term>" (string-trim primary))
             (string-prefix-p "<term>" (string-trim detailed))))))

(defun tibetan-analysis--collect-buddhist-terms (enriched-vocab-pairs)
  "Return a list of (SCRIPT WYLIE DEFINITION) for Buddhist terms in
ENRICHED-VOCAB-PAIRS.  ENRICHED-VOCAB-PAIRS is the
((TIBETAN-CLEAN . SHORT-MEANING) ...) alist threaded out of the
generate-content vocab loop.

For each unique token, the helper calls
`tibetan-vocab-multisource-entries' and inspects each entry for
Steinert 84000 `<term>'-tagged content (see
`--buddhist-term-entry-p').  When found, the longest available
body (`:detailed' preferred over `:primary') is taken as the
definition — 84000Definitions routinely carries a paragraph-length
explanation of the term's meaning, provenance, and related
concepts, which is exactly what a student needs on first encounter.

Deduplicated by Tibetan script so a term appearing twice in the
segment surfaces only once.  Returns nil when no Buddhist terms
are present — the caller omits the subsection entirely in that
case."
  (let ((seen (make-hash-table :test 'equal))
        (results '()))
    (when (fboundp 'tibetan-vocab-multisource-entries)
      (dolist (pair enriched-vocab-pairs)
        (let* ((script (car pair))
               (entries (and script
                             (condition-case nil
                                 (tibetan-vocab-multisource-entries script)
                               (error nil)))))
          (when (and entries (not (gethash script seen)))
            (let* ((buddhist-entries
                    (cl-remove-if-not
                     #'tibetan-analysis--buddhist-term-entry-p
                     entries))
                   ;; Prefer 84000Definitions (rank 44) over 84000Dict
                   ;; (rank 43) when both are present — the Definitions
                   ;; entry carries the long explanation.
                   (best
                    (or (cl-find-if
                         (lambda (e)
                           (string-match-p
                            "84000Definitions" (plist-get e :source)))
                         buddhist-entries)
                        (car buddhist-entries))))
              (when best
                (puthash script t seen)
                (let* ((wylie (plist-get best :wylie))
                       (body (or (plist-get best :detailed)
                                 (plist-get best :primary))))
                  (when (and body (stringp body))
                    (push (list script wylie body) results)))))))))
    (nreverse results)))

(defun tibetan-analysis--format-buddhist-term-body (body &optional max-len)
  "Trim BODY (the 84000Definitions `:detailed' text) for display.
Strips the leading `<term>' tag if present, converts literal `\\n'
escape sequences to real newlines, flattens multi-paragraph bodies
to a single line with `/ ' separators, and truncates to MAX-LEN
characters (default 400) with an ellipsis.  The aim: a one-line
definition compact enough to sit under a `- SCRIPT [wylie]' entry
in the `*** Buddhist Terms' subsection."
  (let ((max-len (or max-len 400))
        (s (or body "")))
    ;; Strip leading `<term> ' / `<term>:' markers.
    (setq s (replace-regexp-in-string "\\`\\s-*<term>\\s-*:?\\s-*" "" s))
    ;; Convert literal `\n' sequences (as they appear in 84000 rows)
    ;; to real newlines, then flatten to single line.
    (setq s (replace-regexp-in-string "\\\\n" " " s))
    (setq s (replace-regexp-in-string "[ \t]*\n[ \t]*" " / " s))
    (setq s (replace-regexp-in-string "[ \t]+" " " s))
    (setq s (string-trim s))
    (if (> (length s) max-len)
        (concat (substring s 0 (- max-len 1)) "…")
      s)))

(defun tibetan-analysis--render-buddhist-terms-section (terms)
  "Insert `*** Buddhist Terms' section into the current buffer for
TERMS.  TERMS is the list of `(SCRIPT WYLIE 84000-BODY)' triples
returned by `tibetan-analysis--collect-buddhist-terms'.

Phase 5 of zettel-in-translation-workflow (2026-04-26): for each
term, consults `tibetan-zettel--read-claude-explanation' first.
When a fresh cache exists (zettel exists AND `:prompt-version:'
matches the live system prompt's hash), the zettel's body is
rendered with a `[via zettel cache]' suffix.  When no cache or
stale, falls back to the truncated 84000Definitions body — same
behaviour as pre-Phase-5 U3.

The cache reader returns nil when the prompt-version is stale,
so the writer (Phase 5 extension to commit 2394c50's writer) can
overwrite on the next Claude response without manual
invalidation."
  (when terms
    (insert "*** Buddhist Terms\n")
    (dolist (entry terms)
      (let* ((script (nth 0 entry))
             (wylie (nth 1 entry))
             (84000-body (nth 2 entry))
             (zettel-entry
              (and wylie (fboundp 'tibetan-zettel-lookup)
                   (ignore-errors (tibetan-zettel-lookup wylie))))
             (cached-body
              (and zettel-entry
                   (fboundp 'tibetan-zettel--read-claude-explanation)
                   (ignore-errors
                     (tibetan-zettel--read-claude-explanation
                      zettel-entry))))
             (head (tibetan-analysis--format-word-with-wylie script))
             (body (or cached-body 84000-body))
             (clean (tibetan-analysis--format-buddhist-term-body
                     body 400))
             (suffix (if cached-body
                         "  [via zettel cache]"
                       "")))
        (insert (format "- %s\n" head))
        (insert (format "  %s%s\n" clean suffix))))
    (insert "\n")))

(defun tibetan-analysis--render-grammar-section (tibetan-text particles verbs
                                                              bialek-analysis
                                                              &optional
                                                              claude-particles
                                                              enriched-vocab-pairs)
  "Render the merged `** Grammar' section body to the current buffer.

Pass 6b replaces three redundant sections (`** Particle Map',
`** Particle Overview', `** Grammatical Markers') with a single
`** Grammar' containing:

  *** Particle Map — the Wylie transliteration with particle markers
      (=CASE= for case particles, ~CONVERB~ for converbs, Ø for
      zero-marked arguments) — a quick visual scan of the grammar.

  *** Claude Grammar (U4, 2026-04-24) — Claude's prose reading of
      the passage's syntactic structure.  Placeholder emitted here;
      body filled in by `--ensure-claude-headings' +
      `--restore-claude-sections' after Claude responds.

  *** Buddhist Terms (U3, 2026-04-24) — 84000Definitions paragraph
      for any fixed Buddhist term (Four Immeasurables, Bodhicitta,
      Skandha, ...) detected in the passage via the multi-source
      dictionary stack.  Omitted when no `<term>'-tagged entries
      are present.

  *** Particles in This Segment — one line per Bialek particle
      detection: type, top-level Portfolio reference, translation
      hint.  Pass 6c augments this with per-occurrence function
      sub-IDs tagged by Claude + the matching Portfolio snippet,
      making the section self-contained for readers without access
      to the user's Portfolio source file.

TIBETAN-TEXT feeds the Particle Map's annotated Wylie.  PARTICLES
and VERBS come from the Bialek / verb-extraction pipeline.
BIALEK-ANALYSIS is the result of `tibetan-analyze-grammar-bialek'
— drives the compact particles list.

CLAUDE-PARTICLES, when non-nil, is a list of plists (parsed via
`tibetan-analysis--parse-claude-particles') carrying
`(:word W :particle P :sub-id ID :label L)' for each per-occurrence
function Claude identified.  When passed, each Bialek line gains a
specific sub-function heading and the matching Portfolio snippet
text.  When nil, falls back to the compact parser-only list.

ENRICHED-VOCAB-PAIRS, when non-nil, is the
((TIBETAN-CLEAN . SHORT-MEANING) ...) alist built upstream by the
vocab-pairs loop — threaded in so the `*** Buddhist Terms'
subsection can look up per-token 84000Definitions bodies.  When
nil, the subsection is omitted."
  (insert "** Grammar\n")
  (insert "Visual particle map + per-particle reference (Bialek 2022\n")
  (insert "+ Portfolio).  Claude's prose reading follows.\n\n")
  ;; ------------------------------------------------------------------
  ;; Sub-section 1 (§5.21 Commit 3/7, 2026-05-20):  merged `***
  ;; Particles' section.  Was previously two siblings — `***
  ;; Particle Map' (visual `=CASE=' / `~CONVERB~' / `Ø' skeleton)
  ;; + `*** Particles in This Segment' (per-particle bullets with
  ;; Portfolio refs).  Merged so the reader gets both views in one
  ;; place:  one-line scan at the top, detailed bullets below.
  ;; ------------------------------------------------------------------
  (insert "*** Particles\n")
  (insert "=CASE= (magenta) · ~CONVERB~ (orange) · Ø zero-marked\n\n")
  (let ((annotated-wylie (tibetan-analysis--render-particle-skeleton
                          tibetan-text particles verbs)))
    (insert annotated-wylie)
    (insert "\n\n"))
  (tibetan-analysis--render-particle-bullets bialek-analysis claude-particles)
  (insert "\n")
  ;; ------------------------------------------------------------------
  ;; Sub-section 2: Claude Grammar — prose reading (U4, 2026-04-24).
  ;; Placeholder heading at org level 3 so the Claude write-path can
  ;; target it.  Sits AFTER the merged Particles section (visual +
  ;; bullets), giving the reader flow:
  ;;   particle markup → per-particle refs → prose interpretation.
  ;; The body is filled by `tibetan-analysis--ensure-claude-headings'
  ;; + `tibetan-analysis--restore-claude-sections' after the Claude
  ;; response arrives.  When no Claude data yet, the heading sits
  ;; empty — fine, it's a placeholder.
  ;;
  ;; Legacy files carry `** Claude Grammar' at level 2 (pre-U4
  ;; layout).  The Claude writer's migration step demotes + moves
  ;; the body into this slot on next regeneration.
  ;; ------------------------------------------------------------------
  (insert "*** Claude Grammar\n")
  (insert "\n\n")
  ;; ------------------------------------------------------------------
  ;; Sub-section 3 (optional): Buddhist Terms (U3, 2026-04-24;
  ;; Phase 5 of zettel-in-translation-workflow on 2026-04-26 adds
  ;; the zettel-cache read path).
  ;; ------------------------------------------------------------------
  (let ((terms (and enriched-vocab-pairs
                    (fboundp 'tibetan-analysis--collect-buddhist-terms)
                    (tibetan-analysis--collect-buddhist-terms
                     enriched-vocab-pairs))))
    (when terms
      (tibetan-analysis--render-buddhist-terms-section terms))))

(defun tibetan-analysis--render-particle-bullets (bialek-analysis claude-particles)
  "Render per-particle bullets for `*** Particles' (§5.21 Commit 3/7).
Was the body of the standalone `*** Particles in This Segment'
section pre-§5.21.  Now part of the merged `*** Particles' that
also carries the visual skeleton at the top.

For each Bialek-detected particle in BIALEK-ANALYSIS:
  1. Header line:  particle (with context word when clitic) ·
     type · `[Bialek 2022 §X.Y; Portfolio §A.B]' reference
     bracket.  Bialek 2022 ref added Commit 4/7;  this commit
     emits only the Portfolio ref via the existing `portfolio'
     field on the bialek tuple.
  2. Try to match against CLAUDE-PARTICLES on particle wylie for
     a per-occurrence sub-ID + short label.  On hit, look up the
     Portfolio snippet via
     `tibetan-interlinear-portfolio-function-snippet'.
  3. On miss, fall back to the parser's generic translation
     hint."
  (if bialek-analysis
      (dolist (a bialek-analysis)
        (let* ((particle (nth 0 a))
               (word (nth 1 a))
               (type (nth 2 a))
               (trans-guide (nth 4 a))
               (function-desc (nth 3 a))
               (portfolio (nth 6 a))
               ;; word-wylie retained for potential future word-level
               ;; matching (e.g. if the Claude tuple's :word field
               ;; starts sharing a prefix with bialek's dedup'd
               ;; word); current match runs on particle-wylie alone.
               (_word-wylie (condition-case nil
                                (downcase
                                 (string-trim
                                  (tibetan-to-wylie-fixed word)))
                              (error nil)))
               (particle-wylie (condition-case nil
                                   (downcase
                                    (string-trim
                                     (tibetan-to-wylie-fixed particle)))
                                 (error nil)))
               (portfolio-key
                (and (fboundp 'tibetan-interlinear--portfolio-key)
                     (tibetan-interlinear--portfolio-key type)))
               ;; Find ALL matching Claude tuples for this particle.
               ;; Matching rules (loose to accommodate real data):
               ;;   · Particle Wylie must be equivalent — with the
               ;;     inherent-vowel-stripping normaliser so `r' and
               ;;     `ra' both match for terminative.
               ;;   · Word Wylie is NOT required to match, because
               ;;     the Bialek analyser dedups per-particle (two
               ;;     `nas' occurrences → one entry with word = nas)
               ;;     while Claude emits one tuple per occurrence
               ;;     (word = bslabs nas, word = tshim nas).  Showing
               ;;     BOTH tuples under the single bialek entry is
               ;;     the right behaviour — each carries the
               ;;     context-specific sub-function.
               ;; Dedup by sub-id so identical functions collapse.
               (matching-tuples
                (and claude-particles particle-wylie
                     (let ((seen (make-hash-table :test 'equal))
                           (out '()))
                       (dolist (p claude-particles)
                         (let ((pw (plist-get p :particle))
                               (id (plist-get p :sub-id)))
                           (when (and pw id
                                      (not (gethash id seen))
                                      (tibetan-analysis--particle-wylie-equivalent-p
                                       pw particle-wylie))
                             (puthash id t seen)
                             (push p out))))
                       (nreverse out)))))
          ;; Header line.  Two shapes:
          ;;   · standalone (word == particle):
          ;;       PARTICLE · TYPE [Bialek 2022 §X.Y (Title); Portfolio §A.B]
          ;;   · clitic (word contains particle):
          ;;       WORD · PARTICLE · TYPE [Bialek 2022 §X.Y; Portfolio §A.B]
          ;; The « » wrapping and the double word-in-word pattern of
          ;; Pass 6b read as noise when the word IS just the particle
          ;; (`ནས [nas] in «ནས [nas]»').  Compact format drops that.
          ;;
          ;; §5.21 Commit 4/7 (2026-05-20):  bullet bracket now carries
          ;; BOTH the Bialek 2022 published-textbook reference
          ;; (canonical numbering, looked up via
          ;; `tibetan-bialek-textbook-ref' against the particle-type
          ;; string) AND the existing Portfolio §A.B field from the
          ;; bialek tuple.  Either side may be absent:
          ;;   · Both present  → `[Bialek 2022 §X.Y …; Portfolio §A.B]'
          ;;   · Bialek-only   → `[Bialek 2022 §X.Y …]'
          ;;   · Portfolio-only→ `[Portfolio §A.B]'
          ;;   · Both nil      → bracket omitted entirely
          ;; The Portfolio side is RETAINED because it can carry an
          ;; in-house function breakdown that Bialek's published
          ;; chapter numbering doesn't expose.
          (let ((standalone-p (equal word particle))
                (bialek-ref
                 (and (fboundp 'tibetan-bialek-textbook-ref)
                      (tibetan-bialek-textbook-ref type))))
            (insert (format "- %s"
                            (tibetan-analysis--format-word-with-wylie
                             (if standalone-p particle word))))
            (unless standalone-p
              (insert (format " · %s"
                              (tibetan-analysis--format-word-with-wylie
                               particle))))
            (insert (format " · %s" type))
            (cond
             ((and bialek-ref portfolio)
              (insert (format "  [%s; %s]" bialek-ref portfolio)))
             (bialek-ref
              (insert (format "  [%s]" bialek-ref)))
             (portfolio
              (insert (format "  [%s]" portfolio))))
            (insert "\n"))
          ;; Claude-assigned sub-functions + Portfolio snippets.  A
          ;; single bialek entry may match several Claude tuples when
          ;; the same particle has multiple functions in the segment
          ;; (e.g. `nas' used sequentially AND causally on two
          ;; different verbs).  Emit one `§...' block per tuple;
          ;; fall back to the parser's generic hint when no tuple
          ;; matched.
          (if matching-tuples
              (dolist (tuple matching-tuples)
                (let* ((sub-id (plist-get tuple :sub-id))
                       (label (plist-get tuple :label))
                       (context-word (plist-get tuple :word))
                       (snippet (and portfolio-key sub-id
                                     (fboundp 'tibetan-interlinear-portfolio-function-snippet)
                                     (tibetan-interlinear-portfolio-function-snippet
                                      portfolio-key sub-id))))
                  (cond
                   ;; Full hit: sub-ID + Portfolio snippet (self-contained).
                   (snippet
                    (insert (format "  § %s %s — %s"
                                    sub-id (car snippet)
                                    (or label "")))
                    ;; When two+ tuples matched (e.g. two `nas'
                    ;; occurrences), annotate with the surface form
                    ;; so the reader can tell which function applies
                    ;; to which occurrence.
                    (when (and context-word
                               (> (length matching-tuples) 1))
                      (insert (format " (in %s)" context-word)))
                    (insert "\n")
                    ;; Indent EVERY line of the snippet body (not just
                    ;; the first) so example bullets inside the
                    ;; Portfolio description stay nested under the
                    ;; particle entry.  Without per-line indent, a
                    ;; line starting `- foo' after an embedded newline
                    ;; would render at column 0 and look like a new
                    ;; top-level particle entry.  Regression guarded by
                    ;; `-portfolio-snippet-multiline-indented' test.
                    (let* ((raw (tibetan-interlinear--truncate-para
                                 (cdr snippet) 400))
                           (indented (replace-regexp-in-string
                                      "\n" "\n    " raw)))
                      (insert (format "    %s\n" indented))))
                   ;; Partial hit: sub-ID from Claude but no Portfolio
                   ;; snippet (Claude picked a broader ID than the
                   ;; parsed Portfolio covers, or Portfolio cache is
                   ;; unavailable).
                   (sub-id
                    (insert (format "  § %s — %s"
                                    sub-id (or label "")))
                    (when (and context-word
                               (> (length matching-tuples) 1))
                      (insert (format " (in %s)" context-word)))
                    (insert "\n")))))
            ;; No Claude tuple matched — fall back to the bialek
            ;; analyser's generic translation hint.
            (let ((hint (or trans-guide function-desc)))
              (when (and hint (not (string-empty-p hint)))
                (insert (format "  → %s\n" hint)))))))
    (insert "[No grammatical markers detected]\n"))
  (insert "\n"))

(defconst tibetan-analysis--priority-section-order
  '("** Wylie Transliteration"
    "** Phonetics"
    "** Interlinear Gloss"
    "** Claude Vocabulary"
    "** Claude Translation"
    "** Translation"
    "** DharmaMitra Translation"
    ;; Reading-optimized order (2026-06-02):  Sentence Structure is
    ;; elevated ABOVE Grammar — once the student has the translation,
    ;; the sentence skeleton (subjects / objects / verbs) is the next
    ;; thing they reach for, before drilling into per-particle grammar.
    "** Sentence Structure"
    "** Grammar"
    "** Verb Classification (Hill 2010)"
    ;; §5.21 Commit 5/7 (2026-05-20):  Detailed Dictionary is the LAST
    ;; entry — reference material consulted on confusion, not flow
    ;; reading.  Class-use feedback (2026-06-02):  Concept Notes
    ;; (Buddhist / Sanskrit encyclopedia glossary) is ALSO reference,
    ;; not flow — moved DOWN from after the AI translations to just
    ;; above Detailed Dictionary, so the top-to-bottom reading flow is
    ;; Wylie → Phonetics → Interlinear → Translations → Sentence
    ;; Structure → Grammar → Verb Class. → Provided Translations, then
    ;; the two reference blocks (Concept Notes, Detailed Dictionary).
    "** Provided Translations"
    "** Concept Notes"
    "** Detailed Dictionary")
  "Section headings (at org level-2) that should appear first in the
`* Auto-Analysis' output, in this exact order.  Any level-2 section
NOT listed here is kept and emitted afterwards in the order it was
generated.

Phase 3 of two-language-parallel-analysis (2026-04-30):  the
`** Sanskrit Source' entry (Phase-2 sanskrit-parallel-workflow)
is retired here — Sanskrit raw text now lives at the top-level
`* Sanskrit Text' section (outside `* Auto-Analysis'), so it
no longer needs ordering INSIDE.  The reorder pass only
positions sections that exist, so dropping it from the list
is safe for any existing files that still carry the old
heading;  those sections simply fall to the end of
Auto-Analysis until a reanalyse drops them.

Phase 1 of two-language-parallel-analysis (2026-04-30):  the
`** Claude Translation (Sanskrit)' / `(Combined)' /
`** Claude Divergence' entries (added Phase B–D earlier today)
are retired.  Sanskrit-side and Combined-synthesis Claude
output now lives under separate top-level sections (`*
Sanskrit Analysis' / `* Combined Analysis').  Inside `*
Auto-Analysis' the priority order returns to its
pre-Phase-B shape.

Pass 6b (2026-04-22) redesign: the four redundant particle sections
— Particle Map, Particle Overview, Grammatical Markers, and the
segment-specific content of Claude Grammar — collapsed into a single
`** Grammar' section with three sub-headings (Particle Map, Particles
in This Segment, [future] Portfolio snippets).  Sentence Structure
and Clause Structure likewise merge into one `** Sentence Structure'
carrying per-clause verb + NP + role info.

U4 (2026-04-24): `** Claude Grammar' moved from a level-2 sibling
section to a level-3 sub-heading `*** Claude Grammar' under
`** Grammar', placed between `*** Particle Map' and
`*** Particles in This Segment'.  Reader flow inside Grammar:
map (visual) → Claude's prose reading → per-particle Portfolio
references.  The Claude writer, reader, migration, and scaffolding
all consult `tibetan-analysis--claude-section-order' (in
`tibetan-analysis-claude.el') for the canonical level — that is
where U4's change lands for the Claude side.

Reader flow: Wylie → Interlinear Gloss (word-for-word) → Claude
Translation (fluent) → Grammar (map + prose + particle refs) →
Sentence Structure (clause + arguments) → Verb Classification →
Detailed Dictionary (deep reference).")

(defun tibetan-analysis--split-level2-sections (content)
  "Split CONTENT into an ordered list of level-2 section cons cells.
Each element is (HEADING . BODY), where HEADING is the full heading
line (e.g. `** Wylie Transliteration') and BODY is everything up to
the next `^\\*\\* ' heading or end of string.  Text that appears
before the first level-2 heading is returned under the special key
`t' (typically empty) so the caller can preserve it."
  (let ((result '())
        (preamble nil)
        (idx 0))
    (while (< idx (length content))
      (if (string-match "^\\*\\* .*$" content idx)
          (let* ((h-start (match-beginning 0))
                 (h-end (match-end 0))
                 (heading (match-string 0 content))
                 (next-start (or (and (string-match
                                       "^\\*\\* .*$" content (1+ h-end))
                                      (match-beginning 0))
                                 (length content)))
                 (body (substring content (1+ h-end) next-start)))
            (unless preamble
              (let ((pre (substring content 0 h-start)))
                (setq preamble pre)))
            (push (cons heading body) result)
            (setq idx next-start))
        ;; No more headings — everything that remains is trailing text.
        ;; If we never saw a heading, the whole thing is preamble.
        (unless preamble
          (setq preamble (substring content idx)))
        (setq idx (length content))))
    (cons (or preamble "") (nreverse result))))

(defun tibetan-analysis--extract-claude-grammar (sections)
  "If SECTIONS contains a `** Provided Translations' whose body holds a
`*** Claude Grammar' sub-heading, extract that subsection and return
a new list with:
  - a new `** Claude Grammar' level-2 entry carrying the promoted body
  - the original `** Provided Translations' with that sub-heading
    removed (the rest of its body preserved)
When no `*** Claude Grammar' is present the sections are returned
unchanged."
  (let ((found-body nil)
        (updated '()))
    (dolist (pair sections)
      (if (string= (car pair) "** Provided Translations")
          (let ((body (cdr pair)))
            (if (string-match
                 "^\\*\\*\\* Claude Grammar[ \t]*\n\\([\000-\377]*?\\)\\(\\(?:\n\\*\\*\\* \\)\\|\\'\\)"
                 body)
                (let* ((grammar-body (string-trim (match-string 1 body)))
                       (match-start (match-beginning 0))
                       (tail-start (match-beginning 2))
                       (new-body (concat (substring body 0 match-start)
                                         (substring body tail-start))))
                  (setq found-body grammar-body)
                  (push (cons (car pair) new-body) updated))
              (push pair updated)))
        (push pair updated)))
    (setq updated (nreverse updated))
    (if found-body
        (append updated
                (list (cons "** Claude Grammar"
                            (concat found-body "\n"))))
      updated)))

(defun tibetan-analysis--reorder-auto-content (content)
  "Reorder the level-2 sections of CONTENT into the priority order
defined by `tibetan-analysis--priority-section-order', keeping every
other section in its original relative position.

This also promotes `*** Claude Grammar' out of `** Provided
Translations' so it can slot into the priority list as a first-
class level-2 section."
  (let* ((split (tibetan-analysis--split-level2-sections content))
         (preamble (car split))
         (sections (tibetan-analysis--extract-claude-grammar (cdr split)))
         (priority-pairs '())
         (remaining '()))
    ;; Walk priority list and pull the matching sections out of SECTIONS.
    (dolist (p tibetan-analysis--priority-section-order)
      (let ((hit (cl-find p sections :key #'car :test #'string=)))
        (when hit
          (push hit priority-pairs)
          (setq sections (cl-remove p sections
                                    :key #'car :test #'string=)))))
    (setq priority-pairs (nreverse priority-pairs))
    (setq remaining sections)
    (concat preamble
            (mapconcat
             (lambda (pair)
               (concat (car pair) "\n" (cdr pair)))
             (append priority-pairs remaining)
             ""))))

(defvar tibetan-analysis--claude-particles-for-render nil
  "Dynamic binding: parsed Claude-particles list for the in-flight render.
Set by callers that have just read (or are about to re-insert) the
`*** Claude Particles' body — e.g. `tibetan-analysis-reanalyze-file'
reads the preserved Claude sections BEFORE calling
`tibetan-analysis-generate-content', so it can thread the parsed
particles through this var.  The Grammar renderer consults it to
attach per-occurrence Portfolio snippets; nil → compact parser-only
output, identical to Pass 6b behaviour.")

(defvar tibetan-analysis--sanskrit-text-for-render nil
  "Dynamic binding: Sanskrit-text plist for the in-flight render.

Set by callers that have located the segment's `**** Sanskrit'
sibling (typically via
`tibetan-sanskrit-parallel-text-for-segment-id' from
`core/tibetan-sanskrit-parallel.el').  When non-nil, the value
is the plist returned by that walker:
  (:iast STRING :devanagari STRING-or-nil :script-source SYMBOL).

The renderer `tibetan-analysis--render-sanskrit-source' reads
this var (indirectly, through the caller passing the value) and
emits a `** Sanskrit Source' level-2 section.  When nil — the
default — no Sanskrit section is emitted; today's Tibetan-only
documents are unchanged.

Phase 2 of the sanskrit-parallel-workflow (2026-04-27).")

(defun tibetan-analysis--render-sanskrit-source (sanskrit-plist)
  "Return a top-level `* Sanskrit Text' org section as a string.

SANSKRIT-PLIST is the walker plist
`(:iast STRING :devanagari STRING-or-nil :script-source SYMBOL)'
or nil.  Returns:
  - empty string for nil input or empty `:iast', so callers can
    safely concatenate without guarding.
  - a complete top-level section for a populated plist:

      * Sanskrit Text

      IAST: <iast>
      [Devanagari: <devanagari>]

The trailing blank line ensures the section concatenates cleanly
with the next section in the buffer.

Pure function — no buffer side effects, no metadata reads.  All
Sanskrit-text decisions (whether to emit, which lines to
include) happen here so callers stay simple.

Phase 3 of two-language-parallel-analysis (2026-04-30) promotes
this from the Phase-2 `** Sanskrit Source' (which lived inside
`* Auto-Analysis') to the new top-level `* Sanskrit Text'
section.  Top-level placement makes Sanskrit a peer of the
Tibetan analysis rather than a subsection of it; the same
walker-driven gate (placeholder bodies → nil) applies."
  (let* ((iast (and sanskrit-plist (plist-get sanskrit-plist :iast)))
         (devanagari (and sanskrit-plist
                          (plist-get sanskrit-plist :devanagari))))
    (if (or (null iast) (string-empty-p iast))
        ""
      (concat "* Sanskrit Text\n"
              "\n"
              (format "IAST: %s\n" iast)
              (when (and devanagari (not (string-empty-p devanagari)))
                (format "Devanagari: %s\n" devanagari))
              "\n"))))

(defun tibetan-analysis-generate-content (tibetan-text &optional seg-id source-text source-file)
  "Generate auto-analysis content for TIBETAN-TEXT.
Returns the analysis as a string (org-mode formatted).

SEG-ID, if provided, enables segment-scoped reference translations
(per-segment Blue Annals files, narrowing multi-segment class files).

SOURCE-TEXT, if provided, is the full text of the source class file.
When SEG-ID resolves to a segment number, the 〔trans:SEG-NUM〕 block
inside SOURCE-TEXT is surfaced as an additional reference
translation.  This is how inline class-taught translations reach the
analysis buffer.  Batch callers that do not have the source buffer
handy may omit this argument; only the inline-trans surfacing is
affected, not the rest of the analysis.

SOURCE-FILE, if provided, is the absolute path to the source
document.  Its `#+TIBETAN_CORPUS:' header (if any) is read and
`tibetan-vocab--corpus' is dynamically bound for the duration of
analysis so the dictionary ranker promotes the matching Steinert
sub-dictionary into rank-3.  When omitted, the function falls back
to `buffer-file-name' (useful when called from inside a source-doc
buffer); when that too is nil, corpus-specific ranking simply
doesn't apply and the default ranking is used.

Claude-tagged per-particle functions (Pass 6c) are threaded in via
the dynamic `tibetan-analysis--claude-particles-for-render' — set
it with `let' around the call when Claude data is available.

§5.21 Commit 6/7 (2026-05-20):  SEG-ID and SOURCE-TEXT are kept
in the signature for caller compatibility but are no longer
consumed inside this function.  Their sole previous use was the
`*** Reference Translations' auto-fill nested under `**
Provided Translations';  that auto-fill was retired in the
same commit so PT could become a pristine user-content slot.
The `(ignore …)' form below silences the byte-compiler's
unused-arg warning without breaking the public API."
  (ignore seg-id source-text)
  (let* ((resolved-src (or source-file
                           (and (boundp 'tibetan-current-source-file)
                                tibetan-current-source-file)
                           (buffer-file-name)))
         (meta (and resolved-src
                    (fboundp 'tibetan-analysis--read-source-metadata)
                    (condition-case nil
                        (tibetan-analysis--read-source-metadata resolved-src)
                      (error nil))))
         (corpus-val     (plist-get meta :corpus))
         (target-lang-val (plist-get meta :target-lang))
         (tibetan-vocab--corpus
          (if (and corpus-val (stringp corpus-val)
                   (not (string-empty-p corpus-val)))
              corpus-val
            tibetan-vocab--corpus))
         ;; Pass 5c (2026-04-22): per-document target language for the
         ;; visible translation output.  `de' / `en' are the canonical
         ;; values; nil means unset → callers default to English for
         ;; backward compatibility.  Dynamically bound for the
         ;; duration of analysis so Interlinear / CAT Gloss / Claude
         ;; prompt helpers can prefer the right half of bilingual
         ;; `DE // EN' glosses without threading explicit args.
         (tibetan-analysis--target-lang
          (if (and target-lang-val (stringp target-lang-val)
                   (not (string-empty-p target-lang-val)))
              target-lang-val
            tibetan-analysis--target-lang)))
  (condition-case err
      (progn
        ;; Drop non-Tibetan lines (English descriptions, # comments,
        ;; blank separators).  Required before Wylie conversion and
        ;; parser tokenisation so English words don't collide with
        ;; Wylie glossary keys.
        (setq tibetan-text (tibetan-analysis--filter-to-tibetan-lines
                            tibetan-text))
        ;; Strip folio markers before analysis (e.g. "(12a2)")
        (setq tibetan-text (tibetan-analysis--strip-folio-markers tibetan-text))

        ;; Ensure vocabulary is loaded
        (tibetan-analysis--ensure-vocabulary)

        (let* ((parsed (condition-case nil
                           (when (fboundp 'tibetan-parse-enhanced)
                             (tibetan-parse-enhanced tibetan-text))
                         (error nil)))
               (words (alist-get 'words parsed))
               (analysis (alist-get 'analysis parsed))
               (multiword-units (alist-get 'multiword-units parsed))
               (wylie-full (condition-case nil
                               (when (fboundp 'tibetan-to-wylie-fixed)
                                 (tibetan-to-wylie-fixed tibetan-text))
                             (error "[Wylie conversion error]")))
               (verbs (condition-case nil
                          (when (fboundp 'tibetan-extract-verbs-compound-aware)
                            (tibetan-extract-verbs-compound-aware tibetan-text words multiword-units))
                        (error nil)))
               (_zero-analysis (condition-case nil
                                   (when (and verbs multiword-units (fboundp 'tibetan-analyze-zero-markers))
                                     (tibetan-analyze-zero-markers verbs multiword-units words))
                                 (error nil)))
               ;; Inline DharmaMitra lookup retired 2026-05-19 with the
               ;; removal of the level-3 `*** DharmaMitra' placeholder.
               ;; The real Tibetan DM translation is fetched async by
               ;; `tibetan-dharmamitra-translation-fire-tibetan' and
               ;; written to `** DharmaMitra Translation' under
               ;; `* Tibetan Analysis'.  This binding is retained as
               ;; a no-op probe so the let* shape stays stable for
               ;; downstream destructuring callers.
               (_translation (condition-case nil
                                 (when (fboundp 'tibetan-get-dharmamitra-translation)
                                   (tibetan-get-dharmamitra-translation tibetan-text))
                               (error nil)))
               (_claimed-indices (condition-case nil
                                     (when (fboundp 'tibetan-get-claimed-indices)
                                       (tibetan-get-claimed-indices multiword-units))
                                   (error nil)))
               (particles (when analysis (alist-get 'particles analysis)))
               ;; Build verb lookup table
               (verb-table (make-hash-table :test 'equal))
               ;; Extract vocabulary for DharmaMitra-style display
               (vocab-pairs (condition-case nil
                                (when (fboundp 'tibetan-extract-vocabulary)
                                  (tibetan-extract-vocabulary tibetan-text))
                              (error nil)))
               ;; Populated by the Word/Particle List loop below with
               ;; (word . short-English-gloss) pairs reflecting the same
               ;; Hill-morphology / Resources enrichment that shows up
               ;; in the Word/Particle List.  Also consumed by the
               ;; Buddhist-terms collector (`--collect-buddhist-terms')
               ;; that feeds the Detailed Dictionary head's gloss
               ;; line.  Used to feed the retired `*** CAT Gloss'
               ;; section too (§5.21 retired CAT Gloss; the
               ;; enrichment chain stays for the DD path).
               (enriched-vocab-pairs nil)
               ;; `word-clean' → t for every token whose primary
               ;; dictionary hit was Resources or Custom (the hand-
               ;; curated per-document vocabulary list).  Consumed
               ;; by the Interlinear renderer to prepend ★ to
               ;; authoritative entries, matching the marker the
               ;; legacy Word/Particle List used to show.
               (curated-words-hash (make-hash-table :test 'equal))
               (interlinear-marker nil))

          ;; Build verb lookup for quick access
          (dolist (verb verbs)
            (when (and verb (listp verb) (consp (car verb)))
              (let ((lemma (alist-get 'lemma verb)))
                (when lemma
                  (puthash lemma verb verb-table)))))

          (with-temp-buffer
            ;; Phase 3 of two-language-parallel-analysis (2026-04-30):
            ;; The previous Phase-2 `** Sanskrit Source' (inside
            ;; `* Auto-Analysis') is retired here.  Sanskrit raw text
            ;; now renders as a separate top-level `* Sanskrit Text'
            ;; section, emitted by `tibetan-analysis-create-file' (and
            ;; the reanalyse path) — NOT by this function, which only
            ;; produces `* Auto-Analysis'-internal content.

            ;; ============================================================
            ;; SECTION 1: Wylie Transliteration
            ;; Reading the sequence first.
            ;; ============================================================
            (insert "** Wylie Transliteration\n")
            (insert (or wylie-full "[Not available]"))
            (insert "\n\n")

            ;; ============================================================
            ;; SECTION 1.5: Phonetics (THL Simplified, Lhasa-based)
            ;; Class-reading aid (2026-05-19):  Wylie alone is unforgiving
            ;; when the student is vocalising a line.  THL approximates
            ;; modern Lhasa pronunciation in Wylie-friendly Roman
            ;; orthography (sh / ch / zh / ng).  Soft-required so
            ;; segments still generate when the converter is absent.
            ;; ============================================================
            (insert "** Phonetics\n")
            (let ((phon (and (fboundp 'tibetan-to-phonetics)
                             (ignore-errors
                               (tibetan-to-phonetics tibetan-text)))))
              (insert (or (and phon
                               (stringp phon)
                               (not (string-empty-p (string-trim phon)))
                               phon)
                          "[Phonetics not available]")))
            (insert "\n\n")

            ;; ============================================================
            ;; SECTION 1a: Interlinear Gloss + Particle Overview
            ;; Mark position — content inserted after the Word/Particle List
            ;; loop has built enriched-vocab-pairs and bialek-analysis.
            ;; Marker has default insertion-type nil → text inserted AT the
            ;; marker position stays AFTER the marker (Interlinear lands at
            ;; the saved point, sections below it come AFTER Interlinear).
            ;; ============================================================
            (setq interlinear-marker (copy-marker (point)))

            ;; ============================================================
            ;; SECTION 1a': Claude Vocabulary (promoted to level 2 in §5.21,
            ;; 2026-05-20).  Was buried at level 3 inside `** Provided
            ;; Translations'.  Now sits immediately AFTER Interlinear and
            ;; BEFORE the AI translations — natural reading order for
            ;; class:  word-for-word trot → per-word annotations → fluent
            ;; AI translations → grammar.  Populated asynchronously by
            ;; `tibetan-analysis--insert-claude-sections' (Claude section-
            ;; order has the `:vocabulary' entry at level 2 now).
            ;; ============================================================
            (insert "** Claude Vocabulary\n")
            (insert "[Awaiting Claude…]\n\n")

            ;; ============================================================
            ;; SECTION 1b: Claude Translation (promoted to level 2)
            ;; Kept at the top so students see the fluent English rendering
            ;; right after the Wylie reading — before the word-by-word lists.
            ;; Populated asynchronously by `tibetan-analysis--insert-claude-sections'.
            ;; ============================================================
            (insert "** Claude Translation\n")
            (insert "[Requesting translation...]\n\n")

            ;; ============================================================
            ;; SECTION 1c: DharmaMitra Translation (level-2, sibling of
            ;; Claude Translation).  Populated asynchronously by
            ;; `tibetan-dharmamitra-translation-fire-tibetan'.  Placed
            ;; immediately after Claude so the two AI translations
            ;; sit side by side for class comparison (2026-05-19).
            ;; ============================================================
            (insert "** DharmaMitra Translation\n")
            (insert "[Awaiting DharmaMitra…]\n\n")

            ;; ============================================================
            ;; ** Concept Notes (§5.24, 2026-05-22).  Class-reading
            ;; surface for Buddhist + Sanskrit technical concepts,
            ;; lineage / person / place names, doxography.  Replaces
            ;; the retired narrative-arc `*** Claude Context' (which
            ;; sat inside Provided Translations in sentence files
            ;; only).  Placement:  after the two AI translations,
            ;; before Grammar — reader-flow `read → concept lookup
            ;; → grammar'.  Populated asynchronously by Claude's
            ;; `## Concept Notes' response section.
            ;; ============================================================
            (insert "** Concept Notes\n")
            (insert "[Awaiting Claude…]\n\n")

            ;; ============================================================
            ;; SECTION 2: Word / Particle List
            ;; Compact, numbered list for word-by-word reading in class.
            ;; Format:  N. Tibetan  wylie  [tag]  — short gloss [★ if Resources]
            ;; Glosses are pulled from the same layered lookup the Detailed
            ;; Dictionary uses (Resources → Custom → Bundled → Rangjung Yeshe
            ;; → DharmaMitra), so short glosses match the dictionary entries
            ;; below.  Falls back to vocab-pairs meaning if lookup misses.
            ;; Tag is shown only when informative (particle category, verb).
            ;; ============================================================
            ;; ============================================================
            ;; SECTION 2 (computation-only): build `enriched-vocab-pairs'
            ;; and `curated-words-hash' from the vocabulary layer.
            ;; ============================================================
            ;; Previously this loop also emitted a `** Word / Particle List'
            ;; section.  Removed 2026-04-21 per user feedback — the
            ;; Interlinear Gloss above carries the same information in a
            ;; denser, more readable form, and repeating it here just
            ;; duplicated the word-by-word listing.  We keep the ENTIRE
            ;; computation because:
            ;;   1. `enriched-vocab-pairs' is consumed by the CAT Gloss
            ;;      renderer (section 8b below) and by the Interlinear
            ;;      generator itself.
            ;;   2. `curated-words-hash' (new) is consumed by the Interlinear
            ;;      renderer to prepend ★ to Resources / Custom entries so
            ;;      students can spot authoritative, hand-curated glosses
            ;;      at a glance.
            (when vocab-pairs
              (let ((idx 1))
                (dolist (pair vocab-pairs)
                    (let* ((word (car pair))
                           (fallback-meaning (cdr pair))
                           ;; Strip shad/punctuation before lookup so ལ། → ལ,
                           ;; otherwise dictionary lookup misses and we fall
                           ;; through to noisy partial matches.
                           ;;
                           ;; 2026-04-24 (B3): previously stripped only
                           ;; TRAILING shads via `[།༎༏༐༑ ]+$'.  Leading
                           ;; shads from verse-start tokens (e.g. the second
                           ;; pada of `na/ /byang chub ...') survived and
                           ;; leaked into the Interlinear link label as
                           ;; `/byang chub ...'.  The helper mirrors the
                           ;; two sibling cleanup sites (--get-grammatical-
                           ;; role, --build-cat-translation) that already
                           ;; strip all shads.
                           (word-clean (tibetan-analysis--clean-word-token word))
                           (root-form (tibetan-strip-particles word-clean))
                           (gram-role (tibetan-analysis--get-grammatical-role
                                       word-clean root-form verb-table))
                           ;; Formerly shown as `[TAG]' in the Word / Particle
                           ;; List heading (removed 2026-04-21).  Kept in the
                           ;; binding chain because `root-form' and
                           ;; `gram-role' remain useful further down for the
                           ;; `curated-source-p' / `verb-gloss' enrichment.
                           ;; Underscore prefix silences the byte-compiler.
                           (_tag (cond
                                  ((null gram-role) nil)
                                  ((member gram-role
                                           '("Noun" "?" "Unknown" "N")) nil)
                                  (t gram-role)))
                           ;; Primary lookup: route through the SAME multi-source
                           ;; pipeline that the Detailed Dictionary section uses,
                           ;; taking the HIGHEST-RANKED entry across both the
                           ;; full word and its stem form.  This is the
                           ;; Resources-first priority chain.
                           ;;
                           ;; Bug fixed 2026-04-22: the previous implementation
                           ;; was `(or word-lookup stem-lookup)', which
                           ;; short-circuits on any word-level hit including a
                           ;; low-rank Bundled / DharmaMitra entry.  For
                           ;; `mthu'i' the word-level lookup returned a Bundled
                           ;; hit (rank 9) so the stem lookup (`mthu' → Resources
                           ;; rank 2, Hopkins rank 4, ...) was never tried, and
                           ;; the Interlinear Gloss silently dropped the curated
                           ;; German // English gloss + ★ that the Detailed
                           ;; Dictionary correctly surfaced.
                           ;;
                           ;; Fix: run BOTH lookups, concatenate, re-apply the
                           ;; ranker, pick the top.  Stem entries dominate for
                           ;; particle-bearing words (`mthu'i' → `mthu' wins);
                           ;; full-word entries dominate for compounds with no
                           ;; strippable suffix (`grogs po' → `grogs po' wins,
                           ;; because `strip-particles' leaves it alone and the
                           ;; second lookup is a no-op).
                           (detailed-entry
                            (condition-case nil
                                (when (fboundp 'tibetan-vocab-multisource-entries)
                                  (let* ((word-entries
                                          (tibetan-vocab-multisource-entries
                                           word-clean))
                                         (stem-entries
                                          (and root-form
                                               (not (string-empty-p root-form))
                                               (not (string= root-form
                                                             word-clean))
                                               (tibetan-vocab-multisource-entries
                                                root-form)))
                                         (combined
                                          (append word-entries stem-entries)))
                                    (when combined
                                      (if (fboundp 'tibetan-vocab--sort-entries-by-rank)
                                          (car (tibetan-vocab--sort-entries-by-rank
                                                combined))
                                        (car combined)))))
                              (error nil)))
                           ;; Multi-source labels Resources as "Resources (provided)";
                           ;; downstream checks need to recognise both that and the
                           ;; bare "Resources" / "Custom" labels older paths produced.
                           (source (and detailed-entry
                                        (plist-get detailed-entry :source)))
                           (curated-source-p
                            (and source
                                 (or (string-prefix-p "Resources" source)
                                     (string-prefix-p "Custom" source))))
                           ;; Resources/Custom entries are hand-curated and
                           ;; compact (German // English format), so use the
                           ;; full :detailed field — :primary is cut off at the
                           ;; first comma/period, which mangles German syn-lists
                           ;; and abbreviations like "Pf.".  For larger
                           ;; dictionaries (RY, DharmaMitra, Bundled), :primary
                           ;; is the appropriate short sense.
                           (clean-meaning
                            (when detailed-entry
                              (if curated-source-p
                                  (or (plist-get detailed-entry :detailed)
                                      (plist-get detailed-entry :primary))
                                (or (plist-get detailed-entry :primary)
                                    (plist-get detailed-entry :detailed)))))
                           ;; Fall back to the raw vocab-pairs meaning.
                           (raw-meaning (or clean-meaning
                                            (when (and fallback-meaning
                                                       (not (string= fallback-meaning
                                                                     "[look up]"))
                                                       (not (string= fallback-meaning
                                                                     "[not found]")))
                                              fallback-meaning)))
                           ;; Tidy the gloss without over-truncating.
                           ;;
                           ;; Empty-string guard (P5 fix, 2026-04-30):
                           ;; `raw-meaning' can be an empty string when
                           ;; `tibetan-vocab-multisource-entries' returned a
                           ;; detailed-entry whose `:primary' / `:detailed'
                           ;; field is `""' (e.g.  `གྱུར་པའོ' /
                           ;; gotrapaṭala seg-030..034 corner case).
                           ;; `(when raw-meaning …)' enters the body for
                           ;; `""' (truthy in elisp), then `(car
                           ;; (split-string "" ";" t))' returns nil and
                           ;; downstream `(string-trim nil)' raises
                           ;; `Wrong type argument: stringp, nil', tripping
                           ;; the outer condition-case fallback that
                           ;; emits `[Analysis error — partial file
                           ;; only]'.  Treat empty-after-trim as `no
                           ;; gloss' so the binding becomes nil and the
                           ;; downstream short-meaning chain follows the
                           ;; same path as a missing dictionary entry.
                           (short-meaning
                            (when (and raw-meaning
                                       (not (string-empty-p
                                             (string-trim raw-meaning))))
                              (let ((m (string-trim raw-meaning)))
                                ;; Strip leading numbering like "1) " or "1. "
                                (setq m (replace-regexp-in-string
                                         "^[0-9]+[.):]\\s-*" "" m))
                                ;; For non-curated dictionaries, keep only the
                                ;; first sense (before ';' — proper sense
                                ;; separator).  Curated Resources entries are
                                ;; already compact, so leave intact.
                                (unless curated-source-p
                                  (setq m (string-trim
                                           (car (split-string m ";" t)))))
                                ;; Truncate only non-curated sources.  Resources
                                ;; and Custom entries are hand-written compact
                                ;; glosses — cutting them loses the critical
                                ;; "im Spiel einsetzen" / "to stake" sense.
                                (setq m (if (and (not curated-source-p)
                                                 (> (length m) 90))
                                            (concat (substring m 0 87) "…")
                                          m))
                                ;; Strip trailing Wylie cross-reference compounds
                                ;; that some user wordlists bake into the gloss
                                ;; (e.g. "dice kha phung la thong" → "dice").
                                (tibetan-analysis--strip-wylie-tail m))))
                           ;; Safety-net enrichment: if the gloss at this point
                           ;; is still a bare stem reference (e.g. "pf. of byed"),
                           ;; chase the base verb and append its meaning.  This
                           ;; catches cases where the text came through the
                           ;; vocab-pairs fallback path or any other route that
                           ;; bypassed `tibetan-vocab-lookup-detailed'-level
                           ;; enrichment. Skip if already enriched (em dash
                           ;; present after the reference).
                           (short-meaning
                            (if (and short-meaning
                                     (fboundp 'tibetan-vocab--extract-stem-reference)
                                     (fboundp 'tibetan-vocab--lookup-base-meaning)
                                     (not (string-match-p " — " short-meaning)))
                                (let ((stem-base
                                       (tibetan-vocab--extract-stem-reference
                                        short-meaning)))
                                  (if stem-base
                                      (let ((base-m
                                             (tibetan-vocab--lookup-base-meaning
                                              stem-base)))
                                        (if (and base-m
                                                 (not (string-empty-p base-m))
                                                 (not (tibetan-vocab--extract-stem-reference
                                                       base-m)))
                                            (format "%s — %s"
                                                    short-meaning
                                                    ;; Trim base gloss at first
                                                    ;; semicolon to keep it short.
                                                    (string-trim
                                                     (car (split-string base-m ";" t))))
                                          short-meaning))
                                    short-meaning))
                              short-meaning))
                           ;; Verb-morphology enrichment: when the stripped
                           ;; root is a verb in the Hill 2010 DB and the
                           ;; current gloss is either missing, unhelpful
                           ;; (e.g. RY "verb: do"), or short/non-curated,
                           ;; swap in a morphology-aware gloss built from
                           ;; the lemma and its stem class.  Resources and
                           ;; Custom entries are hand-curated and always win;
                           ;; we only augment if they don't already reference
                           ;; the verb lemma explicitly.
                           (verb-gloss
                            (tibetan-analysis--verb-morphology-gloss root-form))
                           (short-meaning
                            (cond
                             ;; No verb info → keep whatever we had.
                             ((null verb-gloss) short-meaning)
                             ;; No gloss at all yet → use verb gloss.
                             ((or (null short-meaning)
                                  (string-empty-p short-meaning))
                              verb-gloss)
                             ;; Curated Resources/Custom entry: don't replace
                             ;; the human-written bilingual gloss.
                             (curated-source-p
                              short-meaning)
                             ;; Current gloss already contains a stem
                             ;; reference ("pf. of X — ...") from the
                             ;; previous enrichment pass.  Leave it.
                             ((and (fboundp 'tibetan-vocab--extract-stem-reference)
                                   (tibetan-vocab--extract-stem-reference
                                    short-meaning))
                              short-meaning)
                             ;; Current gloss already echoes the Hill meaning.
                             ;; Look at the first *content* word (≥4 chars,
                             ;; not a function word) so "to" doesn't cause
                             ;; false matches between e.g. "to arrive" and
                             ;; "to extend to".
                             ((let* ((case-fold-search t)
                                     (words (split-string verb-gloss
                                                          "[ ,;—.]+" t))
                                     (distinctive
                                      (car (seq-filter
                                            (lambda (w)
                                              (and (>= (length w) 4)
                                                   (not (member (downcase w)
                                                                '("the" "verb"
                                                                  "noun")))))
                                            words))))
                                (and distinctive
                                     (string-match-p
                                      (regexp-quote distinctive)
                                      short-meaning)))
                              short-meaning)
                             ;; Otherwise, replace the non-curated gloss
                             ;; (typically RY's "verb: do"/"a loss") with
                             ;; the Hill-based morphology gloss.
                             (t verb-gloss)))
                           ;; Claude-based sense override (B1, B2, 2026-04-24).
                           ;; After ALL dictionary-derived refinements, let
                           ;; Claude's own per-word output have the final word.
                           ;;   B1: dict gloss starts with `<person>'/`<place>'
                           ;;       tag (Steinert 84000Dict proper-noun marker)
                           ;;       AND Claude Vocabulary has a verb / lexical
                           ;;       reading → use Claude's quoted gloss.
                           ;;   B2: Claude Particles tagged this token with a
                           ;;       specific function (conditional, terminative,
                           ;;       etc.) → use `LABEL (§SUB-ID)' as the gloss
                           ;;       so the Interlinear reflects the grammar.
                           ;; First-time generation runs with both dynamic vars
                           ;; nil — overrides degrade to no-ops.  The regen
                           ;; path (C-c u R / C-c u r / auto-regen on Claude
                           ;; arrival) sees them bound.
                           (short-meaning
                            (or (tibetan-analysis--claude-particle-label-for-token
                                 word-clean
                                 tibetan-analysis--claude-particles-for-render)
                                (tibetan-analysis--apply-claude-vocab-override
                                 word-clean
                                 short-meaning
                                 tibetan-analysis--claude-vocabulary-for-render))))
                      ;; Mark Resources / Custom entries in the curated hash
                      ;; so the Interlinear renderer can prepend ★.  The
                      ;; `source' variable is set earlier in this let* from
                      ;; `detailed-entry's :source plist field.
                      (when (and source
                                 (or (string-prefix-p "Resources" source)
                                     (string-prefix-p "Custom" source)))
                        (puthash word-clean t curated-words-hash))
                      ;; Record the enriched gloss for reuse by the CAT Gloss
                      ;; section and the Interlinear generator.  We store the
                      ;; ORIGINAL surface word (with particles still attached)
                      ;; so the CAT renderer can pattern-match on converb/case
                      ;; endings.
                      (push (cons word-clean short-meaning)
                            enriched-vocab-pairs)
                      (setq idx (1+ idx))))))
            (setq enriched-vocab-pairs (nreverse enriched-vocab-pairs))

            ;; ============================================================
            ;; SECTION 1a (deferred): Interlinear Gloss + Particle Overview
            ;; Now that enriched-vocab-pairs is ready, go back to the marker
            ;; position and insert the interlinear sections before Claude
            ;; Translation.
            ;; ============================================================
            (when (and enriched-vocab-pairs
                       (fboundp 'tibetan-interlinear-insert-sections))
              (let ((bialek-data (condition-case nil
                                     (when (fboundp 'tibetan-analyze-grammar-bialek)
                                       (tibetan-analyze-grammar-bialek tibetan-text))
                                   (error nil))))
                (save-excursion
                  (goto-char interlinear-marker)
                  (tibetan-interlinear-insert-sections
                   enriched-vocab-pairs
                   bialek-data
                   tibetan-text
                   vocab-pairs
                   curated-words-hash))))
            (when interlinear-marker
              (set-marker interlinear-marker nil))

            ;; ============================================================
            ;; SECTION 3b: Grammar (merged Particle Map + Particle
            ;; Overview + Grammatical Markers — Pass 6b, 2026-04-22).
            ;; Pass 6c adds the Claude-tagged particle functions +
            ;; Portfolio snippets when available via the dynamic var
            ;; `tibetan-analysis--claude-particles-for-render'.
            ;; ============================================================
            (let ((bialek-analysis (condition-case nil
                                       (when (fboundp 'tibetan-analyze-grammar-bialek)
                                         (tibetan-analyze-grammar-bialek tibetan-text))
                                     (error nil))))
              (tibetan-analysis--render-grammar-section
               tibetan-text particles verbs bialek-analysis
               tibetan-analysis--claude-particles-for-render
               enriched-vocab-pairs))

            ;; ============================================================
            ;; SECTION 4: Sentence Structure (merged — Pass 6b, 2026-04-22)
            ;; ============================================================
            ;; Pass 6b merged the old skinny `** Sentence Structure'
            ;; (verb-then-arguments one-liner) into the Round-2 clause
            ;; structure — the Round-2 output ALREADY carries per-
            ;; clause verb + NPs + roles + converb dependency, which is
            ;; a strict superset of the old skinny line.  We rename
            ;; the merged view to `** Sentence Structure' because
            ;; that's the conceptual label students expect at this
            ;; level of analysis; `** Clause Structure' as a label is
            ;; retired.  The gate `tibetan-analysis-show-clause-
            ;; structure' still controls whether the section appears
            ;; at all (default t).
            (when tibetan-analysis-show-clause-structure
              (insert "** Sentence Structure\n")
              (let ((rendered (tibetan-analysis--render-clause-structure
                               words verbs multiword-units)))
                (if (and rendered (not (string-empty-p rendered)))
                    (insert rendered)
                  (insert "[Round-2 sentence structure unavailable]\n")))
              (insert "\n"))

            ;; ============================================================
            ;; SECTION 5: Verb Classification (Hill 2010) - detailed format
            ;; ============================================================
            (insert "** Verb Classification (Hill 2010)\n")
            ;; Only show full records here; `minimal' entries (from the
            ;; minor-verb / modal / reporting fallback sets) lack stem and
            ;; case-frame data — they'd render as noise.
            (let ((full-verbs (cl-remove-if (lambda (v)
                                              (alist-get 'minimal v))
                                            verbs)))
              (if full-verbs
                  (dolist (verb full-verbs)
                    (when (and verb (listp verb) (consp (car verb)))
                      (let* ((lemma (alist-get 'lemma verb))
                             (meaning (alist-get 'meaning verb))
                             (present (or (alist-get 'present_stem verb) "—"))
                             (past (or (alist-get 'past_stem verb) "—"))
                             (future (or (alist-get 'future_stem verb) "—"))
                             (imperative (or (alist-get 'imperative_stem verb) "—"))
                             (vol (or (alist-get 'volitionality verb) "?"))
                             (trans (or (alist-get 'transitivity verb) "?"))
                             (frame (or (alist-get 'case_frame verb) "?"))
                             (class (or (alist-get 'indigenous_class verb) "?")))
                        (insert (format "- %s"
                                        (tibetan-analysis--format-word-with-wylie
                                         lemma)))
                        (when meaning
                          (insert (format " — %s" meaning)))
                        (insert "\n")
                        ;; Note which stem actually appears in the text
                        ;; when it's NOT the present/lemma form — so the
                        ;; reader sees e.g. the perfect stem was attested.
                        (let* ((surface (alist-get 'source-form verb))
                               (matched
                                (and surface
                                     (fboundp 'tibetan-verb-matched-stem)
                                     (tibetan-verb-matched-stem surface verb))))
                          (when (and matched (not (eq matched 'present)))
                            (insert
                             (format "  ATTESTED: %s — %s stem\n"
                                     (tibetan-analysis--format-word-with-wylie
                                      surface)
                                     (pcase matched
                                       ('past "perfect (past)")
                                       ('future "future")
                                       ('imperative "imperative")
                                       (_ (symbol-name matched)))))))
                        (insert (format "  STEMS: %s / %s / %s / %s\n"
                                        (tibetan-analysis--format-word-with-wylie
                                         present)
                                        (tibetan-analysis--format-word-with-wylie
                                         past)
                                        (tibetan-analysis--format-word-with-wylie
                                         future)
                                        (tibetan-analysis--format-word-with-wylie
                                         imperative)))
                        (insert (format "  CLASS: %s, %s, %s\n" vol trans frame))
                        (insert (format "  TIBETAN: %s\n\n"
                                        (cond
                                         ((string= class "tha_dad_pa")
                                          "ཐ་དད་པ་ (transitive)")
                                         ((string= class "tha_mi_dad_pa")
                                          "ཐ་མི་དད་པ་ (intransitive)")
                                         (t "—")))))))
                (insert "[No Hill-DB verbs detected]\n")))
            (insert "\n")

            ;; NOTE: Zero-Marked NPs section removed - was producing confusing output

            ;; ============================================================
            ;; SECTION 7: Provided Translations (combine step)
            ;;
            ;; §5.21 Commit 5/7 (2026-05-20):  SWAPPED with the
            ;; Detailed Dictionary emission below.  Provided
            ;; Translations now renders BEFORE the Detailed
            ;; Dictionary so the dictionary moves to the very bottom
            ;; of `* Tibetan Analysis' — class-use feedback:  DD is
            ;; reference material consulted on confusion, not flow
            ;; reading;  it shouldn't sit between Verb Classification
            ;; and Provided Translations.  Reader-flow goal:  Wylie
            ;; → Phonetics → Interlinear → Translations → Grammar →
            ;; Sentence/Verb structure → Provided Translations →
            ;; Detailed Dictionary (reference, not flow).
            ;; ============================================================
            ;; §5.21 Commit 6/7 (2026-05-20):  Provided Translations
            ;; becomes a PURELY USER-CONTENT slot — pristine empty
            ;; placeholder at the renderer level;  the regenerate-auto
            ;; path preserves any hand-pasted body across regenerates
            ;; (same pattern as `* My Notes' / `* Working Translation'
            ;; / the §5.20 nested DharmaMitra body).  Carsten pastes
            ;; published / hand-curated reference translations
            ;; (Roehrich, Lopez, Bialek-style published English
            ;; renderings) into this slot during class prep;  prior
            ;; behaviour clobbered them on every reanalyze.
            ;;
            ;; Retired auto-children:
            ;;  · `*** CAT Gloss'           — Commit 1 of this batch.
            ;;  · `*** Claude Vocabulary'   — Commit 2 (promoted to
            ;;                                  level-2 under
            ;;                                  Interlinear).
            ;;  · `*** Reference Translations' (auto-populated from
            ;;     external PDF/text in Resources) — retired here.
            ;;     For paragraph-mode files (`par-NNN.org') the
            ;;     reference translations still live at the TOP-LEVEL
            ;;     `* Reference Translations' section emitted by
            ;;     `tibetan-analysis-create-paragraph-file' from sibling
            ;;     subsections of the source `** §N' heading.  For
            ;;     segment files, Carsten now pastes reference
            ;;     translations into PT directly — auto-population
            ;;     was a useful pre-fill but tripped the preserve
            ;;     story (the user-edited version got overwritten
            ;;     on every regenerate).  Manual paste survives
            ;;     verbatim.
            (insert "** Provided Translations\n\n\n")

            ;; ============================================================
            ;; SECTION 8 (§5.21 Commit 5/7, 2026-05-20):  Detailed
            ;; Dictionary (rich entries with Sanskrit).  Now emitted
            ;; AFTER Provided Translations so it sits at the BOTTOM
            ;; of `* Tibetan Analysis' as reference material — was
            ;; SECTION 7 (between Verb Classification and Provided
            ;; Translations) pre-§5.21.  Body unchanged;  the
            ;; per-entry rendering improvement was deferred per
            ;; AskUserQuestion.
            ;;
            ;; The bialek analysis is threaded through so the
            ;; renderer can split word+particle compounds the same
            ;; way the Interlinear does — anchoring `mthu'i' under
            ;; `<<term-mthu>>' so the Interlinear's jump link
            ;; resolves to the real stem entry.
            ;; ============================================================
            (let ((bialek-for-dd
                   (condition-case nil
                       (when (fboundp 'tibetan-analyze-grammar-bialek)
                         (tibetan-analyze-grammar-bialek tibetan-text))
                     (error nil))))
              (tibetan-analysis--render-detailed-dictionary
               tibetan-text vocab-pairs bialek-for-dd))

            ;; Reorder level-2 sections into the workshop-agreed
            ;; priority: Wylie → Particle Map → Interlinear Gloss →
            ;; Verb Classification → Claude Translation → Claude
            ;; Grammar, with the remaining sections retained in
            ;; their generated order afterwards.  Also promotes the
            ;; level-3 `*** Claude Grammar' out of `** Provided
            ;; Translations' so it can take its priority slot.
            (tibetan-analysis--reorder-auto-content (buffer-string)))))
    (error
     ;; On error, return a minimal analysis that STILL preserves the
     ;; most important user-facing sections:
     ;;   - Wylie Transliteration (computed independently, usually works)
     ;;   - Claude Translation placeholder (so `tibetan-auto-request-
     ;;     claude-translations' can still fire and fill it in)
     ;;   - Grammar scaffold with nested Claude Grammar placeholder
     ;;     (U4 layout, 2026-04-24)
     ;; Followed by a visible `[ANALYSIS ERROR]' marker so the user can
     ;; spot the file and investigate.  Previously this emitted only
     ;; three stub sections (Wylie/Provided/Vocabulary) with `[Error]'
     ;; bodies, which meant a parser failure on ONE corner-case verb
     ;; form (e.g. YBh seg-30..34's `gyur pa'o') stripped an otherwise-
     ;; usable analysis file down to unusable scaffolding.
     (let ((wylie (condition-case nil
                      (when (and (stringp tibetan-text)
                                 (fboundp 'tibetan-to-wylie-fixed))
                        (tibetan-to-wylie-fixed tibetan-text))
                    (error nil))))
       (concat "** Wylie Transliteration\n"
               (or wylie "[Wylie conversion unavailable]")
               "\n\n"
               "** Claude Translation\n[Requesting translation...]\n\n"
               "** Grammar\n*** Claude Grammar\n\n\n"
               (format "** [Analysis error — partial file only]\nParser failure for this segment: %s\n\nThe structural analysis sections (Particle Map, Interlinear Gloss, Word/Particle List, Verb Classification, Grammatical Markers, Sentence Structure, Clause Structure, Detailed Dictionary) could not be generated.  The Tibetan Text and Claude sections above should still be usable.\n\nTo retry: `C-c u R' on this segment, or check the source segment's Tibetan for an unusual construction.\n"
                       (error-message-string err))))))))

;; ============================================================================
;; MAIN COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-open-segment-analysis ()
  "Open or create analysis, dispatched by cursor context (all 3 levels).
Priority is most-specific-wins, respecting nested org layouts:

  1. `*** Segment N' / `**** Segment N' heading (or its body)
     → classical segment-level analysis (seg-NNN.org)
  2. `*** Sentence N' heading (or its body between segments)
     → `tibetan-sentence-open-analysis' (sent-NNN.org)
  3. `** §N' paragraph heading (or any descendant when the subtree
     has no sentence/segment children)
     → `tibetan-open-paragraph-analysis' (par-NNN.org)
  4. Legacy 〔seg:…〕 or plain-text line
     → classical segment impl via `-any-format' detection.

Segment/sentence detectors only look at the nearest heading, so
they remain mutually exclusive.  The paragraph detector walks up
the outline (it's true anywhere inside a §-subtree), so checking
it last prevents paragraph from swallowing a nested segment or
sentence."
  (interactive)
  (cond
   ((and (derived-mode-p 'org-mode)
         (fboundp 'tibetan-org-at-segment-p)
         (tibetan-org-at-segment-p))
    (tibetan--open-segment-analysis-impl))
   ((and (derived-mode-p 'org-mode)
         (fboundp 'tibetan-org-at-sentence-p)
         (tibetan-org-at-sentence-p)
         (fboundp 'tibetan-sentence-open-analysis))
    (tibetan-sentence-open-analysis))
   ((and (derived-mode-p 'org-mode)
         (fboundp 'tibetan-org-at-paragraph-p)
         (tibetan-org-at-paragraph-p))
    (tibetan-open-paragraph-analysis))
   (t
    ;; Not inside a recognised heading — let the classical
    ;; implementation try legacy 〔seg:…〕 and plain-text fallbacks.
    (tibetan--open-segment-analysis-impl))))

(defun tibetan--open-segment-analysis-impl ()
  "Segment-level implementation; see `tibetan-open-segment-analysis'."
  (let* ((seg-data (tibetan-get-current-segment-any-format))
         (seg-id (car seg-data))
         (tibetan-text (cdr seg-data))
         ;; P6 (2026-05-05): grab the source segment's `:FOLIO:'
         ;; before any extractor strips the drawer, so it can be
         ;; threaded into the new analysis file's `* Tibetan Text'
         ;; heading.  nil for non-YBh sources without a folio drawer.
         (segment-folio (and (fboundp 'tibetan-org-get-segment-folio)
                             (tibetan-org-get-segment-folio)))
         ;; Capture full source buffer text so inline 〔trans:N〕
         ;; blocks from the class file can be surfaced as reference
         ;; translations.
         (source-text (buffer-substring-no-properties
                       (point-min) (point-max))))

    (unless seg-data
      (error "Not in a segment or paragraph"))

    (let* ((source-file (buffer-file-name))
           ;; §5.23 (2026-05-22):  thread source-file so the lookup
           ;; resolves to the SUFFIXED `seg-NNN-SHORT.org' path —
           ;; matches what `tibetan-analysis-create-file' writes
           ;; post-§5.23.
           (filepath (tibetan-analysis-get-filepath seg-id source-file))
           (exists (file-exists-p filepath)))

      (if exists
          ;; File exists - check sync and open
          (progn
            (unless (tibetan-analysis-check-sync filepath tibetan-text)
              (message "WARNING: Source text has changed since last analysis!"))
            (let ((buf (find-file-noselect filepath)))
              (with-current-buffer buf
                (tibetan-analysis-setup-faces)
                ;; Always land at the top of the analysis file.  Without
                ;; this, `save-place-mode' (or the mid-insert point left
                ;; by Claude's async callback before the last save)
                ;; would drop the cursor near the bottom — confusing
                ;; when you expect to see Tibetan Text first.
                (goto-char (point-min)))
              (display-buffer-in-side-window buf
                                             '((side . right)
                                               (window-width . 0.5))))
            ;; 2026-04-24: if the file's Claude Translation is still a
            ;; placeholder (original Claude fire never completed, or
            ;; OTPM'd out), auto-fire a fresh request on open.  Covers
            ;; the common case where seg-NNN.org was created weeks ago
            ;; but Claude never filled it in — previously you had to
            ;; notice this and explicitly run `C-c u F' or `C-c u R'.
            (when (and (fboundp 'tibetan-auto--claude-needs-request-p)
                       (tibetan-auto--claude-needs-request-p filepath))
              (message "Claude placeholder detected — firing translation request for seg-%s"
                       seg-id)
              (condition-case err
                  (tibetan-analysis--request-claude-translation
                   tibetan-text filepath source-file)
                (error
                 (message "Claude auto-fire skipped for seg-%s: %s"
                          seg-id (error-message-string err)))))
            ;; Phase A.1.5 of multi-translator-parallel-reading
            ;; (2026-04-30) + bug fix 2026-05-04: also auto-fire
            ;; DharmaMitra translation when the existing analysis file
            ;; lacks EITHER a populated Tibetan DM section OR a
            ;; populated Sanskrit DM section.
            ;;
            ;; Pre-fix:  the gate checked ONLY `--needs-request-p
            ;; filepath "Tibetan"'.  When yesterday's run populated
            ;; Tibetan-DM but Sanskrit-DM never landed (interrupted
            ;; fire, etc.), the gate returned nil on every subsequent
            ;; `C-c u A' — leaving `* DharmaMitra Translation
            ;; (Sanskrit)' permanently absent.
            ;;
            ;; The umbrella `fire-for-segment' does internal per-
            ;; language gating (parallel-mode + non-placeholder
            ;; sibling), so calling it when EITHER side needs work
            ;; correctly skips the populated side and fires only the
            ;; missing one.
            (when (and (fboundp 'tibetan-dharmamitra-translation-needs-fire-on-open-p)
                       (fboundp 'tibetan-dharmamitra-translation-fire-for-segment)
                       (tibetan-dharmamitra-translation-needs-fire-on-open-p
                        filepath))
              (condition-case err
                  (tibetan-dharmamitra-translation-fire-for-segment
                   tibetan-text filepath source-file seg-id)
                (error
                 (message "DharmaMitra auto-fire skipped for seg-%s: %s"
                          seg-id (error-message-string err)))))
            ;; Phase 5 of two-language-parallel-analysis (§5.17,
            ;; 2026-04-30):  when the existing file lacks a
            ;; populated `* Sanskrit Analysis' / `* Combined
            ;; Analysis', auto-fire the dispatcher just like Claude
            ;; / DM auto-fire above.  Bug fix 2026-05-02: this wire
            ;; was missed when §5.17 shipped — interactive
            ;; `C-c u A' on an existing pre-parallel-mode file would
            ;; otherwise never grow the new sections even after
            ;; source-side Sanskrit alignment landed.  No-op when
            ;; source isn't parallel-mode or sibling is placeholder.
            (when (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls)
              (condition-case err
                  (tibetan-analysis--fire-parallel-mode-claude-calls
                   tibetan-text source-file filepath)
                (error
                 (message "Sanskrit/Combined auto-fire skipped for seg-%s: %s"
                          seg-id (error-message-string err))))))
        ;; Create new file.  Phase 6 of sanskrit-parallel-workflow
        ;; (2026-04-27): in parallel-Sanskrit mode, thread the
        ;; segment's `**** Sanskrit' sibling through the render var
        ;; so the new file emits `** Sanskrit Source' above Wylie.
        ;; The wrapper returns nil when the source isn't in parallel
        ;; mode, so non-parallel callers see no change.
        (let* ((tibetan-analysis--sanskrit-text-for-render
                (and (fboundp 'tibetan-sanskrit-parallel-plist-for-segment-id)
                     (condition-case nil
                         (tibetan-sanskrit-parallel-plist-for-segment-id
                          source-file seg-id)
                       (error nil))))
               (auto-content (tibetan-analysis-generate-content
                              tibetan-text seg-id source-text))
               (new-filepath (tibetan-analysis-create-file
                              seg-id tibetan-text source-file
                              auto-content segment-folio)))
          (message "Created analysis file: %s" new-filepath)
          (let ((buf (find-file-noselect new-filepath)))
            (with-current-buffer buf
              (tibetan-analysis-setup-faces)
              (goto-char (point-min)))
            (display-buffer-in-side-window buf
                                           '((side . right)
                                             (window-width . 0.5))))
          ;; Request Claude translation asynchronously (never break on failure)
          (condition-case err
              (tibetan-analysis--request-claude-translation tibetan-text new-filepath)
            (error (message "Claude translation skipped: %s" (error-message-string err))))
          ;; Phase A.1 of multi-translator-parallel-reading (2026-04-30):
          ;; Fire DharmaMitra translation alongside Claude.  Soft-coded —
          ;; missing module / API failures are silent (NOT broadcast as
          ;; user-facing errors) so a DM outage doesn't disrupt the
          ;; Claude-driven primary workflow.  Phase A.2 (2026-04-30):
          ;; uses umbrella `fire-for-segment' which fires BOTH Tibetan
          ;; AND Sanskrit (parallel-mode + sibling) automatically.
          (when (fboundp 'tibetan-dharmamitra-translation-fire-for-segment)
            (condition-case err
                (tibetan-dharmamitra-translation-fire-for-segment
                 tibetan-text new-filepath source-file seg-id)
              (error (message "DharmaMitra translation skipped: %s"
                              (error-message-string err)))))
          ;; Phase 5 of two-language-parallel-analysis (§5.17,
          ;; 2026-04-30):  on first creation of a parallel-mode
          ;; segment file, also fire Sanskrit + Combined Claude
          ;; calls so all three top-level analyses land together.
          ;; Bug fix 2026-05-02: this wire was missed when §5.17
          ;; shipped — `C-c u A' on a fresh segment otherwise only
          ;; produced the Tibetan side.  No-op when source isn't
          ;; parallel-mode or sibling is placeholder.
          (when (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls)
            (condition-case err
                (tibetan-analysis--fire-parallel-mode-claude-calls
                 tibetan-text source-file new-filepath)
              (error (message "Sanskrit/Combined first-fire skipped: %s"
                              (error-message-string err))))))))))

;;;###autoload
(defun tibetan-reanalyze-segment ()
  "Re-analyze current segment / sentence / paragraph, preserving user notes.
Dispatches by context exactly like `tibetan-open-segment-analysis':
segment > sentence > paragraph > legacy, most-specific-wins."
  (interactive)
  (cond
   ((and (derived-mode-p 'org-mode)
         (fboundp 'tibetan-org-at-segment-p)
         (tibetan-org-at-segment-p))
    (tibetan--reanalyze-segment-impl))
   ((and (derived-mode-p 'org-mode)
         (fboundp 'tibetan-org-at-sentence-p)
         (tibetan-org-at-sentence-p)
         (fboundp 'tibetan-sentence-reanalyze))
    (tibetan-sentence-reanalyze))
   ((and (derived-mode-p 'org-mode)
         (fboundp 'tibetan-org-at-paragraph-p)
         (tibetan-org-at-paragraph-p))
    (tibetan-reanalyze-paragraph))
   (t
    (tibetan--reanalyze-segment-impl))))

(defun tibetan--reanalyze-segment-impl ()
  "Segment-level implementation; see `tibetan-reanalyze-segment'."
  (let* ((seg-data (tibetan-get-current-segment-any-format))
         (seg-id (car seg-data))
         (tibetan-text (cdr seg-data))
         ;; Same source-text capture as in `tibetan-open-segment-analysis'
         ;; so re-analysis picks up edits to the inline 〔trans:N〕 block.
         (source-text (buffer-substring-no-properties
                       (point-min) (point-max))))

    (unless seg-data
      (error "Not in a segment or paragraph"))

    ;; §5.23 (2026-05-22):  thread source-file (= current buffer)
    ;; so the lookup resolves to `seg-NNN-SHORT.org'.  Falls back to
    ;; UNSUFFIXED `seg-NNN.org' for backward compatibility:  if the
    ;; suffixed file is absent but the unsuffixed one exists (older
    ;; pre-migration analyses), use it instead.
    (let* ((source-file (buffer-file-name))
           (suffixed (tibetan-analysis-get-filepath seg-id source-file))
           (unsuffixed (tibetan-analysis-get-filepath seg-id))
           (filepath (cond
                      ((file-exists-p suffixed) suffixed)
                      ((file-exists-p unsuffixed) unsuffixed)
                      (t suffixed))))
      (unless (file-exists-p filepath)
        (error "No analysis file exists. Use C-c u A to create one first"))

      ;; 2026-04-24: switched from `yes-or-no-p' (typed full "yes") to
      ;; `y-or-n-p' (single key) — the old prompt caused accidental
      ;; declines when user hit RET without typing.  Regen is still
      ;; gated because it wipes the auto-analysis section, but the
      ;; friction is now one keystroke.
      (when (y-or-n-p "Re-analyze segment? (regen auto section + re-fire Claude; notes preserved) ")
        ;; Phase 6 of sanskrit-parallel-workflow (2026-04-27): pick up
        ;; parallel-mode rendering on `C-c u R'.  Source file is the
        ;; current buffer (the user invokes reanalyse from the source
        ;; doc); when it carries `#+SOURCE_MODE: parallel-sanskrit'
        ;; AND the segment has a `**** Sanskrit' sibling, the render
        ;; var fires the `** Sanskrit Source' renderer.  Wrapper
        ;; returns nil for non-parallel docs → today's behaviour
        ;; preserved.
        (let* ((source-file (buffer-file-name))
               (tibetan-analysis--sanskrit-text-for-render
                (and (fboundp 'tibetan-sanskrit-parallel-plist-for-segment-id)
                     (condition-case nil
                         (tibetan-sanskrit-parallel-plist-for-segment-id
                          source-file seg-id)
                       (error nil))))
               (auto-content (tibetan-analysis-generate-content
                              tibetan-text seg-id source-text)))
          (tibetan-analysis-regenerate-auto filepath tibetan-text auto-content)
          ;; Refresh the buffer if it's open
          (let ((buf (get-file-buffer filepath)))
            (when buf
              (with-current-buffer buf
                (revert-buffer t t))))
          ;; Request Claude translation asynchronously (never break on failure)
          (condition-case err
              (tibetan-analysis--request-claude-translation tibetan-text filepath)
            (error (message "Claude translation skipped: %s" (error-message-string err))))
          ;; Phase A.1.5 of multi-translator-parallel-reading (2026-04-30):
          ;; on explicit reanalyse (`C-c u R'), refresh the DM
          ;; translation unconditionally — the user asked for a re-
          ;; analysis, they want fresh translations from every engine.
          ;; Phase A.2 (2026-04-30): uses umbrella `fire-for-segment'
          ;; that handles both Tibetan and Sanskrit (parallel-mode).
          ;; FORCE = t:  this is the explicit-refresh path, so re-fire
          ;; even a populated section (fire-for-segment otherwise skips
          ;; populated sections — see the on-open auto-fire gating).
          (when (fboundp 'tibetan-dharmamitra-translation-fire-for-segment)
            (condition-case err
                (tibetan-dharmamitra-translation-fire-for-segment
                 tibetan-text filepath source-file seg-id t)
              (error (message "DharmaMitra translation skipped: %s"
                              (error-message-string err)))))
          ;; Phase 5 of two-language-parallel-analysis (§5.17, 2026-04-30):
          ;; on explicit reanalyse, also fire Sanskrit + (chained)
          ;; Combined Claude calls.  Bug fix 2026-05-02: this wire
          ;; was missed when §5.17 shipped (the dispatcher was wired
          ;; into headless `reanalyze-file' / `auto-analyze-document'
          ;; / sentence batch but not into the interactive `C-c u R'
          ;; entry point).  No-op when source isn't parallel-mode or
          ;; the segment's Sanskrit sibling is a placeholder /
          ;; continuation marker.
          (when (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls)
            (condition-case err
                (tibetan-analysis--fire-parallel-mode-claude-calls
                 tibetan-text source-file filepath)
              (error (message "Sanskrit/Combined fire skipped: %s"
                              (error-message-string err))))))))))

;; ============================================================================
;; PARAGRAPH-LEVEL COMMANDS (C-c p A / C-c p R)
;; ============================================================================
;;
;; Paragraphs are `** §N'-headed subtrees whose Tibetan content lives in a
;; `*** Tibetisch' (or `*** Tibetisch (B2)') child — the layout of
;; `Rgyan-comparative.org' for Gendün Chöpel's Klu sgrub dgongs rgyan.
;;
;; Analysis files live alongside `seg-*.org' in the document's `analysis/'
;; folder, named `par-NNN.org'.  The scaffold and auto-content generation
;; reuse the segment pipeline (`tibetan-analysis-generate-content') so
;; paragraph analysis is a true granularity extension of segment analysis.

;;;###autoload
(defun tibetan-open-paragraph-analysis ()
  "Open or create analysis for the current `** §N' paragraph.
Requires point to be anywhere inside a paragraph subtree whose
Tibetan text is carried by a `*** Tibetisch' (or
`*** Tibetisch (B2)') child.  If no analysis exists yet, generate
one via `tibetan-analysis-generate-content' (same pipeline as
`tibetan-open-segment-analysis'), write `par-NNN.org', and fire an
async Claude translation request.  The analysis file opens in a
right-side window."
  (interactive)
  (unless (tibetan-org-at-paragraph-p)
    (error "Not inside a `** §N' paragraph"))
  (let* ((par-id (tibetan-org-get-paragraph-id))
         (tibetan-text (tibetan-org-get-paragraph-text))
         (references (tibetan-org-get-paragraph-references))
         (source-file (buffer-file-name))
         (source-text (buffer-substring-no-properties
                       (point-min) (point-max))))
    (unless par-id
      (error "Could not determine paragraph id"))
    (unless (and tibetan-text (not (string-empty-p tibetan-text)))
      (error "Paragraph §%d has no `*** Tibetisch' child with content" par-id))

    (let* ((filepath (tibetan-analysis-get-paragraph-filepath par-id))
           (exists (file-exists-p filepath)))

      (if exists
          (progn
            (unless (tibetan-analysis-check-sync filepath tibetan-text)
              (message "WARNING: Source paragraph has changed since last analysis!"))
            (let ((buf (find-file-noselect filepath)))
              (with-current-buffer buf
                (tibetan-analysis-setup-faces)
                (goto-char (point-min)))
              (display-buffer-in-side-window buf
                                             '((side . right)
                                               (window-width . 0.5)))))
        ;; Create new file
        (let* ((auto-content (tibetan-analysis-generate-content
                              tibetan-text (format "§%d" par-id) source-text))
               (new-filepath (tibetan-analysis-create-paragraph-file
                              par-id tibetan-text source-file auto-content
                              references)))
          (message "Created paragraph analysis file: %s" new-filepath)
          (let ((buf (find-file-noselect new-filepath)))
            (with-current-buffer buf
              (tibetan-analysis-setup-faces)
              (goto-char (point-min)))
            (display-buffer-in-side-window buf
                                           '((side . right)
                                             (window-width . 0.5))))
          (condition-case err
              (tibetan-analysis--request-claude-translation tibetan-text new-filepath)
            (error (message "Claude translation skipped: %s"
                            (error-message-string err)))))))))

;;;###autoload
(defun tibetan-reanalyze-paragraph ()
  "Re-analyze the current paragraph, preserving user sections.
Regenerates only `* Auto-Analysis'; `* My Notes',
`* Working Translation', and `* Footnotes' stay intact, matching
the segment-level `tibetan-reanalyze-segment' contract."
  (interactive)
  (unless (tibetan-org-at-paragraph-p)
    (error "Not inside a `** §N' paragraph"))
  (let* ((par-id (tibetan-org-get-paragraph-id))
         (tibetan-text (tibetan-org-get-paragraph-text))
         (source-text (buffer-substring-no-properties
                       (point-min) (point-max))))
    (unless (and tibetan-text (not (string-empty-p tibetan-text)))
      (error "Paragraph §%d has no `*** Tibetisch' child with content" par-id))
    (let ((filepath (tibetan-analysis-get-paragraph-filepath par-id)))
      (unless (file-exists-p filepath)
        (error "No paragraph analysis file exists.  Use C-c p A first"))
      (when (yes-or-no-p
             "Re-analyze paragraph? (Auto section regenerated, notes preserved) ")
        (let ((auto-content (tibetan-analysis-generate-content
                             tibetan-text (format "§%d" par-id) source-text)))
          (tibetan-analysis-regenerate-auto filepath tibetan-text auto-content)
          (let ((buf (get-file-buffer filepath)))
            (when buf
              (with-current-buffer buf
                (revert-buffer t t))))
          (condition-case err
              (tibetan-analysis--request-claude-translation tibetan-text filepath)
            (error (message "Claude translation skipped: %s"
                            (error-message-string err)))))))))

;; ============================================================================
;; BATCH RE-ANALYSIS
;; ============================================================================
;;
;; Entry points:
;;   `tibetan-analysis-reanalyze-file'  — headless single-file reanalysis.
;;   `tibetan-analysis-batch-reanalyze' — interactive batch over a folder.
;;
;; Both preserve:
;;   * `* My Notes'            (via `tibetan-analysis-get-user-sections')
;;   * `* Working Translation'
;;   * `* Footnotes'
;;   * `*** Claude' translation (captured before regen, restored after)
;;
;; CAT Gloss / DharmaMitra / Reference Translations are regenerated from
;; scratch — they are derived artefacts.  Set `:re-request-claude t' to
;; force a fresh Claude request instead of preserving the stored one.

(defun tibetan-analysis--read-section-body (filepath section-name)
  "Return the body of `* SECTION-NAME' in FILEPATH (nil if missing).
The body excludes the heading line itself and any trailing blank line.
Works for top-level (* …) sections."
  (when (file-exists-p filepath)
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\* %s$" (regexp-quote section-name)) nil t)
        (forward-line 1)
        (let ((start (point))
              (end (save-excursion
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (string-trim (buffer-substring-no-properties start end)))))))


(defun tibetan-analysis--seg-id-from-filename (filepath)
  "Return the numeric segment id encoded in FILEPATH's basename, or nil."
  (let ((base (file-name-nondirectory filepath)))
    (when (string-match "seg-\\([0-9]+\\)" base)
      (string-to-number (match-string 1 base)))))

;; ----------------------------------------------------------------------------
;; Three-call dispatcher (Phase 5 of two-language-parallel-analysis, 2026-04-30)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--fire-parallel-claude-with-plist
    (tibetan-text sanskrit-plist source-file analysis-file)
  "Fire Sanskrit + Combined Claude calls with a PRE-RESOLVED plist.

SANSKRIT-PLIST must already be the walker output (or a
sentence-level aggregation thereof) for the relevant segment
or sentence.  The Tibetan call is fired SEPARATELY by the
caller; this helper only dispatches the parallel-mode-specific
Sanskrit call (and chains Combined off its callback).

Soft-coded: when the Sanskrit / Combined modules aren't
loaded, the call is a clean no-op.  When SANSKRIT-PLIST is
nil — which the walker returns for non-parallel sources, no-
sibling segments, OR placeholder bodies — also a no-op.

Returns t when the Sanskrit call was dispatched, nil otherwise."
  (when (and tibetan-text sanskrit-plist analysis-file
             (fboundp 'tibetan-analysis-sanskrit--request-translation))
    (condition-case err
        (let ((tib tibetan-text)
              (src source-file)
              (ana analysis-file)
              (skt sanskrit-plist))
          (tibetan-analysis-sanskrit--request-translation
           skt src ana
           (lambda (skt-parsed)
             ;; Sanskrit response landed.  Find the Tibetan
             ;; translation body (either preserved from a prior run
             ;; or freshly arrived from the parallel Tibetan call)
             ;; and fire Combined when both are present.  Phase 1.5
             ;; of layout-revision §5.18 (2026-05-04):  segment
             ;; layout's level-2 heading is now `** Translation' (was
             ;; `** Claude Translation').  Try the new name first;
             ;; fall back to the legacy name at level 2 (pre-rename
             ;; segment layout) and level 3 (sentence layout).
             (when (fboundp 'tibetan-analysis-combined--request-synthesis)
               (let* ((skt-trans
                       (plist-get skt-parsed :translation))
                      (tib-trans
                       (and (fboundp 'tibetan-analysis--read-claude-section-body)
                            (or
                             (tibetan-analysis--read-claude-section-body
                              ana "Translation" 2)
                             (tibetan-analysis--read-claude-section-body
                              ana "Claude Translation" 2)
                             (tibetan-analysis--read-claude-section-body
                              ana "Claude Translation" 3)))))
                 (when (and skt-trans tib-trans)
                   (condition-case e2
                       (tibetan-analysis-combined--request-synthesis
                        tib skt tib-trans skt-trans src ana)
                     (error
                      (message "Combined re-request failed for %s: %s"
                               (file-name-nondirectory ana)
                               (error-message-string e2)))))))))
          t)
      (error
       (message "Sanskrit re-request failed for %s: %s"
                (file-name-nondirectory analysis-file)
                (error-message-string err))
       nil))))

(defun tibetan-analysis--fire-parallel-mode-claude-calls
    (tibetan-text source-file analysis-file)
  "Fire the Sanskrit + Combined Claude calls for ANALYSIS-FILE
\(SEGMENT-level analysis file — looks up the segment walker
plist by seg-id parsed from the filename).

Thin wrapper around
`tibetan-analysis--fire-parallel-claude-with-plist'.  Returns
nil when the source isn't parallel-mode or the segment's
Sanskrit sibling is a placeholder."
  (when (and tibetan-text source-file analysis-file
             (fboundp 'tibetan-sanskrit-parallel-text-for-segment-id))
    (let* ((seg-id (tibetan-analysis--seg-id-from-filename analysis-file))
           (skt-plist (and seg-id
                           (condition-case nil
                               (tibetan-sanskrit-parallel-text-for-segment-id
                                source-file seg-id)
                             (error nil)))))
      (when skt-plist
        (tibetan-analysis--fire-parallel-claude-with-plist
         tibetan-text skt-plist source-file analysis-file)))))

(cl-defun tibetan-analysis-reanalyze-file
    (filepath &key source-file re-request-claude dry-run)
  "Re-run auto-analysis on an existing analysis FILEPATH.

Tibetan text is read from the file's own `* Tibetan Text' section;
segment id is parsed from the filename (`seg-NNN[-short].org').
SOURCE-FILE, when supplied, is the path of the original class file —
its buffer contents are scanned for inline 〔trans:N〕 blocks.

RE-REQUEST-CLAUDE controls Claude / DM request dispatch:
  · nil             — never re-fire;  preserve existing content.
  · t               — always re-fire (legacy behaviour).
  · `:missing-only' — fire only when the file's Claude
                       Translation / Vocabulary slots are missing
                       or placeholders (§5.22 follow-up, 2026-05-21
                       — `tibetan-analysis--should-fire-claude-p').
                       DharmaMitra is fired in parallel under the
                       same gate.  Files already populated are
                       skipped, saving API spend and class-prep
                       time when batch-reanalysing for layout
                       updates.

With DRY-RUN non-nil, return a plist describing what would happen
without touching the file.  Otherwise return a plist:
  (:file F :seg-id ID :ok BOOL :error STR :claude-preserved BOOL)."
  (let* ((seg-id (tibetan-analysis--seg-id-from-filename filepath))
         (tibetan-text (tibetan-analysis--read-section-body
                        filepath "Tibetan Text"))
         ;; Fall back to resolving the source-file from the analysis
         ;; file's own `#+SOURCE:' header when the caller didn't pass
         ;; one.  Bug fix 2026-05-03:  the auto-regen-on-Claude-arrival
         ;; path (`--insert-claude-sections' → reanalyze-file) calls
         ;; this with no `:source-file', and previously the resulting
         ;; nil source-file made `plist-for-segment-id' return nil for
         ;; `* Sanskrit Text' rendering, erasing the section that the
         ;; initial `C-c u R' regenerate-auto had emitted correctly.
         ;; Mirrors the sentence-level fallback in
         ;; `tibetan-sentence-reanalyze-file'.
         (source-file
          (or source-file
              (and (fboundp 'tibetan-analysis--source-file-from-analysis)
                   (tibetan-analysis--source-file-from-analysis filepath))))
         (source-text
          (when (and source-file (file-readable-p source-file))
            (condition-case nil
                (with-temp-buffer
                  (insert-file-contents source-file)
                  (buffer-substring-no-properties (point-min) (point-max)))
              (error nil))))
         ;; §5.26 (2026-05-26):  preserve existing Claude content
         ;; UNLESS the caller explicitly asked for a force-refresh.
         ;; Was `(not re-request-claude)' before §5.22-follow-up —
         ;; that treated `:missing-only' as truthy → preservation
         ;; SKIPPED → regenerate wiped the file → `:missing-only'
         ;; then fired Claude because the file LOOKED missing.
         ;; Asynchronous Claude queue rate-limits / writer-hooks /
         ;; user-quits-Emacs could swallow the responses, and the
         ;; populated content was already gone — net effect:
         ;; bulk silent data loss on a `:missing-only' batch run
         ;; over a fully-populated folder (exactly what hit
         ;; Carsten's Milarepa folder on 2026-05-24:  274 of 287
         ;; seg-NNN.org files lost their Claude content).
         ;;
         ;; Now:  preserve UNLESS re-request-claude is the symbol
         ;; `t' (force-refresh).  `nil' and `:missing-only' both
         ;; preserve.
         (existing-sections
          (and (not (eq re-request-claude t))
               (tibetan-analysis--read-claude-sections filepath)))
         (has-any-section
          (and existing-sections
               (or (plist-get existing-sections :translation)
                   (plist-get existing-sections :grammar)
                   (plist-get existing-sections :particles)
                   (plist-get existing-sections :concepts)
                   (plist-get existing-sections :vocabulary)))))
    (cond
     ((null seg-id)
      `(:file ,filepath :ok nil
              :error "Could not extract seg-id from filename"))
     ((or (null tibetan-text) (string-empty-p tibetan-text))
      `(:file ,filepath :seg-id ,seg-id :ok nil
              :error "No `* Tibetan Text' section or it is empty"))
     (dry-run
      `(:file ,filepath :seg-id ,seg-id :ok t :dry-run t
              :claude-preserved ,(and has-any-section t)))
     (t
      (condition-case err
          ;; Pass 6c: thread the preserved Claude Particles (if any)
          ;; through to the Grammar renderer via the dynamic var, so
          ;; the regenerated `*** Particles in This Segment' inherits
          ;; Claude's per-occurrence function-ID assignments and the
          ;; matching Portfolio snippets.  When no existing Claude
          ;; particles body is found, the dynamic binding is nil and
          ;; the renderer falls back to its compact parser-only list.
          ;;
          ;; B1+B2 (2026-04-24): also thread Claude Vocabulary via
          ;; `--claude-vocabulary-for-render' so the enriched-vocab-pairs
          ;; builder can override polysemous-token glosses where the
          ;; dictionary stack alone gives a wrong reading (e.g.
          ;; `<person>'-tagged proper-noun entries for `blo sbyangs').
          (let* (;; Resources / Custom vocab are located relative to the
                 ;; analysis file (`tibetan-find-resources-folder' walks
                 ;; ./ ../ ../../).  In headless batch reanalysis
                 ;; `generate-content' runs in the ambient `*scratch*'
                 ;; buffer (no `buffer-file-name'), so without binding the
                 ;; directory the finder found nothing and the curated
                 ;; Resources glosses were silently wiped corpus-wide
                 ;; (2026-06-03).  Bind `default-directory' to this file's
                 ;; folder so the finder's default-directory fallback
                 ;; resolves the document's Resources/ on every path.
                 (default-directory (file-name-directory
                                     (expand-file-name filepath)))
                 (claude-particles-raw
                  (and existing-sections
                       (plist-get existing-sections :particles)))
                 (claude-vocabulary-raw
                  (and existing-sections
                       (plist-get existing-sections :vocabulary)))
                 (tibetan-analysis--claude-particles-for-render
                  (and claude-particles-raw
                       (fboundp 'tibetan-analysis--parse-claude-particles)
                       (tibetan-analysis--parse-claude-particles
                        claude-particles-raw)))
                 (tibetan-analysis--claude-vocabulary-for-render
                  (and claude-vocabulary-raw
                       (fboundp 'tibetan-analysis--parse-claude-vocabulary)
                       (tibetan-analysis--parse-claude-vocabulary
                        claude-vocabulary-raw)))
                 ;; Phase 6 of sanskrit-parallel-workflow (2026-04-27):
                 ;; in parallel-Sanskrit mode, thread the segment's
                 ;; `**** Sanskrit' sibling through to the renderer
                 ;; via the dynamic var so `C-c u r' (batch reanalyse)
                 ;; populates `** Sanskrit Source' from the source
                 ;; on every regen pass.  Wrapper returns nil for
                 ;; non-parallel sources or when no source-file is
                 ;; supplied — today's behaviour preserved.
                 (tibetan-analysis--sanskrit-text-for-render
                  (and (fboundp 'tibetan-sanskrit-parallel-plist-for-segment-id)
                       (condition-case nil
                           (tibetan-sanskrit-parallel-plist-for-segment-id
                            source-file seg-id)
                         (error nil))))
                 (auto-content (tibetan-analysis-generate-content
                                tibetan-text seg-id source-text)))
            (tibetan-analysis-regenerate-auto filepath tibetan-text
                                              auto-content)
            (when has-any-section
              (tibetan-analysis--restore-claude-sections
               filepath existing-sections))
            ;; §5.22 follow-up (2026-05-21):  Claude / DM / parallel-mode
            ;; gates consult `tibetan-analysis--should-fire-claude-p',
            ;; which honours the `:missing-only' value of RE-REQUEST-
            ;; CLAUDE.  When set, files already carrying populated
            ;; Claude content are skipped — saving API spend on bulk
            ;; layout-update reanalyses.
            (let ((fire-p (tibetan-analysis--should-fire-claude-p
                           re-request-claude filepath)))
              (when fire-p
                (condition-case e2
                    (tibetan-analysis--request-claude-translation
                     tibetan-text filepath)
                  (error (message "Claude re-request failed for %s: %s"
                                  (file-name-nondirectory filepath)
                                  (error-message-string e2)))))
              ;; Phase A.3 of multi-translator-parallel-reading (2026-04-30):
              ;; when the caller explicitly asks for re-request (`C-u C-c u r'),
              ;; also refresh DharmaMitra translations.  Same gate as Claude
              ;; — `:missing-only' skips DM when Claude is being skipped too,
              ;; matching the user's "skip if exists" intent for batch ops.
              (when (and fire-p
                         (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
                (condition-case e3
                    ;; FORCE only on an explicit force-all re-request
                    ;; (RE-REQUEST-CLAUDE = t).  Under `:missing-only'
                    ;; (force nil) fire-for-segment self-gates and skips
                    ;; a populated DM section — honouring "renew only on
                    ;; explicit request".
                    (tibetan-dharmamitra-translation-fire-for-segment
                     tibetan-text filepath source-file seg-id
                     (eq re-request-claude t))
                  (error (message "DharmaMitra re-request failed for %s: %s"
                                  (file-name-nondirectory filepath)
                                  (error-message-string e3)))))
              ;; Phase 5 of two-language-parallel-analysis (2026-04-30):
              ;; when re-firing in parallel-mode, also fire Sanskrit +
              ;; (chained) Combined Claude calls via the dispatcher.
              ;; No-op when source isn't parallel-mode or the segment's
              ;; Sanskrit sibling is a placeholder.
              (when fire-p
                (tibetan-analysis--fire-parallel-mode-claude-calls
                 tibetan-text source-file filepath)))
            `(:file ,filepath :seg-id ,seg-id :ok t
                    :claude-preserved ,(and has-any-section t)))
        (error
         `(:file ,filepath :seg-id ,seg-id :ok nil
                 :error ,(error-message-string err))))))))

(defun tibetan-analysis--folder-analysis-files (folder)
  "Return the list of seg-NNN*.org files under FOLDER, sorted by seg-id."
  (let* ((all (directory-files folder t "\\`seg-[0-9]+.*\\.org\\'"))
         (ordered
          (sort (copy-sequence all)
                (lambda (a b)
                  (< (or (tibetan-analysis--seg-id-from-filename a) 0)
                     (or (tibetan-analysis--seg-id-from-filename b) 0))))))
    ordered))

;;;###autoload
(cl-defun tibetan-analysis-batch-reanalyze
    (&key folder source-file re-request-claude dry-run)
  "Re-run auto-analysis on every `seg-NNN*.org' file in FOLDER.

FOLDER defaults to the analysis folder of the current buffer (see
`tibetan-analysis-get-folder').  SOURCE-FILE defaults to the current
buffer's file.  With RE-REQUEST-CLAUDE non-nil, a fresh Claude request
is dispatched for each file; otherwise the stored `*** Claude'
translation is preserved verbatim.  With DRY-RUN non-nil, no files
are written — a report is returned without touching anything.

User sections (My Notes, Working Translation, Footnotes) and the
`*** Claude' translation are preserved on every file.

Returns a plist summary:
  (:folder F :total N :ok N-ok :failed N-bad :results RESULTS)."
  (interactive
   (list :folder (let ((d (or (and (buffer-file-name)
                                   (tibetan-analysis-get-folder))
                              default-directory)))
                   (read-directory-name "Analysis folder: " d d t))
         :source-file (buffer-file-name)
         :re-request-claude
         ;; §5.22 follow-up (2026-05-21):  three-way prompt.  Default
         ;; is `:missing-only' — fire Claude/DM only for files that
         ;; currently carry empty / placeholder Translation slots,
         ;; skip files already populated.  Matches Carsten's stated
         ;; expectation that batch reanalyse shouldn't re-fire when
         ;; translations exist;  explicit force is still available
         ;; via the second prompt branch.
         (let* ((c (read-char-choice
                    "Claude/DM:  [m] missing-only (skip populated)  [a] always re-fire  [n] never  ? "
                    '(?m ?a ?n))))
           (cond ((eq c ?a) t)
                 ((eq c ?n) nil)
                 (t         :missing-only)))
         :dry-run nil))
  (let* ((folder (or folder
                     (and (buffer-file-name)
                          (tibetan-analysis-get-folder))
                     default-directory))
         (files (tibetan-analysis--folder-analysis-files folder))
         (results '())
         (n (length files))
         (i 0)
         (ok 0))
    (unless files
      (user-error "No analysis files (seg-NNN*.org) in %s" folder))
    (dolist (f files)
      (cl-incf i)
      (message "[%d/%d] %s %s"
               i n (if dry-run "dry-run" "reanalyzing")
               (file-name-nondirectory f))
      (let ((r (tibetan-analysis-reanalyze-file
                f
                :source-file source-file
                :re-request-claude re-request-claude
                :dry-run dry-run)))
        (push r results)
        (when (plist-get r :ok) (cl-incf ok))))
    (let ((summary `(:folder ,folder
                     :total ,n
                     :ok ,ok
                     :failed ,(- n ok)
                     :dry-run ,(and dry-run t)
                     :results ,(nreverse results))))
      (message "Batch reanalysis: %d/%d ok (%d failed)%s"
               ok n (- n ok) (if dry-run " — dry run" ""))
      summary)))

(provide 'tibetan-analysis-persist)
;;; tibetan-analysis-persist.el ends here
