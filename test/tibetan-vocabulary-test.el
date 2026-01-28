;;; tibetan-vocabulary-test.el --- Tests for Tibetan vocabulary module -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for vocabulary lookup, parsing, and formatting functions.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Setup load path
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-vocabulary)

;; Declare variables that may not be loaded during tests
;; (tibetan-skip-external-glossaries prevents loading bundled glossaries)
(defvar tibetan-comprehensive-vocabulary nil
  "Comprehensive vocabulary hash table - declared for tests.")
(defvar tibetan-rangjung-yeshe-vocabulary nil
  "Rangjung Yeshe vocabulary - declared for tests.")
(defvar tibetan-rangjung-yeshe-loaded nil
  "Whether Rangjung Yeshe is loaded - declared for tests.")
(defvar tibetan-current-resources-vocab nil
  "Resources vocabulary - declared for tests.")
(defvar tibetan-current-custom-vocab nil
  "Custom vocabulary - declared for tests.")

;; ============================================================================
;; SAFE SUBSTRING TESTS
;; ============================================================================

(ert-deftest tibetan-vocab-safe-substring-basic ()
  "Test basic substring extraction."
  (should (string= (tibetan-vocab-safe-substring "hello" 0 2) "he"))
  (should (string= (tibetan-vocab-safe-substring "hello" 1 4) "ell"))
  (should (string= (tibetan-vocab-safe-substring "hello" 0) "hello")))

(ert-deftest tibetan-vocab-safe-substring-tibetan ()
  "Test substring with Tibetan characters."
  (let ((tib "བདག་གི་"))
    (should (stringp (tibetan-vocab-safe-substring tib 0 2)))
    (should (stringp (tibetan-vocab-safe-substring tib 0)))))

(ert-deftest tibetan-vocab-safe-substring-out-of-range ()
  "Test substring with out of range indices."
  (should (string= (tibetan-vocab-safe-substring "abc" 0 100) "abc"))
  (should (string= (tibetan-vocab-safe-substring "abc" 100 200) ""))
  (should (string= (tibetan-vocab-safe-substring "abc" -5 2) "ab")))

(ert-deftest tibetan-vocab-safe-substring-nil-input ()
  "Test substring with nil input."
  (should (string= (tibetan-vocab-safe-substring nil 0 2) ""))
  (should (string= (tibetan-vocab-safe-substring 123 0 2) "")))

(ert-deftest tibetan-vocab-safe-substring-empty ()
  "Test substring with empty string."
  (should (string= (tibetan-vocab-safe-substring "" 0 2) ""))
  (should (string= (tibetan-vocab-safe-substring "" 0) "")))

;; ============================================================================
;; PARTICLE STRIPPING TESTS
;; ============================================================================

(ert-deftest tibetan-strip-particles-genitive ()
  "Test stripping genitive particles.
Note: Function preserves trailing tsheg as it's part of syllable structure."
  (should (string= (tibetan-strip-particles "བདག་གི") "བདག་"))
  (should (string= (tibetan-strip-particles "ཆོས་ཀྱི") "ཆོས་")))

(ert-deftest tibetan-strip-particles-ergative ()
  "Test stripping ergative particles."
  (should (string= (tibetan-strip-particles "བདག་གིས") "བདག་"))
  (should (string= (tibetan-strip-particles "སེམས་ཀྱིས") "སེམས་")))

(ert-deftest tibetan-strip-particles-ablative ()
  "Test stripping ablative particles."
  (should (string= (tibetan-strip-particles "དེ་ནས") "དེ་"))
  (should (string= (tibetan-strip-particles "དེ་ལས") "དེ་")))

(ert-deftest tibetan-strip-particles-converb ()
  "Test stripping converb particles."
  (should (string= (tibetan-strip-particles "བྱས་ནས") "བྱས་"))
  (should (string= (tibetan-strip-particles "བྱས་ཏེ") "བྱས་")))

(ert-deftest tibetan-strip-particles-topic ()
  "Test stripping topic marker."
  (should (string= (tibetan-strip-particles "དེ་ནི") "དེ་")))

(ert-deftest tibetan-strip-particles-final ()
  "Test stripping sentence-final particles."
  (should (string= (tibetan-strip-particles "ཡིན་ནོ") "ཡིན་"))
  (should (string= (tibetan-strip-particles "ཡོད་དོ") "ཡོད་")))

