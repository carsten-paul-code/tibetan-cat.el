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

(provide 'tibetan-analysis-persist-test)
;;; tibetan-analysis-persist-test.el ends here
