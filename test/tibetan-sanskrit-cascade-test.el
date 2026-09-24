;;; tibetan-sanskrit-cascade-test.el --- Sanskrit im Kaskaden-Layout -*- lexical-binding: t -*-

;;; Commentary:
;; Sanskrit-Kaskade Teil C (2026-09-24).  Scaffold-/Regenerate-/
;; Landungs-Tests für `#+SOURCE_LANG: sa'-Dokumente.  Fixtures in
;; Tempdirs; Fires gestubbt; kein Netz.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (dolist (d '("../core" "../analysis" "../persist" "../data" "../config"
               "../workspace" "../philology" "../doc-prep"))
    (add-to-list 'load-path (expand-file-name d base-dir))))

(require 'tibetan-cascade)
(require 'tibetan-sanskrit-reading)

(defmacro tibetan-sanskrit-cascade-test--with-source (&rest body)
  "Ein sa-Kaskaden-Quelldokument (1 Section, 1 Satz, 2 Segmente,
IAST); bindet SRC, DIR, ANALYSIS-DIR.  Fires gestubbt."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sa-cascade-" t))
          (src (expand-file-name "belegstellen.org" dir))
          (analysis-dir (file-name-as-directory
                         (expand-file-name "analysis" dir))))
     (unwind-protect
         (progn
           (make-directory analysis-dir t)
           (with-temp-file src
             (insert "#+TITLE: Sanskrit-Belegstellen\n"
                     "#+TIBETAN_LAYOUT: cascade\n"
                     "#+SOURCE_LANG: sa\n"
                     "#+TIBETAN_TARGET_LANG: de\n\n"
                     "* Tibetan Text\n"
                     "** Section PP ad MMK 24.8\n"
                     ":PROPERTIES:\n:LOPEZ_SECTION: 1\n:END:\n"
                     "*** Sentence 1\n"
                     "**** Segment 1\n"
                     "dharmāṇāṃ śūnyatā svabhāvaḥ ।\n\n"
                     "**** Segment 2\n"
                     "na svato nāpi parataḥ ॥\n\n"))
           (cl-letf (((symbol-function 'tibetan-cascade--fire-sentence)
                      (lambda (&rest _) 'stubbed))
                     ((symbol-function 'tibetan-cascade--fire-section)
                      (lambda (&rest _) 'stubbed)))
             ,@body))
       (delete-directory dir t))))

(defconst tibetan-sanskrit-cascade-test--wa-org
  "*** Segment 1
dharmāṇām śūnyatā svabhāvaḥ
- dharmāṇām — dharma; N.GEN.PL
- śūnyatā — śūnyatā; N.NOM.SG
- svabhāvaḥ — svabhāva; N.NOM.SG

*** Segment 2
na svataḥ na api parataḥ
- na — na; IND
- svataḥ — svatas; IND
- api — api; IND
- parataḥ — paratas; IND"
  "Gelandete Word-Analysis (org-Form) für das Fixture.")

(defun tibetan-sanskrit-cascade-test--file-string (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun tibetan-sanskrit-cascade-test--insert-word-analysis (file body)
  "BODY als `** Word Analysis' vor `* Footnotes' in FILE einsetzen."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward "^\\* Footnotes")
    (goto-char (line-beginning-position))
    (insert "** Word Analysis\n" body "\n\n")
    (write-region (point-min) (point-max) file nil 'silent)))

(ert-deftest tibetan-sanskrit-cascade-scaffold-reading-plain-iast ()
  "C1: sa-Scaffold — Reading mit reinen IAST-Zeilen (kein
Wylie-Dekor, kein ` /'), ⟦N⟧-Renderings, Glossentabellen mit
Oberflächenwörtern und `?'-Labels, KEINE Sentence Structure,
`#+SOURCE_LANG: sa' im Satzdatei-Header."
  (tibetan-sanskrit-cascade-test--with-source
    (let* ((file (tibetan-cascade--create-file
                  1 '((1 . "dharmāṇāṃ śūnyatā svabhāvaḥ ।")
                      (2 . "na svato nāpi parataḥ ॥"))
                  src))
           (s (tibetan-sanskrit-cascade-test--file-string file)))
      (should (string-match-p "^#\\+SOURCE_LANG: sa$" s))
      (should (string-match-p "^\\* Reading$" s))
      ;; Plain IAST interlinear line, no decoration, no shad suffix.
      (should (string-match-p "^dharmāṇāṃ śūnyatā svabhāvaḥ$" s))
      (should (string-match-p "^na svato nāpi parataḥ$" s))
      (should-not (string-match-p "=[a-z]" s))
      ;; Renderings placeholders per unit.
      (should (string-match-p "⟦1⟧" s))
      (should (string-match-p "⟦2⟧" s))
      ;; Gloss tables: surface words in row 1, `?' labels in row 3.
      (should (string-match-p "^\\*\\* Gloss Tables$" s))
      (should (string-match-p "| dharmāṇāṃ" s))
      ;; No Tibetan sentence-structure trees over IAST.
      (should-not (string-match-p "^\\*\\* Sentence Structure$" s))
      ;; Minimal analysis headings for the landing writers.
      (should (string-match-p "^\\*\\* Translation$" s))
      (should (string-match-p "^\\*\\* DharmaMitra Translation$" s)))))

