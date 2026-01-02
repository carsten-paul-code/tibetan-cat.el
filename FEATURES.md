# Tibetan CAT - Feature Documentation

*This documentation is auto-generated from executable specifications.*
*Last updated: 2025-12-07 13:19*

---

## Verb detection and classification (Hill 2010)

*Suite: `verb-detection`*

### Detect གསུངས (hon. to speak) in direct speech

**Example:** Segment 25: འཕགས་བས...གསུངས།

**Tags:** `:regression` `:critical`

```
GIVEN: (setq test-word "གསུངས")
WHEN:  (tibetan-verb-lookup test-word)
```

### Detect བཙོང (to sell) from future stem

**Example:** Segment 25: དབུལ་བ་བཙོང་ན

**Tags:** `:regression`

```
GIVEN: (setq test-word "བཙོང")
WHEN:  (tibetan-verb-lookup test-word)
```

### Detect ཐོངས (imperative of གཏོང, to release)

**Example:** Segment 25: སྦྱིན་པ་ཐོངས་ཤིག

**Tags:** `:regression`

```
GIVEN: (setq test-word "ཐོངས")
WHEN:  (tibetan-verb-lookup test-word)
```

### Detect ཁྲུས (to bathe)

**Example:** Segment 25: ཁྲུས་གྱིས་ལ

**Tags:** `:regression`

```
GIVEN: (setq test-word "ཁྲུས")
WHEN:  (tibetan-verb-lookup test-word)
```

### Recognize past stem བྱིན as སྦྱིན

**Example:** Common verb: give

**Tags:** `:verb-stems`

```
GIVEN: (setq test-word "བྱིན")
WHEN:  (tibetan-verb-lookup test-word)
```

### Recognize past stem སོང as འགྲོ

**Example:** Common verb: go

**Tags:** `:verb-stems`

```
GIVEN: (setq test-word "སོང")
WHEN:  (tibetan-verb-lookup test-word)
```

### Classify transitive verb with Erg-Abs frame

**Example:** Perception verb: to see

**Tags:** `:case-frames`

```
GIVEN: (setq test-word "མཐོང")
WHEN:  (tibetan-verb-lookup test-word)
```

### Classify intransitive verb with Abs frame

**Example:** Motion verb: to go

**Tags:** `:case-frames`

```
GIVEN: (setq test-word "འགྲོ")
WHEN:  (tibetan-verb-lookup test-word)
```

### Classify ditransitive verb with Erg-Abs-Dat frame

**Example:** Ditransitive verb: to give

**Tags:** `:case-frames` `:critical`

```
GIVEN: (setq test-word "སྦྱིན")
WHEN:  (tibetan-verb-lookup test-word)
```

### Strip trailing shad before lookup

**Example:** Verb at end of sentence

**Tags:** `:parsing`

```
GIVEN: (setq test-word "གསུངས།")
WHEN:  (tibetan-verb-lookup test-word)
```

### Handle verb with double shad

**Example:** Verb at end of verse

**Tags:** `:parsing`

```
GIVEN: (setq test-word "གསུངས༎")
WHEN:  (tibetan-verb-lookup test-word)
```

### Return nil for non-verb

**Example:** Buddha - noun, not verb

**Tags:** `:edge-cases`

```
GIVEN: (setq test-word "སངས་རྒྱས")
WHEN:  (tibetan-verb-lookup test-word)
```

### Return nil for empty string

**Tags:** `:edge-cases`

```
GIVEN: (setq test-word "")
WHEN:  (tibetan-verb-lookup test-word)
```

### Return nil for whitespace

**Tags:** `:edge-cases`

```
GIVEN: (setq test-word "  ")
WHEN:  (tibetan-verb-lookup test-word)
```

---

## Grammatical particle detection and annotation

*Suite: `particle-analysis`*

### Detect གྱིས as ergative marker

**Example:** Segment 25: ཁྲུས་གྱིས་ལ

**Tags:** `:regression` `:case-markers`

```
GIVEN: (setq test-particle "གྱིས")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ས as ergative marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "ས")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ཀྱིས as ergative marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "ཀྱིས")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ལ as dative marker

**Example:** Segment 25: གྱིས་ལ

**Tags:** `:regression` `:case-markers`

```
GIVEN: (setq test-particle "ལ")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ན as locative/conditional

**Example:** Segment 25: བཙོང་ན

**Tags:** `:regression` `:case-markers`

```
GIVEN: (setq test-particle "ན")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ཏུ as allative marker

**Example:** Segment 25: འོག་ཏུ

**Tags:** `:regression` `:case-markers`

```
GIVEN: (setq test-particle "ཏུ")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect སུ as allative marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "སུ")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect དུ as allative marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "དུ")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ར as allative marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "ར")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect གི as genitive marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "གི")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ཀྱི as genitive marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "ཀྱི")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect འི as genitive marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "འི")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ནས as ablative marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "ནས")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ལས as ablative marker

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "ལས")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect སྟེ as continuative converb

