;;; -*- lexical-binding: nil -*-
;; Directory tree

(defconst ztree-hidden-files-regexp "^\\."
  "Hidden files regexp")

(defvar ztree-expanded-dir-list nil
  "A list of Expanded directory entries.")
(make-variable-buffer-local 'ztree-expanded-dir-list)

(defvar ztree-start-dir nil
  "Start directory for the window.")
(make-variable-buffer-local 'ztree-start-dir)

(defvar ztree-files-info nil
  "List of tuples with full file name and the line.")
(make-variable-buffer-local 'ztree-files-info)

(defvar ztree-filter-list nil
  "List of regexp for file/directory names to filter out")
(make-variable-buffer-local 'ztree-filter-list)

;;
;; Major mode definitions
;;

(defvar ztree-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "\r") 'ztree-perform-action)
    (define-key map (kbd "SPC") 'ztree-perform-action)
    (define-key map [double-mouse-1] 'ztree-perform-action)
    (define-key map (kbd "g") 'ztree-refresh-buffer)
    map)
  "Keymap for `ztree-mode'.")

(defvar ztree-font-lock-keywords
  '(("[+] .*" (1 diredp-dir-heading)))
  "Directory highlighting specification for `ztree-mode'.")

;;;###autoload
(define-derived-mode ztree-mode special-mode "Ztree"
  "A major mode for Diff Tree."
  (setq-local font-lock-defaults
              '(ztree-font-lock-keywords)))


(defun ztree-find-file-in-line (line)
  "Search through the array of filename-line pairs and return the
filename for the line specified"
  (let ((found (find line ztree-files-info
                     :test #'(lambda (l entry) (eq l (cdr entry))))))
    (when found
      (car found))))

(defun ztree-is-expanded-dir (dir)
  "Find if the directory is in the list of expanded directories"
  (find dir ztree-expanded-dir-list :test 'string-equal))

(defun scroll-to-line (line)
  "Recommended way to set the cursor to specified line"
  (goto-char (point-min))
  (forward-line (1- line)))


(defun ztree-perform-action ()
  "Toggle expand/collapsed state for directories"
  (interactive)
  (let* ((line (line-number-at-pos))
         (file (ztree-find-file-in-line line)))
    (when file
      (if (file-directory-p file)  ; only for directories
          (ztree-toggle-dir-state file)
        nil)                            ; do nothiang for files for now
      (let ((current-pos (window-start))) ; save the current window start position
        (ztree-refresh-buffer line)    ; refresh buffer and scroll back to the saved line
        (set-window-start (selected-window) current-pos))))) ; restore window start position


(defun ztree-toggle-dir-state (dir)
  "Toggle expanded/collapsed state for directories"
  (if (ztree-is-expanded-dir dir)
      (setq ztree-expanded-dir-list (remove-if #'(lambda (x) (string-equal dir x))
                                                  ztree-expanded-dir-list))
    (push dir ztree-expanded-dir-list)))

(defun file-basename (file)
  "Base file/directory name. Taken from http://lists.gnu.org/archive/html/emacs-devel/2011-01/msg01238.html"
  (file-name-nondirectory (directory-file-name file)))

(defun printable-string (string)
  "Strip newline character from file names, like 'Icon\n'"
  (replace-regexp-in-string "\n" "" string))  


(defun ztree-get-directory-contens (path)
  "Returns pair of 2 elements: list of subdirectories and
list of files"
  (let ((files (directory-files path 'full)))
    (cons (remove-if-not #'(lambda (f) (file-directory-p f)) files)
          (remove-if #'(lambda (f) (file-directory-p f)) files))))

(defun ztree-file-is-in-filter-list (file)
  "Determine if the file is in filter list (and therefore
apparently shall not be visible"
  (find file ztree-filter-list :test #'(lambda (f rx) (string-match rx f))))

(defun ztree-draw-char (c x y)
  "Draw char c at the position (1-based) (x y)"
  (save-excursion
    (scroll-to-line y)
    (beginning-of-line)
    (goto-char (+ x (-(point) 1)))
    (delete-char 1)
    (insert-char c 1)))

(defun ztree-draw-vertical-line (y1 y2 x)
  (if (> y1 y2)
    (dotimes (y (1+ (- y1 y2)))
      (ztree-draw-char ?\| x (+ y2 y)))
    (dotimes (y (1+ (- y2 y1)))
      (ztree-draw-char ?\| x (+ y1 y)))))
        
(defun ztree-draw-horizontal-line (x1 x2 y)
  (if (> x1 x2)
    (dotimes (x (1+ (- x1 x2)))
      (ztree-draw-char ?\- (+ x2 x) y))
    (dotimes (x (1+ (- x2 x1)))
      (ztree-draw-char ?\- (+ x1 x) y))))
  

(defun ztree-draw-tree (tree offset)
  "Draw the tree of lines with parents"
  (if (atom tree)
      nil
    (let ((root (car tree))
          (children (cdr tree)))
      (when children
        ;; draw the line to the last child
        ;; since we push'd children to the list, the last line
        ;; is the first
        (let ((last-child (car children))
              (x-offset (+ 2 (* offset 4))))
          (if (atom last-child)
              (ztree-draw-vertical-line (1+ root) last-child x-offset)
            (ztree-draw-vertical-line (1+ root) (car last-child) x-offset)))
        ;; draw recursively
        (dolist (child children)
          (ztree-draw-tree child (1+ offset))
          (if (listp child)
              (ztree-draw-horizontal-line (+ 3 (* offset 4))
                                             (+ 4 (* offset 4))
                                             (car child))
            (ztree-draw-horizontal-line (+ 3 (* offset 4))
                                           (+ 7 (* offset 4))
                                           child)))))))
  
                                            
(defun ztree-insert-directory-contents (path)
  ;; insert path contents with initial offset 0
  (let ((tree (ztree-insert-directory-contents-1 path 0)))
    (ztree-draw-tree tree 0)))

  

(defun ztree-insert-directory-contents-1 (path offset)
  (let* ((expanded (ztree-is-expanded-dir path))
         (root-line (ztree-insert-entry path offset expanded))
         (children nil))
    (when expanded 
      (let* ((contents (ztree-get-directory-contens path))
             (dirs (car contents))
             (files (cdr contents)))
        (dolist (dir dirs)
          (let ((short-dir-name (file-basename dir)))
            (when (not (or (string-equal short-dir-name ".")
                           (string-equal short-dir-name "..")
                           (ztree-file-is-in-filter-list short-dir-name)))
              (push (ztree-insert-directory-contents-1 dir (1+ offset))
                    children))))
        (dolist (file files)
          (let ((short-file-name (file-basename file)))
            (when (not (ztree-file-is-in-filter-list short-file-name))
              (push (ztree-insert-entry file (1+ offset) nil)
                    children))))))
    (cons root-line children)))

(defun ztree-insert-entry (path offset expanded)
  (let ((short-name (printable-string (file-basename path)))
        (dir-sign #'(lambda (exp)
                      (insert "[" (if exp "-" "+") "]")))
        (is-dir (file-directory-p path))
        (line (line-number-at-pos)))
    (when (> offset 0)
      (dotimes (i offset)
        (insert " ")
        (insert-char ?\s 3)))           ; insert 3 spaces
    (if is-dir
        (progn
          (funcall dir-sign expanded)
          (insert " " short-name))
      (insert "    " short-name))
    (push (cons path (line-number-at-pos)) ztree-files-info)
    (newline)
    line))

(defun ztree-insert-buffer-header ()
  (insert "Directory tree")
  (newline)
  (insert "==============")
  (newline))


(defun ztree-refresh-buffer (&optional line)
  (interactive)
  (when (and (equal major-mode 'ztree-mode)
             (boundp 'ztree-start-dir))
    (setq ztree-files-info nil)
    (toggle-read-only)
    (erase-buffer)
    (ztree-insert-buffer-header)
    (ztree-insert-directory-contents ztree-start-dir)
    (scroll-to-line (if line line 3))
    (toggle-read-only)))


(defun ztree (path)
  (interactive "DDirectory: ")
  (when (and (file-exists-p path) (file-directory-p path))
    (let ((buf (get-buffer-create (concat "*Directory " path " tree*"))))
      (switch-to-buffer buf)
      (ztree-mode)
      (setq ztree-start-dir (expand-file-name (substitute-in-file-name path)))
      (setq ztree-expanded-dir-list (list ztree-start-dir))
      (setq ztree-filter-list (list ztree-hidden-files-regexp))
      (ztree-refresh-buffer))))


(provide 'ztree)
;;; ztree.el ends here