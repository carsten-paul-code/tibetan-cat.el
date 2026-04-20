;;; tibetan-sentence-structure.el --- Add sentence structure to Tibetan documents -*- lexical-binding: t -*-

;;; Commentary:
;; Provides functions to automatically detect and add sentence-level
;; structure to existing Tibetan .org documents.
;;
;; `tibetan-is-sentence-boundary-p' classifies a segment-ending into one
;; of three confidence levels:
;;
;;   nil      — not a sentence boundary (converb, case particle, topic
;;              marker, coordinator, no shad, fused ergative)
;;   'strong  — high confidence: double shad, sentence-final particle,
;;              or known finite verb form
;;   'weak    — bare single shad on a multi-syllable phrase (typically
;;              a finite past verb not in the explicit list)
;;
;; Both 'strong and 'weak are truthy, so callers that want a simple
;; boolean (`when'/`if') still work.  The auto-segmenter
;; (`tibetan-add-sentence-structure') and preview
;; (`tibetan-detect-sentence-boundaries') accept a prefix argument to
;; include 'weak hits; without the prefix they are strong-only and
;; deliberately conservative.
;;
;; Usage:
;;   M-x tibetan-detect-sentence-boundaries      ; preview strong only
;;   C-u M-x tibetan-detect-sentence-boundaries  ; preview strong + weak
;;   M-x tibetan-add-sentence-structure          ; apply strong only
;;   C-u M-x tibetan-add-sentence-structure      ; apply strong + weak
;;   M-x tibetan-mark-sentence-start             ; manual boundary
;;
;; After running `tibetan-add-sentence-structure', the document has:
;;   ** Section
;;   *** Sentence 1
;;   **** Segment 1
;;   **** Segment 2
;;   *** Sentence 2
;;   **** Segment 3
;;   ...

;;; Code:

(require 'org)
(require 'cl-lib)

;; ============================================================================
;; SENTENCE BOUNDARY DETECTION
;; ============================================================================

(defvar tibetan-sentence-final-particles
  '("སོ" "ཏོ" "ནོ" "དོ" "རོ" "འོ" "ངོ"   ; Sentence-final particles
    "གོ" "བོ"                            ; More sentence finals
    "ཡིན" "མིན"                          ; Copulas (often end sentences)
    "ཡོད" "མེད"                          ; Existentials
    ;; Finite verb forms common in rnam thar prose
    "ཟེར" "གསུངས" "སྨྲས" "བྱས" "བྱུང" "གྱུར" "ཤོག" "མཛད"
    ;; Honorific finite verbs (rnam thar style)
    "བྱོན"       ; "went / came" (hon., past of འགྲོ / འོང)
    "བཞུགས"     ; "resided / stayed" (hon.)
    "གནང"        ; "gave / did" (hon.)
    "གསུང"       ; "said" (hon., present; past གསུངས already listed)
    "གཤེགས"     ; "passed away / went" (hon.)
    "བགྱིས"     ; "did" (hon., past)
    "ཞུས"        ; "requested" (hon., past)
    ;; Past-tense finite verbs (profiled from Milarepa rnam thar)
    "སྐྱེས"     ; "was born"
    "འོངས"      ; "came" (past)
    "སོང"        ; "went" (past of འགྲོ)
    "ཤི"         ; "died"
    "བརྫངས"    ; "sent" (past)
    "བལྟམས"    ; "was born" (hon., archaic)
    "བཏགས"     ; "named / gave (a name)"
    "བཅུག"      ; "caused / put" (past)
    "བསྟན"      ; "showed / taught" (past)
    "ཤེས"        ; "knew / knows"
    ;; Future / transformative
    "འགྱུར"     ; "will become" (future; past གྱུར already listed)
    ;; Sentence-final existential
    "འདུག")     ; "exists / is present" (typically sentence-final in cl.)
  "Particles and finite-verb stems that strongly indicate a sentence end
when followed by shad.
Populated in two passes: (a) the traditional sentence-final particle set
(sa, to, no, do, ro, \\='o, ngo, go, bo) and the copulas/existentials,
plus (b) finite verbs harvested from corpus profiling of the Milarepa
rnam thar.  The verb set is deliberately a closed list rather than a
morphology-based heuristic: rnam-thar verb morphology is irregular enough
(stem suppletion, honorific substitution, archaic past forms) that any
rule over stems is lossier than an enumerated list maintained from real
texts.  Extend as new corpora are profiled.")

(defvar tibetan-sentence-converb-particles
  '("ནས" "སྟེ" "ཏེ" "དེ" "ཅིང" "ཞིང" "ཤིང"
    ;; Expanded: nominalizer + case as converbs
    "པས"         ; causal  (X-pas → because X)
    "བས"         ; causal allomorph of པས on non-aspirated nominalizer stems
                 ; (e.g. ཟེར་བས། "because [he] said", མཐོང་བས། "because [he] saw")
    "པར"         ; terminative on nominalizer (so that / into)
    ;; Conditional / concessive
    "ན" "ཀྱང" "ཡང"
    ;; Coordinator / enumerator
    "དང")
  "Converb / clause-connective particles for sentence-boundary detection.
Anything matching here is treated as a clause-internal connective, not a
sentence end.  The `sentence-' prefix disambiguates from the similarly
named variables in `core/tibetan-vocabulary.el' (flat list, used by verb
suffix detection) and `analysis/tibetan-clause-analysis.el' (alist keyed
by converb type, used by clause typing), which have different structure
and purpose.")

