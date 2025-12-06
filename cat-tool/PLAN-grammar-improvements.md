# CAT Tool Grammar Improvements Plan

Based on Tibetan III class analysis (01.12.2025 and 04.12.2025)

**User decisions:**
1. Split terminative from dative ✓
2. Complex absolutive detection (product-quality) ✓
3. Verb classification already available via Hill lexicon ✓

## Existing Infrastructure

**Hill Lexicon Verb Classifier** (`~/.emacs.d/tibetan-verb-classifier.el`):
- 1,662 verbs, 6,018 stems in SQLite database
- **Volitionality**: Voluntary / Involuntary / Both
- **Transitivity**: Transitive / Intransitive / Ambitransitive
- **Case frame**: Erg-Abs, Abs-Dat, Abs, etc.
- **Indigenous class**: ཐ་དད་པ་ (transitive) / ཐ་མི་དད་པ་ (intransitive)

This gives us everything needed for absolutive detection!

## Key Findings from Class

### 1. ABSOLUTIVE (ABS) - Currently Missing!

The CAT tool does NOT currently detect the **absolutive case** (zero marker / unmarked).

**The absolutive marks:**
- Subject of verbs of movement and staying (intransitive controllable)
  - `ston pa (ABS) mnyan yod na bzhugs pa'i tshe`
- Direct object of transitive verbs
  - `bka' drin (ABS) dran pas`
- Subject of intransitive uncontrollable verbs
  - `rab tu dga'ba (ABS) skyes te`
- Subject of existential copulas
  - `bu gnyis shig (ABS) yod de`
- Focus/topicalization
  - `gleng gzhi (ABS) ston pa...`

### 2. TERMINATIVE (TER) - Split from Dative

**Examples:**
- Location: `grong khyer der (TER)` - "in that town"
- Adverbial: `rtag tu (TER)` - "always, constantly"
- Direction: `gsod pa'i gnas su (TERM)` - "to the place of execution"

**Dative (DAT)** now only for:
- Possessive function (+ yod): `rgan mo zhig la (DAT) bu gnyis shig yod de`
- Object of certain verbs: `khrims la (DAT) sbyar bas`
- Recipient/addressee: `kun dga 'bo la (DAT) bha stsal te`

### 3. ELATIVE (ELA) vs ABLATIVE (ABL)

**Elative**: Spatial origin - `rgyang ring mo nas (ELA)` "coming from afar"
**Ablative-temporal**: After V-ing - `zin nas` "after catching" (converb use)

Detection: Use verb classifier to determine if root is a verb stem.

## Implementation Plan

### Phase 1: Integrate Verb Classifier into CAT Grammar

**File**: `cat-tool/core/cat-grammar.el`

Add dependency on verb classifier:
```elisp
(require 'tibetan-verb-classifier nil t)

(defvar cat-grammar-verb-classifier-available
  (featurep 'tibetan-verb-classifier)
  "Non-nil if verb classifier is available.")
```

New function to classify verb:
```elisp
(defun cat-grammar-get-verb-info (word)
  "Get verb classification for WORD from Hill lexicon.
Returns plist with :transitivity :volitionality :case-frame or nil."
  (when cat-grammar-verb-classifier-available
    (tibetan-verb-classify word)))
```

### Phase 2: Absolutive Detection

**Strategy**: Analyze sentence structure using verb classification