**Example:** Segment 25: ཇི་སྟེ

**Tags:** `:regression` `:converbs`

```
GIVEN: (setq test-particle "སྟེ")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ཏེ as continuative converb

**Tags:** `:converbs`

```
GIVEN: (setq test-particle "ཏེ")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ཅིང as simultaneous converb

**Tags:** `:converbs`

```
GIVEN: (setq test-particle "ཅིང")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect བ as nominalizer

**Example:** Segment 25: དབུལ་བ

**Tags:** `:regression` `:nominalizers`

```
GIVEN: (setq test-particle "བ")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect པ as nominalizer

**Tags:** `:nominalizers`

```
GIVEN: (setq test-particle "པ")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ཤིག as imperative marker

**Example:** Segment 25: ཐོངས་ཤིག

**Tags:** `:regression` `:imperative`

```
GIVEN: (setq test-particle "ཤིག")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ཅིག as imperative marker

**Tags:** `:imperative`

```
GIVEN: (setq test-particle "ཅིག")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect ནི as topic marker

**Tags:** `:discourse-markers`

```
GIVEN: (setq test-particle "ནི")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

### Detect དང as comitative

**Tags:** `:case-markers`

```
GIVEN: (setq test-particle "དང")
WHEN:  (tibetan-bdd--get-particle-annotation test-particle)
```

---

## Segment analysis pipeline (C-c u A)

*Suite: `segment-analysis`*

### Generate analysis content for segment with verbs

**Example:** Segment 25: selling poverty passage

**Tags:** `:regression` `:critical` `:integration`

```
GIVEN: (setq test-text "འཕགས་བས་ཇི་སྟེ་དབུལ་བ་བཙོང་ན་ཁྱོད་སྔར་ཁྲུས་གྱིས་ལ་འོག་ཏུ་སྦྱིན་པ་ཐོངས་ཤིག་གསུངས།")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

### Include verb stems in Verb Details

**Example:** Segment 25

**Tags:** `:regression` `:verbs`

```
GIVEN: (setq test-text "འཕགས་བས་ཇི་སྟེ་དབུལ་བ་བཙོང་ན་ཁྱོད་སྔར་ཁྲུས་གྱིས་ལ་འོག་ཏུ་སྦྱིན་པ་ཐོངས་ཤིག་གསུངས།")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

### Include Wylie transliteration

**Example:** Buddha

**Tags:** `:wylie`

```
GIVEN: (setq test-text "སངས་རྒྱས།")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

### Include DharmaMitra translation when available

**Example:** Segment with parallel translation

**Tags:** `:translations`

```
GIVEN: (setq test-text "འཕགས་བས་ཇི་སྟེ་དབུལ་བ་བཙོང་ན")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

### Format word with Wylie in brackets

**Example:** Basic word annotation

**Tags:** `:format`

```
GIVEN: (setq test-text "སངས་རྒྱས")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

### Format particle with grammatical annotation

**Example:** Conditional particle

**Tags:** `:format` `:particles`

```
GIVEN: (setq test-text "བཙོང་ན")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

### Look up word meanings from glossary

**Example:** Common Buddhist term

**Tags:** `:vocabulary`

```
GIVEN: (setq test-text "སྦྱིན་པ")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

### Handle empty text gracefully

**Tags:** `:edge-cases`

```
GIVEN: (setq test-text "")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

### Handle text with only punctuation

**Tags:** `:edge-cases`

```
GIVEN: (setq test-text "།།")
WHEN:  (when (fboundp 'tibetan-analysis-generate-content) (tibetan-analysis-generate-content test-text))
```

---

## CAT translation engine (C-c u t)

*Suite: `cat-translation`*

### Generate gloss for known vocabulary word

**Example:** Buddha

**Tags:** `:glossing`

```
GIVEN: (setq test-word "སངས་རྒྱས")
WHEN:  (when (fboundp 'tibetan-cat--gloss-word) (tibetan-cat--gloss-word test-word))
```

### Generate gloss for verb

**Example:** Honorific verb

**Tags:** `:glossing` `:verbs`

```
GIVEN: (setq test-word "གསུངས")
WHEN:  (when (fboundp 'tibetan-cat--gloss-word) (tibetan-cat--gloss-word test-word))
```

### Return nil for unknown word gracefully

**Tags:** `:glossing` `:edge-cases`

```
GIVEN: (setq test-word "ཨ་ཀ་ར")
WHEN:  (when (fboundp 'tibetan-cat--gloss-word) (tibetan-cat--gloss-word test-word))
```

### Word order variable exists

**Tags:** `:word-order`

```
WHEN:  (boundp 'tibetan-cat-translation-word-order)
```

### Map Erg-Abs to correct order

**Tags:** `:word-order`

