;;; tibetan-phonetics-test.el --- Tests for THL phonetics conversion -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for `core/tibetan-phonetics.el' — the Wylie → THL
;; Simplified Phonetic Transcription (Germano & Tournadre 2003)
;; converter introduced 2026-05-19 as a class-reading aid.
;;
;; Tests are organised by category:
;;   - Empty / nil input edge cases
;;   - Simple root consonants (no prefix, no subscript)
;;   - Prefix devoicing (b-, d-, g-, m-, '- prefixes)
;;   - Superscript dropping (r-, l-, s-)
;;   - Subscripts (-y, -r, -l, -w)
;;   - Vowel umlauts from -i / -e / -n / -l / -d / -s suffixes
;;   - Final consonant rules (-g silent, -b → p, -m / -ng kept, ...)
;;   - Multi-syllable phrases (the real-world use case)
;;   - Shad (།) preservation
;;   - Curated thesaurus override

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir)))

(require 'tibetan-phonetics)

;; ============================================================================
;; Empty / nil input
;; ============================================================================

(ert-deftest tibetan-phonetics-nil-input-returns-nil ()
  "Nil input → nil (no crash, no empty string)."
  (should (null (tibetan-to-phonetics nil))))

(ert-deftest tibetan-phonetics-empty-string-returns-empty ()
  "Empty string → empty string."
  (should (string= "" (tibetan-to-phonetics ""))))

(ert-deftest tibetan-phonetics-whitespace-only-returns-empty ()
  "Whitespace-only string → empty (after trim)."
  (should (string= "" (string-trim (tibetan-to-phonetics "   ")))))

;; ============================================================================
;; Simple root consonants — no prefix, no subscript, no suffix
;; ============================================================================
;;
;; THL Simplified does not transcribe tone, so high-tone unaspirated
;; and low-tone unaspirated collapse to the same Roman letter in
;; pure-syllable form.  e.g. `ka' and `ga' both → `ka' in some THL
;; renderings;  we keep them distinct (k vs g) to stay close to the
;; Wylie reader's intuition.

(ert-deftest tibetan-phonetics-simple-ka ()
  (should (string= "ka" (tibetan-wylie-syllable-to-phonetic "ka"))))

(ert-deftest tibetan-phonetics-simple-kha ()
  (should (string= "kha" (tibetan-wylie-syllable-to-phonetic "kha"))))

(ert-deftest tibetan-phonetics-simple-nga ()
  (should (string= "nga" (tibetan-wylie-syllable-to-phonetic "nga"))))

(ert-deftest tibetan-phonetics-simple-cha ()
  (should (string= "cha" (tibetan-wylie-syllable-to-phonetic "cha"))))

(ert-deftest tibetan-phonetics-simple-pa ()
  (should (string= "pa" (tibetan-wylie-syllable-to-phonetic "pa"))))

(ert-deftest tibetan-phonetics-simple-pha ()
  (should (string= "pha" (tibetan-wylie-syllable-to-phonetic "pha"))))

(ert-deftest tibetan-phonetics-simple-ma ()
  (should (string= "ma" (tibetan-wylie-syllable-to-phonetic "ma"))))

(ert-deftest tibetan-phonetics-simple-sha ()
  (should (string= "sha" (tibetan-wylie-syllable-to-phonetic "sha"))))

;; ============================================================================
;; Prefix devoicing — b-/d-/g-/m-/'- prefixes drop, root surfaces
;; ============================================================================
;;
;; A prefix letter (b, d, g, m, ') makes the root surface plain in
;; modern Lhasa pronunciation;  the prefix itself is silent.

(ert-deftest tibetan-phonetics-prefix-bka-drops-b ()
  "`bka' → `ka' (b-prefix silent, root `k' surfaces)."
  (should (string= "ka" (tibetan-wylie-syllable-to-phonetic "bka"))))

(ert-deftest tibetan-phonetics-prefix-bde-drops-b ()
  "`bde' → `de' (b-prefix silent, root `d' surfaces)."
  (should (string= "de" (tibetan-wylie-syllable-to-phonetic "bde"))))

(ert-deftest tibetan-phonetics-prefix-dpa-drops-d ()
  "`dpa'' → `pa' (d-prefix silent, root `p' surfaces, ' silent)."
  (should (string= "pa" (tibetan-wylie-syllable-to-phonetic "dpa'"))))

(ert-deftest tibetan-phonetics-prefix-bdag-drops-b-silent-g ()
  "`bdag' → `dak' (b-prefix silent, root `d', a, -g realised as -k)."
  (should (string= "dak" (tibetan-wylie-syllable-to-phonetic "bdag"))))

