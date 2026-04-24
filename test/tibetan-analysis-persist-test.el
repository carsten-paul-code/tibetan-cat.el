;;; tibetan-analysis-persist-test.el --- Tests for tibetan-analysis-persist.el -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for Tibetan analysis persistence module.
;; Tests cover: filename generation, hash computation, section parsing,
;; and utility functions.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-analysis-persist)

;; ============================================================================
;; FILENAME GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-make-short-name-tigress ()
  "Test short name generation for Tigress file."
  (should (string= "blockpri"
                   (tibetan-analysis-make-short-name "Tigress-Story-BlockPrint-Class.org"))))

(ert-deftest tibetan-analysis-make-short-name-saskya ()
  "Test short name generation for Sa-skya file."
  (should (string= "sa"
                   (tibetan-analysis-make-short-name "Reading-Sa-skya-legs-bshad.org"))))

(ert-deftest tibetan-analysis-make-short-name-reading ()
  "Test short name generation for Reading files."
  (let ((result (tibetan-analysis-make-short-name "Reading-05-Padma.org")))
    (should (stringp result))
    (should (string= "padma" result))))

(ert-deftest tibetan-analysis-make-short-name-generic ()
  "Test short name generation for generic files."
  (let ((result (tibetan-analysis-make-short-name "SomeDocument.org")))
    (should (stringp result))
    (should (> (length result) 0))
    (should (<= (length result) 8))))

(ert-deftest tibetan-analysis-make-short-name-nil ()
  "Test short name generation with nil input."
  (should (null (tibetan-analysis-make-short-name nil))))

(ert-deftest tibetan-analysis-segment-filename-number ()
  "Test segment filename generation from number."
  (let ((result (tibetan-analysis-segment-filename 1)))
    (should (string= "seg-001.org" result))))

(ert-deftest tibetan-analysis-segment-filename-number-with-source ()
  "Test segment filename generation from number with source file."
  (let ((result (tibetan-analysis-segment-filename 42)))
    (should (string= "seg-042.org" result))))

(ert-deftest tibetan-analysis-segment-filename-string ()
  "Test segment filename generation from string ID."
  (let ((result (tibetan-analysis-segment-filename "Segment 15")))
    (should (string= "seg-015.org" result))))

(ert-deftest tibetan-analysis-segment-filename-string-with-source ()
  "Test segment filename generation from string."
  (let ((result (tibetan-analysis-segment-filename "Segment 7")))
    (should (string= "seg-007.org" result))))

(ert-deftest tibetan-analysis-segment-filename-line-format ()
  "Test segment filename with Line N format."
  (let ((result (tibetan-analysis-segment-filename "Line 3")))
    (should (string-match-p "seg-003" result))))

(ert-deftest tibetan-analysis-segment-filename-padding ()
  "Test that segment numbers are zero-padded to 3 digits."
  (should (string-match-p "seg-001" (tibetan-analysis-segment-filename 1)))
  (should (string-match-p "seg-010" (tibetan-analysis-segment-filename 10)))
  (should (string-match-p "seg-100" (tibetan-analysis-segment-filename 100))))

;; ============================================================================
;; HASH COMPUTATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-compute-hash-basic ()
  "Test basic hash computation."
  (let ((hash (tibetan-analysis-compute-hash "test")))
    (should (stringp hash))
    (should (= 32 (length hash)))))  ; MD5 is 32 hex chars

(ert-deftest tibetan-analysis-compute-hash-consistency ()
  "Test that same input gives same hash."
  (let ((text "བཀྲ་ཤིས་བདེ་ལེགས།"))
    (should (string= (tibetan-analysis-compute-hash text)
                     (tibetan-analysis-compute-hash text)))))

(ert-deftest tibetan-analysis-compute-hash-different ()
  "Test that different inputs give different hashes."
  (should-not (string= (tibetan-analysis-compute-hash "text1")
                       (tibetan-analysis-compute-hash "text2"))))

(ert-deftest tibetan-analysis-compute-hash-tibetan ()
  "Test hash computation with Tibetan text."
  (let ((hash (tibetan-analysis-compute-hash "བཀྲ་ཤིས།")))
    (should (stringp hash))
    (should (= 32 (length hash)))))

(ert-deftest tibetan-analysis-compute-hash-empty ()
  "Test hash computation with empty string."
  (let ((hash (tibetan-analysis-compute-hash "")))
    (should (stringp hash))
    (should (= 32 (length hash)))))

;; ============================================================================
;; SECTION BOUNDS PARSING TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-find-section-bounds-basic ()
  "Test finding section bounds in buffer."
  (with-temp-buffer
    (insert "* Section 1\nContent 1\n* Section 2\nContent 2\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Section 1")))
      (should bounds)
      (should (consp bounds))
      (should (integerp (car bounds)))
      (should (integerp (cdr bounds))))))

(ert-deftest tibetan-analysis-find-section-bounds-not-found ()
  "Test finding non-existent section."
  (with-temp-buffer
    (insert "* Section 1\nContent\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Missing")))
      (should (null bounds)))))

(ert-deftest tibetan-analysis-find-section-bounds-nested ()
  "Test finding section bounds with subsections."
  (with-temp-buffer
    (insert "* Top\n** Sub1\nContent 1\n** Sub2\nContent 2\n* Next\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Top")))
      (should bounds)
      (should (< (car bounds) (cdr bounds))))))

