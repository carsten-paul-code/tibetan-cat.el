;;; tibetan-analysis-claude-prompt-test.el --- Tests for Claude prompt enrichment -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for the source-aware Claude translation prompt built by
;; `tibetan-analysis--build-claude-prompts'.  Exercise the three input
;; sources that shape the prompt:
;;   1. #+TITLE / :WORK / :AUTHOR / :SOURCES from the source file
;;   2. #+TIBETAN_CLAUDE_CONTEXT: headers (multi-line, repeatable)
;;   3. Resources vocabulary matches (so proper names / technical terms
;;      are not paraphrased away)
;;
;; gptel is stubbed: no network activity; we inspect the prompt that
;; `tibetan-analysis--request-claude-translation' *would* have sent.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((root (expand-file-name ".." (file-name-directory
                                    (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path root)
  (add-to-list 'load-path (expand-file-name "core" root))
  (add-to-list 'load-path (expand-file-name "persist" root))
  (add-to-list 'load-path (expand-file-name "analysis" root))
  (add-to-list 'load-path (expand-file-name "data" root))
  (add-to-list 'load-path (expand-file-name "philology" root))
  (add-to-list 'load-path (expand-file-name "config" root)))

(require 'tibetan-analysis-persist)

;; ============================================================================
;; HELPERS
;; ============================================================================

(defun tibetan-test--write (path text)
  "Write TEXT to PATH, creating parent directories."
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert text)))

(defmacro tibetan-test--with-source (source-contents &rest body)
  "Write SOURCE-CONTENTS to a temp source.org, bind SOURCE-FILE, eval BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-claude-prompt-" t))
          (source-file (expand-file-name "source.org" dir)))
     (unwind-protect
         (progn
           (tibetan-test--write source-file ,source-contents)
           ,@body)
       (delete-directory dir t))))

;; ============================================================================
;; METADATA EXTRACTION
;; ============================================================================

(ert-deftest tibetan-claude-prompt-reads-title-and-properties ()
  "WORK/AUTHOR/SOURCES from the first :PROPERTIES: drawer are captured."
  (tibetan-test--with-source
      "#+TITLE: Milarepa\n#+AUTHOR: Carsten Paul\n\n* bKa' bum\n:PROPERTIES:\n:WORK: Mila rnam thar\n:AUTHOR: gTsang smyon He ru ka\n:SOURCES: fol. 1a1\n:END:\n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (equal (plist-get meta :title) "Milarepa"))
      (should (equal (plist-get meta :work)  "Mila rnam thar"))
      (should (equal (plist-get meta :author) "gTsang smyon He ru ka"))
      (should (equal (plist-get meta :sources) "fol. 1a1")))))

(ert-deftest tibetan-claude-prompt-collects-multiple-context-headers ()
  "Every `#+TIBETAN_CLAUDE_CONTEXT:' line is collected in source order."
  (tibetan-test--with-source
      "#+TITLE: T\n#+TIBETAN_CLAUDE_CONTEXT: Kadampa blo sbyong verse.\n#+TIBETAN_CLAUDE_CONTEXT: Target language: English.\n#+TIBETAN_CLAUDE_CONTEXT: For PNs see Sörensen & Hazod 2007.\n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (equal (plist-get meta :claude-context)
                     '("Kadampa blo sbyong verse."
                       "Target language: English."
                       "For PNs see Sörensen & Hazod 2007."))))))

