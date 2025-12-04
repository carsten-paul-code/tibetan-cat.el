;;; test-grammatical-analysis.el --- Test grammatical analysis on real segments

;; Load the grammatical analysis modules
(load-file "~/buddhist-studies/translation-tools/tibetan-verb-analyzer.el")
(load-file "~/buddhist-studies/translation-tools/tibetan-particle-analyzer.el")

;; Test segments from Reading_1-bp.org
(defvar test-segments
  '(("001" . "བཅོམ་ལྡན་འདས་ནི་རྒྱུ་མེད་པར་བརྩེ་བའི་བདག་ཉིད་དེ།")
    ("002" . "སེམས་ཅན་མང་པོ་སྐྱོབ་པའི་སླད་དུ།")
    ("003" . "དམ་པའི་ཆོས་འཚོལ་བ་སོགས་ཀྱི་ཕྱིར།")
    ("004" . "རང་གི་སྐུ་སྲོག་ལའང་མ་གཟིགས་ཏེ་དཀའ་བ་དཔག་ཏུ་མེད་པ་བསྒྲུབས་ནས།")
    ("005" . "རྩོད་པའི་དུས་འདིར་མངོན་པར་སངས་རྒྱས་ཏེ།")
    ("006" . "ཆོས་ཀྱི་འཁོར་ལོ་བསྐོར་བར་མཛད་པས་འཇིག་རྟེན་ན།")
    ("007" . "དཀོན་མཆོག་གསུམ་པོ་མངོན་སུམ་དུ་གྱུར་ཏོ།")
    ("008" . "དེའི་ཕྱིར་སངས་རྒྱས་ཀྱི་བཀའ་དྲིན་རྗེས་སུ་འཚོབ་པ་དང་།")
    ("009" . "དམ་པའི་ཆོས་རྙེད་པར་དཀའ་བའི་ཚུལ་ལ་ལེགས་པར་བསམས་ནས་གུས་པས་ཉན་ཅིང་ནན་ཏན་གྱིས་སྒྲུབ་པ།")
    ("010" . "ལྷུར་ལེན་པར་བྱའོ།"))
  "Test segments extracted from Reading_1-bp.org")

(message "\n")
(message "╔══════════════════════════════════════════════════════════════╗")
(message "║    GRAMMATICAL ANALYSIS TEST - CLASSICAL TIBETAN VERBS       ║")
(message "╚══════════════════════════════════════════════════════════════╝")
(message "\n")

;; Load databases
(load-tibetan-verbs)
(load-tibetan-particles)

(message "\n═══════════════════════════════════════════════════════════════")
(message "VERB IDENTIFICATION TEST")
(message "═══════════════════════════════════════════════════════════════\n")

(let ((total-segments 0)
      (segments-with-verbs 0)
      (total-verbs-found 0))

  (dolist (seg-pair test-segments)
    (let* ((seg-num (car seg-pair))
           (segment (cdr seg-pair))
           (verbs (tibetan-identify-verbs-in-segment segment)))

      (setq total-segments (1+ total-segments))
      (when verbs
        (setq segments-with-verbs (1+ segments-with-verbs))
        (setq total-verbs-found (+ total-verbs-found (length verbs))))

      (message "Segment %s: %s" seg-num segment)
      (if verbs
          (progn
            (message "  ✓ Found %d verb(s):" (length verbs))
            (dolist (verb-pair verbs)
              (let* ((word (car verb-pair))
                     (props (cdr verb-pair))
                     (transitivity (plist-get props :transitivity))
                     (controllability (plist-get props :controllability))
                     (english (plist-get props :english)))
                (message "    • %s - %s [%s, %s]"
                        word english transitivity controllability))))
        (message "  ✗ No verbs found"))
      (message "")))

  (message "───────────────────────────────────────────────────────────────")
  (message "STATISTICS:")
  (message "  Segments analyzed: %d" total-segments)
  (message "  Segments with verbs: %d (%.1f%%)"
          segments-with-verbs
          (* 100.0 (/ (float segments-with-verbs) total-segments)))
  (message "  Total verbs found: %d" total-verbs-found)
  (message "  Average verbs per segment: %.1f"
          (/ (float total-verbs-found) total-segments))
  (message "═══════════════════════════════════════════════════════════════\n"))

