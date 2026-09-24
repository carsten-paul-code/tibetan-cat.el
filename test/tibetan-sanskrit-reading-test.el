;;; tibetan-sanskrit-reading-test.el --- Tests for the Sanskrit token provider -*- lexical-binding: t -*-

;;; Commentary:
;; Sanskrit-Kaskade B3 (2026-09-24).  Pure tests: token plists and
;; parsed word-analysis bodies are hand-built; no dictionaries, no
;; disk, no network.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-sanskrit-reading)

(defconst tibetan-sanskrit-reading-test--wa-md
  "### Segment 153
dharmāṇām śūnyatā svabhāvaḥ
- dharmāṇām — dharma; N.GEN.PL
- śūnyatā — śūnyatā; N.NOM.SG
- svabhāvaḥ — svabhāva; N.NOM.SG

### Segment 154
na svataḥ
- na — na; IND
- svataḥ — svatas; IND"
  "Raw markdown Word-Analysis body (pre-conversion form).")

(defconst tibetan-sanskrit-reading-test--wa-org
  (replace-regexp-in-string "^### " "*** "
                            tibetan-sanskrit-reading-test--wa-md)
  "The same body in the landed org form (`*** Segment N').")

(ert-deftest tibetan-sanskrit-reading-surface-tokenize-strips-danda ()
  "Whitespace split; daṇḍas (Unicode und romanisiert) und
anhängende Interpunktion fallen weg."
  (should (equal '("na" "svato" "nāpi" "parataḥ")
                 (tibetan-sanskrit-reading--tokenize-surface
                  "na svato nāpi parataḥ ।")))
  (should (equal '("dharmāṇāṃ" "śūnyatā")
                 (tibetan-sanskrit-reading--tokenize-surface
                  "dharmāṇāṃ śūnyatā ||")))
  (should (equal '("kutaḥ")
                 (tibetan-sanskrit-reading--tokenize-surface "kutaḥ॥")))
  (should-not (tibetan-sanskrit-reading--tokenize-surface "। ॥"))
  (should-not (tibetan-sanskrit-reading--tokenize-surface nil)))

