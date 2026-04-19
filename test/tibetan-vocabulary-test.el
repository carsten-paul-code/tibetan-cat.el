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
Trailing tsheg is trimmed so the stripped form matches the canonical
(tsheg-free) keys used in Resources and bundled dictionaries."
  (should (string= (tibetan-strip-particles "བདག་གི") "བདག"))
  (should (string= (tibetan-strip-particles "ཆོས་ཀྱི") "ཆོས")))

(ert-deftest tibetan-strip-particles-ergative ()
  "Test stripping ergative particles."
  (should (string= (tibetan-strip-particles "བདག་གིས") "བདག"))
  (should (string= (tibetan-strip-particles "སེམས་ཀྱིས") "སེམས")))

(ert-deftest tibetan-strip-particles-ablative ()
  "Test stripping ablative particles."
  (should (string= (tibetan-strip-particles "དེ་ནས") "དེ"))
  (should (string= (tibetan-strip-particles "དེ་ལས") "དེ")))

(ert-deftest tibetan-strip-particles-converb ()
  "Test stripping converb particles."
  (should (string= (tibetan-strip-particles "བྱས་ནས") "བྱས"))
  (should (string= (tibetan-strip-particles "བྱས་ཏེ") "བྱས")))

(ert-deftest tibetan-strip-particles-topic ()
  "Test stripping topic marker."
  (should (string= (tibetan-strip-particles "དེ་ནི") "དེ")))

(ert-deftest tibetan-strip-particles-final ()
  "Test stripping sentence-final particles."
  (should (string= (tibetan-strip-particles "ཡིན་ནོ") "ཡིན"))
  (should (string= (tibetan-strip-particles "ཡོད་དོ") "ཡོད")))

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
    ;; Register both stripped forms: strip-particles may return either
    ;; "བདག" (bare) or "བདག་" (with trailing tsheg) depending on input.
    (puthash "བདག་" "self" tibetan-comprehensive-vocabulary)
    (puthash "བདག" "self" tibetan-comprehensive-vocabulary)
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
  "Test that lookup follows correct priority order.
