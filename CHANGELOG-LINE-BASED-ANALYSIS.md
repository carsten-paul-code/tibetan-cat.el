# Line-Based Analysis Support

**Date**: 2025-12-02
**Feature**: Enable C-c u i and C-c u E to work on plain Tibetan text lines

## Problem

Previously, the segment analysis functions (C-c u i and C-c u E) only worked with:
1. Org structure: `*** Segment N` headings
2. Old markers: `〔seg:...〕...〔/seg〕`

This was problematic for text-only documents (like Reading1-Tigress-Story-TextOnly.org) that contain plain Tibetan text without structural markers.

## Solution

Extended `tibetan-get-current-segment-any-format()` to support a third mode: **plain text lines**.

### Changes Made

**File**: `~/emacs-tibetan-cat/core/tibetan-utils.el`

1. **Added new function**: `tibetan-get-current-line-as-segment()`
   - Treats the current line as a segment
   - Detects Tibetan Unicode characters ([ཀ-࿿])
   - Excludes org-mode syntax (headings, properties, #+keywords)
   - Returns: `(cons "Line N" "tibetan text")`

2. **Modified function**: `tibetan-get-current-segment-any-format()`
   - Now tries THREE formats in order:
     1. Org structure (*** Segment N)
     2. Old markers (〔seg:...〕)
     3. **Plain text line** (NEW)

### Behavior

When you press **C-c u i** on any line containing Tibetan text:
- If line has Tibetan characters → Analysis window appears
- If line is org heading/keyword → Skipped
- If line is empty → Skipped

When you enable **C-c u E** (auto-analysis mode):
- Analysis automatically updates as you move between Tibetan text lines
- Works seamlessly with all three formats

### Example

**Before** (would fail):
```org
#+TITLE: Tigress Story
* བྱང་ཆུབ་སེམས་དཔའ་དང་སྟག་མོ་བཀྲེས་པའི་སྐད་རྒྱུད།

གཞན་ཡང་གླེང་གཞི་སྟོན་པ་མཉན་ཡོད་ན་བཞུགས་པའི་ཚེ།  <-- C-c u i here would error
```

**After** (works):
```org
#+TITLE: Tigress Story
* བྱང་ཆུབ་སེམས་དཔའ་དང་སྟག་མོ་བཀྲེས་པའི་སྐད་རྒྱུད།

གཞན་ཡང་གླེང་གཞི་སྟོན་པ་མཉན་ཡོད་ན་བཞུགས་པའི་ཚེ།  <-- C-c u i here shows "Line 7" analysis
```

### Technical Details

The new detection logic:
```elisp
;; Check if line contains Tibetan text
(when (and (not (string-empty-p (string-trim line-text)))
           (string-match-p "[ཀ-࿿]" line-text)        ; Tibetan Unicode range
           (not (string-match-p "^\\*+ " line-text))    ; Not org heading
           (not (string-match-p "^[ \t]*:" line-text))  ; Not property
           (not (string-match-p "^#\\+" line-text)))    ; Not keyword
  (cons (format "Line %d" line-num) (string-trim line-text)))
```

## How to Use

### 1. Reload Configuration

After pulling this update, reload the Tibetan CAT system in Emacs:

```elisp
M-x eval-buffer RET  ; in tibetan-utils.el
```

Or restart Emacs.

### 2. Open Text-Only File

```elisp
C-x C-f ~/path/to/Reading1-Tigress-Story-TextOnly.org
```

### 3. Test Line-Based Analysis

Move cursor to any line with Tibetan text and press:
- **C-c u i** - Show analysis for current line
- **C-c u E** - Enable auto-analysis (updates as you navigate)

### 4. Expected Output

Analysis window shows:
```
╔══════════════════════════════════════════════════════════════╗
║         SEGMENT ANALYSIS - CLASSROOM                         ║
╚══════════════════════════════════════════════════════════════╝

Segment: Line 7

TIBETAN TEXT:
གཞན་ཡང་གླེང་གཞི་སྟོན་པ་མཉན་ཡོད་ན་བཞུགས་པའི་ཚེ།

WYLIE (for reading aloud):
gzhan yang gleng gzhi ston pa mnyan yod na bzhugs pa'i tshe/

DHARMAMITRA TRANSLATION:
[Translation...]

VOCABULARY:
  གཞན་ (other) ཡང་ (also) ...

GRAMMATICAL ANALYSIS (Bialek):
  • པ in 'བཞུགས་པ'
    TYPE: Nominalizer
    FUNCTION: Creates noun from verb
    TRANSLATION: -ing, one who...
    REFERENCE: Bialek §12.3
  ...

SUGGESTED TRANSLATION:
[Generated translation based on vocab + grammar]

[Press q to close]
```

## Compatibility

The change is **fully backward compatible**:
- Old org structure files (*** Segment N) → Still work
- Old marker files (〔seg:...〕) → Still work
- New plain text files → **Now work**

## Files Modified

- `~/emacs-tibetan-cat/core/tibetan-utils.el`
  - Added: `tibetan-get-current-line-as-segment()`
  - Modified: `tibetan-get-current-segment-any-format()`

## Testing

Tested with:
- ✓ Plain text file: Reading1-Tigress-Story-TextOnly.org
- ✓ Org structure file: Reading1-Tigress-Story-Structured.org
- ✓ Auto-analysis mode (C-c u E)
- ✓ Manual analysis (C-c u i)

## Notes

- Line numbers are displayed as "Line N" in the analysis window
- Empty lines and org syntax are automatically skipped
- Auto-analysis mode uses fast mode (skips slow DharmaMitra translation)
- Press C-c u i manually to see full translation with DharmaMitra

## Related Files

- Main entry: `~/emacs-tibetan-cat/tibetan-cat.el`
- Keybindings: `~/emacs-tibetan-cat/config/tibetan-keybindings.el`
- Analysis engine: `~/emacs-tibetan-cat/analysis/tibetan-classroom.el`
- Utilities: `~/emacs-tibetan-cat/core/tibetan-utils.el` (modified)

## Credits

Implementation based on user request to support text-only Tibetan documents for classroom translation work (Tibetisch III, WS25-26).
