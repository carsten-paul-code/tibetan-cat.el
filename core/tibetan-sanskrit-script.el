;;; tibetan-sanskrit-script.el --- Devanagari→IAST transliteration -*- lexical-binding: t -*-

;;; Commentary:
;; Sanskrit-Kaskade B2 (2026-09-24).  Pure, deterministic
;; Devanagari→IAST transliteration for the Sanskrit source importer:
;; Carsten's e-texts come mixed (IAST editions, Devanagari editions),
;; the tool normalizes everything to IAST at import time.  No
;; buffers, no files, no network — string in, string out, so batch
;; and interactive runs are byte-identical by construction.
;;
;; Scope: classical Sanskrit as found in Buddhist śāstra e-texts.
;; Covered: consonant + virāma vs. inherent a, dependent vowel
;; signs, independent vowels, anusvāra (ṃ), visarga (ḥ),
;; candrabindu (m̐), avagraha ('), daṇḍa ।/॥ (kept — script-neutral
;; punctuation the importer splits on), Devanagari digits.
;; NOT covered (out of scope): nukta forms (क़ …), Vedic accents,
;; IAST→Devanagari (the reverse direction is not built).

;;; Code:

(require 'cl-lib)
(require 'ucs-normalize)

(defconst tibetan-sanskrit-script--consonants
  '((?क . "k")  (?ख . "kh") (?ग . "g")  (?घ . "gh") (?ङ . "ṅ")
    (?च . "c")  (?छ . "ch") (?ज . "j")  (?झ . "jh") (?ञ . "ñ")
    (?ट . "ṭ")  (?ठ . "ṭh") (?ड . "ḍ")  (?ढ . "ḍh") (?ण . "ṇ")
    (?त . "t")  (?थ . "th") (?द . "d")  (?ध . "dh") (?न . "n")
    (?प . "p")  (?फ . "ph") (?ब . "b")  (?भ . "bh") (?म . "m")
    (?य . "y")  (?र . "r")  (?ल . "l")  (?व . "v")
    (?श . "ś")  (?ष . "ṣ")  (?स . "s")  (?ह . "h")
    (?ळ . "ḻ"))
  "Devanagari consonant → IAST base (without the inherent a).")

(defconst tibetan-sanskrit-script--independent-vowels
  '((?अ . "a")  (?आ . "ā")  (?इ . "i")  (?ई . "ī")
    (?उ . "u")  (?ऊ . "ū")  (?ऋ . "ṛ")  (?ॠ . "ṝ")
    (?ऌ . "ḷ")  (?ॡ . "ḹ")  (?ए . "e")  (?ऐ . "ai")
    (?ओ . "o")  (?औ . "au"))
  "Independent (initial) Devanagari vowels → IAST.")

(defconst tibetan-sanskrit-script--vowel-signs
  '((?ा . "ā")  (?ि . "i")  (?ी . "ī")  (?ु . "u")  (?ू . "ū")
    (?ृ . "ṛ")  (?ॄ . "ṝ")  (?ॢ . "ḷ")  (?ॣ . "ḹ")
    (?े . "e")  (?ै . "ai") (?ो . "o")  (?ौ . "au"))
  "Dependent Devanagari vowel signs (mātrās) → IAST.")

(defconst tibetan-sanskrit-script--signs
  '((?ं . "ṃ")  (?ः . "ḥ")  (?ँ . "m̐")  (?ऽ . "'"))
  "Anusvāra / visarga / candrabindu / avagraha → IAST.")

(defconst tibetan-sanskrit-script--virama ?्
  "The Devanagari virāma (vowel killer).")

(defun tibetan-sanskrit-script-devanagari-to-iast (str)
  "STR with every Devanagari character transliterated to IAST.
Non-Devanagari characters (including existing IAST, whitespace and
the daṇḍas ।/॥) pass through untouched, so mixed input is safe and
the function is idempotent on pure IAST.  nil-safe.

Consonant logic: a consonant emits its base form, then the NEXT
character decides the vowel — a dependent vowel sign replaces the
inherent a, the virāma suppresses it (conjuncts, word-final stops),
anything else (another consonant, space, end of string) leaves the
inherent a in place."
  (when str
    (let ((out nil)
          (i 0)
          (len (length str)))
      (while (< i len)
        (let* ((ch (aref str i))
               (cons-entry (assq ch tibetan-sanskrit-script--consonants)))
          (cond
           (cons-entry
            (push (cdr cons-entry) out)
            (let* ((next (and (< (1+ i) len) (aref str (1+ i))))
                   (sign (and next
                              (assq next
                                    tibetan-sanskrit-script--vowel-signs))))
              (cond
               (sign
                (push (cdr sign) out)
                (cl-incf i))
               ((and next (eq next tibetan-sanskrit-script--virama))
                (cl-incf i))
               (t (push "a" out)))))
           ((assq ch tibetan-sanskrit-script--independent-vowels)
            (push (cdr (assq ch tibetan-sanskrit-script--independent-vowels))
                  out))
           ((assq ch tibetan-sanskrit-script--signs)
            (push (cdr (assq ch tibetan-sanskrit-script--signs)) out))
           ((<= ?० ch ?९)
            (push (char-to-string (+ ?0 (- ch ?०))) out))
           ;; Stray vowel sign / virāma without a consonant (defective
           ;; input): drop the virāma, emit the sign's vowel.
           ((assq ch tibetan-sanskrit-script--vowel-signs)
            (push (cdr (assq ch tibetan-sanskrit-script--vowel-signs))
                  out))
           ((eq ch tibetan-sanskrit-script--virama))
           (t (push (char-to-string ch) out))))
        (cl-incf i))
      (apply #'concat (nreverse out)))))

(defun tibetan-sanskrit-script-normalize (str)
  "STR NFC-normalized with Devanagari transliterated to IAST.
The importer's single entry point for mixed IAST/Devanagari input.
Line structure survives untouched (pāda breaks are data).
Idempotent; nil-safe."
  (when str
    (tibetan-sanskrit-script-devanagari-to-iast
     (ucs-normalize-NFC-string str))))

(provide 'tibetan-sanskrit-script)

;;; tibetan-sanskrit-script.el ends here