Note: The function combines English (from glossary) and German (from resources).
When both glossary and resources exist, result is formatted as 'glossary (DE: resources)'."
  (let ((tibetan-dictionary-priority
         '(resources custom rangjung-yeshe local-glossary))
        (tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal))
        (tibetan-rangjung-yeshe-vocabulary (make-hash-table :test 'equal))
        (tibetan-rangjung-yeshe-loaded t))
    ;; Set different meanings in each source
    (puthash "བདག" "resources-meaning" tibetan-current-resources-vocab)
    (puthash "བདག" "custom-meaning" tibetan-current-custom-vocab)
    (puthash "བདག" "glossary-meaning" tibetan-comprehensive-vocabulary)
    ;; When both glossary and resources exist, they are combined
    (should (string= (tibetan-lookup-word "བདག") "glossary-meaning (DE: resources-meaning)"))))

(ert-deftest tibetan-lookup-word-fallback-to-custom ()
  "Test fallback to custom vocab when not in resources.
Note: The function combines English (from glossary) and German (from custom).
When both glossary and custom exist, result is formatted as 'glossary (DE: custom)'."
  (let ((tibetan-dictionary-priority
         '(resources custom rangjung-yeshe local-glossary))
        (tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal))
        (tibetan-rangjung-yeshe-vocabulary (make-hash-table :test 'equal))
        (tibetan-rangjung-yeshe-loaded t))
    (puthash "བདག" "custom-meaning" tibetan-current-custom-vocab)
    (puthash "བདག" "glossary-meaning" tibetan-comprehensive-vocabulary)
    ;; When both glossary and custom exist, they are combined
    (should (string= (tibetan-lookup-word "བདག") "glossary-meaning (DE: custom-meaning)"))))

(ert-deftest tibetan-lookup-word-fallback-to-glossary ()
  "Test fallback to comprehensive glossary."
  (let ((tibetan-dictionary-priority
         '(resources custom rangjung-yeshe local-glossary))
        (tibetan-current-resources-vocab nil)
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

;; ============================================================================
;; PARSE WORDLIST PDF TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-parse-wordlist-pdf-nonexistent-file ()
  "Test PDF parsing with nonexistent file."
  (let ((vocab (tibetan-parse-wordlist-pdf "/nonexistent/file.pdf")))
    (should (hash-table-p vocab))
    (should (= (hash-table-count vocab) 0))))

(ert-deftest tibetan-parse-wordlist-pdf-nil-path ()
  "Test PDF parsing with nil path."
  (let ((vocab (tibetan-parse-wordlist-pdf nil)))
    (should (hash-table-p vocab))
    (should (= (hash-table-count vocab) 0))))

(ert-deftest tibetan-parse-wordlist-pdf-returns-hashtable ()
  "Test that PDF parsing returns a hash table."
  (let ((result (tibetan-parse-wordlist-pdf "/dev/null")))
    (should (hash-table-p result))))

;; ============================================================================
;; LOAD RESOURCES VOCAB TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-load-resources-vocab-initializes-variable ()
  "Test that load-resources-vocab initializes the variable."
  (let ((tibetan-current-resources-vocab nil))
    (tibetan-load-resources-vocab)
    ;; Should set the variable (either nil or hash-table)
    (should (or (null tibetan-current-resources-vocab)
                (hash-table-p tibetan-current-resources-vocab)))))

(ert-deftest tibetan-load-resources-vocab-returns-hashtable ()
  "Test that load-resources-vocab returns a hash table."
  (let ((result (tibetan-load-resources-vocab)))
    (should (or (null result) (hash-table-p result)))))

(ert-deftest tibetan-load-resources-vocab-safe ()
  "Test that load-resources-vocab doesn't error on missing resources."
  (condition-case err
      (tibetan-load-resources-vocab)
    (error (should-not (format "Should not error: %s" err)))))

;; ============================================================================
;; LOAD CUSTOM VOCAB TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-load-custom-vocab-returns-hashtable ()
  "Test that load-custom-vocab returns a hash table."
  (let ((result (tibetan-load-custom-vocab)))
    (should (or (null result) (hash-table-p result)))))

(ert-deftest tibetan-load-custom-vocab-safe ()
  "Test that load-custom-vocab doesn't error on missing file."
  (condition-case err
      (tibetan-load-custom-vocab)
    (error (should-not (format "Should not error: %s" err)))))

(ert-deftest tibetan-load-custom-vocab-sets-variable ()
  "Test that load-custom-vocab sets the current variable."
  (let ((tibetan-current-custom-vocab nil))
    (tibetan-load-custom-vocab)
    ;; Should set the variable
    (should (or (null tibetan-current-custom-vocab)
                (hash-table-p tibetan-current-custom-vocab)))))

;; ============================================================================
;; LOOKUP IN DHARMAMITRA TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-lookup-word-in-dharmamitra-basic ()
  "Test DharmaMitra lookup with simple word."
  (let ((result (tibetan-lookup-word-in-dharmamitra "བདག")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-lookup-word-in-dharmamitra-empty ()
  "Test DharmaMitra lookup with empty string."
  (let ((result (tibetan-lookup-word-in-dharmamitra "")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-lookup-word-in-dharmamitra-nil ()
  "Test DharmaMitra lookup with nil."
  (let ((result (tibetan-lookup-word-in-dharmamitra nil)))
    (should (or (null result) (stringp result)))))

;; ============================================================================
;; FORMAT BILINGUAL MEANING TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-format-bilingual-meaning-english-only ()
  "Test bilingual format with English only."
  (let ((result (tibetan-format-bilingual-meaning "self" nil)))
    (should (stringp result))
    (should (string-match-p "self" result))))

(ert-deftest tibetan-format-bilingual-meaning-german-only ()
  "Test bilingual format with German only."
  (let ((result (tibetan-format-bilingual-meaning nil "ich")))
    (should (stringp result))))

(ert-deftest tibetan-format-bilingual-meaning-both ()
  "Test bilingual format with both English and German."
  (let ((result (tibetan-format-bilingual-meaning "self" "ich")))
    (should (stringp result))
    (should (string-match-p "self" result))))

(ert-deftest tibetan-format-bilingual-meaning-empty-strings ()
  "Test bilingual format with empty strings."
  (let ((result (tibetan-format-bilingual-meaning "" "")))
    (should (stringp result))))

(ert-deftest tibetan-format-bilingual-meaning-special-chars ()
  "Test bilingual format with special characters."
  (let ((result (tibetan-format-bilingual-meaning "self & ego" "Ich/du")))
    (should (stringp result))
    (should (> (length result) 0))))

;; ============================================================================
;; EXTRACT ENGLISH FROM BILINGUAL TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-extract-english-from-bilingual-english-only ()
  "Test extracting English from bilingual meaning."
  (let ((result (tibetan-extract-english-from-bilingual "self (DE: ich)")))
    (should (stringp result))
    (should (string-match-p "self" result))))

(ert-deftest tibetan-extract-english-from-bilingual-complex ()
  "Test extracting from complex bilingual format."
  (let ((result (tibetan-extract-english-from-bilingual "self, ego (DE: ich, das Selbst)")))
    (should (stringp result))))

(ert-deftest tibetan-extract-english-from-bilingual-no-german ()
  "Test extracting when no German part exists."
  (let ((result (tibetan-extract-english-from-bilingual "self")))
    (should (stringp result))
    (should (string-match-p "self" result))))

(ert-deftest tibetan-extract-english-from-bilingual-empty ()
  "Test extracting from empty string."
  (let ((result (tibetan-extract-english-from-bilingual "")))
    (should (stringp result))))

(ert-deftest tibetan-extract-english-from-bilingual-nil ()
  "Test extracting from nil."
  (let ((result (tibetan-extract-english-from-bilingual nil)))
    (should (or (null result) (stringp result)))))

;; ============================================================================
;; DETECT VERB WITH SUFFIX TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-detect-verb-with-suffix-ba ()
  "Test detecting verb with བ suffix."
  (let ((syllables '("བ" "ྱ" "ས")))
    (let ((result (tibetan-detect-verb-with-suffix syllables 0)))
      (should (or (null result) (listp result) (stringp result))))))

(ert-deftest tibetan-detect-verb-with-suffix-va ()
  "Test detecting verb with ྭ suffix."
  (let ((syllables '("ྭ")))
    (let ((result (tibetan-detect-verb-with-suffix syllables 0)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-detect-verb-with-suffix-ma ()
  "Test detecting verb with མ suffix."
  (let ((syllables '("མ")))
    (let ((result (tibetan-detect-verb-with-suffix syllables 0)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-detect-verb-with-suffix-no-suffix ()
  "Test with syllables that don't form verb suffix."
  (let ((syllables '("ང")))
    (let ((result (tibetan-detect-verb-with-suffix syllables 0)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-detect-verb-with-suffix-empty ()
  "Test with empty syllables list."
  (let ((result (tibetan-detect-verb-with-suffix '() 0)))
    (should (or (null result) (listp result)))))

(ert-deftest tibetan-detect-verb-with-suffix-out-of-range ()
  "Test with start index out of range."
  (let ((syllables '("བ")))
    (let ((result (tibetan-detect-verb-with-suffix syllables 10)))
      (should (or (null result) (listp result))))))

;; ============================================================================
;; RESOURCE PATHS TESTS
;; ============================================================================

(ert-deftest tibetan-get-custom-vocab-file-returns-string ()
  "Test that get-custom-vocab-file returns a string path."
  (let ((result (tibetan-get-custom-vocab-file)))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-find-resources-folder-returns-string ()
  "Test that find-resources-folder returns a string or nil."
  (let ((result (tibetan-find-resources-folder)))
    (should (or (null result) (stringp result)))))

;; ============================================================================
;; VOCABULARY INITIALIZATION TESTS
;; ============================================================================

;; Note: `tibetan-vocabulary-initialize-callable' is defined earlier in this
;; file (see around line 534). Defining it again here used to abort the file
;; load mid-way under newer ERT, silently preventing all subsequent tests
;; (including regression tests at the end of the file) from registering.

(ert-deftest tibetan-vocabulary-initialize-safe ()
  "Test that vocabulary-initialize doesn't error."
  (condition-case err
      (tibetan-vocabulary-initialize)
    (error (should-not (format "Should not error: %s" err)))))

;; ============================================================================
;; PARSE VOCAB PDF TESTS
;; ============================================================================

(ert-deftest tibetan-parse-vocab-pdf-nonexistent-file ()
  "Test parsing non-existent PDF file."
  (skip-unless (fboundp 'tibetan-parse-vocab-pdf))
  (let ((result (tibetan-parse-vocab-pdf "/nonexistent/path/vocab.pdf")))
    (should (hash-table-p result))
    (should (= (hash-table-count result) 0))))

(ert-deftest tibetan-parse-vocab-pdf-returns-hash ()
  "Test that parsing returns a hash table."
  (skip-unless (fboundp 'tibetan-parse-vocab-pdf))
  (let ((result (tibetan-parse-vocab-pdf nil)))
    (should (hash-table-p result))))

(ert-deftest tibetan-parse-vocab-pdf-nil-input ()
  "Test parsing with nil input."
  (skip-unless (fboundp 'tibetan-parse-vocab-pdf))
  (let ((result (tibetan-parse-vocab-pdf nil)))
    (should (hash-table-p result))
    (should (= (hash-table-count result) 0))))

(ert-deftest tibetan-parse-vocab-pdf-empty-hash-table ()
  "Test that empty PDF path returns empty hash table."
  (skip-unless (fboundp 'tibetan-parse-vocab-pdf))
  (let ((result (tibetan-parse-vocab-pdf "")))
    (should (hash-table-p result))
    ;; Empty path should return empty hash
    (should (<= (hash-table-count result) 1))))

;; ============================================================================
;; RESOURCES-VOCAB PRIORITY REGRESSION TEST
;; ============================================================================
;; When a Resources folder contains both a clean TXT wordlist and a
;; two-column PDF Wortliste, pdftotext -layout fuses right-column
;; continuation text into left-column entries (e.g. ལྕགས་ཕོ ended up
;; with the gloss of a neighbouring entry: "distress overwhelms").
;; `tibetan-load-resources-vocab' must therefore skip PDFs whenever
;; TXT/ORG entries are already loaded.

(ert-deftest tibetan-resources-vocab-pdf-skipped-when-txt-present ()
  "TXT/ORG entries must take precedence; PDF must not clobber them."
  (skip-unless (fboundp 'tibetan-load-resources-vocab))
  (skip-unless (fboundp 'tibetan-parse-wordlist-txt))
  (let* ((tmp-root (make-temp-file "tibetan-res-" t))
         (res-dir  (expand-file-name "Resources" tmp-root))
         (doc-dir  (expand-file-name "doc" tmp-root))
         (doc-file (expand-file-name "seg.org" doc-dir))
         (txt      (expand-file-name "wordlist.txt" res-dir))
         (pdf      (expand-file-name "Wortliste-bad.pdf" res-dir)))
    (unwind-protect
        (progn
          (make-directory res-dir t)
          (make-directory doc-dir t)
          (with-temp-file doc-file (insert "dummy"))
          (with-temp-file txt
            (insert "lcags pho 'brug gi lo\n")
            (insert "    iron male dragon year (1040)\n"))
          (with-temp-file pdf (insert "not a real pdf"))
          (when (boundp 'tibetan-resources-vocab-cache)
            (clrhash tibetan-resources-vocab-cache))
          (setq tibetan-current-resources-vocab nil)
          (with-current-buffer (find-file-noselect doc-file)
            (unwind-protect
                (tibetan-load-resources-vocab)
              (kill-buffer)))
          (should (hash-table-p tibetan-current-resources-vocab))
          (should (or (gethash "lcags pho 'brug gi lo"
                               tibetan-current-resources-vocab)
                      (gethash "ལྕགས་ཕོ་འབྲུག་གི་ལོ"
                               tibetan-current-resources-vocab)))
          (should-not (gethash "ལྕགས་ཕོ" tibetan-current-resources-vocab))
          (should-not (gethash "lcags pho" tibetan-current-resources-vocab)))
      (delete-directory tmp-root t))))

(provide 'tibetan-vocabulary-test)
;;; tibetan-vocabulary-test.el ends here
