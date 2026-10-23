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
;; Panels are independent: each has its own frame, Runtime and behaviour, and
;; several may be open at once.  A panel is passive by default: it does not take keyboard focus, it hides
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
;;   :at         Placement, default 'point.  `frame-PLACE' puts the panel
;;               inside the parent frame and `window-PLACE' inside the current
;;               window's text area, where PLACE is one of top-left,
;;               top-center, top-right, center-left, center, center-right,
;;               bottom-left, bottom-center, bottom-right.  `point' and
;;               `point-top' follow point; a cons (X . Y) is frame pixels and
;;               a function is a posframe poshandler.
;;   :cell       (ROW . COLUMN) in character cells, counted from zero at the
;;               top left of the current window's text area.  Takes precedence
;;               over `:at'.
;;   :width      Content columns, default `etaf-posframe-default-width' and
;;               clamped to the parent frame.  Resizing the panel's frame
;;               from outside sets the width instead, and the View re-lays
;;               out at it.
;;   :height     Row budget: content lines the View lays out for, default
;;               `etaf-posframe-default-max-height'.  Taller content clips, and
;;               a frame resized from outside sets the budget instead.
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
;;   :key        Identity of the panel.  Showing a View with a key that is
;;               already live replaces that panel; views with different keys,
;;               or without a key, keep their own frame, Runtime and position,
;;               so several panels stay open at the same time.
;;
;; Signal `etaf-posframe-error' for an unknown option, an invalid anchor or a
;; non-graphical frame.  A failed show unmounts the View and deletes the frame
;; before the error is re-signaled.
;;
;; Function: etaf-posframe-hide (&optional panel)
;;;###autoload (autoload 'etaf-posframe-hide "etaf-posframe" nil t)
;; Hide PANEL and release its Runtime, timer and frame.  PANEL defaults to the
;; newest panel of the current buffer, which is what the panel's own keys call.
;; Other panels stay open.  Return non-nil when a live panel was hidden.  Safe
;; to call repeatedly.
;;
;; Function: etaf-posframe-toggle (view &rest options)
;;;###autoload (autoload 'etaf-posframe-toggle "etaf-posframe" nil t)
;; Hide the panel of the same `:key', or show VIEW with OPTIONS.  Without `:key'
;; this is the newest panel of the current buffer.  Return the new panel, or nil
;; when it hid one.  This is the entry for a key binding that opens and closes
;; the same panel without touching the others.
;;
;; Function: etaf-posframe-refresh (&optional panel)
;;;###autoload (autoload 'etaf-posframe-refresh "etaf-posframe" nil t)
;; Schedule PANEL to re-lay out at its frame width and fit the frame to the
;; rendered content.  PANEL defaults to the current buffer's panel.  A frame
;; resized from outside becomes the panel width, so the View reflows and the
;; title bar repaints to the new column count.  The fit is deferred past the
;; current event and render, so it is safe to call from a Button, a timer or a
;; theme callback.  A panel also re-fits automatically when its host frame
;; changes size.  Return non-nil when PANEL is live.
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
  "Hide every panel anchored to the buffer being killed."
  (let ((buffer (current-buffer)))
    (dolist (panel (copy-sequence (etaf-posframe-panels)))
      (when (eq (etaf-posframe--panel-parent panel) buffer)
        (etaf-posframe-hide panel)))))

(defun etaf-posframe--panel-for-frame (frame)
  "Return the live panel displayed by FRAME, or nil."
  (cl-find-if (lambda (panel) (eq (etaf-posframe--panel-frame panel) frame))
              etaf-posframe--panels))

(defun etaf-posframe--anchor-frame (frame)
  "Return the frame a panel opened from FRAME belongs to.
A panel frame is itself a child: a new panel belongs to the frame underneath,
so closing the covering panel cannot delete the new one with it."
  (if-let* ((panel (etaf-posframe--panel-for-frame frame))
            (parent (etaf-posframe--panel-parent-frame panel))
            ((frame-live-p parent)))
      (etaf-posframe--anchor-frame parent)
    frame))

