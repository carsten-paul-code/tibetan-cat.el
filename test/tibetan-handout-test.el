;;; tibetan-handout-test.el --- Tests for the reading-class handout -*- lexical-binding: t -*-

;;; Commentary:
;; §5.59 (2026-10-09): printable handout per § / sentence of a
;; cascade source — Wylie (+ Uchen), translation, vocabulary (★
;; wordlist first), grammar (filtered labels).  All fixtures in temp
;; dirs — never the live corpus; no network, no LaTeX run except the
;; one skip-unless smoke test.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-handout)
(require 'tibetan-sentence-persist)

;; ----------------------------------------------------------------------------
;; Fixtures
;; ----------------------------------------------------------------------------

(defconst tibetan-handout-test--bo-source
  (concat
   "#+TITLE: Klu sgrub dgongs rgyan — CAT-Quelle (B2)\n"
   "#+TIBETAN_LAYOUT: cascade\n\n"
   "* Tibetan Text\n"
   "** Section §220\n"
   ":PROPERTIES:\n:LOPEZ_SECTION: 220\n:END:\n\n"
   "*** Sentence 654\n"
   "**** Segment 1970\nབློས་མཐོང་བ་དང་།\n\n"
   "**** Segment 1971\nཀུན་རྫོབ་ཀྱི་བདེན་པ།\n\n"
   "*** Sentence 655\n"
   "**** Segment 1975\nབཅོས་མར་གྱུར་པའི་དངོས་ནི།\n\n"
   "** Section §221\n"
   ":PROPERTIES:\n:LOPEZ_SECTION: 221\n:END:\n\n"
   "*** Sentence 656\n"
   "**** Segment 1979\nཚད་མ་དང་རིགས་པ།\n\n"))

(defconst tibetan-handout-test--bo-sent-654
  (concat
   "#+TITLE: Sentence 654 Analysis\n"
   "#+TIBETAN_LAYOUT: cascade\n"
   "#+SOURCE: [[file:../Rgyan-cat.org::*Sentence 654][Rgyan-cat.org / Sentence 654]]\n"
   "#+SEGMENTS: 1970, 1971\n\n"
   "* Translation\n"
   "Ganzer Satz deutsch.\n\n"
   "* Reading\n** Gloss Tables\n"
   "*** Segment 1970\n| blos |\n- ⟦1970⟧ Durch den Verstand gesehen,\n\n"
   "*** Segment 1971\n| kun rdzob |\n- ⟦1971⟧ die scheinbare Wahrheit.\n\n"
   "* Tibetan Analysis\n"
   "** Claude Vocabulary\n"
   "*** Segment 1970\n"
   "blos, ergative/instrumental, \"durch den Verstand\", instrumental of *blo*; Skt. *buddhi*\n"
   "dang, particle, \"und\", coordinating\n\n"
   "*** Segment 1971\n"
   "kun rdzob, noun, \"scheinbar\", Skt. *saṃvṛti*; concealer\n\n"
   "** Claude Grammar\n"
   "**Cross-clause overview:** OVERVIEW TEXT.\n\n"
   "*** Segment 1970\n"
   "- *Verb backbone:* mthong is the verb.\n"
   "- *Case frame:* CASEFRAME TEXT.\n"
   "- *Notable constructions:* blos instrumental,\n"
   "  continued on a second line.\n"
   "- *Translation justifications:* JUSTIFICATION TEXT.\n\n"
   "*** Segment 1971\n"
   "- *Case frame:* only case frame here.\n\n"
   "** Concept Notes\n- **kun rdzob** — note.\n\n"
   "* Provided Translations\n"
   "** DharmaMitra Translation\nDM POISON TEXT\n\n"
   "** Lopez 2006\nLOPEZ POISON TEXT\n\n"
   "* Working Translation\nWT POISON TEXT\n\n"
   "* My Notes\n\n* Footnotes\n"))

(defconst tibetan-handout-test--bo-wordlist
  (concat "| Term | Bedeutung |\n|------+-----------|\n"
          "| blo | Verstand // mind / awareness |\n"
          "| kun rdzob | scheinbar / scheinbare Wahrheit // conventional (truth) |\n"
          "| yin | sein // to be |\n"
          "| na | POISON-NA |\n"))

(defconst tibetan-handout-test--sa-source
  (concat
   "#+TITLE: MAv VI.28\n"
   "#+TIBETAN_LAYOUT: cascade\n"
   "#+SOURCE_LANG: sa\n\n"
   "* Tibetan Text\n"
   "** Section MAv VI.28\n\n"
   "*** Sentence 1\n"
   "**** Segment 1\nmohaḥ svabhāvāvaraṇād dhi saṃvṛtiḥ |\n\n"))

(defconst tibetan-handout-test--sa-sent-1
  (concat
   "#+TITLE: Sentence 1 Analysis\n"
   "#+TIBETAN_LAYOUT: cascade\n"
   "#+SOURCE: [[file:../Mav-sa.org::*Sentence 1][Mav-sa.org / Sentence 1]]\n\n"
   "* Translation\nDer moha ist saṃvṛti.\n\n"
   "* Reading\n** Gloss Tables\n*** Segment 1\n| mohaḥ |\n"
   "- ⟦1⟧ Der moha ist saṃvṛti.\n\n"
   "* Tibetan Analysis\n"
   "** Claude Vocabulary\n*** Segment 1\n"
   "mohaḥ, noun (m.), \"Verblendung\", root affliction\n"
   "na, indeclinable, \"nicht\", negation\n\n"
   "** Claude Grammar\n*** Segment 1\n"
   "- *Syntax:* nominal sentence.\n\n"
   "** Concept Notes\n- note\n\n"
   "** Word Analysis\n*** Segment 1\nmohaḥ na\n\n"
   "- mohaḥ — moha; N.NOM.SG.M\n- na — na; IND.\n\n"
   "* Provided Translations\n\n* Working Translation\n\n"
   "* My Notes\n\n* Footnotes\n"))

(defmacro tibetan-handout-test--with-corpus (&rest body)
  "Temp corpus: bo source Rgyan-cat.org (§220: Sentences 654, 655;
§221: 656) with Resources wordlist and the sent file of 654 only;
sa source Mav-sa.org with Resources (poison `na') and its sent file.
Binds DIR, SRC, SA-SRC, FOLDER, SA-FOLDER."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "handout-" t))
          (src (expand-file-name "Rgyan-cat.org" dir))
          (folder (file-name-as-directory (expand-file-name "analysis" dir)))
          (sa-dir (expand-file-name "sa" dir))
          (sa-src (expand-file-name "Mav-sa.org" sa-dir))
          (sa-folder (file-name-as-directory
                      (expand-file-name "analysis" sa-dir))))
     (unwind-protect
         (progn
           (make-directory folder t)
           (make-directory (expand-file-name "Resources" dir) t)
           (make-directory sa-folder t)
           (make-directory (expand-file-name "Resources" sa-dir) t)
           (with-temp-file src (insert tibetan-handout-test--bo-source))
           (with-temp-file (expand-file-name "Resources/Wortliste-test.org" dir)
             (insert tibetan-handout-test--bo-wordlist))
           (with-temp-file (tibetan-sentence--filepath 654 folder src)
             (insert tibetan-handout-test--bo-sent-654))
           (with-temp-file sa-src (insert tibetan-handout-test--sa-source))
           (with-temp-file (expand-file-name "Resources/Wortliste-sa.org" sa-dir)
             (insert tibetan-handout-test--bo-wordlist))
           (with-temp-file (tibetan-sentence--filepath 1 sa-folder sa-src)
             (insert tibetan-handout-test--sa-sent-1))
           ,@body)
       (delete-directory dir t))))

(defun tibetan-handout-test--curated (&rest pairs)
  "Hash of curated wordlist PAIRS (KEY VALUE …)."
  (let ((h (make-hash-table :test 'equal)))
    (while pairs
      (puthash (pop pairs) (pop pairs) h))
    h))

;; ----------------------------------------------------------------------------
;; B1 — data layer
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-handout-vocab-fields ()
  "The comma-format vocabulary line splits into term / part of speech
/ gloss; only the Skt. equivalent survives from the note.  A stray
leading bullet (C6a model drift) is tolerated."
  (let ((f (tibetan-handout--vocab-fields
            "blos, ergative/instrumental, \"durch den Verstand\", instrumental of *blo*; Skt. *buddhi*")))
    (should (equal "blos" (plist-get f :term)))
    (should (equal "ergative/instrumental" (plist-get f :pos)))
    (should (equal "durch den Verstand" (plist-get f :gloss)))
    (should (equal "buddhi" (plist-get f :skt))))
  (let ((f (tibetan-handout--vocab-fields "- ste, particle, \"—\", converb")))
    (should (equal "ste" (plist-get f :term)))
    (should (equal "—" (plist-get f :gloss)))
    (should-not (plist-get f :skt)))
  ;; No quoted gloss: third comma field is the gloss.
  (should (equal "Wahrheit"
                 (plist-get (tibetan-handout--vocab-fields
                             "bden pa, noun, Wahrheit")
                            :gloss)))
  (should-not (tibetan-handout--vocab-fields ""))
  (should-not (tibetan-handout--vocab-fields "---")))

(ert-deftest tibetan-handout-curated-gloss-pos-gated ()
  "★ lookup: exact key, a trailing particle SYLLABLE, or a merged
clitic — the latter ONLY when Claude's part of speech licenses it
\(blos ergative → blo; rgyas as a verb must NOT become rgya)."
  (let ((tibetan-current-resources-vocab
         (tibetan-handout-test--curated
          "blo" "Verstand // mind / awareness"
          "kun rdzob" "scheinbar // conventional"
          "rgya" "weit // vast"
          "yin" "sein // to be"
          "'di" "dies // this"))
        (tibetan-current-custom-vocab nil))
    (should (equal "scheinbar // conventional"
                   (tibetan-handout--curated-gloss "kun rdzob" "noun")))
    (should (equal "Verstand // mind / awareness"
                   (tibetan-handout--curated-gloss
                    "blos" "ergative/instrumental")))
    (should-not (tibetan-handout--curated-gloss "rgyas" "verb"))
    (should (equal "sein // to be"
                   (tibetan-handout--curated-gloss "yin pas"
                                                   "copula + converb")))
    (should (equal "dies // this"
                   (tibetan-handout--curated-gloss
                    "'di'i" "demonstrative pronoun + genitive")))
    (should-not (tibetan-handout--curated-gloss "'di'i" "noun"))
    (should-not (tibetan-handout--curated-gloss "gti mug" "noun"))))

(ert-deftest tibetan-handout-context-differs-p ()
  "The context gloss is shown only when its alternatives are not
already among the ★ entry's alternatives (either language half)."
  (should-not (tibetan-handout--context-differs-p
               "Verstand" "Verstand // mind / awareness"))
  (should-not (tibetan-handout--context-differs-p
               "scheinbar" "scheinbar / scheinbare Wahrheit // conventional (truth)"))
  (should (tibetan-handout--context-differs-p
           "durch den Verstand" "Verstand // mind / awareness"))
  (should (tibetan-handout--context-differs-p
           "Schein / scheinbar" "scheinbar / scheinbare Wahrheit // conventional (truth)")))

(ert-deftest tibetan-handout-grammar-bullets-filtered ()
  "Only the configured labels survive; continuation lines join their
bullet; a segment carrying none of the labels keeps ALL bullets (the
filter never empties a segment)."
  (let ((b (tibetan-handout--grammar-bullets
            (concat "- *Verb backbone:* mthong is the verb.\n"
                    "- *Case frame:* CASEFRAME.\n"
                    "- *Notable constructions:* blos instrumental,\n"
                    "  continued on a second line.\n"
                    "- *Translation justifications:* JUST."))))
    (should (equal '(("Verb backbone" . "mthong is the verb.")
                     ("Notable constructions"
                      . "blos instrumental, continued on a second line."))
                   b)))
  (should (equal '(("Case frame" . "only case frame here."))
                 (tibetan-handout--grammar-bullets
                  "- *Case frame:* only case frame here.")))
  ;; Free prose (no labelled bullets) survives unlabelled.
  (should (equal '((nil . "A nominal sentence."))
                 (tibetan-handout--grammar-bullets "A nominal sentence.")))
  (should-not (tibetan-handout--grammar-bullets nil)))

(ert-deftest tibetan-handout-load-curated-from-source-resources ()
  "The ★ source is the Resources folder BESIDE THE SOURCE, loaded
without leaking into the global vocabulary state (§5.34 lesson:
locate assets from the source path, never from the caller's
buffer)."
  (tibetan-handout-test--with-corpus
    (let ((before tibetan-current-resources-vocab)
          (h (tibetan-handout--load-curated src)))
      (should (hash-table-p h))
      (should (equal "Verstand // mind / awareness" (gethash "blo" h)))
      (should (eq before tibetan-current-resources-vocab)))))

(ert-deftest tibetan-handout-sentence-data-bo ()
  "Full bo sentence: segments with Wylie + Uchen, translation by
segment from the ⟦N⟧ lines, vocabulary per segment with ★ and the
context gloss only where it differs, grammar filtered (overview
dropped, 1971 falls back to its only bullet)."
  (tibetan-handout-test--with-corpus
    (let* ((tibetan-current-resources-vocab
            (tibetan-handout--load-curated src))
           (tibetan-current-custom-vocab nil)
           (d (tibetan-handout--sentence-data 654 src))
           (segs (plist-get d :segs)))
      (should (equal "bo" (plist-get d :lang)))
      (should-not (plist-get d :missing))
      (should (equal '(1970 1971) (mapcar (lambda (s) (plist-get s :num)) segs)))
      (should (string-match-p "\\`blos mthong ba dang"
                              (plist-get (car segs) :wylie)))
      (should (string-match-p "བློས" (plist-get (car segs) :uchen)))
      (should (equal '((1970 . "Durch den Verstand gesehen,")
                       (1971 . "die scheinbare Wahrheit."))
                     (plist-get (plist-get d :translation) :by-seg)))
      (let* ((v1970 (cdr (assq 1970 (plist-get d :vocab))))
             (blos (car v1970))
             (dang (cadr v1970))
             (kun (car (cdr (assq 1971 (plist-get d :vocab))))))
        (should (plist-get blos :star))
        (should (equal "Verstand // mind / awareness" (plist-get blos :gloss)))
        (should (equal "durch den Verstand" (plist-get blos :context)))
        (should (string-match-p "Skt\\. buddhi" (plist-get blos :info)))
        (should-not (plist-get dang :star))
        (should (equal "und" (plist-get dang :gloss)))
        (should (plist-get kun :star))
        (should-not (plist-get kun :context)))
      (let ((g (plist-get d :grammar)))
        (should-not (assq nil g))
        (should (equal '("Verb backbone" "Notable constructions")
                       (mapcar #'car (cdr (assq 1970 g)))))
        (should (equal '("Case frame") (mapcar #'car (cdr (assq 1971 g)))))))))

