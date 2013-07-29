;;; virtualenvwrapper.el -- a modern virtualenv tool for Emacs

;; Copyright (C) 2013 James J Porter
;; Author: James J Porter <porterjamesj@gmail.com>

;;; Commentary:
;; I really like the new python.el, but virtualenv.el
;; is built for old python.el and python-mode.el.  I don't
;; care about the code supporting those; virtualenv.el
;; also doesn't work correctly with M-x shell and eshell.
;; This is my attempt to make a mode that supports only the
;; new python.el and gives a smooth workflow with the python
;; shell, M-x shell, and M-x eshell, as well as running shell
;; commands with M-! or what have you.

;;; TODO:
;; 1. I would like to eventually support some of the virtualenvwrapper
;;    operations: lsvirtualenv, mkvirtualenv, rmvirtualenv, etc. This
;;    shouldn't be too difficult to implement.
;; 2. I would also like to make the way this handles M-x shell a bit less
;;    hacky. It's currently not POSIX compliant, just feels like the
;;    wrong thing to do, and looks weird when you open a shell to
;;    boot. The only alternative I can see, however, would be to
;;    basically reimplement everything vitrualenvwrapper > workon does in
;;    elisp, which seems like a waste of time.


;;; Code:

(defcustom venv-dir
  (expand-file-name "~/.virtualenvs/")
  "The directory in which your virtualenvs are located.")

(defvar venv-history nil "The last venv we worked on.")

(defvar venv-current-name nil "Name of current virtualenv.")

(defvar venv-current-dir nil "Directory of current virtualenv.")

