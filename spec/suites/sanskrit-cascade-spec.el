;;; sanskrit-cascade-spec.el --- BDD: Sanskrit im Kaskaden-Layout -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Sanskrit-Kaskade C5 (2026-09-24).  End-to-End über die REALE
;; Pipeline: create-all → Dispatcher → Claim → Queue → gptel →
;; Landung (Word Analysis + Spans) → Regenerate-after-Land — nur die
;; Prozessränder gestubbt (Muster von sentence-first-spec.el):
;;
;;   - `tibetan-claude-queue-submit' läuft synchron
;;   - `gptel-request' ruft den :callback mit der gecannten Antwort
;;   - `run-at-time' sofort (Fan-out + DM-Stagger)
;;   - `tibetan-dharmamitra-api-chat-translate' als Capture-Stub —
;;     liefert eine Übersetzung UND fängt target-lang/input-encoding
;;
;; Kein Netz, keine Timer, deterministisch.

;;; Code:

(require 'tibetan-bdd)
(require 'cl-lib)
(require 'tibetan-analysis-claude)
(require 'tibetan-sentence-persist)
(require 'tibetan-sentence-claude)
(require 'tibetan-cascade)
(require 'tibetan-sanskrit-reading)

(defconst sanskrit-cascade-spec--response
  "## Translation
⟦1⟧Die Leerheit der Gegebenheiten ist das Eigenwesen⟦/1⟧ — ⟦2⟧weder aus sich noch aus anderem⟦/2⟧.

### Segment 1
Die Leerheit der Gegebenheiten ist das Eigenwesen.

### Segment 2
Weder aus sich noch aus anderem.

## Word Analysis
### Segment 1
dharmāṇām śūnyatā svabhāvaḥ
- dharmāṇām — dharma; N.GEN.PL
- śūnyatā — śūnyatā; N.NOM.SG
- svabhāvaḥ — svabhāva; N.NOM.SG

### Segment 2
na svataḥ na api parataḥ
- na — na; IND
- svataḥ — svatas; IND
- api — api; IND
- parataḥ — paratas; IND

## Vocabulary
### Segment 1
dharmāṇām, noun, \"der Gegebenheiten\", Genitiv Plural
śūnyatā, noun, \"Leerheit\", Abstraktum
svabhāvaḥ, noun, \"Eigenwesen\", Nominativ

### Segment 2
svataḥ, indeclinable, \"aus sich\", Ablativadverb

## Grammar
Nominalsatz mit elliptischer Fortführung.

### Segment 1
- Prädikatsnomen im Nominativ.

### Segment 2
- Verneinte Ablativadverbien.

## Concept Notes
- **svabhāva** — Eigenwesen; der zentrale Verhandlungsbegriff von MMK 24.
"
  "Gecannte sa-Satz-Antwort im vollen C2-Kontrakt.")

(defvar sanskrit-cascade-spec--dir nil)

(defun sanskrit-cascade-spec--corpus (dir)
  "Ein sa-Quelldokument (1 Section, 1 Satz, 2 Segmente); Pfad-Plist."
  (let ((src (expand-file-name "belegstellen.org" dir)))
    (make-directory (expand-file-name "analysis" dir) t)
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
    (list :src src
          :analysis (file-name-as-directory
                     (expand-file-name "analysis" dir)))))

(defun sanskrit-cascade-spec--read (path)
  (with-temp-buffer (insert-file-contents path) (buffer-string)))

(defun sanskrit-cascade-spec--run (paths)
  "create-all + Satz-Fire mit gecannter Antwort; Ergebnis-Plist."
  (tibetan-sentence-claude-clear-inflight)
  (let ((statuses '())
        (dm-captures '())
        (had-gptel (featurep 'gptel)))
    (unwind-protect
        (progn
          (unless had-gptel (provide 'gptel))
          (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
                     (lambda (thunk &rest _)
                       (funcall thunk
                                (lambda (status) (push status statuses)))))
                    ((symbol-function 'gptel-request)
                     (lambda (_prompt &rest args)
                       (funcall (plist-get args :callback)
                                sanskrit-cascade-spec--response
                                '(:status 200))))
                    ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
                     (lambda (&rest _) t))
                    ((symbol-function 'run-at-time)
                     (lambda (_secs _repeat fn &rest args)
                       (apply fn args) nil))
                    ((symbol-function 'tibetan-dharmamitra-api-chat-translate)
                     (lambda (_text &rest args)
                       (push (list :target-lang
                                   (plist-get args :target-lang)
                                   :input-encoding
                                   (plist-get args :input-encoding))
                             dm-captures)
                       "Die Leerheit der Gegebenheiten ist das Eigenwesen — weder aus sich noch aus anderem.")))
            (with-current-buffer (find-file-noselect (plist-get paths :src))
              (unwind-protect
                  ;; create-all ohne Auto-Fire; dann der Dispatcher.
                  (let ((tibetan-auto-fire-claude-on-create nil))
                    (tibetan-cascade-create-all))
                (set-buffer-modified-p nil)
                (kill-buffer (current-buffer))))
            (let* ((file (car (directory-files
                               (plist-get paths :analysis) t "\\`sent-001")))
                   (fired (tibetan-analysis--fire-sentence-level
                           "dharmāṇāṃ śūnyatā svabhāvaḥ ।na svato nāpi parataḥ ॥"
                           file (plist-get paths :src) 1 nil))
                   (second (tibetan-analysis--fire-sentence-level
                            "dharmāṇāṃ śūnyatā svabhāvaḥ ।na svato nāpi parataḥ ॥"
                            file (plist-get paths :src) 1 nil)))
              (list :fired fired :second second :statuses statuses
                    :dm dm-captures
                    :file file
                    :content (sanskrit-cascade-spec--read file)))))
      (unless had-gptel
        (setq features (delq 'gptel features))))))

(define-bdd-suite sanskrit-cascade
    "Sanskrit-Quelldokumente im Kaskaden-Layout (SOURCE_LANG sa)"

  (spec "Ein sa-Satz: Landung, Word Analysis, Tabellen, DM iast/german"
    :given (setq sanskrit-cascade-spec--dir
                 (make-temp-file "bdd-sacas-" t))
    :when (sanskrit-cascade-spec--run
           (sanskrit-cascade-spec--corpus sanskrit-cascade-spec--dir))
    :then ((should (eq 'fired (plist-get result :fired)))
           (tibetan-bdd-assert-contains
            (format "%S" (plist-get result :statuses)) "(:status ok)"
            "Queue job should complete ok")
           ;; Deutsche Übersetzung + ⟦N⟧-Renderings gelandet.
           (tibetan-bdd-assert-contains
            (plist-get result :content)
            "Die Leerheit der Gegebenheiten ist das Eigenwesen"
            "Die Satzdatei trägt die deutsche Übersetzung")
           (tibetan-bdd-assert-contains
            (plist-get result :content) "⟦1⟧"
            "Rendering ⟦1⟧ vorhanden")
           ;; Word Analysis als org-Sektion.
           (tibetan-bdd-assert-contains
            (plist-get result :content) "** Word Analysis"
            "Word Analysis gelandet")
           (tibetan-bdd-assert-contains
            (plist-get result :content) "- dharmāṇām — dharma; N.GEN.PL"
            "Padapāṭha-Bullets vorhanden")
           ;; Materialisierte Tabellen: Padapāṭha + Morph + Glosse.
           (tibetan-bdd-assert-contains
            (plist-get result :content) "| dharmāṇām"
            "Tabelle trägt die Padapāṭha-Form")
           (tibetan-bdd-assert-contains
            (plist-get result :content) "N.GEN.PL"
            "Tabelle trägt das Morph-Label")
           (tibetan-bdd-assert-contains
            (plist-get result :content) "der Gegebenheiten"
            "Tabelle trägt die deutsche Claude-Glosse")
           ;; Keine tibetische Vergiftung.
           (should-not (string-match-p "Wylie" (plist-get result :content)))
           ;; DM: iast + german.
           (tibetan-bdd-assert-contains
            (format "%S" (plist-get result :dm)) "iast"
            "DM-Call trägt input-encoding iast")
           (tibetan-bdd-assert-contains
            (format "%S" (plist-get result :dm)) "german"
            "DM-Call trägt target-lang german")
           ;; Zweiter Fire: dedup/decline, nie doppelt.
           (should-not (eq 'fired (plist-get result :second)))
           (progn (delete-directory sanskrit-cascade-spec--dir t) t))
    :example "PP-ad-MMK-24.8-Fixture: ein Call, volle sa-Landung"
    :tags (:sanskrit :cascade)))

(provide 'sanskrit-cascade-spec)

;;; sanskrit-cascade-spec.el ends here