(ert-deftest tibetan-handout-sentence-data-gaps ()
  "A sentence without analysis file is flagged :missing (visible gap,
never an error); incomplete renderings fall back to the whole
Translation with the machine label stripped; a placeholder
Translation yields no translation at all."
  (tibetan-handout-test--with-corpus
    (let ((d (tibetan-handout--sentence-data 655 src)))
      (should (plist-get d :missing))
      (should (equal '(1975) (mapcar (lambda (s) (plist-get s :num))
                                     (plist-get d :segs)))))
    (let ((file (tibetan-sentence--filepath 654 folder src)))
      (with-temp-file file
        (insert (replace-regexp-in-string
                 "- ⟦1971⟧ die scheinbare Wahrheit\\."
                 "- ⟦1971⟧ [Awaiting Claude — span]"
                 (replace-regexp-in-string
                  "Ganzer Satz deutsch\\."
                  "(Sentence 654 — §220 chunk)\nGanzer Satz deutsch."
                  tibetan-handout-test--bo-sent-654))))
      (should (equal '(:whole "Ganzer Satz deutsch.")
                     (plist-get (tibetan-handout--sentence-data 654 src)
                                :translation)))
      (with-temp-file file
        (insert (replace-regexp-in-string
                 "- ⟦1971⟧ die scheinbare Wahrheit\\."
                 "- ⟦1971⟧ [Awaiting Claude — span]"
                 (replace-regexp-in-string
                  "Ganzer Satz deutsch\\."
                  "[Requesting translation...]"
                  tibetan-handout-test--bo-sent-654))))
      (should-not (plist-get (tibetan-handout--sentence-data 654 src)
                             :translation)))))

