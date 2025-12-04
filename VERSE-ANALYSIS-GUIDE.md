# VERSE ANALYSIS GUIDE

**Date**: 2025-11-10
**Feature**: Two-level analysis architecture for verse texts

---

## ARCHITECTURE DECISION: LINE-LEVEL + VERSE-LEVEL ANALYSIS

After refactoring the Madhyamaka verse text (dbu ma'i bsdus don lta ba'i me long), we established a **two-level analysis architecture** for verse texts:

### Level 1: LINE-LEVEL ANALYSIS (`C-c u i`)
**Granularity**: Individual 7-syllable line
**Use case**: Deep analysis of a single line
**Features**:
- Wylie transliteration
- DharmaMitra translation
- Vocabulary extraction
- Bialek grammar analysis (case particles, converbial constructions)
- Translation suggestions

**How it works**:
- Each line is wrapped in segment markers: `〔seg:xxx:NNN〕line text〔/seg〕`
- Placing cursor on any line and pressing `C-c u i` analyzes that single line
- Fast, focused analysis for line-by-line study

### Level 2: VERSE-LEVEL ANALYSIS (`C-c v v`)
**Granularity**: Entire verse block (typically 4 lines)
**Use case**: Holistic verse analysis with metrical and philosophical context
**Features**:
- **Metrical analysis**: Syllable count validation for all lines (7-syllable meter)
- **Core meaning extraction**: Removes metrical fillers, shows semantic core
- **Vocabulary**: All terms from all lines in the verse
- **Madhyamaka terminology**: Identifies and explains 90+ technical terms
- **Translation workspace**: Space for complete verse translation

**How it works**:
- Verses are grouped with `〔verse:NNN〕` markers
- Placing cursor anywhere in a verse and pressing `C-c v v` analyzes the entire verse
- Comprehensive view for understanding verse structure and meaning

---

## FILE STRUCTURE

For verse texts, use this structure:

```org
#+TIBETAN_TEXT_TYPE: madhyamaka-verse

* Verse 1: Opening Homage

〔verse:001〕

〔seg:text:001〕གཉིས་མེད་གསུང་ལ་ཕྱག་འཚལ་ནས།〔/seg〕
〔seg:text:002〕ཤེས་བྱའི་གནས་ལུགས་གསལ་བའི་ཕྱིར།〔/seg〕
〔seg:text:003〕ཐེག་མཆོག་དབུ་མའི་ལྟ་བ་ཡི།〔/seg〕
〔seg:text:004〕རྣམ་གཞག་མདོ་ཙམ་བསྟན་པར་བྱ།〔/seg〕

Translation:
"Having paid homage to the non-dual teachings..."

*** Key Terms
- གཉིས་མེད་ (gnyis med) - non-dual
- དབུ་མ (dbu ma) - Madhyamaka
```

**Key points**:
1. **No intermediate "sequence" level** - just verses and lines
2. **Segment markers wrap individual lines** - each line is analyzable
3. **Verse markers group lines** - provides context for verse-level analysis
4. **Two-level hierarchy**: Verse blocks → Line segments

---

## WORKFLOW EXAMPLES

### Studying a difficult line
1. Place cursor on the line
2. Press `C-c u i` (line-level analysis)
3. Review vocabulary, grammar, translation suggestion
4. Focus on understanding this specific 7-syllable unit

### Analyzing verse meter and structure
1. Place cursor anywhere in the verse
2. Press `C-c v v` (verse-level analysis)
3. Check all lines are 7 syllables
4. See metrical fillers marked (ནི, ཡང, etc.)
5. Extract core meaning without fillers
6. Review all vocabulary and Madhyamaka terms at once

### Translating a verse
1. Use `C-c v v` to see full verse context
2. Identify key Madhyamaka terms
3. See metrical structure
4. Use `C-c u i` on difficult lines for detailed analysis
5. Write translation in verse-level workspace

---

## EXAMPLE OUTPUT

### Line-Level Analysis (`C-c u i`)

