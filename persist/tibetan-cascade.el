;;; tibetan-cascade.el --- CASCADE layout: sentence files with shad subsegments -*- lexical-binding: t -*-

;;; Commentary:
;;
;; CASCADE v2 (plan 2026-07-22, implementation started 2026-07-28):
;; for a document carrying `#+TIBETAN_LAYOUT: cascade' the sentence
;; file `sent-NNN-SHORT.org' is the ONLY persisted analysis artifact.
;; The shad-delimited units of the sentence live as nested subsegments
;; inside it (`* Subsegments' → `** Segment N', keyed by the source's
;; GLOBAL segment numbers), and every subsegment rendering is an
;; extracted ⟦N⟧-span of the whole-sentence translation — the
;; subsegment translation is always contained in the complete
;; sentence translation, by construction.
;;
;; The architectural point (preserve in commit messages): in cascade
;; mode NOTHING user-valuable is keyed to segment numbers — subsegment
;; shells are regenerable, so shad renumbering (the §5.26/§5.33 top
;; data-loss class) can no longer orphan anything.  Only sentence
;; numbers must stay stable.
;;
;; This module grows in stages:
;;   C1 (here)  — the pure shad-unit splitter.  The mode marker and
;;                `tibetan-analysis--cascade-p' predicate live in
;;                tibetan-analysis-claude.el beside --defer-mt-p.
;;   C2         — sent-file scaffold + subsegment subtree I/O +
;;                regenerate.
;;   C3         — sentence-level fire + response landing + span
;;                extraction into `*** Rendering'.
;;   C4         — dispatch/UX (open-at-segment, batches).
;;
;; Splitting at shads is DETERMINISTIC — mechanical, never wrong —
;; which is exactly why it is the subsegment generator: all linguistic
;; intelligence (main-verb recognition, verse grouping, speech frames)
;; stays at the sentence boundary.

;;; Code:

;; Declared SPECIAL here (defined in tibetan-analysis-persist.el):
;; `tibetan-cascade--scaffold' let-binds it for its renderer calls.
;; Without this declaration the let would create an invisible LEXICAL
;; shadow under lexical-binding — the `features'-shadow lesson.
(defvar tibetan-analysis--target-lang)
(defvar tibetan-analysis--claude-vocabulary-for-render)
;; Sanskrit-Kaskade C1 (2026-09-24): the source-language dispatch var
;; (defined in tibetan-analysis-claude.el) and the text-keyed word
;; analysis (defined in tibetan-sanskrit-reading.el) — both let-bound
;; by the scaffold/regenerate below; same shadow hazard as above.
(defvar tibetan-analysis--source-lang)
(defvar tibetan-sanskrit-reading--word-analysis)
;; T3 (§5.58): die textkeyed Particles-Dynamik der Glossentabellen
;; (definiert in tibetan-gloss-table.el) — vom Regenerate gebunden;
;; gleiche Shadow-Falle wie oben.
(defvar tibetan-gloss-table--claude-particles)
(defvar tibetan-sentence-claude--system-prompt-sanskrit)
(defvar tibetan-analysis-auto-regen-on-claude-arrival)
(declare-function tibetan-analysis--resolve-source-lang
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--sanitize-claude-body-stars
                  "tibetan-analysis-claude")
(declare-function tibetan-fresh-file-buffer "tibetan-utils")

;; The §184-handout gloss tables (Masterarbeit three-view plan,
;; 2026-09-15).  Soft — the emitter is fboundp-guarded and
;; emit-vs-omit is non-destructive; the require keeps interactive
;; and batch load-state aligned (the B0 lesson).
(require 'tibetan-gloss-table nil t)

;; B1 (§5.58, 2026-10-09): HARD require.  keep-l2 in
;; `tibetan-cascade--regenerate' reads every landed L2 body through
;; `tibetan-sentence--read-l2-body'; behind an fboundp probe that
;; read silently returned NOTHING in a batch that never loaded the
;; module, and the regenerate then threw away Translation / DM /
;; Vocabulary / Concept Notes / Word Analysis / Provided
;; Translations (B0 class — an fboundp probe is a LOAD-STATE probe
;; and must never choose between destructive and preserving
;; behaviour).  sentence-persist requires tibetan-cascade only at
;; call time (soft), so there is no load-time cycle.
(require 'tibetan-sentence-persist)

(defun tibetan-cascade-split-shad-units (text)
  "Split TEXT into its shad-terminated units.

Returns a list of strings whose CONCATENATION reproduces TEXT
exactly: each unit carries its terminating shad run — including
double shads `།།', the pecha-style spaced `། །', and any following
whitespace (so the next unit starts clean at its first content
character).  Text after the last shad, or text containing no shad at
all, forms a final (or only) unit — a fused segment like Khu-dbon's
seg-137 becomes one subsegment, never zero.

Recognised shads: ། (U+0F0D) and ༎ (U+0F0E).  Rarer marks (ter-shad
etc.) are treated as ordinary content — extend the character class
here if a corpus needs them.

Pure and deterministic; nil for nil / empty / whitespace-only input;
never signals."
  (when (and (stringp text)
             (not (string-empty-p (string-trim text))))
    (let ((units '())
          (start 0)
          (len (length text)))
      (while (< start len)
        (if (string-match
             "[།༎]+\\(?:[ \t\n]+[།༎]+\\)*[ \t\n]*" text start)
            (let ((end (match-end 0)))
              (push (substring text start end) units)
              (setq start end))
          ;; No further shad — the remainder is the final unit.
          (push (substring text start) units)
          (setq start len)))
      (nreverse units))))

;; ============================================================================
;; C2.1 — sent-file scaffold + create-file
;; ============================================================================

(defconst tibetan-cascade-rendering-placeholder
  "[Awaiting sentence translation…]"
  "Placeholder body of a subsegment's `*** Rendering' section.
Counts as needs-request: a subsegment whose Rendering still carries
this (or any `[…'-anchored placeholder) re-fires at SENTENCE level —
there is no per-segment fallback in cascade mode.")

(defun tibetan-cascade--extract-l2-body (content heading)
  "Body of `** HEADING' inside the renderer output CONTENT, or nil.
Bounds follow the §5.38-C1 discipline (stars-then-SPACE), so
markdown-bold body lines never truncate the section."
  (when (and content heading)
    (with-temp-buffer
      (insert content)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\* %s$" (regexp-quote heading)) nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                        (line-beginning-position)
                      (point-max)))
               (body (string-trim
                      (buffer-substring-no-properties start end))))
          (unless (string-empty-p body) body))))))

(defun tibetan-cascade--unit-has-shad-p (unit-text)
  "Non-nil when UNIT-TEXT carries a trailing shad run."
  (and unit-text (string-match-p "[།༎༏༐༑༔]\\s-*$" unit-text)))

(defun tibetan-cascade--renderings-list-body (segs)
  "LEGACY shape helper: one `- ⟦N⟧ placeholder' line per unit.
T4 (§5.58): der Scaffold emittiert keine `** Renderings'-Sektion
mehr — die Zeilen leben unter ihren Segment-Tabellen (siehe
`tibetan-cascade--gloss-tables-with-renderings').  Der Helfer
bleibt für Alt-Layout-Tests und als Zeilenform-Referenz."
  (mapconcat (lambda (seg)
               (format "- ⟦%d⟧ %s" (car seg)
                       tibetan-cascade-rendering-placeholder))
             segs "\n"))

(defun tibetan-cascade--gloss-tables-canonical (body)
  "BODY der `** Gloss Tables'-Sektion OHNE die ⟦N⟧-Maschinenzeilen.
T4 (§5.58): die Sequenzübersetzungen stehen unter den
Segment-Tabellen, also IM gehashten Body — ohne diese Kanonik
kippte jede Landung den :GENERATED_HASH:-Vergleich und fröre die
Tabellen dauerhaft als »handeditiert« ein.  Emitter UND
Edit-Erkennung hashen beide die kanonische Form; ein Zellen-Edit
ändert sie, eine Landung nicht.  Alt-Layout-Bodies (ohne
⟦N⟧-Zeilen) sind ihr eigener Kanon — alte Hashes bleiben gültig."
  (string-trim
   (replace-regexp-in-string "^- ⟦[0-9]+⟧ .*\n?" "" (or body ""))
   "\n+" "\n+"))

(defun tibetan-cascade--gloss-tables-with-renderings (segs tables)
  "Der `** Gloss Tables'-Body: je Einheit das `*** Segment N' aus
TABLES (dem Output von `tibetan-gloss-table-render-captioned`; nil
im degradierten Fall), gefolgt von der `- ⟦N⟧ …'-Zeile der Einheit
\(T4, §5.58: die Sequenzübersetzung steht UNTER ihrer Tabelle).
Jede Einheit bekommt Heading + Zeile auch ohne renderbare Tabelle —
die ⟦N⟧-Zeile ist der Maschinenschlüssel, auf den die Landung
schreibt."
  (let ((blocks '()))
    (when (and tables (stringp tables))
      (with-temp-buffer
        (insert tables)
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\*\\* Segment \\([0-9]+\\)$" nil t)
          (let ((n (string-to-number (match-string 1)))
                (start (line-beginning-position))
                (end (save-excursion
                       (forward-line 1)
                       (if (re-search-forward "^\\*\\*\\* Segment [0-9]+$"
                                              nil t)
                           (line-beginning-position)
                         (point-max)))))
            (push (cons n (string-trim-right
                           (buffer-substring-no-properties start end)
                           "\n+"))
                  blocks)))))
    (mapconcat
     (lambda (seg)
       (let* ((n (car seg))
              (blk (cdr (assq n blocks))))
         (concat (or blk (format "*** Segment %d" n))
                 "\n"
                 (format "- ⟦%d⟧ %s" n
                         tibetan-cascade-rendering-placeholder))))
     segs "\n\n")))

(defun tibetan-cascade--reading-section (segs)
  "The full `* Reading' section string for SEGS ((GLOBAL-NUM . TEXT)…).

§5.58 (S2, Reading-Class-Struktur): * Reading trägt NUR noch die
`** Gloss Tables' — je Einheit das `*** Segment N'-Heading, die
Drei-Zeilen-Tabelle (sofern renderbar) und die
⟦N⟧-Sequenzübersetzung darunter (T4).  Die kombinierte
`** Interlinear'-Zeile ist pensioniert: ihre Steinert-Links und
Glossen wandern in die Tabellen, das Prompt-Grounding wird aus den
Token-Strömen erzeugt (`tibetan-cascade--generated-reading-lines').

Der :GENERATED_HASH:-Drawer deckt die KANONISCHE Form (ohne die
⟦N⟧-Maschinenzeilen), damit Landungen den §5.54-Edit-Schutz nicht
kippen; Reset weiterhin: Sektion löschen → nächster Regenerate
emittiert frisch."
  (let ((tables
         (and (fboundp 'tibetan-gloss-table-render-captioned)
              (condition-case nil
                  (tibetan-gloss-table-render-captioned
                   segs
                   (and (boundp
                         'tibetan-analysis--claude-vocabulary-for-render)
                        tibetan-analysis--claude-vocabulary-for-render)
                   ;; Carsten's 2026-09-16 form: segment number as
                   ;; a foldable L3 HEADING (handout style).
                   3)
                (error nil)))))
    (let ((gt-body (tibetan-cascade--gloss-tables-with-renderings
                    segs tables)))
      (concat "* Reading\n"
              "** Gloss Tables\n"
              ":PROPERTIES:\n"
              (format ":GENERATED_HASH: %s\n"
                      (sha1 (tibetan-cascade--gloss-tables-canonical
                             gt-body)))
              ":END:\n"
              gt-body "\n\n"))))

(declare-function tibetan-segment-text "tibetan-enhanced-parser" (text))
(declare-function tibetan-extract-verbs-compound-aware
                  "tibetan-enhanced-display" (text words mwus))
(declare-function tibetan-analysis--render-sentence-tree
                  "tibetan-analysis-persist" (words verbs mwus))

(defun tibetan-cascade--read-gloss-tables (file)
  "FILE's `** Gloss Tables' state: (BODY . STORED-HASH), or nil.
BODY is the section body WITHOUT the :PROPERTIES: drawer, edge
newlines stripped (the hash canonicalization — the emitter hashes
the rendered string before appending its blank line); STORED-HASH
is the :GENERATED_HASH: value, nil for a legacy or hand-created
section.  nil when the file carries no `** Gloss Tables' under
`* Reading'."
  (when (and file (stringp file) (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Reading[ \t]*$" nil t)
        (let ((reading-end (save-excursion
                             (if (re-search-forward "^\\* " nil t)
                                 (line-beginning-position)
                               (point-max)))))
          (when (re-search-forward "^\\*\\* Gloss Tables[ \t]*$"
                                   reading-end t)
            (forward-line 1)
            (let (hash)
              (when (looking-at "^:PROPERTIES:$")
                (let ((drawer-end (save-excursion
                                    (re-search-forward "^:END:$"
                                                       reading-end t))))
                  (when drawer-end
                    (when (re-search-forward
                           "^:GENERATED_HASH: \\(.+\\)$" drawer-end t)
                      (setq hash (match-string 1)))
                    (goto-char drawer-end)
                    (forward-line 1))))
              (let* ((start (point))
                     (end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                              (line-beginning-position)
                            (point-max)))
                     (body (string-trim
                            (buffer-substring start end)
                            "\n+" "\n+")))
                (cons body hash)))))))))

(defun tibetan-cascade--gloss-tables-edited-p (state)
  "Non-nil when STATE ((BODY . STORED-HASH), from
`tibetan-cascade--read-gloss-tables') is a HAND-EDITED section:
non-empty body whose hash no longer matches the stored one — or a
section without any stored hash (legacy / hand-created counts as
edited; protection errs on the preserving side)."
  (and state
       (not (string-empty-p (car state)))
       (or (null (cdr state))
           ;; T4 (§5.58): Vergleich über die KANONISCHE Form — die
           ;; ⟦N⟧-Maschinenzeilen im Body (Landungen!) zählen nicht
           ;; als Edit; Alt-Layout-Bodies sind ihr eigener Kanon.
           (not (equal (sha1 (tibetan-cascade--gloss-tables-canonical
                              (car state)))
                       (cdr state))))))

(defun tibetan-cascade--restore-gloss-tables-in-buffer (state)
  "Replace or insert the `** Gloss Tables' section from STATE in
the current buffer — the edit-protection restore: Carsten's edited
tables win over the fresh render.  The stored hash (or its
absence) is re-emitted unchanged, so the mismatch persists and the
section stays protected on every later regenerate.  Reset story:
delete the whole section by hand → the next regenerate emits a
fresh generated one."
  (let ((block (concat "** Gloss Tables\n"
                       (when (cdr state)
                         (concat ":PROPERTIES:\n"
                                 ":GENERATED_HASH: " (cdr state) "\n"
                                 ":END:\n"))
                       (car state) "\n\n")))
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\* Reading[ \t]*$" nil t)
        (forward-line 1)
        (let ((reading-start (point))
              (reading-end (save-excursion
                             (if (re-search-forward "^\\* " nil t)
                                 (line-beginning-position)
                               (point-max)))))
          (if (re-search-forward "^\\*\\* Gloss Tables[ \t]*$"
                                 reading-end t)
              (let ((start (line-beginning-position))
                    (end (progn
                           (forward-line 1)
                           (if (re-search-forward "^\\*\\{1,2\\} "
                                                  reading-end t)
                               (line-beginning-position)
                             reading-end))))
                (delete-region start end)
                (goto-char start)
                (insert block))
            ;; Scaffold omitted the section (nothing rendered) —
            ;; the edited block still goes in as the FIRST Reading
            ;; child (the eb9b573 create-missing pattern).
            (goto-char reading-start)
            (insert block)))))))

(defun tibetan-cascade--extract-auto-sections (auto)
  "Zerlege den Auto-Renderer-Block AUTO in die §5.58-Slots.
Returns (:vocabulary B :concepts B :sentence-structure B
:particles-map B :claude-grammar B :buddhist-terms B :rest LIST) —
B jeweils der getrimmte Body oder nil, :rest die unbekannten
L2-Subtrees verbatim (preserve-by-default, §5.38-H2).  Der
Renderer bleibt unberührt (geteilt mit Two-File); die Kaskade hebt
seinen Output hier in ihre flache Struktur um: die ** Grammar-Hülle
wird in Partikelkarte / Claude Grammar / Buddhist Terms zerlegt,
** Translation / ** Provided Translations / ** DharmaMitra
Translation werden verworfen (eigene L1-Slots bzw. Scaffold-Sache)."
  (let ((out (list :rest nil)))
    (when (and auto (stringp auto))
      (with-temp-buffer
        (insert auto)
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\* \\(.+?\\)[ \t]*$" nil t)
          (let* ((heading (match-string 1))
                 (h-start (line-beginning-position))
                 (b-start (progn (forward-line 1) (point)))
                 (end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                          (line-beginning-position)
                        (point-max)))
                 (body (string-trim
                        (buffer-substring-no-properties b-start end))))
            (goto-char end)
            (pcase heading
              ("Claude Vocabulary"
               (plist-put out :vocabulary
                          (unless (string-empty-p body) body)))
              ("Concept Notes"
               (plist-put out :concepts
                          (unless (string-empty-p body) body)))
              ("Sentence Structure"
               (plist-put out :sentence-structure
                          (unless (string-empty-p body) body)))
              ("Grammar"
               ;; Die Hülle zerlegen: *** Particles → Partikelkarte,
               ;; *** Claude Grammar / *** Buddhist Terms heben.
               (with-temp-buffer
                 (insert body)
                 (goto-char (point-min))
                 (while (re-search-forward "^\\*\\*\\* \\(.+?\\)[ \t]*$"
                                           nil t)
                   (let* ((h3 (match-string 1))
                          (s3 (progn (forward-line 1) (point)))
                          (e3 (if (re-search-forward
                                   "^\\*\\{1,3\\} " nil t)
                                  (line-beginning-position)
                                (point-max)))
                          (b3 (string-trim
                               (buffer-substring-no-properties s3 e3))))
                     (goto-char e3)
                     (pcase h3
                       ("Particles"
                        (plist-put out :particles-map
                                   (unless (string-empty-p b3) b3)))
                       ("Claude Grammar"
                        (plist-put out :claude-grammar
                                   (unless (string-empty-p b3) b3)))
                       ("Buddhist Terms"
                        (plist-put out :buddhist-terms
                                   (unless (string-empty-p b3) b3))))))))
              ((or "Translation" "Claude Translation"
                   "Provided Translations" "DharmaMitra Translation")
               nil)
              (_
               (plist-put out :rest
                          (append
                           (plist-get out :rest
                                      )
                           (list (string-trim-right
                                  (buffer-substring-no-properties
                                   h-start end)))))))))))
    out))