(ert-deftest tibetan-handout-sentence-data-sa ()
  "Sanskrit: no ★ lookup EVER (the wordlist is Wylie-keyed — `na'
would hit a Tibetan entry, §5.57 poison class), no Uchen line, the
info column carries the Word-Analysis morphology."
  (tibetan-handout-test--with-corpus
    (let* ((tibetan-current-resources-vocab
            (tibetan-handout--load-curated sa-src))
           (tibetan-current-custom-vocab nil)
           (d (tibetan-handout--sentence-data 1 sa-src))
           (v (cdr (assq 1 (plist-get d :vocab))))
           (na (cadr v)))
      (should (equal "sa" (plist-get d :lang)))
      (should-not (plist-get (car (plist-get d :segs)) :uchen))
      (should (string-match-p "\\`mohaḥ" (plist-get (car (plist-get d :segs))
                                                     :wylie)))
      (should-not (cl-some (lambda (e) (plist-get e :star)) v))
      (should (equal "nicht" (plist-get na :gloss)))
      (should (equal "moha; N.NOM.SG.M" (plist-get (car v) :info)))
      (should (equal '(("Syntax" . "nominal sentence."))
                     (cdr (assq 1 (plist-get d :grammar))))))))

;; ----------------------------------------------------------------------------
;; B2 — renderer (pure: data → org string)
;; ----------------------------------------------------------------------------

