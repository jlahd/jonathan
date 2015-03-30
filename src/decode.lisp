(in-package :cl-user)
(defpackage jonathan.decode
  (:use :cl
        :jonathan.util
        :proc-parse)
  (:export :parse))
(in-package :jonathan.decode)

(defun parse (string &key (as :plist))
  (declare (type simple-string string))
  (with-string-parsing (string)
    (macrolet ((skip-spaces ()
                 `(skip* #\Space))
               (skip?-with-spaces (char)
                 `(progn
                    (skip-spaces)
                    (skip? ,char)
                    (skip-spaces)))
               (skip?-or-eof (char)
                 `(or (skip? ,char) (eofp))))
      (labels ((dispatch ()
                 (skip-spaces)
                 (match-case
                  ("{" (read-object))
                  ("\"" (read-string))
                  ("[" (read-array))
                  ("true" t)
                  ("false" nil)
                  ("null" nil)
                  (otherwise (read-number))))
               (read-object ()
                 (skip-spaces)
                 (loop until (skip?-or-eof #\})
                       with first = t
                       for key = (progn (advance*) (read-string))
                       for value = (progn (skip-spaces) (advance*) (skip-spaces) (dispatch))
                       do (skip?-with-spaces #\,)
                       when (and first (eq as :jsown))
                         collecting (progn (setq first nil) :obj)
                       if (or (eq as :alist) (eq as :jsown))
                         collecting (cons key value)
                       else
                         nconc (list (make-keyword key) value)))
               (read-string ()
                 (if (eofp)
                     ""
                     (let ((start (pos))
                           (escaped-count 0))
                       (declare (type fixnum start escaped-count))
                       (loop when (char= (current) #\\)
                               do (incf escaped-count)
                                  (or (advance*) (return))
                             while (and (advance*)
                                        (char/= #\" (current))))
                       (prog1
                           (if (= escaped-count 0)
                               (subseq string start (pos))
                               (read-string-with-escaping start escaped-count))
                         (skip? #\")))))
               (read-string-with-escaping (start escaped-count)
                 (declare (optimize (speed 3) (debug 0) (safety 0)))
                 (loop with result = (make-array (- (pos) start escaped-count)
                                                 :element-type 'character
                                                 :adjustable nil)
                       with result-index = 0
                       with escaped-p
                       for index from start below (pos)
                       for char = (char string index)
                       if escaped-p
                         do (setf escaped-p nil)
                            (setf (char result result-index)
                                  (case char
                                    (#\b #\Backspace)
                                    (#\f #\Linefeed)
                                    (#\n #\Linefeed)
                                    (#\r #\Return)
                                    (#\t #\Tab)
                                    (t char)))
                            (incf result-index)
                       else
                         if (char= char #\\)
                           do (setf escaped-p t)
                       else
                         do (setf (char result result-index) char)
                            (incf result-index)
                       finally (return result)))
               (read-array ()
                 (skip-spaces)
                 (loop until (skip?-or-eof #\])
                       collect (prog1 (dispatch)
                                 (skip?-with-spaces #\,))))
               (read-number (&optional rest-p)
                 (let ((start (the fixnum (pos))))
                   (bind (num-str (skip-while integer-char-p))
                     (let ((num (the fixnum (or (parse-integer num-str :junk-allowed t) 0))))
                       (cond
                         (rest-p
                          (the rational (/ num (the fixnum (expt 10 (- (pos) start))))))
                         ((skip? #\.)
                          (the rational (+ num (the rational (read-number t)))))
                         (t (the fixnum num))))))))
        (declare (inline read-string-with-escaping))
        (skip-spaces)
        (return-from parse (dispatch))))))
