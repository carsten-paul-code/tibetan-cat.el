# CAT-Tool Improvements Plan

## Issues Identified

### 1. Latin Text Too Large in Prepared .org Files
**Problem**: The `〔seg〕`, `〔sent〕`, `〔/seg〕` markers appear too large relative to Tibetan text.

**Solution**: Add font-lock rules to scale down segment markers in org-mode buffers when viewing prepared documents.

**Implementation**:
- Create `tibetan-doc-display.el` in `doc-prep/` folder
- Add face definitions for segment markers (smaller, muted color)
- Hook into `org-mode` for files containing Tibetan segment markers
- Target height: ~60-70% of Tibetan text size

### 2. Analysis Output Quality Degraded
**Problem**: Current `C-c u A` output is less informative than before. Many `[?]` entries, poor segmentation.

**Root Cause**: The `tibetan-analysis-generate-content` function may not be loading vocabularies or using the enhanced parser correctly.

**Solution**:
- Verify vocabulary loading before analysis
- Ensure `tibetan-parse-enhanced` is called with proper context
- Improve word-by-word gloss lookup (check multiple sources)

### 3. Compact Segmentation with Inline Annotations
**Problem**: User wants vocabulary/particle info close to the units, not in separate sections.

**Current format**:
```
** Segmentation
འཕགས | བས | ཇི | སྟེ | དབུལ | བ | ...

** Lexical Units
- སྟེ [ste] - continuative
```

**New format** (proposed):
```
** Annotated Segments
འཕགས ['phags] |
བས [bas] (ERG: by) |
ཇི་སྟེ [ji ste] "why" (continuative) |
དབུལ་བ [dbul ba] "poverty/poor" |
བཙོང [btsong] "sell" (VERB: pres/past/fut/imp) |
ན [na] (LOC: if/when) |
...
```

**Implementation**:
- Restructure `tibetan-analysis-generate-content` output
- Combine Wylie, meaning, and grammatical info per segment
- Use compact notation: `(CASE: function)` for particles

### 4. CAT-Tool Suggested Translation
**Problem**: User wants a machine translation suggestion from the tool itself, not just DharmaMitra.

**Solution**:
- Create `tibetan-cat-translate.el` with rule-based translation
- Use detected verb frames, arguments, and vocabulary to generate gloss
- Output: rough word-order translation as starting point

**Implementation**:
- Parse sentence structure (S-O-V order)
- Map case markers to English prepositions
- Combine into rough translation
- Label as "CAT Suggested Translation (rough)"

### 5. Translations Immediately Below Segments
**Problem**: User wants translations visible at a glance, not buried in separate sections.

**New output structure**:
```
** Annotated Segments
[segmented text with inline annotations]

** Translations
- DharmaMitra: "..."
- CAT Suggested: "..."

** Grammatical Analysis
[verbs, arguments, etc.]

* My Notes
* Working Translation
```

### 6. Grammatical Structure Analysis
**Problem**: User wants explicit subject/predicate/object/head analysis.

**Solution**: Enhance argument structure display with:
- Subject identification (ERG or ABS depending on verb)
- Object identification (ABS for transitive)
- Predicate (main verb with tense/aspect)
- Oblique arguments (LOC, DAT, ALL)
- Head noun identification in NPs

**Output format**:
```
** Sentence Structure
*** Clause 1
- SUBJECT: ཁྱོད (you) [ABS]
- PREDICATE: བཙོང (sell) [PRES]
- OBJECT: དབུལ་བ (poverty) [ABS]
- CONDITION: ... ན (if...)
```

---

## Implementation Order

1. **Fix vocabulary loading** - ensures better analysis immediately
2. **Latin text scaling** - improves document readability
3. **Compact annotated segments** - core UX improvement
4. **Translations placement** - better at-a-glance view
5. **Grammatical structure** - deeper linguistic analysis
6. **CAT suggested translation** - long-term improvement

---

## Files to Modify/Create

| File | Action | Purpose |
|------|--------|---------|
| `doc-prep/tibetan-doc-display.el` | CREATE | Scale segment markers in prepared docs |
| `persist/tibetan-analysis-persist.el` | MODIFY | Restructure output format |
| `analysis/tibetan-enhanced-display.el` | MODIFY | Add grammatical structure analysis |
| `analysis/tibetan-cat-translate.el` | CREATE | Rule-based translation suggestions |
| `tibetan-cat.el` | MODIFY | Load new modules |

---

## Output Format Comparison

### BEFORE (Current)
```
** Wylie Transliteration
'phags bsa ji ste...

** Segmentation
འཕགས | བས | ཇི | སྟེ | ...

** Lexical Units
- སྟེ [ste]
  - Type: Vocabulary
  - Meaning: continuative

** Particles & Case Markers
- ན
  - Type: Case particle
  ...

** DharmaMitra Translation
"..."
```

### AFTER (Proposed)
```
** Annotated Text
འཕགས ['phags] |
བས [bas] (ERG) |
ཇི་སྟེ [ji ste] "why" + continuative |
དབུལ་བ [dbul ba] "poverty" |
བཙོང [btsong] V:sell |
ན [na] (LOC: if) |
ཁྱོད [khyod] "you" |
...

** Translations
- DharmaMitra: "The noble one said..."
- CAT Suggested: "[you] if [poverty] sell, [you] first bathe and then give alms..."

** Sentence Structure
SUBJECT: ཁྱོད (you)
CONDITION: དབུལ་བ་བཙོང་ན (if selling poverty)
PREDICATE₁: ཁྲུས་གྱིས (bathe!)
PREDICATE₂: སྦྱིན་པ་ཐོངས (give alms!)

** Verb Details
[Hill 2010 analysis if needed]

** Notes on Particles
[Only unusual or ambiguous cases]
```
