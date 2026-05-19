;;; tibetan-phonetics.el --- Wylie → THL phonetic transcription -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Carsten Paul

;;; Commentary:
;;
;; Wylie → THL Simplified Phonetic Transcription converter
;; (Germano & Tournadre 2003, the international academic standard
;; for romanising Standard Tibetan).  Used as a class-reading aid:
;; Wylie alone is unforgiving when you just need to vocalise a line,
;; THL approximates Lhasa pronunciation in Wylie-friendly Roman
;; orthography (sh / ch / zh / ng).
;;
;; Public entry points:
;;
;;   (tibetan-to-phonetics TEXT)
;;       TEXT may be Tibetan Unicode (auto-converted to Wylie via
;;       `tibetan-to-wylie-fixed') or already-Wylie.  Returns a
;;       space-separated THL phonetic string, shad-preserving,
;;       nil-safe.
;;
;;   (tibetan-wylie-syllable-to-phonetic WYLIE-SYL)
;;       Single-syllable converter — public so the thesaurus UI
;;       and tests can re-use the same rules.
;;
;;   (tibetan-phonetics--curated-override WYLIE)
;;       Looks up WYLIE in `tibetan-thesaurus-lookup' (when
;;       available).  When the matching zettel carries a non-empty
;;       `:phonetics:' field, that value wins over the rule
;;       engine — lets the user pin tricky cases (Madhyamaka,
;;       Sanskrit loans, monastic-tradition readings) without
;;       editing the rules table.
;;
;; Algorithm:
;;   1. Split TEXT into Wylie syllables on whitespace / tsheg /
;;      punctuation.  Punctuation (shad `།', slash, etc.) is
;;      preserved verbatim.
;;   2. For each syllable, try the thesaurus override first.
;;   3. Otherwise:
;;      a. Parse the syllable into prefix / superscript / root /
;;         subscript / vowel / suffix / post-suffix.
;;      b. Map the initial consonant cluster (prefix + superscript +
;;         root + subscript) to a THL initial via the rules engine.
;;      c. Apply vowel umlaut based on suffix:
;;            a / o / u + {i, e, n, l, d, s}  →  e / ö / ü
;;      d. Apply final consonant rules:
;;            -ng, -m  →  kept
;;            -g + silent -s  →  realised as -k
;;            -b  →  realised as -p (final devoicing)
;;            -s, -d, -n, -l, -'  →  silent (after umlaut)
;;      e. Compose the THL syllable.
;;
;; Known limitations:
;;   - THL is Lhasa-based.  Some monastic-reading traditions
;;     pronounce specific terms differently;  use the thesaurus
;;     `:phonetics:' override for these.
;;   - Tone is NOT transcribed (standard simplification — most
;;     published THL renderings outside linguistics journals
;;     omit tone diacritics).
;;   - Archaic / hyper-orthographic spellings (rare 4-letter
;;     clusters) may pass through as Wylie when the cluster
;;     table doesn't recognise them.  Acceptable graceful
;;     degradation.

;;; Code:

(require 'cl-lib)
(require 'tibetan-wylie nil t)
(declare-function tibetan-to-wylie-fixed "tibetan-wylie" (text))
(declare-function tibetan-thesaurus-lookup "tibetan-thesaurus" (key))

;; ============================================================================
;; Tibetan letter inventory
;; ============================================================================

(defconst tibetan-phonetics--consonant-roots
  ;; Wylie root letters, in LONGEST-FIRST order so a greedy prefix
  ;; match grabs `tsh' / `kh' / `ng' before falling back to single
  ;; characters.  Excludes the vowel-only root `a' — that one is
  ;; handled separately because it can't follow a prefix or
  ;; superscript.
  '("tsh"
    "kh" "ch" "th" "ph"
    "ng" "ny" "sh" "zh" "ts" "dz" "dh" "lh" "hr"
    "k" "g" "c" "j" "t" "d" "n" "p" "b" "m"
    "w" "z" "'" "y" "r" "l" "s" "h")
  "Wylie consonant root letters, longest first for greedy match.