(defcustom venv-configure-shell t "Whether to enable virtualenv support
for M-x shell.")
(defcustom venv-configure-eshell t "Whether to enable virtulenv support
for M-x ehell.")

(defun venv-deactivate ()
  "Deactivate the current venv."
  (interactive)
  (setq python-shell-virtualenv-path nil)
  (setq exec-path (-filter (lambda (s) (not (s-contains? venv-dir s)))
                           exec-path))
  (setenv "PATH" (venv-get-stripped-path))
  (setenv "VIRTUAL_ENV" nil)
  (setq venv-current-name nil)
  (setq venv-current-dir nil)
  (setq eshell-path-env (getenv "PATH"))
  (message "virtualenv deactivated"))

(defun venv-get-candidates (dir)
  "Given a directory containing virtualenvs, return a list
of candidates to match against in the completion."
  (let ((proper-dir (file-name-as-directory dir)))
    (-filter (lambda (s) (car (file-attributes (concat dir s))))
             (directory-files proper-dir nil "^[^.]"))))

(defun venv-get-stripped-path ()
  "Return what the PATH environment variable would look like if
we weren't in a virtualenv."
  (s-join ":" (-filter (lambda (s) (not (s-contains? venv-dir s)))
                       (s-split ":" (getenv "PATH")))))

(defun venv-is-valid (name)
  "Test if a venv named NAME exists in the venv-dir"
  (-contains? (venv-get-candidates venv-dir) name))

(defun venv-read-name (prompt)
  "Do a completing read to get the name of a candidate."
  (completing-read prompt
                   (venv-get-candidates venv-dir) nil t nil
                   'venv-history
                   (car venv-history)))

(defun venv-workon (&optional name)
  "Interactively switch to a virtualenv."
  (interactive)
  ;; first deactivate
  (venv-deactivate)
  (if name
      ;; if called with argument, make sure it is valid
      (progn
        (when (not (venv-is-valid name))
          (error "Invalid virtualenv specified!"))
        ;; then switch to it
        (setq venv-current-name name))
    ;; if called without argument, prompt for completion
  (setq venv-current-name
          (venv-read-name "Virtualenv to switch to: ")))
  (setq venv-current-dir
        (file-name-as-directory
         (concat (file-name-as-directory venv-dir) venv-current-name)))
  ;; push it onto the history
  (add-to-list 'venv-history venv-current-name)
  ;; setup the python shell
  (setq python-shell-virtualenv-path venv-current-dir)
  ;; setup emacs exec-path
  (add-to-list 'exec-path (concat venv-current-dir "bin"))
  ;; setup the environment for subprocesses
  (setenv "PATH" (concat venv-current-dir "bin:" (getenv "PATH")))
  (setenv "VIRTUAL_ENV" venv-current-dir)
  ;; set eshell path
  (setq eshell-path-env (getenv "PATH"))
  (message (concat "Switched to virtualenv: " venv-current-name)))

(defun venv-mkvirtualenv (&optional name)
  (interactive)
  (when (not name)
    (setq name (read-from-minibuffer "New virtualenv: ")))
  ;; error if this env already exist
  (when (-contains? (venv-get-candidates venv-dir) name)
    (error "A virtualenv with this name already exists!"))
  ;; should this be asynchronous?
  (shell-command (concat "virtualenv " (file-name-as-directory venv-dir) name)))

(defun venv-rmvirtualenv (&optional name)
  (interactive)
  ;; deactivate first
  (venv-deactivate)
  (if name
      (when (not (venv-is-valid name))
        (error "Invalid virtualenv specified!"))
    (setq name (venv-read-name "Virtualenv to delete: ")))
  (delete-directory (concat (file-name-as-directory venv-dir) name) t)
  ;; get it out of the history so it doesn't show up in completing reads
  (setq venv-history (-filter
                      (lambda (s) (not (s-equals? s name))) venv-history))
  (message (concat "Deleted virtualenv: " name)))

(defun venv-lsvirtualenv ()
  "List all available virtualenvs in a temp buffer."
  (interactive)
  (with-output-to-temp-buffer
      "*Virtualenvs*"
      (princ (s-join "\n" (venv-get-candidates venv-dir)))))

(defun venv-cdvirtualenv (&optional subdir)
  "Change to the directory of a virtualenv. If
SUBDIR is passed, append that to the path such that
we are immediately in that directory."
  (interactive)
  (if venv-current-dir
      (cd (concat (file-name-as-directory venv-current-dir) subdir))
    (error "No virtualenv is currently active.")))

(defun venv-cpvirtualenv (&optional name newname)
  "Copy virtualenv NAME to NEWNAME. This comes with the
same caveat as cpvirtualenv in the original virtualenvwrapper,
which is that is far from guarenteed to work well. Many packages
hardcode absolute paths in various places an will break if moved to
a new location. Use with caution."
  (interactive)
  (let ((proper-dir (file-name-as-directory venv-dir)))
    (when (not name) (setq name (venv-read-name "Virtualenv to copy from: ")))
    (when (not newname) (setq newname
                              (read-from-minibuffer "Virtualenv to copy to: ")))
    ;; throw an error if newname already exists
    (when (file-exists-p (concat proper-dir newname))
      (error "A virtualenv with the proposed name already exists!"))
    (copy-directory (concat proper-dir name)
                    (concat proper-dir newname))
    (venv-workon newname)))


;; Advice for the shell so it doesn't blow up

(defun venv-shell-init (process)
  "Startup the current virtualenv in a newly opened shell."
  (comint-send-string
   process
   (concat "if command -v workon >/dev/null 2>&1; then workon "
           venv-current-name
           "; else source "
           venv-current-dir
           "bin/activate; fi \n")))


(defun venv-initialize ()
  (when venv-configure-shell
    (defadvice shell (around strip-env ())
      "Use the environment without the venv to start up a new shell."
      (let* ((buffer-name (or buffer "*shell*"))
             (buffer-exists-already (get-buffer buffer-name)))
        (if (or buffer-exists-already (not venv-current-name))
            ad-do-it
          (progn (setenv "PATH" (venv-get-stripped-path))
                 (setenv "VIRTUAL_ENV" nil)
                 ad-do-it
                 (venv-shell-init buffer-name)
               (setenv "PATH" (concat venv-current-dir "bin:" (getenv "PATH")))
               (setenv "VIRTUAL_ENV" venv-current-dir)))))
    (ad-activate 'shell))
  (when venv-configure-eshell
    (defun eshell/workon (arg) (venv-workon arg))
    (defun eshell/deactivate () (venv-deactivate))))

(provide 'virtualenvwrapper)
;;; venvwrapper.el ends here
