;;; tibetan-sanskrit-script-test.el --- Tests for Devanagari→IAST -*- lexical-binding: t -*-

;;; Commentary:
;; Sanskrit-Kaskade B2 (2026-09-24).  Pure tests — strings only.

;;; Code:

(require 'ert)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-sanskrit-script)

(ert-deftest tibetan-sanskrit-script-consonant-virama ()
  "Consonant + virāma suppresses the inherent a; conjuncts chain."
  ;; धर्म = dha r(virāma) ma → dharma
  (should (equal "dharma"
                 (tibetan-sanskrit-script-devanagari-to-iast "धर्म")))
  ;; सत्त्व = sa t(v) t(v) va → sattva
  (should (equal "sattva"
                 (tibetan-sanskrit-script-devanagari-to-iast "सत्त्व")))
  ;; Word-final virāma: तत् → tat
  (should (equal "tat"
                 (tibetan-sanskrit-script-devanagari-to-iast "तत्"))))

(ert-deftest tibetan-sanskrit-script-inherent-a ()
  "A bare consonant carries the inherent a."
  (should (equal "na ca"
                 (tibetan-sanskrit-script-devanagari-to-iast "न च")))
  (should (equal "bhagavat"
                 (tibetan-sanskrit-script-devanagari-to-iast "भगवत्"))))

(ert-deftest tibetan-sanskrit-script-vowel-signs ()
  "Dependent vowel signs replace the inherent a; independent vowels
stand alone."
  ;; बुद्ध → buddha; धी → dhī; गुरु → guru
  (should (equal "buddha"
                 (tibetan-sanskrit-script-devanagari-to-iast "बुद्ध")))
  (should (equal "dhī"
                 (tibetan-sanskrit-script-devanagari-to-iast "धी")))
  (should (equal "guru"
                 (tibetan-sanskrit-script-devanagari-to-iast "गुरु")))
  ;; Vocalic ṛ as sign and independent: कृत → kṛta; ऋषि → ṛṣi
  (should (equal "kṛta"
                 (tibetan-sanskrit-script-devanagari-to-iast "कृत")))
  (should (equal "ṛṣi"
                 (tibetan-sanskrit-script-devanagari-to-iast "ऋषि")))
  ;; Diphthongs: गौतम → gautama; एक → eka
  (should (equal "gautama"
                 (tibetan-sanskrit-script-devanagari-to-iast "गौतम")))
  (should (equal "eka"
                 (tibetan-sanskrit-script-devanagari-to-iast "एक"))))

(ert-deftest tibetan-sanskrit-script-anusvara-visarga ()
  "Anusvāra → ṃ, visarga → ḥ, candrabindu → m̐."
  ;; संस्कृत → saṃskṛta
  (should (equal "saṃskṛta"
                 (tibetan-sanskrit-script-devanagari-to-iast "संस्कृत")))
  ;; दुःख → duḥkha
  (should (equal "duḥkha"
                 (tibetan-sanskrit-script-devanagari-to-iast "दुःख")))
  ;; नमः → namaḥ
  (should (equal "namaḥ"
                 (tibetan-sanskrit-script-devanagari-to-iast "नमः"))))

(ert-deftest tibetan-sanskrit-script-avagraha-danda ()
  "Avagraha → apostrophe; daṇḍas pass through (the importer splits
on them — script-neutral punctuation)."
  ;; सो ऽपि → so 'pi
  (should (equal "so 'pi"
                 (tibetan-sanskrit-script-devanagari-to-iast "सो ऽपि")))
  (should (equal "gataḥ। punaḥ॥"
                 (tibetan-sanskrit-script-devanagari-to-iast
                  "गतः। पुनः॥"))))

(ert-deftest tibetan-sanskrit-script-digits ()
  "Devanagari digits map to ASCII."
  (should (equal "24.18"
                 (tibetan-sanskrit-script-devanagari-to-iast "२४.१८"))))

(ert-deftest tibetan-sanskrit-script-normalize-idempotent-on-iast ()
  "Pure IAST passes through byte-identically (idempotence — the
importer may be run on already-normalized text)."
  (let ((iast "svabhāvo hi prakṛtir akṛtrimā | dharmāṇāṃ śūnyatā ||"))
    (should (equal iast (tibetan-sanskrit-script-normalize iast)))
    (should (equal (tibetan-sanskrit-script-normalize iast)
                   (tibetan-sanskrit-script-normalize
                    (tibetan-sanskrit-script-normalize iast))))))

(ert-deftest tibetan-sanskrit-script-normalize-mixed-input ()
  "Mixed Devanagari/IAST input normalizes to one IAST form; line
structure (pāda breaks) survives untouched."
  (should (equal "na svato nāpi parato\ndharmāṇāṃ śūnyatā"
                 (tibetan-sanskrit-script-normalize
                  "न स्वतो नापि परतो\ndharmāṇāṃ śūnyatā")))
  ;; Same line in both scripts → same normalization.
  (should (equal (tibetan-sanskrit-script-normalize "धर्माणां शून्यता")
                 (tibetan-sanskrit-script-normalize
                  "dharmāṇāṃ śūnyatā"))))

(ert-deftest tibetan-sanskrit-script-nil-safe ()
  "nil and empty input degrade quietly."
  (should-not (tibetan-sanskrit-script-devanagari-to-iast nil))
  (should-not (tibetan-sanskrit-script-normalize nil))
  (should (equal "" (tibetan-sanskrit-script-devanagari-to-iast "")))
  (should (equal "" (tibetan-sanskrit-script-normalize ""))))

(provide 'tibetan-sanskrit-script-test)

;;; tibetan-sanskrit-script-test.el ends here