(defun tibetan-cascade--analysis-body (auto sa-p segs)
  "Der flache `* Tibetan Analysis'-Body der §5.58-Struktur.
Reihenfolge: Sentence Structure (bo) · Claude Vocabulary · Claude
Grammar · Buddhist Terms (bo, nur bei Inhalt) · Partikelkarte (bo,
nur bei Inhalt) · Claude Particles (bo) · Concept Notes; unbekannte
Renderer-Sektionen verbatim hinten.  AUTO ist der (geteilte)
Renderer-Output oder nil (sa / degradiert)."
  (let* ((x (tibetan-cascade--extract-auto-sections auto))
         (per-unit (and (not sa-p)
                        (tibetan-cascade--sentence-structure-body segs)))
         (parts '()))
    (cl-flet ((sec (heading body)
                (push (format "** %s\n%s\n" heading
                              (if (and body (not (string-empty-p body)))
                                  (concat (string-trim-right body) "\n")
                                ""))
                      parts)))
      (when (not sa-p)
        (let ((ss (or per-unit (plist-get x :sentence-structure))))
          (when ss (sec "Sentence Structure" ss))))
      (sec "Claude Vocabulary"
           (or (plist-get x :vocabulary) "[Awaiting Claude…]"))
      (sec "Claude Grammar" (plist-get x :claude-grammar))
      (when (and (not sa-p) (plist-get x :buddhist-terms))
        (sec "Buddhist Terms" (plist-get x :buddhist-terms)))
      (when (and (not sa-p) (plist-get x :particles-map))
        (sec "Partikelkarte" (plist-get x :particles-map)))
      (unless sa-p
        (sec "Claude Particles" nil))
      (sec "Concept Notes"
           (or (plist-get x :concepts) "[Awaiting Claude…]"))
      (dolist (r (plist-get x :rest))
        (push (concat r "\n") parts)))
    (mapconcat #'identity (nreverse parts) "\n")))

(defun tibetan-cascade--sentence-structure-body (segs)
  "Per-shad-unit verb-first trees for the `** Sentence Structure'
section (R10): each unit of SEGS ((GLOBAL-NUM . TEXT)…) is parsed
SEPARATELY under a `Unit K — Segment N' header — parsing the joined
sentence produced fused tokens across shads and hallucinated main
verbs (the live sent-001 evidence behind R1).  Returns nil when the
tree machinery is unavailable or no unit parses (the caller keeps
the whole-sentence fallback body)."
  ;; 2026-09-16 (Carsten's SS185 review): the tabular form —
  ;; Übersicht + Detailtabelle je Segment — replaces the flat
  ;; per-unit trees when the renderer is available.
  (or (and (fboundp 'tibetan-analysis--render-structure-tables)
           (condition-case nil
               (tibetan-analysis--render-structure-tables segs)
             (error nil)))
      (tibetan-cascade--sentence-structure-body-trees segs)))

(defun tibetan-cascade--sentence-structure-body-trees (segs)
  "Legacy per-unit tree text for SEGS — the pre-2026-09-16 form,
kept as the fallback when the tabular renderer is unavailable."
  (when (and (fboundp 'tibetan-segment-text)
             (fboundp 'tibetan-extract-verbs-compound-aware)
             (fboundp 'tibetan-analysis--render-sentence-tree))
    (let ((ordinal 0) blocks)
      (dolist (seg segs)
        (cl-incf ordinal)
        (condition-case nil
            (let* ((text (cdr seg))
                   (words (tibetan-segment-text text))
                   (verbs (and words
                               (tibetan-extract-verbs-compound-aware
                                text words nil)))
                   (tree (and words verbs
                              (tibetan-analysis--render-sentence-tree
                               words verbs nil))))
              (when (and tree
                         (not (string-empty-p (string-trim tree)))
                         (not (string-prefix-p "[No clause"
                                               (string-trim tree))))
                (push (format "Unit %d — Segment %d\n%s"
                              ordinal (car seg)
                              (string-trim-right tree))
                      blocks)))
          (error nil)))
      (when blocks
        (mapconcat #'identity (nreverse blocks) "\n\n")))))

(defun tibetan-cascade--scaffold (sent-num segs source-file)
  "Return the full cascade sent-file body for SENT-NUM (a string).
SEGS is an ordered list of (GLOBAL-SEG-NUM . TEXT) conses — the
sentence's shad units as they appear in the source.  SOURCE-FILE is
the absolute source path (nil tolerated: no #+SOURCE header).

Layout: user slots on top, `* Tibetan Analysis' (sentence-level —
rendered through the compressed sentence renderer when available),
`* Subsegments' with one `** Segment N' subtree per unit, and
`* Footnotes' at the bottom.  The `#+TIBETAN_LAYOUT: cascade' header
marks the file for every reader (§2.8: explicit, never sniffed)."
  (let* ((source-name (and source-file
                           (file-name-nondirectory source-file)))
         ;; Renderer calls below (generate-content per subsegment, the
         ;; sentence auto-renderer) resolve the curated Resources
         ;; wordlist through `tibetan-find-resources-folder', which
         ;; falls back to `default-directory' in headless runs
         ;; (2026-06-03 corpus-wipe lesson).  Pin it to the SOURCE's
         ;; directory so a batch caller's alien cwd cannot silently
         ;; drop every ★ gloss (V3 refresh regression, 2026-08-10).
         (default-directory (if source-file
                                (file-name-directory
                                 (expand-file-name source-file))
                              default-directory))
         ;; W2 (2026-08-11): the bilingual `DE // EN' gloss selection
         ;; (Pass 5c) reads the dynamic `tibetan-analysis--target-lang';
         ;; generate-content derives it from the CURRENT BUFFER's
         ;; source, which a temp-buffer scaffold doesn't have — bind it
         ;; from the source header here, or the Portfolio's curated
         ;; German glosses render English-only.
         (tibetan-analysis--target-lang
          (or (and source-file
                   (fboundp 'tibetan-analysis--read-source-metadata)
                   (condition-case nil
                       (plist-get (tibetan-analysis--read-source-metadata
                                   source-file)
                                  :target-lang)
                     (error nil)))
              (and (boundp 'tibetan-analysis--target-lang)
                   tibetan-analysis--target-lang)))
         ;; Sanskrit-Kaskade C1 (2026-09-24): bind the source language
         ;; from the SOURCE document's metadata — the reading/gloss-
         ;; table dispatch (B4) keys on it.  Metadata-only binding =
         ;; batch/interactive parity by construction (§5.53).
         (tibetan-analysis--source-lang
          (and source-file
               (fboundp 'tibetan-analysis--resolve-source-lang)
               (condition-case nil
                   (tibetan-analysis--resolve-source-lang source-file)
                 (error nil))))
         (sa-p (equal tibetan-analysis--source-lang "sa"))
         (date (format-time-string "%Y-%m-%d"))
         (tibetan-text (mapconcat #'cdr segs ""))
         (hash (and (fboundp 'tibetan-sentence--compute-hash)
                    (condition-case nil
                        (tibetan-sentence--compute-hash tibetan-text)
                      (error nil))))
         (segs-csv (mapconcat (lambda (s) (number-to-string (car s)))
                              segs ", ")))
    (with-temp-buffer
      (insert (format "#+TITLE: Sentence %d Analysis\n" sent-num))
      (insert "#+STARTUP: showall\n")
      (insert "#+OPTIONS: toc:nil num:nil\n")
      (insert "#+TIBETAN_LAYOUT: cascade\n")
      ;; C1: mirror the source language into the sent file so the
      ;; dependency-free textual probes (B0 class) work without the
      ;; source, and the metadata resolver prefers the file itself.
      (when sa-p
        (insert "#+SOURCE_LANG: sa\n"))
      (when source-name
        (insert (format
                 "#+SOURCE: [[file:../%s::*Sentence %d][%s / Sentence %d]]\n"
                 source-name sent-num source-name sent-num)))
      (insert (format "#+SEGMENTS: %s\n" segs-csv))
      (when hash
        (insert (format "#+TIBETAN_HASH: %s\n" hash)))
      (insert (format "#+CREATED: %s\n" date))
      (insert (format "#+LAST_ANALYZED: %s\n" date))
      (insert "\n")
      ;; §5.58 (S2, Reading-Class-Struktur): die Satz-/Vers-
      ;; Übersetzung steht GANZ OBEN als L1-Slot; * Tibetan Text
      ;; entfällt ersatzlos (Hash/SEGMENTS kommen weiter aus den
      ;; Quell-Segmenten, das Tibetische lebt in den Tabellen).
      (insert "* Translation\n[Requesting translation...]\n\n")
      ;; R8/T4: the Reading block — Gloss Tables with the per-unit
      ;; ⟦N⟧ sequence-translation lines (the Interlinear layer is
      ;; retired with S2; prompt grounding is generated from the
      ;; token streams instead).
      (insert (tibetan-cascade--reading-section segs))
      ;; Flat sentence-level analysis (§5.58): Sentence Structure /
      ;; Claude Vocabulary / Claude Grammar / [Buddhist Terms] /
      ;; [Partikelkarte] / Claude Particles / Concept Notes — the
      ;; shared renderer's output is decomposed, the ** Grammar hull
      ;; and the nested Provided Translations are gone.
      (insert "* Tibetan Analysis\n")
      (insert ":PROPERTIES:\n:GENERATED: t\n:END:\n\n")
      ;; C1: no Tibetan auto-analysis over IAST — sa gets the
      ;; minimal slot scaffold; the landing writers fill it.
      (let ((auto (and (not sa-p)
                       (fboundp 'tibetan-sentence--render-auto-analysis)
                       (condition-case nil
                           (tibetan-sentence--render-auto-analysis
                            tibetan-text)
                         (error nil)))))
        (insert (tibetan-cascade--analysis-body auto sa-p segs))
        (unless (bolp) (insert "\n")))
      ;; §5.58: * Provided Translations ist jetzt L1 — DM-Slot (und
      ;; später Lopez/W&M) leben hier, von keep-l1 als Subtree
      ;; preserved.
      (insert "\n* Provided Translations\n"
              "** DharmaMitra Translation\n[Awaiting DharmaMitra…]\n\n")
      (insert "* Working Translation\n\n\n")
      (insert "* My Notes\n\n\n")
      (insert "* Footnotes\n\n")
      ;; DEFER-MT VISIBILITY (2026-07-30): on a defer-MT document the
      ;; generic placeholders read as a failure — say WHY they are
      ;; empty.  The defer text keeps the `[Awaiting' prefix, so every
      ;; needs-request recognizer still fires once the header is gone.
      (when (and source-file
                 (fboundp 'tibetan-analysis--defer-mt-p)
                 (fboundp 'tibetan-analysis--defer-mt-rewrite-placeholders)
                 (tibetan-analysis--defer-mt-p source-file))
        (tibetan-analysis--defer-mt-rewrite-placeholders))
      (buffer-string))))

(defun tibetan-cascade--create-file (sent-num segs source-file)
  "Write the cascade sent file for SENT-NUM; return its path.
SEGS as in `tibetan-cascade--scaffold'.  The path comes from the
suffix-aware `tibetan-sentence--filepath' (cascade files KEEP the
`sent-NNN-SHORT.org' name — every resolver/glob/batch works
unchanged); falls back to a bare `sent-NNN.org' beside
SOURCE-FILE when the sentence module is not loaded."
  (let* ((folder (file-name-as-directory
                  (expand-file-name
                   "analysis" (file-name-directory source-file))))
         (filepath (if (fboundp 'tibetan-sentence--filepath)
                       ;; Explicit FOLDER: the sentence module's default
                       ;; derivation needs the source BUFFER current,
                       ;; which batch/cascade callers don't guarantee.
                       (tibetan-sentence--filepath sent-num folder
                                                   source-file)
                     (expand-file-name (format "sent-%03d.org" sent-num)
                                       folder)))
         (body (tibetan-cascade--scaffold sent-num segs source-file)))
    (make-directory (file-name-directory filepath) t)
    (with-temp-file filepath
      (insert body))
    filepath))

;; ============================================================================
;; C2.2 — subsegment subtree I/O (keyed by GLOBAL segment number)
;; ============================================================================

(defun tibetan-cascade--subsegment-bounds (seg-num)
  "In the current buffer: (START . END) of `** Segment SEG-NUM' under
`* Subsegments', or nil.  END stops at the next L1/L2 heading (§5.38-C1
stars-then-space) or at the * Subsegments region's end."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Subsegments$" nil t)
      (let ((limit (save-excursion
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
        (when (re-search-forward
               (format "^\\*\\* Segment %d$" seg-num) limit t)
          (let ((start (line-beginning-position))
                (end (if (re-search-forward "^\\*\\{1,2\\} " limit t)
                         (line-beginning-position)
                       limit)))
            (cons start end)))))))

(defun tibetan-cascade--subsegment-numbers (file)
  "Ordered list of GLOBAL segment numbers under FILE's * Subsegments.
nil for nil / missing / non-cascade files; never signals."
  (when (and file (stringp file) (file-exists-p file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward "^\\* Subsegments$" nil t)
            (let ((limit (save-excursion
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max))))
                  (nums '()))
              (while (re-search-forward
                      "^\\*\\* Segment \\([0-9]+\\)$" limit t)
                (push (string-to-number (match-string 1)) nums))
              (nreverse nums))))
      (error nil))))

(defun tibetan-cascade--read-subsegment-section (file seg-num heading)
  "Body of `*** HEADING' inside FILE's `** Segment SEG-NUM' subtree.
Trimmed string, or nil when the subsegment or heading is absent /
the body is empty.  Placeholders are returned verbatim — use
`tibetan-cascade--subsegment-rendering-needs-request-p' for gating."
  (when (and file (stringp file) (file-exists-p file) heading)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (let ((bounds (tibetan-cascade--subsegment-bounds seg-num)))
            (when bounds
              (save-restriction
                (narrow-to-region (car bounds) (cdr bounds))
                (goto-char (point-min))
                (when (re-search-forward
                       (format "^\\*\\*\\* %s$" (regexp-quote heading))
                       nil t)
                  (forward-line 1)
                  (let* ((start (point))
                         (end (if (re-search-forward "^\\*\\{1,3\\} " nil t)
                                  (line-beginning-position)
                                (point-max)))
                         (body (string-trim
                                (buffer-substring-no-properties
                                 start end))))
                    (unless (string-empty-p body) body)))))))
      (error nil))))

(defun tibetan-cascade--write-subsegment-section-in-buffer
    (seg-num heading body)
  "Buffer-local core of `tibetan-cascade--write-subsegment-section'.
Replaces the body of `*** HEADING' inside the `** Segment SEG-NUM'
subtree of the CURRENT buffer.  Returns t when replaced."
  (let ((bounds (tibetan-cascade--subsegment-bounds seg-num))
        (done nil))
    (when bounds
      (save-restriction
        (narrow-to-region (car bounds) (cdr bounds))
        (goto-char (point-min))
        (when (re-search-forward
               (format "^\\*\\*\\* %s$" (regexp-quote heading))
               nil t)
          (forward-line 1)
          (let ((start (point))
                (end (if (re-search-forward "^\\*\\{1,3\\} " nil t)
                         (line-beginning-position)
                       (point-max))))
            (delete-region start end)
            (goto-char start)
            (insert (string-trim-right body) "\n\n")
            (setq done t)))))
    done))

(defun tibetan-cascade--write-subsegment-section (file seg-num heading body)
  "Replace the body of `*** HEADING' in FILE's `** Segment SEG-NUM'.
Returns t on success; nil (file untouched) when the subsegment or
heading is absent.  BODY is inserted verbatim — the C3 landing path
sanitizes Claude-derived text (line-leading `*', §5.28 class) BEFORE
calling this primitive."
  (when (and file (stringp file) (file-exists-p file) heading body)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (when (tibetan-cascade--write-subsegment-section-in-buffer
                 seg-num heading body)
            (write-region (point-min) (point-max) file nil 'silent)
            t))
      (error nil))))

;; ============================================================================
;; C2.3 — regenerate with preservation (the §5.26 discipline)
;; ============================================================================

(defconst tibetan-cascade--known-l1-sections
  '("My Notes" "Working Translation" "Tibetan Text" "Reading"
    "Translation" "Provided Translations"
    "Tibetan Analysis" "Subsegments" "Footnotes")
  "The L1 headings the cascade scaffold owns.  Anything else found in
an existing file is preserved verbatim across regenerate
\(§5.38-H2: preserve-by-default, never a whitelist wipe).

R8: \"Subsegments\" STAYS listed although the scaffold no longer
emits it — it is OWNED-LEGACY, so regenerating an old file DROPS
the retired tree (its renderings having been preserved through the
dual-format primitives) instead of re-appending it verbatim as an
unknown section.  Preserve-mode reanalyze of an old file is thereby
the migration.  §5.58 (S2): \"Translation\" und \"Provided
Translations\" sind neue OWNED-Slots (slot-bewusst restauriert);
\"Tibetan Text\" ist jetzt OWNED-LEGACY — der Scaffold emittiert
ihn nicht mehr, das Regenerate droppt ihn (der Text lebt in den
Quell-Segmenten und den Tabellen).")

(defun tibetan-cascade--read-l1-body (file heading)
  "Trimmed body of `* HEADING' in FILE (bounded at the next L1
heading, so the user's own sub-structure inside survives), or nil
when absent / empty."
  (when (and file (stringp file) (file-exists-p file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^\\* %s$" (regexp-quote heading)) nil t)
            (forward-line 1)
            (let* ((start (point))
                   (end (if (re-search-forward "^\\* " nil t)
                            (line-beginning-position)
                          (point-max)))
                   (body (string-trim
                          (buffer-substring-no-properties start end))))
              (unless (string-empty-p body) body))))
      (error nil))))

(defun tibetan-cascade--read-l3-body (file heading)
  "Trimmed body of the (unique) `*** HEADING' in FILE, or nil.
Used for the sentence-level `*** Claude Grammar' — subsegments never
carry that heading, so a file-wide search is unambiguous."
  (when (and file (stringp file) (file-exists-p file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^\\*\\*\\* %s$" (regexp-quote heading)) nil t)
            (forward-line 1)
            (let* ((start (point))
                   (end (if (re-search-forward "^\\*\\{1,3\\} " nil t)
                            (line-beginning-position)
                          (point-max)))
                   (body (string-trim
                          (buffer-substring-no-properties start end))))
              (unless (or (string-empty-p body)
                          (string-match-p "\\`\\[Awaiting" body))
                body))))
      (error nil))))

(defun tibetan-cascade--collect-unknown-l1-sections (file)
  "List of verbatim L1 subtrees in FILE whose headings the scaffold
does not own (`tibetan-cascade--known-l1-sections')."
  (when (and file (stringp file) (file-exists-p file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (let ((subtrees '()))
            (while (re-search-forward "^\\* \\(.+\\)$" nil t)
              (let ((heading (string-trim (match-string 1)))
                    (start (line-beginning-position)))
                (unless (member heading tibetan-cascade--known-l1-sections)
                  (let ((end (save-excursion
                               (if (re-search-forward "^\\* " nil t)
                                   (line-beginning-position)
                                 (point-max)))))
                    (push (buffer-substring-no-properties start end)
                          subtrees)))))
            (nreverse subtrees)))
      (error nil))))

(defun tibetan-cascade--set-body-in-buffer (level heading body)
  "Replace the body of the first LEVEL-star HEADING in the current
buffer (skipping a :PROPERTIES: drawer; bounded at the next heading
of level ≤ LEVEL, so a subtree body keeps its children).  Returns t
when replaced."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^\\*\\{%d\\} %s$" level (regexp-quote heading)) nil t)
      (forward-line 1)
      (when (looking-at "^:PROPERTIES:$")
        (when (re-search-forward "^:END:$" nil t)
          (forward-line 1)))
      (let ((start (point))
            (end (if (re-search-forward
                      (format "^\\*\\{1,%d\\} " level) nil t)
                     (line-beginning-position)
                   (point-max))))
        (delete-region start end)
        (goto-char start)
        (insert (string-trim-right body) "\n\n")
        t))))

(defun tibetan-cascade--insert-l2-in-analysis (heading body)
  "HEADING als `** '-Sektion mit BODY ans ENDE von `* Tibetan
Analysis' im aktuellen Buffer einsetzen (S2, §5.58).  Der alte
Anlege-Anker »vor * Footnotes« ist mit der neuen L1-Ordnung falsch
— zwischen Analysis und Footnotes liegen jetzt Provided
Translations / Working Translation / My Notes, ein dort angelegter
Slot landete im falschen Elternteil."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^\\* Tibetan Analysis$" nil t)
        (progn
          (forward-line 1)
          (if (re-search-forward "^\\* " nil t)
              (goto-char (line-beginning-position))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))))
      (goto-char (point-max))
      (unless (bolp) (insert "\n")))
    (insert "** " heading "\n"
            (string-trim-right body) "\n\n")))

(defun tibetan-cascade--provided-translations-rest (filepath)
  "Der preservierte `Provided Translations'-Body OHNE den DM- und
den Claude-Particles-Subtree, aus der L1- (neu) oder L2-Position
\(alt), oder nil.  DM wird separat komponiert (eigener Slot unter
* Provided Translations); *** Claude Particles zieht nach
** Claude Particles um (S2) — beide dürfen nicht als PT-Rest
dupliziert zurückkehren.  Was bleibt, sind Lopez/W&M und
Hand-Einträge: verbatim erhalten."
  (let ((body (or (tibetan-cascade--read-l1-body
                   filepath "Provided Translations")
                  (tibetan-sentence--read-l2-body
                   filepath "Provided Translations"))))
    (when body
      (with-temp-buffer
        (insert body)
        ;; DM-Subtree (nur neue Dateien tragen ihn im PT-Body).
        (goto-char (point-min))
        (when (re-search-forward "^\\*\\* DharmaMitra Translation$" nil t)
          (let ((start (line-beginning-position))
                (end (progn (forward-line 1)
                            (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                                (line-beginning-position)
                              (point-max)))))
            (delete-region start end)))
        ;; Claude-Particles-Subtree (Alt-Layout).
        (goto-char (point-min))
        (when (re-search-forward "^\\*\\*\\* Claude Particles$" nil t)
          (let ((start (line-beginning-position))
                (end (progn (forward-line 1)
                            (if (re-search-forward "^\\*\\{1,3\\} " nil t)
                                (line-beginning-position)
                              (point-max)))))
            (delete-region start end)))
        (let ((rest (string-trim (buffer-string))))
          (unless (string-empty-p rest) rest))))))

(defun tibetan-cascade--regenerate (filepath sent-num segs source-file)
  "Regenerate FILEPATH's deterministic sections; preserve everything
user-valuable.  PRESERVE → REBUILD (via `tibetan-cascade--scaffold')
→ RESTORE, the §5.18 sentence pattern.

§5.58 (S2): die Restores sind SLOT-BEWUSST und heben Alt-Layout-
Inhalte zugleich in die neue Struktur (das Regenerate IST die
Migration): Translation (L2 alt / L1 neu, via Dual-Read) → L1-Slot;
Claude Vocabulary / Claude Grammar / Claude Particles / Concept
Notes (alle Positionen, placeholder-gefiltert via
`tibetan-analysis--read-claude-sections') → ihre flachen L2-Slots
in * Tibetan Analysis (fehlende Headings werden am Analysis-ENDE
angelegt, nicht mehr vor * Footnotes); Word Analysis ebenso; der
* Provided-Translations-Body wird KOMPONIERT (DM-Slot mit
preserviertem Body samt :LAST_TRANSLATED:-Drawer, danach der
PT-Rest ohne DM/Particles-Duplikate).  Dazu wie gehabt: die drei
User-L1-Slots, populierte ⟦N⟧-Renderings der noch vorhandenen
Segmente, editierte Gloss Tables (§5.54-Hash, T4-kanonisch) und
jede UNBEKANNTE L1-Sektion verbatim (§5.38-H2).  Placeholders
regenerate freshly.  Idempotent modulo LAST_ANALYZED.  Returns
FILEPATH."
  (let* ((keep-l1
          (cl-remove-if-not
           #'cdr
           (mapcar (lambda (h)
                     (cons h (tibetan-cascade--read-l1-body filepath h)))
                   '("My Notes" "Working Translation" "Footnotes"))))
         ;; B1 (§5.58): UNCONDITIONAL reads — tibetan-sentence-persist
         ;; ist hartes require; S1: der Sections-Leser ist dual-
         ;; positionell und placeholder-gefiltert.
         (claude (tibetan-analysis--read-claude-sections filepath))
         (keep-dm (tibetan-sentence--read-l2-body
                   filepath "DharmaMitra Translation"))
         (keep-word-analysis (tibetan-sentence--read-l2-body
                              filepath "Word Analysis"))
         (keep-pt-rest (tibetan-cascade--provided-translations-rest
                        filepath))
         ;; R7: dual-format preserve — new-layout ⟦N⟧ lines or legacy
         ;; subtrees, whichever the file carries.
         (renderings
          (cl-loop for n in (tibetan-cascade--rendering-numbers filepath)
                   when (and (assq n segs)
                             (not (tibetan-cascade--rendering-needs-request-p
                                   filepath n)))
                   collect (cons n (tibetan-cascade--read-rendering
                                    filepath n))))
         ;; Edit protection (Carsten's 2026-09-15 decision): a
         ;; `** Gloss Tables' section he has EDITED (body no longer
         ;; matches its :GENERATED_HASH:) is preserved verbatim —
         ;; his decision layer; only a still-generated section is
         ;; refreshed by the scaffold.
         (edited-gloss-tables
          (let ((state (tibetan-cascade--read-gloss-tables filepath)))
            (and (tibetan-cascade--gloss-tables-edited-p state) state)))
         (unknown (tibetan-cascade--collect-unknown-l1-sections filepath)))
    (with-temp-buffer
      ;; C-für-Cascade (2026-09-15): render the Reading lines with
      ;; the file's own preserved Claude Vocabulary in scope, so
      ;; `tibetan-reading--gloss' (and the Gloss Table's Claude-POS
      ;; tier) can prefer the context glosses over dictionary
      ;; first-senses.
      (let ((tibetan-analysis--claude-vocabulary-for-render
             (and (fboundp 'tibetan-analysis--claude-render-vars)
                  (plist-get
                   (tibetan-analysis--claude-render-vars
                    (list :vocabulary (plist-get claude :vocabulary)))
                   :vocabulary)))
            ;; T3 (§5.58): die preservierten Claude Particles,
            ;; segment-gruppiert geparst und auf UNIT-TEXT gekeyed —
            ;; die Converb-Funktionen (CONV:nas (seq.)) erreichen
            ;; Zeile 3 der Tabellen (§5.57-Word-Analysis-Muster).
            (tibetan-gloss-table--claude-particles
             (when (fboundp 'tibetan-analysis--parse-claude-particles-by-segment)
               (let ((groups (tibetan-analysis--parse-claude-particles-by-segment
                              (plist-get claude :particles))))
                 (when groups
                   (cl-loop for (n . text) in segs
                            for g = (or (cdr (assq n groups))
                                        ;; flache Alt-Form: nur bei
                                        ;; Einzel-Segment eindeutig.
                                        (and (= 1 (length segs))
                                             (cdr (assq nil groups))))
                            when g
                            collect (cons (string-trim text) g))))))
            ;; C1 (2026-09-24): the preserved `** Word Analysis'
            ;; body, parsed and re-keyed by UNIT TEXT — the Sanskrit
            ;; gloss tables materialize from it.
            (tibetan-sanskrit-reading--word-analysis
             (when (fboundp 'tibetan-sanskrit-reading-parse-word-analysis)
               (let ((parsed (tibetan-sanskrit-reading-parse-word-analysis
                              keep-word-analysis)))
                 (when parsed
                   (cl-loop for (n . text) in segs
                            for entry = (assq n parsed)
                            when entry
                            collect (cons (string-trim text)
                                          (cdr entry))))))))
        (insert (tibetan-cascade--scaffold sent-num segs source-file)))
      (when edited-gloss-tables
        (tibetan-cascade--restore-gloss-tables-in-buffer
         edited-gloss-tables))
      (dolist (kv keep-l1)
        (tibetan-cascade--set-body-in-buffer 1 (car kv) (cdr kv)))
      ;; S2: Translation → der L1-Slot (Dual-Read hat alt L2 / neu L1
      ;; bereits vereinheitlicht gelesen).
      (when (plist-get claude :translation)
        (tibetan-cascade--set-body-in-buffer
         1 "Translation" (plist-get claude :translation)))
      ;; S2: die flachen Analysis-Slots; fehlt ein Heading (sa,
      ;; degradiert), wird es am ENDE von * Tibetan Analysis angelegt
      ;; (eb9b573-Muster, neuer Anker).
      (dolist (slot '((:vocabulary . "Claude Vocabulary")
                      (:grammar . "Claude Grammar")
                      (:particles . "Claude Particles")
                      (:concepts . "Concept Notes")))
        (let ((body (plist-get claude (car slot))))
          (when body
            (unless (tibetan-cascade--set-body-in-buffer
                     2 (cdr slot) body)
              (tibetan-cascade--insert-l2-in-analysis
               (cdr slot) body)))))
      (when keep-word-analysis
        (unless (tibetan-cascade--set-body-in-buffer
                 2 "Word Analysis" keep-word-analysis)
          (tibetan-cascade--insert-l2-in-analysis
           "Word Analysis" keep-word-analysis)))
      ;; S2: * Provided Translations komponieren — DM-Slot (Body samt
      ;; Drawer preserved) + PT-Rest (Lopez/W&M, Hand-Einträge; ohne
      ;; DM-/Particles-Duplikate).
      (tibetan-cascade--set-body-in-buffer
       1 "Provided Translations"
       (concat "** DharmaMitra Translation\n"
               (string-trim-right
                (or keep-dm "[Awaiting DharmaMitra…]"))
               "\n"
               (when keep-pt-rest
                 (concat "\n" (string-trim-right keep-pt-rest) "\n"))))
      (dolist (r renderings)
        (when (cdr r)
          ;; R7: dual-format restore into whatever layout the
          ;; scaffold just emitted.
          (tibetan-cascade--write-rendering-in-buffer
           (car r) (cdr r))))
      (dolist (u unknown)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (string-trim-right u) "\n\n"))
      (write-region (point-min) (point-max) filepath nil 'silent))
    filepath))

(defun tibetan-cascade--subsegment-rendering-needs-request-p (file seg-num)
  "Non-nil when SEG-NUM's `*** Rendering' still needs the sentence fire.
Missing body, the creation placeholder, or a failure/missing stub all
count.  Deliberately NOT `[`-anchored wholesale: a real extracted span
may open with an editorial bracket (`[He] spoke…' — the §5.40 lesson),
so only the known machine prefixes gate."
  (let ((body (tibetan-cascade--read-subsegment-section
               file seg-num "Rendering")))
    (or (null body)
        (string-match-p "\\`\\[Awaiting" body)
        (string-match-p "\\`\\[Claude" body)
        (string-match-p "\\`\\[Requesting" body))))

;; ============================================================================
;; R5 — dual-format rendering I/O (READING VIEW redesign, 2026-08-12)
;;
;; New format: `- ⟦N⟧ body' lines inside `* Reading' / `** Renderings'.
;; Every primitive tries the new format FIRST and falls back to the
;; legacy `** Segment N' / `*** Rendering' subtree — old and new files
;; are equally servable, which is the whole migration mechanism: the
;; landing/regenerate layers switch to these primitives while the
;; scaffold still emits the old layout (R8 flips it last).
;; ============================================================================

(defun tibetan-cascade--renderings-region ()
  "Bounds (START . END) of the region holding the `- ⟦N⟧ …' lines:
the whole `* Reading' section body, or nil.

T4 (§5.58): die Zeilen leben unter ihren Segment-Tabellen in
`** Gloss Tables'; Alt-Layout-Dateien tragen sie unter
`** Renderings' — beides liegt in `* Reading', und innerhalb der
Sektion matchen NUR Maschinenzeilen das `- ⟦N⟧ '-Zeilenformat
\(Translation-Spans und Nutzernotizen leben außerhalb von
* Reading).  Die weite Region ist damit zugleich das Dual-Format:
ein Leser/Writer-Pfad für alt und neu."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Reading[ \t]*$" nil t)
      (forward-line 1)
      (let ((start (point))
            (end (if (re-search-forward "^\\* " nil t)
                     (line-beginning-position)
                   (point-max))))
        (cons start end)))))

(defun tibetan-cascade--rendering-line-re (seg-num)
  "Anchored regex for SEG-NUM's rendering line; body in group 1."
  (format "^- ⟦%d⟧ \\(.*\\)$" seg-num))

(defun tibetan-cascade--read-rendering (file seg-num)
  "SEG-NUM's rendering body in FILE, or nil.
New `- ⟦N⟧' line first; legacy `*** Rendering' subtree fallback."
  (when (and file (stringp file) (file-exists-p file) seg-num)
    (or (with-temp-buffer
          (insert-file-contents file)
          (let ((region (tibetan-cascade--renderings-region)))
            (when region
              (goto-char (car region))
              (when (re-search-forward
                     (tibetan-cascade--rendering-line-re seg-num)
                     (cdr region) t)
                (let ((body (string-trim (match-string 1))))
                  (unless (string-empty-p body) body))))))
        (tibetan-cascade--read-subsegment-section file seg-num
                                                  "Rendering"))))

(defun tibetan-cascade--write-rendering-in-buffer (seg-num body)
  "Replace SEG-NUM's rendering in the CURRENT buffer with BODY.
BODY is normalized to a single line (the ⟦N⟧ list format is
one physical line per unit).  New format first, legacy subtree
fallback.  Returns t when written."
  (let ((clean (string-trim
                (replace-regexp-in-string "[ \t]*\n[ \t]*" " "
                                          (or body "")))))
    (or (let ((region (tibetan-cascade--renderings-region)))
          (when region
            (save-excursion
              (goto-char (car region))
              (when (re-search-forward
                     (tibetan-cascade--rendering-line-re seg-num)
                     (cdr region) t)
                (replace-match (format "- ⟦%d⟧ %s" seg-num clean)
                               t t)
                t))))
        ;; T4 (§5.58): Insert-if-missing — eine hand-preservierte
        ;; Gloss-Tables-Sektion aus dem ALTEN Layout trägt keine
        ;; ⟦N⟧-Zeilen; die Zeile wird dann hinter dem
        ;; `*** Segment N'-Block NEU eingesetzt statt die
        ;; Sequenzübersetzung still zu verlieren.
        (let ((region (tibetan-cascade--renderings-region)))
          (when region
            (save-excursion
              (goto-char (car region))
              (when (re-search-forward
                     (format "^\\*\\*\\* Segment %d$" seg-num)
                     (cdr region) t)
                (let ((block-end
                       (save-excursion
                         (forward-line 1)
                         (if (re-search-forward "^\\*\\{1,3\\} "
                                                (cdr region) t)
                             (line-beginning-position)
                           (cdr region)))))
                  (goto-char block-end)
                  (skip-chars-backward " \t\n")
                  (forward-line 1)
                  (insert (format "- ⟦%d⟧ %s\n" seg-num clean))
                  t)))))
        (tibetan-cascade--write-subsegment-section-in-buffer
         seg-num "Rendering" clean))))

(defun tibetan-cascade--write-rendering (file seg-num body)
  "Replace SEG-NUM's rendering in FILE with BODY; t on success.
Same dual-format resolution as the buffer variant; nil (file
untouched) when neither format carries the unit.

C7 (2026-09-24, §5.49-Klasse): writes through
`tibetan-fresh-file-buffer' + `save-buffer' — the old
temp-buffer + `write-region' path was the last direct disk writer
crossing the buffer-writer family on the SAME landing: after the
section writers left a visiting buffer and the first span's
`write-region' changed the file behind it, the SECOND span's
`write-region' hit Emacs' supersession ask (\"Cannot resolve
conflict in batch mode\"), silently swallowed by the
condition-case — ⟦2⟧ stayed a placeholder in every real landing.
Masked in tempdir tests: `lock_file' matches the visiting buffer
only when the passed path is the TRUENAME (/var/… tempdir paths
never match; /Users/… production paths always do)."
  (when (and file (stringp file) (file-exists-p file) seg-num body)
    (condition-case nil
        (let ((buf (if (fboundp 'tibetan-fresh-file-buffer)
                       (tibetan-fresh-file-buffer file)
                     (find-file-noselect file))))
          (with-current-buffer buf
            (save-excursion
              (when (tibetan-cascade--write-rendering-in-buffer
                     seg-num body)
                (save-buffer)
                t))))
      (error nil))))

(defun tibetan-cascade--rendering-numbers (file)
  "Ordered global segment numbers of FILE's rendering units.
New-format ⟦N⟧ lines first; legacy subtree numbers fallback."
  (when (and file (stringp file) (file-exists-p file))
    (or (with-temp-buffer
          (insert-file-contents file)
          (let ((region (tibetan-cascade--renderings-region))
                nums)
            (when region
              (goto-char (car region))
              (while (re-search-forward "^- ⟦\\([0-9]+\\)⟧ "
                                        (cdr region) t)
                (push (string-to-number (match-string 1)) nums))
              (nreverse nums))))
        (tibetan-cascade--subsegment-numbers file))))

(defun tibetan-cascade--read-interlinear-for-unit (file seg-num)
  "SEG-NUM's Interlinear Gloss line/body in FILE, or nil.
New layout: the `** Interlinear Gloss' layer under `* Reading' is
POSITIONAL — the Kth non-empty line belongs to the Kth ⟦N⟧ key of
the Renderings list (the regenerable layers share the unit order;
only renderings are ⟦N⟧-keyed).  Legacy layout: the `** Segment N'
subtree's own `*** Interlinear Gloss' section."
  (when (and file (stringp file) (file-exists-p file) seg-num)
    (or (with-temp-buffer
          (insert-file-contents file)
          (let ((nums (save-excursion
                        (let ((region (tibetan-cascade--renderings-region))
                              ns)
                          (when region
                            (goto-char (car region))
                            (while (re-search-forward
                                    "^- ⟦\\([0-9]+\\)⟧ " (cdr region) t)
                              (push (string-to-number (match-string 1))
                                    ns))
                            (nreverse ns))))))
            (when nums
              (let ((idx (cl-position seg-num nums)))
                (when idx
                  (goto-char (point-min))
                  (when (re-search-forward "^\\* Reading[ \t]*$" nil t)
                    (let ((reading-end
                           (save-excursion
                             (if (re-search-forward "^\\* " nil t)
                                 (line-beginning-position)
                               (point-max)))))
                      (when (re-search-forward
                             "^\\*\\* Interlinear[ \t]*$"
                             reading-end t)
                        (forward-line 1)
                        (let ((end (save-excursion
                                     (if (re-search-forward
                                          "^\\*\\{1,2\\} " reading-end t)
                                         (line-beginning-position)
                                       reading-end)))
                              (lines '()))
                          (while (< (point) end)
                            (let ((l (string-trim
                                      (buffer-substring-no-properties
                                       (line-beginning-position)
                                       (line-end-position)))))
                              (unless (string-empty-p l)
                                (push l lines)))
                            (forward-line 1))
                          (nth idx (nreverse lines)))))))))))
        (tibetan-cascade--read-subsegment-section
         file seg-num "Interlinear Gloss"))))

(defun tibetan-cascade--rendering-needs-request-p (file seg-num)
  "Non-nil when SEG-NUM's rendering still needs the sentence fire.
Missing body, the creation placeholder, or a failure/missing stub
all count — same machine prefixes as the legacy predicate (NOT
`['-anchored wholesale: a real span may open with an editorial
bracket, the §5.40 lesson)."
  (let ((body (tibetan-cascade--read-rendering file seg-num)))
    (or (null body)
        (string-match-p "\\`\\[Awaiting" body)
        (string-match-p "\\`\\[Claude" body)
        (string-match-p "\\`\\[Requesting" body))))

;; ============================================================================
;; C3.1 — span extraction + response landing
;; ============================================================================

(declare-function tibetan-sentence-claude--parse-response
                  "tibetan-sentence-claude")
(declare-function tibetan-sentence-claude--strip-span-markers
                  "tibetan-sentence-claude")
(declare-function tibetan-sentence-claude--synthesize-segment-markdown
                  "tibetan-sentence-claude")
(declare-function tibetan-analysis--insert-claude-sections
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--claude-needs-request-p
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--read-claude-sections
                  "tibetan-analysis-claude")

(defun tibetan-cascade--extract-span (whole seg-num)
  "The text between `⟦SEG-NUM⟧' and `⟦/SEG-NUM⟧' in WHOLE, or nil.
Any residual span markers inside the extract are stripped
defensively (the schema forbids nesting, but Claude occasionally
misplaces a sibling marker).  nil on absent or malformed pairs —
the caller then writes a visible stub, never a silent blank."
  (when (and whole (stringp whole) seg-num)
    (let* ((open (format "⟦%d⟧" seg-num))
           (close (format "⟦/%d⟧" seg-num))
           (s (string-search open whole))
           (e (string-search close whole)))
      (when (and s e (< s e))
        (let ((span (string-trim
                     (replace-regexp-in-string
                      "⟦/?[0-9]+⟧" ""
                      (substring whole (+ s (length open)) e)))))
          (unless (string-empty-p span) span))))))

(defun tibetan-cascade--reassemble-subsections (parsed key seg-nums
                                                &optional preamble)
  "Rebuild the `### Segment N' markdown for KEY from PARSED slots.
PREAMBLE (e.g. the cross-clause Grammar overview) opens the body.
nil when nothing is available for any segment."
  (let* ((blocks
          (delq nil
                (mapcar
                 (lambda (n)
                   (let* ((slot (cdr (assq n (plist-get parsed
                                                        :per-segment))))
                          (body (and slot (plist-get slot key))))
                     (when (and body (not (string-empty-p body)))
                       (format "### Segment %d\n%s" n body))))
                 seg-nums)))
         (parts (if (and preamble (not (string-empty-p (or preamble ""))))
                    (cons preamble blocks)
                  blocks)))
    (when parts
      (mapconcat #'identity parts "\n\n"))))

(defun tibetan-cascade--response-word-analysis-body (response)
  "The `## Word Analysis' section body of RESPONSE, or nil.
Extracted from the RAW response with plain ^##-bounds —
`tibetan-sentence-claude--parse-response' is deliberately NOT
extended (its known-heading scan keeps the two-file responses
byte-identical)."
  (when (and response (stringp response))
    (with-temp-buffer
      (insert response)
      (goto-char (point-min))
      (when (re-search-forward "^## Word Analysis[ \t]*$" nil t)
        (let ((beg (progn (forward-line 1) (point)))
              (end (if (re-search-forward "^## " nil t)
                       (line-beginning-position)
                     (point-max))))
          (let ((body (string-trim (buffer-substring-no-properties
                                    beg end))))
            (and (not (string-empty-p body)) body)))))))

(defun tibetan-cascade--write-word-analysis (file body)
  "Write BODY as the `** Word Analysis' section of FILE.
Placed at the end of `* Tibetan Analysis' (above `* Footnotes');
an existing section is replaced.  `### Segment N' headers are
demoted to `*** Segment N' (the md-h3 convention), line-leading
star runs deeper than the section are left alone, shallower ones
get the §5.38-C1b space prefix.  Writes through
`tibetan-fresh-file-buffer' (§5.49 — never the raw
find-file-noselect at a landing site)."
  (when (and file (file-exists-p file) body (stringp body))
    (let* ((org-body
            (replace-regexp-in-string "^### \\(Segment [0-9]+\\)"
                                      "*** \\1" body))
           (safe (if (fboundp 'tibetan-analysis--sanitize-claude-body-stars)
                     (tibetan-analysis--sanitize-claude-body-stars
                      org-body 2)
                   org-body))
           (buf (if (fboundp 'tibetan-fresh-file-buffer)
                    (tibetan-fresh-file-buffer file)
                  (find-file-noselect file))))
      (with-current-buffer buf
        (save-excursion
          (goto-char (point-min))
          ;; Replace an existing section …
          (if (re-search-forward "^\\*\\* Word Analysis[ \t]*$" nil t)
              (let ((beg (progn (forward-line 1) (point)))
                    (end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                             (line-beginning-position)
                           (point-max))))
                (delete-region beg end)
                (goto-char beg)
                (insert (string-trim-right safe) "\n\n"))
            ;; … or create it at the end of * Tibetan Analysis
            ;; (S2, §5.58: »vor * Footnotes« wäre mit der neuen
            ;; L1-Ordnung der falsche Elternteil).
            (tibetan-cascade--insert-l2-in-analysis
             "Word Analysis" safe)))
        (save-buffer))
      t)))

(defun tibetan-cascade--regenerate-after-land (file)
  "Pure preserve-regenerate of the cascade FILE after a landing.
Materializes what just landed into the Reading layer: the Claude
vocabulary reaches the Interlinear/gloss-table gloss tier, and for
Sanskrit files the Word Analysis becomes padapāṭha tables (C3,
2026-09-24 — before this, a cascade file showed fresh vocabulary
only after a MANUAL regenerate; the auto-regen router only knew
seg-/par- files).

Deliberately calls `tibetan-cascade--regenerate' DIRECTLY, never
`tibetan-cascade-reanalyze-file': that entry point carries the
fire logic, and a PARTIAL landing leaves stubs that still count as
needs-request — routing through it would loop
Land→Regenerate→Fire→Land.  The pure regenerate never fires.
Never signals (a failed re-render must not kill the landing)."
  (condition-case nil
      (let* ((source-file
              (and (fboundp 'tibetan-sentence--source-file-from-analysis)
                   (tibetan-sentence--source-file-from-analysis file)))
             (sent-num
              (and (fboundp 'tibetan-sentence--sent-id-from-filename)
                   (tibetan-sentence--sent-id-from-filename file)))
             (segs (and source-file sent-num
                        (tibetan-cascade--segs-for-sentence
                         source-file sent-num))))
        (when (and segs (file-exists-p file))
          ;; A live visiting buffer would shadow the on-disk write —
          ;; drop it into sync afterwards via the fresh-buffer helper.
          (tibetan-cascade--regenerate file sent-num segs source-file)
          (let ((buf (get-file-buffer file)))
            (when buf
              (with-current-buffer buf
                (unless (buffer-modified-p)
                  (revert-buffer t t)))))
          t))
    (error nil)))

(defconst tibetan-cascade-truncation-stub
  "[Antwort abgeschnitten — Satz neu feuern mit C-c u R]"
  "Sichtbarer Stub für den Concept-Notes-Slot einer abgeschnittenen
Satz-Antwort (B4, §5.58).  Das Präfix ist BEWUSST keines der
Platzhalter-Präfixe (`[Awaiting' / `[Requesting' / …): keep-l2
filtert die beim Regenerate heraus — der Stub muss den
Regenerate-after-Land aber ÜBERLEBEN (dieselbe Persistenz-Familie
wie der §5.40-Missing-Stub `[Claude sentence response missing…').
Dass er trotzdem als still-needing-request zählt, leisten
`tibetan-cascade--truncation-stub-p' in
`tibetan-cascade--claude-sections-incomplete-p' und das
per-Slot-Gate der Landung.")

(defun tibetan-cascade--truncation-stub-p (body)
  "Non-nil wenn BODY der B4-Truncation-Stub ist (präfix-stabil,
damit künftige Wortlaut-Feinschliffe alte Stubs nicht stranden)."
  (and (stringp body)
       (string-prefix-p "[Antwort abgeschnitten" body)))

(defun tibetan-cascade--response-truncated-p (response)
  "Non-nil wenn RESPONSE sichtbar unvollständig ist (abgeschnitten).
Definitives Signal: der verpflichtende Schluss `## Concept Notes'
fehlt.  Beide Satz-Schemata (bo UND sa) verlangen die Sektion in
jeder Antwort — ein leeres Ergebnis muss den Sentinel `[No notable
concepts in this passage]' tragen —, ihr Fehlen heißt also: die
Antwort brach vor ihrem Schwanz ab (sent-654: mitten im
Particles-Eintrag bei `approx-quotative (') oder driftete vom
Schema; so oder so sind die hinteren Sektionen nicht
vertrauenswürdig.  Bewusst KEIN Auto-Refire am Erkennungsort
\(Schleifengefahr — die Landung ruft nie einen feuernden
Entry-Point); der Stub hält das B3-Gate für den NÄCHSTEN manuellen
oder Batch-Fire offen."
  (and (stringp response)
       (not (string-match-p "^## Concept Notes" response))))

(defun tibetan-cascade--land-response (response ctx)
  "Land a sentence-first RESPONSE into the ONE cascade file.
CTX: (:sent-num N :seg-nums L :sent-file FILE :cascade t :force BOOL).

Sentence level (landing-gated like every Claude write): Translation =
the whole-sentence rendering with the ⟦N⟧ markers STRIPPED;
Vocabulary / Grammar / Particles keep their per-segment subsections
\(reassembled from the parse); Concept Notes as-is — all through
`tibetan-analysis--insert-claude-sections' (heading placement, md-h3
conversion, §5.38-C1b sanitization, zettel cross-links for free).
The `### Segment N' SUB-TRANSLATIONS are DISCARDED by design — the
subsegment rendering is always the extracted span of the whole, so
the subsegment translation is contained in the sentence translation
by construction.

Per subsegment (gated per Rendering): the extracted span, or a
visible `[Claude sentence response missing Segment N …]' stub that
still counts as needs-request.  Returns non-nil when the file was
touched."
  (let* ((sent-num (plist-get ctx :sent-num))
         (seg-nums (plist-get ctx :seg-nums))
         (file (or (plist-get ctx :cascade-file)
                   (plist-get ctx :sent-file)))
         (force (plist-get ctx :force))
         (parsed (and (fboundp 'tibetan-sentence-claude--parse-response)
                      (tibetan-sentence-claude--parse-response
                       response seg-nums)))
         (whole (plist-get parsed :translation-whole)))
    (ignore sent-num)
    (when (and parsed file (file-exists-p file))
      ;; Sanskrit-Kaskade C3 (2026-09-24): land the `## Word
      ;; Analysis' section (padapāṭha + morphology) — the sent file
      ;; mirrors `#+SOURCE_LANG: sa' since C1, so the resolver reads
      ;; the file itself.  Gate: FORCE or section absent (idempotent
      ;; second landing).
      (when (and (fboundp 'tibetan-analysis--resolve-source-lang)
                 (equal (tibetan-analysis--resolve-source-lang file)
                        "sa"))
        (let ((wa (tibetan-cascade--response-word-analysis-body
                   response)))
          (when (and wa
                     (or force
                         (not (and (fboundp 'tibetan-sentence--read-l2-body)
                                   (tibetan-sentence--read-l2-body
                                    file "Word Analysis")))))
            (tibetan-cascade--write-word-analysis file wa))))
      ;; Sentence-level sections.  The generic auto-regen router only
      ;; knows seg-/par- files and would silently fail on a sent file
      ;; — bound off; the cascade does its OWN re-render below.
      ;;
      ;; B3 (§5.58, Gate-Falle): per-SLOT gating statt des alten
      ;; Gesamt-Gates.  Nach einer Chunk-Landung (nur Translation)
      ;; war `tibetan-analysis--claude-needs-request-p' (Translation
      ;; UND Vocabulary beide leer) dauerhaft nil — Vocabulary /
      ;; Grammar / Particles / Concept Notes einer späteren
      ;; Satz-Antwort wurden hier verworfen und konnten ohne FORCE
      ;; NIE mehr ankommen (der Zustand von ~736 Rgyan-Dateien).
      ;; Jetzt landet jeder Slot, der FORCE ist oder noch leer; ein
      ;; gelandeter Slot wird ohne FORCE nicht überschrieben (M7).
      (let* ((have (tibetan-analysis--read-claude-sections file))
             (md (cl-flet ((want (key)
                             (let ((v (plist-get have key)))
                               (or force (null v)
                                   ;; B4: ein Truncation-Stub zählt
                                   ;; als leer — sonst blockierte er
                                   ;; seine eigene Ersetzung beim
                                   ;; Re-Fire.
                                   (tibetan-cascade--truncation-stub-p
                                    v)))))
                   (tibetan-sentence-claude--synthesize-segment-markdown
                    (list :translation
                          (and (want :translation)
                               whole
                               (tibetan-sentence-claude--strip-span-markers
                                whole))
                          :vocabulary
                          (and (want :vocabulary)
                               (tibetan-cascade--reassemble-subsections
                                parsed :vocabulary seg-nums))
                          :grammar
                          (and (want :grammar)
                               (tibetan-cascade--reassemble-subsections
                                parsed :grammar seg-nums
                                (plist-get parsed :grammar-preamble)))
                          :particles
                          (and (want :particles)
                               (tibetan-cascade--reassemble-subsections
                                parsed :particles seg-nums))
                          :concepts
                          (and (want :concepts)
                               (or (plist-get parsed :concepts)
                                   ;; B4 (§5.58): abgeschnittene
                                   ;; Antwort → sichtbarer Stub statt
                                   ;; stummem Platzhalter.
                                   (and (tibetan-cascade--response-truncated-p
                                         response)
                                        tibetan-cascade-truncation-stub))))))))
        (when (and md (not (string-empty-p md)))
          (when (and (null (plist-get parsed :concepts))
                     (tibetan-cascade--response-truncated-p response))
            (message "tibetan-cascade: Claude-Antwort für %s wirkt abgeschnitten — Concept Notes als Stub markiert, Satz braucht einen Re-Fire"
                     (file-name-nondirectory file)))
          (let ((tibetan-analysis-auto-regen-on-claude-arrival nil))
            (tibetan-analysis--insert-claude-sections md file))))
      ;; C3 (2026-09-24): ONE pure re-render so the landing reaches
      ;; the Reading layer immediately — the Claude vocabulary hits
      ;; the gloss tier, and a Sanskrit file materializes its
      ;; padapāṭha tables from the just-written Word Analysis.
      ;; Fire-free by construction (see --regenerate-after-land).
      ;; Runs BEFORE the renderings write: the regenerate replaces
      ;; still-needs-request placeholders freshly, so a missing-span
      ;; stub written first would silently degrade to the generic
      ;; `[Awaiting…]' — the §5.40 visible-stub intent would be lost
      ;; at the only moment the stub appears.
      (tibetan-cascade--regenerate-after-land file)
      ;; Subsegment renderings — span or visible stub, per-unit gated.
      ;; R6: dual-format writer — ⟦N⟧ line in new-layout files,
      ;; legacy subtree otherwise.
      (dolist (n seg-nums)
        (when (or force
                  (tibetan-cascade--rendering-needs-request-p
                   file n))
          (let ((span (tibetan-cascade--extract-span whole n)))
            (tibetan-cascade--write-rendering
             file n
             (if span
                 ;; §5.38-C1b: neutralise line-leading `*' runs.
                 (replace-regexp-in-string "^\\(\\*+\\)" " \\1" span)
               (format "[Claude sentence response missing Segment %d — re-fire the sentence (C-c u R)]"
                       n))))))
      t)))

;; ============================================================================
;; C3.2 — cascade fire (claim + request + DM through the §5.40 machinery)
;; ============================================================================

(declare-function tibetan-sentence-claude--claim "tibetan-sentence-claude")
(declare-function tibetan-sentence-claude--request "tibetan-sentence-claude")
(declare-function tibetan-sentence-claude--schedule-dm
                  "tibetan-sentence-claude")
(declare-function tibetan-sentence--filepath "tibetan-sentence-persist")

(defun tibetan-cascade--generated-reading-lines (file source-file units)
  "Decorated Reading lines for UNITS, erzeugt mit DENSELBEN
Bindungen wie Scaffold/Regenerate (S2, §5.58): default-directory an
der Quelle (★-Wordlist-Auflösung, 2026-06-03-Lektion), target-lang
und source-lang aus den Quell-Metadaten, Claude-Vokabular aus der
Datei selbst.  Batch/Interaktiv-Parität by construction (§5.53) —
die pensionierte ** Interlinear-Sektion und diese Erzeugung müssen
auf Alt-Fixtures dieselben Zeilen liefern (Paritätstest)."
  (let* ((default-directory (if source-file
                                (file-name-directory
                                 (expand-file-name source-file))
                              default-directory))
         (tibetan-analysis--target-lang
          (or (and source-file
                   (fboundp 'tibetan-analysis--read-source-metadata)
                   (condition-case nil
                       (plist-get (tibetan-analysis--read-source-metadata
                                   source-file)
                                  :target-lang)
                     (error nil)))
              (and (boundp 'tibetan-analysis--target-lang)
                   tibetan-analysis--target-lang)))
         (tibetan-analysis--source-lang
          (and source-file
               (fboundp 'tibetan-analysis--resolve-source-lang)
               (condition-case nil
                   (tibetan-analysis--resolve-source-lang source-file)
                 (error nil))))
         (tibetan-analysis--claude-vocabulary-for-render
          (and (fboundp 'tibetan-analysis--claude-render-vars)
               (plist-get
                (tibetan-analysis--claude-render-vars
                 (list :vocabulary
                       (plist-get
                        (tibetan-analysis--read-claude-sections file)
                        :vocabulary)))
                :vocabulary))))
    (and (fboundp 'tibetan-reading-decorated-lines)
         (condition-case nil
             (tibetan-reading-decorated-lines units)
           (error nil)))))

(defun tibetan-cascade--prompt-grounding (sentence source-file folder)
  "Per-subsegment Interlinear grounding for the sentence-first prompt.
In cascade mode there are no child seg files — the grounding blocks
come from the cascade file's own `** Interlinear' lines (Alt-Layout)
or, seit S2 (§5.58, die Sektion ist pensioniert), aus der INTERNEN
Token-Strom-Erzeugung (`tibetan-cascade--generated-reading-lines'
über die shad-gesplitteten Units des Satzes — Splitter-Kontrakt:
Konkatenation == Satztext, Position K ↔ K-tes Segment).  Same
anti-hallucination purpose as the §5.34 child grounding.  nil when
the file or every gloss is unavailable."
  (let* ((sent-num (plist-get sentence :sent-num))
         (seg-nums (plist-get sentence :seg-nums))
         (file (and sent-num
                    (fboundp 'tibetan-sentence--filepath)
                    (tibetan-sentence--filepath sent-num folder
                                                source-file))))
    (when (and file (file-exists-p file))
      (let* ((units (let ((u (and (plist-get sentence :tibetan-text)
                                  (tibetan-cascade-split-shad-units
                                   (plist-get sentence :tibetan-text)))))
                      (and (= (length u) (length seg-nums)) u)))
             (gen 'unset)
             (idx -1)
             (blocks
              (delq nil
                    (mapcar
                     (lambda (n)
                       (setq idx (1+ idx))
                       (let ((gloss
                              (or (tibetan-cascade--read-interlinear-for-unit
                                   file n)
                                  (when units
                                    (when (eq gen 'unset)
                                      (setq gen
                                            (tibetan-cascade--generated-reading-lines
                                             file source-file units)))
                                    (nth idx gen)))))
                         ;; Placeholder filter: `[Interlinear not
                         ;; available]' etc. — but a combined Reading
                         ;; line may legitimately BEGIN with an org
                         ;; link (`[[https://…'), so require a
                         ;; non-bracket after the opening bracket.
                         (when (and gloss
                                    (not (string-match-p "\\`\\[[^[]"
                                                         gloss)))
                           (format "=== Segment %d ===\n%s" n gloss))))
                     seg-nums))))
        (when blocks
          (concat "\n\nPer-segment vocabulary matches (the tool's own "
                  "layered dictionary lookup; dictionary-attested — base "
                  "the Vocabulary subsections on them and do NOT invent "
                  "meanings for listed words):\n"
                  (mapconcat #'identity blocks "\n")))))))

(defun tibetan-cascade--claude-sections-incomplete-p (file)
  "Non-nil when a sentence-level Claude slot of FILE still lacks
content: Translation, Claude Vocabulary or Concept Notes missing or
placeholder — for a `#+SOURCE_LANG: sa' file also a missing
`** Word Analysis'.

B3 (§5.58, Gate-Falle): das alte Fire-Gate nutzte
`tibetan-analysis--claude-needs-request-p' (Translation UND
Vocabulary BEIDE leer).  Nach einer Chunk-Landung — die nur die
Translation schreibt — war es dauerhaft zu: die übrigen Sektionen
konnten ohne FORCE nie mehr nachgefeuert werden.  Dieses Prädikat
gilt je SLOT: solange irgendein Pflicht-Slot leer ist, darf der
Satz-Fire öffnen (die Landung gated ihrerseits per Slot und fasst
Gelandetes nicht an)."
  (when (and file (file-exists-p file))
    (let ((sections (tibetan-analysis--read-claude-sections file)))
      (cl-flet ((empty (key)
                  (let ((v (plist-get sections key)))
                    (or (null v)
                        ;; B4: der persistente Truncation-Stub zählt
                        ;; als leer — er hält das Gate offen.
                        (tibetan-cascade--truncation-stub-p v)))))
        (or (empty :translation)
            (empty :vocabulary)
            (empty :concepts)
            (and (fboundp 'tibetan-analysis--resolve-source-lang)
                 (equal (tibetan-analysis--resolve-source-lang file) "sa")
                 (null (tibetan-sentence--read-l2-body
                        file "Word Analysis"))))))))

(defun tibetan-cascade--fire-plist (sent-num segs)
  "The sentence plist `tibetan-cascade--fire-sentence' expects, built
from SENT-NUM and SEGS ((GLOBAL-NUM . TEXT) …): :sent-num,
:seg-nums, :children and :tibetan-text.
A0 (§5.59): EINE Bauvorschrift — der Prompt-Builder leitet die
`### Segment N'-Enumeration aus :children ab (A3-Vertrag, 2026-09-24:
ohne sie bekommt Claude keine Segmenttexte und kann die ⟦N⟧-Spans
nicht setzen)."
  (list :sent-num sent-num
        :seg-nums (mapcar #'car segs)
        :children (mapcar (lambda (s)
                            (list :seg-num (car s) :text (cdr s)))
                          segs)
        :tibetan-text (mapconcat #'cdr segs "")))

(defun tibetan-cascade--sentence-needs-fire-p (file seg-nums)
  "Non-nil when the cascade FILE still needs a sentence-level fire:
a Claude slot is incomplete (`--claude-sections-incomplete-p', per
slot — B3) or any ⟦N⟧ rendering of SEG-NUMS is a placeholder/stub.
A0 (§5.59): EIN Gate für den Fire selbst und für die Vorab-Zählung
der Subtree-Analyse (C-c u A auf höheren Ebenen fragt ab einer
Schwelle nach — die Zahl muss exakt die Fires sein, die passieren)."
  (or (tibetan-cascade--claude-sections-incomplete-p file)
      (cl-some (lambda (n)
                 (tibetan-cascade--rendering-needs-request-p file n))
               seg-nums)))

(defun tibetan-cascade--fire-sentence (sentence source-file folder
                                       &optional force)
  "Fire ONE sentence-level Claude call for a CASCADE document.
SENTENCE is the walker plist; the target is the single cascade file
\(resolved suffix-aware in FOLDER) — there are no child seg files.
Fire gate: FORCE, ANY sentence-level Claude slot still incomplete
\(`tibetan-cascade--claude-sections-incomplete-p' — per-slot, B3),
or ANY subsegment Rendering still a placeholder/stub.
Claim/request/DM all ride the §5.40 machinery — the request carries
the `:cascade' context flag so the response lands through
`tibetan-cascade--land-response'; DM targets the cascade file's own
nested slot.  Returns `fired' / `dedup-hit' / nil (does not apply)."
  ;; P1 discipline: this is a LEAF fire entry point — the defer-MT
  ;; guard applies here too, not only in the dispatcher above it
  ;; (create-all and future batch drivers call this directly).
  (if (and (fboundp 'tibetan-analysis--defer-mt-p)
           (tibetan-analysis--defer-mt-p source-file))
      'deferred
    (tibetan-cascade--fire-sentence-1 sentence source-file folder force)))

(defun tibetan-cascade--fire-sentence-1 (sentence source-file folder force)
  "Unguarded body of `tibetan-cascade--fire-sentence'."
  (let* ((sent-num (plist-get sentence :sent-num))
         (seg-nums (plist-get sentence :seg-nums))
         (file (and sent-num
                    (fboundp 'tibetan-sentence--filepath)
                    (tibetan-sentence--filepath sent-num folder
                                                source-file))))
    (when (and file (file-exists-p file) seg-nums
               (fboundp 'tibetan-sentence-claude--claim)
               (fboundp 'tibetan-sentence-claude--request))
      ;; B3 (§5.58): per-Slot-Prädikat statt needs-request-p; A0
      ;; (§5.59): das Gate lebt in `--sentence-needs-fire-p'.
      (when (or force
                (tibetan-cascade--sentence-needs-fire-p file seg-nums))
        (let ((label (format "sent-%03d (cascade)" sent-num)))
          (if (not (tibetan-sentence-claude--claim
                    source-file sent-num label))
              'dedup-hit
            (tibetan-sentence-claude--request
             sentence nil file source-file folder force 'cascade)
            (when (fboundp 'tibetan-sentence-claude--schedule-dm)
              (tibetan-sentence-claude--schedule-dm
               sentence (list file) nil force))
            'fired))))))

;; ============================================================================
;; C4.1 — create-all (the cascade branch of C-c u B / C-c s N)
;; ============================================================================

(defvar tibetan-auto-fire-claude-on-create)

(defun tibetan-cascade--collect-sentences ()
  "Collect the current buffer's sentences with per-segment texts.
Ordered list of plists (:sent-num N :segs ((GLOBAL-NUM . TEXT) …)).
Sentences without segment children are skipped.  Matches both
`*** Sentence' and legacy `** Sentence' levels; segments at any
deeper level (the `tibetan-auto--collect-segments' convention)."
  (save-excursion
    (goto-char (point-min))
    (let ((sentences '()))
      (while (re-search-forward "^\\(\\*+\\) Sentence \\([0-9]+\\)" nil t)
        (let* ((level (length (match-string 1)))
               (sent-num (string-to-number (match-string 2)))
               (limit (save-excursion
                        (if (re-search-forward
                             (format "^\\*\\{1,%d\\} " level) nil t)
                            (line-beginning-position)
                          (point-max))))
               (segs '()))
          (while (re-search-forward "^\\*+ Segment \\([0-9]+\\)" limit t)
            (let ((n (string-to-number (match-string 1)))
                  (text (and (fboundp 'tibetan-org-get-segment-text)
                             (tibetan-org-get-segment-text))))
              (when (and text (not (string-empty-p (string-trim text))))
                (push (cons n text) segs))))
          (when segs
            ;; CH2: record the enclosing Section (position anchor,
            ;; heading label, Lopez number) for chunk grouping.
            (let (section-pos section-label lopez)
              (save-excursion
                (goto-char (point-min))
                (let ((sent-pos (progn
                                  (re-search-forward
                                   (format "^\\*+ Sentence %d\\b" sent-num)
                                   nil t)
                                  (match-beginning 0))))
                  (goto-char sent-pos)
                  (when (re-search-backward
                         "^\\*\\{1,2\\} \\(Section\\b.*\\)$" nil t)
                    (setq section-pos (point)
                          section-label (string-trim (match-string 1)))
                    (forward-line 1)
                    (when (looking-at "^:PROPERTIES:$")
                      (let ((end (save-excursion
                                   (re-search-forward "^:END:$" nil t))))
                        (when (and end
                                   (re-search-forward
                                    "^:LOPEZ_SECTION:[ \t]*\\([0-9]+\\)"
                                    end t))
                          (setq lopez (string-to-number
                                       (match-string 1)))))))))
              (push (list :sent-num sent-num :segs (nreverse segs)
                          :section-pos section-pos
                          :section-label section-label
                          :lopez lopez)
                    sentences)))
          (goto-char limit)))
      (nreverse sentences))))

(defcustom tibetan-cascade-chunk-max-segments 40
  "Hard cap on segments per chunk-fire call.
The §5.40 record shows output LENGTH is the reliability ceiling —
chunk responses carry only the marked translation, but an unbounded
passage still risks marker drop-off.  Oversized sections split at
sentence boundaries."
  :type 'integer
  :group 'tibetan-cat)

(defun tibetan-cascade--collect-section-chunks ()
  "Group the current buffer's sentences into section chunks.
Ordered list of plists (:label STR-or-nil :lopez N-or-nil
:sentences SENTENCE-PLISTS) — one chunk per Section (sentences
before/without any Section form an implicit chunk), split further
when a chunk would exceed `tibetan-cascade-chunk-max-segments'."
  (let ((chunks '())
        (cur-sentences '())
        (cur-label nil) (cur-lopez nil)
        (cur-key 'none) (cur-count 0))
    (cl-flet ((flush ()
                (when cur-sentences
                  (push (list :label cur-label :lopez cur-lopez
                              :sentences (nreverse cur-sentences))
                        chunks))
                (setq cur-sentences '() cur-count 0)))
      (dolist (s (tibetan-cascade--collect-sentences))
        (let ((key (or (plist-get s :section-pos) 0))
              (nsegs (length (plist-get s :segs))))
          (when (or (not (equal key cur-key))
                    (and cur-sentences
                         (> (+ cur-count nsegs)
                            tibetan-cascade-chunk-max-segments)))
            (flush))
          (setq cur-key key
                cur-label (plist-get s :section-label)
                cur-lopez (plist-get s :lopez))
          (push s cur-sentences)
          (cl-incf cur-count nsegs)))
      (flush))
    (nreverse chunks)))

(defconst tibetan-cascade--chunk-system-addendum
  "

CHUNK MODE — this request covers a PASSAGE spanning several
sentences (the shad-delimited segments your user prompt lists under
`### Segment N' headers).  Produce ONLY the section
`## Translation': ONE fluent translation of the WHOLE passage.
Inside it, wrap the English span corresponding to EACH listed
segment in markers `⟦N⟧' before and `⟦/N⟧' after, using the exact
segment numbers — every listed segment exactly once, no nesting, no
overlaps (English may reorder the segments; mark the spans wherever
they fall).  NO `### Segment' subsections, NO other `## ' sections,
no commentary before or after."
  "System-prompt addendum for the chunk-fire translation layer.
Constant per document — a third coexisting Anthropic cache prefix
beside the segment-level and sentence-level ones.  Output is the
translation ONLY: the §5.40 record shows long multi-section
responses drop content, so vocabulary/grammar stay per-sentence.")

(defconst tibetan-cascade--chunk-system-addendum-sanskrit
  "

CHUNK MODE — this request covers a PASSAGE spanning several
sentences (the daṇḍa-delimited segments your user prompt lists under
`### Segment N' headers).  Produce ONLY the section
`## Translation': ONE fluent translation of the WHOLE passage.
Inside it, wrap the span corresponding to EACH listed segment in
markers `⟦N⟧' before and `⟦/N⟧' after, using the exact segment
numbers — every listed segment exactly once, no nesting, no
overlaps (the translation may reorder the segments; mark the spans
wherever they fall).  NO `### Segment' subsections, NO other `## '
sections, no commentary before or after."
  "The Sanskrit chunk addendum (Sanskrit-Kaskade C2, 2026-09-24) —
appended to the Sanskrit base; overrides its five-section schema
down to the translation-only chunk contract, exactly like the
Tibetan pair.  Constant per document.")

(defun tibetan-cascade--build-chunk-prompts (chunk source-file)
  "Build (SYSTEM . USER) for a chunk-fire call over CHUNK."
  (let* ((sa-p (and source-file
                    (fboundp 'tibetan-analysis--resolve-source-lang)
                    (equal (tibetan-analysis--resolve-source-lang
                            source-file)
                           "sa")))
         (system (concat
                  (if sa-p
                      (concat
                       (if (boundp
                            'tibetan-sentence-claude--system-prompt-sanskrit)
                           tibetan-sentence-claude--system-prompt-sanskrit
                         "")
                       tibetan-cascade--chunk-system-addendum-sanskrit)
                    (concat
                     (if (boundp 'tibetan-analysis--claude-system-prompt)
                         tibetan-analysis--claude-system-prompt
                       "")
                     tibetan-cascade--chunk-system-addendum))
                  (if (and source-file
                           (fboundp
                            'tibetan-analysis--claude-static-system-blocks))
                      (tibetan-analysis--claude-static-system-blocks
                       source-file)
                    "")))
         (sentences (plist-get chunk :sentences))
         (all-segs (apply #'append
                          (mapcar (lambda (s) (plist-get s :segs))
                                  sentences)))
         (text (mapconcat #'cdr all-segs ""))
         (enumeration
          (mapconcat (lambda (sp)
                       (format "### Segment %d\n%s"
                               (car sp) (string-trim (cdr sp))))
                     all-segs "\n"))
         (refs (when (fboundp 'tibetan-cascade--section-refs-block)
                 (tibetan-cascade--section-refs-block
                  (car sentences) source-file)))
         (user (concat
                (format "%s (%s — segments %s):\n\n"
                        (if sa-p "Sanskrit passage (IAST)"
                          "Classical Tibetan passage")
                        (or (plist-get chunk :label) "passage")
                        (mapconcat (lambda (sp)
                                     (number-to-string (car sp)))
                                   all-segs ", "))
                (string-trim text)
                "\n\nThe passage consists of these segments:\n"
                enumeration
                (or refs "")
                "\n\nProduce ONLY the `## Translation' section now, with every listed segment's span marked ⟦N⟧…⟦/N⟧ exactly as instructed.")))
    (cons system user)))

(defun tibetan-cascade--chunk-translation-body (response)
  "The `## Translation' body of RESPONSE (whole response when the
heading is absent — the markers still carry the information)."
  (when (and response (stringp response))
    (if (string-match "^## Translation[ \t]*\n" response)
        (let* ((start (match-end 0))
               (end (or (and (string-match "^## " response start)
                             (match-beginning 0))
                        (length response))))
          (string-trim (substring response start end)))
      (string-trim response))))

(defun tibetan-cascade--land-chunk-response (response ctx)
  "Land a chunk-fire RESPONSE into every member cascade file.
CTX: (:chunk t :label STR :sentences ((:sent-num N :seg-nums L
:file F) …) :force BOOL).

Per subsegment: the extracted ⟦N⟧ span (or the visible missing-span
stub — the C3 sentence-level dispatcher is the automatic fallback on
the next open/batch).  Per sentence: the SLICE of the whole between
its first span opening and its last span closing, all markers
stripped — preserving the connective English between the sentence's
own segments — labeled `(Sentence N — LABEL chunk)'.  All writes
landing-gated per file (§5.38-M7)."
  (let ((sentences (plist-get ctx :sentences))
        (force (plist-get ctx :force))
        (label (or (plist-get ctx :label) "section"))
        (whole (tibetan-cascade--chunk-translation-body response)))
    (when (and whole (not (string-empty-p whole)) sentences)
      (dolist (s sentences)
        (let ((file (plist-get s :file))
              (sent-num (plist-get s :sent-num))
              (seg-nums (plist-get s :seg-nums)))
          (when (and file (file-exists-p file))
            ;; C3 (2026-09-24): re-render FIRST (fire-free — see
            ;; --regenerate-after-land), then write spans/stubs and
            ;; the slice — the regenerate replaces needs-request
            ;; placeholders freshly and would degrade a stub written
            ;; before it.
            (tibetan-cascade--regenerate-after-land file)
            ;; Subsegment renderings (R6: dual-format writer).
            (dolist (n seg-nums)
              (when (or force
                        (tibetan-cascade--rendering-needs-request-p
                         file n))
                (let ((span (tibetan-cascade--extract-span whole n)))
                  (tibetan-cascade--write-rendering
                   file n
                   (if span
                       (replace-regexp-in-string "^\\(\\*+\\)" " \\1"
                                                 span)
                     (format "[Claude sentence response missing Segment %d — re-fire the sentence (C-c u R)]"
                             n))))))
            ;; Sentence Translation: the marker-bounded slice.
            (when (and (fboundp 'tibetan-analysis--claude-needs-request-p)
                       (or force
                           (tibetan-analysis--claude-needs-request-p
                            file)))
              (let* ((opens (delq nil
                                  (mapcar (lambda (n)
                                            (string-search
                                             (format "⟦%d⟧" n) whole))
                                          seg-nums)))
                     (closes (delq nil
                                   (mapcar
                                    (lambda (n)
                                      (let* ((c (format "⟦/%d⟧" n))
                                             (p (string-search c whole)))
                                        (and p (+ p (length c)))))
                                    seg-nums))))
                (when (and opens closes)
                  (let* ((slice (substring whole
                                           (apply #'min opens)
                                           (apply #'max closes)))
                         (plain (string-trim
                                 (replace-regexp-in-string
                                  "⟦/?[0-9]+⟧" "" slice))))
                    (unless (string-empty-p plain)
                      (let ((tibetan-analysis-auto-regen-on-claude-arrival
                             nil))
                        (tibetan-analysis--insert-claude-sections
                         (format "## Translation\n(Sentence %s — %s chunk)\n%s\n"
                                 sent-num label plain)
                         file))))))))))
      t)))


;;;###autoload
(defun tibetan-cascade-create-all (&optional force)
  "Create the cascade sent file for EVERY sentence of the current
source buffer (one file per sentence — no seg files).  Skips
existing files unless FORCE.  When
`tibetan-auto-fire-claude-on-create' is non-nil, fires the
sentence-level Claude/DM call for each newly-created file (the
queue throttles; `tibetan-cascade--fire-sentence' itself defers
under `#+TIBETAN_DEFER_MT').  Returns
\(:created N :skipped M :files LIST)."
  (interactive "P")
  (unless (buffer-file-name)
    (error "Buffer must be saved to a file first"))
  (let* ((source-file (buffer-file-name))
         (sentences (tibetan-cascade--collect-sentences))
         (folder (file-name-as-directory
                  (expand-file-name
                   "analysis" (file-name-directory source-file))))
         (created '())
         (skipped 0))
    (unless sentences
      (error "No sentences found. Run tibetan-prepare-document first"))
    (dolist (s sentences)
      (let* ((sent-num (plist-get s :sent-num))
             (file (if (fboundp 'tibetan-sentence--filepath)
                       (tibetan-sentence--filepath sent-num folder
                                                   source-file)
                     (expand-file-name (format "sent-%03d.org" sent-num)
                                       folder))))
        (if (and (file-exists-p file) (not force))
            (cl-incf skipped)
          (tibetan-cascade--create-file sent-num (plist-get s :segs)
                                        source-file)
          (push (cons s file) created))))
    (setq created (nreverse created))
    ;; CH (2026-07-29, after the live §167 evaluation — 9/9 spans):
    ;; cascade auto-fire is CHUNKED — one translation-layer call +
    ;; one DM call per SECTION.  Fire gates skip populated members,
    ;; and missing spans fall back to the C3 sentence dispatcher on
    ;; the next open/batch.
    (when (and created
               (boundp 'tibetan-auto-fire-claude-on-create)
               tibetan-auto-fire-claude-on-create)
      (dolist (chunk (tibetan-cascade--collect-section-chunks))
        (condition-case err
            (tibetan-cascade--fire-section chunk source-file folder)
          (error (message "Cascade chunk fire skipped (%s): %s"
                          (or (plist-get chunk :label) "chunk")
                          (error-message-string err))))))
    (message "Cascade: %d sentence file%s created, %d skipped"
             (length created) (if (= 1 (length created)) "" "s") skipped)
    (list :created (length created) :skipped skipped
          :files (mapcar #'cdr created))))

;; ============================================================================
;; C4.2 — open dispatch (C-c u A at a segment of a cascade document)
;; ============================================================================

(declare-function tibetan-sentence--sentence-for-segment
                  "tibetan-sentence-persist")

(defun tibetan-cascade--segs-for-sentence (source-file sent-num)
  "SOURCE-FILE's sentence SENT-NUM as (GLOBAL-NUM . TEXT) pairs, or nil."
  (when (and source-file (file-readable-p source-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents source-file)
          (org-mode)
          (plist-get
           (cl-find sent-num (tibetan-cascade--collect-sentences)
                    :key (lambda (p) (plist-get p :sent-num)))
           :segs))
      (error nil))))

;;;###autoload
(defun tibetan-cascade-open-for-segment (seg-id source-file)
  "Open the cascade file owning SEG-ID; point on its subsegment subtree.
Resolves the sentence through the §5.40 walker, creates the cascade
file when missing (C-c u A parity: opening implies creating), and
displays it in the side window.  Returns the buffer.

SEG-ID may be a number or a composite label like `\"Sentence 5,
Segment 107\"' (what `tibetan-get-current-segment-any-format'
returns for the nested §2.12 layout) — the trailing segment number
is what counts."
  (when (and (stringp seg-id)
             (string-match "Segment \\([0-9]+\\)" seg-id))
    (setq seg-id (string-to-number (match-string 1 seg-id))))
  (let* ((sentence (and (fboundp 'tibetan-sentence--sentence-for-segment)
                        (condition-case nil
                            (tibetan-sentence--sentence-for-segment
                             seg-id source-file)
                          (error nil))))
         (sent-num (plist-get sentence :sent-num)))
    (unless sent-num
      (user-error "Segment %s is not inside a sentence of %s"
                  seg-id (file-name-nondirectory (or source-file "?"))))
    (let* ((folder (file-name-as-directory
                    (expand-file-name
                     "analysis" (file-name-directory source-file))))
           (file (if (fboundp 'tibetan-sentence--filepath)
                     (tibetan-sentence--filepath sent-num folder
                                                 source-file)
                   (expand-file-name (format "sent-%03d.org" sent-num)
                                     folder))))
      (unless (file-exists-p file)
        (tibetan-cascade--create-file
         sent-num
         (tibetan-cascade--segs-for-sentence source-file sent-num)
         source-file))
      (let ((buf (find-file-noselect file)))
        (with-current-buffer buf
          (when (fboundp 'tibetan-analysis-setup-faces)
            (tibetan-analysis-setup-faces))
          (goto-char (point-min))
          ;; R9: land on the unit's ⟦N⟧ rendering line in the Reading
          ;; view; legacy `** Segment N' heading for unmigrated
          ;; files; `* Reading' as the final anchor.
          (cond
           ((re-search-forward
             (format "^- ⟦%d⟧ " seg-id) nil t)
            (beginning-of-line))
           ((re-search-forward
             (format "^\\*\\* Segment %d$" seg-id) nil t)
            (beginning-of-line))
           ((re-search-forward "^\\* Reading[ \t]*$" nil t)
            (beginning-of-line))))
        (let ((win (display-buffer-in-side-window
                    buf '((side . right) (window-width . 0.5)))))
          (when (windowp win)
            (set-window-point win (with-current-buffer buf (point)))))
        ;; DEFER-MT VISIBILITY (2026-07-30): say on open WHY the MT
        ;; slots are placeholders — the file alone looked like a
        ;; failed request in the live Portfolio session.
        (when (and (fboundp 'tibetan-analysis--defer-mt-p)
                   (tibetan-analysis--defer-mt-p source-file))
          (message (concat "MT deferred for this document "
                           "(#+TIBETAN_DEFER_MT, portfolio mode) — "
                           "draft your own translation first; remove "
                           "the header and re-fire when frozen")))
        ;; Tshig-gsal-Befund (2026-09-24): opening implied creating,
        ;; but NOT firing — Claude/DM stayed placeholders until a
        ;; manual C-c u R (parity gap to the two-file openers,
        ;; §5.8.1/§5.29).  Fire the sentence-level dispatcher on
        ;; every open: its gates (claim/dedup, needs-request,
        ;; rendering placeholders) decline populated files, and the
        ;; leaf fire still defers under #+TIBETAN_DEFER_MT.  Same
        ;; opt-out as every create-fire.
        (when (and (boundp 'tibetan-auto-fire-claude-on-create)
                   tibetan-auto-fire-claude-on-create
                   (fboundp 'tibetan-analysis--fire-sentence-level))
          (condition-case err
              (tibetan-analysis--fire-sentence-level
               "" file source-file seg-id nil)
            (error (message "Cascade open fire skipped: %s"
                            (error-message-string err)))))
        buf))))

;; ============================================================================
;; A1 (§5.59) — C-c u A above sentence level: the org subtree cascades
;; ============================================================================

(defcustom tibetan-cascade-subtree-confirm-threshold 10
  "C-c u A above sentence level asks before firing MORE sentences.
The subtree analysis fires one Claude + one DharmaMitra call per
incomplete sentence; on `* Tibetan Text' of a big source that is
hundreds of API calls.  Up to this many it fires without asking (a
§ typically has a handful of sentences)."
  :type 'integer
  :group 'tibetan-cat)

(defun tibetan-cascade--subtree-sentences ()
  "The org subtree at point in the current cascade SOURCE buffer.
Returns (LABEL . SENTENCES): LABEL is the heading text (nil before
the first heading = whole document), SENTENCES the walker plists
of every `Sentence' below it — level-agnostic, the org outline
decides the scope (`*' = all, `** Section' = its sentences …)."
  (save-excursion
    (save-restriction
      (widen)
      (let ((label nil))
        (unless (org-before-first-heading-p)
          (org-back-to-heading t)
          (setq label (org-get-heading t t t t))
          (org-narrow-to-subtree))
        (cons label (tibetan-cascade--collect-sentences))))))

;;;###autoload
(defun tibetan-cascade-analyze-subtree (source-file)
  "C-c u A on a heading ABOVE sentence level of the cascade SOURCE-FILE.
Cascades down the org subtree at point: every sentence below gets
its cascade file (created when missing — structural, free), every
INCOMPLETE one a sentence-level fire (the A0 gate
`--sentence-needs-fire-p'; the queue throttles, the leaf defers
under #+TIBETAN_DEFER_MT, claim/dedup prevents doubles).  More than
`tibetan-cascade-subtree-confirm-threshold' fires → `y-or-n-p' with
the count.  Finally the first sentence's file opens (its open-fire
is a dedup hit; after a declined prompt the open does not fire).
Honors `tibetan-auto-fire-claude-on-create' like every create-fire.
Returns (:sentences N :created N :fired N :pending N).

A1 (§5.59, Carstens Befund an §220): auf `** Section §220' lief
C-c u A bisher in den Two-File-ABSATZpfad (`** §N' + `*** Tibetisch'),
auf Sections ohne „§\" und `* Tibetan Text' in den Segment-Impl —
beides Fehlermeldungen statt Analyse."
  (let* ((sub (tibetan-cascade--subtree-sentences))
         (label (or (car sub) (file-name-nondirectory source-file)))
         (sentences (cdr sub))
         (folder (file-name-as-directory
                  (expand-file-name
                   "analysis" (file-name-directory source-file))))
         (created 0)
         (todo '()))
    (unless sentences
      (user-error "Keine Sätze unter „%s“" label))
    (dolist (s sentences)
      (let* ((n (plist-get s :sent-num))
             (segs (plist-get s :segs))
             (file (tibetan-sentence--filepath n folder source-file)))
        (unless (file-exists-p file)
          (tibetan-cascade--create-file n segs source-file)
          (cl-incf created))
        (when (tibetan-cascade--sentence-needs-fire-p
               file (mapcar #'car segs))
          (push s todo))))
    (setq todo (nreverse todo))
    (let* ((auto (and (boundp 'tibetan-auto-fire-claude-on-create)
                      tibetan-auto-fire-claude-on-create))
           (go (and todo auto
                    (or (<= (length todo)
                            tibetan-cascade-subtree-confirm-threshold)
                        (y-or-n-p
                         (format "%s: %d Sätze an Claude + DharmaMitra senden? "
                                 label (length todo))))))
           (fired 0))
      (when go
        (dolist (s todo)
          (condition-case err
              (when (eq 'fired
                        (tibetan-cascade--fire-sentence
                         (tibetan-cascade--fire-plist
                          (plist-get s :sent-num) (plist-get s :segs))
                         source-file folder))
                (cl-incf fired))
            (error (message "Cascade fire skipped (Satz %s): %s"
                            (plist-get s :sent-num)
                            (error-message-string err))))))
      (message "%s: %d Sätze — %d angelegt, %d gefeuert, %d vollständig"
               label (length sentences) created fired
               (- (length sentences) (length todo)))
      ;; Open the first sentence.  A declined prompt must not be
      ;; undercut by the open path's own fire.
      (let ((tibetan-auto-fire-claude-on-create (and go auto)))
        (tibetan-cascade-open-for-segment
         (car (car (plist-get (car sentences) :segs))) source-file))
      (list :sentences (length sentences) :created created
            :fired fired :pending (- (length todo) fired)))))

;;;###autoload
(defun tibetan-cascade-reanalyze-subtree (source-file &optional force)
  "C-c u R on a heading ABOVE sentence level of the cascade SOURCE-FILE.
Mirrors C-c u R on a sentence (`tibetan-sentence-reanalyze', A1
branch): every EXISTING cascade file of the org subtree at point is
regenerated preserve-mode (user/Claude/DM content stays) — no fire.
FORCE (C-u) re-fires every one of them, overwriting landed Claude
content; therefore always confirmed with the count.  Missing files
are reported (C-c u A creates them).  Visiting buffers are reverted.
Returns (:reanalyzed N :failed N :missing N).
A2 (§5.59): dieselbe Fehlerklasse wie A1 — C-c u R auf
`** Section §220' lief in `tibetan-reanalyze-paragraph'."
  (let* ((sub (tibetan-cascade--subtree-sentences))
         (label (or (car sub) (file-name-nondirectory source-file)))
         (folder (file-name-as-directory
                  (expand-file-name
                   "analysis" (file-name-directory source-file))))
         (files '())
         (missing 0))
    (unless (cdr sub)
      (user-error "Keine Sätze unter „%s“" label))
    (dolist (s (cdr sub))
      (let ((file (tibetan-sentence--filepath (plist-get s :sent-num)
                                              folder source-file)))
        (if (file-exists-p file)
            (push file files)
          (cl-incf missing))))
    (setq files (nreverse files))
    (if (and force files
             (not (y-or-n-p
                   (format "%s: %d Sätze NEU an Claude + DharmaMitra senden (überschreibt Gelandetes)? "
                           label (length files)))))
        (progn (message "Nichts geändert.")
               (list :reanalyzed 0 :failed 0 :missing missing))
      (let ((ok 0) (failed 0))
        (dolist (file files)
          (if (plist-get (tibetan-cascade-reanalyze-file
                          file :source-file source-file
                          :re-request-claude (and force t))
                         :ok)
              (cl-incf ok)
            (cl-incf failed))
          (let ((buf (get-file-buffer file)))
            (when buf
              (with-current-buffer buf (revert-buffer t t)))))
        (message "%s: %d Satzdatei%s neu gerendert%s%s%s"
                 label ok (if (= ok 1) "" "en")
                 (if force ", neu gefeuert" "")
                 (if (> failed 0) (format ", %d FEHLER" failed) "")
                 (if (> missing 0)
                     (format " — %d ohne Datei (C-c u A legt sie an)"
                             missing)
                   ""))
        (list :reanalyzed ok :failed failed :missing missing)))))

;; ============================================================================
;; C4.3 — reanalyze routing (single file, per-segment, batch guard)
;; ============================================================================

(declare-function tibetan-sentence--sent-id-from-filename
                  "tibetan-sentence-persist")
(declare-function tibetan-sentence--source-file-from-analysis
                  "tibetan-sentence-persist")
(declare-function tibetan-analysis--should-fire-claude-p
                  "tibetan-analysis-claude")

(cl-defun tibetan-cascade-reanalyze-file (filepath &key source-file
                                                   re-request-claude)
  "Headless re-analysis of the cascade file FILEPATH.
Sentence number from the filename; segs freshly re-read from
SOURCE-FILE (or the file's #+SOURCE link); regenerate preserves all
user/Claude/DM content (C2.3).  RE-REQUEST-CLAUDE follows the
§5.22-follow-up policy (nil / t / :missing-only) — the fire itself
still defers under #+TIBETAN_DEFER_MT.  Returns
\(:file F :sent-id N :ok BOOL :error STR)."
  (let* ((sent-id (and (fboundp 'tibetan-sentence--sent-id-from-filename)
                       (tibetan-sentence--sent-id-from-filename filepath)))
         (src (or source-file
                  (and (fboundp 'tibetan-sentence--source-file-from-analysis)
                       (tibetan-sentence--source-file-from-analysis
                        filepath))))
         (segs (and sent-id src
                    (tibetan-cascade--segs-for-sentence src sent-id))))
    (cond
     ((null sent-id)
      (list :file filepath :ok nil
            :error "Could not extract sent-id from filename"))
     ((null src)
      (list :file filepath :sent-id sent-id :ok nil
            :error "Could not resolve source file"))
     ((null segs)
      (list :file filepath :sent-id sent-id :ok nil
            :error (format "Sentence %d not found in source" sent-id)))
     (t
      (condition-case err
          (progn
            (tibetan-cascade--regenerate filepath sent-id segs src)
            (when (and re-request-claude
                       (or (not (fboundp 'tibetan-analysis--should-fire-claude-p))
                           (tibetan-analysis--should-fire-claude-p
                            re-request-claude filepath)))
              ;; DEFER-MT VISIBILITY (2026-07-30): the guarded fire
              ;; returns `deferred' silently — C-c u R then LOOKED
              ;; like a no-op failure.  Tell the user what happened.
              ;; A3 (2026-09-24) / A0 (§5.59): :children trägt die
              ;; Segment-Enumeration — `--fire-plist' baut sie.
              (when (eq (tibetan-cascade--fire-sentence
                         (tibetan-cascade--fire-plist sent-id segs)
                         src (file-name-directory
                              (expand-file-name filepath))
                         (eq re-request-claude t))
                        'deferred)
                (message (concat "MT request NOT fired: #+TIBETAN_DEFER_MT "
                                 "is active (portfolio mode) — remove the "
                                 "header once your draft is frozen"))))
            (list :file filepath :sent-id sent-id :ok t))
        (error (list :file filepath :sent-id sent-id :ok nil
                     :error (error-message-string err))))))))

;;;###autoload
(defun tibetan-cascade-reanalyze-for-segment (seg-id source-file
                                              &optional re-request-claude)
  "Re-analyze the cascade file owning SEG-ID (the C-c u R branch).
SEG-ID as in `tibetan-cascade-open-for-segment' (number or composite
label).  Returns the `tibetan-cascade-reanalyze-file' plist."
  (when (and (stringp seg-id)
             (string-match "Segment \\([0-9]+\\)" seg-id))
    (setq seg-id (string-to-number (match-string 1 seg-id))))
  (let* ((sentence (and (fboundp 'tibetan-sentence--sentence-for-segment)
                        (condition-case nil
                            (tibetan-sentence--sentence-for-segment
                             seg-id source-file)
                          (error nil))))
         (sent-num (plist-get sentence :sent-num)))
    (if (not sent-num)
        (list :ok nil
              :error (format "Segment %s not inside a sentence" seg-id))
      (let* ((folder (file-name-as-directory
                      (expand-file-name
                       "analysis" (file-name-directory source-file))))
             (file (if (fboundp 'tibetan-sentence--filepath)
                       (tibetan-sentence--filepath sent-num folder
                                                   source-file)
                     (expand-file-name (format "sent-%03d.org" sent-num)
                                       folder))))
        (if (file-exists-p file)
            (tibetan-cascade-reanalyze-file
             file :source-file source-file
             :re-request-claude re-request-claude)
          (list :ok nil :error (format "No cascade file for sentence %d"
                                       sent-num)))))))

(defun tibetan-cascade-file-p (filepath)
  "Non-nil when FILEPATH itself carries `#+TIBETAN_LAYOUT: cascade'.
The batch-safety predicate: folder batches must route such files to
the cascade regenerate — the two-file sentence regenerate would
destroy the * Subsegments tree."
  (and filepath (stringp filepath) (file-exists-p filepath)
       (fboundp 'tibetan-analysis--read-source-metadata)
       (equal "cascade"
              (plist-get (tibetan-analysis--read-source-metadata filepath)
                         :layout))))

;; ============================================================================
;; C5.2 — one-time source transform: segment = shad unit
;; ============================================================================

(declare-function tibetan-analysis--folder-analysis-files-strict
                  "tibetan-analysis-persist")
(declare-function tibetan-analysis--file-source-basename
                  "tibetan-analysis-persist")

;;;###autoload
(defun tibetan-shad-split-segments ()
  "Split every Segment of the current source buffer into shad units.
One-time SOURCE transform preparing a document for cascade analysis
\(segment = shad unit; sentence = group of segments).  Renumbers ALL
segments globally from 1 afterwards — therefore it REFUSES with a
`user-error' when analysis/ already holds seg files for this source:
renumbering would orphan them (the §5.26/§5.33 data-loss class).
Never run it on a two-file corpus.

A `:PROPERTIES:' drawer (e.g. :FOLIO:) stays on the FIRST unit of a
split segment; Working Translation siblings are untouched; the
concatenated Tibetan is preserved (the C1 splitter's contract).
Returns (:segments-before N :segments-after M)."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Buffer must be saved to a file first"))
  (let* ((source-file (buffer-file-name))
         (folder (expand-file-name
                  "analysis" (file-name-directory source-file))))
    (when (file-directory-p folder)
      (let ((seg-files
             (if (fboundp 'tibetan-analysis--folder-analysis-files-strict)
                 (tibetan-analysis--folder-analysis-files-strict
                  folder "seg")
               (directory-files folder t "\\`seg-"))))
        (when (cl-some
               (lambda (f)
                 (if (fboundp 'tibetan-analysis--file-source-basename)
                     (equal (tibetan-analysis--file-source-basename f)
                            (file-name-nondirectory source-file))
                   ;; Resolver unavailable → any seg file blocks.
                   t))
               seg-files)
          (user-error
           "analysis/ holds seg files for this source — shad-splitting would renumber and orphan them"))))
    (let ((before 0) (after 0))
      (save-excursion
        ;; Pass 1: split each multi-unit segment in place.
        (goto-char (point-min))
        (while (re-search-forward "^\\(\\*+\\) Segment [0-9]+.*$" nil t)
          (cl-incf before)
          (let* ((stars (match-string 1))
                 (h-start (line-beginning-position))
                 (h-end (line-end-position))
                 (subtree-end (save-excursion
                                (goto-char h-end)
                                (if (re-search-forward "^\\*+ " nil t)
                                    (line-beginning-position)
                                  (point-max))))
                 (drawer
                  (save-excursion
                    (goto-char h-end)
                    (forward-line 1)
                    (when (looking-at "^:PROPERTIES:$")
                      (let ((ds (point)))
                        (when (re-search-forward "^:END:$" subtree-end t)
                          (forward-line 1)
                          (buffer-substring-no-properties ds (point)))))))
                 (body-start (save-excursion
                               (goto-char h-end)
                               (forward-line 1)
                               (when drawer
                                 (re-search-forward "^:END:$" subtree-end t)
                                 (forward-line 1))
                               (point)))
                 (body (buffer-substring-no-properties body-start
                                                       subtree-end))
                 (units (tibetan-cascade-split-shad-units
                         (string-trim body))))
            (if (or (null units) (< (length units) 2))
                (progn (cl-incf after)
                       (goto-char subtree-end))
              (cl-incf after (length units))
              (delete-region h-start subtree-end)
              (goto-char h-start)
              (let ((first t))
                (dolist (u units)
                  (insert stars " Segment 0\n")
                  (when (and first drawer) (insert drawer))
                  (setq first nil)
                  (insert (string-trim u) "\n\n"))))))
        ;; Pass 2: renumber globally from 1.
        (goto-char (point-min))
        (let ((n 0))
          (while (re-search-forward "^\\(\\*+\\) Segment [0-9]+" nil t)
            (cl-incf n)
            (replace-match (format "\\1 Segment %d" n) t nil))))
      (when (called-interactively-p 'any)
        (message "Shad-split: %d segment%s → %d shad-unit segments"
                 before (if (= 1 before) "" "s") after))
      (list :segments-before before :segments-after after))))

;; ============================================================================
;; C7.1 — comparative-document importer (the Rgyan §-layer)
;; ============================================================================

;;;###autoload
(declare-function tibetan-sanskrit-script-normalize
                  "tibetan-sanskrit-script")

(defun tibetan-cascade--sanskrit-split-prose (block)
  "BLOCK (IAST prose) as daṇḍa units, concatenation-preserving.
Splits after ।, ॥ and the romanized |, || of many e-texts; each
unit keeps its trailing daṇḍa run plus following whitespace (the
`tibetan-cascade-split-shad-units' contract, transposed).  A
daṇḍa-less block is ONE unit.  nil-safe."
  (when (and block (stringp block)
             (not (string-empty-p (string-trim block))))
    (let ((units '())
          (start 0))
      (while (string-match "[।॥|]+[ \t\n]*" block start)
        (push (substring block start (match-end 0)) units)
        (setq start (match-end 0)))
      (when (< start (length block))
        (push (substring block start) units))
      (nreverse units))))

(defun tibetan-cascade--sanskrit-block-verse-p (block)
  "Non-nil when BLOCK reads as a verse: ≥2 lines AND a double-daṇḍa
\(॥ or ||) close.  Everything else is prose."
  (let ((lines (split-string (string-trim block) "\n" t)))
    (and (>= (length lines) 2)
         (string-match-p "\\(?:॥\\|||\\)[ \t]*\\'" (string-trim block)))))

(defun tibetan-cascade--sanskrit-split-blocks (text)
  "TEXT as ((LABEL . (BLOCK…)) …) — section marker lines `# LABEL'
open a new section; blank-line-separated paragraphs are blocks.
Text before the first marker forms a section labeled \"Text\"."
  (let ((sections '())
        (label nil)
        (chunk '()))
    (cl-flet ((flush-block (acc)
                (let ((b (string-trim (string-join (nreverse chunk) "\n"))))
                  (setq chunk '())
                  (if (string-empty-p b) acc (cons b acc)))))
      (let ((blocks '()))
        (dolist (line (split-string (or text "") "\n"))
          (cond
           ((string-match "\\`#[ \t]+\\(.+\\)\\'" line)
            (setq blocks (flush-block blocks))
            (when (or label blocks)
              (push (cons (or label "Text") (nreverse blocks)) sections)
              (setq blocks '()))
            (setq label (string-trim (match-string 1 line))))
           ((string-empty-p (string-trim line))
            (setq blocks (flush-block blocks)))
           (t (push line chunk))))
        (setq blocks (flush-block blocks))
        (when (or label blocks)
          (push (cons (or label "Text") (nreverse blocks)) sections))))
    (nreverse sections)))

;;;###autoload
(cl-defun tibetan-cascade-import-sanskrit (input output-file &key title)
  "Import raw Sanskrit INPUT into the cascade CAT source OUTPUT-FILE.

Sanskrit-Kaskade D1 (2026-09-24).  INPUT is a string (or,
interactively, the active region / a file's contents), mixed
IAST/Devanagari — normalized to IAST via
`tibetan-sanskrit-script-normalize'.  Structure rules, all
deterministic:

  - a line `# LABEL' opens a new `** Section LABEL' (e.g.
    `# PP ad MMK 24.8'); the drawer carries a SEQUENTIAL
    `:LOPEZ_SECTION:' integer — the stitcher/§-view key on ints,
    the heading text carries the real reference;
  - blank-line paragraphs are blocks; a block of ≥2 lines closed by
    ॥/|| is a VERSE: each line = one pāda = one `**** Segment', the
    block = one `*** Sentence' (stanza);
  - any other block is PROSE: each daṇḍa unit (।/॥/|/||) = one
    Segment = its OWN Sentence (singletons fire sentence-level
    since B-1.2; joining units into larger sentences is hand work
    in the source, as with Tibetan);
  - sentence and segment numbers are GLOBAL from 1; every segment
    is daṇḍa-terminated as written, so the cascade's shad-less
    one-unit contract applies per segment.

Headers written: `#+TIBETAN_LAYOUT: cascade', `#+SOURCE_LANG: sa',
`#+TIBETAN_TARGET_LANG: de', TITLE.  Refuses to overwrite an
existing OUTPUT-FILE (hand-owned once created — the
import-comparative rule).  Empfehlung: EIN Belegstellen-Dokument
je Vorhaben und ein EIGENER Ordner je Quelle — die Stitcher-
Ausgabenamen sind pro analysis/-Ordner fix, und
`tibetan-analysis-make-short-name' kollabiert ähnliche Dateinamen
\(MMK-…) auf denselben Suffix.

Returns (:sections N :sentences N :segments N :file OUTPUT-FILE)."
  (interactive
   (list (if (use-region-p)
             (buffer-substring-no-properties (region-beginning)
                                             (region-end))
           (with-temp-buffer
             (insert-file-contents
              (read-file-name "Sanskrit-Rohtext (Datei): " nil nil t))
             (buffer-string)))
         (read-file-name "Kaskaden-Quelle anlegen: ")
         :title (read-string "Titel: " "Sanskrit-Belegstellen")))
  (when (file-exists-p output-file)
    (user-error
     "%s already exists — the CAT source is hand-owned once created"
     (file-name-nondirectory output-file)))
  (unless (and input (stringp input)
               (not (string-empty-p (string-trim input))))
    (user-error "Empty Sanskrit input"))
  (let* ((normalized (if (fboundp 'tibetan-sanskrit-script-normalize)
                         (tibetan-sanskrit-script-normalize input)
                       input))
         (sections (tibetan-cascade--sanskrit-split-blocks normalized))
         (sent-num 0) (seg-num 0) (sec-num 0))
    (unless sections
      (user-error "No Sanskrit content found in the input"))
    (with-temp-file output-file
      (insert (format "#+TITLE: %s\n" (or title "Sanskrit-Belegstellen")))
      (insert "#+STARTUP: showall\n")
      (insert "#+OPTIONS: toc:nil num:nil\n")
      (insert "#+TIBETAN_LAYOUT: cascade\n")
      (insert "#+SOURCE_LANG: sa\n")
      (insert "#+TIBETAN_TARGET_LANG: de\n\n")
      (insert "* Tibetan Text\n")
      (dolist (sec sections)
        (cl-incf sec-num)
        (insert (format "** Section %s\n" (car sec)))
        (insert ":PROPERTIES:\n"
                (format ":LOPEZ_SECTION: %d\n" sec-num)
                ":END:\n")
        (dolist (block (cdr sec))
          (if (tibetan-cascade--sanskrit-block-verse-p block)
              ;; Verse: one sentence, one segment per pāda line.
              (progn
                (cl-incf sent-num)
                (insert (format "*** Sentence %d\n" sent-num))
                (dolist (line (split-string block "\n" t))
                  (let ((pada (string-trim line)))
                    (unless (string-empty-p pada)
                      (cl-incf seg-num)
                      (insert (format "**** Segment %d\n%s\n\n"
                                      seg-num pada))))))
            ;; Prose: each daṇḍa unit = its own sentence + segment.
            (dolist (unit (tibetan-cascade--sanskrit-split-prose block))
              (let ((u (string-trim unit)))
                (unless (string-empty-p u)
                  (cl-incf sent-num)
                  (cl-incf seg-num)
                  (insert (format "*** Sentence %d\n" sent-num))
                  (insert (format "**** Segment %d\n%s\n\n"
                                  seg-num u)))))))))
    (when (called-interactively-p 'interactive)
      (message "Sanskrit-Import: %d Section%s, %d Sätze, %d Segmente → %s"
               sec-num (if (= 1 sec-num) "" "s") sent-num seg-num
               (file-name-nondirectory output-file)))
    (list :sections sec-num :sentences sent-num :segments seg-num
          :file output-file)))

(defun tibetan-cascade-import-comparative (comparative-file output-file)
  "One-time import of a §-comparative document into a cascade CAT source.

COMPARATIVE-FILE is GENERATOR-OWNED (build_comparative_doc.py —
hand-edits are lost on re-run), so it must never become the CAT
source itself.  This importer extracts, per `** §N' subtree, the
`*** Tibetisch (B2)' body and the Lopez anchors
\(:SECTION:/:B2_SEG_START:/:B2_SEG_END:) into OUTPUT-FILE:

  ** Section §N          with :LOPEZ_SECTION: + the B2 anchors
  *** Segment M          ONE initial segment per § (global numbering)

The copyrighted §-level reference translations (Lopez, Wangjié &
Mulligan, …) and the Wylie are NEVER copied — the CAT source points
back via `#+TIBETAN_SECTION_REFS:' and the prompt builder injects
them as ¶-context at request time (C7.2).

After importing: run `tibetan-shad-split-segments' (segment = shad
unit) and then the genre-aware `tibetan-add-sentence-structure' on
OUTPUT-FILE.  Refuses to overwrite an existing OUTPUT-FILE — it is
hand-owned from the moment it exists.  Returns
\(:sections N :segments N :file OUTPUT-FILE)."
  (interactive
   (list (read-file-name "Comparative document: " nil nil t)
         (read-file-name "CAT source to create: ")))
  (unless (and comparative-file (file-readable-p comparative-file))
    (user-error "Comparative document not readable: %s" comparative-file))
  (when (file-exists-p output-file)
    (user-error
     "%s already exists — the CAT source is hand-owned once created"
     (file-name-nondirectory output-file)))
  (let ((sections '()))
    ;; Collect (§-num b2-start b2-end tibetan-body) per § subtree.
    (with-temp-buffer
      (insert-file-contents comparative-file)
      (goto-char (point-min))
      (while (re-search-forward "^\\*\\* §\\([0-9]+\\)" nil t)
        (let* ((secnum (string-to-number (match-string 1)))
               (limit (save-excursion
                        (if (re-search-forward "^\\*\\* " nil t)
                            (line-beginning-position)
                          (point-max))))
               (b2-start nil) (b2-end nil) (tib nil))
          (save-excursion
            (when (re-search-forward
                   "^:B2_SEG_START:[ \t]*\\([0-9]+\\)" limit t)
              (setq b2-start (match-string 1))))
          (save-excursion
            (when (re-search-forward
                   "^:B2_SEG_END:[ \t]*\\([0-9]+\\)" limit t)
              (setq b2-end (match-string 1))))
          (save-excursion
            (when (re-search-forward "^\\*\\*\\* Tibetisch (B2)$" limit t)
              (forward-line 1)
              (let ((start (point))
                    (end (if (re-search-forward "^\\*\\{1,3\\} " limit t)
                             (line-beginning-position)
                           limit)))
                (setq tib (string-trim
                           (buffer-substring-no-properties start end))))))
          (push (list secnum b2-start b2-end tib) sections)
          (goto-char limit))))
    (setq sections (nreverse sections))
    (unless sections
      (user-error "No `** §N' subtrees found in %s"
                  (file-name-nondirectory comparative-file)))
    ;; Emit the CAT source.
    (let ((refs (file-relative-name
                 comparative-file (file-name-directory
                                   (expand-file-name output-file))))
          (seg 0))
      (with-temp-file output-file
        (insert (format "#+TITLE: %s — CAT-Quelle (B2)\n"
                        (file-name-base output-file)))
        (insert "#+STARTUP: showall\n")
        (insert "#+OPTIONS: toc:nil num:nil\n")
        (insert "#+TIBETAN_LAYOUT: cascade\n")
        (insert "#+TIBETAN_TARGET_LANG: de\n")
        (insert (format "#+TIBETAN_SECTION_REFS: %s\n" refs))
        (insert (format "#+CREATED: %s\n"
                        (format-time-string "%Y-%m-%d")))
        (insert "\n")
        (insert "# Einmalig importiert aus dem generator-eigenen\n"
                (format "# Komparativdokument (%s).\n"
                        (file-name-nondirectory comparative-file))
                "# Ab jetzt HAND-EIGEN — der Importer überschreibt nie.\n"
                "# Nächste Schritte: M-x tibetan-shad-split-segments,\n"
                "# dann C-c s S (genre-bewusste Satzstruktur).\n\n")
        (insert "* Tibetan Text\n")
        (dolist (sec sections)
          (cl-destructuring-bind (secnum b2-start b2-end tib) sec
            (insert (format "** Section §%d\n" secnum))
            (insert ":PROPERTIES:\n")
            (insert (format ":LOPEZ_SECTION: %d\n" secnum))
            (when b2-start
              (insert (format ":B2_SEG_START: %s\n" b2-start)))
            (when b2-end
              (insert (format ":B2_SEG_END: %s\n" b2-end)))
            (insert ":END:\n\n")
            (cl-incf seg)
            (insert (format "*** Segment %d\n" seg))
            (insert (if (and tib (not (string-empty-p tib)))
                        tib
                      "[B2-Text fehlt — im Komparativdokument ergänzen]")
                    "\n\n"))))
      (when (called-interactively-p 'any)
        (message "Imported %d §§ → %s (now: shad-split + C-c s S)"
                 (length sections)
                 (file-name-nondirectory output-file)))
      (list :sections (length sections) :segments seg
            :file output-file))))

;; ============================================================================
;; C7.2 — §-refs ¶-context (USER prompt only; system stays constant)
;; ============================================================================

(defun tibetan-cascade--sentence-lopez-section (source-file sent-num)
  "The :LOPEZ_SECTION: of the Section wrapping SENT-NUM, or nil."
  (when (and source-file (file-readable-p source-file) sent-num)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents source-file)
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^\\*+ Sentence %d\\b" sent-num) nil t)
            (when (re-search-backward "^\\*\\{1,2\\} Section\\b" nil t)
              (forward-line 1)
              (when (looking-at "^:PROPERTIES:$")
                (let ((end (save-excursion
                             (re-search-forward "^:END:$" nil t))))
                  (when (and end
                             (re-search-forward
                              "^:LOPEZ_SECTION:[ \t]*\\([0-9]+\\)" end t))
                    (string-to-number (match-string 1))))))))
      (error nil))))

(defun tibetan-cascade--section-refs-block (sentence source-file)
  "The §-level reference-translation block for SENTENCE's Section.
Resolves `#+TIBETAN_SECTION_REFS:' relative to SOURCE-FILE, locates
the `** §N' subtree, and collects every `*** <name>' child EXCEPT
the B2 Tibetan and the Wylie — i.e. Lopez, Wangjié & Mulligan, and
any additional §-indexed translations the generator carries.  The
bodies stay in the comparative file and the prompt: they are NEVER
written into analysis files (copyright + regen safety).  nil when
anything along the chain is missing."
  (let* ((refs-rel (and (fboundp 'tibetan-analysis--read-source-metadata)
                        (plist-get
                         (tibetan-analysis--read-source-metadata
                          source-file)
                         :section-refs)))
         (refs-file (and refs-rel
                         (expand-file-name
                          refs-rel (file-name-directory
                                    (expand-file-name source-file)))))
         (secnum (and refs-file (file-readable-p refs-file)
                      (tibetan-cascade--sentence-lopez-section
                       source-file (plist-get sentence :sent-num)))))
    (when secnum
      (let ((bodies (tibetan-cascade--section-ref-bodies
                     refs-file secnum)))
        (when bodies
          (concat
           (format
            "\n\nReference translations for Lopez §%d (¶-level context ONLY — they span several sentences; do NOT copy their wording, and never reproduce them in your output sections):\n"
            secnum)
           (mapconcat (lambda (nb)
                        (format "=== %s ===\n%s" (car nb) (cdr nb)))
                      bodies "\n")))))))

(defun tibetan-cascade--section-ref-bodies (refs-file secnum)
  "Die §-Referenzübersetzungen aus REFS-FILE für Lopez-§ SECNUM:
\((NAME . BODY) …) in Dateireihenfolge — jedes `*** <name>'-Kind
des `** §N'-Subtrees AUSSER dem B2-Tibetisch und dem Wylie (also
Lopez, Wangjié & Mulligan, Thakchoe/Hessel wo vorhanden).
:PROPERTIES:-Drawer (:READ_ONLY: etc.) werden übersprungen.  nil
wenn Datei/§/Inhalte fehlen; signalisiert nie.

P1 (§5.58): aus `tibetan-cascade--section-refs-block'
herausgelöst — Konsumenten sind der User-Prompt (Block-Format
unverändert) und die Materialisierung nach * Provided
Translations (P2)."
  (when (and refs-file (file-readable-p refs-file) secnum)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents refs-file)
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^\\*\\* §%d\\b" secnum) nil t)
            (let ((limit (save-excursion
                           (if (re-search-forward "^\\*\\* " nil t)
                               (line-beginning-position)
                             (point-max))))
                  (bodies '()))
              (while (re-search-forward
                      "^\\*\\*\\* \\(.+\\)$" limit t)
                (let ((name (string-trim (match-string 1))))
                  (forward-line 1)
                  ;; Skip a :PROPERTIES: drawer (:READ_ONLY: etc.).
                  (when (looking-at "^:PROPERTIES:$")
                    (when (re-search-forward "^:END:$" limit t)
                      (forward-line 1)))
                  (let* ((start (point))
                         (end (if (re-search-forward
                                   "^\\*\\{1,3\\} " limit t)
                                  (progn (goto-char
                                          (line-beginning-position))
                                         (point))
                                limit))
                         (body (string-trim
                                (buffer-substring-no-properties
                                 start end))))
                    (unless (or (string-prefix-p "Tibetisch" name)
                                (string-prefix-p "Wylie" name)
                                (string-empty-p body))
                      (push (cons name body) bodies)))))
              (nreverse bodies))))
      (error nil))))

(defun tibetan-cascade--pt-region ()
  "Bounds (START . END) des `* Provided Translations'-Bodys im
aktuellen Buffer, oder nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Provided Translations[ \t]*$" nil t)
      (forward-line 1)
      (let ((start (point))
            (end (if (re-search-forward "^\\* " nil t)
                     (line-beginning-position)
                   (point-max))))
        (cons start end)))))

(defun tibetan-cascade--pt-slot-present-p (name)
  "Non-nil wenn `** NAME' bereits im Provided-Translations-Body
des aktuellen Buffers steht (EINMALIG-Gate: ein vorhandener Slot
— auch hand-gekürzt oder geleert — wird nie überschrieben)."
  (let ((region (tibetan-cascade--pt-region)))
    (when region
      (save-excursion
        (goto-char (car region))
        (re-search-forward
         (format "^\\*\\* %s[ \t]*$" (regexp-quote name))
         (cdr region) t)))))

(defun tibetan-cascade--pt-insert-slot (name body)
  "`** NAME' mit BODY ans Ende des Provided-Translations-Bodys
des aktuellen Buffers einsetzen; t bei Erfolg."
  (let ((region (tibetan-cascade--pt-region)))
    (when region
      (save-excursion
        (goto-char (cdr region))
        (skip-chars-backward " \t\n")
        (forward-line 1)
        (insert "** " name "\n"
                (string-trim-right body) "\n\n")
        t))))

;;;###autoload
(defun tibetan-cascade-materialize-provided-translations (target)
  "Materialisiere die §-Referenzübersetzungen in TARGET (Satzdatei
oder analysis/-Ordner): jedes `*** <name>'-Kind des zugehörigen
`** §N' der `#+TIBETAN_SECTION_REFS:'-Comparative (Lopez 2006,
Wangjié & Mulligan, …; NIE Tibetisch/Wylie) wird als `** <name>'
unter `* Provided Translations' der Satzdatei eingesetzt.

EINMALIG (Carstens Entscheidung 09.10.): ein bereits vorhandener
Slot wird nie angefasst — die Kopien sind danach editierbar (z. B.
W&M-Mehr-§-Blöcke von Hand zuschneiden; das [W&M ¶N, PDF-S. N]-
Präfix trägt den Hinweis) und über die keep-l1-Preservation des
Provided-Translations-Subtrees regenerate-geschützt.  Copyright:
die §5.54-Poison-Locks halten die Bodies aus Stitcher und
§-Ansicht heraus.  Headless-tauglich; Rückgabe-Plist
\(:written :skipped :missing)."
  (interactive "fSatzdatei oder analysis/-Ordner: ")
  (let* ((files (if (file-directory-p target)
                    (sort (directory-files
                           target t
                           "\\`sent-[0-9]+\\(?:-[A-Za-z0-9]+\\)?\\.org\\'")
                          #'string<)
                  (list target)))
         (written 0) (skipped 0) (missing 0))
    (dolist (file files)
      (let* ((source (and (fboundp 'tibetan-sentence--source-file-from-analysis)
                          (tibetan-sentence--source-file-from-analysis
                           file)))
             (sent (and (fboundp 'tibetan-sentence--sent-id-from-filename)
                        (tibetan-sentence--sent-id-from-filename file)))
             (secnum (and source sent
                          (tibetan-cascade--sentence-lopez-section
                           source sent)))
             (refs-rel (and secnum
                            (fboundp 'tibetan-analysis--read-source-metadata)
                            (plist-get
                             (tibetan-analysis--read-source-metadata
                              source)
                             :section-refs)))
             (refs-file (and refs-rel
                             (expand-file-name
                              refs-rel (file-name-directory
                                        (expand-file-name source)))))
             (bodies (and refs-file
                          (tibetan-cascade--section-ref-bodies
                           refs-file secnum))))
        (if (not bodies)
            (cl-incf missing)
          (let ((buf (tibetan-fresh-file-buffer file))
                (any nil))
            (with-current-buffer buf
              (save-excursion
                (dolist (nb bodies)
                  (unless (or
                           ;; Carstens EIGENE Comparative-Rubrik
                           ;; („Übersetzung CP") wird NIE dupliziert
                           ;; — seine autorschaftliche Ebene hat
                           ;; genau eine Quelle (Comparative bzw.
                           ;; * Working Translation); zwei Kopien
                           ;; drifteten sofort (Korpus-Befund
                           ;; 09.10.: 21 Dateien).  Der PROMPT-Pfad
                           ;; (--section-refs-block) bleibt
                           ;; unverändert.
                           (string-prefix-p "Übersetzung" (car nb))
                           (tibetan-cascade--pt-slot-present-p
                            (car nb)))
                    (when (tibetan-cascade--pt-insert-slot
                           (car nb) (cdr nb))
                      (setq any t)))))
              (if any
                  (progn (save-buffer) (cl-incf written))
                (cl-incf skipped)))))))
    (when (called-interactively-p 'any)
      (message "Provided Translations: %d Datei(en) befüllt, %d übersprungen, %d ohne §-Referenzen"
               written skipped missing))
    (list :written written :skipped skipped :missing missing)))

;;;###autoload
(defun tibetan-cascade-migrate-structure-v2 (folder)
  "Migriere alle Kaskaden-Satzdateien in FOLDER auf die
§5.58-Reading-Class-Struktur.  Je Datei ein PURES
Preserve-Regenerate (`tibetan-cascade-reanalyze-file' mit
re-request-claude nil — das Regenerate IST die Migration, S2;
trotz der per B3 geöffneten Fire-Gates wird NIE gefeuert).
Two-File-Satzdateien (ohne `#+TIBETAN_LAYOUT: cascade') werden
übersprungen.  Resume-fähig: Fehler werden gesammelt, der Lauf
geht weiter.  Betriebsrezept (M3): git-Snapshot vorher, Dry-Run
auf einer Scratch-Kopie, Diff-Review, Lauf, Idempotenz-Zweitlauf.
Rückgabe (:total :ok :skipped :failed :failures ((FILE . ERR)…))."
  (interactive "DAnalysis-Ordner: ")
  (let* ((files (sort (directory-files
                       folder t
                       "\\`sent-[0-9]+\\(?:-[A-Za-z0-9]+\\)?\\.org\\'")
                      #'string<))
         (ok 0) (skipped 0) (failed 0) (failures '()))
    (dolist (file files)
      (if (not (and (fboundp 'tibetan-cascade-file-p)
                    (tibetan-cascade-file-p file)))
          (cl-incf skipped)
        (let ((r (condition-case err
                     (tibetan-cascade-reanalyze-file file)
                   (error (list :ok nil
                                :error (error-message-string err))))))
          (if (plist-get r :ok)
              (cl-incf ok)
            (cl-incf failed)
            (push (cons file (plist-get r :error)) failures)))))
    (when (called-interactively-p 'any)
      (message "Migration v2: %d ok, %d übersprungen (Two-File), %d fehlgeschlagen"
               ok skipped failed))
    (list :total (length files) :ok ok :skipped skipped
          :failed failed :failures (nreverse failures))))

;; ============================================================================
;; CH2c — fire-section + UX
;; ============================================================================

(declare-function tibetan-dharmamitra-translation-fire-section
                  "tibetan-dharmamitra-translation")
(defvar tibetan-sentence-claude--dm-schedule-count)
(defvar tibetan-dharmamitra-sentence-request-delay)

(defun tibetan-cascade--schedule-dm-section (chunk files force)
  "Schedule ONE DharmaMitra call for CHUNK's whole text — staggered
against the 10/min limit like the §5.40 sentence DM, but one call
per SECTION instead of one per sentence."
  (when (and files
             (fboundp 'tibetan-dharmamitra-translation-fire-section)
             (boundp 'tibetan-sentence-claude--dm-schedule-count)
             (boundp 'tibetan-dharmamitra-sentence-request-delay))
    (let ((delay (* tibetan-sentence-claude--dm-schedule-count
                    tibetan-dharmamitra-sentence-request-delay))
          (text (mapconcat (lambda (s)
                             (mapconcat #'cdr (plist-get s :segs) ""))
                           (plist-get chunk :sentences) ""))
          (label (or (plist-get chunk :label) "Section")))
      (cl-incf tibetan-sentence-claude--dm-schedule-count)
      (run-at-time
       delay nil
       (lambda ()
         (condition-case err
             (tibetan-dharmamitra-translation-fire-section
              text label files force)
           (error (message "Section DM fire failed (%s): %s"
                           label (error-message-string err)))))))))

(defun tibetan-cascade--fire-section (chunk source-file folder
                                      &optional force)
  "Fire ONE chunk-level Claude call (translation layer) for CHUNK.
Resolves every member sentence's cascade file; gate = FORCE, any
member needing Claude, or any member Rendering placeholder.  Claim,
queue, and gptel all ride the §5.40 machinery (`chunk' request
flavor); DM rides the same claim at SECTION granularity.  Returns
`fired' / `dedup-hit' / `deferred' / nil."
  (if (and (fboundp 'tibetan-analysis--defer-mt-p)
           (tibetan-analysis--defer-mt-p source-file))
      'deferred
    (let ((sentences
           (delq nil
                 (mapcar
                  (lambda (s)
                    (let* ((sent-num (plist-get s :sent-num))
                           (file (and sent-num
                                      (fboundp 'tibetan-sentence--filepath)
                                      (tibetan-sentence--filepath
                                       sent-num folder source-file))))
                      (when (and file (file-exists-p file))
                        (list :sent-num sent-num
                              :seg-nums (mapcar #'car
                                                (plist-get s :segs))
                              :segs (plist-get s :segs)
                              :file file))))
                  (plist-get chunk :sentences)))))
      (when (and sentences
                 (fboundp 'tibetan-sentence-claude--claim)
                 (fboundp 'tibetan-sentence-claude--request))
        (when (or force
                  (cl-some
                   (lambda (s)
                     (let ((file (plist-get s :file)))
                       (or (and (fboundp
                                 'tibetan-analysis--claude-needs-request-p)
                                (tibetan-analysis--claude-needs-request-p
                                 file))
                           (cl-some
                            (lambda (n)
                              (tibetan-cascade--rendering-needs-request-p
                               file n))
                            (plist-get s :seg-nums)))))
                   sentences))
          (let* ((key (cons 'chunk (plist-get (car sentences) :sent-num)))
                 (label (format "chunk %s"
                                (or (plist-get chunk :label) key))))
            (if (not (tibetan-sentence-claude--claim
                      source-file key label))
                'dedup-hit
              (tibetan-sentence-claude--request
               (list :sent-num key
                     :seg-nums (apply #'append
                                      (mapcar (lambda (s)
                                                (plist-get s :seg-nums))
                                              sentences))
                     :label (plist-get chunk :label)
                     :sentences sentences)
               nil nil source-file folder force 'chunk)
              (tibetan-cascade--schedule-dm-section
               (list :label (plist-get chunk :label)
                     :sentences sentences)
               (mapcar (lambda (s) (plist-get s :file)) sentences)
               force)
              'fired)))))))

;;;###autoload
(defun tibetan-cascade-fire-sections (&optional force)
  "Chunk-fire every section of the current cascade source buffer.
One translation-layer Claude call + one DharmaMitra call per section
chunk (`tibetan-cascade--collect-section-chunks'); everything lands
into the member cascade files.  With prefix FORCE, re-fires
populated sections too."
  (interactive "P")
  (unless (buffer-file-name)
    (user-error "Buffer must be saved to a file first"))
  (unless (and (fboundp 'tibetan-analysis--cascade-p)
               (tibetan-analysis--cascade-p (buffer-file-name)))
    (user-error "Not a cascade document (#+TIBETAN_LAYOUT: cascade)"))
  (let* ((source-file (buffer-file-name))
         (folder (file-name-as-directory
                  (expand-file-name
                   "analysis" (file-name-directory source-file))))
         (chunks (tibetan-cascade--collect-section-chunks))
         (fired 0) (other 0))
    (unless chunks
      (user-error "No sentences found"))
    (dolist (c chunks)
      (if (eq 'fired (tibetan-cascade--fire-section
                      c source-file folder force))
          (cl-incf fired)
        (cl-incf other)))
    (message "Chunk-fire: %d section call%s queued, %d skipped/deferred"
             fired (if (= 1 fired) "" "s") other)
    (list :fired fired :skipped other)))

(provide 'tibetan-cascade)
;;; tibetan-cascade.el ends here