```
╔══════════════════════════════════════════════════════════════╗
║         SEGMENT ANALYSIS - CLASSROOM                         ║
╚══════════════════════════════════════════════════════════════╝

Segment: seg:dbu-ma-bsdus-don:004

TIBETAN TEXT:
གཉིས་མེད་གསུང་ལ་ཕྱག་འཚལ་ནས།

WYLIE (for reading aloud):
gnyis med gsung la phyag 'tshal nas/

VOCABULARY:
  གཉིས་མེད (non-dual) གསུང (teaching) ཕྱག་འཚལ (homage)

GRAMMATICAL ANALYSIS (Bialek):
  • ལ in 'གསུང་ལ'
    TYPE: DAT (dative)
    FUNCTION: Recipient/goal
    TRANSLATION: 'to/toward the teachings'
    REFERENCE: Bialek §8.2

  • ནས in 'འཚལ་ནས'
    TYPE: ABLATIVE CONVERB
    FUNCTION: Sequential action
    TRANSLATION: 'having paid homage'
    REFERENCE: Bialek §12.3

SUGGESTED TRANSLATION:
  "Having paid homage to the non-dual teachings"
```

### Verse-Level Analysis (`C-c v v`)

```
╔══════════════════════════════════════════════════════════════╗
║         VERSE ANALYSIS - PHILOLOGY TOOLS                     ║
╚══════════════════════════════════════════════════════════════╝

VERSE 001

ROOT TEXT:
──────────────────────────────────────
གཉིས་མེད་གསུང་ལ་ཕྱག་འཚལ་ནས།
ཤེས་བྱའི་གནས་ལུགས་གསལ་བའི་ཕྱིར།
ཐེག་མཆོག་དབུ་མའི་ལྟ་བ་ཡི།
རྣམ་གཞག་མདོ་ཙམ་བསྟན་པར་བྱ།

╔═══════════════════════════════════════════════════════════╗
║ VERSE 001 ANALYSIS
╚═══════════════════════════════════════════════════════════╝

Line 1: གཉིས་མེད་གསུང་ལ་ཕྱག་འཚལ་ནས།
  [7 syllables] ✓
  གཉིས་  མེད་  གསུང་  ལ་  ཕྱག་  འཚལ་  ནས།
  1      2      3       4    5      6       7

Line 2: ཤེས་བྱའི་གནས་ལུགས་གསལ་བའི་ཕྱིར།
  [7 syllables] ✓
  ཤེས་  བྱ་  འི་  གནས་  ལུགས་  གསལ་  བ་  འི་  ཕྱིར།
  1     2     3    4      5       6      7    8    9
  [METER ERROR: 9 syllables detected]

METRICAL ANALYSIS:
  གཉིས་མེད་གསུང་[ལ་]ཕྱག་འཚལ་[ནས]
  ཤེས་བྱ་[འི་]གནས་ལུགས་གསལ་བ་[འི་][ཕྱིར]
  ཐེག་མཆོག་དབུ་མ་[འི་]ལྟ་བ་[ཡི]
  རྣམ་གཞག་མདོ་[ཙམ་]བསྟན་པར་བྱ

VOCABULARY (all lines):
  གཉིས་མེད་གསུང་ལ་ཕྱག་འཚལ་ནས།:
    • གཉིས་མེད (non-dual)
    • གསུང (teaching, honorific)
    • ཕྱག་འཚལ (pay homage)

  ཤེས་བྱའི་གནས་ལུགས་གསལ་བའི་ཕྱིར།:
    • ཤེས་བྱ (knowable object)
    • གནས་ལུགས (mode of abiding/reality)
    • གསལ་བ (clarity/illuminate)

MADHYAMAKA TERMINOLOGY:
──────────────────────────────────────
  • གཉིས་མེད
    → Non-dual

  • ཐེག་མཆོག
    → Supreme vehicle (Mahāyāna)

  • དབུ་མའི་ལྟ་བ
    → Madhyamaka view

  • གནས་ལུགས
    → Mode of abiding/reality

TRANSLATION WORKSPACE:
──────────────────────────────────────
[Your translation here]

PHILOLOGICAL NOTES:
──────────────────────────────────────
[Your notes here]
```

