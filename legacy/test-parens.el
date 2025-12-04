(defun test-function ()
  (interactive)
  (let* ((var1 "value1")
         (var2 "value2"))

    (unless var1
      (error "Error"))

    (when (somefunc)
      (let ((inner1 "val1"))
        (action1)
        (action2))

      (let ((inner2 "val2")
            (inner3 "val3"))

        (action3)
        (action4)
        (message "Done")))))

(provide 'test-parens)