(defconst tibetan-handout-test--spec
  (list
   :title "Klu sgrub dgongs rgyan" :scope "§220" :source-name "Rgyan-cat.org"
   :date "2026-10-09"
   :sentences
   (list
    (list :sent-num 654 :lang "bo"
          :segs '((:num 1970 :wylie "blos mthong ba ~M_x" :uchen "བློས་མཐོང་བ།")
                  (:num 1971 :wylie "kun rdzob/" :uchen "ཀུན་རྫོབ།"))
          :translation '(:by-seg ((1970 . "Durch den Verstand gesehen,")
                                  (1971 . "die scheinbare Wahrheit.")))
          :vocab '((1970 (:term "blos" :gloss "Verstand // mind / awareness"
                          :star t :context "durch den Verstand, dadurch"
                          :info "ergative/instrumental; Skt. buddhi")
                         (:term "dang" :gloss "und | mit" :star nil
                          :context nil :info "particle"))
                   (1971 (:term "kun rdzob" :gloss "scheinbar" :star t
                          :context nil :info "noun")))
          :grammar '((1970 ("Verb backbone" . "*mthong* is the verb.")
                           ("Notable constructions" . "**blos** instrumental."))
                     (1971 (nil . "Free prose."))))
    (list :sent-num 655 :lang "bo" :missing t
          :segs '((:num 1975 :wylie "bcos mar" :uchen "བཅོས་མར།")))
    (list :sent-num 656 :lang "bo"
          :segs '((:num 1976 :wylie "zhes" :uchen "ཞེས།"))
          :translation '(:whole "Ganzer *Satz*.")
          :vocab nil :grammar nil)))
  "A hand-built handout spec: full sentence, missing file, gaps.")