```elisp
(cl-defstruct cat-absolutive
  "Structure for detected absolutive arguments."
  word          ; The unmarked word
  role          ; 'subject-intransitive, 'object-transitive, 'existential-subject, 'focus
  verb          ; The related verb (if identified)
  verb-info     ; Verb classification from Hill lexicon
  confidence)   ; 'high, 'medium, 'low

(defun cat-grammar-detect-absolutives (words)
  "Detect absolutive (unmarked) arguments in WORDS list.
Returns list of cat-absolutive structs."
  (let ((results '())
        (verbs '())
        (copulas '("ཡོད" "ཡིན" "འདུག" "རེད" "བཞུགས")))

    ;; First pass: identify all verbs
    (dolist (word words)
      (when-let ((verb-info (cat-grammar-get-verb-info word)))
        (push (cons word verb-info) verbs)))

    ;; Second pass: identify absolutive arguments
    (let ((i 0))
      (dolist (word words)
        (unless (cat-grammar-has-case-marker-p word)
          ;; Check context
          (let ((role (cat-grammar-determine-absolutive-role
                       word i words verbs copulas)))
            (when role
              (push (make-cat-absolutive
                     :word word
                     :role (car role)
                     :verb (cadr role)
                     :verb-info (caddr role)
                     :confidence (cadddr role))
                    results))))
        (cl-incf i)))
    (nreverse results)))

(defun cat-grammar-has-case-marker-p (word)
  "Check if WORD has any overt case marker."
  (or (cat-grammar-detect-particle word)
      (cat-grammar-detect-standalone-particle word)))

(defun cat-grammar-determine-absolutive-role (word index words verbs copulas)
  "Determine the absolutive role of unmarked WORD.
Returns (role verb verb-info confidence) or nil."
  (let ((next-words (nthcdr (1+ index) words)))
    (cond
     ;; Before existential copula → existential subject
     ((cl-some (lambda (w) (member w copulas)) next-words)
      (list 'existential-subject nil nil 'high))

     ;; Before intransitive verb → subject
     ((cl-some (lambda (v)
                 (and (member (car v) next-words)
                      (string= (plist-get (cdr v) :transitivity) "Intransitive")))
               verbs)
      (let ((v (cl-find-if (lambda (v)
                            (and (member (car v) next-words)
                                 (string= (plist-get (cdr v) :transitivity) "Intransitive")))
                          verbs)))
        (list 'subject-intransitive (car v) (cdr v) 'high)))

     ;; Before transitive verb (and ergative subject exists) → object
     ((cl-some (lambda (v)
                 (and (member (car v) next-words)
                      (string= (plist-get (cdr v) :transitivity) "Transitive")))
               verbs)
      (let ((v (cl-find-if (lambda (v)
                            (and (member (car v) next-words)
                                 (string= (plist-get (cdr v) :transitivity) "Transitive")))
                          verbs)))
        ;; Check if there's an ergative-marked word
        (if (cl-some (lambda (w)
                       (when-let ((p (cat-grammar-detect-particle w)))
                         (eq (cat-particle-type p) 'ergative)))
                     words)
            (list 'object-transitive (car v) (cdr v) 'high)
          (list 'object-transitive (car v) (cdr v) 'medium))))

     ;; Sentence-initial position → possible focus/topic
     ((= index 0)
      (list 'focus nil nil 'low))

     (t nil))))
```

### Phase 3: Split Terminative from Dative

**Update particle definitions:**

```elisp
(defconst cat-grammar-particle-info
  '(;; ... existing ...

    (dative
     :particles ("ལ")
     :type-name "DATIVE (DAT)"
     :function "Marks recipient, possessor (with yod), or object of certain verbs"
     :translation "to %s; for %s"
     :reference "Dative for indirect objects and possession")

    (terminative
     :particles ("དུ" "ཏུ" "སུ" "རུ" "ར")
     :type-name "TERMINATIVE (TER)"
     :function "Marks direction, location, or adverbial function"
     :translation "to/in %s; %s-ward"
     :reference "Terminative for direction and location")

    ;; ... rest ...
  ))
```

**Context-aware detection for ལ:**
```elisp
(defun cat-grammar-is-dative-possessive-p (word words)
  "Check if ལ in WORD is possessive dative (followed by yod/existential)."
  (let ((pos (cl-position word words :test 'equal)))
    (when pos
      (let ((following (nthcdr (1+ pos) words)))
        (cl-some (lambda (w) (member w '("ཡོད" "འདུག" "ཡོད་པ" "མེད")))
                 following)))))
```

### Phase 4: Elative vs Ablative-Temporal

```elisp
(defun cat-grammar-classify-nas-particle (word)
  "Classify ནས particle as elative (spatial) or ablative-temporal (converb).
Returns 'elative or 'ablative-temporal."
  (let ((root (cat-safe-substring word 0 (- (length word) 2)))) ; strip ནས
    (if (and cat-grammar-verb-classifier-available
             (tibetan-verb-lookup root))
        'ablative-temporal  ; Root is a verb → converb use
      'elative)))           ; Root is not a verb → spatial origin
```

