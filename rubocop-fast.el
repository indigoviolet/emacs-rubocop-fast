;;; rubocop-fast.el --- Emacs minor mode to format Ruby code on file save

;; Version: 0.1.0

;; Author: Venky Iyer
;; Keywords: convenience wp edit ruby

;; This file is not part of GNU Emacs.

;;; Commentary: Formats your Ruby code using 'rubocop' on file save.
;;
;; Based on the prettier-js code by jlongster and others at
;; https://github.com/prettier/prettier-emacs
;;
;;
;; Needs the custom wrapper around rubocop as the rubocop command, and
;; the auto-correct options as below::
;;
;;
;; (setq rubocop-fast--rubocop-command "/path/to/rubocop-emacs.sh")
;; (setq rubocop-fast--rubocop-args '( "--auto-correct" "--format"
;; "emacs"))


;;; Code:

(defcustom rubocop-fast--rubocop-command "rubocop"
  "The 'rubocop' command."
  :type 'string
  :group 'rubocop)

(defcustom rubocop-fast--rubocop-args '()
  "List of args to send to rubocop command."
  :type 'list
  :group 'rubocop)

(defcustom rubocop-fast--rubocop-target-mode
  "ruby-mode"
  "Name of the major mode to be used by 'rubocop-before-save'."
  :type 'string
  :group 'rubocop)

(defcustom rubocop-fast--rubocop-show-errors 'buffer
    "Where to display rubocop error output.
It can either be displayed in its own buffer, in the echo area, or not at all.
Please note that Emacs outputs to the echo area when writing
files and will overwrite rubocop's echo output if used from inside
a `before-save-hook'."
    :type '(choice
            (const :tag "Own buffer" buffer)
            (const :tag "Echo area" echo)
            (const :tag "None" nil))
      :group 'rubocop)

(defcustom rubocop-fast--rubocop-width-mode nil
  "Specify width when formatting buffer contents."
  :type '(choice
          (const :tag "Window width" window)
          (const :tag "Fill column" fill)
          (const :tag "None" nil))
  :group 'rubocop)

;;;###autoload
(defun rubocop-before-save ()
  "Add this to .emacs to run rubocop on the current buffer when saving: (add-hook 'before-save-hook 'rubocop-before-save)."
  (interactive)
  (when (string-equal (symbol-name major-mode) rubocop-fast--rubocop-target-mode) (rubocop)))

(defun rubocop-fast--goto-line (line)
  "Move cursor to line LINE."
  (goto-char (point-min))
    (forward-line (1- line)))

(defun rubocop-fast--delete-whole-line (&optional arg)
    "Delete the current line without putting it in the `kill-ring'.
Derived from function `kill-whole-line'.  ARG is defined as for that
function."
    (setq arg (or arg 1))
    (if (and (> arg 0)
             (eobp)
             (save-excursion (forward-visible-line 0) (eobp)))
        (signal 'end-of-buffer nil))
    (if (and (< arg 0)
             (bobp)
             (save-excursion (end-of-visible-line) (bobp)))
        (signal 'beginning-of-buffer nil))
    (cond ((zerop arg)
           (delete-region (progn (forward-visible-line 0) (point))
                          (progn (end-of-visible-line) (point))))
          ((< arg 0)
           (delete-region (progn (end-of-visible-line) (point))
                          (progn (forward-visible-line (1+ arg))
                                 (unless (bobp)
                                   (backward-char))
                                 (point))))
          (t
           (delete-region (progn (forward-visible-line 0) (point))
                                                  (progn (forward-visible-line arg) (point))))))

(defun rubocop-fast--apply-rcs-patch (patch-buffer)
  "Apply an RCS-formatted diff from PATCH-BUFFER to the current buffer."
  (let ((target-buffer (current-buffer))
        ;; Relative offset between buffer line numbers and line numbers
        ;; in patch.
        ;;
        ;; Line numbers in the patch are based on the source file, so
        ;; we have to keep an offset when making changes to the
        ;; buffer.
        ;;
        ;; Appending lines decrements the offset (possibly making it
        ;; negative), deleting lines increments it. This order
        ;; simplifies the forward-line invocations.
        (line-offset 0))
    (save-excursion
      (with-current-buffer patch-buffer
        (goto-char (point-min))
        (while (not (eobp))
          (unless (looking-at "^\\([ad]\\)\\([0-9]+\\) \\([0-9]+\\)")
            (error "Invalid rcs patch or internal error in rubocop-fast--apply-rcs-patch"))
          (forward-line)
          (let ((action (match-string 1))
                (from (string-to-number (match-string 2)))
                (len  (string-to-number (match-string 3))))
            (cond
             ((equal action "a")
              (let ((start (point)))
                (forward-line len)
                (let ((text (buffer-substring start (point))))
                  (with-current-buffer target-buffer
                    (setq line-offset (- line-offset len))
                    (goto-char (point-min))
                    (forward-line (- from len line-offset))
                    (insert text)))))
             ((equal action "d")
              (with-current-buffer target-buffer
                (rubocop-fast--goto-line (- from line-offset))
                (setq line-offset (+ line-offset len))
                (rubocop-fast--delete-whole-line len)))
             (t
              (error "Invalid rcs patch or internal error in rubocop-fast--apply-rcs-patch")))))))))

(defun rubocop-fast--process-errors (errorfile errbuf)
  "Process errors using ERRORFILE and display the output in ERRBUF."
  (with-current-buffer errbuf
    (if (eq rubocop-fast--rubocop-show-errors 'echo)
        (progn
          (message "%s" (buffer-string))
          (rubocop-fast--kill-error-buffer errbuf))
      (insert-file-contents errorfile nil nil nil)
      ;; Convert the rubocop stderr to something understood by the compilation mode.
      (goto-char (point-min))
      (insert "rubocop errors:\n")
      (compilation-mode)
      (display-buffer errbuf))))

(defun rubocop-fast--kill-error-buffer (errbuf)
  "Kill buffer ERRBUF."
  (let ((win (get-buffer-window errbuf)))
    (if win
        (quit-window t win)
      (with-current-buffer errbuf
        (erase-buffer))
      (kill-buffer errbuf))))

(defun rubocop ()
   "Format the current buffer according to the rubocop tool."
   (interactive)
   (let* ((ext (file-name-extension buffer-file-name t))
          (outputfile (make-temp-file "rubocop" nil ext))
          (errorfile (make-temp-file "rubocop" nil ext))
          (errbuf (if rubocop-fast--rubocop-show-errors (get-buffer-create "*rubocop errors*")))
          (patchbuf (get-buffer-create "*rubocop patch*"))
          (coding-system-for-read 'utf-8)
          (coding-system-for-write 'utf-8)
          (width-args
           (cond
            ((equal rubocop-fast--rubocop-width-mode 'window)
             (list "--print-width" (number-to-string (window-body-width))))
            ((equal rubocop-fast--rubocop-width-mode 'fill)
             (list "--print-width" (number-to-string fill-column)))
            (t
             '()))))
     (unwind-protect
         (save-restriction
           (widen)
           (if errbuf
               (with-current-buffer errbuf
                 (setq buffer-read-only nil)
                 (erase-buffer)))
           (with-current-buffer patchbuf
             (erase-buffer))
           (if (zerop (apply 'call-process-region
                             (point-min) (point-max)
                             rubocop-fast--rubocop-command nil (list (list :file outputfile) errorfile) nil
                             (append rubocop-fast--rubocop-args width-args (list "--stdin" (buffer-file-name)))))
               (progn
                 (call-process-region (point-min) (point-max) "diff" nil patchbuf nil "-n" "-"
                                      outputfile)
                 (rubocop-fast--apply-rcs-patch patchbuf)
                 (message "Applied rubocop with args `%s'" rubocop-fast--rubocop-args)
                 (if errbuf (rubocop-fast--kill-error-buffer errbuf))
                 (message outputfile)
                 (message errorfile)
                 (message errbuf)
                 )
             (message "Could not apply rubocop")
             (message outputfile)
             (message errorfile)
             (message errbuf)
             (if errbuf
                 (rubocop-fast--process-errors errorfile errbuf))
             )))
     (kill-buffer patchbuf)
     (delete-file errorfile)
     (delete-file outputfile)
))

;;;###autoload
(define-minor-mode rubocop-mode
  "Runs rubocop on file save when this mode is turned on"
  :lighter " rubocop"
  :global nil
  (if rubocop-mode
      (add-hook 'before-save-hook 'rubocop nil 'local)
    (remove-hook 'before-save-hook 'rubocop 'local)))

(provide 'rubocop-fast)
;;; rubocop-fast.el ends here