(ert-deftest tibetan-sanskrit-reading-never-touches-tibetan-lookup ()
  "Poison-Lock: der Sanskrit-Provider darf NIE die tibetische
Tokenisierung oder die Wylie-gekeyten Wörterbücher berühren —
kurze IAST-Wörter (na/ca/ma/sa) träfen dort tibetische Einträge."
  (cl-letf (((symbol-function 'tibetan-extract-vocabulary)
             (lambda (&rest _) (error "POISON: tibetan tokenizer")))
            ((symbol-function 'tibetan-lookup-word)
             (lambda (&rest _) (error "POISON: wylie dictionary"))))
    (should (tibetan-sanskrit-reading-unit-tokens "na ca sa mā"))
    (should (tibetan-sanskrit-reading-unit-tokens
             "na ca"
             '(:pada ("na" "ca") :morph (("na" . "IND")))))
    (should (tibetan-sanskrit-reading-unit-line "na ca sa mā"))))

(ert-deftest tibetan-sanskrit-reading-parse-word-analysis-md-form ()
  "Der Parser liest die rohe `### Segment N'-Form: Zeile 1 =
Padapāṭha, Bullets = Morph-Labels."
  (let ((parsed (tibetan-sanskrit-reading-parse-word-analysis
                 tibetan-sanskrit-reading-test--wa-md)))
    (should (equal '(153 154) (mapcar #'car parsed)))
    (let ((s153 (cdr (assq 153 parsed))))
      (should (equal '("dharmāṇām" "śūnyatā" "svabhāvaḥ")
                     (plist-get s153 :pada)))
      (should (equal "N.GEN.PL"
                     (cdr (assoc "dharmāṇām"
                                 (plist-get s153 :morph))))))
    (let ((s154 (cdr (assq 154 parsed))))
      (should (equal '("na" "svataḥ") (plist-get s154 :pada)))
      (should (equal "IND"
                     (cdr (assoc "na" (plist-get s154 :morph))))))))

(ert-deftest tibetan-sanskrit-reading-parse-word-analysis-org-form ()
  "Dual-Format (R5-Lektion): die gelandete `*** Segment N'-Form
parst identisch."
  (should (equal (tibetan-sanskrit-reading-parse-word-analysis
                  tibetan-sanskrit-reading-test--wa-md)
                 (tibetan-sanskrit-reading-parse-word-analysis
                  tibetan-sanskrit-reading-test--wa-org)))
  (should-not (tibetan-sanskrit-reading-parse-word-analysis nil))
  (should-not (tibetan-sanskrit-reading-parse-word-analysis "")))

(ert-deftest tibetan-sanskrit-reading-tokens-carry-morph ()
  "Mit Word-Analysis: Tokens = Padapāṭha-Wörter mit :morph; :wylie
= :tibetan = IAST-Wort (der Claude-Vocabulary-Key); :kind word."
  (let* ((wa '(:pada ("dharmāṇām" "śūnyatā")
               :morph (("dharmāṇām" . "N.GEN.PL")
                       ("śūnyatā" . "N.NOM.SG"))))
         (toks (tibetan-sanskrit-reading-unit-tokens
                "dharmāṇāṃ śūnyatā" wa)))
    (should (= 2 (length toks)))
    (should (equal "dharmāṇām" (plist-get (car toks) :wylie)))
    (should (equal "dharmāṇām" (plist-get (car toks) :tibetan)))
    (should (eq 'word (plist-get (car toks) :kind)))
    (should (equal "N.GEN.PL" (plist-get (car toks) :morph)))
    (should (equal "N.NOM.SG" (plist-get (cadr toks) :morph)))))

(ert-deftest tibetan-sanskrit-reading-tokens-degrade-to-surface ()
  "Ohne Word-Analysis: Oberflächen-Tokens (degradierte
Pre-Claude-Form) — :morph nil, :meaning nil."
  (let ((toks (tibetan-sanskrit-reading-unit-tokens
               "dharmāṇāṃ śūnyatā ।")))
    (should (= 2 (length toks)))
    (should (equal "dharmāṇāṃ" (plist-get (car toks) :wylie)))
    (should-not (plist-get (car toks) :morph))
    (should-not (plist-get (car toks) :meaning))))

(ert-deftest tibetan-sanskrit-reading-tokens-resolve-via-dynamic-var ()
  "Ohne explizites WORD-ANALYSIS löst der Provider über die
textkeyed Dynamik auf (string-trim-Schlüssel)."
  (let ((tibetan-sanskrit-reading--word-analysis
         '(("dharmāṇāṃ śūnyatā" . (:pada ("dharmāṇām" "śūnyatā")
                                   :morph (("śūnyatā" . "N.NOM.SG")))))))
    (let ((toks (tibetan-sanskrit-reading-unit-tokens
                 "  dharmāṇāṃ śūnyatā \n")))
      (should (equal '("dharmāṇām" "śūnyatā")
                     (mapcar (lambda (tk) (plist-get tk :wylie)) toks)))
      (should (equal "N.NOM.SG" (plist-get (cadr toks) :morph))))))

(ert-deftest tibetan-sanskrit-reading-unit-line-degrades ()
  "Ohne Analysis: die reine Oberflächenzeile, kein ` /'-Suffix."
  (cl-letf (((symbol-function 'tibetan-reading--gloss)
             (lambda (_tok) nil)))
    (should (equal "na svato nāpi parataḥ"
                   (tibetan-sanskrit-reading-unit-line
                    "na svato nāpi parataḥ ।")))))

(ert-deftest tibetan-sanskrit-reading-unit-line-renders-claude-gloss ()
  "Mit Analysis + Glossen-Tier: `wort [gloss]' je Wort mit Glosse."
  (cl-letf (((symbol-function 'tibetan-reading--gloss)
             (lambda (tok)
               (cdr (assoc (plist-get tok :wylie)
                           '(("dharmāṇām" . "der Gegebenheiten")
                             ("śūnyatā" . "Leerheit")))))))
    (should (equal "dharmāṇām [der Gegebenheiten] śūnyatā [Leerheit]"
                   (tibetan-sanskrit-reading-unit-line
                    "dharmāṇāṃ śūnyatā"
                    '(:pada ("dharmāṇām" "śūnyatā") :morph nil))))))

(ert-deftest tibetan-sanskrit-reading-parse-strips-pada-label ()
  "C6b (sa-Dry-Run, 2026-09-24): Claude prefixt die Padapāṭha-Zeile
gern mit einem Label (`**Padapāṭha:**' o.ä.) — das Label darf NIE
als erstes Wort in die Tabelle laufen."
  (let ((parsed (tibetan-sanskrit-reading-parse-word-analysis
                 "### Segment 1
**Padapāṭha:** yaḥ pratītya-samutpādaḥ śūnyatām
- yaḥ — yad; PRON.NOM.SG.M
- śūnyatām — śūnyatā; N.ACC.SG.F")))
    (should (equal '("yaḥ" "pratītya-samutpādaḥ" "śūnyatām")
                   (plist-get (cdr (assq 1 parsed)) :pada))))
  ;; Auch die Klartext-Form `Padapāṭha:'.
  (let ((parsed (tibetan-sanskrit-reading-parse-word-analysis
                 "### Segment 2
Padapāṭha: sā prajñaptiḥ
- sā — tad; PRON.NOM.SG.F")))
    (should (equal '("sā" "prajñaptiḥ")
                   (plist-get (cdr (assq 2 parsed)) :pada)))))

(ert-deftest tibetan-sanskrit-reading-parse-compacts-morph ()
  "C6b: Morph-Labels mit Klammer-Kommentar (`PRON.NOM.SG.M
\(relative pronoun)') werden aufs kompakte Label gekürzt — der
Kommentar sprengte die Tabellenspalten (Dry-Run: 2er-Bänder)."
  (let ((parsed (tibetan-sanskrit-reading-parse-word-analysis
                 "### Segment 1
yaḥ pracakṣmahe
- yaḥ — yad; PRON.NOM.SG.M (relative pronoun)
- pracakṣmahe — pra-√cakṣ; V.PRS.1PL (ātmanepada, \"we call\")")))
    (let ((morph (plist-get (cdr (assq 1 parsed)) :morph)))
      (should (equal "PRON.NOM.SG.M" (cdr (assoc "yaḥ" morph))))
      (should (equal "V.PRS.1PL" (cdr (assoc "pracakṣmahe" morph)))))))

(provide 'tibetan-sanskrit-reading-test)

;;; tibetan-sanskrit-reading-test.el ends here
