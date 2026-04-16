;;; tibetan-sentence-structure-test.el --- Tests for tibetan-sentence-structure.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for sentence structure detection and manipulation functionality.
;; Tests cover boundary detection, sentence structure addition, and marking.

;;; Code:

(require 'ert)
(require 'org)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../doc-prep" base-dir)))

(require 'tibetan-sentence-structure)

;; ============================================================================
;; SENTENCE BOUNDARY DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-is-sentence-boundary-p-double-shad ()
  "Test detection of double shad as sentence boundary."
  (should (tibetan-is-sentence-boundary-p "བདག་།།"))
  (should (tibetan-is-sentence-boundary-p "བདག་༎")))

(ert-deftest tibetan-is-sentence-boundary-p-with-final-particles ()
  "Test detection of sentence-final particles."
  ;; Words ending in common final particles
  (should (tibetan-is-sentence-boundary-p "བདག་སོ།"))
  (should (tibetan-is-sentence-boundary-p "བདག་ཏོ།"))
  (should (tibetan-is-sentence-boundary-p "བདག་ངོ།")))

(ert-deftest tibetan-is-sentence-boundary-p-converb-particles ()
  "Test that converb particles are not sentence boundaries."
  (skip-unless (fboundp 'tibetan-is-sentence-boundary-p))
  ;; Converbs should return nil (not sentence boundaries)
  (should-not (tibetan-is-sentence-boundary-p "བདག་ནས།"))
  (should-not (tibetan-is-sentence-boundary-p "བདག་སྟེ།"))
  (should-not (tibetan-is-sentence-boundary-p "བདག་ཞིང།")))

(ert-deftest tibetan-is-sentence-boundary-p-bare-single-shad-is-weak ()
  "Bare single shad on a multi-character last syllable yields 'weak.
Single-character last syllables (fused ergative, e.g. ས) stay nil."
  (should (eq 'weak (tibetan-is-sentence-boundary-p "བདག་།")))
  ;; Single-character last syllable: too ambiguous → nil
  (should-not (tibetan-is-sentence-boundary-p "ས།")))

(ert-deftest tibetan-is-sentence-boundary-p-no-shad ()
  "Test that text without shad is not a boundary."
  (should-not (tibetan-is-sentence-boundary-p "བདག")))

(ert-deftest tibetan-is-sentence-boundary-p-nil-input ()
  "Test boundary detection with nil input."
  (should-not (tibetan-is-sentence-boundary-p nil))
  (should-not (tibetan-is-sentence-boundary-p "")))

(ert-deftest tibetan-is-sentence-boundary-p-returns-confidence ()
  "Boundary detection returns nil | 'strong | 'weak."
  (let ((cases '("བདག་།།" "བདག་སོ།" "བདག་།" "བདག་ནས།" "བདག")))
    (dolist (case cases)
      (let ((result (tibetan-is-sentence-boundary-p case)))
        (should (memq result '(nil strong weak)))))))

(ert-deftest tibetan-is-sentence-boundary-p-double-shad-strong ()
  "Double shad yields strong confidence."
  (should (eq 'strong (tibetan-is-sentence-boundary-p "བདག་།།")))
  (should (eq 'strong (tibetan-is-sentence-boundary-p "བདག་༎"))))

(ert-deftest tibetan-is-sentence-boundary-p-final-particle-strong ()
  "Sentence-final particle + shad yields strong confidence."
  (should (eq 'strong (tibetan-is-sentence-boundary-p "བདག་སོ།")))
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཡིན།")))
  (should (eq 'strong (tibetan-is-sentence-boundary-p "མ་མཆིས་སོ།"))))

(ert-deftest tibetan-is-sentence-boundary-p-finite-verb-strong ()
  "Common finite verbs (rnam thar style) yield strong boundary."
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཞེས་ཟེར།")))
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཞེས་གསུངས།")))
  (should (eq 'strong (tibetan-is-sentence-boundary-p "མཛད།"))))

(ert-deftest tibetan-is-sentence-boundary-p-honorific-verbs-strong ()
  "Honorific finite verbs profiled from Milarepa are now strong."
  (should (eq 'strong (tibetan-is-sentence-boundary-p "སར་བྱོན།")))       ; "came"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ལོ་གཅིག་བཞུགས།"))) ; "stayed one year"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "གཅིག་ཀྱང་མ་གནང།"))) ; "did not give even one"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཅི་ཡིན་གསུང།")))   ; "said what it is"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཡབ་གཤེགས།")))     ; "father passed away"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཆོས་ཞུས།")))       ; "requested teachings"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "བགྱིས།"))))

(ert-deftest tibetan-is-sentence-boundary-p-past-verbs-strong ()
  "Past-tense finite verbs profiled from Milarepa are now strong."
  (should (eq 'strong (tibetan-is-sentence-boundary-p "བུ་སྐྱེས།")))       ; "a son was born"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "འོངས།")))            ; "came"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "སོང་།")))            ; "went"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཤི།")))              ; "died"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "བལྟམས།")))          ; "was born"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "བཏགས།")))           ; "named"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཕུག་ཏུ་མཚམས་གཅོད་དུ་བཅུག།"))) ; "caused to do retreat"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཆོས་བསྟན།")))      ; "taught dharma"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ཡི་གེ་བརྫངས།")))  ; "sent a letter"
  (should (eq 'strong (tibetan-is-sentence-boundary-p "ངས་ཤེས།"))))        ; "I knew"

(ert-deftest tibetan-is-sentence-boundary-p-existential-duk-strong ()
  "Sentence-final existential འདུག། yields strong boundary."
  (should (eq 'strong (tibetan-is-sentence-boundary-p "སློབ་པར་འདུག།")))
  (should (eq 'strong (tibetan-is-sentence-boundary-p "འདེབས་མ་ནུས་པར་འདུག།"))))

(ert-deftest tibetan-is-sentence-boundary-p-future-gyur-strong ()
  "Future / transformative འགྱུར། yields strong boundary."
  (should (eq 'strong (tibetan-is-sentence-boundary-p "སྣང་བ་འགྱུར།")))
  (should (eq 'strong (tibetan-is-sentence-boundary-p "བདུན་བཅུ་རྩ་གསུམ་པར་འགྱུར།"))))

(ert-deftest tibetan-is-sentence-boundary-p-topic-marker-not-boundary ()
  "Topic marker ནི། does NOT end a sentence (Milarepa seg:1)."
  (should-not (tibetan-is-sentence-boundary-p "རྣལ་འབྱོར་གྱི་དབང་ཕྱུག་མི་ལ་རས་པ་ནི།")))

(ert-deftest tibetan-is-sentence-boundary-p-case-particle-not-boundary ()
  "Case particle as its own last syllable before shad is NOT a boundary.
Note: fused case suffixes (e.g. ཆེན་པོར།, where `pa-o` + `r` write as one
syllable) are NOT caught here — we leave those as weak for review."
  ;; Locative
  (should-not (tibetan-is-sentence-boundary-p "ཤར་ཕྱོགས་ལ།"))
  ;; Terminative སུ
  (should-not (tibetan-is-sentence-boundary-p "ཡ་ཆད་དུ།"))
  ;; Genitive
  (should-not (tibetan-is-sentence-boundary-p "སློབ་མའི་ཀྱི།"))
  ;; Ergative ending as own syllable
  (should-not (tibetan-is-sentence-boundary-p "ཁོས་གིས།")))

(ert-deftest tibetan-is-sentence-boundary-p-pa-la-not-boundary ()
  "Nominalizer + locative (པ་ལ / པ་ར / པ་ན) marks subordinate clause, not end.
Milarepa seg:4 pattern."
  (should-not (tibetan-is-sentence-boundary-p "ཁྱེ'ུ་ཆུང་བཙས་པ་ལ།"))
  (should-not (tibetan-is-sentence-boundary-p "ཕྱིན་པ་ན།"))
  (should-not (tibetan-is-sentence-boundary-p "འདུག་པར།")))

(ert-deftest tibetan-is-sentence-boundary-p-pas-causal-converb ()
  "པས (causal converb) does NOT end a sentence (Milarepa seg:10)."
  (should-not (tibetan-is-sentence-boundary-p "ཡིན་པས།")))

(ert-deftest tibetan-is-sentence-boundary-p-bas-causal-allomorph ()
  "བས (causal allomorph of པས on non-aspirated stems) does NOT end a sentence.
Profiled from Milarepa: ཟེར་བས། \"because he said\", མཐོང་བས། \"because he saw\"."
  (should-not (tibetan-is-sentence-boundary-p "ཟེར་བས།"))
  (should-not (tibetan-is-sentence-boundary-p "མཐོང་བས།")))

(ert-deftest tibetan-is-sentence-boundary-p-pai-tshe-not-boundary ()
  "Nominalizer + genitive + ཚེ = temporal subordinate clause, not a boundary.
Milarepa: ཡོད་པའི་ཚེ། \"while being\", ཚོགས་བཞེས་པའི་ཚེ། \"when assembled\"."
  (should-not (tibetan-is-sentence-boundary-p "ཡོད་པའི་ཚེ།"))
  (should-not (tibetan-is-sentence-boundary-p "བཞེས་པའི་ཚེ།"))
  (should-not (tibetan-is-sentence-boundary-p "བྱས་པའི་ཚེ།")))

(ert-deftest tibetan-is-sentence-boundary-p-expanded-converbs ()
  "Expanded converb list: ན (conditional), ཀྱང/ཡང (concessive)."
  (should-not (tibetan-is-sentence-boundary-p "སོང་ན།"))
  (should-not (tibetan-is-sentence-boundary-p "ལྟ་ཀྱང།"))
  (should-not (tibetan-is-sentence-boundary-p "དེ་ཡང།")))

(ert-deftest tibetan-is-sentence-boundary-p-unknown-residual-is-weak ()
  "Multi-syllable last word + bare single shad, not matching any closed
list, falls through to weak.  This is the residual class the auto
segmenter leaves for human review.
The specific verbs asserted here (ཚར \"finished\", and a made-up form)
are not in the finite-verb list and should stay weak until profiled."
  (should (eq 'weak (tibetan-is-sentence-boundary-p "ཚར།")))
  ;; Proper name in sentence-final position: staying weak is right —
  ;; syntactically indistinguishable from a mid-sentence title.
  (should (eq 'weak (tibetan-is-sentence-boundary-p "ཐོས་པ་དགའ།"))))

(ert-deftest tibetan-is-sentence-boundary-p-coordinator-dang ()
  "Coordinator དང། does NOT end a sentence."
  (should-not (tibetan-is-sentence-boundary-p "ནོར་རྫས་དང་།"))
  (should-not (tibetan-is-sentence-boundary-p "འབུལ་བ་དང་།")))

(ert-deftest tibetan-is-sentence-boundary-p-zhig-not-boundary ()
  "Indefinite article ཞིག། should not end a sentence (Milarepa seg:3)."
  (should-not (tibetan-is-sentence-boundary-p "བསྟན་པ་ཞིག།")))

;; ============================================================================
;; SENTENCE DETECTION FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-detect-sentence-boundaries-function-exists ()
  "Test that tibetan-detect-sentence-boundaries function exists."
  (should (fboundp 'tibetan-detect-sentence-boundaries)))

(ert-deftest tibetan-detect-sentence-boundaries-interactive ()
  "Test that detect-sentence-boundaries is interactive."
  (skip-unless (fboundp 'tibetan-detect-sentence-boundaries))
  (should (commandp 'tibetan-detect-sentence-boundaries)))

;; ============================================================================
;; ADD SENTENCE STRUCTURE FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-add-sentence-structure-function-exists ()
  "Test that tibetan-add-sentence-structure function exists."
  (should (fboundp 'tibetan-add-sentence-structure)))

(ert-deftest tibetan-add-sentence-structure-interactive ()
  "Test that add-sentence-structure is interactive."
  (skip-unless (fboundp 'tibetan-add-sentence-structure))
  (should (commandp 'tibetan-add-sentence-structure)))

;; ============================================================================
;; MARK SENTENCE START TESTS
;; ============================================================================

(ert-deftest tibetan-mark-sentence-start-function-exists ()
  "Test that tibetan-mark-sentence-start function exists."
  (should (fboundp 'tibetan-mark-sentence-start)))

(ert-deftest tibetan-mark-sentence-start-interactive ()
  "Test that mark-sentence-start is interactive."
  (skip-unless (fboundp 'tibetan-mark-sentence-start))
  (should (commandp 'tibetan-mark-sentence-start)))

;; ============================================================================
;; BOUNDARY EDGE CASES
;; ============================================================================

(ert-deftest tibetan-is-sentence-boundary-p-with-whitespace ()
  "Test boundary detection with extra whitespace."
  ;; Should handle trailing whitespace
  (should (tibetan-is-sentence-boundary-p "བདག་།། "))
  (should (tibetan-is-sentence-boundary-p "  བདག་།།")))

(ert-deftest tibetan-is-sentence-boundary-p-complex-text ()
  "Boundary detection with complex sentences ending in final particle."
  (let ((result (tibetan-is-sentence-boundary-p "བདག་གིས་བྱེད་དོ།")))
    (should (memq result '(nil strong weak)))
    (should (eq result 'strong))))

;; ============================================================================
;; FINAL PARTICLE TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-final-particles-defined ()
  "Test that tibetan-sentence-final-particles is defined."
  (should (boundp 'tibetan-sentence-final-particles))
  (should (listp tibetan-sentence-final-particles))
  (should (> (length tibetan-sentence-final-particles) 0)))

(ert-deftest tibetan-sentence-converb-particles-defined ()
  "Test that tibetan-sentence-converb-particles is defined."
  (should (boundp 'tibetan-sentence-converb-particles))
  (should (listp tibetan-sentence-converb-particles))
  (should (> (length tibetan-sentence-converb-particles) 0)))

(ert-deftest tibetan-sentence-converb-particles-contents ()
  "Diagnostic: each expected converb syllable must be present in the list.
If this test passes but the `should-not` boundary tests on converb-ending
text still fail, the bug is in the extraction layer, not the defvar."
  (dolist (sy '("ནས" "སྟེ" "ཏེ" "དེ" "ཅིང" "ཞིང" "ཤིང"
                "པས" "པར" "ན" "ཀྱང" "ཡང" "དང"))
    (should (member sy tibetan-sentence-converb-particles))))

(ert-deftest tibetan-sentence-converb-particles-no-collision ()
  "The sentence-boundary converb list is the one from sentence-structure.el,
not the flat list from core/tibetan-vocabulary.el nor the alist from
analysis/tibetan-clause-analysis.el.  A regression here means the rename
to `tibetan-sentence-converb-particles' was undone and we've re-collided."
  ;; Must be a flat list of strings (not an alist of (type . (...)))
  (should (cl-every #'stringp tibetan-sentence-converb-particles))
  ;; Must contain the expanded entries my refactor added — these are
  ;; absent from both other definitions.
  (should (member "དང" tibetan-sentence-converb-particles))
  (should (member "པས" tibetan-sentence-converb-particles))
  (should (member "པར" tibetan-sentence-converb-particles))
  (should (member "ན" tibetan-sentence-converb-particles))
  (should (member "ཀྱང" tibetan-sentence-converb-particles))
  (should (member "ཡང" tibetan-sentence-converb-particles)))

(ert-deftest tibetan--last-syllable-on-converb-inputs ()
  "Diagnostic: extraction for each converb-ending test input.
If this test passes and `tibetan-sentence-converb-particles-contents`
passes but the boundary tests still fail, the bug is in the cond chain
ordering."
  (should (equal "ནས" (tibetan--last-syllable "བདག་ནས།")))
  (should (equal "དང" (tibetan--last-syllable "ནོར་རྫས་དང་།")))
  (should (equal "ཀྱང" (tibetan--last-syllable "ལྟ་ཀྱང།")))
  (should (equal "པར" (tibetan--last-syllable "འདུག་པར།")))
  (should (equal "པས" (tibetan--last-syllable "ཡིན་པས།")))
  (should (equal "ནས" (tibetan--last-syllable "འདི་ནི་བོད་ནས།"))))

(ert-deftest tibetan-case-particle-syllables-defined ()
  "Case particle list is available and non-empty."
  (should (boundp 'tibetan-case-particle-syllables))
  (should (listp tibetan-case-particle-syllables))
  (should (member "ལ" tibetan-case-particle-syllables))
  (should (member "ཀྱིས" tibetan-case-particle-syllables)))

(ert-deftest tibetan-topic-particle-syllables-defined ()
  "Topic marker list is available."
  (should (boundp 'tibetan-topic-particle-syllables))
  (should (member "ནི" tibetan-topic-particle-syllables)))

;; ============================================================================
;; SYLLABLE HELPERS
;; ============================================================================

(ert-deftest tibetan--last-syllable-basic ()
  "Extract last tsheg-separated syllable, stripping shad."
  (should (equal "པ" (tibetan--last-syllable "མིད་ལ་རས་པ།")))
  (should (equal "ནི" (tibetan--last-syllable "མི་ལ་རས་པ་ནི།")))
  (should (equal "སོ" (tibetan--last-syllable "བདག་སོ།།"))))

(ert-deftest tibetan--last-syllable-no-shad ()
  "Syllable extraction works without trailing shad."
  (should (equal "པ" (tibetan--last-syllable "མི་ལ་རས་པ")))
  (should (null (tibetan--last-syllable ""))))

(ert-deftest tibetan--last-two-syllables-basic ()
  "Joins last two tsheg-separated syllables with ་."
  (should (equal "པ་ལ" (tibetan--last-two-syllables "བཙས་པ་ལ།")))
  (should (equal "རས་པ" (tibetan--last-two-syllables "མི་ལ་རས་པ།")))
  (should (null (tibetan--last-two-syllables "པ།"))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-structure-end-detection-vs-converb ()
  "Test that sentences ending in particles are distinguished from converbs."
  ;; Sentence-final particle should be detected
  (should (tibetan-is-sentence-boundary-p "འདི་ནི་བོད་སོ།"))
  ;; Converb should not be detected as boundary
  (should-not (tibetan-is-sentence-boundary-p "འདི་ནི་བོད་ནས།"))
  ;; Converb in isolation also not boundary
  (should-not (tibetan-is-sentence-boundary-p "ནས།")))

;; ============================================================================
;; EXTRACT PARTICLE TEXT TESTS
;; ============================================================================

(ert-deftest tibetan-extract-particle-text-string-input ()
  "Test extracting text from string particle."
  (skip-unless (fboundp 'tibetan-extract-particle-text))
  (let ((result (tibetan-extract-particle-text "སོ")))
    (should (listp result))
    (should (= (length result) 1))
    (should (equal (car result) "སོ"))))

(ert-deftest tibetan-extract-particle-text-alist-input ()
  "Test extracting text from alist format particle."
  (skip-unless (fboundp 'tibetan-extract-particle-text))
  (let ((result (tibetan-extract-particle-text '(type . ("སོ" "ཏོ")))))
    (should (listp result))
    (should (> (length result) 0))
    ;; Should extract both particle texts
    (should (member "སོ" result))))

(ert-deftest tibetan-extract-particle-text-nil-input ()
  "Test extracting text with nil input."
  (skip-unless (fboundp 'tibetan-extract-particle-text))
  (let ((result (tibetan-extract-particle-text nil)))
    (should (or (null result) (listp result)))))

(ert-deftest tibetan-extract-particle-text-returns-list ()
  "Test that extract-particle-text returns a list."
  (skip-unless (fboundp 'tibetan-extract-particle-text))
  (let ((result (tibetan-extract-particle-text "ནས")))
    (should (listp result))
    (dolist (item result)
      (should (stringp item)))))

(provide 'tibetan-sentence-structure-test)
;;; tibetan-sentence-structure-test.el ends here