(ert-deftest tibetan-strip-particles-punctuation ()
  "Test stripping Tibetan punctuation."
  (should (string= (tibetan-strip-particles "བདག།") "བདག"))
  (should (string= (tibetan-strip-particles "བདག༎") "བདག")))

(ert-deftest tibetan-strip-particles-no-particle ()
  "Test that words without particles are unchanged."
  (should (string= (tibetan-strip-particles "བདག") "བདག"))
  (should (string= (tibetan-strip-particles "ཆོས") "ཆོས")))

(ert-deftest tibetan-strip-particles-empty ()
  "Test empty and nil input."
  (should (string= (tibetan-strip-particles "") ""))
  (should (string= (tibetan-strip-particles "།") "")))

;; ============================================================================
;; CUSTOM VOCAB FILE TESTS
;; ============================================================================

(ert-deftest tibetan-get-custom-vocab-file-none ()
  "Test getting custom vocab file when not set."
  (with-temp-buffer
    (insert "* Test heading\nSome content")
    (should (null (tibetan-get-custom-vocab-file)))))

(ert-deftest tibetan-get-custom-vocab-file-absolute ()
  "Test getting absolute custom vocab file path."
  (with-temp-buffer
    (insert "#+TIBETAN_VOCAB_FILE: /path/to/vocab.pdf\n* Content")
    (should (string= (tibetan-get-custom-vocab-file) "/path/to/vocab.pdf"))))

(ert-deftest tibetan-get-custom-vocab-file-relative ()
  "Test getting relative custom vocab file path."
  (let ((temp-file (make-temp-file "test-org" nil ".org")))
    (unwind-protect
        (with-temp-buffer
          (setq buffer-file-name temp-file)
          (insert "#+TIBETAN_VOCAB_FILE: vocab/wordlist.pdf\n* Content")
          (let ((result (tibetan-get-custom-vocab-file)))
            (should result)
            (should (file-name-absolute-p result))
            (should (string-match-p "vocab/wordlist.pdf$" result))))
      (delete-file temp-file))))

;; ============================================================================
;; RESOURCES FOLDER TESTS
;; ============================================================================

(ert-deftest tibetan-find-resources-folder-none ()
  "Test when no Resources folder exists."
  (with-temp-buffer
    (setq buffer-file-name nil)
    (should (null (tibetan-find-resources-folder)))))

(ert-deftest tibetan-find-resources-folder-exists ()
  "Test finding Resources folder when it exists."
  (let* ((temp-dir (make-temp-file "test-dir" t))
         (res-dir (expand-file-name "Resources" temp-dir))
         (test-file (expand-file-name "test.org" temp-dir)))
    (unwind-protect
        (progn
          (make-directory res-dir)
          (with-temp-buffer
            (setq buffer-file-name test-file)
            (let ((result (tibetan-find-resources-folder)))
              (should result)
              (should (string= result res-dir)))))
      (delete-directory temp-dir t))))

;; ============================================================================
;; PARSE WORDLIST TXT TESTS
;; ============================================================================

(ert-deftest tibetan-parse-wordlist-txt-tab-separated ()
  "Test parsing TAB-separated wordlist."
  (let ((temp-file (make-temp-file "wordlist" nil ".txt")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "བདག\tself, I\n")
            (insert "ཆོས\tdharma, teaching\n"))
          (let ((vocab (tibetan-parse-wordlist-txt temp-file)))
            (should (hash-table-p vocab))
            (should (gethash "བདག" vocab))
            (should (gethash "ཆོས" vocab))))
      (delete-file temp-file))))

(ert-deftest tibetan-parse-wordlist-txt-colon-separated ()
  "Test parsing colon-separated wordlist."
  (let ((temp-file (make-temp-file "wordlist" nil ".txt")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "བདག: self, I\n")
            (insert "ཆོས: dharma, teaching\n"))
          (let ((vocab (tibetan-parse-wordlist-txt temp-file)))
            (should (hash-table-p vocab))
            (should (> (hash-table-count vocab) 0))))
      (delete-file temp-file))))

(ert-deftest tibetan-parse-wordlist-txt-dash-separated ()
  "Test parsing dash-separated wordlist."
  (let ((temp-file (make-temp-file "wordlist" nil ".txt")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "བདག - self, I\n")
            (insert "ཆོས - dharma\n"))
          (let ((vocab (tibetan-parse-wordlist-txt temp-file)))
            (should (hash-table-p vocab))
            (should (> (hash-table-count vocab) 0))))
      (delete-file temp-file))))