(defvar tibetan-case-particle-syllables
  '("ལ" "ར" "སུ" "ཏུ" "དུ"                      ; dative/locative/terminative
    "ཀྱི" "གི" "གྱི" "ཡི" "འི"                    ; genitive
    "ཀྱིས" "གིས" "གྱིས" "ཡིས"                    ; ergative/instrumental
    "ལས"                                         ; ablative
    ;; Indefinite article / determiner
    "ཞིག" "ཅིག" "ཤིག")
  "Case particles and NP modifiers that indicate the clause continues.")

(defvar tibetan-topic-particle-syllables
  '("ནི")
  "Topic markers that typically do NOT end a sentence on their own.")

(defvar tibetan-non-boundary-two-syllable-patterns
  '("པ་ལ" "པ་ན" "པ་ལས"
    ;; Temporal subordinate clause: "at the time of X-ing / when X"
    "པའི་ཚེ" "བའི་ཚེ")
  "Two-syllable (tsheg-separated) patterns that mark a non-final clause.
Covers the case where nominalizer པ and a following case particle are
written as two syllables rather than fused (e.g. པ་ལ vs. པར), and the
fixed nominalizer + genitive + ཚེ pattern that introduces a temporal
subordinate clause (e.g. ཡོད་པའི་ཚེ། \"while being\").")

