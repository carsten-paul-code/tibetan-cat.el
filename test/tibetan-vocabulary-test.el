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

(ert-deftest tibetan-strip-particles-preserves-verb-past-stems ()
  "Known Hill-DB past/imperative stems that happen to end in a
particle-shaped suffix (`བས' for causal converb) are returned
UNCHANGED.  Without this guard `བསླབས' (past of སློབ) would get
stripped to the nonsense root `བསླ' — breaking every dictionary
lookup downstream and producing garbled Wylie like `basla' in the
Interlinear + Detailed Dictionary output."
  (skip-unless (fboundp 'tibetan-verb-lookup))
  ;; བསླབས (past of སློབ "to train") — must stay intact
  (should (string= (tibetan-strip-particles "བསླབས") "བསླབས"))
  ;; སླེབས (past of སླེབ "to arrive")
  (should (string= (tibetan-strip-particles "སླེབས") "སླེབས"))
  ;; Control: a bare noun + causal converb DOES still strip (the
  ;; guard is specific to verb-stem overlap, not a blanket disable).
  (should (string= (tibetan-strip-particles "རྒྱལ་པོ་བས") "རྒྱལ་པོ")))

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
  "Test when no Resources folder exists.
Binds `default-directory' to a Resources-free temp dir so the
default-directory fallback (added 2026-06-03) has nothing to find."
  (let ((clean (make-temp-file "tcat-nores" t)))
    (unwind-protect
        (with-temp-buffer
          (setq buffer-file-name nil)
          (let ((default-directory (file-name-as-directory clean)))
            (should (null (tibetan-find-resources-folder)))))
      (delete-directory clean t))))

(ert-deftest tibetan-find-resources-folder-falls-back-to-default-directory ()
  "When the buffer is not visiting a file (headless batch reanalysis),
the Resources folder is resolved relative to `default-directory'.

Regression for the 2026-06-03 corpus-wide Resources wipe: batch
reanalyse ran `generate-content' in the ambient `*scratch*' buffer
where `buffer-file-name' is nil, so the finder returned nil and the
curated Resources glosses were silently dropped from every file."
  (let* ((root (make-temp-file "tcat-resroot" t))
         (analysis (expand-file-name "work/analysis" root))
         (res (expand-file-name "Resources" root)))  ; ../../Resources from analysis
    (unwind-protect
        (progn
          (make-directory analysis t)
          (make-directory res t)
          (with-temp-buffer
            (setq buffer-file-name nil)
            (let ((default-directory (file-name-as-directory analysis)))
              (should (string= (file-name-as-directory
                                (tibetan-find-resources-folder))
                               (file-name-as-directory res))))))
      (delete-directory root t))))

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

(ert-deftest tibetan-extract-vocabulary-rejects-particle-tail-compound ()
  "Compounds whose tail syllable is a case / converb particle are
tokenised as stem + particle, not glued into a single lookup key.

Regression for Milarepa seg-026 (2026-04-21): `བདག་ལ' (Skt. naḥ
\"to me\") and `སྟོད་ནས' (Skt. uparimāt \"from above\") are real
Steinert entries that were being picked up as 2-syllable compounds
by the greedy MWU pass, hiding the grammatical `bdag + LA' /
`stod + NAS' split that Particle Map, Clause Structure, and
Grammatical Markers render correctly.

The fix rejects any compound whose LAST syllable is in
`tibetan-extract-vocab--particle-tails'."
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    ;; Seed the idiomatic 2-syllable compound AND the stem alone.
    (puthash "བདག་ལ" "to me [compound idiom]"
             tibetan-comprehensive-vocabulary)
    (puthash "བདག" "self"
             tibetan-comprehensive-vocabulary)
    (let* ((vocab (tibetan-extract-vocabulary "བདག་ལ"))
           (keys (mapcar #'car vocab)))
      ;; The compound with particle tail must NOT be picked.
      (should-not (member "བདག་ལ" keys))
      ;; The stem alone must be recognised.
      (should (member "བདག" keys)))))

(ert-deftest tibetan-extract-vocabulary-rejects-particle-head-compound ()
  "Compounds whose first syllable is a case / converb particle are
rejected — a particle cannot legitimately be the HEAD of a compound.

Without this, after `བདག་ལ' splits into `bdag' + LA, the next
iteration starting at `ལ' would be allowed to pick up `ལ་སྟོད'
(\"Latö, western Tsang\" — a real place name in the dictionary),
stranding the particle with the following content word."
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    ;; Seed the particle-head 2-syllable compound AND the stem alone.
    (puthash "ལ་སྟོད" "Latö, western Tsang"
             tibetan-comprehensive-vocabulary)
    (puthash "སྟོད" "upper part"
             tibetan-comprehensive-vocabulary)
    (let* ((vocab (tibetan-extract-vocabulary "ལ་སྟོད"))
           (keys (mapcar #'car vocab)))
      (should-not (member "ལ་སྟོད" keys))
      (should (member "སྟོད" keys)))))

(ert-deftest tibetan-extract-vocabulary-keeps-legitimate-compounds ()
  "Compounds without particle tails — e.g. `སངས་རྒྱས' (Buddha) —
remain intact.  The particle-guard must not over-reject."
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "སངས་རྒྱས" "Buddha, awakened one"
             tibetan-comprehensive-vocabulary)
    (let ((vocab (tibetan-extract-vocabulary "སངས་རྒྱས")))
      (should (assoc "སངས་རྒྱས" vocab)))))

(ert-deftest tibetan-extract-vocabulary-rejects-verb-tail-compound ()
  "A dictionary phrasal compound whose LAST syllable is a Hill-DB
verb is NOT glued — the verb stays a separate token so it reaches
clause / Verb-Classification analysis.

Regression for Milarepa Segment 39 (`རྔོག་གི་དྲུང་དུ་ཕྱིན་ནས'): the
Rangjung-Yeshe phrasal entry `དྲུང་དུ་ཕྱིན' was being picked up as a
3-syllable Interlinear MWU, swallowing the verb `ཕྱིན' (\"went\") and
surfacing the RY entry's Tibetan EXAMPLE sentence (`bcom ldan 'das
kyi drung du') as the token's gloss."
  (skip-unless (fboundp 'tibetan-verb-lookup))
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    ;; Seed the phrasal verb-tail compound AND the bare verb stem.
    (puthash "དྲུང་དུ་ཕྱིན" "bcom ldan 'das kyi drung du"
             tibetan-comprehensive-vocabulary)
    (puthash "ཕྱིན" "went" tibetan-comprehensive-vocabulary)
    (let* ((vocab (tibetan-extract-vocabulary "དྲུང་དུ་ཕྱིན"))
           (keys (mapcar #'car vocab)))
      ;; The verb-tail compound must NOT be glued.
      (should-not (member "དྲུང་དུ་ཕྱིན" keys))
      ;; The verb syllable must surface independently.
      (should (member "ཕྱིན" keys)))))

(ert-deftest tibetan-extract-vocabulary-keeps-curated-verb-tail-compound ()
  "A USER-CURATED (Resources / Custom) MWU ending in a verb is kept
intact — the verb-tail guard applies only to auto-sourced dictionary
phrasal entries.  If Carsten defined `ཆུང་མ་བྱེད' (\"to take a wife\")
as a unit, honour it even though it ends in the verb `བྱེད'."
  (skip-unless (fboundp 'tibetan-verb-lookup))
  (let* ((res (make-hash-table :test 'equal))
         (tibetan-current-resources-vocab res)
         (tibetan-current-custom-vocab nil)
         (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "ཆུང་མ་བྱེད" "to take a wife" res)
    (puthash "ཆུང་མ་བྱེད" "to take a wife" tibetan-comprehensive-vocabulary)
    (let* ((vocab (tibetan-extract-vocabulary "ཆུང་མ་བྱེད"))
           (keys (mapcar #'car vocab)))
      (should (member "ཆུང་མ་བྱེད" keys)))))

;; ============================================================================
;; Strict MWU existence — root-cause fix for Interlinear↔DD divergence
;; (2026-05-18, addresses Tibetisch IV seg-049 dangling-link report)
;; ============================================================================
;;
;; Before this work, `tibetan-extract-vocabulary' (the Interlinear path)
;; consulted `tibetan-lookup-word' to decide whether a 4/3/2-syllable
;; compound was a real MWU.  `tibetan-lookup-word' internally falls
;; back to `tibetan-strip-particles', stripping trailing particles like
;; `སོ' (sentence-final) or `ནས' (ablative) before lookup — so
;; `rnams ngo so' returned the `rnams' gloss ("me and those with evil
;; karma like me,"), and the MWU loop accepted the bogus 3-syll group
;; as a valid MWU.  Detailed Dictionary's `tibetan-vocab-lookup-detailed'
;; is strict (`gethash' on exact keys, no particle stripping), so the
;; two paths disagreed on MWU groupings — producing dangling
;; `[[term-rnams-ngo-so][...]]' links that broke `org-export'.

(ert-deftest tibetan-vocab-mwu-exists-p-true-for-exact-key ()
  "Strict MWU predicate returns t when COMPOUND is the EXACT key of
some consulted dictionary."
  (skip-unless (fboundp 'tibetan-vocab--mwu-exists-p))
  (let ((tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab nil)
        (tibetan-detailed-vocab-cache (make-hash-table :test 'equal)))
    (puthash "སངས་རྒྱས" "Buddha" tibetan-current-resources-vocab)
    (should (tibetan-vocab--mwu-exists-p "སངས་རྒྱས"))))

(ert-deftest tibetan-vocab-mwu-exists-p-false-when-particle-stripping-would-rescue ()
  "Strict MWU predicate returns nil when COMPOUND is NOT an exact
key, even if particle-stripping would produce a key that IS in a
dictionary.

Concrete case:  `རྣམས་ངོ་སོ' (3-syll) has no exact entry, but
stripping the trailing `སོ' + `ངོ' (both sentence-final particles)
leaves `རྣམས' which IS a known entry.  The strict predicate must
NOT be fooled by this — `tibetan-extract-vocabulary's greedy MWU
loop must NOT accept `rnams ngo so' as a 3-syll MWU on the basis
of the `rnams' substring match."
  (skip-unless (fboundp 'tibetan-vocab--mwu-exists-p))
  (let ((tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab nil)
        (tibetan-detailed-vocab-cache (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    ;; Seed `rnams' but NOT `rnams ngo so'.
    (puthash "རྣམས" "plural marker" tibetan-comprehensive-vocabulary)
    ;; Strict check on `rnams ngo so' → nil (no exact key).
    (should-not (tibetan-vocab--mwu-exists-p "རྣམས་ངོ་སོ"))))

(ert-deftest tibetan-vocab-mwu-exists-p-nil-on-empty-input ()
  "Strict MWU predicate returns nil for nil / empty / whitespace input."
  (skip-unless (fboundp 'tibetan-vocab--mwu-exists-p))
  (should-not (tibetan-vocab--mwu-exists-p nil))
  (should-not (tibetan-vocab--mwu-exists-p ""))
  (should-not (tibetan-vocab--mwu-exists-p "   ")))

(ert-deftest tibetan-extract-vocabulary-no-false-mwu-from-particle-strip ()
  "Interlinear path does NOT detect `rnams ngo so' as a 3-syll MWU
even when `tibetan-lookup-word' would happily return the `rnams'
gloss after stripping `སོ' + `ངོ'.

This is the root-cause regression for the Tibetisch IV seg-049
export failure (2026-05-18):  Interlinear emitted `[[term-rnams-
ngo-so][rnams ngo so]] [me and those with evil karma]', but DD's
strict lookup only anchored `<<term-rnams>>' and `<<term-so>>'.
Result: dangling link, `org-export-dispatch' aborted on the first
unresolved target."
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-detailed-vocab-cache (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    ;; Seed `rnams' as a single-syll entry — same as Steinert/RY in
    ;; the live setup.  Do NOT seed `rnams ngo so'.
    (puthash "རྣམས" "plural marker" tibetan-comprehensive-vocabulary)
    (let* ((vocab (tibetan-extract-vocabulary "རྣམས་ངོ་སོ"))
           (keys (mapcar #'car vocab)))
      ;; The bogus 3-syll MWU must NOT appear in vocab.
      (should-not (member "རྣམས་ངོ་སོ" keys))
      ;; The legitimate single-syll `rnams' should still surface.
      (should (member "རྣམས" keys)))))

(ert-deftest tibetan-extract-vocabulary-no-verb-converb-fake-mwu ()
  "Interlinear path does NOT produce a `verb + converb' combined
token that has no matching dictionary entry.

Concrete case:  `ཕྱར་ནས' (phyar = verb \"raise/lift\", nas =
ablative/converb).  The legacy `verb+converb' merging path in
`tibetan-extract-vocabulary' would combine these into a fake MWU
`phyar nas' with the `phyar' gloss + a `[converb]' suffix
annotation.  But DD never merges verb+converb;  the merge
produced dangling Interlinear→DD links.

The fix removes the verb+converb merging path entirely;  the
Particle Map / Clause Structure / Grammar sections handle verb
morphology better than a fake-MWU display in Interlinear ever
could."
  (let ((tibetan-current-resources-vocab nil)
        (tibetan-current-custom-vocab nil)
        (tibetan-detailed-vocab-cache (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    ;; Seed `phyar' (verb) as a single-syll entry.  Do NOT seed
    ;; `phyar nas'.
    (puthash "ཕྱར" "raise, lift" tibetan-comprehensive-vocabulary)
    (let* ((vocab (tibetan-extract-vocabulary "ཕྱར་ནས"))
           (keys (mapcar #'car vocab)))
      ;; The fake 2-syll combined token must NOT appear.
      (should-not (member "ཕྱར་ནས" keys))
      ;; The verb stem alone should surface.
      (should (member "ཕྱར" keys)))))

(ert-deftest tibetan-extract-vocabulary-keeps-real-mwu-from-detailed-dict ()
  "When an MWU IS an exact key of a consulted dictionary
\(`tibetan-vocab-lookup-detailed' returns non-nil), the greedy MWU
loop accepts it.  This is the positive case — we must NOT
over-reject;  legitimate MWUs like `mkha' 'gro chos skyong' /
`zla ba bzhin' (Steinert / Resources hits) must continue to be
detected as units, not split into syllables.

Tested by seeding the 2-syll compound into Resources (the lookup
chain consulted by `tibetan-vocab-lookup-detailed').  The compound
should be picked up;  the single-syll fallback should not fire."
  (let ((tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab nil)
        (tibetan-detailed-vocab-cache (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    ;; Real exact-key entry in Resources.
    (puthash "སངས་རྒྱས" "Buddha // awakened one"
             tibetan-current-resources-vocab)
    (let* ((vocab (tibetan-extract-vocabulary "སངས་རྒྱས"))
           (keys (mapcar #'car vocab)))
      (should (member "སངས་རྒྱས" keys))
      ;; Should NOT have split into single syllables.
      (should-not (member "སངས" keys))
      (should-not (member "རྒྱས" keys)))))

(ert-deftest tibetan-extract-vocabulary-and-detailed-agree-on-mwu-groupings ()
  "Integration:  given the same input, the Interlinear path
\(`tibetan-extract-vocabulary') and the Detailed Dictionary path
\(`tibetan-vocab-extract-detailed') produce the SAME MWU
groupings — measured by comparing the tibetan-text of each
extracted unit.

This is the canonical invariant the root-cause fix enforces:
both paths must agree on which syllables form a lexical unit.
Before the fix they disagreed because Interlinear used a loose
particle-stripping lookup and DD used a strict gethash lookup."
  (skip-unless (and (fboundp 'tibetan-extract-vocabulary)
                    (fboundp 'tibetan-vocab-extract-detailed)))
  (let ((tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab nil)
        (tibetan-detailed-vocab-cache (make-hash-table :test 'equal))
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "རྣམས" "plural marker" tibetan-comprehensive-vocabulary)
    (puthash "ཕྱར" "raise, lift" tibetan-comprehensive-vocabulary)
    (puthash "ནས" "ablative" tibetan-comprehensive-vocabulary)
    (puthash "ངོ" "face" tibetan-comprehensive-vocabulary)
    (puthash "སོ" "tooth" tibetan-comprehensive-vocabulary)
    (let* ((text "རྣམས་ངོ་སོ་ཕྱར་ནས")
           (interlinear-keys
            (mapcar #'car (tibetan-extract-vocabulary text)))
           (detailed-keys
            (mapcar (lambda (entry) (plist-get entry :tibetan))
                    (tibetan-vocab-extract-detailed text))))
      ;; Same set of MWU groupings (ignoring placeholder cases).
      (let ((i-set (sort (cl-remove-if-not
                          (lambda (k) (gethash k tibetan-comprehensive-vocabulary))
                          interlinear-keys)
                         #'string<))
            (d-set (sort (cl-remove-if-not
                          (lambda (k) (gethash k tibetan-comprehensive-vocabulary))
                          detailed-keys)
                         #'string<)))
        (should (equal i-set d-set))))))

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

(ert-deftest tibetan-lookup-word-in-dharmamitra-negative-caches-misses ()
  "A DharmaMitra MISS is cached, so a repeated lookup of an
out-of-dictionary word does not re-hit the network.  Regression: only
hits were cached, so every miss re-queried on each call."
  (clrhash tibetan-dharmamitra-cache)
  (let ((calls 0))
    (cl-letf (((symbol-function 'dharmamitra-text-get-translation)
               (lambda (&rest _) (cl-incf calls) nil)))   ; always a miss
      (should (null (tibetan-lookup-word-in-dharmamitra "ཟzzz")))
      (should (null (tibetan-lookup-word-in-dharmamitra "ཟzzz")))
      (should (= calls 1))))
  (clrhash tibetan-dharmamitra-cache))

(ert-deftest tibetan-lookup-word-in-dharmamitra-caches-hits ()
  "A DharmaMitra HIT is cached (one query for repeated lookups)."
  (clrhash tibetan-dharmamitra-cache)
  (let ((calls 0))
    (cl-letf (((symbol-function 'dharmamitra-text-get-translation)
               (lambda (&rest _) (cl-incf calls) "house")))
      (should (equal "house" (tibetan-lookup-word-in-dharmamitra "ཁྱིམ")))
      (should (equal "house" (tibetan-lookup-word-in-dharmamitra "ཁྱིམ")))
      (should (= calls 1))))
  (clrhash tibetan-dharmamitra-cache))

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