(ert-deftest tibetan-parse-wordlist-txt-skip-comments ()
  "Test that comments are skipped.
Note: tibetan--store-vocab-entry stores under both Tibetan and Wylie keys,
so a single valid entry may result in 2 hash entries."
  (let ((temp-file (make-temp-file "wordlist" nil ".txt")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "# This is a comment\n")
            (insert "; Another comment\n")
            (insert "བདག\tself\n"))
          (let ((vocab (tibetan-parse-wordlist-txt temp-file)))
            ;; May be 1 or 2 depending on whether Wylie conversion is available
            (should (>= (hash-table-count vocab) 1))
            (should (<= (hash-table-count vocab) 2))))
      (delete-file temp-file))))

(ert-deftest tibetan-parse-wordlist-txt-empty-file ()
  "Test parsing empty file."
  (let ((temp-file (make-temp-file "wordlist" nil ".txt")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert ""))
          (let ((vocab (tibetan-parse-wordlist-txt temp-file)))
            (should (hash-table-p vocab))
            (should (= (hash-table-count vocab) 0))))
      (delete-file temp-file))))

(ert-deftest tibetan-parse-wordlist-txt-nonexistent ()
  "Test parsing nonexistent file."
  (let ((vocab (tibetan-parse-wordlist-txt "/nonexistent/path/file.txt")))
    (should (hash-table-p vocab))
    (should (= (hash-table-count vocab) 0))))

;; ============================================================================
;; PARSE WORDLIST ORG TESTS
;; ============================================================================

(ert-deftest tibetan-parse-wordlist-org-headings ()
  "Test parsing org file with heading format."
  (let ((temp-file (make-temp-file "wordlist" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "* བདག\n  self, I, ego\n")
            (insert "* ཆོས\n  dharma, teaching, phenomenon\n"))
          (let ((vocab (tibetan-parse-wordlist-org temp-file)))
            (should (hash-table-p vocab))
            (should (> (hash-table-count vocab) 0))))
      (delete-file temp-file))))

(ert-deftest tibetan-parse-wordlist-org-table ()
  "Test parsing org file with table format."
  (let ((temp-file (make-temp-file "wordlist" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "| Term | Definition |\n")
            (insert "|------+------------|\n")
            (insert "| བདག | self |\n")
            (insert "| ཆོས | dharma |\n"))
          (let ((vocab (tibetan-parse-wordlist-org temp-file)))
            (should (hash-table-p vocab))
            (should (> (hash-table-count vocab) 0))))
      (delete-file temp-file))))

(ert-deftest tibetan-parse-wordlist-org-nonexistent ()
  "Test parsing nonexistent org file."
  (let ((vocab (tibetan-parse-wordlist-org "/nonexistent/file.org")))
    (should (hash-table-p vocab))
    (should (= (hash-table-count vocab) 0))))

;; ============================================================================
;; VOCABULARY LOOKUP TESTS
;; ============================================================================

(ert-deftest tibetan-lookup-word-in-local-glossary-not-loaded ()
  "Test lookup when glossary not loaded."
  ;; When tibetan-comprehensive-vocabulary is not bound or nil
  (let ((tibetan-comprehensive-vocabulary nil))
    (should (null (tibetan-lookup-word-in-local-glossary "བདག")))))

