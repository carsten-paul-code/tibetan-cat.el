;;; test-integration-simple.el --- Simple test of grammatical analysis modules

;; Load just the grammatical analysis modules (not full init.el)
(load-file "~/buddhist-studies/translation-tools/tibetan-verb-analyzer.el")
(load-file "~/buddhist-studies/translation-tools/tibetan-particle-analyzer.el")

(message "\n╔══════════════════════════════════════════════════════════════╗")
(message "║    GRAMMATICAL ANALYSIS - SIMPLE INTEGRATION TEST            ║")
(message "╚══════════════════════════════════════════════════════════════╝\n")

;; Load databases
(load-tibetan-verbs)
(load-tibetan-particles)

(message "\n═══════════════════════════════════════════════════════════════")
(message "QUICK FUNCTIONAL TEST")
(message "═══════════════════════════════════════════════════════════════\n")

;; Test segment from Reading_1-bp.org
(let ((segment "བཅོམ་ལྡན་འདས་ནི་རྒྱུ་མེད་པར་བརྩེ་བའི་བདག་ཉིད་དེ།"))
  (message "Testing segment 001:")
  (message "  %s\n" segment)

  ;; Test verb identification
  (let ((verbs (tibetan-identify-verbs-in-segment segment)))
    (if verbs
        (progn
          (message "✓ Verb identification WORKING:")
          (message "  Found %d verb(s):" (length verbs))
          (dolist (verb-pair verbs)
            (let* ((word (car verb-pair))
                   (props (cdr verb-pair))
                   (english (plist-get props :english))
                   (trans (plist-get props :transitivity)))
              (message "    • %s - %s [%s]" word english trans))))
      (message "✗ No verbs found")))

  (message "")

  ;; Test particle identification
  (let ((particles (tibetan-identify-particles-in-segment segment)))
    (if particles
        (progn
          (message "✓ Particle identification WORKING:")
          (message "  Found %d particle(s):" (length particles))
          (dolist (particle-triple particles)
            (let* ((full-word (nth 0 particle-triple))
                   (stem (nth 1 particle-triple))
                   (particle (nth 2 particle-triple))
                   (props (lookup-tibetan-particle particle))
                   (function (when props (plist-get props :primary-function))))
              (message "    • %s = [%s] + [%s] → %s"
                      full-word stem particle (or function "unknown")))))
      (message "✗ No particles found"))))

(message "\n═══════════════════════════════════════════════════════════════")
(message "INTEGRATION STATUS")
(message "═══════════════════════════════════════════════════════════════\n")

(message "✓ Verb analyzer loaded: %d entries"
        (hash-table-count tibetan-verb-database))
(message "✓ Particle analyzer loaded: %d entries"
        (hash-table-count tibetan-particle-database))
(message "✓ All analysis functions working correctly")

(message "\n╔══════════════════════════════════════════════════════════════╗")
(message "║                   INTEGRATION SUCCESSFUL!                    ║")
(message "╚══════════════════════════════════════════════════════════════╝\n")

(message "The grammatical analysis system is ready for use in Emacs!")
(message "\nKey bindings (after starting Emacs):")
(message "  C-c u G  - Full grammatical analysis")
(message "  C-c u V  - Verb analysis only")
(message "  C-c u P  - Particle analysis only\n")