`lh' is the unusual l+h cluster (kept as a single phonetic unit
in THL).  `hr' similarly.  Vowel-only root `a' is omitted —
when an initial cluster has no consonant root, the parser
short-circuits.")

(defun tibetan-phonetics--starts-with-root (s)
  "Return the longest Wylie root prefix of S, or nil when none match."
  (when (and s (stringp s) (not (string-empty-p s)))
    (cl-find-if (lambda (root) (string-prefix-p root s))
                tibetan-phonetics--consonant-roots)))

(defconst tibetan-phonetics--valid-prefix-combos
  ;; (PREFIX . ROOT) cons cells listing the legitimate Tibetan prefix
  ;; combinations.  When the parser sees a candidate prefix letter
  ;; followed by a root letter that ISN'T in this list, it concludes
  ;; the first letter is itself part of the root (e.g. `by-' is root
  ;; `b' + subscript `y', NOT prefix `b' + root `y').
  '(;; b-
    ("b" . "k") ("b" . "kh") ("b" . "g") ("b" . "c") ("b" . "j")
    ("b" . "t") ("b" . "d") ("b" . "ts") ("b" . "dz")
    ("b" . "zh") ("b" . "z") ("b" . "sh") ("b" . "s")
    ;; d-
    ("d" . "k") ("d" . "g") ("d" . "ng") ("d" . "p") ("d" . "b") ("d" . "m")
    ;; g-
    ("g" . "c") ("g" . "ny") ("g" . "t") ("g" . "d") ("g" . "n")
    ("g" . "ts") ("g" . "zh") ("g" . "z") ("g" . "sh") ("g" . "s")
    ;; NOT ("g" . "y") — `gy-' is the palatalised cluster g + y-
    ;; subscript (genitive particle `gyi', words like `gyung',
    ;; `gyal'), NOT prefix g + root y.  Removing this combo lets the
    ;; parser correctly identify `gy-' as a root+subscript cluster.
    ;; m-
    ("m" . "kh") ("m" . "g") ("m" . "ng")
    ("m" . "ch") ("m" . "j") ("m" . "ny")
    ("m" . "th") ("m" . "d") ("m" . "n")
    ("m" . "tsh") ("m" . "dz")
    ;; '- (a-chung) — weak prefix, rare
    ("'" . "kh") ("'" . "g") ("'" . "ch") ("'" . "j")
    ("'" . "th") ("'" . "d") ("'" . "ph") ("'" . "b")
    ("'" . "tsh") ("'" . "dz"))
  "Valid Tibetan (PREFIX . ROOT) combinations.")

(defconst tibetan-phonetics--valid-super-combos
  '(;; r-
    ("r" . "k") ("r" . "g") ("r" . "ng") ("r" . "j") ("r" . "ny")
    ("r" . "t") ("r" . "d") ("r" . "n") ("r" . "b") ("r" . "m")
    ("r" . "ts") ("r" . "dz")
    ;; l-
    ("l" . "k") ("l" . "g") ("l" . "ng") ("l" . "c") ("l" . "j")
    ("l" . "t") ("l" . "d") ("l" . "p") ("l" . "b")
    ;; NOT ("l" . "h") — `lh' is a fused phonetic unit (single
    ;; consonant in modern Lhasa), not an l-superscript + h-root
    ;; split.  The parser recognises `lh' via the root table.
    ;; s-
    ("s" . "k") ("s" . "g") ("s" . "ng") ("s" . "ny")
    ("s" . "t") ("s" . "d") ("s" . "n")
    ("s" . "p") ("s" . "b") ("s" . "m") ("s" . "ts"))
  "Valid (SUPERSCRIPT . ROOT) combinations.")

;; ============================================================================
;; Syllable parser
;; ============================================================================