(ert-deftest tibetan-sanskrit-cascade-regenerate-preserves-word-analysis ()
  "C1: `** Word Analysis' überlebt das Regenerate byte-erhalten —
und die Glossentabellen materialisieren daraus (Padapāṭha in
Zeile 1, Morph-Labels in Zeile 3)."
  (tibetan-sanskrit-cascade-test--with-source
    (let ((file (tibetan-cascade--create-file
                 1 '((1 . "dharmāṇāṃ śūnyatā svabhāvaḥ ।")
                     (2 . "na svato nāpi parataḥ ॥"))
                 src)))
      (tibetan-sanskrit-cascade-test--insert-word-analysis
       file tibetan-sanskrit-cascade-test--wa-org)
      (let ((r (tibetan-cascade-reanalyze-file file :source-file src)))
        (should (plist-get r :ok)))
      (let ((s (tibetan-sanskrit-cascade-test--file-string file)))
        ;; Word Analysis preserved (keep-l2).
        (should (string-match-p "^\\*\\* Word Analysis$" s))
        (should (string-match-p "- dharmāṇām — dharma; N.GEN.PL" s))
        ;; Tables now carry padapāṭha forms + morph labels.
        (should (string-match-p "| dharmāṇām" s))
        (should (string-match-p "| N\\.GEN\\.PL" s))
        (should (string-match-p "| IND" s))))))

(ert-deftest tibetan-sanskrit-cascade-regenerate-idempotent ()
  "C1: zweites Regenerate ist byte-identisch (modulo Stamps)."
  (tibetan-sanskrit-cascade-test--with-source
    (let ((file (tibetan-cascade--create-file
                 1 '((1 . "dharmāṇāṃ śūnyatā svabhāvaḥ ।")
                     (2 . "na svato nāpi parataḥ ॥"))
                 src)))
      (tibetan-sanskrit-cascade-test--insert-word-analysis
       file tibetan-sanskrit-cascade-test--wa-org)
      (tibetan-cascade-reanalyze-file file :source-file src)
      (let ((first (tibetan-sanskrit-cascade-test--file-string file)))
        (tibetan-cascade-reanalyze-file file :source-file src)
        (let ((second (tibetan-sanskrit-cascade-test--file-string file)))
          (cl-flet ((strip (s)
                      (replace-regexp-in-string
                       "^#\\+\\(CREATED\\|LAST_ANALYZED\\):.*$" "" s)))
            (should (equal (strip first) (strip second)))))))))

(ert-deftest tibetan-sanskrit-cascade-regenerate-preserves-user-slots ()
  "C1: My Notes / Working Translation / editierte Glossentabellen
\(Hash-Mismatch) überleben das sa-Regenerate."
  (tibetan-sanskrit-cascade-test--with-source
    (let ((file (tibetan-cascade--create-file
                 1 '((1 . "dharmāṇāṃ śūnyatā svabhāvaḥ ।")
                     (2 . "na svato nāpi parataḥ ॥"))
                 src)))
      ;; Fill user slots + edit the gloss tables (invalidate hash).
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (re-search-forward "^\\* My Notes\n")
        (insert "MEINE NOTIZ.\n")
        (goto-char (point-min))
        (re-search-forward "^\\* Working Translation\n")
        (insert "Die Leerheit der Gegebenheiten…\n")
        (goto-char (point-min))
        (when (re-search-forward "^\\*\\*\\* Segment 1\n" nil t)
          (insert "| HANDEDIT |\n"))
        (write-region (point-min) (point-max) file nil 'silent))
      (tibetan-cascade-reanalyze-file file :source-file src)
      (let ((s (tibetan-sanskrit-cascade-test--file-string file)))
        (should (string-match-p "MEINE NOTIZ\\." s))
        (should (string-match-p "Die Leerheit der Gegebenheiten…" s))
        (should (string-match-p "| HANDEDIT |" s))))))