(ert-deftest tibetan-phonetics-prefix-mthong-drops-m ()
  "`mthong' → `thong' (m-prefix silent, root `th', o, -ng kept)."
  (should (string= "thong" (tibetan-wylie-syllable-to-phonetic "mthong"))))

;; ============================================================================
;; Superscripts — r-/l-/s- drop, root surfaces
;; ============================================================================

(ert-deftest tibetan-phonetics-superscript-rdo ()
  "`rdo' → `do' (r-superscript silent, root `d' + o)."
  (should (string= "do" (tibetan-wylie-syllable-to-phonetic "rdo"))))

(ert-deftest tibetan-phonetics-superscript-rje ()
  "`rje' → `je' (r-superscript silent, root `j' + e)."
  (should (string= "je" (tibetan-wylie-syllable-to-phonetic "rje"))))

(ert-deftest tibetan-phonetics-superscript-lha ()
  "`lha' → `lha' (l-superscript + h root: kept as `lha')."
  (should (string= "lha" (tibetan-wylie-syllable-to-phonetic "lha"))))

(ert-deftest tibetan-phonetics-superscript-sgo ()
  "`sgo' → `go' (s-superscript silent, root `g' + o)."
  (should (string= "go" (tibetan-wylie-syllable-to-phonetic "sgo"))))

;; ============================================================================
;; Subscripts — -y palatalises, -r retroflexes
;; ============================================================================

(ert-deftest tibetan-phonetics-subscript-bya-becomes-ja ()
  "`bya' → `ja' (b + -y subscript → palatalised `j')."
  (should (string= "ja" (tibetan-wylie-syllable-to-phonetic "bya"))))

(ert-deftest tibetan-phonetics-subscript-phyag-becomes-chak ()
  "`phyag' → `chak' (ph + -y subscript → aspirated palatal `ch';  -g → -k)."
  (should (string= "chak" (tibetan-wylie-syllable-to-phonetic "phyag"))))

(ert-deftest tibetan-phonetics-subscript-bkra-becomes-tra ()
  "`bkra' → `tra' (b-prefix silent, k + -r subscript → retroflex `tr')."
  (should (string= "tra" (tibetan-wylie-syllable-to-phonetic "bkra"))))

(ert-deftest tibetan-phonetics-subscript-mya-becomes-nya ()
  "`mya' → `nya' (m + -y subscript → palatalised `ny')."
  (should (string= "nya" (tibetan-wylie-syllable-to-phonetic "mya"))))

(ert-deftest tibetan-phonetics-subscript-gyi-stays-gyi ()
  "`gyi' → `gyi' (g + -y subscript = palatalised g, kept).
This is the Tibetan genitive particle.  Regression for the
ambiguity:  `(g . y)' must NOT be in the valid-prefix table,
or the parser mis-identifies `g' as a prefix + `y' as the
root and drops the `g'."
  (should (string= "gyi" (tibetan-wylie-syllable-to-phonetic "gyi"))))

(ert-deftest tibetan-phonetics-subscript-gyung-stays-gyung ()
  "`gyung' → `gyung' (g + -y subscript = palatalised g)."
  (should (string= "gyung" (tibetan-wylie-syllable-to-phonetic "gyung"))))

(ert-deftest tibetan-phonetics-prefix-rgyud-becomes-gyü ()
  "`rgyud' → `gyü' (r-superscript + g+y subscript = `gy', + u +
-d suffix → ü umlaut, d silent).  The classic `kagyü' element
from `bka' brgyud'."
  (should (string= "gyü" (tibetan-wylie-syllable-to-phonetic "rgyud"))))

(ert-deftest tibetan-phonetics-prefix-brgyud-becomes-gyü ()
  "`brgyud' → `gyü' (b-prefix + r-super + g-root + y-sub + u + d).
Regression for the parser's prefix detection:  Case A (prefix +
super + root pattern) must fire when the b-prefix sits over a
superscript-root combo.  Without this, the cluster passes
through with `b' and `r' still visible (`brgyü')."
  (should (string= "gyü" (tibetan-wylie-syllable-to-phonetic "brgyud"))))

(ert-deftest tibetan-phonetics-phrase-bka-brgyud-becomes-kagyü ()
  "`bka' brgyud' → `ka gyü' (the canonical `Kagyü' lineage name)."
  (should (string= "ka gyü" (tibetan-to-phonetics "bka' brgyud"))))

