;;; tibetan-bialek-textbook-refs.el --- Bialek 2022 published-textbook section refs -*- lexical-binding: t -*-

;;; Commentary:
;; §5.21 Commit 4/7 (Mid-class Cleanup, 2026-05-20):
;;
;; Maps Bialek-analyser particle-type strings (the ALL-CAPS `nth 2'
;; of a `tibetan-analyze-grammar-bialek' tuple) to the canonical
;; section reference in Joanna Bialek's published textbook,
;;
;;     Bialek, Joanna.  2022.  A Textbook of Classical Tibetan.
;;     London / New York:  Routledge.
;;
;; Carsten's hand-written Portfolio zettel — already exposed on
;; each bialek tuple via the `nth 6' Portfolio field — sometimes
;; uses different section numbering than the published textbook
;; (the Portfolio was begun before the textbook's final
;; numbering crystallised, and is organised functionally rather
;; than by Bialek's chapter sequence).  The merged `*** Particles'
;; section's bullet bracket emits BOTH refs so the reader can
;; cross-check the textbook AND the Portfolio:
;;
;;     - དང [dang] · COMITATIVE (COM)
;;         [Bialek 2022 §1.7 (Comitative); Portfolio §1.9]
;;
;; Either side may be absent → bracket falls back gracefully.
;;
;; Bialek 2022 chapter structure (for context when extending the
;; table):
;;   Chapter 1 — Case suffixes (§1.1 Genitive … §1.10 Topic).
;;   Chapter 2 — Converbs / verb suffixes (§2.1 Nominaliser pa,
;;               §2.4 V+te, §2.5 V+na, §2.6 V+pas, §2.7 V+kyang,
;;               §2.10 V+cing, §2.11 V+nas, etc.).
;;   Chapter 3 — Sentence finals / declarative particles
;;               (§3.1 V+'o final-declarative).
;;
;; The keys in `tibetan-bialek-textbook-refs' are the LITERAL
;; ALL-CAPS strings the analyser emits (`GENITIVE (GEN)' etc.),
;; not symbolic identifiers.  This means a renderer can do a
;; direct `assoc' lookup on `(nth 2 bialek-tuple)' without any
;; intermediate translation step.

;;; Code:

(defconst tibetan-bialek-textbook-refs
  '(;; ============ CHAPTER 1: CASE SUFFIXES ============
    ("GENITIVE (GEN)"
     . "Bialek 2022 §1.1 (Genitive)")
    ("ERGATIVE/INSTRUMENTAL (ERG/INST)"
     . "Bialek 2022 §1.2 (Ergative/Instrumental)")
    ("DATIVE (DAT)"
     . "Bialek 2022 §1.4 (Dative)")
    ("TERMINATIVE (ALL)"
     . "Bialek 2022 §1.6 (Terminative)")
    ("COMITATIVE (COM)"
     . "Bialek 2022 §1.7 (Comitative)")
    ("ELATIVE/ABLATIVE (ABL)"
     . "Bialek 2022 §1.8 (Ablative)")
    ("LOCATIVE (LOC)"
     . "Bialek 2022 §1.9 (Locative)")
    ("TOPIC (TOP)"
     . "Bialek 2022 §1.10 (Topic)")
    ("LOCATIVE+CONCESSIVE (LOC+CONC)"
     . "Bialek 2022 §1.9+§2.7 (Locative + Concessive)")

    ;; ============ CHAPTER 2: CONVERBS / VERB SUFFIXES ============
    ("CONVERBIAL: ABLATIVE CONVERB"
     . "Bialek 2022 §2.11 (V+nas)")
    ("CONVERBIAL: COORDINATIVE CONVERB"
     . "Bialek 2022 §2.4 (V+te/V+ste)")
    ("CONVERBIAL: SIMULTANEOUS CONVERB"
     . "Bialek 2022 §2.10 (V+cing)")
    ("CONVERBIAL: CAUSAL CONVERB"
     . "Bialek 2022 §2.6 (V+pas)")
    ("CONVERBIAL: CONDITIONAL CONVERB"
     . "Bialek 2022 §2.5 (V+na)")
    ("CONVERBIAL: CONCESSIVE (RUNG)"
     . "Bialek 2022 §2.7 (V+rung)")
    ("CONCESSIVE PARTICLE"
     . "Bialek 2022 §2.7 (V+kyang)")
    ("CONVERBIAL: IMMEDIATE SEQUENCE"
     . "Bialek 2022 §2.8 (V+pa dang)")
    ("CONVERBIAL: TEMPORAL/CIRCUMSTANTIAL"
     . "Bialek 2022 §2.9 (V+pa la)"))
  "Alist mapping `tibetan-analyze-grammar-bialek' type strings to
canonical Bialek 2022 published-textbook section references.

Keys are the LITERAL ALL-CAPS strings the analyser emits in the
`nth 2' position of a particle tuple (`GENITIVE (GEN)',
`ERGATIVE/INSTRUMENTAL (ERG/INST)', `CONVERBIAL: ABLATIVE
CONVERB', …).  Values are canonical reference strings of the
shape `Bialek 2022 §X.Y (Title)' or `Bialek 2022 §X.Y (V+xxx)'
that the `*** Particles' renderer drops verbatim into the bullet
bracket.

Extend this table when the bialek analyser starts emitting a
type not yet covered — the renderer falls back to Portfolio-only
when the lookup misses, so a missing entry degrades gracefully
rather than crashing.")

(defun tibetan-bialek-textbook-ref (type)
  "Return the canonical `Bialek 2022 §X.Y (Title)' reference for
TYPE, or nil when TYPE is not in the table.

TYPE is the ALL-CAPS string from `nth 2' of a
`tibetan-analyze-grammar-bialek' tuple (e.g. `GENITIVE (GEN)' or
`CONVERBIAL: ABLATIVE CONVERB').  Used by the merged `***
Particles' bullet renderer in
`tibetan-analysis--render-particle-bullets' to emit a
`[Bialek 2022 §X.Y …; Portfolio §A.B]' bracket alongside each
particle.

Returns nil rather than signalling when TYPE is unknown — the
renderer's bracket-building logic treats nil as `Bialek side
absent, emit Portfolio side only'."
  (when (stringp type)
    (cdr (assoc type tibetan-bialek-textbook-refs))))

(provide 'tibetan-bialek-textbook-refs)
;;; tibetan-bialek-textbook-refs.el ends here