(ert-deftest tibetan-analysis-target-lang-dynamic-binding-from-header ()
  "When `tibetan-analysis-generate-content' is called with a SOURCE-FILE
carrying a `#+TIBETAN_TARGET_LANG: de' header, the dynamic var
`tibetan-analysis--target-lang' is bound to `\"de\"' for the
duration of the call.  Callers that don't pass SOURCE-FILE leave
the dynamic var at its outer value (nil by default, meaning
English-preferred)."
  (tibetan-test--with-source
      "#+TITLE: T\n#+TIBETAN_TARGET_LANG: de\n"
    (let ((captured-lang nil))
      (cl-letf (((symbol-function 'tibetan-analysis--filter-to-tibetan-lines)
                 (lambda (text)
                   (setq captured-lang tibetan-analysis--target-lang)
                   text)))
        ;; Nil initial value; generate-content must rebind to "de"
        ;; for the body of the call.
        (let ((tibetan-analysis--target-lang nil))
          (ignore-errors
            (tibetan-analysis-generate-content
             "བདག་" nil nil source-file))
          (should (equal captured-lang "de")))))))

(ert-deftest tibetan-analysis-cat-english-gloss-respects-target-lang ()
  "`--cat-english-gloss' (the CAT Gloss helper that extracts a
short gloss from a bilingual entry) must pick the GERMAN half
when `tibetan-analysis--target-lang' is `\"de\"', so the CAT
line reads in German for a document whose header selects German.
Default (nil / `en') keeps the English-preferred legacy behavior."
  (let ((gloss "Heimat // homeland"))
    (let ((tibetan-analysis--target-lang nil))
      (should (equal "homeland"
                     (tibetan-analysis--cat-english-gloss gloss))))
    (let ((tibetan-analysis--target-lang "en"))
      (should (equal "homeland"
                     (tibetan-analysis--cat-english-gloss gloss))))
    (let ((tibetan-analysis--target-lang "de"))
      (should (equal "Heimat"
                     (tibetan-analysis--cat-english-gloss gloss))))))

(ert-deftest tibetan-analysis-target-lang-no-header-leaves-nil ()
  "When the source file has no `#+TIBETAN_TARGET_LANG:' header, the
dynamic var stays at its outer value — downstream helpers treat
nil as \"prefer English\" for backward compatibility."
  (tibetan-test--with-source
      "#+TITLE: T\n"
    (let ((captured-lang :untouched))
      (cl-letf (((symbol-function 'tibetan-analysis--filter-to-tibetan-lines)
                 (lambda (text)
                   (setq captured-lang tibetan-analysis--target-lang)
                   text)))
        (let ((tibetan-analysis--target-lang nil))
          (ignore-errors
            (tibetan-analysis-generate-content
             "བདག་" nil nil source-file))
          (should (null captured-lang)))))))

(ert-deftest tibetan-claude-prompt-injects-german-target-directive ()
  "When the source carries `#+TIBETAN_TARGET_LANG: de', the built
system prompt includes a clear instruction for Claude to produce
the `## Translation' section in German.  Without the header (or
with `en'), the prompt stays English-directed for backward
compatibility — no German instruction injected."
  (tibetan-test--with-source
      "#+TITLE: T\n#+TIBETAN_TARGET_LANG: de\n"
    (let* ((prompts (tibetan-analysis--build-claude-prompts
                     "བདག་" source-file))
           (system (car prompts)))
      ;; Some kind of German-instruction phrase present.
      (should (string-match-p "German\\|auf Deutsch\\|deutsch"
                              system))))
  ;; No header → no German directive.
  (tibetan-test--with-source
      "#+TITLE: T\n"
    (let* ((prompts (tibetan-analysis--build-claude-prompts
                     "བདག་" source-file))
           (system (car prompts)))
      (should-not (string-match-p "produce.*German\\|in German"
                                  system)))))

(ert-deftest tibetan-claude-prompt-reads-target-lang-header ()
  "`#+TIBETAN_TARGET_LANG:' header is captured under the
`:target-lang' key so the renderer and Claude prompt can pick
German or English as the primary visible translation for this
specific document.  Values are lowercased; `en' / `de' are the
canonical forms.  Blank value → nil (treat as unset); missing
header → nil."
  (tibetan-test--with-source
      "#+TITLE: Milarepa IV\n#+TIBETAN_TARGET_LANG: de\n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (equal (plist-get meta :target-lang) "de"))))
  ;; Uppercase normalised to lowercase for predictable downstream matching.
  (tibetan-test--with-source
      "#+TITLE: T\n#+TIBETAN_TARGET_LANG: EN\n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (equal (plist-get meta :target-lang) "en"))))
  ;; Missing header → nil (implicit default English handled by callers).
  (tibetan-test--with-source
      "#+TITLE: T\n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (null (plist-get meta :target-lang)))))
  ;; Blank value treated as unset.
  (tibetan-test--with-source
      "#+TITLE: T\n#+TIBETAN_TARGET_LANG:   \n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (null (plist-get meta :target-lang))))))

(ert-deftest tibetan-claude-prompt-reads-corpus-header ()
  "`#+TIBETAN_CORPUS:' header is captured under the `:corpus' key so the
dictionary ranker can promote the corresponding Steinert sub-dictionary."
  (tibetan-test--with-source
      "#+TITLE: YBh Gotrapatala\n#+TIBETAN_CORPUS: Yogacarabhumi\n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (equal (plist-get meta :corpus) "Yogacarabhumi"))))
  ;; Missing header → nil
  (tibetan-test--with-source
      "#+TITLE: No corpus header\n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (null (plist-get meta :corpus)))))
  ;; Blank value after the header key is treated as unset
  (tibetan-test--with-source
      "#+TITLE: T\n#+TIBETAN_CORPUS:   \n"
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (null (plist-get meta :corpus))))))

;; ============================================================================
;; set-source-target-lang — configure translation language on source file
;; ============================================================================

(ert-deftest tibetan-analysis-set-source-target-lang-adds-missing-header ()
  "`tibetan-analysis-set-source-target-lang' adds
`#+TIBETAN_TARGET_LANG: de' when no header exists yet, placing
it right after `#+TITLE:' to keep metadata contiguous at the
top of the source file."
  (tibetan-test--with-source
      "#+TITLE: Gotrapaṭala — Yogācārabhūmi\n#+AUTHOR: Asaṅga\n\n* Segment 1\n..."
    (tibetan-analysis-set-source-target-lang source-file "de")
    (with-temp-buffer
      (insert-file-contents source-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^#\\+TIBETAN_TARGET_LANG: de$" s))
        ;; Header lands between #+TITLE and blank line (contiguous
        ;; with other metadata; order matters for readability).
        (should (string-match-p
                 "#\\+TITLE:.*\n#\\+TIBETAN_TARGET_LANG: de"
                 s))))
    ;; Subsequent read via --read-source-metadata sees the value.
    (let ((meta (tibetan-analysis--read-source-metadata source-file)))
      (should (equal (plist-get meta :target-lang) "de")))))

(ert-deftest tibetan-analysis-set-source-target-lang-updates-existing ()
  "When the source already has a `#+TIBETAN_TARGET_LANG:' line,
the command replaces its value in place — no duplicate header
and no line duplication."
  (tibetan-test--with-source
      "#+TITLE: T\n#+TIBETAN_TARGET_LANG: en\n\n* Body\n"
    (tibetan-analysis-set-source-target-lang source-file "de")
    (with-temp-buffer
      (insert-file-contents source-file)
      (let ((s (buffer-string)))
        ;; New value present.
        (should (string-match-p "^#\\+TIBETAN_TARGET_LANG: de$" s))
        ;; Old value gone — no stale `en' line.
        (should-not (string-match-p "^#\\+TIBETAN_TARGET_LANG: en$" s))
        ;; Exactly ONE target-lang line.
        (should (= 1
                   (cl-count-if
                    (lambda (ln)
                      (string-prefix-p "#+TIBETAN_TARGET_LANG:" ln))
                    (split-string s "\n"))))))))

(ert-deftest tibetan-analysis-set-source-target-lang-rejects-unknown ()
  "Only `de' / `en' are accepted values — anything else raises a
user-error rather than writing gibberish into the source file."
  (tibetan-test--with-source
      "#+TITLE: T\n"
    (should-error (tibetan-analysis-set-source-target-lang source-file "fr")
                  :type 'user-error)
    ;; File untouched.
    (with-temp-buffer
      (insert-file-contents source-file)
      (should-not (string-match-p "TIBETAN_TARGET_LANG" (buffer-string))))))

(ert-deftest tibetan-analysis-set-source-target-lang-nil-source-errors ()
  "Called with nil / non-existent source path → user-error."
  (should-error (tibetan-analysis-set-source-target-lang nil "de")
                :type 'user-error)
  (should-error (tibetan-analysis-set-source-target-lang
                 "/no/such/file.org" "de")
                :type 'user-error))

(ert-deftest tibetan-claude-prompt-missing-file-safe ()
  "Non-existent / nil source file returns an empty metadata plist."
  (let ((meta (tibetan-analysis--read-source-metadata nil)))
    (should (null (plist-get meta :claude-context)))
    (should (null (plist-get meta :title))))
  (let ((meta (tibetan-analysis--read-source-metadata
               "/nonexistent/path/source.org")))
    (should (null (plist-get meta :claude-context)))))

;; ============================================================================
;; ANALYSIS-FILE ↦ SOURCE-FILE RESOLUTION
;; ============================================================================

(ert-deftest tibetan-claude-prompt-extracts-source-from-analysis ()
  "`#+SOURCE:' org-link in an analysis file resolves to an absolute path."
  (let* ((dir (make-temp-file "tib-src-" t))
         (source (expand-file-name "Milarepa-prepared.org" dir))
         (subdir (expand-file-name "analysis" dir))
         (analysis (expand-file-name "seg-007.org" subdir)))
    (unwind-protect
        (progn
          (tibetan-test--write source "#+TITLE: Milarepa\n")
          (tibetan-test--write
           analysis
           "#+TITLE: Segment 7 Analysis\n#+SOURCE: [[file:../Milarepa-prepared.org::*Segment 7][Milarepa-prepared.org / Segment 7]]\n\n* Tibetan Text\nfoo\n")
          (let ((resolved (tibetan-analysis--source-file-from-analysis
                           analysis)))
            (should (stringp resolved))
            (should (file-equal-p resolved source))))
      (delete-directory dir t))))

;; ============================================================================
;; PROMPT ASSEMBLY
;; ============================================================================

(ert-deftest tibetan-claude-prompt-assembles-system-and-user ()
  "System prompt carries context headers; user prompt carries text + Wylie."
  (tibetan-test--with-source
      "#+TITLE: bKa' 'bum rgyas pa\n#+TIBETAN_CLAUDE_CONTEXT: Kadampa blo sbyong verse; author Sangs rgyas dbon ston.\n#+TIBETAN_CLAUDE_CONTEXT: Target language: English.\n\n* W\n:PROPERTIES:\n:WORK: bKa' 'bum rgyas pa\n:AUTHOR: Sangs rgyas dbon ston (1138–1210)\n:END:\n"
    (let* ((prompts (tibetan-analysis--build-claude-prompts
                     "མཉམ་མེད།" source-file))
           (sys (car prompts))
           (usr (cdr prompts)))
      (should (stringp sys))
      (should (stringp usr))
      ;; Work / author propagate into the system prompt
      (should (string-match-p "bKa' 'bum rgyas pa" sys))
      (should (string-match-p "Sangs rgyas dbon ston" sys))
      ;; Context headers propagate verbatim
      (should (string-match-p "Kadampa blo sbyong" sys))
      (should (string-match-p "Target language: English" sys))
      ;; User prompt carries the Tibetan
      (should (string-match-p "མཉམ་མེད" usr)))))

(ert-deftest tibetan-claude-prompt-works-without-source-file ()
  "Nil source-file yields a valid fallback prompt (no crash, sane default)."
  (let* ((prompts (tibetan-analysis--build-claude-prompts "མཉམ་མེད།" nil))
         (sys (car prompts))
         (usr (cdr prompts)))
    (should (stringp sys))
    (should (stringp usr))
    (should (string-match-p "Classical Tibetan" sys))
    (should (string-match-p "མཉམ་མེད" usr))))

(ert-deftest tibetan-claude-prompt-drops-hardcoded-rnam-thar-default ()
  "The system prompt no longer force-assumes rnam thar / chos 'byung.
Genre hints come from `#+TIBETAN_CLAUDE_CONTEXT:' instead."
  (let* ((prompts (tibetan-analysis--build-claude-prompts "ཀ།" nil))
         (sys (car prompts)))
    (should-not (string-match-p "biographical narratives (rnam thar)" sys))
    (should-not (string-match-p "historical chronicles (chos 'byung)" sys))))

;; ============================================================================
;; RESOURCES VOCABULARY MATCHING
;; ============================================================================

(ert-deftest tibetan-claude-prompt-glossary-matches-are-surfaced ()
  "Resources vocabulary entries whose term occurs in the segment are
attached to the user prompt as a 'Glossary for this passage' block."
  (let* ((dir (make-temp-file "tib-vocab-" t))
         (source (expand-file-name "source.org" dir))
         (res-dir (expand-file-name "Resources" dir))
         (vocab (expand-file-name "vocabulary.org" res-dir)))
    (unwind-protect
        (progn
          (tibetan-test--write
           vocab
           "#+TITLE: V\n\n* Vocabulary\n\n| Term | Gloss |\n|------+-------|\n| མཉམ་མེད | peerless // ohnegleichen |\n| སངས་རྒྱས་དབོན་སྟོན | Sangs rgyas dbon ston (1138–1210) |\n| རྒྱུ | cause — unrelated filler |\n")
          (tibetan-test--write
           source
           "#+TITLE: T\n#+TIBETAN_VOCAB_FILE: Resources/vocabulary.org\n")
          (let* ((prompts
                  (tibetan-analysis--build-claude-prompts
                   "མཉམ་མེད་འགྲོ་བའི་མགོན་པོ་སངས་རྒྱས་དབོན་སྟོན།"
                   source))
                 (usr (cdr prompts)))
            ;; Terms present in the segment surface
            (should (string-match-p "མཉམ་མེད" usr))
            (should (string-match-p "peerless" usr))
            (should (string-match-p "Sangs rgyas dbon ston" usr))
            ;; Terms NOT in the segment are filtered out
            (should-not (string-match-p "unrelated filler" usr))))
      (delete-directory dir t))))

;; ============================================================================
;; INTEGRATION WITH --request-claude-translation (gptel stubbed)
;; ============================================================================

(defvar tibetan-test--captured-prompt nil)
(defvar tibetan-test--captured-system nil)

(ert-deftest tibetan-claude-prompt-request-honours-source-file ()
  "`--request-claude-translation' passes the enriched prompt to gptel."
  (tibetan-test--with-source
      "#+TITLE: Milarepa-prepared\n#+TIBETAN_CLAUDE_CONTEXT: Classical rnam thar narrative; gTsang smyon He ru ka version of the Mila rnam thar. Target language: English.\n"
    (let* ((analysis-dir (make-temp-file "tib-analysis-" t))
           (analysis-file (expand-file-name "seg-001.org" analysis-dir)))
      (unwind-protect
          (progn
            (tibetan-test--write
             analysis-file
             "#+TITLE: Segment 1 Analysis\n\n* Tibetan Text\n\n** Provided Translations\n*** Claude\n[Requesting translation...]\n")
            (setq tibetan-test--captured-prompt nil
                  tibetan-test--captured-system nil)
            (cl-letf*
                (((symbol-function 'gptel-request)
                  (lambda (prompt &rest args)
                    (setq tibetan-test--captured-prompt prompt
                          tibetan-test--captured-system (plist-get args :system))
                    nil))
                 ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
                  (lambda () t))
                 ((symbol-function 'featurep)
                  (lambda (feat &rest _) (eq feat 'gptel)))
                 ((symbol-function 'fboundp)
                  (lambda (sym) (memq sym '(gptel-request
                                            tibetan-analysis--ensure-gptel-ready
                                            tibetan-to-wylie-fixed))))
                 ((symbol-function 'tibetan-to-wylie-fixed)
                  (lambda (_s) "mnyam med")))
              (tibetan-analysis--request-claude-translation
               "མཉམ་མེད།" analysis-file source-file))
            (should (stringp tibetan-test--captured-prompt))
            (should (stringp tibetan-test--captured-system))
            (should (string-match-p "Classical rnam thar narrative"
                                    tibetan-test--captured-system))
            (should (string-match-p "མཉམ་མེད"
                                    tibetan-test--captured-prompt)))
        (delete-directory analysis-dir t)))))

(ert-deftest tibetan-claude-prompt-request-backwards-compatible ()
  "`--request-claude-translation' still accepts 2 args (no source-file)."
  (let* ((analysis-dir (make-temp-file "tib-analysis-" t))
         (analysis-file (expand-file-name "seg-001.org" analysis-dir)))
    (unwind-protect
        (progn
          (tibetan-test--write analysis-file
                               "* Tibetan Text\n** Provided Translations\n*** Claude\n[Requesting translation...]\n")
          (setq tibetan-test--captured-prompt nil)
          (cl-letf*
              (((symbol-function 'gptel-request)
                (lambda (prompt &rest _)
                  (setq tibetan-test--captured-prompt prompt)
                  nil))
               ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
                (lambda () t))
               ((symbol-function 'featurep)
                (lambda (feat &rest _) (eq feat 'gptel)))
               ((symbol-function 'fboundp)
                (lambda (sym) (memq sym '(gptel-request
                                          tibetan-analysis--ensure-gptel-ready
                                          tibetan-to-wylie-fixed))))
               ((symbol-function 'tibetan-to-wylie-fixed)
                (lambda (_s) "mnyam med")))
            (tibetan-analysis--request-claude-translation
             "མཉམ་མེད།" analysis-file))
          (should (stringp tibetan-test--captured-prompt)))
      (delete-directory analysis-dir t))))

;; ============================================================================
;; PASS 7: Portfolio reference injection
;; ============================================================================

(ert-deftest tibetan-claude-prompt-injects-portfolio-reference-when-loaded ()
  "When a Portfolio is loaded, the built system prompt carries the
Portfolio reference block — so Claude tags `## Particles' sub-IDs
using the user's actual numbering (e.g. §1.6 Terminative) rather
than guessing from textbook-canonical numbering (§1.5)."
  (tibetan-test--with-source
      "#+TITLE: T\n"
    (cl-letf (((symbol-function 'tibetan-interlinear--get-portfolio)
               (lambda ()
                 '(("terminative" :section "1.6" :title "Terminative"
                    :intro "..." :functions
                    ((("1.6.1" . "Place / Location") . "Place desc.")))))))
      (let* ((prompts (tibetan-analysis--build-claude-prompts
                       "བདག་" source-file))
             (system (car prompts)))
        ;; The built system prompt includes the Portfolio reference.
        (should (string-match-p "§1\\.6 Terminative" system))
        (should (string-match-p "1\\.6\\.1 Place / Location" system))))))

(ert-deftest tibetan-claude-prompt-no-portfolio-no-injection ()
  "When NO Portfolio is loaded, no reference block is injected into
the system prompt.  The static prompt instruction may mention the
phrase `Portfolio section reference' (as a forward-reference to
the injected block), but the actual two-space-indented `§N.N'
bullet list that the helper emits must be absent.  Callers that
don't set `tibetan-interlinear-portfolio-file' still get a
well-formed prompt."
  (tibetan-test--with-source
      "#+TITLE: T\n"
    (cl-letf (((symbol-function 'tibetan-interlinear--get-portfolio)
               (lambda () nil)))
      (let* ((prompts (tibetan-analysis--build-claude-prompts
                       "བདག་" source-file))
             (system (car prompts)))
        ;; The INJECTED block — a two-space-indented `§N.N Title' line —
        ;; must NOT appear.  The static prompt instruction mentions the
        ;; name of the block as a forward-reference; that's allowed.
        (should-not (string-match-p "^  §[0-9]" system))))))

;; ============================================================================
;; U1+U2 — tighter translation + translation-justifying grammar (2026-04-24)
;;
;; System-prompt invariants that previous versions violated:
;;   U1: Translation should stay close to Tibetan grammar (conditional
;;       converb → if/when, ablative cause → arises from, nominalised
;;       verb + copula structure preserved).  The old prompt said
;;       "render particles idiomatically, not literally" — exactly the
;;       opposite of what Carsten wants.
;;   U2: Grammar should justify specific translation choices where the
;;       Translation's wording depended on disambiguating a polysemous
;;       word, a converb function, or a case-particle reading.
;;
;; These tests assert the directive keywords are in the system prompt
;; so a future refactor doesn't silently revert them.
;; ============================================================================

(ert-deftest tibetan-analysis-claude-prompt-translation-tight-to-grammar ()
  "U1: the Translation section directive must steer Claude toward
faithfulness, not idiomatic paraphrase.  The old prompt said
`render particles and syntactic structures idiomatically'; the new
version says `stays CLOSE TO THE GRAMMAR'."
  (let ((p tibetan-analysis--claude-system-prompt))
    (should (string-match-p "CLOSE TO THE GRAMMAR" p))
    (should (string-match-p "conditional converb" p))
    (should (string-match-p "ablative" p))
    (should (string-match-p "case-marking pattern" p))
    ;; The old anti-directive must be gone.
    (should-not (string-match-p
                 "idiomatically, not literally" p))))

(ert-deftest tibetan-analysis-claude-prompt-grammar-justifies-translation ()
  "U2: the Grammar section directive must ask Claude to justify
specific translation choices, not just summarise the backbone.
Wording adjusted 2026-04-26 with the bullet-restructuring of
the Grammar section (commit pending) — keep the regression
guard but match the new keywords."
  (let ((p tibetan-analysis--claude-system-prompt))
    (should (string-match-p "Translation justifications" p))
    (should (string-match-p "non-obvious choice" p))
    (should (string-match-p "justify" p))))

(ert-deftest tibetan-analysis-claude-prompt-fixed-buddhist-terms-inline ()
  "U3 (inline): the Translation directive asks for a short
parenthetical explanation on first mention of fixed Buddhist terms
(Four Immeasurables, Bodhicitta, Three Jewels, etc.)."
  (let ((p tibetan-analysis--claude-system-prompt))
    (should (string-match-p "Four Immeasurables" p))
    (should (string-match-p "parenthetical explanation" p))))

(provide 'tibetan-analysis-claude-prompt-test)
;;; tibetan-analysis-claude-prompt-test.el ends here