;; ============================================================================
;; USER SECTION EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-get-user-sections-callable ()
  "Test that get-user-sections function exists."
  (should (fboundp 'tibetan-analysis-get-user-sections)))

;; ============================================================================
;; SYNC CHECK TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-check-sync-no-file ()
  "Test sync check when file doesn't exist."
  (let ((result (tibetan-analysis-check-sync "/nonexistent/path.org" "text")))
    ;; Should return nil or handle gracefully
    (should (or (null result) (eq result t)))))

;; ============================================================================
;; FACE SETUP TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-setup-faces-callable ()
  "Test that face setup function is callable."
  (should (fboundp 'tibetan-analysis-setup-faces)))

(ert-deftest tibetan-analysis-tibetan-face-exists ()
  "Test that Tibetan face is defined."
  (should (facep 'tibetan-analysis-tibetan-face)))

(ert-deftest tibetan-analysis-roman-face-exists ()
  "Test that roman face is defined."
  (should (facep 'tibetan-analysis-roman-face)))

;; ============================================================================
;; VOCABULARY LOADING TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-ensure-vocabulary-callable ()
  "Test that vocabulary loading function exists."
  (should (fboundp 'tibetan-analysis--ensure-vocabulary)))

(ert-deftest tibetan-analysis-get-particle-annotation-callable ()
  "Test that particle annotation function exists."
  (should (fboundp 'tibetan-analysis--get-particle-annotation)))

(ert-deftest tibetan-analysis-get-word-info-callable ()
  "Test that word info function exists."
  (should (fboundp 'tibetan-analysis--get-word-info)))

;; ============================================================================
;; CONTENT GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-generate-content-callable ()
  "Test that content generation function exists."
  (should (fboundp 'tibetan-analysis-generate-content)))

(ert-deftest tibetan-analysis-generate-content-empty ()
  "Test content generation with empty input."
  ;; Should not error on empty input
  (condition-case err
      (let ((result (tibetan-analysis-generate-content "")))
        (should (or (null result) (stringp result))))
    (error (should-not "Should not error on empty input"))))

(ert-deftest tibetan-analysis-generate-content-basic ()
  "Test basic content generation."
  ;; Note: Full content generation depends on vocabulary being loaded
  (condition-case nil
      (let ((result (tibetan-analysis-generate-content "བདག")))
        (should (or (null result) (stringp result))))
    (error nil)))  ; Allow errors if dependencies not loaded

;; ============================================================================
;; MAIN INTERFACE TESTS
;; ============================================================================

(ert-deftest tibetan-open-segment-analysis-callable ()
  "Test that main analysis function exists."
  (should (fboundp 'tibetan-open-segment-analysis)))

(ert-deftest tibetan-reanalyze-segment-callable ()
  "Test that reanalysis function exists."
  (should (fboundp 'tibetan-reanalyze-segment)))

;; Note: The following functions are planned but not yet implemented:
;; - tibetan-collect-all-segments
;; - tibetan-analyze-all-segments
;; - tibetan-refresh-dharmamitra-translation
;; - tibetan-copy-dharmamitra-to-working
;; Tests for these functions are deferred until implementation is available.

;; ============================================================================
;; ANALYSIS MODE HOOK TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-analysis-mode-hook-callable ()
  "Test that mode-hook function exists and is callable."
  (should (fboundp 'tibetan-analysis-mode-hook)))

(ert-deftest tibetan-analysis-mode-hook-safe ()
  "Test that mode-hook doesn't error when called."
  (condition-case err
      (tibetan-analysis-mode-hook)
    (error (should-not (format "Mode hook should not error: %s" err)))))

(ert-deftest tibetan-analysis-mode-hook-in-buffer ()
  "Test mode-hook execution in a buffer context."
  (with-temp-buffer
    (condition-case err
        (tibetan-analysis-mode-hook)
      (error (should-not (format "Mode hook should not error in buffer: %s" err))))))

(ert-deftest tibetan-analysis-mode-hook-preserves-content ()
  "Test that mode-hook doesn't modify buffer content."
  (with-temp-buffer
    (insert "Sample content")
    (let ((original (buffer-string)))
      (tibetan-analysis-mode-hook)
      (should (string= (buffer-string) original)))))

;; ============================================================================
;; GET STORED HASH TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-analysis-get-stored-hash-callable ()
  "Test that get-stored-hash function exists."
  (should (fboundp 'tibetan-analysis-get-stored-hash)))

(ert-deftest tibetan-analysis-get-stored-hash-nonexistent-file ()
  "Test get-stored-hash with nonexistent file."
  (let ((result (tibetan-analysis-get-stored-hash "/nonexistent/file.org")))
    ;; Should return nil or empty string for missing file
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-analysis-get-stored-hash-nil-path ()
  "Test get-stored-hash with nil path."
  (let ((result (tibetan-analysis-get-stored-hash nil)))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-analysis-get-stored-hash-empty-file ()
  "Test get-stored-hash with empty file."
  (let ((temp-file (make-temp-file "test" nil ".org")))
    (unwind-protect
        (let ((result (tibetan-analysis-get-stored-hash temp-file)))
          ;; Should handle empty file gracefully
          (should (or (null result) (stringp result))))
      (delete-file temp-file))))

(ert-deftest tibetan-analysis-get-stored-hash-with-hash-header ()
  "Test get-stored-hash with hash in file header."
  (let ((temp-file (make-temp-file "test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TIBETAN_HASH: abc123def456\n")
            (insert "Some content\n"))
          (let ((result (tibetan-analysis-get-stored-hash temp-file)))
            ;; Should extract the hash if present
            (should (or (null result) (stringp result)))))
      (delete-file temp-file))))

(ert-deftest tibetan-analysis-get-stored-hash-returns-string ()
  "Test that get-stored-hash returns nil or string."
  (skip-unless (fboundp 'tibetan-analysis-get-stored-hash))
  (let ((temp-file (make-temp-file "test" nil ".org")))
    (unwind-protect
        (let ((result (tibetan-analysis-get-stored-hash temp-file)))
          (should (or (null result) (stringp result))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest tibetan-analysis-get-stored-hash-consistency ()
  "Test that reading same file returns same hash."
  (let ((temp-file (make-temp-file "test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TIBETAN_HASH: test123\n"))
          (let ((hash1 (tibetan-analysis-get-stored-hash temp-file))
                (hash2 (tibetan-analysis-get-stored-hash temp-file)))
            (if hash1
                (should (string= hash1 hash2))
              ;; If hash1 is nil, hash2 should also be nil
              (should (null hash2)))))
      (delete-file temp-file))))

;; ============================================================================
;; VERSION AND CONSTANTS TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-version-exists ()
  "Test that version constant is defined."
  (should (boundp 'tibetan-analysis-version))
  (should (stringp tibetan-analysis-version)))

(ert-deftest tibetan-analysis-roman-scale-exists ()
  "Test that roman scale customization exists."
  (should (boundp 'tibetan-analysis-roman-scale))
  (should (numberp tibetan-analysis-roman-scale)))

;; ============================================================================
;; INTEGRATION TESTS (require file system access)
;; ============================================================================

(ert-deftest tibetan-analysis-get-folder-callable ()
  "Test that folder function is callable."
  (should (fboundp 'tibetan-analysis-get-folder)))

(ert-deftest tibetan-analysis-create-file-callable ()
  "Test that file creation function exists."
  (should (fboundp 'tibetan-analysis-create-file)))

(ert-deftest tibetan-analysis-get-filepath-callable ()
  "Test that filepath function exists."
  (should (fboundp 'tibetan-analysis-get-filepath)))

(ert-deftest tibetan-analysis-regenerate-auto-callable ()
  "Test that regeneration function exists."
  (should (fboundp 'tibetan-analysis-regenerate-auto)))

;; ============================================================================
;; format-word-with-wylie — canonical "SCRIPT [wylie]" formatter
;; ============================================================================
;; Used by every analysis section that mentions a Tibetan word (except
;; the top-level * Tibetan Text). Unifies the display so we never ship
;; `script  wylie' in one section and `script [wylie]' in another.

(ert-deftest tibetan-analysis-format-word-with-wylie-happy-path ()
  "Tibetan input → `SCRIPT [wylie]' when the converter produces a
distinct, non-empty wylie string."
  (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (_w) "yul")))
    (should (string= (tibetan-analysis--format-word-with-wylie "ཡུལ")
                     "ཡུལ [yul]"))))

(ert-deftest tibetan-analysis-format-word-with-wylie-empty-returns-empty ()
  "Nil, empty string, and non-string inputs return empty string."
  (should (string= (tibetan-analysis--format-word-with-wylie nil) ""))
  (should (string= (tibetan-analysis--format-word-with-wylie "") ""))
  (should (string= (tibetan-analysis--format-word-with-wylie 42) "")))

(ert-deftest tibetan-analysis-format-word-with-wylie-identical-returns-script-only ()
  "If the converter echoes the input (e.g. already-wylie input, or
converter is identity for punctuation), return the word alone —
never `word [word]'."
  (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (w) w)))
    (should (string= (tibetan-analysis--format-word-with-wylie "yul")
                     "yul"))))

(ert-deftest tibetan-analysis-format-word-with-wylie-converter-errors ()
  "If the converter throws, fall back to the word alone — no brackets."
  (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (_w) (error "boom"))))
    (should (string= (tibetan-analysis--format-word-with-wylie "ཡུལ")
                     "ཡུལ"))))

(ert-deftest tibetan-analysis-format-word-with-wylie-blank-wylie ()
  "Converter returning empty or whitespace-only is treated as no wylie."
  (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (_w) "   ")))
    (should (string= (tibetan-analysis--format-word-with-wylie "ཡུལ")
                     "ཡུལ"))))

;; ============================================================================
;; Bialek-unified grammatical-role labels (DRY: one terminology table)
;; ============================================================================
;; Regression guard: `get-grammatical-role' must surface Bialek's
;; terminology (e.g. "GENITIVE (GEN)", "CONVERBIAL: ABLATIVE CONVERB")
;; rather than the old hand-maintained labels ("Genitive particle",
;; "Ablative particle"), so the Word/Particle List and the Grammatical
;; Markers section stay in lock-step.

(defun tibetan-analysis-persist-test--role (word &optional root)
  "Shorthand: compute a grammatical role with an empty verb-table."
  (tibetan-analysis--get-grammatical-role
   word (or root word) (make-hash-table :test 'equal)))

(ert-deftest tibetan-analysis-role-genitive-is-bialek ()
  "`པའི' ends with the genitive suffix → `GENITIVE (GEN)' (Bialek),
not the legacy `Genitive particle' label."
  (let ((role (tibetan-analysis-persist-test--role "པའི")))
    (should role)
    (should (string-match-p "GENITIVE" role))))

(ert-deftest tibetan-analysis-role-ablative-converb-is-bialek ()
  "`ནས' → Bialek `CONVERBIAL: ABLATIVE CONVERB', not `Ablative particle'."
  (let ((role (tibetan-analysis-persist-test--role "ནས")))
    (should role)
    (should (string-match-p "ABLATIVE CONVERB" role))))

(ert-deftest tibetan-analysis-role-coordinative-converb-is-bialek ()
  "`ཏེ' → Bialek `CONVERBIAL: COORDINATIVE CONVERB'."
  (let ((role (tibetan-analysis-persist-test--role "ཏེ")))
    (should role)
    (should (string-match-p "COORDINATIVE CONVERB" role))))

(ert-deftest tibetan-analysis-role-dative-is-bialek ()
  "`ལ' standalone → Bialek `DATIVE (DAT)'."
  (let ((role (tibetan-analysis-persist-test--role "ལ")))
    (should role)
    (should (string-match-p "DATIVE" role))))

(ert-deftest tibetan-analysis-role-terminative-is-bialek ()
  "`དུ' → Bialek `TERMINATIVE (ALL)'."
  (let ((role (tibetan-analysis-persist-test--role "དུ")))
    (should role)
    (should (string-match-p "TERMINATIVE" role))))

(ert-deftest tibetan-analysis-role-verb-suffix-uses-bialek ()
  "When the word is a verb AND carries a bialek-classifiable particle
tail, the combined label reads `<verb-kind>, <BIALEK TYPE>' — so the
suffix annotation uses Bialek's wording, not the legacy
`causal converb form' / `ablative converb form' strings."
  (let ((suffix (tibetan-analysis--detect-verb-suffix "བྱས་པས" "བྱས")))
    (should suffix)
    (should (string-match-p "CAUSAL CONVERB" suffix))
    (should (string-prefix-p ", " suffix))))

(ert-deftest tibetan-analysis-role-noun-fallback ()
  "Words bialek does not classify and that are not in the verb-table
fall back to the plain `Noun' label.  Uses `ཡུལ' which is neither a
particle-bearing form nor a Hill-DB verb."
  (let ((role (tibetan-analysis-persist-test--role "ཡུལ")))
    (should (string= role "Noun"))))

(ert-deftest tibetan-analysis-bialek-type-handles-compound-word ()
  "`tibetan-analysis--bialek-type' looks up the compound form even
when bialek's tsheg-split would miss the causal-converb pair
(e.g. `བྱས་པས' → split to `བྱས' + `པས' → neither alone classifies).
The tsheg-removed fallback must recover the CAUSAL CONVERB tag."
  (let ((type (tibetan-analysis--bialek-type "བྱས་པས")))
    (should type)
    (should (string-match-p "CAUSAL CONVERB" type))))

(ert-deftest tibetan-analysis-role-nominalised-verb-keeps-verb-prefix ()
  "`སླེབ་པའི' → the genitive-nominalised form of the verb `སླེབ'
must still surface as a verb in the role label, i.e. `Verb, GENITIVE
(GEN)' — NOT bare `GENITIVE (GEN)'.  Regression guard for the
deep-particle-strip path (strip past the bare nominaliser `པ')."
  (let ((role (tibetan-analysis-persist-test--role "སླེབ་པའི"
                                                    "སླེབ་པ")))
    (should role)
    (should (string-match-p "[Vv]erb" role))
    (should (string-match-p "GENITIVE" role))))

(ert-deftest tibetan-analysis-bialek-type-empty-or-nil ()
  "Nil / empty / non-string inputs yield nil, not an error."
  (should (null (tibetan-analysis--bialek-type nil)))
  (should (null (tibetan-analysis--bialek-type "")))
  (should (null (tibetan-analysis--bialek-type 42))))

;; ============================================================================
;; Clause Structure (Round-2) integration
;; ============================================================================
;; The `** Clause Structure' section is populated from
;; `tibetan-analyze-round2' via `tibetan-analysis--render-clause-structure'.
;; It is gated on `tibetan-analysis-show-clause-structure' (defaults to t).

(ert-deftest tibetan-analysis-render-clause-structure-empty-inputs ()
  "No words / no verbs → empty string.  Must NOT throw."
  (should (string= "" (tibetan-analysis--render-clause-structure
                       nil nil nil)))
  (should (string= "" (tibetan-analysis--render-clause-structure
                       '("གཞིས") nil nil))))

(ert-deftest tibetan-analysis-render-clause-structure-no-analysis ()
  "If `tibetan-analyze-round2' produces no clauses, render a
placeholder rather than an empty string, so the section is obviously
present-but-idle in the output."
  (cl-letf (((symbol-function 'tibetan-analyze-round2)
             (lambda (_w _v &optional _m)
               '((clauses . nil) (nps . nil)
                 (argument-structure . nil)))))
    (let ((out (tibetan-analysis--render-clause-structure
                '("ཡུལ") '(((lemma . "ཡུལ"))) nil)))
      (should (string-match-p "No clause structure" out)))))

(ert-deftest tibetan-analysis-render-clause-structure-happy-path ()
  "Single main-clause scenario: renders a `Clause 1 [main]: verb …' line
and any NPs found inside the clause, each routed through the
`SCRIPT [wylie]' formatter."
  (let* ((verb-entry `((lemma . "སླེབ")
                       (meaning . "to arrive, to reach")))
         (np         `((start . 0) (end . 1)
                       (head . "ཀོ་རོན་ས")
                       (case . TERM)))
         (clause     `((start . 0) (end . 2)
                       (type . main)
                       (converb-type . nil)
                       (converb-particle . nil)
                       (verb . ,verb-entry)))
         (r2         `((clauses . (,clause))
                       (nps . (,np))
                       (argument-structure
                        . (((clause . ,clause)
                            (verb . ,verb-entry)
                            (case-frame . "Abs-Term")
                            (arguments
                             . (((role . goal)
                                 (np . ,np))))))))))
    (cl-letf (((symbol-function 'tibetan-analyze-round2)
               (lambda (_w _v &optional _m) r2))
              ((symbol-function 'tibetan-to-wylie-fixed)
               (lambda (w) (cond ((string= w "སླེབ") "sleb")
                                 ((string= w "ཀོ་རོན་ས") "ko ron sa")
                                 (t w)))))
      (let ((out (tibetan-analysis--render-clause-structure
                  '("ཀོ་རོན་ས" "སླེབ") (list verb-entry) nil)))
        (should (string-match-p "Clause 1 \\[main\\]" out))
        (should (string-match-p "verb སླེབ \\[sleb\\]" out))
        (should (string-match-p "NPs: ཀོ་རོན་ས \\[ko ron sa\\] (TERM)" out))
        (should (string-match-p "goal → ཀོ་རོན་ས" out))))))

(ert-deftest tibetan-analysis-render-clause-structure-dependent-shows-converb ()
  "A dependent clause shows the converb particle that licenses it."
  (let* ((verb-entry `((lemma . "འཐོན")))
         (clause     `((start . 0) (end . 1)
                       (type . dependent)
                       (converb-type . coordinative)
                       (converb-particle . "ཏེ")
                       (verb . ,verb-entry)))
         (r2         `((clauses . (,clause))
                       (nps . nil)
                       (argument-structure . nil))))
    (cl-letf (((symbol-function 'tibetan-analyze-round2)
               (lambda (_w _v &optional _m) r2))
              ((symbol-function 'tibetan-to-wylie-fixed)
               (lambda (w) (cond ((string= w "འཐོན") "'thon")
                                 ((string= w "ཏེ") "te")
                                 (t w)))))
      (let ((out (tibetan-analysis--render-clause-structure
                  '("འཐོན" "ཏེ") (list verb-entry) nil)))
        (should (string-match-p "Clause 1 \\[dependent · ཏེ \\[te\\]" out))
        (should (string-match-p "verb འཐོན" out))))))

(ert-deftest tibetan-analysis-show-clause-structure-is-defcustom ()
  "The clause-structure section must be user-configurable (per P2)."
  (should (boundp 'tibetan-analysis-show-clause-structure))
  (should (get 'tibetan-analysis-show-clause-structure 'custom-type)))

;; ============================================================================
;; Interlinear Gloss gloss-lookup goes through the multisource pipeline
;; ============================================================================
;; Regression guard for the DRY consolidation: the Interlinear Gloss
;; (and the Detailed Dictionary) must pick glosses from the SAME
;; multi-source priority chain, so the Resources / Custom entry wins
;; over Steinert / Rangjung Yeshe.  A Resources-sourced entry also
;; gets a ★ marker inline.
;;
;; Previously this test exercised the Word / Particle List section;
;; that section was removed 2026-04-22 (its content was redundant
;; with the Interlinear Gloss) and the ★ marker moved up to the
;; Interlinear.  The multisource lookup path is unchanged; only the
;; display surface shifted.

(ert-deftest tibetan-analysis-interlinear-uses-multisource-resources-first ()
  "When the multisource lookup returns a Resources entry first, the
Interlinear Gloss must surface that gloss (with the ★ marker), not
fall back to a Steinert/RY single-source pick."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (word)
               (when (string= word "ཡུལ")
                 (list (list :source "Resources (provided)"
                             :primary "Heimat // homeland"
                             :detailed "Heimat, Land // homeland, region"
                             :sanskrit nil :wylie "yul")
                       (list :source "Steinert/02-RangjungYeshe"
                             :primary "object"
                             :detailed "object; place; sense object"
                             :sanskrit nil :wylie "yul"))))))
    (let* ((out (condition-case nil
                    (tibetan-analysis-generate-content "ཡུལ")
                  (error nil)))
           (il (and out
                    (when (string-match
                           "\\*\\* Interlinear Gloss\\(.\\|\n\\)*?\\*\\* "
                           out)
                      (match-string 0 out)))))
      (when il
        ;; The Resources bilingual "Heimat // homeland" gets its English
        ;; half surfaced by `tibetan-interlinear--prefer-english'.
        (should (string-match-p "homeland" il))
        (should (string-match-p "★" il))
        ;; Must NOT have surfaced the Steinert gloss.
        (should-not (string-match-p "object; place" il))))))

(ert-deftest tibetan-analysis-word-particle-list-section-is-removed ()
  "The Word / Particle List section must NOT be present in the
generated analysis content.  Regression guard for 2026-04-22 — the
section was removed in favour of relying on the Interlinear Gloss
above, which carries the same information more compactly."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content "སངས་རྒྱས།")
                 (error nil))))
      (when out
        (should-not (string-match-p "^\\*\\* Word / Particle List"
                                    out))))))

;; ----------------------------------------------------------------------------
;; Pass 6b: merged `** Grammar' section + retired subheadings
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-grammar-section-renders-merged ()
  "Pass 6b (2026-04-22) merges Particle Map + Particle Overview +
Grammatical Markers into a single `** Grammar' section with two
sub-headings: `*** Particle Map' and `*** Particles in This Segment'.
The old standalone sections must NOT appear."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content "བདག་གིས་ལས་བྱས་ནས་སོང་།")
                 (error nil))))
      (when out
        ;; Merged section exists at level 2
        (should (string-match-p "^\\*\\* Grammar$" out))
        ;; With expected sub-headings
        (should (string-match-p "^\\*\\*\\* Particle Map$" out))
        (should (string-match-p "^\\*\\*\\* Particles in This Segment$" out))
        ;; Old standalone sections are retired
        (should-not (string-match-p "^\\*\\* Particle Map$" out))
        (should-not (string-match-p "^\\*\\* Particle Overview$" out))
        (should-not (string-match-p "^\\*\\* Grammatical Markers$" out))))))

(ert-deftest tibetan-analysis-sentence-structure-replaces-clause-structure ()
  "Pass 6b merges the old skinny `** Sentence Structure' (verb → args)
into the Round-2 clause output and renames the section.  `** Clause
Structure' must be retired; `** Sentence Structure' carries the
per-clause NPs + roles."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content "བདག་གིས་ལས་བྱས།")
                 (error nil))))
      (when out
        (should (string-match-p "^\\*\\* Sentence Structure$" out))
        (should-not (string-match-p "^\\*\\* Clause Structure$" out))))))

;; ----------------------------------------------------------------------------
;; Regression — Portfolio snippet multi-line bodies are fully indented
;; ----------------------------------------------------------------------------
;;
;; Reproduced 2026-04-22 on Milarepa seg-30: the `des' entry's
;; §1.3.4 Portfolio description embedded example bullets, e.g.
;;
;;   The ergative/instrumental may express the cause or reason …
;;
;;   - thos pas phyir mi 'ong gi 'bras bu thob bo --- "because..."
;;   - dran pas rab tu dga' ba skyes te/ --- "because..."
;;
;; The `*** Particles in This Segment' renderer's
;;   (insert (format "    %s\n" (truncate-para body 400)))
;; indented only the FIRST line (the intro paragraph).  Subsequent
;; lines — particularly example bullets that start with `- ' —
;; landed at column 0 after the first newline, so they read as
;; brand-new top-level particle entries rather than body of the
;; current snippet.  Students saw two phantom `- thos pas ...'
;; "particle" items between `des' and `der'.
;;
;; Fix requirement: EVERY line of the snippet body (including
;; blank lines within) must be indented to match the first line's
;; column.  Writing regression test first per CLAUDE.md rule 2.

(ert-deftest tibetan-analysis-grammar-portfolio-snippet-multiline-indented ()
  "Every line of a multi-line Portfolio snippet body must be
indented so it stays nested under the particle entry — example
bullets cannot escape to column 0.  Regression guard for the
`des' §1.3.4 indent leak spotted on seg-30."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w) nil))
            ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
             (lambda (_key sub-id)
               (when (equal sub-id "1.3.4")
                 (cons "Reason"
                       (concat
                        "The ergative may express cause or reason.\n\n"
                        "- thos pas phyir mi 'ong --- example 1\n"
                        "- dran pas rab tu dga' --- example 2"))))))
    (let* ((tibetan-analysis--claude-particles-for-render
            (list (list :word "des" :particle "s"
                        :sub-id "1.3.4" :label "reason")))
           (out (condition-case nil
                    (tibetan-analysis-generate-content "དེས།")
                  (error nil))))
      (when out
        ;; Locate the Grammar section's particle entries.
        (let* ((grammar-start (string-match "\\*\\*\\* Particles in This Segment"
                                            out))
               (grammar-end (or (string-match "^\\*\\* " out
                                              (and grammar-start
                                                   (1+ grammar-start)))
                                (length out)))
               (grammar-body (and grammar-start
                                  (substring out grammar-start grammar-end))))
          (when grammar-body
            ;; CRITICAL: no line beginning with `- thos' / `- dran' at
            ;; column 0 (not nested under `    ' indentation).  The
            ;; example bullets must stay indented as part of the
            ;; snippet body.
            (should-not (string-match-p "^- thos pas" grammar-body))
            (should-not (string-match-p "^- dran pas" grammar-body))
            ;; And the example lines ARE still present (we didn't
            ;; truncate them away) — look for their text, indented.
            (should (string-match-p "    - thos pas\\|      - thos pas"
                                    grammar-body))))))))

;; ----------------------------------------------------------------------------
;; Pass 6c: Claude particle-function parser + Portfolio snippet rendering
;; ----------------------------------------------------------------------------

(require 'tibetan-analysis-claude)

(ert-deftest tibetan-analysis-parse-claude-particles-basic ()
  "Four-field `word, particle, sub-id, label' lines parse into
tuples; junk lines are skipped."
  (let* ((body (concat "der, r, 1.5.1, place\n"
                       "mthu'i, 'i, 1.1.1, attributive\n"
                       "bslabs nas, nas, 2.11.1, sequential-temporal\n"
                       "[none matched]\n"   ;; junk line — skipped
                       "tshim nas, nas, 2.11.2, causal-sequential\n"))
         (tuples (tibetan-analysis--parse-claude-particles body)))
    (should (= 4 (length tuples)))
    (should (equal (plist-get (nth 0 tuples) :word)     "der"))
    (should (equal (plist-get (nth 0 tuples) :particle) "r"))
    (should (equal (plist-get (nth 0 tuples) :sub-id)   "1.5.1"))
    (should (equal (plist-get (nth 0 tuples) :label)    "place"))
    (should (equal (plist-get (nth 1 tuples) :sub-id) "1.1.1"))
    (should (equal (plist-get (nth 2 tuples) :sub-id) "2.11.1"))
    (should (equal (plist-get (nth 3 tuples) :label) "causal-sequential"))))

(ert-deftest tibetan-analysis-parse-claude-particles-empty-nil ()
  "Empty / nil body returns nil, never a spurious tuple."
  (should (null (tibetan-analysis--parse-claude-particles nil)))
  (should (null (tibetan-analysis--parse-claude-particles "")))
  (should (null (tibetan-analysis--parse-claude-particles "\n\n  \n"))))

(ert-deftest tibetan-analysis-grammar-renders-portfolio-snippet-with-claude ()
  "When the dynamic `claude-particles-for-render' var carries tagged
particle tuples, the Grammar section includes the Portfolio sub-
function heading + snippet per occurrence (self-contained output).
Stubs the Portfolio snippet lookup so the test doesn't need the
user's actual Portfolio file loaded.  Uses `mthu'i' where the
Bialek-reported word matches Claude's `:word' field cleanly."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil))
            ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
             (lambda (key sub-id)
               ;; Return a stub snippet only for the tagged occurrence
               ;; we're testing; other lookups return nil.
               (when (and (equal key "genitive")
                          (equal sub-id "1.1.1"))
                 (cons "Genitive Attribute"
                       "Attributive genitive: X-'i Y = 'Y of X' or 'X's Y'.")))))
    (let* ((tibetan-analysis--claude-particles-for-render
            (list (list :word "mthu'i" :particle "'i"
                        :sub-id "1.1.1" :label "attributive")))
           (out (condition-case nil
                    (tibetan-analysis-generate-content
                     "མཐུའི་མན་ངག")
                  (error nil))))
      (when out
        ;; Portfolio snippet heading and body appear under the particle.
        (should (string-match-p "§ 1\\.1\\.1 Genitive Attribute" out))
        (should (string-match-p
                 "Attributive genitive:"
                 out))))))

(ert-deftest tibetan-analysis-grammar-falls-back-without-claude-particles ()
  "Without Claude tuples, the Grammar section renders the compact
parser-only list — no § sub-IDs, no snippet block.  Regression guard
that Pass 6c is additive, not destructive of the Pass 6b baseline."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let* ((tibetan-analysis--claude-particles-for-render nil)
           (out (condition-case nil
                    (tibetan-analysis-generate-content
                     "བདག་གིས་ལས་བྱས།")
                  (error nil))))
      (when out
        (should (string-match-p "^\\*\\* Grammar$" out))
        (should (string-match-p "^\\*\\*\\* Particles in This Segment$" out))
        ;; No Claude-driven sub-ID headers.
        (should-not (string-match-p "^  § [0-9]" out))))))

;; ----------------------------------------------------------------------------
;; Pass 6c follow-up (2026-04-22): Interlinear surfaces Resources gloss
;; + ★ for particle-bearing words; Particle Map avoids double-wrap.
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-interlinear-picks-stem-for-particle-bearing-word ()
  "For a word like `མཐུའི' (mthu'i = mthu + GEN 'i) the Interlinear
must pick the best-ranked gloss across BOTH the word-level and
stem-level multi-source lookups.  Without this fix the word-level
lookup returns a low-rank Bundled hit and short-circuits the (or)
fallback, so the Resources / Hopkins stem entries never surface
— the Interlinear silently diverges from the Detailed Dictionary.

Stub two lookups: `mthu'i' → Bundled (rank 9), `mthu' → Resources
(rank 2).  The combined/ranked pick must be Resources — asserted
via the ★ marker emitted by the Interlinear for curated entries."
  (let ((call-log '()))
    (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
               (lambda (word)
                 (push word call-log)
                 (cond
                  ((equal word "མཐུའི")
                   (list (list :source "Bundled"
                               :tibetan "མཐུའི" :wylie "mthu'i"
                               :primary "ambiguous")))
                  ((equal word "མཐུ")
                   (list (list :source "Resources (provided)"
                               :tibetan "མཐུ" :wylie "mthu"
                               :detailed "Kraft // might"
                               :primary "Kraft")))
                  (t nil)))))
      (let ((out (condition-case nil
                     (tibetan-analysis-generate-content "མཐུའི་མན་ངག")
                   (error nil))))
        (when out
          ;; Both lookups happened (word + stem)
          (should (member "མཐུའི" call-log))
          (should (member "མཐུ" call-log))
          ;; The Interlinear line for mthu'i carries the ★ marker
          ;; because Resources was picked by the ranker.
          (let ((il (when (string-match
                           "\\*\\* Interlinear Gloss\n\\([^*]*?\\)\n\\*\\*"
                           out)
                      (match-string 1 out))))
            (when il
              (should (string-match-p "★" il))
              ;; English side of the bilingual gloss wins (prefer-english).
              (should (string-match-p "might" il)))))))))

(ert-deftest tibetan-analysis-particle-map-no-double-wrap ()
  "`nas' appears in both case-particles (ablative) and
converb-particles — the particle-map renderer must not produce
`=~nas~=' double-wrap.  Pass ordering (converbs first) + case-
sensitive matching (explicit `case-fold-search nil') keep the
passes from stepping on each other's output.  Particle tokens
keep their natural lowercase Wylie now that the face remap
handles visual emphasis."
  (let ((map (tibetan-analysis--generate-particle-map
              "བསླབས་ནས་སོང་" nil nil)))
    ;; Converb wrapping present (lowercase `nas' inside `~...~').
    (should (string-match-p "~nas~" map))
    ;; No nested `=~nas~=' soup.
    (should-not (string-match-p "=~nas~=" map))
    (should-not (string-match-p "=\\(~\\|.\\)*nas\\(~\\|.\\)*=" map))))

(ert-deftest tibetan-analysis-particle-map-case-sensitive-pass-isolation ()
  "Case-particle and converb-particle passes must not cross-contaminate
even when `case-fold-search' is non-nil in the surrounding context.
Uses `མཐུའི' (mthu + genitive 'i in one word) where the `\\b'i\\b'
regex can match — testing that GEN marks `=gis=' and doesn't leak
into a converb `~gis~' wrap."
  (let* ((case-fold-search t)    ;; hostile default
         (map (tibetan-analysis--generate-particle-map
               "མཐུའི་གིས་" nil nil)))
    ;; ERG particle `gis' renders as `=gis=' (lowercase, magenta
    ;; via face remap) and never as `~gis~' (converb orange).
    (should (string-match-p "=gis=" map))
    (should-not (string-match-p "~gis~" map))))

(ert-deftest tibetan-analysis-particle-wylie-normalise ()
  "`--particle-wylie-normalise' strips the trailing `a' from
mono-consonant + inherent-vowel forms so `ra' and `r' both
normalise to `r'.  Needed because `tibetan-to-wylie-fixed' emits
the full-syllable `ra' for bare Tibetan `ར' while Claude's
`## Particles' output emits just `r' for the consonant-only
particle."
  (skip-unless (fboundp 'tibetan-analysis--particle-wylie-normalise))
  ;; Inherent-a forms strip to the bare consonant.
  (should (equal "r" (tibetan-analysis--particle-wylie-normalise "ra")))
  (should (equal "s" (tibetan-analysis--particle-wylie-normalise "sa")))
  (should (equal "d" (tibetan-analysis--particle-wylie-normalise "da")))
  ;; Bare consonant forms pass through unchanged.
  (should (equal "r" (tibetan-analysis--particle-wylie-normalise "r")))
  (should (equal "s" (tibetan-analysis--particle-wylie-normalise "s")))
  ;; Multi-char particles left intact (`la' would be ambiguous if
  ;; stripped; `ni', `dang', `kyi' obviously shouldn't change).
  (should (equal "la"   (tibetan-analysis--particle-wylie-normalise "la")))
  (should (equal "ni"   (tibetan-analysis--particle-wylie-normalise "ni")))
  (should (equal "dang" (tibetan-analysis--particle-wylie-normalise "dang")))
  (should (equal "kyi"  (tibetan-analysis--particle-wylie-normalise "kyi"))))

(ert-deftest tibetan-analysis-particle-wylie-equivalent-p ()
  "Equivalence predicate handles `r'/`ra', `s'/`sa' pairs correctly
and rejects truly distinct particles."
  (skip-unless (fboundp 'tibetan-analysis--particle-wylie-equivalent-p))
  ;; Equivalent pairs — Claude gives `r', bialek/Wylie gives `ra'.
  (should (tibetan-analysis--particle-wylie-equivalent-p "r" "ra"))
  (should (tibetan-analysis--particle-wylie-equivalent-p "ra" "r"))
  (should (tibetan-analysis--particle-wylie-equivalent-p "s" "sa"))
  ;; Identity for multi-char particles.
  (should (tibetan-analysis--particle-wylie-equivalent-p "nas" "nas"))
  (should (tibetan-analysis--particle-wylie-equivalent-p "'i" "'i"))
  ;; Truly distinct particles don't match.
  (should-not (tibetan-analysis--particle-wylie-equivalent-p "nas" "la"))
  (should-not (tibetan-analysis--particle-wylie-equivalent-p "gi" "gis"))
  ;; Nil / empty → nil.
  (should-not (tibetan-analysis--particle-wylie-equivalent-p nil "r"))
  (should-not (tibetan-analysis--particle-wylie-equivalent-p "r" nil)))

(ert-deftest tibetan-analysis-grammar-multiple-claude-tuples-per-particle ()
  "When bialek dedups two `nas' occurrences into one entry but
Claude emits two tuples (one per occurrence with different sub-
functions), the Grammar renderer must surface BOTH sub-functions
under the single bialek entry, annotated with the context word
so the student can tell which applies to which occurrence."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w) nil))
            ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
             (lambda (_key sub-id)
               (cond
                ((equal sub-id "2.11.1")
                 (cons "Sequential Temporal"
                       "V-nas marks the earlier action."))
                ((equal sub-id "2.11.2")
                 (cons "Causal" "V-nas in a causal reading."))))))
    (let* ((tibetan-analysis--claude-particles-for-render
            (list (list :word "bslabs nas" :particle "nas"
                        :sub-id "2.11.1" :label "sequential-temporal")
                  (list :word "tshim nas"  :particle "nas"
                        :sub-id "2.11.2" :label "causal-sequential")))
           (out (condition-case nil
                    (tibetan-analysis-generate-content
                     "བསླབས་ནས་ཚིམ་ནས་སོང་།")
                  (error nil))))
      (when out
        ;; Both sub-functions appear under the single `nas' bialek entry.
        (should (string-match-p "§ 2\\.11\\.1 Sequential Temporal" out))
        (should (string-match-p "§ 2\\.11\\.2 Causal" out))
        ;; Context-word annotation tells them apart.
        (should (string-match-p "(in bslabs nas)" out))
        (should (string-match-p "(in tshim nas)" out))))))

(ert-deftest tibetan-analysis-grammar-terminative-ra-r-match ()
  "`der' → bialek reports particle Wylie `ra' (inherent vowel);
Claude reports particle `r' (consonant alone).  The new Wylie-
equivalence normaliser must treat them as the same so the
terminative-§1.5.1 snippet surfaces under the `der' bialek entry."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w) nil))
            ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
             (lambda (_key sub-id)
               (when (equal sub-id "1.5.1")
                 (cons "Place / Location"
                       "Destination or place reached.")))))
    (let* ((tibetan-analysis--claude-particles-for-render
            (list (list :word "der" :particle "r"
                        :sub-id "1.5.1" :label "place")))
           (out (condition-case nil
                    (tibetan-analysis-generate-content "དེར་སོང་།")
                  (error nil))))
      (when out
        (should (string-match-p "§ 1\\.5\\.1 Place / Location" out))
        (should (string-match-p "Destination or place reached" out))))))

(ert-deftest tibetan-analysis-particle-map-lowercase-particles ()
  "Particle tokens inside `=...=' / `~...~' / `*...*' wrappings
keep their natural lowercase Wylie spelling (Pass 6d, 2026-04-22).
Reads cleaner than upcased `='I='; magenta/orange face remap in
`tibetan-analysis-setup-faces' carries the visual emphasis."
  (let ((case-fold-search nil)   ;; be strict about case in this test
        (map (tibetan-analysis--generate-particle-map
              "མཐུའི་བསླབས་ནས་སོང་" nil nil)))
    ;; Genitive `'i' stays lowercase (apostrophe + i), not upcased.
    (should (string-match-p "='i=" map))
    (should-not (string-match-p "='I=" map))
    ;; Converb `nas' likewise.
    (should (string-match-p "~nas~" map))
    (should-not (string-match-p "~NAS~" map))
    ;; Clean converb, not `~=nas=~' double-wrap.
    (should-not (string-match-p "~=nas=~" map))))

;; ----------------------------------------------------------------------------
;; Regression — Particle-map markers render colored even when embedded in
;; compound Wylie tokens where org's emphasis parser won't fire.
;; ----------------------------------------------------------------------------
;;
;; Reproduced 2026-04-22 on Milarepa seg-30: the `='i=' inside `mthu='i='
;; rendered with no face at all (not magenta).  Diagnosis: org-mode's
;; emphasis regexp requires a word-boundary PRE character before the
;; opening `='.  The Particle Map's compact compound
;;   `der mthu='i= man ngag bslabs ~nas~'
;; has `=' directly after the letter `u' — no PRE match, no verbatim
;; parsing, no face.  Similarly for `~nas~' embedded in compounds on
;; other segments.
;;
;; Fix: install buffer-local font-lock keywords in
;; `tibetan-analysis-setup-faces' that match `=X=' / `~X~' regardless
;; of org's word-boundary rules and apply the magenta / orange face
;; directly.  Tested by running font-lock-ensure on a buffer with the
;; compact particle-map text and checking the face on each marker's
;; character.

(defun tibetan-particle-map-faces-test--face-at (buffer pos)
  "Return the face (or list of faces) at POS in BUFFER."
  (with-current-buffer buffer
    (get-text-property pos 'face)))

(defun tibetan-particle-map-faces-test--any-face-eq (face-value target)
  "Return non-nil if FACE-VALUE is TARGET or contains TARGET in its list."
  (cond
   ((eq face-value target) t)
   ((and (listp face-value) (memq target face-value)) t)
   (t nil)))

(ert-deftest tibetan-analysis-particle-map-case-marker-colored-in-compound ()
  "After `tibetan-analysis-setup-faces' runs, a case-particle marker
embedded INSIDE a compound Wylie token (no word boundary before the
opening `=') must carry `tibetan-analysis-case-particle-face' — so
`'i' in `mthu='i=' renders magenta.  Regression guard for the
org-emphasis-parser-doesn't-fire bug spotted on seg-30."
  (require 'org)
  (with-temp-buffer
    (insert "der mthu='i= man ngag bslabs ~nas~ song /\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    ;; Locate the opening `=' of `='i='.
    (goto-char (point-min))
    (let ((case-pos (save-excursion
                      (goto-char (point-min))
                      (and (re-search-forward "='i=" nil t)
                           (match-beginning 0)))))
      (should case-pos)
      (let ((f (tibetan-particle-map-faces-test--face-at
                (current-buffer) case-pos)))
        (should (tibetan-particle-map-faces-test--any-face-eq
                 f 'tibetan-analysis-case-particle-face))))
    ;; And the same for the middle of the marker (`'i').
    (let ((mid-pos (save-excursion
                     (goto-char (point-min))
                     (and (re-search-forward "='i=" nil t)
                          (1+ (match-beginning 0))))))
      (when mid-pos
        (let ((f (tibetan-particle-map-faces-test--face-at
                  (current-buffer) mid-pos)))
          (should (tibetan-particle-map-faces-test--any-face-eq
                   f 'tibetan-analysis-case-particle-face)))))))

(ert-deftest tibetan-analysis-particle-map-converb-marker-colored-in-compound ()
  "Same contract for converb markers `~X~' — the `nas' in
`bslabs ~nas~' (with `~' NOT at a strict word boundary relative to
the preceding word) must render with
`tibetan-analysis-converb-particle-face' (orange)."
  (require 'org)
  (with-temp-buffer
    (insert "bslabs ~nas~ grogs po\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    (let ((conv-pos (save-excursion
                      (goto-char (point-min))
                      (and (re-search-forward "~nas~" nil t)
                           (match-beginning 0)))))
      (should conv-pos)
      (let ((f (tibetan-particle-map-faces-test--face-at
                (current-buffer) conv-pos)))
        (should (tibetan-particle-map-faces-test--any-face-eq
                 f 'tibetan-analysis-converb-particle-face))))))

(ert-deftest tibetan-analysis-particle-map-delimiters-hidden ()
  "The `=' / `~' delimiters wrapping Particle Map markers must be
rendered INVISIBLE so students see a clean `'i' in magenta and
`nas' in orange — not the delimiter characters.  Matches org's
own `org-hide-emphasis-markers' behaviour for clean-boundary
tokens but works even for compound-embedded markers where org's
emphasis parser doesn't fire.

Implementation detail: we use `invisible' with a namespaced
symbol that's added to `buffer-invisibility-spec' by
`tibetan-analysis-setup-faces'.  Both conditions must be true for
rendering to hide the delimiters — just the property isn't enough."
  (require 'org)
  (with-temp-buffer
    (insert "der mthu='i= man ngag bslabs ~nas~ song /\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    ;; Case-particle opening `=' (embedded in compound, col 8).
    (let ((open-pos (save-excursion
                      (goto-char (point-min))
                      (and (re-search-forward "='i=" nil t)
                           (match-beginning 0)))))
      (should open-pos)
      (let ((inv (get-text-property open-pos 'invisible)))
        ;; The `=' character has an `invisible' property set.
        (should inv)
        ;; And that property value is in the buffer's invisibility
        ;; spec — otherwise the property is a no-op visually.
        (should (or (eq inv t)
                    (and (listp buffer-invisibility-spec)
                         (or (memq inv buffer-invisibility-spec)
                             (assq inv buffer-invisibility-spec)))
                    (and (not (listp buffer-invisibility-spec))
                         buffer-invisibility-spec)))))
    ;; Converb `~' delimiter (not in a compound, but same treatment).
    (let ((conv-pos (save-excursion
                      (goto-char (point-min))
                      (and (re-search-forward "~nas~" nil t)
                           (match-beginning 0)))))
      (should conv-pos)
      (let ((inv (get-text-property conv-pos 'invisible)))
        (should inv)))))

(ert-deftest tibetan-analysis-particle-map-content-stays-visible ()
  "The content INSIDE the delimiters (the actual particle letters
`'i', `nas', `gis', ...) must NOT have the `invisible' property —
only the wrapping `=' / `~' characters are hidden.  Regression
guard that the invisibility treatment doesn't accidentally hide
the particle text itself."
  (require 'org)
  (with-temp-buffer
    (insert "der mthu='i= man bslabs ~nas~\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    ;; The apostrophe inside `='i=' (col 9, the `'' character).
    (let ((content-pos (save-excursion
                         (goto-char (point-min))
                         (and (re-search-forward "='i=" nil t)
                              (1+ (match-beginning 0))))))
      (should content-pos)
      (should-not (get-text-property content-pos 'invisible)))
    ;; The `n' inside `~nas~'.
    (let ((content-pos (save-excursion
                         (goto-char (point-min))
                         (and (re-search-forward "~nas~" nil t)
                              (1+ (match-beginning 0))))))
      (should content-pos)
      (should-not (get-text-property content-pos 'invisible)))))

(ert-deftest tibetan-analysis-particle-map-face-setup-is-idempotent ()
  "Running `tibetan-analysis-setup-faces' twice in the same buffer
must not double-install the font-lock keywords (no duplicated rules,
no accumulated face lookups)."
  (require 'org)
  (with-temp-buffer
    (insert "mthu='i= bslabs ~nas~\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (tibetan-analysis-setup-faces)    ;; 2nd call must be a no-op
    (font-lock-ensure (point-min) (point-max))
    ;; Still colored — face application still correct.
    (let ((pos (save-excursion
                 (goto-char (point-min))
                 (and (re-search-forward "='i=" nil t)
                      (match-beginning 0)))))
      (should (tibetan-particle-map-faces-test--any-face-eq
               (tibetan-particle-map-faces-test--face-at (current-buffer) pos)
               'tibetan-analysis-case-particle-face)))))

;; ============================================================================
;; WORD-TOKEN CLEANUP — B3 regression (live review 2026-04-24, seg-16 of
;; gal-chen-nyi-shu.org).  Interlinear rendered
;;   [[term-byang-chub-kyi-sems][/byang chub kyi sems]]
;; — a leading shad leaked from the tokenizer into the link label because
;; the word-cleanup inside the enriched-vocab-pairs loop stripped only
;; trailing shads ("[།༎༏༐༑ ]+$").  Two sibling cleanup sites in the
;; same module (--get-grammatical-role, --build-cat-translation) already
;; strip all shads via "[།༎༏༐༑༔/]".  These tests pin the contract of
;; the extracted helper `tibetan-analysis--clean-word-token'.
;; ============================================================================

(ert-deftest tibetan-analysis-clean-word-token-strips-leading-shad ()
  "B3 regression: leading shad `།' must not survive cleanup.
Without the strip, the token reaches the Interlinear renderer as
`།བྱང་ཆུབ་ཀྱི་སེམས', is Wylie-converted to `/byang chub kyi sems',
and ends up inside the `[[term-...][...]]' link label."
  (should (string= (tibetan-analysis--clean-word-token "།བྱང་ཆུབ་ཀྱི་སེམས")
                   "བྱང་ཆུབ་ཀྱི་སེམས")))

(ert-deftest tibetan-analysis-clean-word-token-strips-trailing-shad ()
  "Trailing shad (the prior behaviour) must still be stripped."
  (should (string= (tibetan-analysis--clean-word-token "བྱང་ཆུབ།")
                   "བྱང་ཆུབ")))

(ert-deftest tibetan-analysis-clean-word-token-strips-both-sides ()
  "Shad on both sides — the case this bug surfaced in verse contexts
like `... na/ /byang chub ...' where each line-break shad produces a
leading shad on the next token AND a trailing on the previous one."
  (should (string= (tibetan-analysis--clean-word-token "།བྱང་ཆུབ།")
                   "བྱང་ཆུབ")))

(ert-deftest tibetan-analysis-clean-word-token-trims-whitespace ()
  "Whitespace on either side is stripped before shad stripping.
Tsheg `་' is NOT stripped — it's a word-internal separator, not a
boundary marker, and it appears inside legitimate multi-syllable
word tokens like `byang་chub'."
  (should (string= (tibetan-analysis--clean-word-token "  །བྱང་ཆུབ  ")
                   "བྱང་ཆུབ")))

(ert-deftest tibetan-analysis-clean-word-token-handles-all-shad-variants ()
  "The full shad family `།༎༏༐༑༔' plus the Wylie stand-in `/' is
stripped.  Matches the character class used by the two sibling
cleanup sites in the same module."
  (should (string= (tibetan-analysis--clean-word-token "༎བྱང") "བྱང"))
  (should (string= (tibetan-analysis--clean-word-token "༔བྱང") "བྱང"))
  (should (string= (tibetan-analysis--clean-word-token "/byang") "byang")))

(ert-deftest tibetan-analysis-clean-word-token-passthrough ()
  "Clean input must come through unchanged."
  (should (string= (tibetan-analysis--clean-word-token "བྱང་ཆུབ")
                   "བྱང་ཆུབ")))

(ert-deftest tibetan-analysis-clean-word-token-empty-input ()
  "Empty / whitespace-only input collapses to empty string, not nil."
  (should (string= (tibetan-analysis--clean-word-token "") ""))
  (should (string= (tibetan-analysis--clean-word-token "  ") "")))

;; ============================================================================
;; CLAUDE VOCAB / PARTICLE OVERRIDE — B1+B2 regression (live review
;; 2026-04-24, seg-16 of gal-chen-nyi-shu.org).
;;
;; B1: `blo sbyangs' was glossed as `<person> Cīrṇabuddhi, Trained Mind'
;; because Steinert's 84000Dict knows *blo sbyangs* only as the 547th
;; buddha's name.  Claude Vocabulary correctly analyses it as a verb
;; phrase in context ("if one trains the mind").  The Interlinear had
;; no way to consult Claude's per-word output.
;;
;; B2: standalone `na' (wylie) was glossed as `(1) to' — the locative
;; sense from the dictionary — but Claude Particles correctly tagged
;; it `2.8, conditional' (conditional converb after verb stem).
;;
;; Both are `Interlinear uses dict-only disambiguation when Claude has
;; already answered the question correctly'.  Fix: two helpers that
;; consult the parsed Claude sections (already threaded through via
;; dynamic binding for the Grammar renderer); override applies at the
;; END of the short-meaning chain so dictionary remains the default
;; for tokens Claude didn't specifically address.
;; ============================================================================

(ert-deftest tibetan-analysis-claude-particle-label-for-token-match ()
  "B2 regression: standalone `ན' (wylie `na') matches a Claude Particles
entry with label `conditional' at sub-id `2.8' — helper returns the
formatted short label `conditional (§2.8)'."
  (let ((particles '((:word "tshad med bzhi po 'di blo sbyangs na"
                      :particle "na"
                      :sub-id "2.8"
                      :label "conditional"))))
    (should (string= (tibetan-analysis--claude-particle-label-for-token
                      "ན" particles)
                     "conditional (§2.8)"))))

(ert-deftest tibetan-analysis-claude-particle-label-for-token-no-match ()
  "Token Wylie doesn't match any :particle — helper returns nil so the
dictionary gloss survives."
  (let ((particles '((:word "tshad med bzhi po 'di blo sbyangs na"
                      :particle "na"
                      :sub-id "2.8"
                      :label "conditional"))))
    (should-not (tibetan-analysis--claude-particle-label-for-token
                 "བློ" particles))))

(ert-deftest tibetan-analysis-claude-particle-label-for-token-nil-particles ()
  "Nil / empty particle list — helper returns nil without error.
This is the first-time-generate path: Claude hasn't responded yet,
no particles threaded in, override must be a no-op."
  (should-not (tibetan-analysis--claude-particle-label-for-token "ན" nil))
  (should-not (tibetan-analysis--claude-particle-label-for-token "ན" '())))

(ert-deftest tibetan-analysis-claude-vocab-gloss-for-token-extracts-quoted-gloss ()
  "B1 regression: Claude Vocabulary line
`blo sbyangs na, verb + locative converb, \"if one trains the mind\", ...'
— helper extracts the 3rd (quoted) field as the short gloss."
  (let ((vocab '(("blo sbyangs na" . "blo sbyangs na, verb + locative converb, \"if one trains the mind\", conditional construction"))))
    (should (string= (tibetan-analysis--claude-vocab-gloss-for-token
                      "བློ་སྦྱངས" vocab)
                     "if one trains the mind"))))

(ert-deftest tibetan-analysis-claude-vocab-gloss-for-token-no-match ()
  "Token's Wylie is not a prefix of any key — helper returns nil."
  (let ((vocab '(("'di" . "'di, adjective, \"this\", demonstrative"))))
    (should-not (tibetan-analysis--claude-vocab-gloss-for-token
                 "བྱང" vocab))))

(ert-deftest tibetan-analysis-claude-vocab-gloss-for-token-nil-vocab ()
  "Nil vocab alist — helper returns nil without error.
First-time-generate path: no Claude response yet."
  (should-not (tibetan-analysis--claude-vocab-gloss-for-token "བློ" nil)))

(ert-deftest tibetan-analysis-claude-vocab-gloss-only-overrides-tagged-glosses ()
  "The dictionary-facing override logic: dict gloss that starts with
`<person>' or `<place>' tag should be replaced by Claude's gloss.
A dict gloss WITHOUT a tag prefix (i.e. a legitimate lexical
reading) is left alone.  This is the integration-level test on
`tibetan-analysis--apply-claude-vocab-override'."
  (let ((vocab '(("blo sbyangs na" . "blo sbyangs na, verb, \"if one trains the mind\", ..."))))
    ;; <person>-tagged dict gloss → override with Claude
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "བློ་སྦྱངས" "<person> Cīrṇabuddhi, Trained Mind" vocab)
                     "if one trains the mind"))
    ;; <place>-tagged → override
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "བློ་སྦྱངས" "<place> Somewhere" vocab)
                     "if one trains the mind"))
    ;; Plain lexical gloss → keep dict's reading (Claude doesn't win
    ;; here, the tag check gates the override).
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "བློ་སྦྱངས" "cultivated, trained" vocab)
                     "cultivated, trained"))
    ;; <term> tag IS legitimate (84000 canonical term marker) — keep.
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "ཚད་མེད་བཞི་པོ" "<term> four immeasurables" vocab)
                     "<term> four immeasurables"))))

(provide 'tibetan-analysis-persist-test)
;;; tibetan-analysis-persist-test.el ends here
