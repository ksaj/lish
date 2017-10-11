;;
;; complete.lisp - Completion for Lish
;;

(in-package :lish)

(declaim (optimize (speed 0) (safety 3) (debug 3) (space 0)
		   (compilation-speed 0)))

;; (defun quoted-start (str pos)
;;   "Check if we are inside a shell quoted string and return it's starting
;;  position."
;;   (

(defun complete-env-var (str all)
  ;; (complete-string-sequence
  ;;  str all (mapcar #'(lambda (x) (string (car x))) (nos:environment))))
  (complete-list str (length str) all
		 (append
		  (fake-var-list)
		  (mapcar #'(lambda (x) (string (car x))) (nos:environment)))))

(defun complete-user-name (str all)
  (complete-list str (length str) all
		 (mapcar (_ (nos:user-info-name _)) (nos:user-list))))

(defvar *verb-list* nil
  "List of current lish commands. Includes aliases, built-in commands, and ~
exectuables in the path. Use the \"rehash\" command to update after new ~
commands are added.")

#+nil (progn ;; Unused code for better verb list caching
(defun probe-file-or-dir (p)
  (or (probe-directory p) (probe-file p)))

(defvar *last-update* nil
  "An alist of (:<facility> . <time-code>) for storing last time we updated the
*VERB-LIST* for various facilites. The structure of <time-code> depends on the
facility. Usually it's a universal-time, or an alist of (<thing> . <time>).")

(defun verb-list-needs-upadating-p ()
  (with-spin ()
    (loop :for dir :in (split-sequence
			nos:*path-separator*
			(nos:environment-variable *path-variable*))
       :do (spin)
       :if (probe-directory dir)
       :append (loop :for f :in (nos:read-directory
				 :dir dir :full t
				 :omit-hidden t)
		  :if (without-access-errors
			  (is-executable
			   (s+ dir *directory-separator*
			       (nos:dir-entry-name f))))
		  :collect (nos:dir-entry-name f)))))

(defun update-verb-thing (thing)
  (ecase thing
    (:aliases)
    (:commands)
    (:path))
  )
)

(defun verb-list (shell)
  "Return the command list for the current shell: *shell*."
  (if (not *verb-list*)
      (setf *verb-list*
	    (with-spin ()
	      (locally
		#+sbcl (declare
			(sb-ext:muffle-conditions sb-ext:compiler-note))
		(sort
		 (remove-duplicates
		  (append
		   (loop :for k :being :the :hash-keys :of (lish-aliases shell)
		      :collect k)
		   (loop :for k :being :the :hash-keys :of (lish-commands)
		      :do (spin)
		      :collect k)
		   (loop :for dir :in (split-sequence
				       nos:*path-separator*
				       (nos:environment-variable
					*path-variable*))
		      :do (spin)
		      :if (probe-directory dir)
		      :append (loop :for f :in (nos:read-directory
						:dir dir :full t
						:omit-hidden t)
				 :if (without-access-errors
					 (is-executable
					  (s+ dir *directory-separator*
					      (nos:dir-entry-name f))))
				 :collect (nos:dir-entry-name f))))
		  :test #'equal)
		 #'string<))))
      *verb-list*))

(defun complete-command (str all)
;  (complete-string-sequence str all (verb-list *shell*)
  (complete-list str (length str) all (verb-list *shell*)))

;; This is mostly like complete-symbol but it handles the ! at the beginning.
;; XXX Uses completion internals.
(defun complete-bang-symbol (context pos all)
  "Completion function for symbols (preceded by ! in the shell)."
  (let* ((word-start (completion::scan-over-str
		      context pos :backward
		      :not-in completion::*lisp-non-word-chars*))
	 (word (subseq context word-start pos))
	 (pack nil)
	 (external nil))
;    (format t "Howdy: word-start ~s word ~s~%" word-start word)
    (when (eql #\! (aref word 0))
      (setf word (subseq word 1)
	    word-start (1+ word-start)))
    (multiple-value-setq (pack external)
      (completion::find-back-pack context word-start))
    (if all
	(completion::symbol-completion-list
	 word :package pack :external external)
	(let ((result
	       (completion::symbol-completion
		word :package pack :external external)))
	  (setf (completion-result-insert-position result)
		word-start)))))

(defun shell-complete-symbol (context pos all &optional bang-p)
  "Complete symbols in the *lish-user-package*, optionally with a
preceding exclamation point '!' ."
  (with-package *lish-user-package*
    (if bang-p
	(complete-bang-symbol context pos all)
	(complete-symbol context pos all))))

(defun quotify (string)
  "Put a backslash in front of any character that might not be intrepreted
literally in shell syntax."
  (let ((result string))
    (flet ((possibly-quote (c)
	     (when (position c result)
	       (setf result (join (split-sequence c result) (s+ #\\ c))))))
      (loop :for c :across " !$|;[]*?()" :do ;
	 (possibly-quote c))
      result)))

(defun words-past (expr pos)
  "Return how many words the position POS is past in EXPR."
  (let ((past 0))
    (loop :for i :from 0 :below (length (shell-expr-words expr))
       :do (when (> pos (elt (shell-expr-word-end expr) i))
	     (setf past (1+ i))))
    past))

(defun first-word-in-expr (pos expr)
  "Find the first word of pipeline where POS is in a shell expr."
  (let ((w (first (shell-expr-words expr))))
    (cond
      ((stringp w) w)
      ((and (consp w) (eq (car w) :pipe))
       (if (<= pos (elt (shell-expr-word-start expr) 0))
	   (first-word-in-expr pos (cadr w))
	   (if (>= pos (elt (shell-expr-word-start expr) 0))
	       (second (shell-expr-words expr))
	       nil))))))		; We couldn't find it?

(defun term-cols ()
  "Return the terminal columns."
  (terminal-window-columns
   (rl:line-editor-terminal (lish-editor *shell*))))

(defun list-arg-choices (command doc choices)
  (let* (;; (cols (term-cols))
	 (prefix-str (s+ (if (>= *completion-count* 1)
			     (s+ (documentation command 'function) #\newline)
			     (s+ (posix-synopsis command) #\newline))
			 (or doc "") #\newline))
	 (comp-list (or choices (list ""))))
			  ;;      (with-output-to-string (str)
			  ;; 	 (print-columns choices
			  ;; 			:stream str
			  ;; 			:columns cols)))
			  ;; ""))))
    ;; Trim possible trailing newline?
    ;; (when (eql (char out-str (1- (length out-str))) #\newline)
    ;;   (setf out-str (subseq out-str 0 (1- (length out-str)))))
    ;;(make-completion-result :completion (list out-str) :count 1)))
    (make-completion-result :completion comp-list
			    :count (length comp-list)
			    :prefix prefix-str)))

;; (defun show-dash-arglist (arglist)
;;   (list
;;    (with-output-to-string (str)
;;      (loop :with print-newline = nil
;; 	:for a :in arglist
;; 	:when (and (arg-short-arg a)
;; 		   (not (arg-hidden a)))
;; 	:do
;; #|	(format str "~:[~;~%~]-~a ~:[~;[T] ~]~25a~@[ ~a~]"
;; 		print-newline
;; 		(arg-short-arg a) (arg-default a) (arg-name a)
;; 		(and (slot-boundp a 'help) (arg-help a))) |#
;; 	(format str "~:[~;~%~] -~a ~@[ ~a~] ~:[~;~1:*[~a] ~]"
;; 		print-newline
;; 		(arg-short-arg a)
;; 		(or (and (slot-boundp a 'help) (arg-help a))
;; 		    (arg-name a))
;; 		(arg-default a))
;; 	(when (not print-newline)
;; 	  (setf print-newline t))))))

(defun show-dash-arglist (arglist)
  (let ((result (make-stretchy-string 200)))
    (with-output-to-string (str result)
      (nice-print-table
       (loop :for a :in arglist
	  :when (and (arg-short-arg a)
		     (not (arg-hidden a)))
	  :collect
	  (list (s+ " -" (arg-short-arg a))
		(s+ (or (and (slot-boundp a 'help)
			     (substitute #\space #\newline (arg-help a)))
			(arg-name a))
		    (if (arg-default a)
			(s+ " [" (arg-default a) "]")
			""))))
       '("Arg" ("desc" :wrap)) :stream str :trailing-spaces nil
       :print-titles nil :max-width (term-cols)))
    ;; Get rid of the final newline
    (when (and (> (length result) 0)
	       (char= #\newline (aref result (- (length result) 1))))
      (setf (fill-pointer result) (- (length result) 2)))
    (make-completion-result :completion (list result) :count 1)))

(defvar *long-double-dash-help* nil
  "True to show longer help for double dash arguments.")

(defun show-double-dash-arglist (arglist)
  (let ((result (make-stretchy-string 200)))
    (with-output-to-string (str result)
      (nice-print-table
       (loop :for a :in arglist
	  :when (and (arg-long-arg a)
		     (not (arg-hidden a)))
	  :collect
	  (if *long-double-dash-help*
	      (list (s+ "--" (arg-long-arg a))
		    (arg-default a)
		    (string-downcase (arg-type a))
		    (or (and (slot-boundp a 'help) (arg-help a))
			(arg-name a)))
	      (list (s+ "--" (arg-long-arg a))
		    (or (and (slot-boundp a 'help)
			     (substitute #\space #\newline (arg-help a)))
			(format nil "~s ~(~a~)"
				(arg-default a) (arg-type a))))))
       '(("Arg" :overflow) ("desc" :wrap)) :stream str :trailing-spaces nil
       :print-titles nil :max-width (term-cols)))
    ;; Get rid of the final newline
    (when (and (> (length result) 0)
	       (char= #\newline (aref result (- (length result) 1))))
      (setf (fill-pointer result) (- (length result) 2)))
    (make-completion-result :completion (list result) :count 1)))

(defun complete-double-dash-arglist (word pos arglist)
  (dbug "word = ~s pos = ~s~%" word pos)
  (complete-list
   ;; (subseq word 2) (- pos 2) nil
   word pos nil
   (loop :for a :in arglist
      :if (arg-long-arg a)
      :collect (s+ "--" (arg-long-arg a)))))

(defun first-mandatory-or-non-flag-arg (past arglist)
  (or (loop :with i = 0
	 :for a :in arglist :do
	 ;;(format t "~a ~a ~s~%" i (>= i (1- past)) a)
	 (when (and (>= i (1- past))
		    (not (arg-optional a)))
	   (return-from first-mandatory-or-non-flag-arg a))
	 (incf i))
      ;; @@@ Unfortunately this makes the wrong choice for non-boolean
      ;; args. It should only pick a non-boolean arg which has a flag if we
      ;; are past the flag, but the simple numeric PAST count can't indicate
      ;; that. I'm not really sure what a workable way to patch this is. This
      ;; really shows how I need to totally redesign the argument code to do
      ;; proper parsing. Then we can reliably show what are the choices from a
      ;; given parse state.
      (loop :with i = 0
	 :for a :in arglist :do
	 ;;(format t "~a ~a ~s~%" i (>= i (1- past)) a)
	 (when (and (>= i (1- past))
		    (not (and (or (arg-short-arg a)
				  (arg-long-arg a)
				  (arg-old-long-arg a))
			      (eq (arg-type a) 'boolean))))
	   (return-from first-mandatory-or-non-flag-arg a))
	 (incf i))
      (nth (max 0 (1- past)) arglist)))

;; Note that this takes different args than a normal completion function.
(defun complete-command-arg (context command expr pos all
			     &optional word-num word word-pos)
  "Complete a command argument."
  (let* ((past (words-past expr pos))
	 (fake-word (or word ""))
;;;	 (arg (nth (1- past) (command-arglist command)))
	 (arg (first-mandatory-or-non-flag-arg past (command-arglist command)))
	 (func (and arg (arg-completion-function arg))))
    (dbug "cmd arg ~s ~s ~s ~s ~s ~s~%"
	  context pos fake-word word-pos arg func)
    (cond
      ((and word-pos (> word-pos 1)
;;;	    (char= (char word (1- word-pos)) #\-)
;;;	    (char= (char word (- word-pos 2)) #\-))
	    (is-flag-char (char word 0))
	    (is-flag-char (char word 1)))
       ;; double dash args
       (if all
	   (show-double-dash-arglist (command-arglist command))
	   (progn
	     (complete-double-dash-arglist word word-pos
					   (command-arglist command)))))
      ((and all word-pos
	    (> word-pos 0)
	    (is-flag-char (char word (1- (min word-pos (length word)))))
	    (is-flag-char (char word 0)))
       ;; dash arg enumeration
       (show-dash-arglist (command-arglist command)))
      (func
       (dbug "---> (~a ~s ~s ~s )~%" func fake-word (length fake-word) all)
       ;; I don't want to make all the arg completion functions have to use
       ;; completion-result, but will this suffice? Or will it lose something?
       ;; @@@
       (let ((result
	      (funcall func fake-word (length fake-word) all :parsed-exp expr)))
	 (if (completion-result-p result)
	     result
	     (make-completion-result
	      :completion result
	      :count (length result) ;; @@@ redundant?
	      ))))
      (t
       (let ((doc (and arg (documentation (type-of arg) 'type)))
	     (choices (and arg (argument-choices arg))))
	 (let ((*print-lines* 20))
	   (dbug "wazzup? ~s choices ~w ~%" fake-word choices))
	 (if all
	     (progn
	       #| (print-values* (command expr pos all word-num word)) |#
	       (dbug "ummm...~a~%" past)
	       (if (and (= past 1) (not word-num))
		   (progn
		     (dbug "snoo ~a? words-past ~a~%" command past)
		     (list-arg-choices command doc choices))
		   (progn
		     (if (and fake-word choices)
			 (complete-list fake-word
					(length fake-word) all choices)
			 (complete-filename fake-word pos all)))))
	     (progn
	       (dbug "cmd arg fake-word ~s" fake-word)
	       (if choices
		   (complete-list fake-word (length fake-word) all choices)
		   (complete-filename fake-word pos all)))))))))

(defun start-of-a-compound-p (expr pos)
  "Return true if we are at the start of the last compound command."
  (and (= (length (shell-expr-words expr)) 1)
       (consp (first (shell-expr-words expr)))
       (keywordp (first (first (shell-expr-words expr))))
       (>= pos (length (shell-expr-line expr)))))

(defun in-command-position-p (expr word-num)
  (or
   ;; first word in a line
   (= word-num 0)
   ;; first word after a compound command
   (and (= (length (shell-expr-words expr)) 2)
	(consp (first (shell-expr-words expr)))
	(keywordp (first (first (shell-expr-words expr))))
	(= word-num 1))))

(defun try-command (command)
  "See if we can dig up the dirt on a command named COMMAND.
Uses the first available of:
  - an already loaded command
  - a command which we load by the normal command path mechanism
  - a pre-defined external command, from an external command cache
  - a mined external command"
  (or (get-command command)
      (and (load-lisp-command command) (get-command command))
      ;;(and (load-external-command command) (get-command command))
      (and (mine-command command) (get-command command))))

(defun shell-complete (context pos all)
  (declare (type string context))
  "Analyze the context and try figure out what kind of thing we want to ~
complete, and call the appropriate completion function."
  (dbugf 'completion "shell-complete ~s ~s ~s~%" context pos all)
  (let (exp explanation cmd)
    (multiple-value-setq (exp explanation)
      (ignore-errors (shell-read context :partial t
				 :package *junk-package*)))
    (dbugf 'completion "exp ~s is a ~a~%" exp (type-of exp))
    (flet ((simple-complete (func word wpos)
	     (let ((result (funcall func word all)))
	       (if all
		   (setf (completion-result-count result)
			 (length (completion-result-completion result)))
		   (setf (completion-result-insert-position result)
			 wpos))
	       result)))
      (typecase exp
	(keyword
	 (cond
	   ;; Couldn't read a whole expression.
	   ((eq exp *continue-symbol*)
	    ;; If it's not something we know about, it's probably a bug.
	    (ecase (car explanation) 
	      (lisp-expr	      ; an incomplete lisp expression
	       ;; (cdr explanation) should be the expr?
	       (dbugf 'completion "partial lisp-expr ~s ~s~%" context pos)
	       (shell-complete-symbol context pos all))
	      (bang-expr	      ; an incomplete !lisp expression
	       ;; (cdr explanation) should be the expr?
	       (dbugf 'completion "partial bang-expr ~s ~s~%" context pos)
	       (shell-complete-symbol context pos all))
	      (string	       ; an unclosed string
	       ;; This is lame. Anything could be in a string.
	       (dbugf 'completion "partial string ~s ~s~%" (second explanation)
		      (third explanation))
	       ;; (complete-filename (cdr explanation)
	       ;; 			  (length (cdr explanation)) all))
	       (simple-complete #'complete-filename (second explanation)
				(third explanation)))
	      (compound		  ; a compound connector with nothing after it
	       (dbugf 'completion "partial compound ~s~%" (cdr explanation))
	       (case (cadr explanation)
		 ((:pipe :and :or :sequence)
		  (dbugf 'completion "whut?~%")
		  (prog1 (simple-complete #'complete-command "" pos)
		    (dbugf 'completion "why?~%")))
		 ((:redirect-to :redirect-from :append-to)
		  (complete-filename "" 0 all))))))
	   (t ;; This is probably a bug.
	    (error "Unknown keyword returned from shell-read."))))
	(cons
	 (dbugf 'completion "Hellow I am janky!~%")
	 (shell-complete-symbol context pos all))
	(shell-expr
	 (let* ((word-num (shell-word-number exp pos))
		(first-word (first-word-in-expr pos exp))
		word word-pos)
	   ;; word-num is the index of the word in the shell expr
	   ;; word is the text of the word
	   ;; word-pos is the relative position in the word
	   (when word-num
	     (setf word (elt (shell-expr-words exp) word-num)
		   word-pos (- pos (elt (shell-expr-word-start exp) word-num))))
	   (dbugf 'completion "~%word-num = ~w word = ~w word-pos = ~w~%"
		  word-num word word-pos)
	   (cond
	     ((or (and (not word-num) (= pos 0))
		  (start-of-a-compound-p exp pos))
	      ;; no words
	      (dbugf 'completion "none~%")
	      (simple-complete #'complete-command "" 0))
	     ((not word)
	      (if (= 0 (length (shell-expr-words exp)))
		  ;; probably ()
		  (progn
		    (dbugf 'completion "bogo~%")
		    (shell-complete-symbol context pos all))
		  ;; a blank spot somewhere in the line
		  (let ((from-end (- (length context) pos)))
		    (dbugf 'completion "heyba~%")
		    (let ((result
			   (if (setf cmd (try-command first-word))
			       (progn
				 (dbugf 'completion "Baaa~%")
				 (complete-command-arg context cmd exp pos all))
			       (complete-filename word
						  (- (length word) from-end)
						  all))))
		      (when (not all)
			(setf (completion-result-completion result)
			      (quotify (completion-result-completion result))))
		      (setf (completion-result-insert-position result)
			    (or (and word-num
				     (elt (shell-expr-word-start exp)
					  word-num))
				pos))
		      result))))
	     ((symbolp word)
	      (dbugf 'completion "janky~%")
	      (shell-complete-symbol context pos all t))
	     ((consp word)		; (foo)
	      (dbugf 'completion "junky~%")
	      (shell-complete-symbol context pos all))
	     ((eql (aref word 0) #\()	; (foo
	      (dbugf 'completion "half baka~%")
	      (shell-complete-symbol context pos all))
	     ((eql (aref word 0) #\!)	; !foo
	      (shell-complete-symbol context pos all t))
	     ((eql (aref word 0) #\$)	; $foo
	      (simple-complete #'complete-env-var
			       (subseq word 1)
			       (1+ (elt (shell-expr-word-start exp)
					word-num))))
	     ((and (eql (aref word 0) #\~) ; ~foo
		   (valid-user-name (subseq word 1)))
	      (simple-complete #'complete-user-name
			       (subseq word 1)
			       (1+ (elt (shell-expr-word-start exp)
					word-num))))
	     ;; first word, when not starting with directory chars
	     ((and
	       (in-command-position-p exp word-num)
	       (not (position (aref word 0) "/.~")))
	      (dbugf 'completion "jinky~%")
	      ;; try commands
	      (let ((result 
		     (simple-complete #'complete-command
				      first-word ;; was: context
				      (elt (shell-expr-word-start exp)
					   word-num))))
		;; then symbols
		;; XXX Symbols won't come up in the list.
		(when (not (completion-result-completion result))
		  (setf result
			(shell-complete-symbol context pos all)))
		result))
	     (t
	      (dbugf 'completion "hello ~a~%" word)
	      (let* ((from-end (- (length context) pos))
		     (result
		      (if (setf cmd (try-command first-word))
			  (progn
			    (dbugf 'completion "blurgg~%")
			    (complete-command-arg
			     context cmd exp pos
			     #| (- (length word) from-end) |#
			     all word-num word word-pos))
			  (progn
			    (dbugf 'completion "jorky~%")
			    ;; But it could be a command which isn't loaded yet.
			    (if (load-lisp-command first-word)
				(complete-command-arg
				 context (get-command first-word) exp pos
				 all word-num word word-pos)
				(complete-filename word
				 		   (- (length word) from-end)
				 		   all)
				)))))
		(dbugf 'completion "result = ~s~%" result)
		(if all
		    (setf (completion-result-count result)
			  (length (completion-result-completion result)))
		    (setf (completion-result-completion result)
			  (quotify (completion-result-completion result))
			  (completion-result-insert-position result)
			  (let ((ss (elt (shell-expr-word-start exp) word-num)))
			    (if (elt (shell-expr-word-quoted exp) word-num)
				(1+ ss) ss))))
		result)))))))))

;; EOF