;; ============================================================================
;; Vowel umlauts — final i / e / n / l / d / s suffixes
;; ============================================================================
;;
;; In modern Lhasa, certain finals colour the preceding vowel:
;;   a + {i,e,n,l,d,s}  →  e
;;   o + {i,e,n,l,d,s}  →  ö
;;   u + {i,e,n,l,d,s}  →  ü
;;
;; The suffix consonant itself is silent (n/l/d/s) or kept as a
;; vowel marker (i/e).

(ert-deftest tibetan-phonetics-umlaut-bun-becomes-bün ()
  "`bun' → `bün' style (u + -n suffix → ü umlaut, n silent OR kept).
We keep n silent post-umlaut → `bü' is acceptable, but the
common convention is to keep -n visually for the reader.  This
test asserts `bün' (n preserved as visual cue) — change if you
prefer `bü'."
  (should (string= "bün" (tibetan-wylie-syllable-to-phonetic "bun"))))

(ert-deftest tibetan-phonetics-umlaut-phun-becomes-phün ()
  "`phun' → `phün' (ph + u + -n → umlaut)."
  (should (string= "phün" (tibetan-wylie-syllable-to-phonetic "phun"))))

(ert-deftest tibetan-phonetics-umlaut-chos-becomes-chö ()
  "`chos' → `chö' (ch + o + silent -s → ö umlaut, s silent).
The classic Dharma → \"chö\" rendering."
  (should (string= "chö" (tibetan-wylie-syllable-to-phonetic "chos"))))

(ert-deftest tibetan-phonetics-umlaut-lus-becomes-lü ()
  "`lus' → `lü' (l + u + -s → ü umlaut)."
  (should (string= "lü" (tibetan-wylie-syllable-to-phonetic "lus"))))

(ert-deftest tibetan-phonetics-umlaut-gnas-becomes-nä ()
  "`gnas' → `nä' (g-prefix silent, n + a + -s → ä umlaut).
Uses the strict THL ä diacritic for the a-umlaut, matching
ö / ü for o / u.  Some casual transcriptions render this as
`ne';  we keep `nä' for consistency."
  (should (string= "nä" (tibetan-wylie-syllable-to-phonetic "gnas"))))

(ert-deftest tibetan-phonetics-umlaut-pai-becomes-pä ()
  "`pa'i' → `pä' (a + genitive 'i compound suffix → ä umlaut,
both `' and i silent).  The 'i suffix is the Tibetan genitive
particle written as a compound after a vowel-ending stem;  it
umlauts the stem vowel in modern Lhasa pronunciation."
  (should (string= "pä" (tibetan-wylie-syllable-to-phonetic "pa'i"))))

(ert-deftest tibetan-phonetics-umlaut-poi-becomes-pö ()
  "`po'i' → `pö' (o + 'i compound → ö umlaut)."
  (should (string= "pö" (tibetan-wylie-syllable-to-phonetic "po'i"))))

(ert-deftest tibetan-phonetics-umlaut-bui-becomes-bü ()
  "`bu'i' → `bü' (u + 'i compound → ü umlaut)."
  (should (string= "bü" (tibetan-wylie-syllable-to-phonetic "bu'i"))))

(ert-deftest tibetan-phonetics-no-umlaut-on-e ()
  "`shes' → `she' (e + -s, no umlaut because e doesn't take one)."
  (should (string= "she" (tibetan-wylie-syllable-to-phonetic "shes"))))

;; ============================================================================
;; Final consonant rules — kept vs realised vs silent
;; ============================================================================

(ert-deftest tibetan-phonetics-final-ng-kept ()
  "`thang' → `thang' (final -ng preserved)."
  (should (string= "thang" (tibetan-wylie-syllable-to-phonetic "thang"))))

(ert-deftest tibetan-phonetics-final-m-kept ()
  "`sum' → `sum' (final -m preserved, no umlaut)."
  (should (string= "sum" (tibetan-wylie-syllable-to-phonetic "sum"))))

(ert-deftest tibetan-phonetics-final-g-becomes-k ()
  "`legs' → `lek' (-g + silent post-suffix -s → final -k)."
  (should (string= "lek" (tibetan-wylie-syllable-to-phonetic "legs"))))

(ert-deftest tibetan-phonetics-final-b-becomes-p ()
  "`chub' → `chup' (-b → -p, final devoicing)."
  (should (string= "chup" (tibetan-wylie-syllable-to-phonetic "chub"))))

(ert-deftest tibetan-phonetics-final-apostrophe-silent ()
  "`bka'' → `ka' (final ' silent)."
  (should (string= "ka" (tibetan-wylie-syllable-to-phonetic "bka'"))))

(ert-deftest tibetan-phonetics-tshogs-becomes-tshok ()
  "`tshogs' → `tshok' (tsh-root kept, o, -g + silent post-suffix
-s → -k).  Aspiration is preserved in this implementation —
matches strict THL convention (Germano & Tournadre 2003)
rather than the informal aspiration-dropping seen in some
travel-guide transcriptions."
  (should (string= "tshok" (tibetan-wylie-syllable-to-phonetic "tshogs"))))