(ert-deftest tibetan-handout-render-header ()
  "Kopf: GENERATED-Marker zuerst, LuaLaTeX, Tibetisch-Font aus der
defcustom, Kopfzeile Werk · Umfang · Sätze, NIRGENDS „Claude“."
  (let ((org (tibetan-handout-render tibetan-handout-test--spec)))
    (should (string-prefix-p tibetan-handout-generated-marker org))
    (should (string-match-p "^#\\+LATEX_COMPILER: lualatex$" org))
    (should (string-match-p (regexp-quote tibetan-handout-tibetan-font) org))
    (should (string-match-p "Klu sgrub dgongs rgyan} · §220 · Sätze 654–656"
                            org))
    (should (string-match-p "Stand 2026-10-09" org))
    (should-not (string-match-p "Claude" org))))

(ert-deftest tibetan-handout-render-text-part ()
  "`* Text': je Segment Uchen (in \\tibfont) über dem Wylie, die
Segmentnummer am Rand; Wylie LaTeX-sicher (~ _ escaped), in einem
Export-Block (org-Markup kann es nicht verbiegen)."
  (let ((org (tibetan-handout-render tibetan-handout-test--spec)))
    (should (string-match-p "^\\* Text$" org))
    (should (string-match-p "\\\\segno{1970}{\\\\tibfont[^}]*བློས་མཐོང་བ།}" org))
    (should (string-match-p (regexp-quote
                             "blos mthong ba \\textasciitilde{}M\\_x")
                            org))
    (should (string-match-p "#\\+BEGIN_EXPORT latex" org))
    ;; Der Text steht auf eigenen Seiten (neben den Klassentext legen).
    (should (string-match-p "}\\\\clearpage\n#\\+END_EXPORT" org))))

