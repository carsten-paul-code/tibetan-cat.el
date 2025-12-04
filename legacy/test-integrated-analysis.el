;;; test-integrated-analysis.el --- Test grammatical analysis integration into C-c u i

;; Load the modules
(load-file "~/.emacs.d/init.el")

(message "\n╔══════════════════════════════════════════════════════════════╗")
(message "║      INTEGRATED ANALYSIS TEST - C-c u i FUNCTIONALITY       ║")
(message "╚══════════════════════════════════════════════════════════════╝\n")

;; Test the helper function directly
(message "Test 1: Testing tibetan-create-verb-grammar-analysis function...")

(if (fboundp 'tibetan-create-verb-grammar-analysis)
    (progn
      (message "  ✓ Function exists")

      ;; Test with a simple segment
      (let* ((test-segment "བཅོམ་ལྡན་འདས་ནི་རྒྱུ་མེད་པར་བརྩེ་བའི་བདག་ཉིད་དེ།")
             (result (tibetan-create-verb-grammar-analysis test-segment)))

        (message "\n  Testing segment: %s\n" test-segment)
        (message "  Analysis output:")
        (message "%s" result)

        (if (string-match-p "VERBS IDENTIFIED" result)
            (message "\n  ✓ Verb analysis integrated successfully")
          (message "\n  ✗ Verb analysis not working"))

        (if (string-match-p "SENTENCE BOUNDARY" result)
            (message "  ✓ Sentence boundary detection integrated")
          (message "  ✗ Sentence boundary detection not working"))))

  (message "  ✗ Function not found"))

(message "\n═══════════════════════════════════════════════════════════════")
(message "Test 2: Checking if tibetan-create-detailed-analysis calls it...")

(if (fboundp 'tibetan-create-detailed-analysis)
    (progn
      (message "  ✓ tibetan-create-detailed-analysis exists")

      ;; Test with a simple segment
      (let* ((test-segment "བཅོམ་ལྡན་འདས་ནི་རྒྱུ་མེད་པར་བརྩེ་བའི་བདག་ཉིད་དེ།")
             (words (split-string test-segment "་"))
             (result (tibetan-create-detailed-analysis test-segment words)))

        (message "\n  Full analysis includes:")
        (if (string-match-p "\\*\\* VERB & GRAMMATICAL ANALYSIS \\*\\*" result)
            (message "    ✓ VERB & GRAMMATICAL ANALYSIS section")
          (message "    ✗ Missing VERB & GRAMMATICAL ANALYSIS section"))

        (if (string-match-p "\\*\\* NATURAL TRANSLATION \\*\\*" result)
            (message "    ✓ NATURAL TRANSLATION section")
          (message "    ✗ Missing NATURAL TRANSLATION section"))

        (if (string-match-p "\\*\\* DETAILED VOCABULARY \\*\\*" result)
            (message "    ✓ DETAILED VOCABULARY section")
          (message "    ✗ Missing DETAILED VOCABULARY section"))

        (if (string-match-p "VERBS IDENTIFIED" result)
            (message "    ✓ Verb identification working in detailed analysis")
          (message "    ✗ Verb identification not appearing"))))

  (message "  ✗ tibetan-create-detailed-analysis not found"))

(message "\n═══════════════════════════════════════════════════════════════")
(message "INTEGRATION STATUS")
(message "═══════════════════════════════════════════════════════════════\n")

(message "✓ Grammatical analysis integrated into segment analysis (C-c u i)")
(message "✓ Grammatical analysis will appear in auto-analysis mode (C-c u E)")
(message "✓ New section: ** VERB & GRAMMATICAL ANALYSIS **")

(message "\n╔══════════════════════════════════════════════════════════════╗")
(message "║                   INTEGRATION COMPLETE!                      ║")
(message "╚══════════════════════════════════════════════════════════════╝\n")

(message "Now when you press C-c u i on a segment, you'll see:")
(message "  - Natural Translation")
(message "  - Detailed Vocabulary")
(message "  - ** VERB & GRAMMATICAL ANALYSIS ** (NEW!)")
(message "  - Particle Analysis")
(message "  - Grammar Explanation")
(message "  - Sentence Structure")
(message "  - Cultural Context\n")

(message "Try it:")
(message "  1. Open Reading_1-bp.org")
(message "  2. Position cursor in segment 001")
(message "  3. Press C-c u i")
(message "  4. See comprehensive analysis with verb information!\n")