(defun tibetan-phonetics--parse-syllable (wylie)
  "Parse WYLIE single-syllable string into a plist.

Returns `(:initial CLUSTER :vowel VOWEL :suffix SFX :post-suffix POST)'.
CLUSTER is everything before the vowel (prefix + super + root +
subscript);  VOWEL is one of `a' / `i' / `e' / `o' / `u' (implicit
`a' when none written);  SFX and POST may be empty strings.

Strips Wylie punctuation (`/' `།' etc.) before parsing — the
caller is expected to preserve punctuation independently."
  (let* ((clean (replace-regexp-in-string "[/།༎༏ \t\n]" "" wylie)))
    (cond
     ((string-empty-p clean)
      (list :initial "" :vowel "" :suffix "" :post-suffix ""))
     (t
      (let* ((vowel-pos (string-match "[aeiou]" clean))
             (initial (if vowel-pos (substring clean 0 vowel-pos) clean))
             (rest    (if vowel-pos (substring clean vowel-pos)   ""))
             (vowel   (if (string-empty-p rest) "" (substring rest 0 1)))
             (tail    (if (string-empty-p rest) "" (substring rest 1)))
             ;; Suffix:  longest match for `ng' first, then single chars.
             (suffix-2 (and (>= (length tail) 2)
                            (member (substring tail 0 2)
                                    '("ng"))
                            (substring tail 0 2)))
             (suffix (or suffix-2
                         (and (>= (length tail) 1)
                              (substring tail 0 1))))
             (after-suffix (if suffix
                               (substring tail (length suffix))
                             tail))
             (post-suffix (and (>= (length after-suffix) 1)
                               (substring after-suffix 0 1))))
        (list :initial (or initial "")
              :vowel (or vowel "")
              :suffix (or suffix "")
              :post-suffix (or post-suffix "")))))))

(defun tibetan-phonetics--parse-cluster (cluster)
  "Parse initial CLUSTER string into a plist of components.

Returns `(:prefix P :super S :root R :subscript SUB)'.  Each
slot is a string (possibly empty).  Greedy left-to-right;
recognises the standard Tibetan prefix / superscript / root /
subscript hierarchy."
  (let* ((s cluster)
         (prefix "")
         (super "")
         (root "")
         (subscript ""))
    ;; Try prefix.  Two patterns:
    ;;
    ;;   (A) prefix + super + root   — e.g. `brgy' = b + r + g + (y).
    ;;       Detected by checking whether the REST starts with a
    ;;       valid (super . root) combo;  the prefix gets stripped
    ;;       and the super check below catches the r.
    ;;
    ;;   (B) prefix + root            — the simple case, e.g. `bk' = b + k.
    ;;       Detected by looking up (first . next-root) in
    ;;       `--valid-prefix-combos'.
    ;;
    ;; Without (A), syllables like `brgyud' (which want to parse as
    ;; b-prefix + r-super + g-root + y-sub + u + d) get stuck:  the
    ;; greedy root finder grabs `r' first;  `b' isn't a valid prefix
    ;; before r in the simple table;  the cluster passes through with
    ;; `b' and `r' intact (output `brgyü' instead of `gyü').
    (when (and (> (length s) 1)
               (member (substring s 0 1)
                       '("b" "d" "g" "m" "'")))
      (let* ((first (substring s 0 1))
             (rest  (substring s 1))
             (rest-root (tibetan-phonetics--starts-with-root rest))
             (case-a-fires
              (and rest-root
                   (member rest-root '("r" "l" "s"))
                   (> (length rest) (length rest-root))
                   (let ((deeper (tibetan-phonetics--starts-with-root
                                  (substring rest (length rest-root)))))
                     (and deeper
                          (member (cons rest-root deeper)
                                  tibetan-phonetics--valid-super-combos)))))
             (case-b-fires
              (and rest-root
                   (member (cons first rest-root)
                           tibetan-phonetics--valid-prefix-combos))))
        (when (or case-a-fires case-b-fires)
          (setq prefix first)
          (setq s rest))))
    ;; Try superscript.
    (when (> (length s) 1)
      (let* ((first (substring s 0 1))
             (rest  (substring s 1))
             (rest-root (tibetan-phonetics--starts-with-root rest)))
        (when (and rest-root
                   (member (cons first rest-root)
                           tibetan-phonetics--valid-super-combos))
          (setq super first)
          (setq s rest))))
    ;; Root (greedy).
    (let ((r (tibetan-phonetics--starts-with-root s)))
      (cond
       (r
        (setq root r)
        (setq s (substring s (length r))))
       (t
        ;; No consonant root recognised — pass cluster through verbatim
        ;; as the "root" for graceful degradation.
        (setq root s)
        (setq s ""))))
    (setq subscript s)
    (list :prefix prefix :super super :root root :subscript subscript)))

;; ============================================================================
;; THL phonetic rules
;; ============================================================================

(defconst tibetan-phonetics--root-thl
  '(;; Single-phoneme mappings, root → THL initial.
    ("k" . "k") ("kh" . "kh") ("g" . "g") ("ng" . "ng")
    ("c" . "ch") ("ch" . "ch") ("j" . "j") ("ny" . "ny")
    ("t" . "t") ("th" . "th") ("d" . "d") ("n" . "n")
    ("p" . "p") ("ph" . "ph") ("b" . "b") ("m" . "m")
    ("ts" . "ts") ("tsh" . "tsh") ("dz" . "dz") ("w" . "w")
    ("zh" . "zh") ("z" . "z") ("'" . "") ("y" . "y")
    ("r" . "r") ("l" . "l") ("sh" . "sh") ("s" . "s") ("h" . "h")
    ("lh" . "lh") ("hr" . "hr"))
  "Wylie ROOT consonant → THL initial.")

(defun tibetan-phonetics--root-thl (root)
  "THL initial for ROOT, or ROOT itself if not in the table."
  (or (cdr (assoc root tibetan-phonetics--root-thl)) root))

(defconst tibetan-phonetics--cluster-overrides
  ;; Special clusters whose combined sound differs from
  ;; root-alone + subscript-modification rules.  Keyed by the
  ;; LEFT-STRIPPED cluster (root + subscript, prefix and
  ;; superscript already removed).  Lookup happens BEFORE the
  ;; generic subscript rules.
  '(;; -y subscript palatalisations
    ("py"   . "ch")    ("phy"  . "ch")    ("by"   . "j")
    ("my"   . "ny")
    ("ky"   . "ky")    ("khy"  . "khy")   ("gy"   . "gy")
    ;; -r subscript retroflexes (the famous "tr" series)
    ("kr"   . "tr")    ("khr"  . "thr")   ("gr"   . "dr")
    ("tr"   . "tr")    ("thr"  . "thr")   ("dr"   . "dr")
    ("pr"   . "tr")    ("phr"  . "thr")   ("br"   . "dr")
    ("sr"   . "s")     ("hr"   . "hr")
    ;; -l subscript: the consonant generally drops, l surfaces
    ("kl"   . "l")     ("gl"   . "l")     ("bl"   . "l")
    ("rl"   . "l")     ("sl"   . "l")
    ("zl"   . "d")     ;; classic exception: zla → da
    ;; -w subscript: w is silent in modern Lhasa
    ("kw"   . "k")     ("khw"  . "kh")    ("gw"   . "g")
    ("cw"   . "ch")    ("nyw"  . "ny")    ("tw"   . "t")
    ("dw"   . "d")     ("zw"   . "z")     ("rw"   . "r")
    ("shw"  . "sh")    ("sw"   . "s")     ("hw"   . "h"))
  "Root+subscript cluster → THL initial.  Looked up BEFORE
generic subscript rules so palatalisations and retroflexes
land correctly.")

(defun tibetan-phonetics--initial-cluster-thl (root subscript)
  "Convert ROOT + SUBSCRIPT to a THL initial string.

Tries the override table first (handles palatalisations and
retroflexes);  otherwise concatenates root's THL value with
subscript verbatim (graceful degradation when subscript is
something unusual)."
  (let ((combined (concat root subscript)))
    (or (cdr (assoc combined tibetan-phonetics--cluster-overrides))
        ;; No override — root alone via simple map, drop subscript
        ;; when it's a known modifier we already handled, else
        ;; concat (degradation path).
        (cond
         ((member subscript '("y" "r" "l" "w" ""))
          (tibetan-phonetics--root-thl root))
         (t
          (concat (tibetan-phonetics--root-thl root) subscript))))))

(defconst tibetan-phonetics--umlaut-table
  '(("a" . "ä") ("o" . "ö") ("u" . "ü") ("e" . "e") ("i" . "i"))
  "Vowel + umlauting-suffix → umlauted vowel.
Triggered by suffixes `i' / `e' / `n' / `l' / `d' / `s' AND by
the genitive `'i' compound suffix.

Uses German-orthography ä / ö / ü diacritics throughout —
matches the strict Germano & Tournadre 2003 THL convention.
Some casual transcriptions use `e' for the a-umlaut;  we keep
ä for consistency with ö / ü and to align with the user's
reading habit.")

(defun tibetan-phonetics--umlaut-vowel (vowel)
  "Return the umlauted form of VOWEL."
  (or (cdr (assoc vowel tibetan-phonetics--umlaut-table)) vowel))

(defconst tibetan-phonetics--umlauting-suffixes
  '("i" "e" "n" "l" "d" "s")
  "Suffixes that trigger vowel umlaut.")

(defun tibetan-phonetics--final-thl (vowel suffix post-suffix)
  "Compute the THL vowel + final-consonant for VOWEL + SUFFIX + POST-SUFFIX.

Umlaut is normally triggered ONLY by the suffix, never by the
post-suffix.  This matters for forms like `tshogs' (suffix `g',
post-suffix `s'):  the `g' blocks the `s'-driven umlaut, so the
vowel `o' stays unchanged and the final realises as `-k'.

EXCEPTION:  the genitive compound suffix `'i' (a-chung + i,
written `'i' in Wylie) DOES trigger umlaut on the stem vowel
and both characters are silent.  `pa'i' → `pä', `po'i' →
`pö', `bu'i' → `bü', etc.  Without this rule, every genitive-
ending word reads as if it had no genitive marker:  `chos kyi
rgyal po'i sa' (a high-frequency YBh construction) would
collapse from `chö kyi gyel pö sa' to `chö kyi gyel po sa'."
  (let* ((genitive-i (and (string= suffix "'") (string= post-suffix "i")))
         (umlaut (or (member suffix tibetan-phonetics--umlauting-suffixes)
                     genitive-i))
         (effective-vowel (if umlaut
                              (tibetan-phonetics--umlaut-vowel vowel)
                            vowel))
         (final-cons
          (cond
           ;; Kept finals
           ((string= suffix "ng") "ng")
           ((string= suffix "m")  "m")
           ;; -g + (silent post-suffix s) → -k
           ((and (string= suffix "g")
                 (member post-suffix '("" "s")))
            "k")
           ;; -b → -p (final devoicing)
           ((string= suffix "b") "p")
           ;; -n, -l (umlaut already applied) — visually keep for
           ;; reading cue (helps the student see the original
           ;; consonant structure).
           ((string= suffix "n") "n")
           ((string= suffix "l") "l")
           ;; -r:  silent in modern Lhasa (no visual)
           ((string= suffix "r") "")
           ;; Silent suffixes
           ((member suffix '("d" "s" "'" "")) "")
           ;; Unknown suffix — pass through for graceful degradation
           (t suffix))))
    (concat effective-vowel final-cons)))

;; ============================================================================
;; Curated thesaurus override
;; ============================================================================

(defun tibetan-phonetics--curated-override (wylie)
  "Return the curated `:phonetics:' value for WYLIE from the
thesaurus, or nil when absent / module unavailable.

Lets the user pin a specific phonetic rendering for tricky cases
(Madhyamaka terms, Sanskrit loanwords, monastic-tradition
readings) via the per-word zettel.  When the rule engine's
output is wrong for a word, the fix is to populate the zettel's
`:phonetics:' field rather than complicate the rules table."
  (when (and wylie (stringp wylie)
             (fboundp 'tibetan-thesaurus-lookup))
    (condition-case nil
        (let* ((entry (tibetan-thesaurus-lookup wylie))
               (phon (and entry (plist-get entry :phonetics))))
          (and phon (stringp phon)
               (not (string-empty-p (string-trim phon)))
               phon))
      (error nil))))

;; ============================================================================
;; Public entry points
;; ============================================================================

;;;###autoload
(defun tibetan-wylie-syllable-to-phonetic (wylie)
  "Convert a single-syllable Wylie string WYLIE to THL phonetic.

Returns the phonetic syllable as a string;  nil when WYLIE is
nil / empty.

Tries the curated thesaurus override first.  Falls back to the
rule engine:  parses into prefix / superscript / root /
subscript / vowel / suffix / post-suffix, computes the initial
cluster + vowel + final, composes the result.

When the syllable can't be parsed as Wylie (e.g. random Roman
text), the input is returned verbatim — graceful degradation
better than crashing the rendering pipeline."
  (when (and wylie (stringp wylie))
    (let ((clean (string-trim wylie)))
      (cond
       ((string-empty-p clean) "")
       ((tibetan-phonetics--curated-override clean))
       (t
        (condition-case nil
            (let* ((parsed-syl (tibetan-phonetics--parse-syllable clean))
                   (initial    (plist-get parsed-syl :initial))
                   (vowel      (plist-get parsed-syl :vowel))
                   (suffix     (plist-get parsed-syl :suffix))
                   (post       (plist-get parsed-syl :post-suffix))
                   (parsed-cluster
                    (tibetan-phonetics--parse-cluster initial))
                   (root      (plist-get parsed-cluster :root))
                   (subscript (plist-get parsed-cluster :subscript))
                   (thl-initial
                    (tibetan-phonetics--initial-cluster-thl
                     root subscript))
                   (thl-final
                    (tibetan-phonetics--final-thl vowel suffix post)))
              (concat thl-initial thl-final))
          (error clean)))))))

;;;###autoload
(defun tibetan-to-phonetics (text)
  "Convert TEXT (Tibetan Unicode OR Wylie) to a THL phonetic string.

Tibetan Unicode is detected by the presence of code-points in
the Tibetan block (U+0F00–U+0FFF) and run through
`tibetan-to-wylie-fixed' first.  Already-Wylie input is used
directly.

Splits on whitespace + tsheg (`་').  Punctuation (shad `།',
slash `/') is preserved verbatim — useful for keeping the
visual rhythm of a clause when reading aloud.  Each syllable
converts via `tibetan-wylie-syllable-to-phonetic'.

Returns the phonetic line as a single space-separated string.
Nil-safe."
  (when (and text (stringp text))
    (let* ((trimmed (string-trim text)))
      (cond
       ((string-empty-p trimmed) "")
       (t
        ;; Detect Tibetan Unicode and convert to Wylie first.
        (let* ((wylie-input
                (if (string-match-p "[ༀ-࿿]" trimmed)
                    (if (fboundp 'tibetan-to-wylie-fixed)
                        (or (ignore-errors
                              (tibetan-to-wylie-fixed trimmed))
                            trimmed)
                      trimmed)
                  trimmed))
               ;; Replace tsheg with space so split picks them up.
               (normalised (replace-regexp-in-string "་+" " " wylie-input))
               ;; Tokenise on whitespace, keeping punctuation chunks
               ;; visible to the iterator.
               (tokens (split-string normalised "[ \t\n]+" t)))
          (mapconcat
           (lambda (tok)
             (cond
              ;; Pure punctuation chunk — pass through.
              ((string-match-p "\\`[།༎༏/]+\\'" tok) tok)
              ;; Mixed:  strip leading + trailing punctuation in two
              ;; explicit passes (more robust than a single non-greedy
              ;; regex, which the engine resolves by greedily
              ;; consuming the middle).  Convert the syllable core,
              ;; re-attach the punctuation.
              (t
               (let* ((s tok)
                      (leading (and (string-match "\\`[།༎༏/]+" s)
                                    (match-string 0 s)))
                      (s1 (if leading
                              (substring s (length leading))
                            s))
                      (trailing (and (string-match "[།༎༏/]+\\'" s1)
                                     (match-string 0 s1)))
                      (core (if trailing
                                (substring s1 0
                                           (- (length s1)
                                              (length trailing)))
                              s1)))
                 (concat (or leading "")
                         (or (and (not (string-empty-p core))
                                  (tibetan-wylie-syllable-to-phonetic
                                   core))
                             core)
                         (or trailing ""))))))
           tokens
           " ")))))))

(provide 'tibetan-phonetics)
;;; tibetan-phonetics.el ends here