(ert-deftest tibetan-handout-render-sentence-blocks ()
  "Je Satz: Übersetzung mit Segmentnummern-Makro bzw. ganz bzw. Lücke,
Vokabular als Tabelle je Segment (★, Kontextglosse im ctx-Makro mit
escapten Kommas, `|' als \\vert{}), Grammatik als Beschreibungsliste
mit org-Kursiv statt Markdown-Sternen; fehlende Datei = sichtbare
Lücke."
  (let ((org (tibetan-handout-render tibetan-handout-test--spec)))
    (should (string-match-p "^\\* Satz 654 (Seg\\. 1970–1971)$" org))
    (should (string-match-p (regexp-quote
                             "{{{n(1970)}}}Durch den Verstand gesehen, {{{n(1971)}}}die scheinbare Wahrheit.")
                            org))
    (should (string-match-p
             (regexp-quote
              "| blos | ★ Verstand // mind / awareness {{{ctx(durch den Verstand\\, dadurch)}}} | ergative/instrumental; Skt. buddhi |")
             org))
    (should (string-match-p (regexp-quote "| dang | und \\vert{} mit | particle |")
                            org))
    (should (string-match-p (regexp-quote "{{{seg(1971)}}}") org))
    (should (string-match-p
             (regexp-quote "- Verb backbone :: /mthong/ is the verb.") org))
    (should (string-match-p
             (regexp-quote "- Notable constructions :: *blos* instrumental.")
             org))
    (should (string-match-p "^Free prose\\.$" org))
    ;; Satz 655: Analysedatei fehlt.
    (should (string-match-p "Analysedatei fehlt" org))
    ;; Satz 656: ganze Übersetzung, Lücken für Vokabular/Grammatik.
    (should (string-match-p "^Ganzer /Satz/\\.$" org))
    (should (string-match-p "{{{luecke(noch kein Vokabular)}}}" org))
    (should (string-match-p "{{{luecke(noch keine Grammatik)}}}" org))))

(ert-deftest tibetan-handout-render-parses-as-org ()
  "Das Ergebnis ist gültiges org: die Satz-Überschriften sind echte
Headlines, jede Vokabelzeile hat genau drei Zellen."
  (let ((org (tibetan-handout-render tibetan-handout-test--spec)))
    (with-temp-buffer
      (insert org)
      (org-mode)
      (let ((tree (org-element-parse-buffer)))
        (should (equal '("Text" "Satz 654 (Seg. 1970–1971)"
                         "Satz 655 (Seg. 1975)" "Satz 656 (Seg. 1976)")
                       (org-element-map tree 'headline
                         (lambda (h) (when (= 1 (org-element-property :level h))
                                       (org-element-property :raw-value h))))))
        (should (cl-every (lambda (n) (= n 3))
                          (org-element-map tree 'table-row
                            (lambda (r)
                              (when (eq 'standard (org-element-property :type r))
                                (length (org-element-contents r)))))))))))

(ert-deftest tibetan-handout-render-sanskrit-no-uchen ()
  "Sanskrit: keine Uchen-Zeile, das IAST steht direkt mit Nummer."
  (let ((org (tibetan-handout-render
              (list :title "MAv" :scope "MAv VI.28" :source-name "x.org"
                    :date "2026-10-09"
                    :sentences
                    (list (list :sent-num 1 :lang "sa"
                                :segs '((:num 1 :wylie "mohaḥ svabhāva" :uchen nil))
                                :translation nil :vocab nil :grammar nil))))))
    (should-not (string-match-p "\\\\tibfont[^a-z]*[ༀ-࿿]" org))
    (should (string-match-p "\\\\segno{1}mohaḥ svabhāva" org))))

;; ----------------------------------------------------------------------------
;; B3 — scope at point, file writing, command
;; ----------------------------------------------------------------------------

(defmacro tibetan-handout-test--in-source (&rest body)
  "Inside `--with-corpus': visit SRC (BUF current) for BODY."
  (declare (indent 0))
  `(let ((buf (find-file-noselect src)))
     (unwind-protect
         (with-current-buffer buf ,@body)
       (with-current-buffer buf (set-buffer-modified-p nil))
       (kill-buffer buf))))

(defun tibetan-handout-test--scope-at (regexp)
  "The handout scope with point on the line matching REGEXP."
  (goto-char (point-min))
  (re-search-forward regexp)
  (beginning-of-line)
  (tibetan-handout--scope-at-point))

(ert-deftest tibetan-handout-scope-at-point ()
  "Umfang wie bei C-c u A (§5.59 A1): Segment → sein Satz; Satz → Satz;
Section → ihre Sätze (+ Lopez-§ fürs Label); `* Tibetan Text' →
alle; in einer sent-Analysedatei → dieser Satz."
  (tibetan-handout-test--with-corpus
    (tibetan-handout-test--in-source
      (let ((s (tibetan-handout-test--scope-at "^\\*\\* Section §220")))
        (should (equal '(654 655) (plist-get s :sent-nums)))
        (should (equal "§220" (plist-get s :label)))
        (should (equal 220 (plist-get s :lopez)))
        (should (equal src (plist-get s :source))))
      (should (equal '(655) (plist-get (tibetan-handout-test--scope-at
                                        "^\\*\\*\\* Sentence 655")
                                       :sent-nums)))
      (let ((s (tibetan-handout-test--scope-at "^\\*\\*\\*\\* Segment 1971")))
        (should (equal '(654) (plist-get s :sent-nums)))
        (should (equal "Satz 654" (plist-get s :label))))
      (should (equal '(654 655 656)
                     (plist-get (tibetan-handout-test--scope-at
                                 "^\\* Tibetan Text")
                                :sent-nums))))
    (let ((buf (find-file-noselect (tibetan-sentence--filepath 654 folder src))))
      (unwind-protect
          (with-current-buffer buf
            (let ((s (tibetan-handout--scope-at-point)))
              (should (equal '(654) (plist-get s :sent-nums)))
              (should (equal (file-truename src)
                             (file-truename (plist-get s :source))))))
        (kill-buffer buf)))))

(ert-deftest tibetan-handout-build-writes-guarded-file ()
  "Build schreibt `handouts/<short>-par-220.org' neben die Quelle:
GENERATED-Marker, Werktitel aus #+TITLE, Lopez/W&M/DM/Working
Translation NIE (Poison-Lock wie §5.54), kein „Claude“.  Eine
vorhandene Datei OHNE Marker wird nie überschrieben; mit Marker
schon (Regenerieren)."
  (tibetan-handout-test--with-corpus
    (let* ((scope (list :source src :sent-nums '(654 655 656)
                        :label "§220" :lopez 220))
           (out (tibetan-handout-build scope "2026-10-09"))
           (text (with-temp-buffer (insert-file-contents out) (buffer-string))))
      (should (equal (expand-file-name "handouts/rgyan-par-220.org" dir) out))
      (should (string-prefix-p tibetan-handout-generated-marker text))
      (should (string-match-p "Klu sgrub dgongs rgyan} · §220" text))
      (dolist (poison '("LOPEZ POISON" "DM POISON" "WT POISON" "Claude"))
        (should-not (string-match-p poison text)))
      ;; Regenerieren überschreibt die generierte Datei …
      (should (equal out (tibetan-handout-build scope "2026-10-10")))
      (should (string-match-p "Stand 2026-10-10"
                              (with-temp-buffer (insert-file-contents out)
                                                (buffer-string))))
      ;; … eine handeigene Datei nie.
      (with-temp-file out (insert "* Meine eigene Fassung\n"))
      (should-error (tibetan-handout-build scope "2026-10-11")
                    :type 'user-error)
      (should (equal "* Meine eigene Fassung\n"
                     (with-temp-buffer (insert-file-contents out)
                                       (buffer-string)))))))

(ert-deftest tibetan-handout-output-names ()
  "Dateiname: Lopez-§ → par-NNN, ein Satz → sent-NNN, mehrere ohne §
→ sent-FIRST-LAST; immer mit dem Quell-Kurznamen (Mehrquellen-
Ordner kollidieren nicht, §5.23-Lektion)."
  (tibetan-handout-test--with-corpus
    (should (string-suffix-p "handouts/rgyan-sent-654.org"
                             (tibetan-handout--output-file
                              (list :source src :sent-nums '(654)))))
    (should (string-suffix-p "handouts/rgyan-sent-654-656.org"
                             (tibetan-handout--output-file
                              (list :source src :sent-nums '(654 655 656)))))))

(ert-deftest tibetan-handout-command-org-only-and-pdf ()
  "C-c u H: in der Quelle mit C-u nur die .org (kein LaTeX-Lauf, die
.org wird geöffnet); ohne Präfix exportiert und das PDF geöffnet.  IN
einer erzeugten Handout-.org exportiert C-c u H die Datei SO WIE SIE
IST (gespeichert) — Carstens Kürzungen vor dem Druck dürfen nie durch
Neu-Generieren verloren gehen."
  (tibetan-handout-test--with-corpus
    (let ((exported nil) (opened nil)
          (org-file (expand-file-name "handouts/rgyan-par-220.org" dir)))
      (cl-letf (((symbol-function 'tibetan-handout-export-pdf)
                 (lambda (org) (setq exported org)
                   (concat (file-name-sans-extension org) ".pdf")))
                ((symbol-function 'org-open-file)
                 (lambda (f &rest _) (setq opened f))))
        (tibetan-handout-test--in-source
          (goto-char (point-min))
          (re-search-forward "^\\*\\* Section §220")
          (save-window-excursion
            (tibetan-handout '(4))
            (should (file-exists-p org-file))
            (should-not exported)
            ;; Jetzt IN der Handout-.org: kürzen, C-c u H → Export der
            ;; bearbeiteten Datei, kein Neu-Generieren.
            (should (equal (file-truename org-file)
                           (file-truename (buffer-file-name))))
            (goto-char (point-max))
            (insert "\nMEINE KÜRZUNG\n")
            (tibetan-handout nil)
            (should (equal (file-truename org-file) (file-truename exported)))
            (should (string-match-p "MEINE KÜRZUNG"
                                    (with-temp-buffer
                                      (insert-file-contents org-file)
                                      (buffer-string))))
            (set-buffer-modified-p nil)
            (kill-buffer))
          ;; Aus der Quelle ohne Präfix: generieren + exportieren + öffnen.
          (setq exported nil opened nil)
          (tibetan-handout nil)
          (should (string-suffix-p "rgyan-par-220.org" exported))
          (should (string-suffix-p "rgyan-par-220.pdf" opened)))))))

(ert-deftest tibetan-handout-export-pdf-smoke ()
  "Echter LuaLaTeX-Lauf (nur wo lualatex + der Tibetisch-Font
vorhanden sind): die erzeugte .org wird zu einem PDF."
  (skip-unless (and (executable-find "lualatex")
                    (executable-find "luaotfload-tool")
                    (zerop (call-process "luaotfload-tool" nil nil nil
                                         "--find" tibetan-handout-tibetan-font))))
  (tibetan-handout-test--with-corpus
    (let* ((out (tibetan-handout-build
                 (list :source src :sent-nums '(654) :label "Satz 654")
                 "2026-10-09"))
           (pdf (tibetan-handout-export-pdf out)))
      (should (file-exists-p pdf))
      (should (string-suffix-p "rgyan-sent-654.pdf" pdf)))))

(provide 'tibetan-handout-test)
;;; tibetan-handout-test.el ends here