(defvar tibetan-sentence-dialogue-single-syllables
  '("ཅེས" "ཞེས")
  "Quotative markers that close direct speech with a shad.
`X ཅེས།' and `X ཞེས།' (\"so saith X\") end a reported-speech
sentence — a ubiquitous Milarepa rnam-thar pattern.  Without
this list the detector sees just a multi-syllable phrase ending
in shad and falls through to the weak tier; with it we promote
to strong.")

(defvar tibetan-sentence-dialogue-two-syllable-patterns
  '("ན་རེ"
    ;; Quotative closers with following speech verb that is NOT yet in
    ;; the finite-verb list (the single-syllable verbs ARE, but the
    ;; two-syllable combinations read more cleanly as one unit):
    "ཅེས་སྐད"  ; ...ces skad    "with the words ..."
    "ཞེས་སྐད") ; ...zhes skad   variant
  "Two-syllable dialogue-framing patterns that close a sentence.

`X ན་རེ།' — \"X said:\" — opens a quoted section and typically
ends its own short sentence.  `ཅེས་སྐད' / `ཞེས་སྐད' ending
patterns (`...ces skad') close reported speech.  Both are
STRONG boundaries on the rnam-thar corpus.")

(defun tibetan-extract-particle-text (particle)
  "Extract text from a particle, handling both string and list formats.
If PARTICLE is a string, return it as a single-element list.
If PARTICLE is a list like (type . (\"text1\" \"text2\")), extract all texts.
Returns a list of strings, or nil if extraction fails."
  (cond
   ((stringp particle) (list particle))
   ((and (listp particle) (cdr particle))
    (let ((parts (cdr particle)))
      (cond
       ((stringp parts) (list parts))
       ((listp parts) (cl-remove-if-not #'stringp parts))
       (t nil))))
   (t nil)))

(defun tibetan--last-syllable (text)
  "Return the final tsheg-separated syllable of TEXT, or nil if none.
Strips trailing shad, tsheg, and whitespace before splitting."
  (when text
    (let* ((trimmed (string-trim text))
           (no-shad (replace-regexp-in-string "།+$" "" trimmed))
           (clean (replace-regexp-in-string "[་\n ]+$" "" no-shad))
           (parts (split-string clean "[་\n ]+" t)))
      (car (last parts)))))

(defun tibetan--last-two-syllables (text)
  "Return the last two tsheg-separated syllables of TEXT joined by ་,
or nil if fewer than two syllables remain after stripping shad/tsheg."
  (when text
    (let* ((trimmed (string-trim text))
           (no-shad (replace-regexp-in-string "།+$" "" trimmed))
           (clean (replace-regexp-in-string "[་\n ]+$" "" no-shad))
           (parts (split-string clean "[་\n ]+" t)))
      (when (>= (length parts) 2)
        (mapconcat #'identity (last parts 2) "་")))))

(defun tibetan-is-sentence-boundary-p (text)
  "Determine whether TEXT ends at a sentence boundary.

Return value:
  nil       — not a sentence boundary
  \\='strong — high-confidence boundary (double shad, sentence-final
              particle, known finite verb)
  \\='weak   — probable boundary (bare single shad on a multi-syllable
              phrase, after ruling out converb/case/topic/coordinator).
              In rnam-thar prose this is most commonly a finite past
              verb that is not in the explicit finite-verb list.

Both \\='strong and \\='weak are truthy, so legacy callers that use
the result in `when'/`if' continue to work.  Callers that want to
gate on confidence (e.g. the auto-segmenter defaulting to strong-only)
can test the symbol explicitly with `eq'.

Detection layers, in order:
  1. Double shad (།།, ༎)                                 → strong
  2. No shad at all                                       → nil
  3. Two-syllable non-boundary patterns (e.g. པ་ལ།)       → nil
  4. Converb / clause-connective last syllable            → nil
  5. Case particle last syllable                          → nil
  6. Topic marker last syllable (ནི།)                     → nil
  7. Sentence-final particle / finite verb                → strong
  7b. Dialogue two-syllable pattern (ན་རེ།, ཅེས་སྐད།)    → strong
  7c. Quotative single-syllable closer (ཅེས།, ཞེས།)       → strong
  8. Bare single shad on multi-syllable phrase            → weak
  9. Single-syllable phrase (likely fused ergative)       → nil

Steps 7b and 7c handle Milarepa-style dialogue framing: `X ན་རེ།'
opens a quoted section (short framing sentence), and `X ཅེས།' or
`X ཞེས།' closes one.  Without these, the detector fell through to
the weak tier and required manual confirmation for every reported-
speech boundary — costly on a rnam-thar corpus where dialogue is
the dominant structure."
  (when (and text (> (length (string-trim text)) 0))
    (let* ((trimmed (string-trim text))
           (has-double-shad (or (string-suffix-p "།།" trimmed)
                                (string-suffix-p "༎" trimmed)))
           (has-single-shad (string-suffix-p "།" trimmed))
           (last-syl (tibetan--last-syllable trimmed))
           (last-two (tibetan--last-two-syllables trimmed)))
      (cond
       (has-double-shad 'strong)
       ((not has-single-shad) nil)
       ((and last-two
             (member last-two tibetan-non-boundary-two-syllable-patterns))
        nil)
       ((member last-syl tibetan-sentence-converb-particles) nil)
       ((member last-syl tibetan-case-particle-syllables) nil)
       ((member last-syl tibetan-topic-particle-syllables) nil)
       ((member last-syl tibetan-sentence-final-particles) 'strong)
       ;; Dialogue framing — two-syllable patterns (ན་རེ།, ཅེས་སྐད།).
       ((and last-two
             (member last-two
                     tibetan-sentence-dialogue-two-syllable-patterns))
        'strong)
       ;; Dialogue framing — single-syllable quotative closers (ཅེས།, ཞེས།).
       ((member last-syl tibetan-sentence-dialogue-single-syllables)
        'strong)
       ;; Bare single shad: weak boundary when the last syllable is
       ;; multi-character.  Single-character stems (e.g. fused ergative
       ;; ཁོས → ས) are too ambiguous; leave those as nil.
       ((and last-syl (>= (length last-syl) 2)) 'weak)
       (t nil)))))

(defun tibetan--segment-boundary-at-point ()
  "Return the confidence symbol of the segment heading at point.
One of nil, \\='strong, or \\='weak.  Reads the segment body from
the next line up to the following Org heading."
  (tibetan-is-sentence-boundary-p
   (save-excursion
     (forward-line 1)
     (let ((start (point)))
       (if (re-search-forward "^\\*" nil t)
           (buffer-substring-no-properties start (line-beginning-position))
         (buffer-substring-no-properties start (point-max)))))))

(defun tibetan--collect-segment-boundaries ()
  "Walk the current buffer and return a plist per `*** Segment' heading.
Each plist has the shape (:seg-num N :pos POS :confidence CONF) where
CONF is one of nil, \\='strong, or \\='weak.  Returns them in
document order."
  (let (acc)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\*\\*\\* Segment \\([0-9]+\\)" nil t)
        (let* ((seg-num (string-to-number (match-string 1)))
               (seg-pos (match-beginning 0))
               (conf    (tibetan--segment-boundary-at-point)))
          (push (list :seg-num seg-num :pos seg-pos :confidence conf)
                acc))))
    (nreverse acc)))

(defun tibetan-detect-sentence-boundaries (&optional include-weak)
  "Preview sentence boundaries in the current buffer.

With no prefix argument, show only STRONG boundaries (double shad,
sentence-final particles, finite verbs).  With prefix argument
\(C-u\) also show WEAK boundaries (bare single shad on multi-syllable
phrases — typically finite past verbs not in the explicit list).

The preview lists each sentence start and tags its trigger as
\[strong] or \[weak], and ends with a summary count of each kind."
  (interactive "P")
  (unless (derived-mode-p 'org-mode)
    (error "This command only works in org-mode buffers"))
  (let* ((segs (tibetan--collect-segment-boundaries))
         (threshold (if include-weak '(strong weak) '(strong)))
         (starts '())
         (strong-count 0)
         (weak-count 0)
         ;; Special value 'first for the very first segment — it always
         ;; starts sentence 1, but isn't "triggered" by anything.
         (prev-conf 'first)
         (current-sent 1))
    (dolist (seg segs)
      (let ((conf (plist-get seg :confidence)))
        (when (or (eq prev-conf 'first) (memq prev-conf threshold))
          (push (list :sentence current-sent
                      :segment  (plist-get seg :seg-num)
                      :trigger  (if (eq prev-conf 'first) nil prev-conf))
                starts)
          (setq current-sent (1+ current-sent)))
        (pcase conf
          ('strong (setq strong-count (1+ strong-count)))
          ('weak   (setq weak-count   (1+ weak-count))))
        (setq prev-conf conf)))
    (with-current-buffer (get-buffer-create "*Sentence Boundaries*")
      (erase-buffer)
      (insert "Detected Sentence Structure\n")
      (insert "===========================\n")
      (insert (format "Mode: %s\n"
                      (if include-weak
                          "strong + weak (C-u)"
                        "strong only")))
      (insert (format "Segments: %d | Strong signals: %d | Weak signals: %d\n\n"
                      (length segs) strong-count weak-count))
      (dolist (s (nreverse starts))
        (insert (format "Sentence %3d starts at Segment %3d  [trigger: %s]\n"
                        (plist-get s :sentence)
                        (plist-get s :segment)
                        (or (plist-get s :trigger) "—"))))
      (insert (format "\nTotal: %d sentences detected\n" (1- current-sent)))
      (display-buffer (current-buffer)))))

;; ============================================================================
;; ADD SENTENCE STRUCTURE
;; ============================================================================

(defun tibetan-add-sentence-structure (&optional include-weak)
  "Add *** Sentence N headings to organize segments into sentences.

By default, only STRONG boundaries split sentences (double shad,
sentence-final particles, finite verbs).  With a prefix argument
\(C-u\) also split at WEAK boundaries (bare single shad on a
multi-syllable phrase — typically finite past verbs not in the
explicit list).

The strong-only default is deliberately conservative: rnam-thar
prose has many ambiguous clause-final verbs, and under-segmentation
is cheaper to fix interactively (via `tibetan-mark-sentence-start')
than over-segmentation.

Transforms:
  ** Section
  *** Segment 1
  *** Segment 2
  ...
Into:
  ** Section
  *** Sentence 1
  **** Segment 1
  **** Segment 2
  *** Sentence 2
  **** Segment 3"
  (interactive "P")
  (unless (derived-mode-p 'org-mode)
    (error "This command only works in org-mode buffers"))
  (unless (yes-or-no-p
           (format "Add sentence structure (%s)? This will modify segment headings. "
                   (if include-weak "strong + weak" "strong only")))
    (user-error "Cancelled"))
  (let* ((threshold (if include-weak '(strong weak) '(strong)))
         (segs (tibetan--collect-segment-boundaries))
         (prev-conf 'first)
         (current-sent 1)
         (annotated nil))
    ;; First pass: annotate each segment with :starts-sentence / :sentence-num
    (dolist (seg segs)
      (let* ((conf (plist-get seg :confidence))
             (starts (or (eq prev-conf 'first)
                         (memq prev-conf threshold))))
        (push (append seg
                      (list :starts-sentence starts
                            :sentence-num (and starts current-sent)))
              annotated)
        (when starts (setq current-sent (1+ current-sent)))
        (setq prev-conf conf)))
    ;; Second pass: walk back-to-front and rewrite headings in place.
    ;;
    ;; Every segment (regardless of whether it starts a new sentence)
    ;; must be demoted from `*** Segment' to `**** Segment' so that
    ;; continuation segments end up nested *inside* their parent
    ;; `*** Sentence' heading rather than orphaned as siblings at
    ;; the same level.  Sentence-starter segments additionally get
    ;; a `*** Sentence N' heading inserted above them.
    ;;
    ;; Walking back-to-front keeps every segment's recorded `:pos'
    ;; valid after earlier insertions (those positions are later
    ;; in the buffer and thus processed first).
    (dolist (seg annotated) ; annotated is already in reverse order
      (let ((pos (plist-get seg :pos)))
        (goto-char pos)
        (when (plist-get seg :starts-sentence)
          (insert (format "*** Sentence %d\n"
                          (plist-get seg :sentence-num)))
          (forward-line 0))
        (when (looking-at "\\*\\*\\* Segment")
          (replace-match "**** Segment"))))
    (message "Added sentence structure: %d sentences (%s)"
             (1- current-sent)
             (if include-weak "strong + weak" "strong only"))))

;; ============================================================================
;; MANUAL SENTENCE MARKING
;; ============================================================================

(defun tibetan-mark-sentence-start ()
  "Mark current segment as starting a new sentence.
Inserts a *** Sentence heading above the current segment and demotes
the segment heading from *** to ****."
  (interactive)
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))

    (unless (looking-at "\\*\\*\\*\\* Segment\\|\\*\\*\\* Segment")
      (error "Not on a Segment heading"))

    ;; Find the next available sentence number
    (let ((max-sent 0))
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\*\\* Sentence \\([0-9]+\\)" nil t)
          (setq max-sent (max max-sent (string-to-number (match-string 1))))))

      ;; Insert sentence heading
      (let ((sent-num (1+ max-sent)))
        (beginning-of-line)
        (insert (format "*** Sentence %d\n" sent-num))
        ;; Demote segment if needed
        (when (looking-at "\\*\\*\\* Segment")
          (replace-match "**** Segment"))
        (message "Marked as start of Sentence %d" sent-num)))))

;; ============================================================================
;; RESET STRUCTURE — undoes what `tibetan-add-sentence-structure' did
;; ============================================================================

(defun tibetan-sentence-reset-structure--counts (buffer)
  "Return (SENT-COUNT . SEG-COUNT) — how many `*** Sentence N' headings
and how many `**** Segment M' (demoted) headings BUFFER contains.
Used by the reset command to show the user what it will touch."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((sents 0)
            (segs  0))
        (while (re-search-forward "^\\*\\*\\* Sentence [0-9]+\\b" nil t)
          (setq sents (1+ sents)))
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\*\\*\\* Segment " nil t)
          (setq segs (1+ segs)))
        (cons sents segs)))))

;;;###autoload
(defun tibetan-sentence-reset-structure ()
  "Undo the effect of `tibetan-add-sentence-structure' on the current buffer.

Two reversible edits:
  1. Delete every `^\\*\\*\\* Sentence N$' heading line (and the
     single trailing blank line that usually follows, if present).
  2. Re-promote every `^\\*\\*\\*\\* Segment M' back to
     `^\\*\\*\\* Segment M' so the next
     `tibetan-add-sentence-structure' run can discover them again.

Prompts with a summary of how many headings will be removed /
promoted before touching the buffer.  Does NOT save; user reviews
the edit, then `C-x C-s' when satisfied.  Idempotent — safe to
run repeatedly.

Intended use: before running `C-c s S' a SECOND time on a file
whose structure is already in place.  The segment regex in the
auto-segmenter only matches three-asterisk `*** Segment', so
without resetting the demoted segments a re-run would silently
find zero segments and do nothing useful."
  (interactive)
  (let* ((counts (tibetan-sentence-reset-structure--counts
                  (current-buffer)))
         (sents  (car counts))
         (segs   (cdr counts)))
    (cond
     ((and (= sents 0) (= segs 0))
      (message "Nothing to reset — buffer has no `*** Sentence' headings and no demoted `**** Segment' headings."))
     ((not (yes-or-no-p
            (format "Reset sentence structure? This will remove %d `*** Sentence N' heading%s and re-promote %d `**** Segment M' → `*** Segment M'. "
                    sents (if (= sents 1) "" "s")
                    segs)))
      (message "Reset cancelled."))
     (t
      (save-excursion
        ;; Step 1 — remove `*** Sentence N' heading lines (with a
        ;; trailing blank line if present, so we don't leave
        ;; run-together blank gaps).
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\*\\* Sentence [0-9]+[^\n]*\n" nil t)
          (replace-match "" t t)
          (when (looking-at "^[ \t]*\n")
            (delete-region (point) (line-beginning-position 2))))
        ;; Step 2 — re-promote demoted segments.
        (goto-char (point-min))
        (while (re-search-forward "^\\(\\*\\*\\*\\)\\* Segment " nil t)
          (replace-match "\\1 Segment " t nil nil 0)))
      (message
       "Reset: removed %d sentence heading%s; re-promoted %d segment heading%s.  Review, then `C-x C-s' to save."
       sents (if (= sents 1) "" "s")
       segs  (if (= segs 1)  "" "s"))))))


(provide 'tibetan-sentence-structure)
;;; tibetan-sentence-structure.el ends here
