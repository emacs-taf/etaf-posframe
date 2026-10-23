;;; etaf-posframe.el --- Floating ETAF panels in child frames -*- lexical-binding: t; -*-

;; Copyright (C) 2026 ETAF contributors
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: ETAF contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf "0.3.0") (posframe "0.9.0"))
;; Keywords: frames, ui
;; URL: https://github.com/emacs-taf/etaf-posframe

;;; Commentary:

;; Public API
;;
;; This package shows any ETAF View in a floating child frame, so a panel does
;; not occupy a window, does not replace the current buffer and does not disturb
;; the user's window layout.  It renders with ETAF, sizes the frame from the
;; rendered content and owns the panel lifecycle.  Graphical frames only.
;;
;; A panel is passive by default: it does not take keyboard focus, it hides
;; before the next command outside the panel, and it never changes the selected
;; buffer.  `:focusable' gives it keyboard input, `:pinned' keeps it open until
;; it is closed explicitly and `:draggable' moves it by dragging its header
;; line.  Several panels may be open at the same time.
;;
;; Load this package with (require 'etaf-posframe) after adding this repository,
;; ETAF and Posframe roots to `load-path'.  Only the interfaces listed below are
;; supported for use by other packages; unlisted symbols are internal even
;; without a double hyphen.
;;
;; Function: etaf-posframe-show (view &rest options)
;;;###autoload (autoload 'etaf-posframe-show "etaf-posframe" nil t)
;; Show VIEW in a floating panel and return the panel.  VIEW is a View or a
;; zero-argument function returning one; it is mounted fresh for this panel and
;; receives its own Runtime.  The panel follows the current buffer at call time.
;; OPTIONS is a plist:
;;
;;   :at         'point (default), 'point-top, 'window-center,
;;               'window-top-center, 'window-bottom-center,
;;               'window-top-right, 'window-bottom-right, 'frame-center,
;;               a cons (X . Y) of absolute pixels, or a poshandler function.
;;   :width      Content columns, default `etaf-posframe-default-width' and
;;               clamped to the parent frame.
;;   :height     Maximum content lines, default
;;               `etaf-posframe-default-max-height'; taller content clips.
;;   :header     Header line text.  Without it the panel has no header line and
;;               cannot be dragged.
;;   :draggable  Move the panel by dragging HEADER.  Defaults to `:pinned'.
;;   :pinned     Keep the panel open regardless of `:dismiss'.  Default nil.
;;   :focusable  Let the panel take keyboard focus, so its View `:keys', text
;;               inputs and buttons receive input.  Default nil.
;;   :auto-focus Default `:focusable'.  Select the panel on open so its keys
;;               work without a click; nil leaves it unfocused until clicked.
;;   :dismiss    'auto (default) hides before the next command outside the
;;               panel; 'focus-out hides when the panel loses focus; nil keeps
;;               it until `etaf-posframe-hide'.
;;   :timeout    Seconds after which the panel hides by itself.
;;   :theme      ETAF UI Theme plist; defaults to `etaf-posframe-theme' for the
;;               current frame, so catalog Components match the user's frame.
;;   :on-close   Function called with the panel after it was hidden.
;;
;; Signal `etaf-posframe-error' for an unknown option, an invalid anchor or a
;; non-graphical frame.  A failed show unmounts the View and deletes the frame
;; before the error is re-signaled.
;;
;; Function: etaf-posframe-hide (&optional panel)
;;;###autoload (autoload 'etaf-posframe-hide "etaf-posframe" nil t)
;; Hide PANEL and release its Runtime, timer and frame.  PANEL defaults to the
;; panel of the current buffer, which is what the panel's own keys call.  Return
;; non-nil when a live panel was hidden.  Safe to call repeatedly.
;;
;; Function: etaf-posframe-toggle (view &rest options)
;;;###autoload (autoload 'etaf-posframe-toggle "etaf-posframe" nil t)
;; Hide the current buffer's live panel, or show VIEW with OPTIONS.  Return the
;; new panel, or nil when it hid one.  This is the entry for a key binding that
;; opens and closes the same panel.
;;
;; Function: etaf-posframe-refresh (&optional panel)
;;;###autoload (autoload 'etaf-posframe-refresh "etaf-posframe" nil t)
;; Schedule PANEL to re-lay out at its frame width and fit the frame to the
;; rendered content.  PANEL defaults to the current buffer's panel.  The fit
;; is deferred past the current event and render, so it is safe to call from a
;; Button, a timer or a theme callback.  A panel also re-fits automatically
;; when its host frame changes size.  Return non-nil when PANEL is live.
;;
;; Function: etaf-posframe-live-p (panel)
;; Return non-nil while PANEL's frame exists and its Runtime is mounted.
;;
;; Function: etaf-posframe-panels ()
;; Return the live panels, most recent first.
;;
;; Function: etaf-posframe-theme (&optional frame)
;; Return an ETAF UI Theme plist derived from FRAME's default face.
;; Pass it to `etaf-theme-provide' in a Component `:setup' when a panel builds
;; its own boundary.  Panels created by `etaf-posframe-show' already provide it.
;;
;; Variable: etaf-posframe-default-width
;; Columns of a new panel when `:width' is absent.
;;
;; Variable: etaf-posframe-default-max-height
;; Maximum content lines of a new panel when `:height' is absent.
;;
;; Variable: etaf-posframe-panel-keys
;; Keymap that is always active while a focusable panel has focus.  It closes
;; the panel on `q', `ESC' and `C-g' and outranks the View's own keys only for
;; those three bindings.
;;
;; Error: etaf-posframe-error
;; Signals invalid panel input and unavailable capabilities.

;;; Code:

(require 'cl-lib)
(require 'etaf)
(require 'posframe)

(defgroup etaf-posframe nil
  "Floating ETAF panels in child frames."
  :group 'etaf
  :prefix "etaf-posframe-")

(defcustom etaf-posframe-default-width 56
  "Content columns of a panel without :width."
  :type 'integer
  :group 'etaf-posframe)

(defcustom etaf-posframe-default-max-height 30
  "Maximum content lines of a panel without :height."
  :type 'integer
  :group 'etaf-posframe)

(defconst etaf-posframe--margin 2
  "Free columns kept between a panel and its parent frame edge.")

(define-error 'etaf-posframe-error "ETAF panel error")

(defvar etaf-posframe--panels nil
  "Live panels, most recent first.")

(defvar etaf-posframe--counter 0
  "Panel sequence number used for buffer names.")

(defvar-local etaf-posframe--panel nil
  "Panel shown in this buffer, or nil.")

(defvar etaf-posframe--dismissing nil
  "Non-nil while a dismissal pass runs, to avoid re-entrant hooks.")

(defvar-local etaf-posframe--parent-panel nil
  "Panel anchored to this buffer, or nil.")

(defun etaf-posframe--parent-killed ()
  "Hide the panel anchored to the buffer being killed."
  (when (and etaf-posframe--parent-panel
             (memq etaf-posframe--parent-panel etaf-posframe--panels))
    (etaf-posframe-hide etaf-posframe--parent-panel)))

(defvar etaf-posframe-panel-keys
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'etaf-posframe-hide)
    (define-key map [escape] #'etaf-posframe-hide)
    (define-key map (kbd "C-g") #'etaf-posframe-hide)
    map)
  "Keys active while a focusable panel has focus.
They close the panel without consulting the View.")

(add-to-list 'emulation-mode-map-alists
             (list (cons 'etaf-posframe--panel etaf-posframe-panel-keys)))

(cl-defstruct (etaf-posframe--panel (:constructor etaf-posframe--make-panel))
  buffer frame runtime parent parent-frame options timer restore-frame focused
  theme fit-timer)

;;; Theme

(defun etaf-posframe--color (color)
  "Return COLOR as an #RRGGBB string, or nil when it is not a color."
  (when (and (stringp color)
             (ignore-errors (color-name-to-rgb color)))
    (apply #'color-rgb-to-hex
           (append (color-name-to-rgb color) '(2)))))

(defun etaf-posframe--mix (from to amount)
  "Mix hex colors FROM and TO by AMOUNT toward TO."
  (let ((start (color-name-to-rgb from))
        (end (color-name-to-rgb to)))
    (apply #'color-rgb-to-hex
           (append (cl-mapcar (lambda (a b) (+ a (* (- b a) amount))) start end)
                   '(2)))))

(defun etaf-posframe-theme (&optional frame)
  "Return an ETAF UI Theme plist derived from FRAME's default face.
FRAME defaults to the selected frame.  Every value is an #RRGGBB color, so the
result is a literal token plist accepted by `etaf-theme-provide'."
  (let* ((frame (or frame (selected-frame)))
         (bg (or (etaf-posframe--color
                  (face-attribute 'default :background nil frame))
                 "#FFFFFF"))
         (fg (or (etaf-posframe--color
                  (face-attribute 'default :foreground nil frame))
                 "#000000"))
         (dark (eq (frame-parameter frame 'background-mode) 'dark))
         ;; The panel must read as a surface above the buffer, not blend
         ;; into it: lift it clearly in dark themes and drop it in light ones.
         (panel (etaf-posframe--mix bg (if dark "#FFFFFF" "#000000")
                                    (if dark 0.10 0.05)))
         (border (etaf-posframe--mix panel fg 0.30))
         (muted (etaf-posframe--mix fg panel 0.42))
         (accent (or (etaf-posframe--color
                      (ignore-errors (face-attribute 'link :foreground nil frame)))
                     (if dark "#6CB6FF" "#2F6FE4")))
         (tint (lambda (color amount)
                 (etaf-posframe--mix panel color amount))))
    (list :ui-bg bg
          :ui-fg fg
          :ui-muted-fg muted
          :ui-border border
          :ui-panel-bg panel
          :ui-panel-fg fg
          :ui-panel-border border
          :ui-accent accent
          :ui-accent-fg (if dark "#101418" "#FFFFFF")
          :ui-accent-soft-bg (funcall tint accent 0.18)
          :ui-disabled-fg (etaf-posframe--mix fg panel 0.6)
          :ui-disabled-bg (etaf-posframe--mix panel border 0.12)
          :ui-disabled-border border
          :ui-button-primary-fg (if dark "#101418" "#FFFFFF")
          :ui-button-primary-bg accent
          :ui-button-secondary-fg (etaf-posframe--mix fg accent 0.35)
          :ui-button-secondary-bg (funcall tint accent 0.18)
          :ui-button-ghost-fg fg
          :ui-info-bg (funcall tint "#6CB6FF" 0.20)
          :ui-info-fg (etaf-posframe--mix fg "#6CB6FF" 0.55)
          :ui-info-border (etaf-posframe--mix panel "#6CB6FF" 0.40)
          :ui-success-bg (funcall tint "#4FB477" 0.20)
          :ui-success-fg (etaf-posframe--mix fg "#4FB477" 0.50)
          :ui-success-border (etaf-posframe--mix panel "#4FB477" 0.40)
          :ui-warning-bg (funcall tint "#E8B45C" 0.20)
          :ui-warning-fg (etaf-posframe--mix fg "#E8B45C" 0.55)
          :ui-warning-border (etaf-posframe--mix panel "#E8B45C" 0.40)
          :ui-danger-bg (funcall tint "#FF7A7A" 0.20)
          :ui-danger-fg (etaf-posframe--mix fg "#FF7A7A" 0.55)
          :ui-danger-border (etaf-posframe--mix panel "#FF7A7A" 0.40))))

;;; Themed surface

(etaf-define-component etaf-posframe--surface (&key theme content)
  "Provide THEME to the panel's CONTENT View."
  :setup (etaf-theme-provide theme)
  :render (etaf-view (expr content)))

;;; Options

(defconst etaf-posframe--anchors
  '(point point-top window-center window-top-center window-bottom-center
    window-top-right window-bottom-right frame-center frame-top-right
    frame-bottom-right)
  "Anchors accepted by `etaf-posframe-show' :at.")

(defconst etaf-posframe--option-keys
  '(:at :width :height :header :draggable :pinned :focusable :auto-focus
    :dismiss :timeout :theme :on-close)
  "Options accepted by `etaf-posframe-show'.")

(defun etaf-posframe--validate (options)
  "Return OPTIONS after checking every key and value."
  (unless (proper-list-p options)
    (signal 'etaf-posframe-error (list "Panel options must be a plist" options)))
  (let (result)
    (while options
      (let ((key (pop options))
            (value (pop options)))
        (unless (memq key etaf-posframe--option-keys)
          (signal 'etaf-posframe-error
                  (list (format "Unknown panel option: %S" key))))
        (pcase key
          ((or :width :height :timeout)
           (unless (and (numberp value) (> value 0))
             (signal 'etaf-posframe-error
                     (list (format "Panel %s must be a positive number: %S"
                                   key value)))))
          (:dismiss
           (unless (memq value '(auto focus-out nil))
             (signal 'etaf-posframe-error
                     (list (format "Panel :dismiss must be auto, focus-out or nil: %S"
                                   value)))))
          (:at
           (unless (or (memq value etaf-posframe--anchors)
                       (functionp value)
                       (and (consp value) (numberp (car value))
                            (numberp (cdr value))))
             (signal 'etaf-posframe-error
                     (list (format "Unsupported panel :at: %S" value)))))
          (:on-close
           (unless (or (null value) (functionp value))
             (signal 'etaf-posframe-error
                     (list "Panel :on-close must be a function" value))))
          (:theme
           (unless (or (null value) (proper-list-p value)
                       (etaf-ref-p value) (etaf-computed-p value))
             (signal 'etaf-posframe-error
                     (list "Panel :theme must be a plist, ref or computed"
                           value)))))
        (setq result (plist-put result key value))))
    result))

(defun etaf-posframe--right-corner (info bottom)
  "Return the top-right or, with BOTTOM, bottom-right corner for INFO.
Anchor inside the parent window's text area: posframe's corner handlers use
the frame edge, which overlaps the parent's vertical scroll bar and shows it
over the panel."
  (let* ((window (plist-get info :parent-window))
         (edges (and (window-live-p window) (window-inside-pixel-edges window)))
         (width (or (plist-get info :posframe-width) 0))
         (height (or (plist-get info :posframe-height) 0))
         (margin 4))
    (if (null edges)
        (cons 0 0)
      (cons (max 0 (- (nth 2 edges) width margin))
            (if bottom
                (max 0 (- (nth 3 edges) height margin))
              (+ (nth 1 edges) margin))))))

(defun etaf-posframe--poshandler (at)
  "Return the posframe poshandler for anchor AT."
  (pcase at
    ('point #'posframe-poshandler-point-bottom-left-corner-upward)
    ('point-top #'posframe-poshandler-point-top-left-corner)
    ('window-center #'posframe-poshandler-window-center)
    ('window-top-center #'posframe-poshandler-window-top-center)
    ('window-bottom-center #'posframe-poshandler-window-bottom-center)
    ('window-top-right
     (lambda (info) (etaf-posframe--right-corner info nil)))
    ('window-bottom-right
     (lambda (info) (etaf-posframe--right-corner info t)))
    ('frame-center #'posframe-poshandler-frame-center)
    ('frame-top-right
     (lambda (info)
       (let* ((parent-frame (plist-get info :parent-frame))
              (width (or (plist-get info :posframe-width) 0))
              (margin 8))
         (cons (max 0 (- (frame-pixel-width parent-frame) width margin))
               margin))))
    ('frame-bottom-right
     (lambda (info)
       (let* ((parent-frame (plist-get info :parent-frame))
              (width (or (plist-get info :posframe-width) 0))
              (height (or (plist-get info :posframe-height) 0))
              (margin 8))
         (cons (max 0 (- (frame-pixel-width parent-frame) width margin))
               (max 0 (- (frame-pixel-height parent-frame) height margin))))))
    ((pred functionp) at)
    (_ (signal 'etaf-posframe-error (list "Unsupported panel :at" at)))))

(defun etaf-posframe--draggable-p (options)
  "Return non-nil when OPTIONS make the panel draggable."
  (and (plist-get options :header)
       (or (plist-get options :draggable)
           (plist-get options :pinned))))

;;; Dismissal

(defun etaf-posframe--auto-panel-p (panel)
  "Return non-nil when PANEL hides before the next outside command."
  (and (eq (plist-get (etaf-posframe--panel-options panel) :dismiss) 'auto)
       (not (plist-get (etaf-posframe--panel-options panel) :pinned))))

(defun etaf-posframe--pre-command ()
  "Hide auto panels before a command that runs outside them."
  (unless etaf-posframe--dismissing
    (let ((etaf-posframe--dismissing t))
      (dolist (panel (copy-sequence etaf-posframe--panels))
        (when (and (etaf-posframe--auto-panel-p panel)
                   (not (eq (current-buffer)
                            (etaf-posframe--panel-buffer panel))))
          (etaf-posframe-hide panel))))))

(defun etaf-posframe--focus-change ()
  "Hide transient panels when focus leaves them or their parent frame."
  (unless etaf-posframe--dismissing
    (let ((etaf-posframe--dismissing t)
          (selected (selected-frame)))
      (dolist (panel (copy-sequence etaf-posframe--panels))
        (let* ((frame (etaf-posframe--panel-frame panel))
               (parent (etaf-posframe--panel-parent-frame panel))
               (dismiss (plist-get (etaf-posframe--panel-options panel) :dismiss)))
          (cond
           ((not (frame-live-p frame)))
           ((eq selected frame)
            (setf (etaf-posframe--panel-focused panel) t))
           ((and (etaf-posframe--panel-focused panel)
                 (memq dismiss '(auto focus-out)))
            (etaf-posframe-hide panel))
           ((and (eq dismiss 'auto)
                 (not (plist-get (etaf-posframe--panel-options panel) :pinned))
                 (not (eq selected parent))
                 (eq (frame-focus-state parent) nil))
            (etaf-posframe-hide panel))))))))

(defun etaf-posframe--refresh-hooks ()
  "Install the dismiss hooks exactly while a panel needs them."
  (if (cl-some #'etaf-posframe--auto-panel-p etaf-posframe--panels)
      (add-hook 'pre-command-hook #'etaf-posframe--pre-command)
    (remove-hook 'pre-command-hook #'etaf-posframe--pre-command))
  (if (cl-some (lambda (panel)
                 (memq (plist-get (etaf-posframe--panel-options panel) :dismiss)
                       '(auto focus-out)))
               etaf-posframe--panels)
      (add-function :after after-focus-change-function
                    #'etaf-posframe--focus-change)
    (remove-function after-focus-change-function
                     #'etaf-posframe--focus-change)))

;;; Rendering

(defun etaf-posframe--lines (buffer)
  "Return the number of rendered lines in BUFFER."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((count 0))
        (while (not (eobp))
          (forward-line 1)
          (cl-incf count))
        count))))

(defun etaf-posframe--header-format (header theme width)
  "Return HEADER as a full-width title bar for THEME and WIDTH columns."
  (when header
    (let* ((text (concat " " header))
           (padding (max 0 (- width (string-width text))))
           (bar (concat text (make-string padding ?\s))))
      (propertize bar
                  'face (list :background (plist-get theme :ui-panel-bg)
                              :foreground (plist-get theme :ui-panel-fg)
                              :weight 'bold
                              :height 1.0
                              ;; A theme may render its own header line
                              ;; inverted; the title bar keeps the panel's
                              ;; palette and paints every column.
                              :inverse-video nil
                              :extend t)
                  'underline (list :color (plist-get theme :ui-panel-border)
                                   :style 'line)))))

(defun etaf-posframe--prepare-buffer (buffer header theme width)
  "Set BUFFER up as a panel surface with HEADER and THEME."
  (let ((theme theme))
    (with-current-buffer buffer
      (erase-buffer)
      (setq-local truncate-lines t)
      (setq-local buffer-display-table
                  (copy-sequence (or buffer-display-table
                                     standard-display-table
                                     (make-display-table))))
      (set-display-table-slot buffer-display-table 'truncation ?\s)
      (setq-local header-line-format
                  (etaf-posframe--header-format header theme width))
      (setq-local mode-line-format nil)
      (setq-local cursor-type nil)
      (setq-local vertical-scroll-bar nil)
      (setq-local horizontal-scroll-bar nil))))

(defun etaf-posframe--frame-args (panel lines)
  "Return the `posframe-show' arguments for PANEL showing LINES of content."
  (let* ((options (etaf-posframe--panel-options panel))
         (header (plist-get options :header))
         (at (or (plist-get options :at) 'point))
         (focusable (plist-get options :focusable)))
    (append
     (list :width (plist-get options :width)
           :height (+ lines (if header 1 0))
           :min-height (+ 1 (if header 1 0))
           :left-fringe 0
           :right-fringe 0
           :border-width 0
           :internal-border-width 0
           :respect-header-line (and header t)
           :accept-focus (and focusable t)
           :background-color (or (plist-get (etaf-value
                                         (etaf-posframe--panel-theme panel))
                                        :ui-bg)
                             "#FFFFFF")
           :foreground-color (or (plist-get (etaf-value
                                             (etaf-posframe--panel-theme panel))
                                            :ui-fg)
                                 "#000000")
           :override-parameters
           (append
            '((horizontal-scroll-bars . nil)
              (vertical-scroll-bars . nil)
              (top-visible . 24)
              (snap-width . 12))
            (when (etaf-posframe--draggable-p options)
              '((drag-with-header-line . t)))))
     (if (and (consp at) (numberp (car at)) (numberp (cdr at)))
         (list :position at)
       (list :poshandler (etaf-posframe--poshandler at))))))

(defun etaf-posframe--fit (panel)
  "Fit PANEL's Runtime to WINDOW's frame width and its body height.
Follow the frame width, not the window's, because a transient scroll bar
would otherwise narrow the canvas and leave a scroll bar strip on the right."
  (let ((runtime (etaf-posframe--panel-runtime panel))
        (width (plist-get (etaf-posframe--panel-options panel) :pixel-width)))
    (etaf-runtime-refit runtime width nil)))

(defun etaf-posframe--text-height (panel window)
  "Return the pixel height of PANEL's rendered content in WINDOW."
  (condition-case nil
      (with-current-buffer (etaf-posframe--panel-buffer panel)
        (save-excursion
          (goto-char (point-max))
          (skip-chars-backward " \t\n")
          (cdr (window-text-pixel-size window nil (point) nil 10000 t))))
    (error nil)))

(defun etaf-posframe--resize-to-content (panel window)
  "Fit PANEL's frame height to WINDOW's rendered rows.
The measured height is clamped to the row count plus one line of slack, so a
transient measurement can never stretch the frame into an empty rectangle."
  (let* ((frame (window-frame window))
         (buffer (etaf-posframe--panel-buffer panel))
         (options (etaf-posframe--panel-options panel))
         (width (plist-get options :pixel-width))
         (rows (max 1 (etaf-posframe--lines buffer)))
         (line (frame-char-height frame))
         (header (if (plist-get options :header)
                     (window-header-line-height window)
                   0))
         (height (+ (or (etaf-posframe--text-height panel window) 0) header))
         (limit (+ (* (1+ rows) line) header 32)))
    (when (and width (> height 0) (<= height limit))
      (set-frame-size frame width height t))))

(defun etaf-posframe--fit-height (panel window)
  "Lay PANEL's content out without clipping, then fit the frame to it."
  (let* ((width (plist-get (etaf-posframe--panel-options panel) :pixel-width))
         (runtime (etaf-posframe--panel-runtime panel)))
    (etaf-runtime-refit runtime width 400)
    (etaf-posframe--resize-to-content panel window)
    (etaf-runtime-refit runtime width nil)
    (etaf-posframe--fit panel)))

(defun etaf-posframe--show-frame (panel lines)
  "Show PANEL's frame for LINES of content and return its frame.
Re-fit once when the settled window width changes the content height."
  (let ((args (etaf-posframe--frame-args panel lines))
        (buffer (etaf-posframe--panel-buffer panel)))
    (apply #'posframe-show buffer args)
    (dotimes (_ 2)
      (let ((window (get-buffer-window buffer t)))
        (when (window-live-p window)
          (set-window-scroll-bars window 0 nil nil)
          (etaf-posframe--fit panel)
          (let ((settled (etaf-posframe--lines buffer)))
            (unless (= settled lines)
              (setq lines settled)
              (apply #'posframe-show buffer
                     (plist-put (copy-sequence args) :height
                                (+ settled (if (plist-get
                                               (etaf-posframe--panel-options panel)
                                               :header)
                                               1 0)))))))))
    (let ((window (get-buffer-window buffer t)))
      (unless (window-live-p window)
        (signal 'etaf-posframe-error (list "Panel frame did not appear" buffer)))
      (set-window-scroll-bars window 0 nil nil)
      (etaf-posframe--fit-height panel window)
      (window-frame window))))

(defun etaf-posframe--teardown (panel)
  "Release PANEL's frame, Runtime and timer without callbacks."
  (let ((buffer (etaf-posframe--panel-buffer panel))
        (frame (etaf-posframe--panel-frame panel))
        (parent (etaf-posframe--panel-parent panel))
        (restore (etaf-posframe--panel-restore-frame panel)))
    (when (buffer-live-p parent)
      (with-current-buffer parent
        (remove-hook 'kill-buffer-hook #'etaf-posframe--parent-killed t)
        (when (eq etaf-posframe--parent-panel panel)
          (setq etaf-posframe--parent-panel nil))))
    (when (and (frame-live-p restore)
               (eq (selected-frame) frame))
      (select-frame restore))
    (when-let* ((timer (etaf-posframe--panel-timer panel)))
      (cancel-timer timer)
      (setf (etaf-posframe--panel-timer panel) nil))
    (when-let* ((timer (etaf-posframe--panel-fit-timer panel)))
      (cancel-timer timer)
      (setf (etaf-posframe--panel-fit-timer panel) nil))
    (when (buffer-live-p buffer)
      (ignore-errors (posframe-hide buffer)))
    (when (buffer-live-p buffer)
      (ignore-errors (posframe-delete-frame buffer)))
    (when (buffer-live-p buffer)
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (ignore-errors (etaf-unmount runtime)))
      (ignore-errors (kill-buffer buffer)))
    (ignore frame)))

;;;###autoload
(defun etaf-posframe--focus (panel)
  "Select PANEL's frame and window, remembering the frame to restore."
  (let ((frame (etaf-posframe--panel-frame panel)))
    (when (frame-live-p frame)
      (setf (etaf-posframe--panel-restore-frame panel) (selected-frame))
      (select-frame frame)
      (when-let* ((window (get-buffer-window (etaf-posframe--panel-buffer panel) t)))
        (select-window window)
        (set-window-point window (point-min))
        (setf (etaf-posframe--panel-focused panel) t)))))

(defun etaf-posframe-hide (&optional panel)
  "Hide PANEL and release its Runtime, timer and frame.
PANEL defaults to the panel of the current buffer.  Return non-nil when a live
panel was hidden."
  (interactive)
  (when-let* ((panel (or panel (etaf-posframe--current-panel))))
    (setq etaf-posframe--panels (delq panel etaf-posframe--panels))
    (etaf-posframe--teardown panel)
    (etaf-posframe--refresh-hooks)
    (when-let* ((callback (plist-get (etaf-posframe--panel-options panel)
                                     :on-close)))
      (condition-case error
          (funcall callback panel)
        (error (message "ETAF panel on-close failed: %s"
                        (error-message-string error)))))
    t))

(defun etaf-posframe--apply-theme ()
  "Apply the current frame Theme to every live panel."
  (dolist (panel (copy-sequence etaf-posframe--panels))
    (let ((theme (etaf-posframe--panel-theme panel))
          (parent-frame (etaf-posframe--panel-parent-frame panel)))
      (when (and (etaf-ref-p theme) (frame-live-p parent-frame))
        (ignore-errors
          (let* ((palette (etaf-posframe-theme parent-frame))
                 (frame (etaf-posframe--panel-frame panel)))
            (etaf-batch (setf (etaf-value theme) palette))
            (when (frame-live-p frame)
              (set-frame-parameter frame 'background-color
                                   (plist-get palette :ui-bg))
              (set-frame-parameter frame 'foreground-color
                                   (plist-get palette :ui-fg)))
            (let ((buffer (etaf-posframe--panel-buffer panel))
                  (header (plist-get (etaf-posframe--panel-options panel)
                                     :header))
                  (width (plist-get (etaf-posframe--panel-options panel)
                                    :width)))
              (when (buffer-live-p buffer)
                (with-current-buffer buffer
                  (setq-local header-line-format
                              (etaf-posframe--header-format
                               header palette width)))))
            ))))))

(defun etaf-posframe--theme-changed (&rest _)
  "Re-derive panels' Theme after `load-theme' finished."
  (run-at-time 0.1 nil #'etaf-posframe--apply-theme))

(add-hook 'enable-theme-functions #'etaf-posframe--theme-changed)
(add-hook 'window-size-change-functions #'etaf-posframe--window-size-changed)

(defun etaf-posframe--panel-for-buffer (buffer)
  "Return the live panel anchored to BUFFER."
  (cl-find-if (lambda (panel) (eq (etaf-posframe--panel-parent panel) buffer))
              etaf-posframe--panels))

(defun etaf-posframe--current-panel ()
  "Return the panel of the current buffer, panel buffer included."
  (or etaf-posframe--panel
      (etaf-posframe--panel-for-buffer (current-buffer))))

;;;###autoload
(defun etaf-posframe--default-dismiss (options)
  "Return OPTIONS with the default :dismiss for its focus mode.
A focusable panel is an independent surface: it keeps its own keys and is
closed explicitly.  A passive panel is a preview: it hides before the next
command outside it."
  (if (plist-member options :dismiss)
      options
    (plist-put options :dismiss
               (if (plist-get options :focusable) nil 'auto))))

(defun etaf-posframe-show (view &rest options)
  "Show VIEW in a floating panel and return the panel.
VIEW is a View or a zero-argument function returning one.  OPTIONS is the plist
described in the package Commentary."
  (unless (or (functionp view) view)
    (signal 'etaf-posframe-error (list "Panel View is nil")))
  (let* ((options (etaf-posframe--default-dismiss
                   (etaf-posframe--validate (copy-sequence options))))
         (parent-frame (selected-frame))
         (parent-buffer (current-buffer))
         (char-width (frame-char-width parent-frame))
         (available (max 20 (- (/ (frame-pixel-width parent-frame) char-width)
                               (* 2 etaf-posframe--margin))))
         (columns (min (or (plist-get options :width)
                           etaf-posframe-default-width)
                       available))
         (max-height (or (plist-get options :height)
                         etaf-posframe-default-max-height))
         (theme (or (plist-get options :theme)
                    (etaf-posframe-theme parent-frame)))
         (theme-ref (if (or (etaf-ref-p theme) (etaf-computed-p theme))
                        theme
                      (etaf-ref theme)))
         (resolved (if (functionp view) (funcall view) view))
         (options (plist-put options :width columns))
         (options (plist-put options :pixel-width (* columns char-width)))
         (panel nil)
         buffer)
    (unless (display-graphic-p)
      (signal 'etaf-posframe-error
              (list "ETAF panels need a graphical frame")))
    (when-let* ((previous (etaf-posframe--panel-for-buffer parent-buffer)))
      (etaf-posframe-hide previous))
    (unless resolved
      (signal 'etaf-posframe-error (list "Panel View returned nil" view)))
    (setq buffer (generate-new-buffer
                  (format " *ETAF Panel %d*" (cl-incf etaf-posframe--counter))))
    (etaf-posframe--prepare-buffer buffer (plist-get options :header)
                                   (etaf-value theme-ref)
                                   (plist-get options :width))
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (lambda ()
                        (etaf-view
                         (etaf-posframe--surface :theme theme-ref
                                                 :content resolved)))
                      (list :viewport-width (* columns char-width)
                            :viewport-height max-height))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (unless runtime
              (signal 'etaf-posframe-error
                      (list "Panel View did not mount" view)))
            (setq panel (etaf-posframe--make-panel
                         :buffer buffer
                         :runtime runtime
                         :options options
                         :parent parent-buffer
                         :parent-frame parent-frame
                         :theme theme-ref))
            (setf (etaf-posframe--panel-frame panel)
                  (etaf-posframe--show-frame
                   panel (max 1 (etaf-posframe--lines buffer))))
            (with-current-buffer buffer
              (setq etaf-posframe--panel panel))
            (with-current-buffer parent-buffer
              (setq etaf-posframe--parent-panel panel)
              (add-hook 'kill-buffer-hook #'etaf-posframe--parent-killed nil t))
            (push panel etaf-posframe--panels)
            (when-let* ((timeout (plist-get options :timeout)))
              (setf (etaf-posframe--panel-timer panel)
                    (run-at-time timeout nil
                                 (lambda ()
                                   (when (memq panel etaf-posframe--panels)
                                     (etaf-posframe-hide panel))))))
            (when (and (plist-get options :focusable)
                       (if (plist-member options :auto-focus)
                           (plist-get options :auto-focus)
                         t))
              (etaf-posframe--focus panel))
            (etaf-posframe--refresh-hooks)
            panel))
      (unless panel
        (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
          (ignore-errors (etaf-unmount runtime)))
        (when (buffer-live-p buffer)
          (ignore-errors (posframe-hide buffer))
          (ignore-errors (posframe-delete-frame buffer))
          (kill-buffer buffer))))))

;;;###autoload
(defun etaf-posframe-toggle (view &rest options)
  "Hide the current buffer's live panel, or show VIEW with OPTIONS.
Return the new panel, or nil when it hid one."
  (if-let* ((panel (etaf-posframe--current-panel)))
      (progn (etaf-posframe-hide panel) nil)
    (apply #'etaf-posframe-show view options)))

;;;###autoload
(defun etaf-posframe--fit-now (panel)
  "Re-lay out PANEL at its frame width and fit the frame to the content.
Runs outside render and event callbacks; it never touches the buffer."
  (when (etaf-posframe-live-p panel)
    (let* ((buffer (etaf-posframe--panel-buffer panel))
           (window (get-buffer-window buffer t)))
      (when (window-live-p window)
        ;; No re-layout here: ETAF already re-rendered the View after the
        ;; change, and a second layout writer duplicates rows.  Only the frame
        ;; height follows the rendered content.
        (etaf-posframe--resize-to-content panel window)))))

;;;###autoload
(defun etaf-posframe-refresh (&optional panel)
  "Schedule PANEL to fit its frame after the current event finishes.
PANEL defaults to the current buffer's panel.  Call it after the View's
content or style changed, or after the frame was resized; the fit itself is
deferred so it never runs inside a render or an event callback.  Return
non-nil when PANEL is live."
  (interactive)
  (let ((panel (or panel (etaf-posframe--current-panel))))
    (when (etaf-posframe-live-p panel)
      (when-let* ((timer (etaf-posframe--panel-fit-timer panel)))
        (cancel-timer timer))
      (setf (etaf-posframe--panel-fit-timer panel)
            (run-at-time 0.05 nil
                         (lambda ()
                           (setf (etaf-posframe--panel-fit-timer panel) nil)
                           (ignore-errors (etaf-posframe--fit-now panel)))))
      t)))

(defun etaf-posframe--window-size-changed (frame)
  "Re-fit panels hosted by FRAME after its size changed."
  (dolist (panel (copy-sequence etaf-posframe--panels))
    (when (eq (etaf-posframe--panel-parent-frame panel) frame)
      (etaf-posframe-refresh panel))))

(defun etaf-posframe-panel-theme (panel)
  "Return PANEL's current Theme plist, or nil when it is not live."
  (when (etaf-posframe-live-p panel)
    (let ((theme (etaf-posframe--panel-theme panel)))
      (and (etaf-ref-p theme) (etaf-value theme)))))

(defun etaf-posframe-current-theme ()
  "Return the Theme of the panel whose View is rendering, or nil."
  (let ((runtime (ignore-errors (etaf-runtime-for-buffer (current-buffer)))))
    (when runtime
      (let ((panel (cl-find-if
                    (lambda (panel)
                      (eq (etaf-posframe--panel-runtime panel) runtime))
                    etaf-posframe--panels)))
        (and panel (etaf-posframe-panel-theme panel))))))

(defun etaf-posframe-live-p (panel)
  "Return non-nil while PANEL's frame exists and its Runtime is mounted."
  (and (etaf-posframe--panel-p panel)
       (frame-live-p (etaf-posframe--panel-frame panel))
       (etaf-runtime-mounted-p (etaf-posframe--panel-runtime panel))))

(defun etaf-posframe-panels ()
  "Return the live panels, most recent first."
  (cl-remove-if-not #'etaf-posframe-live-p etaf-posframe--panels))

(provide 'etaf-posframe)
;;; etaf-posframe.el ends here
