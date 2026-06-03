;;; tibetan-wylie.el --- Wylie transliteration for Tibetan text -*- lexical-binding: t -*-

;;; Commentary:
;; Properly handles implicit 'a' vowels after each consonant in Tibetan syllables
;; Each consonant gets 'a' unless followed by an explicit vowel mark
;;
;; Usage:
;;   (tibetan-to-wylie-fixed "བར་") => "bar"
;;   (tibetan-to-wylie-fixed "པས") => "pas"
;;   (tibetan-to-wylie-fixed "གསད") => "gsad"

;;; Code:

(defun tibetan-safe-substring (str start &optional end)
  "Safely extract substring from STR between START and END.
Returns empty string if indices are out of range."
  (condition-case nil
      (if (not (stringp str))
          ""
        (let* ((len (length str))
               (s (max 0 (min start len)))
               (e (if end (max s (min end len)) len)))
          (if (and (integerp s)
                   (integerp e)
                   (<= 0 s)
                   (<= s e)
                   (<= e len))
              (substring str s e)
            "")))
    (error "")))

(defun tibetan-to-wylie-fixed (tibetan-text)
  "Convert Tibetan Unicode text to Wylie transliteration.
FIXED: Properly handles implicit \='a\=' vowels after each consonant."
  (condition-case err
      (let ((result "")
            (pos 0)
            (len (length tibetan-text)))

        (while (< pos len)
          ;; Safe substring extraction
          (let* ((char (tibetan-safe-substring tibetan-text pos (1+ pos))))

            ;; Check if current position is punctuation - handle it directly
            (if (and (> (length char) 0) (string-match-p "[་།༎༏༐༑༔ ]" char))
                ;; Handle punctuation immediately
                (progn
                  (cond
                   ((string= char "་") (setq result (concat result " ")))
                   ((string= char " ") (setq result (concat result " ")))
                   ((string= char "།") (setq result (concat result "/")))
                   ((string= char "༎") (setq result (concat result "//")))
                   (t (setq result (concat result char))))
                  (setq pos (1+ pos)))

              ;; Not punctuation, process as syllable
              (let* ((search-start (min (1+ pos) len))
                     (syllable-end (or (and (< search-start len)
                                           (string-match-p "་\\|།\\|༎\\|༏\\|༐\\|༑\\|༔\\| "
                                                          tibetan-text search-start))
                                      len))
                     (syllable (tibetan-safe-substring tibetan-text pos syllable-end))
                     (wylie-syllable (if (> (length syllable) 0)
                                        (condition-case nil
                                            (tibetan-syllable-to-wylie syllable)
                                          (error syllable))  ; On error, return original
                                      "")))

                (setq result (concat result wylie-syllable))
                ;; Move to syllable-end, next iteration will handle punctuation
                (setq pos (max (1+ pos) syllable-end))))))

        result)
    (error
     ;; On any error, return the original text or empty string
     (message "Wylie conversion error for '%s': %s" tibetan-text (error-message-string err))
     (or tibetan-text ""))))

(defun tibetan-is-prefix (char next-char)
  "Check if CHAR is a valid prefix before NEXT-CHAR in Tibetan.
Prefixes don't get implicit \='a\=' vowel."
  (let ((prefixes '(
        ;; ག prefix
        ("ག" . ("ཅ" "ཉ" "ཏ" "ད" "ན" "ཙ" "ཞ" "ཟ" "ཡ" "ཤ" "ས"))
        ;; ད prefix
        ("ད" . ("ཀ" "ག" "ང" "པ" "བ" "མ"))
        ;; བ prefix
        ("བ" . ("ཀ" "ག" "ཅ" "ཏ" "ད" "ཙ" "ཞ" "ཟ" "ཤ" "ས"))
        ;; མ prefix
        ("མ" . ("ཁ" "ག" "ང" "ཆ" "ཇ" "ཉ" "ཐ" "ད" "ན" "ཚ" "ཛ"))
        ;; འ prefix (can precede many consonants)
        ("འ" . ("ཀ" "ག" "ཁ" "ཆ" "ཇ" "ཐ" "ད" "ཕ" "བ" "ཚ" "ཛ"))
        )))
    (let ((valid-nexts (cdr (assoc char prefixes))))
      (and valid-nexts (member next-char valid-nexts)))))