### Phase 5: Display Updates

**File**: `cat-tool/display/cat-display.el`

Add absolutive display section:
```elisp
(defun cat-display-insert-absolutives (absolutives)
  "Insert formatted absolutive analysis."
  (when absolutives
    (cat-insert-header "Absolutive Arguments (Zero Marking)")
    (dolist (abs absolutives)
      (insert (format "  %s\n" (cat-absolutive-word abs)))
      (insert (format "    ROLE: %s\n"
                      (cat-display-absolutive-role-name (cat-absolutive-role abs))))
      (when (cat-absolutive-verb abs)
        (insert (format "    VERB: %s (%s, %s)\n"
                        (cat-absolutive-verb abs)
                        (plist-get (cat-absolutive-verb-info abs) :transitivity)
                        (plist-get (cat-absolutive-verb-info abs) :volitionality))))
      (insert (format "    CONFIDENCE: %s\n\n" (cat-absolutive-confidence abs))))))

(defun cat-display-absolutive-role-name (role)
  "Get display name for absolutive ROLE."
  (pcase role
    ('subject-intransitive "Subject of intransitive verb (S)")
    ('object-transitive "Direct object of transitive verb (O)")
    ('existential-subject "Subject of existential copula")
    ('focus "Focus/Topic (sentence-initial)")
    (_ "Unmarked argument")))
```

## Files to Modify

1. **`cat-tool/core/cat-grammar.el`**
   - Add verb classifier integration
   - Add absolutive detection logic
   - Split terminative from dative
   - Add elative/ablative distinction

2. **`cat-tool/display/cat-display.el`**
   - Add absolutive display section
   - Update particle display for new types

3. **`cat-tool/core/cat-parser.el`**
   - Enhance to pass word list to grammar analysis
   - Track sentence structure for absolutive detection

4. **`cat-tool/test/test-cat-grammar.el`**
   - Add tests for absolutive detection
   - Add tests for terminative vs dative
   - Add tests for elative vs ablative

## Testing Plan

Based on class examples:

```elisp
;; Absolutive - existential subject
(ert-deftest test-cat-grammar-absolutive-existential ()
  "Test: bu gnyis shig (ABS) yod de"
  (let ((result (cat-grammar-detect-absolutives
                 '("བུ" "གཉིས" "ཤིག" "ཡོད" "དེ"))))
    (should (= (length result) 1))
    (should (eq (cat-absolutive-role (car result)) 'existential-subject))))

;; Absolutive - object of transitive verb
(ert-deftest test-cat-grammar-absolutive-object ()
  "Test: bka' drin (ABS) dran pas - with ergative agent"
  (let ((result (cat-grammar-detect-absolutives
                 '("དེ" "གཉིས" "བཀའ" "དྲིན" "དྲན" "པས"))))
    ;; བཀའ་དྲིན should be detected as object
    ...))

;; Terminative - location
(ert-deftest test-cat-grammar-terminative-location ()
  "Test: grong khyer der (TER)"
  (let ((p (cat-grammar-detect-particle "གྲོང་ཁྱེར་དེར")))
    (should (eq (cat-particle-type p) 'terminative))))

;; Elative vs Ablative
(ert-deftest test-cat-grammar-elative-spatial ()
  "Test: rgyang ring mo nas (ELA) - spatial origin"
  (should (eq (cat-grammar-classify-nas-particle "རྒྱང་རིང་མོ་ནས") 'elative)))

(ert-deftest test-cat-grammar-ablative-temporal ()
  "Test: zin nas - after catching (converb)"
  (should (eq (cat-grammar-classify-nas-particle "ཟིན་ནས") 'ablative-temporal)))
```

## Priority Order

1. **Phase 1**: Integrate verb classifier (foundation for everything else)
2. **Phase 2**: Absolutive detection (most significant new feature)
3. **Phase 3**: Split terminative from dative
4. **Phase 4**: Elative vs ablative distinction
5. **Phase 5**: Display updates

## Estimated Scope

- **cat-grammar.el**: ~150 lines new code
- **cat-display.el**: ~50 lines new code
- **cat-parser.el**: ~30 lines modifications
- **test-cat-grammar.el**: ~80 lines new tests

Total: ~310 lines of new/modified code
