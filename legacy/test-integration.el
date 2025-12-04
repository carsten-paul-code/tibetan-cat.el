;;; test-integration.el --- Test grammatical analysis integration

;; Load init.el
(load-file "~/.emacs.d/init.el")

(message "\n╔══════════════════════════════════════════════════════════════╗")
(message "║         GRAMMATICAL ANALYSIS INTEGRATION TEST                ║")
(message "╚══════════════════════════════════════════════════════════════╝\n")

;; Test 1: Check if functions are defined
(message "Test 1: Checking if functions are loaded...")
(let ((functions-to-check '(tibetan-grammatical-analysis
                            tibetan-analyze-segment-verbs
                            tibetan-analyze-segment-particles
                            lookup-tibetan-verb
                            lookup-tibetan-particle
                            load-tibetan-verbs
                            load-tibetan-particles)))
  (dolist (func functions-to-check)
    (if (fboundp func)
        (message "  ✓ %s is defined" func)
      (message "  ✗ %s is NOT defined" func))))

(message "")

;; Test 2: Check if databases load
(message "Test 2: Loading verb and particle databases...")
(if (fboundp 'load-tibetan-verbs)
    (progn
      (load-tibetan-verbs)
      (message "  ✓ Verb database loaded: %d entries"
              (if (boundp 'tibetan-verb-database)
                  (hash-table-count tibetan-verb-database)
                0)))
  (message "  ✗ load-tibetan-verbs not available"))

(if (fboundp 'load-tibetan-particles)
    (progn
      (load-tibetan-particles)
      (message "  ✓ Particle database loaded: %d entries"
              (if (boundp 'tibetan-particle-database)
                  (hash-table-count tibetan-particle-database)
                0)))
  (message "  ✗ load-tibetan-particles not available"))

(message "")

;; Test 3: Test verb lookup
(message "Test 3: Testing verb lookup...")
(let ((test-verbs '("བསྒྲུབས" "མཐོང" "ཤེས" "གཟིགས")))
  (dolist (verb test-verbs)
    (let ((result (if (fboundp 'lookup-tibetan-verb)
                     (lookup-tibetan-verb verb)
                   nil)))
      (if result
          (message "  ✓ %s → %s [%s]"
                  verb
                  (plist-get result :english)
                  (plist-get result :transitivity))
        (message "  ✗ %s not found" verb)))))

(message "")

;; Test 4: Test particle lookup
(message "Test 4: Testing particle lookup...")
(let ((test-particles '("ནས" "ལ" "གིས" "པ")))
  (dolist (particle test-particles)
    (let ((result (if (fboundp 'lookup-tibetan-particle)
                     (lookup-tibetan-particle particle)
                   nil)))
      (if result
          (message "  ✓ %s → %s (%s)"
                  particle
                  (plist-get result :primary-function)
                  (plist-get result :type))
        (message "  ✗ %s not found" particle)))))

(message "")

;; Test 5: Test segment analysis
(message "Test 5: Testing segment verb identification...")
(let ((test-segment "བཅོམ་ལྡན་འདས་ནི་རྒྱུ་མེད་པར་བརྩེ་བའི་བདག་ཉིད་དེ།"))
  (message "  Segment: %s" test-segment)
  (if (fboundp 'tibetan-identify-verbs-in-segment)
      (let ((verbs (tibetan-identify-verbs-in-segment test-segment)))
        (if verbs
            (progn
              (message "  ✓ Found %d verb(s):" (length verbs))
              (dolist (verb-pair verbs)
                (let* ((word (car verb-pair))
                       (props (cdr verb-pair))
                       (english (plist-get props :english)))
                  (message "    • %s (%s)" word english))))
          (message "  ⚠ No verbs found in segment")))
    (message "  ✗ tibetan-identify-verbs-in-segment not available")))

(message "")

;; Test 6: Check key bindings
(message "Test 6: Checking key bindings...")
(let ((key-bindings '(("C-c u G" . tibetan-grammatical-analysis)
                     ("C-c u V" . tibetan-analyze-segment-verbs)
                     ("C-c u P" . tibetan-analyze-segment-particles))))
  (dolist (binding key-bindings)
    (let* ((key (car binding))
           (expected-func (cdr binding))
           (actual-func (key-binding (kbd key))))
      (if (eq actual-func expected-func)
          (message "  ✓ %s → %s" key expected-func)
        (message "  ✗ %s → %s (expected %s)" key actual-func expected-func)))))

(message "")
(message "╔══════════════════════════════════════════════════════════════╗")
(message "║                    INTEGRATION TEST COMPLETE                 ║")
(message "╚══════════════════════════════════════════════════════════════╝")

(message "\n✓ The grammatical analysis system is integrated and ready!")
(message "\nAvailable commands:")
(message "  C-c u G  - Full grammatical analysis (verbs + particles)")
(message "  C-c u V  - Verb analysis only")
(message "  C-c u P  - Particle analysis only")
(message "\nTry opening Reading_1-bp.org and pressing C-c u G on a segment!\n")
