# Quick Start: Phase 1 Enhanced Parser

## Installation

1. **Restart Emacs** to load the new modules:
   ```bash
   # Or reload tibetan-cat
   M-x load-file RET ~/emacs-tibetan-cat/tibetan-cat.el RET
   ```

2. **Verify dictionaries loaded**:
   ```elisp
   M-: (hash-table-count tibetan-compounds-dict) RET
   ;; Should return: 15,194 entries (auto-extracted from Hopkins/Bialek)

   M-: (hash-table-count tibetan-proper-nouns-dict) RET
   ;; Should return: 486 entries (auto-extracted)
   ```

## Testing

### Test Case 1: Your Example
1. Open: `/Users/cp/buddhist-studies/WS25-26/Tibetisch III/TigressStory/WorkInProgress/Reading1-Tigress-Story-TextOnly.org`

2. Position cursor on line 7:
   ```tibetan
   གཞན་ཡང་གླེང་གཞི་སྟོན་པ་མཉན་ཡོད་ན་བཞུགས་པའི་ཚེ།
   ```

3. Press **C-c u I** (capital I)

### Expected Results

#### Segmentation
```
གཞན་ཡང | གླེང་གཞི | སྟོན་པ | མཉན་ཡོད | ན | བཞུགས | པའི | ཚེ
```

#### Lexical Units (Should show 4)
- གཞན་ཡང = moreover (connector)
- གླེང་གཞི = nidāna (technical term)
- སྟོན་པ = Teacher (epithet)
- མཉན་ཡོད = Śrāvastī (place)

#### Particles (Should show 2)
- ན (after མཉན་ཡོད) = Locative
- པའི (after བཞུགས) = Nominalizer + Genitive

#### Verbs (Should show 1)
- བཞུགས only (no false matches for ན, ཚེ, etc.)

### Compare with Regular Analysis

Try both:
- **C-c u i** (regular) - may show false positives
- **C-c u I** (enhanced) - cleaner output

## Key Features to Notice

### ✅ No False Particle Detection
Regular parser might show:
- ❌ ན in གཞན (wrong!)
- ❌ ན in སྟོན (wrong!)
- ❌ ན in མཉན (wrong!)

Enhanced parser shows:
- ✅ Only ན AFTER མཉན་ཡོད (correct!)

### ✅ Compound Recognition
Regular parser: splits into syllables
Enhanced parser: recognizes multi-word units with meanings

### ✅ Filtered Verb List
Regular parser: may show ན, ཚེ, etc. as verbs
Enhanced parser: only real verbs in context

## Keyboard Shortcuts

| Key     | Function                    | Output              |
|---------|-----------------------------|---------------------|
| C-c u i | Regular analysis            | Original format     |
| C-c u I | Enhanced analysis (NEW!)    | Cleaner, accurate   |
| C-c u E | Toggle auto-analysis        | Uses regular        |

## Troubleshooting

### "compounds.json not found"
Check path:
```bash
ls -la ~/emacs-tibetan-cat/data/dictionaries/
```

Should show:
- compounds.json (80+ entries)
- proper_nouns.json (40+ entries)

### "tibetan-compounds-dict is nil"
Reload dictionaries:
```elisp
M-: (setq tibetan-compounds-dict nil) RET
M-: (setq tibetan-proper-nouns-dict nil) RET
M-x load-file RET ~/emacs-tibetan-cat/analysis/tibetan-enhanced-parser.el RET
```

### No improved output
1. Check keybinding works: `C-h k C-c u I`
   Should show: `tibetan-segment-info-enhanced`

2. Verify modules loaded:
   ```elisp
   M-: (featurep 'tibetan-enhanced-parser) RET
   ;; Should return: t
   ```

## Adding Your Own Compounds

1. Edit dictionary:
   ```bash
   emacs ~/emacs-tibetan-cat/data/dictionaries/compounds.json
   ```

2. Add entry:
   ```json
   {
     "your_compound": {
       "wylie": "your compound",
       "english": "meaning",
       "category": "technical_term"
     }
   }
   ```

3. Reload:
   ```elisp
   M-: (setq tibetan-compounds-dict nil) RET
   M-: (tibetan-load-dictionaries) RET
   ```

## Next Steps

Once you've verified Phase 1 works:

1. **Test on more texts** - try different classical Tibetan documents
2. **Expand dictionaries** - add compounds you encounter
3. **Report issues** - any parsing problems found
4. **Phase 2 planning** - Bialek verb features, zero marker detection

## Questions?

Check the detailed documentation:
- `PHASE1-ENHANCED-PARSING.md` - Full technical details
- `CHANGELOG-FIXES-2025-12-02.md` - Recent improvements

Happy parsing! 🎉