(defun tibetan-syllable-to-wylie (syllable)
  "Convert a single Tibetan syllable to Wylie.
Handles implicit \='a\=' vowels correctly after each consonant.
Recognizes Tibetan syllable structure: [prefix] ROOT [subscript]
[vowel] [suffix]"
  (condition-case err
  ;; Character mappings with priority (longer matches first)
  (let ((consonant-stacks '(
        ;; Four-character stacks (must come before 3-char!)
        ("བརྒྱ" . "brgy") ("བསྒྱ" . "bsgy") ("བསྐྱ" . "bsky")
        ("བསྒྲ" . "bsgr") ("བསྐྲ" . "bskr")
        ;; Three-character stacks
        ("བརྒ" . "brg") ("བསྒ" . "bsg") ("བརྟ" . "brt") ("བསྟ" . "bst")
        ("བརྡ" . "brd") ("བསྡ" . "bsd")
        ("བསྐ" . "bsk")
        ;; Three-character stacks with ལ-headed roots (ba prefix + l-stack)
        ("བལྟ" . "blt") ("བལྡ" . "bld") ("བལྗ" . "blj")
        ;; Two-character stacks with subscripts (3-char total)
        ("སྨྲ" . "smr") ("སྤྲ" . "spr") ("སྦྲ" . "sbr") ("སྒྲ" . "sgr")
        ("སྐྲ" . "skr") ("སྣྲ" . "snr")
        ;; Two-character stacks
        ("སྐ" . "sk") ("སྒ" . "sg") ("སྔ" . "sng") ("སྙ" . "sny")
        ("སྟ" . "st") ("སྡ" . "sd") ("སྣ" . "sn") ("སྤ" . "sp")
        ("སྦ" . "sb") ("སྨ" . "sm") ("སྩ" . "sts") ("སྲ" . "sr")
        ("གྱ" . "gy") ("ཀྱ" . "ky") ("ཁྱ" . "khy") ("པྱ" . "py")
        ("ཕྱ" . "phy") ("བྱ" . "by") ("མྱ" . "my")
        ("རྔ" . "rng")                                  ; ra-mgo + nga (was missing)
        ("རྒ" . "rg") ("རྐ" . "rk") ("རྟ" . "rt") ("རྡ" . "rd")
        ("རྣ" . "rn") ("རྦ" . "rb") ("རྨ" . "rm") ("རྩ" . "rts")
        ("རྫ" . "rdz") ("རྗ" . "rj") ("རྙ" . "rny") ("རླ" . "rl")
        ("ལྟ" . "lt") ("ལྡ" . "ld") ("ལྗ" . "lj") ("ལྕ" . "lc")
        ("དྲ" . "dr") ("དྭ" . "dw") ("ཕྲ" . "phr") ("ཁྲ" . "khr")
        ("གྲ" . "gr") ("ཀྲ" . "kr") ("ཏྲ" . "tr") ("ཐྲ" . "thr") ("བྲ" . "br")
        ("རྔྱ" . "rngy") ("རྒྱ" . "rgy") ("རྐྱ" . "rky") ("རྨྱ" . "rmy")
        ("སྒྱ" . "sgy") ("སྐྱ" . "sky") ("སྤྱ" . "spy") ("སྦྱ" . "sby")
        ("གྲྭ" . "grw")
        ;; NOTE: `("ཀྲུ" . "kru")' and `("དྲུ" . "dru")' were removed
        ;; 2026-04-22.  They baked the `u' vowel into the stack's wylie
        ;; output, but the implicit-`a'-adding logic downstream can't
        ;; tell the difference between a vowel-embedded wylie and a
        ;; consonant-only wylie.  Result: `དྲུག' (stack + vowel +
        ;; suffix) was being matched as `དྲུ' (len=3 stack → "dru")
        ;; + `ག' (suffix).  No vowel-after followed the 3-stack (the
        ;; next Tibetan char was the suffix `ག'), so the is-root
        ;; branch added an implicit `a' → "dru" + "a" + "g" = "druag".
        ;;
        ;; Letting `དྲུག' decompose naturally as `དྲ' (2-char stack,
        ;; wylie "dr") + `ུ' (vowel, wylie "u") + `ག' (suffix,
        ;; wylie "g") gives "drug" correctly without any special-
        ;; casing.  `གྲྭ' stays — its `ྭ' is a subjoined consonant
        ;; (wa-zur), not a vowel sign, so the implicit-`a' logic
        ;; handles it correctly (`གྲྭ' alone → `grwa', with vowel
        ;; sign after → `grwu' etc.)
        ;; Consonant + subscript ལ (la-btags) - missing stacks
        ("གླ" . "gl") ("བླ" . "bl") ("ཟླ" . "zl") ("སླ" . "sl")
        ("དབླ" . "dbl") ("ཀླ" . "kl")
        ;; Consonant + subscript ྭ (wa-zur) - common combinations
        ("རྭ" . "rw") ("ཀྭ" . "kw") ("གྭ" . "gw") ("ཁྭ" . "khw")
        ("ཉྭ" . "nyw") ("ཏྭ" . "tw") ("ཐྭ" . "thw") ("ནྭ" . "nw")
        ("ཙྭ" . "tsw") ("ཚྭ" . "tshw") ("ཞྭ" . "zhw") ("ཟྭ" . "zw")
        ("ཤྭ" . "shw") ("སྭ" . "sw") ("ཧྭ" . "hw")
        ))
        (single-consonants '(
        ("ཀ" . "k") ("ཁ" . "kh") ("ག" . "g") ("ང" . "ng")
        ("ཅ" . "c") ("ཆ" . "ch") ("ཇ" . "j") ("ཉ" . "ny")
        ("ཏ" . "t") ("ཐ" . "th") ("ད" . "d") ("ན" . "n")
        ("པ" . "p") ("ཕ" . "ph") ("བ" . "b") ("མ" . "m")
        ("ཙ" . "ts") ("ཚ" . "tsh") ("ཛ" . "dz") ("ཝ" . "w")
        ("ཞ" . "zh") ("ཟ" . "z") ("འ" . "'") ("ཡ" . "y")
        ("ར" . "r") ("ལ" . "l") ("ཤ" . "sh") ("ས" . "s")
        ("ཧ" . "h") ("ཨ" . "a")
        ))
        (subjoined '(
        ("ྱ" . "y") ("ྲ" . "r") ("ླ" . "l") ("ྭ" . "w")
        ))
        (vowels '(
        ("ི" . "i") ("ུ" . "u") ("ེ" . "e") ("ོ" . "o")
        ("ཱ" . "A") ("ཱི" . "I") ("ཱུ" . "U") ("ཻ" . "ai") ("ཽ" . "au")
        ))
        (final-marks '(
        ("ྀ" . "-i") ("ཾ" . "M") ("ྂ" . "~M") ("ཿ" . "H")
        ))
        (result "")
        (pos 0)
        (is-first-consonant t)
        (root-seen nil))  ; Track whether we've processed the root consonant

    ;; Process syllable character by character
    (while (< pos (length syllable))
      (let ((matched nil)
            (match-length 0)
            (match-wylie nil)
            (is-consonant nil)
)

        ;; Try to match longest possible sequence first (4, 3, 2, then 1 character)
        (dolist (len '(4 3 2 1))
          (when (and (not matched) (<= (+ pos len) (length syllable)))
            (let ((substr (tibetan-safe-substring syllable pos (+ pos len))))

              ;; Try consonant stacks
              (dolist (pair consonant-stacks)
                (when (and (not matched) (string= substr (car pair)))
                  (setq matched t)
                  (setq match-length len)
                  (setq match-wylie (cdr pair))
                  (setq is-consonant t)))

              ;; Try single consonants
              (dolist (pair single-consonants)
                (when (and (not matched) (string= substr (car pair)))
                  (setq matched t)
                  (setq match-length len)
                  (setq match-wylie (cdr pair))
                  (setq is-consonant t)))

              ;; Try subjoined
              (dolist (pair subjoined)
                (when (and (not matched) (string= substr (car pair)))
                  (setq matched t)
                  (setq match-length len)
                  (setq match-wylie (cdr pair))
                  (setq is-consonant t)))

              ;; Try vowels
              (dolist (pair vowels)
                (when (and (not matched) (string= substr (car pair)))
                  (setq matched t)
                  (setq match-length len)
                  (setq match-wylie (cdr pair))
                  (ignore is-consonant)))  ;; vowel matched

              ;; Try final marks
              (dolist (pair final-marks)
                (when (and (not matched) (string= substr (car pair)))
                  (setq matched t)
                  (setq match-length len)
                  (setq match-wylie (cdr pair)))))))

        (if matched
            (progn
              ;; Add the matched Wylie
              (setq result (concat result match-wylie))

              ;; If this was a consonant, check if we need to add implicit 'a'
              (when is-consonant
                (let* ((next-pos (+ pos match-length))
                       (has-vowel-after nil)
                       (is-prefix nil)
                       (is-root nil)
                       (current-char (tibetan-safe-substring syllable pos (1+ pos))))

                  ;; ===== STEP 1: Check if this consonant is a prefix =====
                  ;; Only single-character consonants can be prefixes
                  ;; A consonant is a prefix ONLY if:
                  ;; 1. It's the first consonant
                  ;; 2. It's a valid prefix for the next consonant
                  ;; 3. Either: there are 3+ consonants, OR there's a vowel mark after position 2
                  ;; This prevents treating root+suffix (like དང་ dang) as prefix+root
                  (when (and (< next-pos (length syllable))
                            is-first-consonant
                            (= match-length 1))
                    (let ((next-char (tibetan-safe-substring syllable next-pos (1+ next-pos)))
                          (consonant-count 0)
                          (has-vowel-after-second nil))
                      ;; Count total consonants in syllable.
                      ;; Include BOTH the main consonant block (U+0F40-U+0F6C)
                      ;; AND the subjoined-consonant block (U+0F90-U+0FBC).
                      ;; Without the subjoined range, syllables like `འདྲ'
                      ;; (U+0F60 U+0F51 U+0FB2) count as only 2 consonants
                      ;; even though `ྲ' (U+0FB2) is a genuine consonant —
                      ;; making the prefix detector fail the `>= 3 consonants'
                      ;; threshold and mis-identify `འ' as a root rather
                      ;; than a prefix.  Result was `'adra' instead of `'dra'.
                      (let ((temp-pos 0)
                            (seen-consonants 0))
                        (while (< temp-pos (length syllable))
                          (let ((temp-char (tibetan-safe-substring syllable temp-pos (1+ temp-pos))))
                            (when (let ((cp (string-to-char temp-char)))
                                    (or (and (>= cp #x0F40) (<= cp #x0F6C))
                                        (and (>= cp #x0F90) (<= cp #x0FBC))))
                              (setq consonant-count (1+ consonant-count))
                              (setq seen-consonants (1+ seen-consonants)))
                            ;; Check for vowel mark after second consonant
                            (when (and (= seen-consonants 2)
                                      (member temp-char '("ི" "ུ" "ེ" "ོ" "ཱ")))
                              (setq has-vowel-after-second t)))
                          (setq temp-pos (1+ temp-pos))))

                      ;; Prefix ONLY if:
                      ;; - Valid prefix combination AND
                      ;; - Either 3+ consonants OR vowel after second consonant
                      ;; This ensures 2-consonant syllables without vowels (like དང) are root+suffix
                      (when (and (tibetan-is-prefix current-char next-char)
                                (or (>= consonant-count 3)
                                    has-vowel-after-second))
                        (setq is-prefix t))))

                  ;; ===== STEP 2: Determine if this is ROOT or SUFFIX =====
                  (cond
                   ;; Multi-character stacks are ALWAYS the root (never prefix or suffix)
                   ((> match-length 1)
                    (setq is-root t)
                    (setq root-seen t))

                   ;; If this is a prefix, it's not the root (root comes next)
                   (is-prefix
                    nil)  ; Don't set root-seen yet

                   ;; If we haven't seen the root yet, THIS is the root
                   ((not root-seen)
                    (setq is-root t)
                    (setq root-seen t))

                   ;; Otherwise, we've already seen the root, so this is a suffix
                   (t
                    nil))  ; suffix position

                  ;; ===== STEP 3: Check for vowel marks after this consonant =====
                  (when (< next-pos (length syllable))
                    (dolist (pair vowels)
                      (when (and (not has-vowel-after)
                                (<= (+ next-pos (length (car pair))) (length syllable)))
                        (let ((next-substr (tibetan-safe-substring syllable next-pos
                                                     (+ next-pos (length (car pair))))))
                          (when (string= next-substr (car pair))
                            (setq has-vowel-after t))))))

                  ;; ===== STEP 4: Check for final marks (no 'a' before final marks) =====
                  (when (< next-pos (length syllable))
                    (dolist (pair final-marks)
                      (when (and (not has-vowel-after)
                                (<= (+ next-pos (length (car pair))) (length syllable)))
                        (let ((next-substr (tibetan-safe-substring syllable next-pos
                                                     (+ next-pos (length (car pair))))))
                          (when (string= next-substr (car pair))
                            (setq has-vowel-after t))))))

                  ;; ===== STEP 5: Add implicit 'a' =====
                  ;; Only ROOT consonants get 'a' (unless followed by vowel mark or final mark)
                  ;; NEVER add 'a' to: prefix, suffix, or consonants followed by vowels
                  ;;
                  ;; SPECIAL CASE — ཨ (a-chen / vowel carrier):
                  ;; The mapping emits "a" for ཨ (line 151).  When ཨ is
                  ;; followed by a vowel sign the "a" must be *removed*
                  ;; because ཨ is merely the carrier — the vowel sign
                  ;; alone determines the syllable value (ཨོ → "o", not "ao").
                  ;; When ཨ is bare (no vowel after), the "a" stays — it IS
                  ;; the vowel.  No extra implicit 'a' is ever added for ཨ.
                  (when (and is-root (string= current-char "ཨ") has-vowel-after)
                    ;; Strip the trailing "a" that the consonant mapping added
                    (setq result (substring result 0 (- (length result) 1))))
                  (when (and is-root
                             (not has-vowel-after)
                             (not (string= current-char "ཨ")))
                    (setq result (concat result "a")))

                  (setq is-first-consonant nil)))

              (setq pos (+ pos match-length)))

          ;; No match, skip this character
          (setq pos (1+ pos)))))

    result)
  (error
   ;; On any error, return empty string - the caller will handle it
   (message "Syllable-to-Wylie error for '%s': %s" syllable (error-message-string err))
   "")))

;; Alias for backward compatibility
(defalias 'tibetan-to-wylie 'tibetan-to-wylie-fixed)

(provide 'tibetan-wylie)
;;; tibetan-wylie.el ends here
