;;; demo-setup.el --- Quick demo of Tibetan CAT system

(message "Setting up Tibetan CAT demo...")

;; Load the system
(add-to-list 'load-path default-directory)
(load "tibetan-cat-mode")
(load "setup-tibetan-cat")

;; Create demo buffer with sample text
(defun demo-tibetan-cat ()
  "Start a demo of the Tibetan CAT system"
  (interactive)
  (let ((demo-text "
སེམས་ཅན་གྱི་དོན་དུ་ལུས་སྦྱིན་པའི་གཏམ་རྒྱུད།

བཅོམ་ལྡན་འདས་ཀྱིས་ཕྱག་འཚལ་ནས་གསོལ་པ་ནི།
སེམས་དཔའ་ཆེན་པོ་རྣམས་ཀྱིས་སེམས་ཅན་གྱི་དོན་ལ་
བསམ་པ་མཆིས་པས་རང་གི་ལུས་ལ་ཡང་མ་གཅེས་པར་
སྦྱིན་པ་ལ་སྦྱོར་བ་མཛད་པའི་གཏམ་རྒྱུད་ཞིག་གསུངས་སོ།།"))

    ;; Create demo buffer
    (switch-to-buffer "*Tibetan CAT Demo*")
    (erase-buffer)
    (insert demo-text)

    ;; Enable CAT mode
    (tibetan-cat-mode 1)

    ;; Load demo glossary
    (puthash "སེམས་ཅན་" '("sentient beings" "all living creatures") tibetan-cat-glossary)
    (puthash "བཅོམ་ལྡན་འདས་" '("Bhagavan" "Blessed One, epithet of Buddha") tibetan-cat-glossary)
    (puthash "སེམས་དཔའ་" '("bodhisattva" "enlightenment being") tibetan-cat-glossary)
    (puthash "ལུས་" '("body" "physical form") tibetan-cat-glossary)
    (puthash "སྦྱིན་པ་" '("giving/generosity" "one of six perfections") tibetan-cat-glossary)
    (puthash "གཏམ་རྒྱུད་" '("story/narrative" "tale or account") tibetan-cat-glossary)

    ;; Highlight particles
    (tibetan-cat-highlight-particles)

    ;; Show instructions
    (message "Tibetan CAT Demo loaded! Try:
C-c C-l = lookup word
C-c C-p = popup translation
C-c C-a = add annotation
C-c t a = analyze particles
Hover over blue text for particle info")))

;; Run demo
(demo-tibetan-cat)