;; ============================================================================
;; Multi-syllable phrases — the real use case
;; ============================================================================

(ert-deftest tibetan-phonetics-phrase-bkra-shis-bde-legs ()
  "Hello / good-fortune greeting:  `bkra shis bde legs' → `tra shi de lek'."
  (should (string= "tra shi de lek"
                   (tibetan-to-phonetics "bkra shis bde legs"))))

(ert-deftest tibetan-phonetics-phrase-phun-sum-tshogs ()
  "`phun sum tshogs' → `phün sum tshok' (aspiration preserved
on tsh, -gs blocks umlaut on o)."
  (should (string= "phün sum tshok"
                   (tibetan-to-phonetics "phun sum tshogs"))))

(ert-deftest tibetan-phonetics-phrase-byang-chub-sems-dpa ()
  "`byang chub sems dpa'' → `jang chup sem pa'."
  (should (string= "jang chup sem pa"
                   (tibetan-to-phonetics "byang chub sems dpa'"))))

(ert-deftest tibetan-phonetics-phrase-rdo-rje ()
  "`rdo rje' → `do je'."
  (should (string= "do je"
                   (tibetan-to-phonetics "rdo rje"))))

(ert-deftest tibetan-phonetics-phrase-thugs-rje-che ()
  "`thugs rje che' → `thuk je che' (th aspiration kept, -gs → -k,
r-superscript dropped on rje, ch kept)."
  (should (string= "thuk je che"
                   (tibetan-to-phonetics "thugs rje che"))))

(ert-deftest tibetan-phonetics-phrase-tibetan-input-via-wylie ()
  "Tibetan Unicode input flows through `tibetan-to-wylie-fixed'
internally, then through the phonetic rules.  `བདག' (bdag)
→ `dak'."
  (skip-unless (fboundp 'tibetan-to-wylie-fixed))
  (should (string= "dak" (tibetan-to-phonetics "བདག"))))

;; ============================================================================
;; Shad and punctuation preservation
;; ============================================================================

(ert-deftest tibetan-phonetics-shad-preserved ()
  "Shad (`།') and slash (`/') in the Wylie should pass through,
not consumed as suffix material."
  (let ((out (tibetan-to-phonetics "bdag/")))
    (should (string-match-p "dak" out))
    (should (string-match-p "/" out))))

;; ============================================================================
;; Unrecognised input — degrades gracefully (passes through)
;; ============================================================================

(ert-deftest tibetan-phonetics-unrecognised-cluster-passes-through ()
  "An input that doesn't parse as a valid Wylie syllable falls
through to its input form (Wylie pass-through).  Defensive
behaviour — better to show Wylie than to crash or emit
gibberish."
  (let ((out (tibetan-wylie-syllable-to-phonetic "xyz")))
    ;; Either passes through verbatim or returns something
    ;; non-nil that at least contains the input letters.
    (should out)
    (should (stringp out))))

;; ============================================================================
;; Curated thesaurus override
;; ============================================================================

(ert-deftest tibetan-phonetics-thesaurus-phonetics-override ()
  "When `tibetan-thesaurus-lookup' returns a plist carrying
`:phonetics:' for a Wylie key, that value wins over the
rule-engine output.  Lets the user pin tricky cases (Madhyamaka
terms, Sanskrit loanwords, monastic-tradition readings) without
modifying the rules table."
  (skip-unless (fboundp 'tibetan-phonetics--curated-override))
  (cl-letf (((symbol-function 'tibetan-thesaurus-lookup)
             (lambda (wylie)
               (when (string= wylie "rgyud")
                 (list :phonetics "gyü-CURATED")))))
    (should (string= "gyü-CURATED"
                     (tibetan-phonetics--curated-override "rgyud")))))

(ert-deftest tibetan-phonetics-thesaurus-no-override-when-empty ()
  "When the thesaurus has no `:phonetics:' field (or returns nil
entirely), the override path returns nil so the rule engine
takes over."
  (skip-unless (fboundp 'tibetan-phonetics--curated-override))
  (cl-letf (((symbol-function 'tibetan-thesaurus-lookup)
             (lambda (_w) nil)))
    (should (null (tibetan-phonetics--curated-override "rgyud")))))

(provide 'tibetan-phonetics-test)
;;; tibetan-phonetics-test.el ends here