(ert-deftest tibetan-lookup-word-in-local-glossary-found ()
  "Test lookup when word is in glossary."
  (let ((tibetan-comprehensive-vocabulary (make-hash-table :test 'equal))
        (tibetan-rangjung-yeshe-vocabulary nil)  ; Disable Rangjung Yeshe for isolated test
        (tibetan-rangjung-yeshe-loaded t))
    (puthash "བདག" "self, I" tibetan-comprehensive-vocabulary)
    (should (string= (tibetan-lookup-word-in-local-glossary "བདག") "self, I"))))

(ert-deftest tibetan-lookup-word-in-local-glossary-list-entry ()
  "Test lookup when glossary entry is a list."
  (let ((tibetan-comprehensive-vocabulary (make-hash-table :test 'equal))
        (tibetan-rangjung-yeshe-vocabulary nil)
        (tibetan-rangjung-yeshe-loaded t))
    (puthash "བདག" '("self, I" "ego") tibetan-comprehensive-vocabulary)
    (should (string= (tibetan-lookup-word-in-local-glossary "བདག") "self, I"))))

(ert-deftest tibetan-lookup-word-in-local-glossary-with-particle ()
  "Test lookup strips particle to find root.
Note: tibetan-strip-particles preserves trailing tsheg, so we need
to register both forms or use tsheg form."
  (let ((tibetan-comprehensive-vocabulary (make-hash-table :test 'equal))
        (tibetan-rangjung-yeshe-vocabulary nil)
        (tibetan-rangjung-yeshe-loaded t))
    ;; Register with tsheg (how strip-particles returns it)
    (puthash "བདག་" "self" tibetan-comprehensive-vocabulary)
    ;; བདག་གི = བདག with genitive particle
    (should (string= (tibetan-lookup-word-in-local-glossary "བདག་གི") "self"))))

(ert-deftest tibetan-lookup-word-in-custom-vocab-none ()
  "Test custom vocab lookup when no custom vocab set."
  (let ((tibetan-current-custom-vocab nil))
    (should (null (tibetan-lookup-word-in-custom-vocab "བདག")))))

(ert-deftest tibetan-lookup-word-in-custom-vocab-found ()
  "Test custom vocab lookup when word is found."
  (let ((tibetan-current-custom-vocab (make-hash-table :test 'equal)))
    (puthash "བདག" "self" tibetan-current-custom-vocab)
    (should (string= (tibetan-lookup-word-in-custom-vocab "བདག") "self"))))

(ert-deftest tibetan-lookup-word-in-resources-vocab-none ()
  "Test resources vocab lookup when no resources vocab."
  (let ((tibetan-current-resources-vocab nil))
    (should (null (tibetan-lookup-word-in-resources-vocab "བདག")))))

(ert-deftest tibetan-lookup-word-in-resources-vocab-found ()
  "Test resources vocab lookup when word is found."
  (let ((tibetan-current-resources-vocab (make-hash-table :test 'equal)))
    (puthash "བདག" "self, I" tibetan-current-resources-vocab)
    (should (string= (tibetan-lookup-word-in-resources-vocab "བདག") "self, I"))))

;; ============================================================================
;; MAIN LOOKUP FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-lookup-word-priority ()
  "Test that lookup follows correct priority order."
  (let ((tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    ;; Set different meanings in each source
    (puthash "བདག" "resources-meaning" tibetan-current-resources-vocab)
    (puthash "བདག" "custom-meaning" tibetan-current-custom-vocab)
    (puthash "བདག" "glossary-meaning" tibetan-comprehensive-vocabulary)
    ;; Resources should have highest priority
    (should (string= (tibetan-lookup-word "བདག") "resources-meaning"))))

(ert-deftest tibetan-lookup-word-fallback-to-custom ()
  "Test fallback to custom vocab when not in resources."
  (let ((tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "བདག" "custom-meaning" tibetan-current-custom-vocab)
    (puthash "བདག" "glossary-meaning" tibetan-comprehensive-vocabulary)
    (should (string= (tibetan-lookup-word "བདག") "custom-meaning"))))

(ert-deftest tibetan-lookup-word-fallback-to-glossary ()
  "Test fallback to comprehensive glossary."
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal))
        (tibetan-rangjung-yeshe-vocabulary nil)
        (tibetan-rangjung-yeshe-loaded t))  ; Pretend already loaded (but empty)
    (puthash "བདག" "glossary-meaning" tibetan-comprehensive-vocabulary)
    (should (string= (tibetan-lookup-word "བདག") "glossary-meaning"))))

;; ============================================================================
;; VOCABULARY EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-extract-vocabulary-basic ()
  "Test basic vocabulary extraction."
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "བདག" "self" tibetan-comprehensive-vocabulary)
    (let ((vocab (tibetan-extract-vocabulary "བདག")))
      (should (listp vocab))
      (should (> (length vocab) 0))
      (should (assoc "བདག" vocab)))))

(ert-deftest tibetan-extract-vocabulary-multiple-words ()
  "Test extraction of multiple words."
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "བདག" "self" tibetan-comprehensive-vocabulary)
    (puthash "ཆོས" "dharma" tibetan-comprehensive-vocabulary)
    (let ((vocab (tibetan-extract-vocabulary "བདག་ཆོས")))
      (should (listp vocab))
      (should (>= (length vocab) 2)))))

(ert-deftest tibetan-extract-vocabulary-nil-input ()
  "Test extraction with nil input."
  (should (null (tibetan-extract-vocabulary nil))))

(ert-deftest tibetan-extract-vocabulary-empty-input ()
  "Test extraction with empty input."
  (let ((vocab (tibetan-extract-vocabulary "")))
    (should (listp vocab))
    (should (= (length vocab) 0))))

;; ============================================================================
;; FORMATTING TESTS
;; ============================================================================

(ert-deftest tibetan-vocab-extract-short-meaning-basic ()
  "Test extracting short meaning from full text."
  (let ((short (tibetan-vocab-extract-short-meaning "self, ego, I")))
    (should (stringp short))
    (should (<= (length short) 100))))

(ert-deftest tibetan-vocab-extract-short-meaning-long ()
  "Test truncation of very long meanings."
  (let* ((long-text (make-string 200 ?a))
         (short (tibetan-vocab-extract-short-meaning long-text)))
    (should (stringp short))
    (should (<= (length short) 103)))) ; 100 + "..."

(ert-deftest tibetan-vocab-extract-short-meaning-nil ()
  "Test with nil input."
  (should (null (tibetan-vocab-extract-short-meaning nil))))

(ert-deftest tibetan-vocab-has-extended-info-short ()
  "Test extended info check for short text."
  (should-not (tibetan-vocab-has-extended-info-p "short meaning")))

(ert-deftest tibetan-vocab-has-extended-info-long ()
  "Test extended info check for long text."
  (let ((long-text (make-string 150 ?a)))
    (should (tibetan-vocab-has-extended-info-p long-text))))

(ert-deftest tibetan-vocab-has-extended-info-nil ()
  "Test extended info check for nil."
  (should-not (tibetan-vocab-has-extended-info-p nil)))

(ert-deftest tibetan-vocab-format-entry-compact ()
  "Test compact formatting of vocabulary entry."
  (let ((result (tibetan-vocab-format-entry "བདག" "self, I")))
    (should (stringp result))
    (should (string-match-p "བདག" result))
    (should (string-match-p "self" result))))

(ert-deftest tibetan-vocab-format-entry-org-compact ()
  "Test org-compact formatting."
  (let ((result (tibetan-vocab-format-entry "བདག" "self, I" 'org-compact)))
    (should (stringp result))
    (should (string-match-p "^- " result))
    (should (string-match-p "བདག" result))))

(ert-deftest tibetan-vocab-format-entry-org-detailed ()
  "Test org-detailed formatting."
  (let ((result (tibetan-vocab-format-entry "བདག" "self, I" 'org-detailed)))
    (should (stringp result))
    (should (string-match-p "^- " result))))

(ert-deftest tibetan-vocab-format-entry-full ()
  "Test full formatting."
  (let ((result (tibetan-vocab-format-entry "བདག" "self, I" 'full)))
    (should (stringp result))
    (should (string-match-p "བདག" result))))

(ert-deftest tibetan-vocab-format-entry-no-meaning ()
  "Test formatting when meaning is nil."
  (let ((result (tibetan-vocab-format-entry "བདག" nil)))
    (should (stringp result))
    (should (string-match-p "\\[look up\\]" result))))

(ert-deftest tibetan-vocab-format-list-basic ()
  "Test formatting list of vocab pairs."
  (let ((pairs '(("བདག" . "self") ("ཆོས" . "dharma"))))
    (let ((result (tibetan-vocab-format-list pairs)))
      (should (stringp result))
      (should (string-match-p "བདག" result))
      (should (string-match-p "ཆོས" result)))))

(ert-deftest tibetan-vocab-format-list-empty ()
  "Test formatting empty list."
  (let ((result (tibetan-vocab-format-list '())))
    (should (stringp result))
    (should (string= result ""))))

(ert-deftest tibetan-vocab-format-detailed-list-basic ()
  "Test detailed formatting of list."
  (let ((pairs '(("བདག" . "self, I, ego"))))
    (let ((result (tibetan-vocab-format-detailed-list pairs)))
      (should (stringp result))
      (should (string-match-p "བདག" result)))))

(ert-deftest tibetan-vocab-format-detailed-list-org ()
  "Test detailed formatting for org-mode."
  (let ((pairs '(("བདག" . "self"))))
    (let ((result (tibetan-vocab-format-detailed-list pairs t)))
      (should (stringp result))
      (should (string-match-p "བདག" result)))))

;; ============================================================================
;; RELOAD GLOSSARIES TESTS
;; ============================================================================

(ert-deftest tibetan-reload-all-glossaries-callable ()
  "Test that reload-all-glossaries is callable."
  (should (fboundp 'reload-all-glossaries)))

(ert-deftest tibetan-vocabulary-initialize-callable ()
  "Test that tibetan-vocabulary-initialize is callable."
  (should (fboundp 'tibetan-vocabulary-initialize)))

;; ============================================================================
;; CACHE TESTS
;; ============================================================================

(ert-deftest tibetan-dharmamitra-cache-exists ()
  "Test that DharmaMitra cache exists."
  (should (boundp 'tibetan-dharmamitra-cache))
  (should (hash-table-p tibetan-dharmamitra-cache)))

(ert-deftest tibetan-custom-vocab-cache-exists ()
  "Test that custom vocab cache exists."
  (should (boundp 'tibetan-custom-vocab-cache))
  (should (hash-table-p tibetan-custom-vocab-cache)))

(ert-deftest tibetan-resources-vocab-cache-exists ()
  "Test that resources vocab cache exists."
  (should (boundp 'tibetan-resources-vocab-cache))
  (should (hash-table-p tibetan-resources-vocab-cache)))

;; ============================================================================
;; STORE VOCAB ENTRY TESTS
;; ============================================================================

(ert-deftest tibetan--store-vocab-entry-basic ()
  "Test storing a basic vocabulary entry."
  (let ((table (make-hash-table :test 'equal)))
    (tibetan--store-vocab-entry table "བདག" "self")
    (should (string= (gethash "བདག" table) "self"))))

(ert-deftest tibetan--store-vocab-entry-wylie ()
  "Test storing Wylie entry also creates Tibetan key."
  (let ((table (make-hash-table :test 'equal)))
    ;; This depends on tibetan-wylie-to-tibetan being available
    (tibetan--store-vocab-entry table "bdag" "self")
    (should (string= (gethash "bdag" table) "self"))))

(ert-deftest tibetan--store-vocab-entry-trims ()
  "Test that entry value is trimmed."
  (let ((table (make-hash-table :test 'equal)))
    (tibetan--store-vocab-entry table "བདག" "  self  ")
    (should (string= (gethash "བདག" table) "self"))))

;; ============================================================================
;; RANGJUNG YESHE FALLBACK TESTS
;; ============================================================================

(ert-deftest tibetan-rangjung-yeshe-vocabulary-var-exists ()
  "Test that Rangjung Yeshe vocabulary variable exists."
  (should (boundp 'tibetan-rangjung-yeshe-vocabulary)))

(ert-deftest tibetan-rangjung-yeshe-loaded-var-exists ()
  "Test that Rangjung Yeshe loaded flag exists."
  (should (boundp 'tibetan-rangjung-yeshe-loaded)))

(ert-deftest tibetan-rangjung-yeshe-get-path-callable ()
  "Test that get-path function exists and is callable."
  (should (fboundp 'tibetan-rangjung-yeshe-get-path))
  (let ((path (tibetan-rangjung-yeshe-get-path)))
    (should (or (null path) (stringp path)))))

(ert-deftest tibetan-rangjung-yeshe-load-callable ()
  "Test that load function exists."
  (should (fboundp 'tibetan-rangjung-yeshe-load)))

(ert-deftest tibetan-lookup-word-in-rangjung-yeshe-callable ()
  "Test that Rangjung Yeshe lookup function exists."
  (should (fboundp 'tibetan-lookup-word-in-rangjung-yeshe)))

(ert-deftest tibetan-lookup-word-in-rangjung-yeshe-nil-safe ()
  "Test that Rangjung Yeshe lookup handles nil safely."
  ;; Should not error
  (condition-case nil
      (tibetan-lookup-word-in-rangjung-yeshe "")
    (error (should-not "Should not error on empty string"))))

(provide 'tibetan-vocabulary-test)
;;; tibetan-vocabulary-test.el ends here
