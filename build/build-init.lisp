;;
;; build-init.lisp - Initialization for built Lish.
;;

(defpackage :build-init
  (:documentation "Initialization for built Lish.")
  (:use :cl))
(in-package :build-init)

;; Do things that are too horrible to mention here.
(load "build/horrible.lisp" :verbose nil)

(msg "[Build initializing...]")

(defun fail (message &rest args)
  (format t "~&/~v,,,va~%~~%BUILD FAILURE:~%~?~%~&\\~v,,,va~%"
	  40 #\- #\- message args 40 #\- #\-)
  (exit-lisp :code 1))

(load "build/load-asdf.lisp" :verbose nil)

(defvar *home* (or (and (sf-getenv "LISP_HOME")
			(namestring (probe-file (sf-getenv "LISP_HOME"))))
		   (namestring (user-homedir-pathname)))
  "Namestring of the home directory.")

(load "build/load-quicklisp.lisp" :verbose nil)

(push "../"          asdf:*central-registry*)
(push "../opsys/"    asdf:*central-registry*)
(push "../terminal/" asdf:*central-registry*)
(push "../rl/"       asdf:*central-registry*)
(push "../deblarg/"  asdf:*central-registry*)
(push "./"           asdf:*central-registry*)

;; Suppress the fucking ASDF warnings.
(let ((bitch (find-symbol "*SUPPRESS-DEFINITION-WARNINGS*" :asdf))
      (troublemakers
       '(:cl-ppcre-test :puri-tests :cl-base64-tests :flexi-streams-test
	 :openssl-1.1.0 :trivial-garbage-tests :cl-fad-test
	 :hunchentoot-test :hunchentoot-dev)))
  (if bitch
      (set bitch troublemakers) ;; yes, I mean set.
      (progn
	(setf bitch (find-symbol
		     "*KNOWN-SYSTEMS-WITH-BAD-SECONDARY-SYSTEM-NAMES*" :asdf))
	(if bitch
	    (set bitch (uiop:list-to-hash-set troublemakers))
	    (format t "~&I'm very sorry, but you're not running a recent ~
                        enough version of ASDF, so you will probably see ~
                        useless warnings.~%")))))

(in-package :cl-user)
(delete-package :build-init)

;; EOF