```
WHEN:  (when (boundp 'tibetan-cat-translation-word-order) (alist-get 'Erg-Abs tibetan-cat-translation-word-order))
```

### Map Abs frame exists

**Tags:** `:word-order`

```
WHEN:  (when (boundp 'tibetan-cat-translation-word-order) (alist-get 'Abs tibetan-cat-translation-word-order))
```

### Map Erg-Abs-Dat for ditransitive verbs

**Tags:** `:word-order`

```
WHEN:  (when (boundp 'tibetan-cat-translation-word-order) (alist-get 'Erg-Abs-Dat tibetan-cat-translation-word-order))
```

### Parse structure text for arguments

**Example:** Structure from segment analysis

**Tags:** `:parsing`

```
GIVEN: (setq test-structure "- PREDICATE: གསུངས \"to speak\"
  - AGENT: འཕགས \"noble\"")
WHEN:  (when (fboundp 'tibetan-cat--get-arguments-from-structure) (tibetan-cat--get-arguments-from-structure test-structure))
```

### Generate translation string from text

**Example:** Simple text

**Tags:** `:integration`

```
GIVEN: (setq test-text "སངས་རྒྱས།")
WHEN:  (when (fboundp 'tibetan-cat-generate-translation) (tibetan-cat-generate-translation test-text))
```

### tibetan-cat-insert-translation function exists

**Tags:** `:api`

```
WHEN:  (fboundp 'tibetan-cat-insert-translation)
```

### tibetan-cat-translate-region function exists

**Tags:** `:api`

```
WHEN:  (fboundp 'tibetan-cat-translate-region)
```

---

## Compound/verse analysis (C-c v A)

*Suite: `compound-analysis`*

### Detect 〔sent〕...〔/sent〕 block

**Example:** Sentence block

**Tags:** `:block-detection`

```
GIVEN: (setq test-buffer-content "〔sent〕
〔seg〕Test〔/seg〕
〔/sent〕")
WHEN:  (with-temp-buffer (insert test-buffer-content) (goto-char 20) (if (fboundp 'tibetan-compound--detect-block-markers) (tibetan-compound--detect-block-markers "sent") 'function-not-loaded))
```

### Detect 〔verse :num N〕...〔/verse〕 block

**Example:** Verse block

**Tags:** `:block-detection`

```
GIVEN: (setq test-buffer-content "〔verse :num 1〕
རིགས་ཅན་གསུམ།
〔/verse〕")
WHEN:  (with-temp-buffer (insert test-buffer-content) (goto-char 20) (if (fboundp 'tibetan-compound--detect-block-markers) (tibetan-compound--detect-block-markers "verse") 'function-not-loaded))
```

### Detect 〔prose :comment-on N〕 block

**Example:** Prose commentary block

**Tags:** `:block-detection`

```
GIVEN: (setq test-buffer-content "〔prose :comment-on 1〕
Commentary
〔/prose〕")
WHEN:  (with-temp-buffer (insert test-buffer-content) (goto-char 25) (if (fboundp 'tibetan-compound--detect-block-markers) (tibetan-compound--detect-block-markers "prose") 'function-not-loaded))
```

### Return nil when outside any block

**Example:** Position before block

**Tags:** `:block-detection` `:edge-cases`

```
GIVEN: (setq test-buffer-content "Before
〔sent〕Inside〔/sent〕
After")
WHEN:  (with-temp-buffer (insert test-buffer-content) (goto-char 3) (if (fboundp 'tibetan-compound--detect-block-markers) (tibetan-compound--detect-block-markers "sent") 'function-not-loaded))
```

### Aggregate vocabulary across verse lines

**Example:** Verse line with compounds

**Tags:** `:aggregation`

```
GIVEN: (setq test-verse "རིགས་ཅན་གསུམ་གྱི་གདུལ་བྱ།")
WHEN:  (if (and (fboundp 'tibetan-parse-enhanced) (fboundp 'tibetan-build-compound-aware-segments)) (let* ((parsed (tibetan-parse-enhanced test-verse)) (words (alist-get 'words parsed)) (multiword (alist-get 'multiword-units parsed))) (tibetan-build-compound-aware-segments words multiword)) 'functions-not-loaded)
```

### Count syllables for meter validation

**Example:** 7-syllable verse line

**Tags:** `:meter`

```
GIVEN: (setq test-line "རིགས་ཅན་གསུམ་གྱི་གདུལ་བྱ་ལ།")
WHEN:  (if (fboundp 'tibetan-count-syllables) (tibetan-count-syllables test-line) 'function-not-loaded)
```

### tibetan-open-compound-analysis exists

**Tags:** `:api`

```
WHEN:  (fboundp 'tibetan-open-compound-analysis)
```

### tibetan-reanalyze-compound exists

**Tags:** `:api`

```
WHEN:  (fboundp 'tibetan-reanalyze-compound)
```

---