(message "\n═══════════════════════════════════════════════════════════════")
(message "PARTICLE IDENTIFICATION TEST")
(message "═══════════════════════════════════════════════════════════════\n")

(let ((total-particles-found 0))

  (dolist (seg-pair test-segments)
    (let* ((seg-num (car seg-pair))
           (segment (cdr seg-pair))
           (particles (tibetan-identify-particles-in-segment segment)))

      (when particles
        (setq total-particles-found (+ total-particles-found (length particles))))

      (message "Segment %s: %s" seg-num segment)
      (if particles
          (progn
            (message "  ✓ Found %d particle(s):" (length particles))
            (dolist (particle-triple particles)
              (let* ((full-word (nth 0 particle-triple))
                     (stem (nth 1 particle-triple))
                     (particle (nth 2 particle-triple))
                     (props (lookup-tibetan-particle particle))
                     (function (when props (plist-get props :primary-function))))
                (message "    • %s = [%s] + [%s] → %s"
                        full-word stem particle (or function "unknown")))))
        (message "  ✗ No particles found"))
      (message "")))

  (message "───────────────────────────────────────────────────────────────")
  (message "STATISTICS:")
  (message "  Total particles found: %d" total-particles-found)
  (message "═══════════════════════════════════════════════════════════════\n"))

(message "\n═══════════════════════════════════════════════════════════════")
(message "DETAILED ANALYSIS - Segment 004 (Complex example)")
(message "═══════════════════════════════════════════════════════════════\n")

(let* ((segment "རང་གི་སྐུ་སྲོག་ལའང་མ་གཟིགས་ཏེ་དཀའ་བ་དཔག་ཏུ་མེད་པ་བསྒྲུབས་ནས།")
       (verbs (tibetan-identify-verbs-in-segment segment))
       (particles (tibetan-identify-particles-in-segment segment)))

  (message "Segment: %s\n" segment)

  (message "VERB ANALYSIS:")
  (if verbs
      (dolist (verb-pair verbs)
        (let ((word (car verb-pair)))
          (message "\n%s" (tibetan-analyze-verb-detailed word))))
    (message "No verbs found"))

  (message "\n\nPARTICLE ANALYSIS:")
  (if particles
      (dolist (particle-triple particles)
        (let ((particle (nth 2 particle-triple)))
          (message "\n%s" (tibetan-analyze-particle-detailed particle))))
    (message "No particles found"))

  (message "\n\nGRAMMATICAL STRUCTURE:")
  (message "  • གི = genitive (possessive)")
  (message "  • ལ = terminative (goal/direction)")
  (message "  • འང = even/also (emphasis)")
  (message "  • མ = negation (not)")
  (message "  • ཏེ = converb (sequential/simultaneous)")
  (message "    → Clause continues, NOT sentence-final!")
  (message "  • ཏུ = terminative/manner")
  (message "  • པ = nominalizer")
  (message "  • བསྒྲུབས་ནས = past verb + sequential converb")
  (message "    → 'having accomplished'")
  (message "\nTRANSLATION STRUCTURE:")
  (message "  'Not even caring for [his] own body and life,")
  (message "   having accomplished immeasurable difficulties...'"))

(message "\n\n═══════════════════════════════════════════════════════════════")
(message "TEST COMPLETE")
(message "═══════════════════════════════════════════════════════════════\n")

(message "✓ Verb database: %d entries loaded" (hash-table-count tibetan-verb-database))
(message "✓ Particle database: %d entries loaded" (hash-table-count tibetan-particle-database))
(message "\nThe grammatical analysis system is ready for use!")
(message "Try: M-x tibetan-grammatical-analysis")
