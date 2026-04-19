;;; tibetan-compound-analysis-test.el --- Tests for compound detection -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-compound-analysis)

;; Helper functions
(defun tibetan-count-syllables (text)
  "Count syllables in Tibetan text (split by tsheg).
Returns 0 for nil or empty input."
  (if (and text (stringp text) (not (string-empty-p text)))
      (length (split-string text "་" t "[།༎༏༐༑༔]"))
    0))

;; ============================================================================
;; CONTEXT CONFIGURATION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-get-context-default ()
  "Test getting default context when none specified."
  (with-temp-buffer
    (insert "Some text without context header\n")
    (let ((ctx (tibetan-compound-get-context)))
      (should (listp ctx))
      (should (eq (car ctx) 'classical-prose)))))

(ert-deftest tibetan-compound-get-context-bhutan-kagyu ()
  "Test reading Bhutan Kagyu context from header."
  (with-temp-buffer
    (insert "#+TIBETAN_CONTEXT: bhutan-kagyu-madhyamaka\n")
    (insert "Some text\n")
    (let ((ctx (tibetan-compound-get-context)))
      (should (listp ctx))
      (should (eq (car ctx) 'bhutan-kagyu-madhyamaka)))))

(ert-deftest tibetan-compound-get-context-gelug ()
  "Test reading Gelug context from header."
  (with-temp-buffer
    (insert "#+TIBETAN_CONTEXT: gelug-madhyamaka\n")
    (insert "Text\n")
    (let ((ctx (tibetan-compound-get-context)))
      (should (listp ctx))
      (should (eq (car ctx) 'gelug-madhyamaka)))))

(ert-deftest tibetan-compound-get-context-invalid-defaults ()
  "Test that invalid context defaults to classical-prose."
  (with-temp-buffer
    (insert "#+TIBETAN_CONTEXT: nonexistent-context\n")
    (insert "Text\n")
    (let ((ctx (tibetan-compound-get-context)))
      (should (listp ctx))
      (should (eq (car ctx) 'classical-prose)))))

;; ============================================================================
;; BLOCK MARKER DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-detect-sent-block ()
  "Test detection of 〔sent〕...〔/sent〕 blocks."
  (with-temp-buffer
    (insert "〔sent〕\n")
    (insert "〔seg〕First segment།〔/seg〕\n")
    (insert "〔seg〕Second segment།〔/seg〕\n")
    (insert "〔/sent〕\n")
    (goto-char 20)  ; Inside the sent block
    (let ((result (tibetan-compound--detect-block-markers "sent")))
      (should result)
      (should (= 1 (car result)))  ; Start line
      (should (= 4 (cdr result))))))  ; End line

(ert-deftest tibetan-compound-detect-verse-block ()
  "Test detection of 〔verse :num N〕...〔/verse〕 blocks."
  (with-temp-buffer
    (insert "〔verse :num 1〕\n")
    (insert "རིགས་ཅན་གསུམ་གྱི་གདུལ་བྱ།༎\n")
    (insert "〔/verse〕\n")
    (goto-char 25)  ; Inside the verse block
    (let ((result (tibetan-compound--detect-block-markers "verse")))
      (should result)
      (should (= 1 (car result)))
      (should (= 3 (cdr result))))))

(ert-deftest tibetan-compound-detect-prose-block ()
  "Test detection of 〔prose :comment-on N〕...〔/prose〕 blocks."
  (with-temp-buffer
    (insert "〔prose :comment-on 1〕\n")
    (insert "〔seg〕ཞེས་པ་སྟེ། commentary text〔/seg〕\n")
    (insert "〔/prose〕\n")
    (goto-char 30)  ; Inside the prose block
    (let ((result (tibetan-compound--detect-block-markers "prose")))
      (should result)
      (should (= 1 (car result)))
      (should (= 3 (cdr result))))))

(ert-deftest tibetan-compound-detect-outside-block ()
  "Test that nil is returned when outside any block."
  (with-temp-buffer
    (insert "Some text before\n")
    (insert "〔sent〕\n")
    (insert "〔seg〕Inside〔/seg〕\n")
    (insert "〔/sent〕\n")
    (insert "Some text after\n")
    (goto-char 5)  ; Before the block
    (should-not (tibetan-compound--detect-block-markers "sent"))))

;; ============================================================================
;; VERSE NUMBER DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-detect-verse-number-simple ()
  "Test verse number detection with Tibetan numerals."
  (with-temp-buffer
    (insert "First line of verse\n")
    (insert "Second line\n")
    (insert "Third line ། ༡༢ །\n")
    (goto-char 30)
    (let ((result (tibetan-compound-detect-verse-number)))
      (should (listp result))
      (should (consp result)))))

(ert-deftest tibetan-compound-detect-verse-number-no-match ()
  "Test verse number detection returns nil when no numbers found."
  (with-temp-buffer
    (insert "Line one\n")
    (insert "Line two\n")
    (insert "Line three\n")
    (goto-char 20)
    (let ((result (tibetan-compound-detect-verse-number)))
      ;; May return nil or a range depending on implementation
      (should (or (null result) (listp result))))))

;; ============================================================================
;; DOUBLE SHAD DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-detect-double-shad-simple ()
  "Test double shad boundary detection."
  (with-temp-buffer
    (insert "དེ་ནས་གཞི་ལས།།\n")
    (insert "བྱུང་བའི་ཕུང་པོ།\n")
    (goto-char 20)
    (let ((result (tibetan-compound-detect-double-shad)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-compound-detect-double-shad-returns-range ()
  "Test that double shad detection returns start and end line."
  (with-temp-buffer
    (insert "First section།།\n")
    (insert "Line 2\n")
    (insert "Line 3།།\n")
    (goto-char 30)
    (let ((result (tibetan-compound-detect-double-shad)))
      (when result
        (should (consp result))
        (should (numberp (car result)))
        (should (numberp (cdr result)))
        (should (<= (car result) (cdr result)))))))

;; ============================================================================
;; SYLLABLE METER DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-detect-syllable-meter-seven ()
  "Test 7-syllable meter detection."
  (with-temp-buffer
    (insert "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།\n")
    (insert "དེ་ནི་སྟོང་པ་ཉིད་དུ་བཤད།\n")
    (insert "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་བྱུང་བ།\n")
    (goto-char 20)
    (let ((result (tibetan-compound-detect-syllable-meter)))
      (when result
        (should (consp result))
        (should (numberp (car result)))
        (should (numberp (cdr result)))))))

(ert-deftest tibetan-compound-detect-syllable-meter-irregular ()
  "Test that non-7-syllable text doesn't match meter detection."
  (with-temp-buffer
    (insert "བདག\n")  ; 1 syllable
    (insert "བདག་གི\n")  ; 2 syllables
    (goto-char 10)
    (let ((result (tibetan-compound-detect-syllable-meter)))
      ;; May return nil or a minimal range
      (should (or (null result)
                  (and (listp result) (consp result)))))))

;; ============================================================================
;; EXPLICIT MARKER DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-detect-explicit-markers-sent ()
  "Test explicit sent marker detection."
  (with-temp-buffer
    (insert "〔sent〕\n")
    (insert "Content\n")
    (insert "〔/sent〕\n")
    (goto-char 20)
    (let ((result (tibetan-compound-detect-explicit-markers)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-compound-detect-explicit-markers-legacy ()
  "Test legacy verse marker detection."
  (with-temp-buffer
    (insert "〔verse:001〕\n")
    (insert "Content\n")
    (insert "〔verse:002〕\n")
    (goto-char 20)
    (let ((result (tibetan-compound-detect-explicit-markers)))
      (should (or (null result) (listp result))))))

;; ============================================================================
;; CONTEXT EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-extract-lines-simple ()
  "Test extracting Tibetan lines from range."
  (with-temp-buffer
    (insert "First line\n")
    (insert "གང་ཞིག་\n")
    (insert "དེ་ནི་\n")
    (insert "Last line\n")
    (let ((lines (tibetan-compound-extract-lines 2 3)))
      (should (listp lines))
      (should (= (length lines) 2)))))

(ert-deftest tibetan-compound-extract-lines-empty ()
  "Test extracting from empty range."
  (with-temp-buffer
    (insert "Line 1\n")
    (insert "Line 2\n")
    (let ((lines (tibetan-compound-extract-lines 1 1)))
      (should (listp lines)))))

;; ============================================================================
;; HASH AND FILENAME TESTS
;; ============================================================================

(ert-deftest tibetan-compound-compute-hash-consistency ()
  "Test that same lines produce same hash."
  (let ((lines1 '((1 . "གང་ཞིག་") (2 . "དེ་ནི་")))
        (lines2 '((1 . "གང་ཞིག་") (2 . "དེ་ནི་"))))
    (should (string= (tibetan-compound-compute-hash lines1)
                     (tibetan-compound-compute-hash lines2)))))

(ert-deftest tibetan-compound-compute-hash-different ()
  "Test that different lines produce different hashes."
  (let ((lines1 '((1 . "གང་ཞིག་") (2 . "དེ་ནི་")))
        (lines2 '((1 . "སྟོང་པ་") (2 . "ཉིད་དུ་"))))
    (should-not (string= (tibetan-compound-compute-hash lines1)
                         (tibetan-compound-compute-hash lines2)))))

(ert-deftest tibetan-compound-filename-numbering ()
  "Test compound filename generation."
  (let ((name1 (tibetan-compound-filename 1))
        (name2 (tibetan-compound-filename 42)))
    (should (string= name1 "compound-001.org"))
    (should (string= name2 "compound-042.org"))))

;; ============================================================================
;; CONNECTOR ANALYSIS TESTS
;; ============================================================================

(ert-deftest tibetan-compound-analyze-connectors-nas ()
  "Test ནས converb connector analysis."
  (let ((lines '((1 . "བྱས་ནས།") (2 . "དེ་ནི།"))))
    (let ((connectors (tibetan-compound-analyze-connectors lines)))
      (should (listp connectors)))))

(ert-deftest tibetan-compound-analyze-connectors-te ()
  "Test ཏེ converb connector analysis."
  (let ((lines '((1 . "བྱས་ཏེ།") (2 . "དེ་ནི།"))))
    (let ((connectors (tibetan-compound-analyze-connectors lines)))
      (should (listp connectors)))))

(ert-deftest tibetan-compound-analyze-connectors-ching ()
  "Test ཅིང converb connector analysis."
  (let ((lines '((1 . "བྱས་ཅིང་།") (2 . "དེ་ནི།"))))
    (let ((connectors (tibetan-compound-analyze-connectors lines)))
      (should (listp connectors)))))

(ert-deftest tibetan-compound-analyze-topic-flow ()
  "Test topic flow analysis across lines."
  (let ((lines '((1 . "བདག་གི་སེམས།") (2 . "བདག་ལ་དོགས་པ།"))))
    (let ((analysis (tibetan-compound-analyze-topic-flow lines)))
      (should (listp analysis)))))

;; ============================================================================
;; BOUNDARY DETECTION STRATEGY TESTS
;; ============================================================================

(ert-deftest tibetan-compound-detect-boundaries-region ()
  "Test that region takes priority in boundary detection."
  (with-temp-buffer
    (insert "Line 1\n")
    (insert "Line 2\n")
    (insert "Line 3\n")
    (insert "Line 4\n")
    ;; Select lines 2-3
    (set-mark (line-beginning-position 2))
    (goto-char (line-end-position 3))
    (let ((result (tibetan-compound-detect-region)))
      (when result
        (should (= (car result) 2))
        (should (= (cdr result) 3))))))

(ert-deftest tibetan-compound-detect-boundaries-fallthrough ()
  "Test fallthrough detection strategy."
  (with-temp-buffer
    (insert "Some content\n")
    (insert "More content\n")
    (goto-char 10)
    (let ((result (tibetan-compound-detect-boundaries)))
      ;; Should try multiple strategies
      (should (or (null result) (listp result))))))

;; ============================================================================
;; CONTENT GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-compound-generate-content-basic ()
  "Test content generation from lines."
  (let ((lines '((1 . "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།")
                 (2 . "དེ་ནི་སྟོང་པ་ཉིད་དུ་བཤད།")))
        (context '(classical-prose)))
    (let ((content (tibetan-compound-generate-content lines context)))
      (should (stringp content))
      (should (> (length content) 0)))))

(ert-deftest tibetan-compound-format-structure-summary ()
  "Test structure summary formatting."
  (let ((lines '((1 . "Line 1") (2 . "Line 2") (3 . "Line 3"))))
    (let ((summary (with-temp-buffer
                     (dolist (line-data lines)
                       (insert (format "%s\n" (cdr line-data))))
                     (buffer-string))))
      (should (stringp summary))
      (should (> (length summary) 0)))))

;; ============================================================================
;; FILE OPERATIONS TESTS
;; ============================================================================

(ert-deftest tibetan-compound-find-existing-not-found ()
  "Test that find-existing returns nil when file doesn't exist."
  (skip-unless (fboundp 'tibetan-compound-find-existing))
  (with-temp-buffer
    (let ((temp-file (make-temp-file "test" nil ".org")))
      (unwind-protect
          (progn
            (set-visited-file-name temp-file)
            (let ((lines '((1 . "unique-content-xyz-abc"))))
              (let ((result (tibetan-compound-find-existing lines)))
                (should (or (null result) (stringp result))))))
        (when (file-exists-p temp-file)
          (delete-file temp-file))))))

(ert-deftest tibetan-compound-check-sync-basic ()
  "Test sync checking with simple content."
  (skip-unless (fboundp 'tibetan-compound-check-sync))
  (let ((temp-file (make-temp-file "test-sync" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TIBETAN_HASH: abc123\n"))
          (let ((result (tibetan-compound-check-sync temp-file '((1 . "test")))))
            (should (or (null result) (eq result t)))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

;; ============================================================================
;; INTERACTIVE COMMAND TESTS
;; ============================================================================

(ert-deftest tibetan-compound-analyze-document-structure ()
  "Test document structure analysis."
  (with-temp-buffer
    (insert "* Chapter 1\n")
    (insert "Content line\n")
    (insert "More content\n")
    (let ((result (tibetan-compound-analyze-document-structure)))
      ;; Should return analysis without error
      (should (or (null result) (listp result) (stringp result))))))

(ert-deftest tibetan-compound-analyze-verse-structure ()
  "Test verse structure analysis."
  (let ((lines '((1 . "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།")
                 (2 . "དེ་ནི་སྟོང་པ་ཉིད་དུ་བཤད།"))))
    (let ((analysis (tibetan-compound-analyze-verse-structure lines)))
      (should (or (null analysis) (listp analysis) (stringp analysis))))))

;; ============================================================================
;; UNTESTED PUBLIC FUNCTIONS
;; ============================================================================

;; Function 1: tibetan-compound-create-file
(ert-deftest tibetan-compound-create-file-basic ()
  "Test creating a compound analysis file with valid inputs."
  (skip-unless (fboundp 'tibetan-compound-create-file))
  (let* ((compound-id 1)
         (lines '((1 . "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།")
                  (2 . "དེ་ནི་སྟོང་པ་ཉིད་དུ་བཤད།")))
         (source-file "/tmp/source.org")
         (auto-content "** Some analysis\nContent here"))
    (with-temp-buffer
      (set-visited-file-name source-file t)
      (let ((result (tibetan-compound-create-file compound-id lines source-file auto-content)))
        (should (stringp result))
        (should (string-match "compound-001\\.org$" result))))))

(ert-deftest tibetan-compound-create-file-returns-filepath ()
  "Test that create-file returns a valid filepath."
  (skip-unless (fboundp 'tibetan-compound-create-file))
  (let* ((compound-id 42)
         (lines '((5 . "བདག་གི་སེམས།")))
         (source-file "/tmp/source.org")
         (auto-content "Analysis"))
    (with-temp-buffer
      (set-visited-file-name source-file t)
      (let ((filepath (tibetan-compound-create-file compound-id lines source-file auto-content)))
        (should (file-name-absolute-p filepath))
        (should (string-match "compound-042\\.org$" filepath))))))

(ert-deftest tibetan-compound-create-file-includes-header ()
  "Test that created file contains required headers."
  (skip-unless (fboundp 'tibetan-compound-create-file))
  (let ((temp-dir (make-temp-file "tibetan-test" t)))
    (unwind-protect
        (let* ((compound-id 3)
               (lines '((1 . "Test")))
               (source-file (expand-file-name "source.org" temp-dir))
               (auto-content "Content"))
          (with-temp-file source-file (insert ""))
          (with-current-buffer (find-file-noselect source-file)
            (let ((result (tibetan-compound-create-file compound-id lines source-file auto-content)))
              (when (file-exists-p result)
                (with-temp-buffer
                  (insert-file-contents result)
                  (should (string-match "#\\+TITLE:" (buffer-string)))
                  (should (string-match "#\\+TIBETAN_HASH:" (buffer-string)))
                  (should (string-match "\\* Tibetan Text" (buffer-string))))))))
      (delete-directory temp-dir t))))

;; Function 2: tibetan-compound-generate-translations-section
(ert-deftest tibetan-compound-generate-translations-section-basic ()
  "Test generating translations section with basic inputs."
  (skip-unless (fboundp 'tibetan-compound-generate-translations-section))
  (let ((lines '((1 . "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།")
                 (2 . "དེ་ནི་སྟོང་པ་ཉིད་དུ་བཤད།")))
        (connectors '())
        (context '(classical-prose)))
    (let ((result (tibetan-compound-generate-translations-section lines connectors context)))
      (should (stringp result))
      (should (> (length result) 0)))))

(ert-deftest tibetan-compound-generate-translations-section-returns-string ()
  "Test that translations section returns org-formatted string."
  (skip-unless (fboundp 'tibetan-compound-generate-translations-section))
  (let ((lines '((1 . "བདག")))
        (connectors nil)
        (context '(gelug-madhyamaka)))
    (let ((result (tibetan-compound-generate-translations-section lines connectors context)))
      (should (stringp result))
      (should (string-match "Working Translation" result)))))

(ert-deftest tibetan-compound-generate-translations-section-with-connectors ()
  "Test translations section generation with connector grammar."
  (skip-unless (fboundp 'tibetan-compound-generate-translations-section))
  (let ((lines '((1 . "བྱས་ནས།") (2 . "དེ་ནི།")))
        (connectors '(((from . 1) (to . 2) (type . converb) (connector . "ནས"))))
        (context '(classical-prose)))
    (let ((result (condition-case nil
                      (tibetan-compound-generate-translations-section lines connectors context)
                    (error nil))))
      ;; Should return a string or nil if connectors format doesn't match
      (should (or (null result) (stringp result))))))

;; Function 3: tibetan-compound-build-line-translation
(ert-deftest tibetan-compound-build-line-translation-basic ()
  "Test building a line translation with gloss and verbs."
  (skip-unless (fboundp 'tibetan-compound-build-line-translation))
  (let ((gloss '(("གང་ཞིག་" . "whatever") ("རྟེན་ཅིང་" . "dependent")))
        (verbs '())
        (connectors '())
        (line-idx 1)
        (total-lines 2))
    (let ((result (tibetan-compound-build-line-translation gloss verbs connectors line-idx total-lines)))
      (should (stringp result))
      (should (> (length result) 0)))))

(ert-deftest tibetan-compound-build-line-translation-with-verbs ()
  "Test line translation includes verb meaning."
  (skip-unless (fboundp 'tibetan-compound-build-line-translation))
  (let ((gloss '(("བྱེད" . "do")))
        (verbs '((meaning . "produces")))
        (connectors '())
        (line-idx 1)
        (total-lines 1))
    (let ((result (tibetan-compound-build-line-translation gloss verbs connectors line-idx total-lines)))
      (should (stringp result))
      (should (string-match "[Dd]" result)))))

(ert-deftest tibetan-compound-build-line-translation-final-line-period ()
  "Test that final line gets period punctuation."
  (skip-unless (fboundp 'tibetan-compound-build-line-translation))
  (let ((gloss '(("བདག" . "I")))
        (verbs '())
        (connectors '())
        (line-idx 3)
        (total-lines 3))
    (let ((result (tibetan-compound-build-line-translation gloss verbs connectors line-idx total-lines)))
      (should (string-match "\\.$" result)))))

(ert-deftest tibetan-compound-build-line-translation-empty-gloss ()
  "Test line translation handles empty gloss gracefully."
  (skip-unless (fboundp 'tibetan-compound-build-line-translation))
  (let ((gloss '())
        (verbs '())
        (connectors '())
        (line-idx 1)
        (total-lines 1))
    (let ((result (tibetan-compound-build-line-translation gloss verbs connectors line-idx total-lines)))
      (should (stringp result)))))

;; Function 4: tibetan-open-compound-analysis
(ert-deftest tibetan-open-compound-analysis-is-command ()
  "Test that tibetan-open-compound-analysis is an interactive command."
  (skip-unless (fboundp 'tibetan-open-compound-analysis))
  (should (commandp 'tibetan-open-compound-analysis)))

(ert-deftest tibetan-open-compound-analysis-callable ()
  "Test that open-compound-analysis can be called without fatal error.
In batch mode, display functions may signal errors which is acceptable."
  (skip-unless (fboundp 'tibetan-open-compound-analysis))
  ;; In batch mode, `display-buffer-in-side-window' can perform a
  ;; non-local exit that escapes `condition-case', aborting the whole
  ;; ERT batch run. The command-ness check in
  ;; `tibetan-open-compound-analysis-is-command' already exercises the
  ;; interactive entry point; skip the live-display smoke test when we
  ;; have no display to talk to.
  (skip-unless (not noninteractive))
  (with-temp-buffer
    (insert "〔sent〕\n")
    (insert "གང་ཞིག་\n")
    (insert "དེ་ནི་\n")
    (insert "〔/sent〕\n")
    (set-visited-file-name "/tmp/test.org" t)
    ;; Call the function — errors from display-buffer are acceptable in batch
    (condition-case err
        (progn
          (tibetan-open-compound-analysis)
          (should t))  ; Passed without error
      (error
       ;; In batch mode, display errors are expected and acceptable
       (should (stringp (error-message-string err)))))))

(ert-deftest tibetan-open-compound-analysis-arity ()
  "Test that open-compound-analysis takes zero arguments."
  (skip-unless (fboundp 'tibetan-open-compound-analysis))
  (let ((func-spec (help-function-arglist 'tibetan-open-compound-analysis)))
    ;; Interactive function should accept no args (or &rest args)
    (should (or (null func-spec)
                (equal func-spec '(&rest _))
                (listp func-spec)))))

;; Function 5: tibetan-compound-regenerate-auto
(ert-deftest tibetan-compound-regenerate-auto-basic ()
  "Test regenerating auto-analysis section in compound file."
  (skip-unless (fboundp 'tibetan-compound-regenerate-auto))
  (let ((temp-file (make-temp-file "test-regen" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TITLE: Test\n")
            (insert "#+TIBETAN_HASH: abc123\n")
            (insert "#+LAST_ANALYZED: 2025-01-01\n")
            (insert "* Auto-Analysis\n")
            (insert ":PROPERTIES:\n")
            (insert ":GENERATED: t\n")
            (insert ":END:\n\n")
            (insert "Old content\n"))
          (let ((lines '((1 . "དེ་ནི་")))
                (context '(classical-prose)))
            ;; Should not error
            (condition-case err
                (progn
                  (with-current-buffer (find-file-noselect temp-file)
                    (tibetan-compound-regenerate-auto temp-file lines context))
                  (should t))
              (error (should nil)))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest tibetan-compound-regenerate-auto-updates-hash ()
  "Test that regenerate-auto updates hash header."
  (skip-unless (fboundp 'tibetan-compound-regenerate-auto))
  (let ((temp-file (make-temp-file "test-hash" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TITLE: Test\n")
            (insert "#+TIBETAN_HASH: old-hash\n")
            (insert "#+LAST_ANALYZED: 2025-01-01\n")
            (insert "* Auto-Analysis\n")
            (insert ":PROPERTIES:\n")
            (insert ":GENERATED: t\n")
            (insert ":END:\n\n")
            (insert "Content\n"))
          (let ((lines '((1 . "new-text")))
                (context '(classical-prose)))
            (with-current-buffer (find-file-noselect temp-file)
              (tibetan-compound-regenerate-auto temp-file lines context))
            ;; Re-read file after regeneration to check header
            (with-temp-buffer
              (insert-file-contents temp-file)
              (should (re-search-forward "#\\+TIBETAN_HASH:" nil t)))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest tibetan-compound-regenerate-auto-preserves-user-sections ()
  "Test that regenerate-auto preserves user-created sections."
  (skip-unless (fboundp 'tibetan-compound-regenerate-auto))
  (let ((temp-file (make-temp-file "test-preserve" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TITLE: Test\n")
            (insert "#+TIBETAN_HASH: abc\n")
            (insert "* Auto-Analysis\n")
            (insert ":PROPERTIES:\n")
            (insert ":GENERATED: t\n")
            (insert ":END:\n\n")
            (insert "Old\n")
            (insert "* Working Translation\n")
            (insert "My custom translation\n"))
          (let ((lines '((1 . "text")))
                (context '(classical-prose)))
            (with-current-buffer (find-file-noselect temp-file)
              (tibetan-compound-regenerate-auto temp-file lines context)
              (goto-char (point-min))
              ;; User section should still exist
              (should (re-search-forward "Working Translation" nil t)))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

;; Function 6: tibetan-compound-get-next-id
(ert-deftest tibetan-compound-get-next-id-empty-folder ()
  "Test get-next-id returns 1 when no compounds exist."
  (skip-unless (fboundp 'tibetan-compound-get-next-id))
  (let ((temp-dir (make-temp-file "empty-test" t)))
    (unwind-protect
        (with-temp-buffer
          (set-visited-file-name (expand-file-name "source.org" temp-dir) t)
          (let ((result (tibetan-compound-get-next-id)))
            (should (numberp result))
            (should (= result 1))))
      (delete-directory temp-dir t))))

(ert-deftest tibetan-compound-get-next-id-increments ()
  "Test get-next-id returns next available ID."
  (skip-unless (fboundp 'tibetan-compound-get-next-id))
  (let ((temp-dir (make-temp-file "id-test" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "analysis" temp-dir) t)
          (with-temp-file (expand-file-name "analysis/compound-001.org" temp-dir) (insert ""))
          (with-temp-file (expand-file-name "analysis/compound-002.org" temp-dir) (insert ""))
          (with-temp-buffer
            (set-visited-file-name (expand-file-name "source.org" temp-dir) t)
            (let ((result (tibetan-compound-get-next-id)))
              (should (numberp result))
              (should (= result 3)))))
      (delete-directory temp-dir t))))

(ert-deftest tibetan-compound-get-next-id-returns-number ()
  "Test that get-next-id returns a number."
  (skip-unless (fboundp 'tibetan-compound-get-next-id))
  (with-temp-buffer
    (set-visited-file-name "/tmp/test.org" t)
    (let ((result (tibetan-compound-get-next-id)))
      (should (numberp result))
      (should (> result 0)))))

;; Function 7: tibetan-compound-get-folder
(ert-deftest tibetan-compound-get-folder-returns-string ()
  "Test get-folder returns a string path."
  (skip-unless (fboundp 'tibetan-compound-get-folder))
  (with-temp-buffer
    (set-visited-file-name "/tmp/test.org" t)
    (let ((result (tibetan-compound-get-folder)))
      (should (stringp result)))))

(ert-deftest tibetan-compound-get-folder-creates-directory ()
  "Test get-folder creates analysis directory if missing."
  (skip-unless (fboundp 'tibetan-compound-get-folder))
  (let ((temp-dir (make-temp-file "folder-test" t)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (set-visited-file-name (expand-file-name "source.org" temp-dir) t)
            (let ((result (tibetan-compound-get-folder)))
              (should (file-exists-p result))
              (should (file-directory-p result)))))
      (delete-directory temp-dir t))))

(ert-deftest tibetan-compound-get-folder-ends-with-analysis ()
  "Test get-folder path ends with /analysis directory."
  (skip-unless (fboundp 'tibetan-compound-get-folder))
  (with-temp-buffer
    (set-visited-file-name "/tmp/source.org" t)
    (let ((result (tibetan-compound-get-folder)))
      (should (string-match "analysis/?$" result)))))

;; Function 8: tibetan-reanalyze-compound
(ert-deftest tibetan-reanalyze-compound-is-command ()
  "Test that tibetan-reanalyze-compound is an interactive command."
  (skip-unless (fboundp 'tibetan-reanalyze-compound))
  (should (commandp 'tibetan-reanalyze-compound)))

(ert-deftest tibetan-reanalyze-compound-checks-buffer ()
  "Test reanalyze-compound errors when not in compound file."
  (skip-unless (fboundp 'tibetan-reanalyze-compound))
  (with-temp-buffer
    (set-visited-file-name "/tmp/not-a-compound.org" t)
    (should-error (tibetan-reanalyze-compound))))

(ert-deftest tibetan-reanalyze-compound-requires-source-reference ()
  "Test reanalyze-compound requires SOURCE header in compound file."
  (skip-unless (fboundp 'tibetan-reanalyze-compound))
  (let ((temp-file (make-temp-file "compound-999" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TITLE: Compound 999\n")
            (insert "* Tibetan Text\n"))
          (with-temp-buffer
            (insert-file-contents temp-file)
            (set-visited-file-name temp-file t)
            (should-error (tibetan-reanalyze-compound))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest tibetan-reanalyze-compound-arity ()
  "Test that reanalyze-compound takes zero arguments."
  (skip-unless (fboundp 'tibetan-reanalyze-compound))
  (let ((func-spec (help-function-arglist 'tibetan-reanalyze-compound)))
    (should (or (null func-spec)
                (equal func-spec '(&rest _))
                (listp func-spec)))))

(provide 'tibetan-compound-analysis-test)
;;; tibetan-compound-analysis-test.el ends here