(defun etaf-posframe--anchor-buffer (buffer)
  "Return the buffer a panel opened in BUFFER belongs to.
A panel whose buffer is current is another panel's surface, possibly shown on
top of a third; the new panel belongs to the first plain buffer, so closing the
covering panel cannot take the new panel with it."
  (let ((panel (and (buffer-live-p buffer)
                    (buffer-local-value 'etaf-posframe--panel buffer))))
    (if (and (etaf-posframe--panel-p panel)
             (buffer-live-p (etaf-posframe--panel-parent panel)))
        (etaf-posframe--anchor-buffer (etaf-posframe--panel-parent panel))
      buffer)))

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
  buffer frame parent parent-frame options timer restore-frame focused
  fit-timer settled fit-window fit-count fit-muted-until)

;; A panel is returned to callers, so it must print: the Runtime and the Theme
;; ref are cyclic (refs, keymaps, closures), and `prin1' on them loops until
;; Emacs runs out of memory.  Both live beside the panel buffer instead and are
;; looked up here; the panel itself only keeps printable slots (buffers,
;; frames, a data plist, timers).

(defvar-local etaf-posframe--theme-ref nil
  "Theme ref of the panel mounted in this buffer.")

(defun etaf-posframe--panel-runtime (panel)
  "Return PANEL's mounted Runtime.
It is looked up from the panel buffer, so the panel struct stays printable."
  (let ((buffer (etaf-posframe--panel-buffer panel)))
    (and (buffer-live-p buffer) (etaf-runtime-for-buffer buffer))))

(defun etaf-posframe--panel-theme (panel)
  "Return PANEL's Theme ref, or nil when the panel is not live."
  (let ((buffer (etaf-posframe--panel-buffer panel)))
    (and (buffer-live-p buffer)
         (buffer-local-value 'etaf-posframe--theme-ref buffer))))

(defconst etaf-posframe--fit-limit 20
  "Fits a panel allows within one second before it backs off.")

(defconst etaf-posframe--fit-backoff 2
  "Seconds a panel stops fitting after it exceeded `etaf-posframe--fit-limit'.")

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

(defconst etaf-posframe--anchor-places
  '(top-left top-center top-right
    center-left center center-right
    bottom-left bottom-center bottom-right)
  "Nine places an anchor can name inside its rectangle.")

(defconst etaf-posframe--anchors
  (append '(point point-top)
          (cl-loop for kind in '(frame window)
                   append (cl-loop for place in etaf-posframe--anchor-places
                                   collect (intern (format "%s-%s" kind place)))))
  "Anchors accepted by `etaf-posframe-show' :at.
`frame-*' names the whole parent frame, `window-*' the parent window's text
area, and every place is one of `etaf-posframe--anchor-places'.  `point' and
`point-top' place the panel at point.")

(defconst etaf-posframe--option-keys
  '(:at :cell :width :height :header :draggable :pinned :focusable
    :auto-focus :dismiss :timeout :theme :on-close :key)
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
          (:cell
           (unless (and (consp value)
                        (wholenump (car value)) (wholenump (cdr value)))
             (signal 'etaf-posframe-error
                     (list (format "Panel :cell must be a (ROW . COLUMN) pair of non-negative integers: %S"
                                   value)))))
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

(defun etaf-posframe--rect (info kind)
  "Return (LEFT TOP RIGHT BOTTOM) pixels for anchor KIND.
KIND is `frame' for the whole parent frame or `window' for the parent window's
text area."
  (if (eq kind 'window)
      (let* ((window (plist-get info :parent-window))
             (edges (and (window-live-p window)
                         (window-inside-pixel-edges window))))
        (or edges (list 0 0 0 0)))
    (let ((frame (plist-get info :parent-frame)))
      (list 0 0
            (or (plist-get info :parent-frame-width)
                (and (frame-live-p frame) (frame-pixel-width frame))
                0)
            (or (plist-get info :parent-frame-height)
                (and (frame-live-p frame) (frame-pixel-height frame))
                0)))))

(defun etaf-posframe--anchor-position (info kind place)
  "Return the pixel position of PLACE inside KIND for INFO.
The panel keeps a margin to the edge it is anchored to, so it never sits on the
parent's scroll bar or window border."
  (let* ((rect (etaf-posframe--rect info kind))
         (left (nth 0 rect))
         (top (nth 1 rect))
         (right (nth 2 rect))
         (bottom (nth 3 rect))
         (width (or (plist-get info :posframe-width) 0))
         (height (or (plist-get info :posframe-height) 0))
         (margin (if (eq kind 'window) 4 8))
         (right-edge (max left (- right width margin)))
         (bottom-edge (max top (- bottom height margin)))
         (x (pcase place
              ((or 'top-left 'center-left 'bottom-left) left)
              ((or 'top-right 'center-right 'bottom-right) right-edge)
              (_ (max left (/ (- right left width) 2)))))
         (y (pcase place
              ((or 'top-left 'top-center 'top-right) (+ top margin))
              ((or 'bottom-left 'bottom-center 'bottom-right) bottom-edge)
              (_ (max top (/ (- bottom top height) 2))))))
    (cons x y)))

(defvar etaf-posframe--anchor-handlers
  (let (table)
    (dolist (kind '(frame window))
      (dolist (place etaf-posframe--anchor-places)
        (let ((kind kind) (place place))
          (push (cons (intern (format "%s-%s" kind place))
                      (lambda (info) (etaf-posframe--anchor-position info kind place)))
                table))))
    table)
  "Poshandler of every symbol in `etaf-posframe--anchors'.")

(defun etaf-posframe--cell-poshandler (cell)
  "Return a poshandler that puts the panel at CELL, a (ROW . COLUMN) pair.
Rows and columns count from the top left of the parent window's text area and
start at zero, so (0 . 0) is its first cell."
  (lambda (info)
    (let* ((rect (etaf-posframe--rect info 'window))
           (row (car cell))
           (column (cdr cell))
           (char-width (or (plist-get info :font-width)
                           (frame-char-width (or (plist-get info :parent-frame)
                                                 (selected-frame)))))
           (line-prefix (if (plist-get info :respect-header-line)
                            (plist-get info :header-line-height)
                          0))
           (char-height (or (plist-get info :font-height) 0)))
      (cons (+ (nth 0 rect) (* column char-width))
            (+ (nth 1 rect) (* row char-height) (or line-prefix 0))))))

(defun etaf-posframe--poshandler (at)
  "Return the posframe poshandler for anchor AT."
  (pcase at
    ('point #'posframe-poshandler-point-bottom-left-corner-upward)
    ('point-top #'posframe-poshandler-point-top-left-corner)
    ((pred functionp) at)
    (_ (or (cdr (assq at etaf-posframe--anchor-handlers))
           (signal 'etaf-posframe-error (list "Unsupported panel :at" at))))))

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
     (if-let* ((cell (plist-get options :cell)))
         (list :poshandler (etaf-posframe--cell-poshandler cell))
       (if (and (consp at) (numberp (car at)) (numberp (cdr at)))
           (list :position at)
         (list :poshandler (etaf-posframe--poshandler at)))))))

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

(defun etaf-posframe--row-budget (panel)
  "Return PANEL's content row budget, the `:height' it opened with."
  (let ((options (etaf-posframe--panel-options panel)))
    (or (plist-get options :height) etaf-posframe-default-max-height)))

(defun etaf-posframe--resize-to-content (panel window)
  "Fit PANEL's frame height to WINDOW's rendered rows.
The rendered content decides the height, but never beyond the rows the panel
was opened for: a View that fills its viewport, such as a complete app, would
otherwise stretch the frame to the measuring budget.  The clamp also keeps a
transient measurement from stretching the frame into an empty rectangle.
Return non-nil when the frame size changed; sizing a frame to the size it
already has is what turns one resize into a stream of size-change hooks."
  (let* ((frame (window-frame window))
         (options (etaf-posframe--panel-options panel))
         (width (plist-get options :pixel-width))
         (line (frame-char-height frame))
         (header (if (plist-get options :header)
                     (window-header-line-height window)
                   0))
         (height (min (+ (or (etaf-posframe--text-height panel window) 0) header)
                      (+ (* (etaf-posframe--row-budget panel) line) header))))
    (when (and width (> height 0)
               (or (/= width (frame-pixel-width frame))
                   (/= height (frame-pixel-height frame))))
      (set-frame-size frame width height t)
      t)))

(defun etaf-posframe--fit-height (panel window)
  "Lay PANEL out in its row budget, then fit the frame to the content."
  (let* ((options (etaf-posframe--panel-options panel))
         (width (plist-get options :pixel-width))
         (runtime (etaf-posframe--panel-runtime panel)))
    ;; The measuring layout uses the row budget rather than an open-ended
    ;; height: a View that paints a full viewport would report that budget as
    ;; its content, and its `:height' rows are what the panel promises.
    (etaf-runtime-refit runtime width (etaf-posframe--row-budget panel))
    (etaf-posframe--resize-to-content panel window)
    (etaf-runtime-refit runtime width nil)
    (etaf-posframe--fit panel)))

(defun etaf-posframe--show-frame (panel lines)
  "Show PANEL's frame for LINES of content and return its frame.
Re-fit once when the settled window width changes the content height."
  (let* ((budget (etaf-posframe--row-budget panel))
         (lines (max 1 (min lines budget)))
         (args (etaf-posframe--frame-args panel lines))
         (buffer (etaf-posframe--panel-buffer panel)))
    (apply #'posframe-show buffer args)
    (dotimes (_ 2)
      (let ((window (get-buffer-window buffer t)))
        (when (window-live-p window)
          (set-window-scroll-bars window 0 nil nil)
          (etaf-posframe--fit panel)
          (let ((settled (min budget (etaf-posframe--lines buffer))))
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
        (unless (etaf-posframe--panel-for-buffer parent)
          (remove-hook 'kill-buffer-hook #'etaf-posframe--parent-killed t))
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

(defun etaf-posframe--panel-for-key (key)
  "Return the live panel whose `:key' is KEY, or nil.
Panels without a `:key' share the nil identity, so showing one replaces the
previous one; panels with distinct keys coexist."
  (cl-find-if (lambda (panel)
                (equal key (plist-get (etaf-posframe--panel-options panel) :key)))
              etaf-posframe--panels))

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
  ;; A new panel belongs to the frame the user is working in.  When a panel has
  ;; focus, its child frame is selected, and parenting the new panel to it would
  ;; delete the new panel together with the covering one.  Keep the caller's
  ;; buffer as the anchor, not the buffer the outer window happens to show.
  (let* ((called-buffer (current-buffer))
         (anchor-frame (etaf-posframe--anchor-frame (selected-frame))))
    (when (and (frame-live-p anchor-frame)
               (not (eq anchor-frame (selected-frame))))
      (select-frame anchor-frame)
      (set-buffer called-buffer)))
  (let* ((options (etaf-posframe--default-dismiss
                   (etaf-posframe--validate (copy-sequence options))))
         (parent-frame (selected-frame))
         (parent-buffer (etaf-posframe--anchor-buffer (current-buffer)))
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
    ;; Only the same key replaces a panel: different keys keep their own
    ;; frame, Runtime and position, so several panels stay open at once.
    (when-let* ((previous (etaf-posframe--panel-for-key
                           (plist-get options :key))))
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
            ;; The Theme ref lives beside the panel buffer: the panel struct
            ;; stays printable, and the frame arguments read the same ref.
            (with-current-buffer buffer
              (setq etaf-posframe--theme-ref theme-ref))
            (setq panel (etaf-posframe--make-panel
                         :buffer buffer
                         :options options
                         :parent parent-buffer
                         :parent-frame parent-frame))
            (setf (etaf-posframe--panel-frame panel)
                  (etaf-posframe--show-frame
                   panel (max 1 (etaf-posframe--lines buffer))))
            ;; From here on a frame resized from outside re-lays the View out
            ;; at its new width instead of being snapped back.
            (setf (etaf-posframe--panel-settled panel) t)
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
  "Hide the panel of the same `:key', or show VIEW with OPTIONS.
Without `:key' this is the panel of the current buffer.  Return the new panel,
or nil when it hid one."
  (let* ((options (etaf-posframe--validate (copy-sequence options)))
         (panel (if (plist-member options :key)
                    (etaf-posframe--panel-for-key (plist-get options :key))
                  (etaf-posframe--current-panel))))
    (if panel
        (progn (etaf-posframe-hide panel) nil)
      (apply #'etaf-posframe-show view options))))

;;;###autoload
(defun etaf-posframe--adopt-frame-size (panel window)
  "Adopt the width and row budget of a frame resized from outside.
An outside resize (a caller's `set-frame-size', a tiling step) sets the frame
size, so the canvas follows it instead of snapping the frame back to the
columns and rows the panel opened with.  A taller or shorter frame becomes the
new row budget, which lets a View that fills its viewport, such as a complete
app, show more or fewer rows.  Return non-nil when the panel adopted a size."
  (let* ((frame (window-frame window))
         (options (etaf-posframe--panel-options panel))
         (char (frame-char-width frame))
         (width (window-body-width window t))
         (header (if (plist-get options :header)
                     (window-header-line-height window)
                   0))
         (rows (max 1 (floor (- (window-pixel-height window) header)
                             (float (frame-char-height frame)))))
         (budget (etaf-posframe--row-budget panel))
         (content (etaf-posframe--lines (etaf-posframe--panel-buffer panel)))
         (adopted options)
         (resized nil))
    (when (and (etaf-posframe--panel-settled panel)
               (> width 0)
               (/= width (or (plist-get options :pixel-width) 0)))
      (setq adopted (plist-put (plist-put (copy-sequence adopted)
                                         :pixel-width width)
                               :width (max 1 (round (/ width (float char)))))
            resized t)
      (when-let* ((text (plist-get adopted :header))
                  (theme-ref (etaf-posframe--panel-theme panel))
                  (theme (and (etaf-ref-p theme-ref) (etaf-value theme-ref)))
                  (buffer (etaf-posframe--panel-buffer panel)))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (setq-local header-line-format
                        (etaf-posframe--header-format
                         text theme (plist-get adopted :width)))))))
    ;; A resize away from the row budget is the new budget: taller always, and
    ;; shorter only when it cuts into the content.  The panel's own fit sets
    ;; the frame to the content height, which must not shrink the budget.
    (when (and (etaf-posframe--panel-settled panel)
               (or (> rows budget) (< rows (min budget content))))
      (setq adopted (plist-put (copy-sequence adopted) :height rows)
            resized t))
    (when resized
      (setf (etaf-posframe--panel-options panel) adopted)
      ;; The retained renderer owns the layout, so the new size is laid out
      ;; once here, deferred out of the resize event that reported it.
      (etaf-runtime-refit (etaf-posframe--panel-runtime panel) width rows))
    resized))

;;;###autoload
(defun etaf-posframe--fit-now (panel)
  "Re-lay out PANEL at its frame size and fit the frame to the content.
Runs outside render and event callbacks; it never touches the buffer.  Only a
real size change re-lays the View out: re-laying out for a size the panel
already has is the cost that made a resize feel like a stall.  A panel that
fits more often than `etaf-posframe--fit-limit' in one second backs off for
`etaf-posframe--fit-backoff', so a condition that keeps resizing it can never
run away with the CPU."
  (when (and (etaf-posframe-live-p panel)
             (or (null (etaf-posframe--panel-fit-muted-until panel))
                 (< (float-time) (etaf-posframe--panel-fit-muted-until panel))))
    (let* ((now (float-time))
           (start (etaf-posframe--panel-fit-window panel))
           (count (if (and start (< (- now start) 1.0))
                      (1+ (or (etaf-posframe--panel-fit-count panel) 0))
                    1)))
      (setf (etaf-posframe--panel-fit-window panel) (if (= count 1) now start)
            (etaf-posframe--panel-fit-count panel) count)
      (if (> count etaf-posframe--fit-limit)
          (progn
            (setf (etaf-posframe--panel-fit-muted-until panel)
                  (+ now etaf-posframe--fit-backoff)
                  (etaf-posframe--panel-fit-count panel) 0
                  (etaf-posframe--panel-fit-window panel) nil)
            (message "ETAF panel: %s fitted %d times in one second; backing off %ss"
                     (buffer-name (etaf-posframe--panel-buffer panel))
                     count etaf-posframe--fit-backoff))
        (let* ((buffer (etaf-posframe--panel-buffer panel))
               (window (get-buffer-window buffer t)))
          (when (window-live-p window)
            ;; A frame resized from outside re-lays the View out at its new
            ;; width and rows; a content change needs no re-layout, because
            ;; ETAF already rendered it and a second layout writer duplicates
            ;; rows.  Either way only the frame height follows the content.
            (let ((adopted (etaf-posframe--adopt-frame-size panel window))
                  (fitted (etaf-posframe--resize-to-content panel window)))
              (when (and (or adopted fitted)
                         (etaf-posframe--panel-settled panel))
                (etaf-posframe--fit panel)))))))))

;;;###autoload
(defun etaf-posframe-refresh (&optional panel)
  "Schedule PANEL to fit its frame after the current event finishes.
PANEL defaults to the current buffer's panel.  Call it after the View's
content or style changed, or after the frame was resized; a frame resized from
outside becomes the panel width and the View re-lays out at it.  The fit is
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
  "Re-fit the panels FRAME hosts or the panel FRAME itself after a resize."
  (dolist (panel (copy-sequence etaf-posframe--panels))
    (when (or (eq (etaf-posframe--panel-parent-frame panel) frame)
              (eq (etaf-posframe--panel-frame panel) frame))
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
