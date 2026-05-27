;;; tibetan-document-genres.el --- Canonical Tibetan-text genre taxonomy -*- lexical-binding: t -*-

;;; Commentary:
;; §5.27 Phase 3 (2026-05-27):  the canonical taxonomy of Tibetan
;; literary genres consumed by the document-preparation wizard and
;; written to source files as `#+TIBETAN_TEXT_TYPE: <key>'.
;;
;; Pre-§5.27 the taxonomy was a hand-typed 4-entry list embedded in
;; two completing-read call sites (`tibetan-doc-format.el',
;; `tibetan-doc-prep.el').  Phase 3 lifts it into a single defconst
;; with 12 traditional Tibetan genres plus 2 legacy keys
;; \(`classical', `madhyamaka-verse') so the wizard's genre selectbox,
;; the existing format dialogs, and the (later) Claude system-prompt
;; hint generator all read from the same source of truth.
;;
;; Each entry is a `(KEY . PLIST)' pair:
;;   :tibetan      — the Tibetan name (Wylie)
;;   :label        — display label for completing-read
;;   :description  — one-line plain-English description
;;   :claude-hint  — guidance line appended to Claude's system prompt
;;                   when this genre is the document's `text-type'

;;; Code:

(require 'cl-lib)

(defconst tibetan-document-genre-taxonomy
  '((rnam-thar
     :tibetan "rnam thar"
     :label "rNam thar — spiritual biography"
     :description "Hagiographical narrative of a saint or yogin's life; often mixes prose with embedded mgur."
     :claude-hint "Treat as classical prose with embedded verse.  Preserve honorific register; identify lineage references and toponyms; watch for direct-speech reporting frames.")

    (lam-rim
     :tibetan "lam rim"
     :label "Lam rim — graduated path"
     :description "Stages-of-the-path instructional literature (Tsongkhapa, Gampopa et al.)."
     :claude-hint "Doctrinal exposition.  Identify the lam-rim section (small/medium/great scope, the hetus, etc.) and cross-reference standard Indian sources (Atiśa, Maitreya, Asaṅga).")

    (mgur
     :tibetan "mgur"
     :label "mGur — yogin's song / spiritual verse"
     :description "Realisation-song verse (Milarepa, Phadampa, the Kagyü vajra-songs)."
     :claude-hint "Verse with 7- or 9-syllable lines.  Identify metrical breaks.  Often dialogic; flag refrain stanzas.  Vocabulary blends classical Tibetan and yogic dialect.")

    (mdo
     :tibetan "mdo"
     :label "mDo — sūtra (Buddha-word, prose)"
     :description "Canonical Buddha-word in Indian style (Kangyur)."
     :claude-hint "Highly formulaic register.  Identify nidāna openings, dharma-paryāya formulae, list conventions, honorific verbs.")

    (rgyud
     :tibetan "rgyud"
     :label "rGyud — tantra (Vajrayāna scripture)"
     :description "Vajrayāna canonical scripture, often using coded language."
     :claude-hint "Symbolic / coded language (sandhyābhāṣā).  Identify mantra phrases; flag deity names and ritual cycles.  Do NOT over-translate technical Vajrayāna terms — leave them in Sanskrit if standard.")

    (bstan-bcos
     :tibetan "bstan bcos"
     :label "bsTan bcos — śāstra / treatise"
     :description "Scholastic Indian-origin treatise (Madhyamaka, Yogācāra, Pramāṇa)."
     :claude-hint "Argumentative prose with definitions, syllogisms, citations.  Identify Sanskrit term-tags and translator's gloss conventions.  Cross-reference Tengyur lineage where relevant.")

    (snyan-ngag
     :tibetan "snyan ngag"
     :label "sNyan ngag — kāvya / belles-lettres"
     :description "Ornate poetic literature (Daṇḍin-derived;  Kāvyādarśa tradition)."
     :claude-hint "High-register diction with figures of speech (alaṅkāra).  Identify rhetorical devices and Sanskrit lexical loans;  meter and syllable-count matter.")

    (gtam-rgyud
     :tibetan "gtam rgyud"
     :label "gTam rgyud — narrative tale"
     :description "Folktale or didactic story prose."
     :claude-hint "Vernacular-tinged narrative prose.  Identify reported speech and character voices.  Often a moralising frame at start / end.")

    (grel-pa
     :tibetan "'grel pa"
     :label "'Grel pa — commentary"
     :description "Tibetan commentary on an Indian root-text."
     :claude-hint "Verse-citation + gloss alternation.  Identify the embedded root verses (often marked by quote-frames or shifts to verse meter).  Term-by-term exegesis follows.")

    (tika
     :tibetan "ṭīkā"
     :label "Ṭīkā — sub-commentary"
     :description "Sub-commentary on a Tibetan or Indian commentary."
     :claude-hint "Layered exegesis.  Track which level of the chain (root → 'grel pa → ṭīkā) each gloss is interpreting.  Often more discursive than 'grel pa.")

    (gter-ma
     :tibetan "gter ma"
     :label "gTer ma — revealed text"
     :description "Treasure-text revealed via tertön transmission (Nyingma)."
     :claude-hint "Often archaic register.  Identify treasure-grammar markers (gter shad U+0F14) and the discovered / concealed framing convention.")

    (gdams-ngag
     :tibetan "gdams ngag"
     :label "gDams ngag — pith instruction"
     :description "Practical / oral instruction in essence form."
     :claude-hint "Aphoristic prose, often imperative.  Identify the practice frame (preliminary / main / conclusion).  Strong oral register;  short, declarative sentences.")

    (classical
     :tibetan ""
     :label "Classical prose (fallback)"
     :description "Generic classical Tibetan prose with no specific genre signal."
     :claude-hint "Bialek-grammar default.  No genre-specific guidance — rely on per-segment analysis.")

    (madhyamaka-verse
     :tibetan ""
     :label "Madhyamaka verse (legacy)"
     :description "Madhyamaka philosophical verse (7-syllable meter, Gelug tradition)."
     :claude-hint "Verse meter:  preserve syllable-count in literal renderings.  Identify Nāgārjuna / Candrakīrti citation conventions and Madhyamaka technical terms (svabhāva, śūnyatā, pratītyasamutpāda)."))
  "Canonical genre taxonomy for `#+TIBETAN_TEXT_TYPE:'.