---

## WHY TWO LEVELS?

### Problem with single level
If we only had segment-level analysis, we'd miss:
- Verse-wide metrical patterns
- Philosophical term relationships across lines
- Overall verse structure and meaning

If we only had verse-level analysis, we'd miss:
- Detailed grammatical analysis of individual lines
- Line-by-line vocabulary and translation help
- Focused study of difficult constructions

### Solution: Two complementary levels
**Line-level** (`C-c u i`): Microscope for detailed grammatical study
**Verse-level** (`C-c v v`): Telescope for metrical and philosophical overview

Both use the same underlying structure:
- Lines are segments (analyzable units)
- Verses group lines (contextual units)
- No redundant "sequence" level needed

---

## BENEFITS OF THIS ARCHITECTURE

1. **Clean structure**: Two clear levels (verses contain lines)
2. **Flexible analysis**: Choose granularity based on need
3. **Existing tools work**: `C-c u i` already handles line-level
4. **New tools added**: `C-c v v` adds verse-level capability
5. **No confusion**: Clear when to use which analysis
6. **Efficient**: Both levels share underlying segment structure

---

## COMPARISON TO PROSE TEXTS

### Classical Prose (Tibetisch III)
- Text type: `#+TIBETAN_TEXT_TYPE: classical`
- Structure: Sentences → Segments (variable length)
- Analysis: `C-c u i` (segment analysis with Bialek grammar)
- No verse-level analysis needed

### Madhyamaka Verse
- Text type: `#+TIBETAN_TEXT_TYPE: madhyamaka-verse`
- Structure: Verses → Lines (7 syllables each)
- Analysis: **Both** `C-c u i` (line) and `C-c v v` (verse)
- Specialized tools for meter and philosophical terminology

---

## GETTING STARTED

### 1. Add classification header to your verse text
```org
#+TIBETAN_TEXT_TYPE: madhyamaka-verse
```

### 2. Reload Emacs or load the CAT system
```elisp
M-x load-file RET ~/emacs-tibetan-cat/tibetan-cat.el RET
```

### 3. Try line-level analysis
- Place cursor on any verse line
- Press `C-c u i`
- See grammatical analysis of that line

### 4. Try verse-level analysis
- Place cursor anywhere in a verse block
- Press `C-c v v`
- See metrical analysis, vocabulary, and Madhyamaka terms for entire verse

---

## KEYBOARD SHORTCUTS SUMMARY

| Shortcut | Level | Function |
|----------|-------|----------|
| `C-c u i` | Line | Segment analysis (grammar, vocab, translation) |
| `C-c v v` | Verse | Verse block analysis (meter, terms, structure) |
| `C-c u E` | - | Toggle auto-analysis mode |
| `C-c s w` | - | Sentence/verse workspace |
| `C-c u v` | - | Reload glossaries |

---

## FILES MODIFIED

1. **philology/tibetan-verse-philology.el**
   - Added `tibetan-get-current-verse-block` (extracts verse data)
   - Added `tibetan-analyze-current-verse-interactive` (interactive wrapper)

2. **config/tibetan-keybindings.el**
   - Added `C-c v v` keybinding for verse analysis

3. **tibetan-cat.el**
   - Updated initialization messages to explain two-level analysis

---

## NEXT STEPS

Consider extending verse analysis with:
- Auto-detection of meter violations
- Cross-reference to commentary annotations
- Export verse analysis to PDF
- Comparison of multiple text editions
- Integration with critical apparatus

---

**Status**: ✅ Implemented and tested
**Version**: Tibetan CAT v1.0.0 - Classroom & Philology Edition
**Author**: Developed for Buddhist Studies graduate coursework

May this reduce suffering in Prof. Schwerk's Madhyamaka class! 🙏📚