;; ----------------------------------------------------------------------------
;; C2 — Prompts (Satz + Chunk)
;; ----------------------------------------------------------------------------

(require 'tibetan-sentence-claude)

(defun tibetan-sanskrit-cascade-test--sentence-plist ()
  '(:sent-num 1 :seg-nums (1 2)
    :children ((:seg-num 1 :text "dharmāṇāṃ śūnyatā svabhāvaḥ ।")
               (:seg-num 2 :text "na svato nāpi parataḥ ॥"))
    :tibetan-text "dharmāṇāṃ śūnyatā svabhāvaḥ ।na svato nāpi parataḥ ॥"))

(ert-deftest tibetan-sanskrit-cascade-sentence-prompt-sa ()
  "C2: der Satz-Prompt eines sa-Dokuments — KEIN 'Wylie:', KEIN
'Classical Tibetan'; System trägt den Sanskrit-Kontrakt
\(## Word Analysis, Padapāṭha, ⟦N⟧-Marker) und die
### Segment-Enumeration erreicht den User-Prompt."
  (tibetan-sanskrit-cascade-test--with-source
    (let* ((prompts (tibetan-sentence-claude--build-prompts
                     (tibetan-sanskrit-cascade-test--sentence-plist)
                     src analysis-dir))
           (system (car prompts))
           (user (cdr prompts)))
      (should (string-match-p "## Word Analysis" system))
      (should (string-match-p "padapāṭha" system))
      (should (string-match-p "⟦N⟧" system))
      (should (string-match-p "Sanskrit" user))
      (should (string-match-p "### Segment 1" user))
      (should (string-match-p "### Segment 2" user))
      (should-not (string-match-p "Wylie:" user))
      (should-not (string-match-p "Classical Tibetan" user))
      (should-not (string-match-p "Classical Tibetan" system)))))

(ert-deftest tibetan-sanskrit-cascade-sentence-prompt-cache-constant ()
  "C2: der sa-System-Prompt ist pro Dokument byte-konstant
\(Anthropic-Cache-Präfix — vierter koexistierender)."
  (tibetan-sanskrit-cascade-test--with-source
    (let ((s1 (car (tibetan-sentence-claude--build-prompts
                    (tibetan-sanskrit-cascade-test--sentence-plist)
                    src analysis-dir)))
          (s2 (car (tibetan-sentence-claude--build-prompts
                    '(:sent-num 2 :seg-nums (3)
                      :children ((:seg-num 3 :text "kutaḥ ॥"))
                      :tibetan-text "kutaḥ ॥")
                    src analysis-dir))))
      (should (equal s1 s2)))))

(ert-deftest tibetan-sanskrit-cascade-chunk-prompt-sa ()
  "C2: der Chunk-Prompt eines sa-Dokuments sagt 'Sanskrit passage'
und behält die ⟦N⟧-Only-Translation-Anweisung."
  (tibetan-sanskrit-cascade-test--with-source
    (let* ((chunk '(:label "PP ad MMK 24.8" :lopez 1
                    :sentences ((:sent-num 1
                                 :segs ((1 . "dharmāṇāṃ śūnyatā ।")
                                        (2 . "na svato ॥"))))))
           (prompts (tibetan-cascade--build-chunk-prompts chunk src))
           (system (car prompts))
           (user (cdr prompts)))
      (should (string-match-p "Sanskrit passage" user))
      (should-not (string-match-p "Classical Tibetan" user))
      (should-not (string-match-p "Classical Tibetan" system))
      (should (string-match-p "ONLY" system))
      (should (string-match-p "⟦N⟧" system)))))

(ert-deftest tibetan-sanskrit-cascade-bo-prompts-unchanged ()
  "C2-Lock: bo-Prompts bleiben unverändert (Header 'Classical
Tibetan sentence', Wylie-Zeile vorhanden wenn konvertierbar)."
  (let ((dir (make-temp-file "bo-prompt-" t)))
    (unwind-protect
        (let ((src (expand-file-name "doc.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                    "* Tibetan Text\n*** Sentence 1\n**** Segment 1\nབདག\n"))
          (let* ((prompts (tibetan-sentence-claude--build-prompts
                           '(:sent-num 1 :seg-nums (1)
                             :children ((:seg-num 1 :text "བདག"))
                             :tibetan-text "བདག")
                           src nil))
                 (user (cdr prompts)))
            (should (string-match-p "Classical Tibetan sentence" user))))
      (delete-directory dir t))))

(provide 'tibetan-sanskrit-cascade-test)

;;; tibetan-sanskrit-cascade-test.el ends here