Alist of `(KEY . PLIST)' where PLIST carries `:tibetan',
`:label', `:description', `:claude-hint'.  KEY is the symbol
written verbatim into the source-file header.  The wizard's
completing-read presents `:label';  Claude prompt builders look
up `:claude-hint' for genre-specific guidance.")

;; ============================================================================
;; ACCESSORS
;; ============================================================================

(defun tibetan-document-genres-keys ()
  "Return the list of KEY symbols from the taxonomy, in order."
  (mapcar #'car tibetan-document-genre-taxonomy))

(defun tibetan-document-genres-labels ()
  "Return the list of `:label' strings from the taxonomy, in order."
  (mapcar (lambda (entry) (plist-get (cdr entry) :label))
          tibetan-document-genre-taxonomy))

(defun tibetan-document-genres--entry-for (key)
  "Return the PLIST for KEY (a symbol), or nil when unknown."
  (cdr (assq key tibetan-document-genre-taxonomy)))

(defun tibetan-document-genres-label-for (key)
  "Return the display label for KEY, or nil when unknown."
  (plist-get (tibetan-document-genres--entry-for key) :label))

(defun tibetan-document-genres-description-for (key)
  "Return the one-line description for KEY, or nil when unknown."
  (plist-get (tibetan-document-genres--entry-for key) :description))

(defun tibetan-document-genres-claude-hint-for (key)
  "Return the Claude system-prompt hint for KEY, or nil when unknown.
Wizard / prompt builders append the returned line to Claude's
system prompt when the document carries a known genre."
  (plist-get (tibetan-document-genres--entry-for key) :claude-hint))

(defun tibetan-document-genres-tibetan-for (key)
  "Return the Wylie/Tibetan name for KEY, or nil when unknown.
The legacy keys `classical' and `madhyamaka-verse' have no
Tibetan-name analogue and return the empty string."
  (plist-get (tibetan-document-genres--entry-for key) :tibetan))

;; ============================================================================
;; READER  --------------------------------------------------------------------
;; ============================================================================

(defun tibetan-document-genres-read (&optional default prompt)
  "Read a genre interactively via `completing-read'.

Returns the KEY symbol of the chosen genre.  DEFAULT (when
provided as a KEY symbol) preselects its label;  unrecognised
DEFAULT falls through to no preselection.  PROMPT defaults to
`\"Genre: \"'.

The completing-read input is a `:label' string — Carsten's vertico/
ivy/marginalia UI honours the alist mapping back to keys."
  (let* ((label->key (mapcar (lambda (entry)
                               (cons (plist-get (cdr entry) :label)
                                     (car entry)))
                             tibetan-document-genre-taxonomy))
         (labels (mapcar #'car label->key))
         (default-label (and default
                             (tibetan-document-genres-label-for default)))
         (choice (completing-read (or prompt "Genre: ")
                                  labels nil t nil nil default-label)))
    (cdr (assoc choice label->key))))

(provide 'tibetan-document-genres)
;;; tibetan-document-genres.el ends here
