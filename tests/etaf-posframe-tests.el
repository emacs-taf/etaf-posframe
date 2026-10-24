;;; etaf-posframe-tests.el --- Public panel behaviour -*- lexical-binding: t; -*-

;; Copyright (C) 2026 ETAF contributors
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Public behaviour of `etaf-posframe'.  Cases that need a child frame are
;; skipped in batch Emacs and run in a graphical verification instance.

;;; Code:

(require 'ert)
(require 'seq)
(require 'etaf-posframe)

(ert-deftest etaf-posframe-rejects-invalid-options ()
  "Reject bad options with a message that names the option."
  (let ((view (etaf-view (text "panel"))))
    (should (string-match-p
             "bogus"
             (error-message-string
              (should-error (etaf-posframe-show view :bogus 1)
                            :type 'etaf-posframe-error))))
    (should (string-match-p
             "width"
             (error-message-string
              (should-error (etaf-posframe-show view :width 0)
                            :type 'etaf-posframe-error))))
    (should (string-match-p
             "dismiss"
             (error-message-string
              (should-error (etaf-posframe-show view :dismiss 'never)
                            :type 'etaf-posframe-error))))
    (should (string-match-p
             ":at"
             (error-message-string
              (should-error (etaf-posframe-show view :at 'nowhere)
                            :type 'etaf-posframe-error))))
    (should (string-match-p
             "theme-mode"
             (error-message-string
              (should-error (etaf-posframe-show view :theme-mode 'sepia)
                            :type 'etaf-posframe-error))))))

(ert-deftest etaf-posframe-theme-returns-frame-colors ()
  "Derive a complete Theme plist with hex colors from the frame."
  (let ((theme (etaf-posframe-theme)))
    (dolist (key '(:ui-panel-bg :ui-panel-fg :ui-border :ui-muted-fg
                   :ui-accent :ui-info-bg :ui-danger-fg))
      (should (string-match-p "\\`#[0-9A-Fa-f]\\{6\\}\\'"
                              (plist-get theme key))))))

(ert-deftest etaf-posframe-live-p-rejects-non-panels ()
  "Only a live panel counts as live."
  (should-not (etaf-posframe-live-p nil))
  (should-not (etaf-posframe-live-p 'not-a-panel))
  (should-not (etaf-posframe-panels)))

(ert-deftest etaf-posframe-show-owns-panel-lifecycle ()
  "Show mounts one panel and hide releases it."
  (skip-unless (display-graphic-p))
  (let* ((view (etaf-view (text "panel")))
         (panel (etaf-posframe-show view :width 24 :height 4)))
    (should (etaf-posframe-live-p panel))
    (should (= 1 (length (etaf-posframe-panels))))
    (should (etaf-posframe-hide panel))
    (should-not (etaf-posframe-live-p panel))
    (should-not (etaf-posframe-panels))))

(ert-deftest etaf-posframe-toggle-hides-the-open-panel ()
  "Toggle hides the current buffer's panel and reports nil."
  (skip-unless (display-graphic-p))
  (let* ((view (etaf-view (text "panel")))
         (panel (etaf-posframe-toggle view :width 24 :height 4)))
    (unwind-protect
        (progn
          (should (etaf-posframe-live-p panel))
          (should-not (etaf-posframe-toggle view :width 24 :height 4))
          (should-not (etaf-posframe-panels)))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-show-replaces-the-buffer-panel ()
  "A second show for the same buffer replaces its panel."
  (skip-unless (display-graphic-p))
  (let* ((view (etaf-view (text "panel")))
         (first (etaf-posframe-show view :width 24 :height 3)))
    (unwind-protect
        (progn
          (should (= 1 (length (etaf-posframe-panels))))
          (let ((second (etaf-posframe-show view :width 24 :height 3)))
            (should (= 1 (length (etaf-posframe-panels))))
            (should-not (etaf-posframe-live-p first))
            (should (etaf-posframe-live-p second))))
      (mapc #'etaf-posframe-hide (etaf-posframe-panels)))))

(ert-deftest etaf-posframe-timeout-closes-the-panel ()
  "A panel with :timeout hides by itself."
  (skip-unless (display-graphic-p))
  (let* ((view (etaf-view (text "panel")))
         (panel (etaf-posframe-show view :width 24 :height 3 :timeout 0.2))
         (deadline (+ (float-time) 3)))
    (should (etaf-posframe-live-p panel))
    ;; Poll instead of sleeping a fixed span: a busy session runs the hide
    ;; timer late, and the panel still has to close.
    (while (and (etaf-posframe-live-p panel) (< (float-time) deadline))
      (sleep-for 0.05))
    (should-not (etaf-posframe-live-p panel))
    (should-not (etaf-posframe-panels))))

(ert-deftest etaf-posframe-focusable-panel-takes-and-restores-focus ()
  "A focusable panel is selected on open and restores the previous frame."
  (skip-unless (display-graphic-p))
  (let* ((view (etaf-view (text "panel")))
         (origin (selected-frame))
         (panel (etaf-posframe-show view :width 24 :height 3 :focusable t)))
    (unwind-protect
        (progn
          (should (etaf-posframe-live-p panel))
          (should-not (eq (selected-frame) origin))
          (should (frame-parent (selected-frame))))
      (etaf-posframe-hide panel))
    (should (eq (selected-frame) origin))))

(ert-deftest etaf-posframe-killing-the-parent-buffer-closes-the-panel ()
  "Killing the buffer that owns a panel hides that panel."
  (skip-unless (display-graphic-p))
  (let ((buffer (generate-new-buffer " *etaf-posframe-test-parent*")))
    (unwind-protect
        (with-current-buffer buffer
          (let ((panel (etaf-posframe-show (etaf-view (text "panel"))
                                           :width 24 :height 3)))
            (should (etaf-posframe-live-p panel))
            (kill-buffer buffer)
            (should-not (etaf-posframe-live-p panel))
            (should-not (etaf-posframe-panels))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(defun etaf-posframe-tests--panel-frame (parent)
  "Return the single child frame of PARENT that shows a panel."
  (let ((frames (seq-filter (lambda (frame) (eq (frame-parent frame) parent))
                            (frame-list))))
    (should (= 1 (length frames)))
    (car frames)))

(defun etaf-posframe-tests--top-frame ()
  "Return a top level frame, whatever the previous case left selected."
  (or (seq-find (lambda (frame) (null (frame-parent frame))) (frame-list))
      (selected-frame)))

(defun etaf-posframe-tests--placement (parent columns lines &rest options)
  "Show a COLUMNS x LINES panel with OPTIONS in PARENT.
Return a plist with the frame `:at' offset and its `:size'; the frame shrinks to
its content, so its height is not the requested line count."
  (let ((panel (apply #'etaf-posframe-show (etaf-view (text "x"))
                      :width columns :height lines options)))
    (unwind-protect
        (let ((frame (etaf-posframe-tests--panel-frame parent)))
          (list :at (cons (frame-parameter frame 'left)
                          (frame-parameter frame 'top))
                :size (cons (frame-pixel-width frame)
                            (frame-pixel-height frame))))
      (etaf-posframe-hide panel))))

(defun etaf-posframe-tests--panel-window (frame)
  "Return the window FRAME shows its panel in."
  (frame-root-window frame))

(defun etaf-posframe-tests--panel-buffer (frame)
  "Return the buffer FRAME displays."
  (window-buffer (etaf-posframe-tests--panel-window frame)))

(defun etaf-posframe-tests--with-pointer-on (frame function)
  "Call FUNCTION with the window system reporting the pointer on FRAME.
A child frame cannot be pointed at from Lisp, so the position query the panel
follows is answered instead."
  (cl-letf (((symbol-function 'mouse-pixel-position)
             (lambda () (list frame 5 5))))
    (funcall function)))

(defun etaf-posframe-tests--luminance (color)
  "Return the relative luminance of COLOR."
  (apply #'+ (cl-mapcar (lambda (weight channel) (* weight channel))
                        '(0.2126 0.7152 0.0722)
                        (color-name-to-rgb color))))

(ert-deftest etaf-posframe-frame-is-as-wide-as-the-canvas ()
  "A panel frame is exactly as wide as its content columns.
The frame used to keep whatever width posframe gave it, so a font metric
mismatch left empty frame to the right of the canvas."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (char (frame-char-width parent))
         (columns (max 20 (- (/ (frame-pixel-width parent) char) 8)))
         (panel (etaf-posframe-show (etaf-view (text "panel"))
                                    :width columns)))
    (unwind-protect
        (let* ((frame (etaf-posframe-tests--panel-frame parent))
               (window (etaf-posframe-tests--panel-window frame)))
          ;; The border is painted outside the text area, so the visible
          ;; content keeps exactly the panel's column width.
          (should (= (* columns char) (window-body-width window t)))
          (should (= (frame-text-width frame) (window-body-width window t)))
          (should (= columns (window-body-width window))))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-frame-is-not-taller-than-the-content ()
  "A one-line panel fits its frame instead of leaving empty rows below."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (line (frame-char-height parent))
         (panel (etaf-posframe-show (etaf-view (text "panel"))
                                    :width 24 :height 6)))
    (unwind-protect
        (let* ((frame (etaf-posframe-tests--panel-frame parent))
               (window (etaf-posframe-tests--panel-window frame))
               (height (frame-pixel-height frame)))
          (should (<= height (* 2 line)))
          (should (<= (cdr (window-text-pixel-size window (point-min) (point-max)
                                                   nil nil t))
                      height)))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-header-bar-paints-the-full-width ()
  "The title bar covers every column and keeps the panel's own palette."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (panel (etaf-posframe-show (etaf-view (text "panel"))
                                    :width 24 :header "ETAF")))
    (unwind-protect
        (let* ((frame (etaf-posframe-tests--panel-frame parent))
               (header (with-current-buffer (etaf-posframe-tests--panel-buffer frame)
                         header-line-format))
               (face (get-text-property 0 'face header)))
          (should (= 24 (string-width header)))
          (should (eq t (plist-get face :extend)))
          (should (memq :inverse-video face))
          (should-not (plist-get face :inverse-video)))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-frame-follows-an-outside-resize ()
  "A frame resized from outside becomes the panel width, canvas included."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (char (frame-char-width parent))
         (columns (max 20 (- (/ (frame-pixel-width parent) char) 40)))
         (panel (etaf-posframe-show (etaf-view (text "panel"))
                                    :width columns :header "ETAF")))
    (unwind-protect
        (let* ((frame (etaf-posframe-tests--panel-frame parent))
               (window (etaf-posframe-tests--panel-window frame))
               (buffer (etaf-posframe-tests--panel-buffer frame))
               (width (+ (* columns char) (* 10 char))))
          (set-frame-size frame width 400 t)
          ;; The resize is reported by the next redisplay, which then defers
          ;; the re-layout out of its own callback.
          (redisplay t)
          (sleep-for 0.4)
          (should (= width (window-body-width window t)))
          (should (= width (car (etaf-runtime-viewport
                                 (etaf-runtime-for-buffer buffer)))))
          (should (= (/ width char)
                     (string-width (with-current-buffer buffer
                                     header-line-format))))
          ;; A later fit keeps the adopted width instead of snapping back.
          (etaf-posframe-refresh panel)
          (sleep-for 0.3)
          (should (= width (window-body-width window t))))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-frame-adopts-a-shorter-height ()
  "A frame shortened below the content becomes the new row budget."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (line (frame-char-height parent))
         (char (frame-char-width parent))
         (panel (etaf-posframe-show
                 (etaf-view (column :item-gap '(lh 0)
                                    (text "r1") (text "r2") (text "r3")
                                    (text "r4") (text "r5") (text "r6")))
                 :width 24 :height 6)))
    (unwind-protect
        (let* ((frame (etaf-posframe-tests--panel-frame parent))
               (window (etaf-posframe-tests--panel-window frame)))
          (should (<= 6 (window-body-height window)))
          (set-frame-size frame (* 24 char) (* 3 line) t)
          (redisplay t)
          (sleep-for 0.4)
          (should (= 3 (window-body-height window))))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-panel-prints-without-recursing ()
  "Printing a panel finishes, so evaluating a show call cannot hang Emacs.
`C-x C-e' prints the returned panel into the buffer; a Runtime or Theme ref
slot made that print follow a cycle until Emacs ran out of memory."
  (skip-unless (display-graphic-p))
  (let ((panel (etaf-posframe-show (etaf-view (text "panel"))
                                   :width 20 :height 2)))
    (unwind-protect
        (let ((text (with-timeout (2 :print-did-not-finish)
                      (let ((print-circle nil)
                            (print-level nil)
                            (print-length nil))
                        (prin1-to-string panel)))))
          (should (stringp text))
          (should (string-match-p "etaf-posframe--panel" text)))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-panels-coexist-by-key ()
  "Panels with different keys stay open together and hide independently."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (first (etaf-posframe-show (etaf-view (text "first")) :key 'first
                                    :width 24 :height 2))
         (second (etaf-posframe-show (etaf-view (text "second")) :key 'second
                                     :width 24 :height 2)))
    (unwind-protect
        (progn
          (should (etaf-posframe-live-p first))
          (should (etaf-posframe-live-p second))
          (should (= 2 (length (etaf-posframe-panels))))
          (should (= 2 (length (seq-filter (lambda (frame) (frame-parent frame))
                                          (frame-list)))))
          (should (etaf-posframe-hide first))
          (should-not (etaf-posframe-live-p first))
          (should (etaf-posframe-live-p second))
          (should (= 1 (length (etaf-posframe-panels)))))
      (ignore-errors (etaf-posframe-hide second))
      (ignore-errors (etaf-posframe-hide first))
      (ignore-errors (etaf-posframe-tests--panel-frame parent)))))

(ert-deftest etaf-posframe-show-replaces-the-same-key ()
  "A second show with the same key replaces that panel and nothing else."
  (skip-unless (display-graphic-p))
  (let* ((first (etaf-posframe-show (etaf-view (text "first")) :key 'same
                                    :width 24 :height 2))
         (other (etaf-posframe-show (etaf-view (text "other")) :key 'other
                                    :width 24 :height 2))
         (replacement (etaf-posframe-show (etaf-view (text "third")) :key 'same
                                          :width 24 :height 2)))
    (unwind-protect
        (progn
          (should-not (etaf-posframe-live-p first))
          (should (etaf-posframe-live-p replacement))
          (should (etaf-posframe-live-p other))
          (should (= 2 (length (etaf-posframe-panels)))))
      (ignore-errors (etaf-posframe-hide replacement))
      (ignore-errors (etaf-posframe-hide other)))))

(ert-deftest etaf-posframe-toggle-targets-its-key ()
  "Toggle hides the panel of its own key and leaves the others open."
  (skip-unless (display-graphic-p))
  (let* ((first (etaf-posframe-show (etaf-view (text "first")) :key 'first
                                    :width 24 :height 2 :pinned t))
         (second (etaf-posframe-show (etaf-view (text "second")) :key 'second
                                     :width 24 :height 2 :pinned t)))
    (unwind-protect
        (progn
          (should-not (etaf-posframe-toggle (etaf-view (text "first")) :key 'first
                                            :width 24 :height 2))
          (should-not (etaf-posframe-live-p first))
          (should (etaf-posframe-live-p second)))
      (ignore-errors (etaf-posframe-hide second)))))

(ert-deftest etaf-posframe-anchors-place-panels-in-the-grid ()
  "Frame and window anchors put a panel at the expected place.
Each assertion uses the size of the frame it just measured, because a panel is
sized from its content."
  (skip-unless (display-graphic-p))
  (let* ((parent (etaf-posframe-tests--top-frame))
         (frame-width (frame-pixel-width parent))
         (frame-height (frame-pixel-height parent))
         (edges (window-inside-pixel-edges (selected-window)))
         (margin 8)
         (window-margin 4))
    (cl-labels ((place (anchor)
                  (etaf-posframe-tests--placement parent 20 2 :at anchor))
                (at-of (anchor) (plist-get (place anchor) :at))
                (size-of (anchor) (plist-get (place anchor) :size)))
      (should (equal (at-of 'frame-top-left) (cons 0 margin)))
      (let ((size (size-of 'frame-top-left)))
        (should (equal (at-of 'frame-top-right)
                       (cons (- frame-width (car size) margin) margin))))
      (let ((size (size-of 'frame-bottom-left)))
        (should (equal (at-of 'frame-bottom-left)
                       (cons 0 (- frame-height (cdr size) margin)))))
      (let ((size (size-of 'frame-bottom-right)))
        (should (equal (at-of 'frame-bottom-right)
                       (cons (- frame-width (car size) margin)
                             (- frame-height (cdr size) margin)))))
      (let ((size (size-of 'frame-center)))
        (should (equal (at-of 'frame-center)
                       (cons (/ (- frame-width (car size)) 2)
                             (/ (- frame-height (cdr size)) 2)))))
      (should (equal (at-of 'window-top-left)
                     (cons (nth 0 edges) (+ (nth 1 edges) window-margin))))
      (let ((size (size-of 'window-bottom-right)))
        (should (equal (at-of 'window-bottom-right)
                       (cons (- (nth 2 edges) (car size) window-margin)
                             (- (nth 3 edges) (cdr size) window-margin))))))))

(ert-deftest etaf-posframe-cell-places-a-panel-at-character-cells ()
  "A :cell pair lands on the same cell whatever the panel size."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (edges (window-inside-pixel-edges (selected-window)))
         (char-width (frame-char-width parent))
         (char-height (frame-char-height parent))
         (origin (cons (nth 0 edges) (nth 1 edges))))
    (should (equal (plist-get (etaf-posframe-tests--placement
                               parent 20 2 :cell '(0 . 0))
                              :at)
                   origin))
    (should (equal (plist-get (etaf-posframe-tests--placement
                               parent 30 4 :cell '(0 . 0))
                              :at)
                   origin))
    (should (equal (plist-get (etaf-posframe-tests--placement
                               parent 20 2 :cell '(3 . 5))
                              :at)
                   (cons (+ (car origin) (* 5 char-width))
                         (+ (cdr origin) (* 3 char-height)))))))

(ert-deftest etaf-posframe-rejects-a-bad-cell ()
  "A :cell that is not a pair of non-negative integers signals an error."
  (let ((view (etaf-view (text "x"))))
    (dolist (cell '((-1 . 2) (1.5 . 2) 3 ("a" . 1)))
      (should (string-match-p
               ":cell"
               (error-message-string
                (should-error (etaf-posframe-show view :cell cell)
                              :type 'etaf-posframe-error)))))))

(ert-deftest etaf-posframe-panel-opened-in-a-panel-is-independent ()
  "A panel opened while another panel has focus outlives that panel."
  (skip-unless (display-graphic-p))
  (let* ((buffer (get-buffer-create " *etaf-posframe-test-owner*"))
         (first nil)
         (second nil))
    (unwind-protect
        (with-current-buffer buffer
          (setq first (etaf-posframe-show (etaf-view (text "first"))
                                          :key 'first :width 24 :height 2
                                          :focusable t))
          ;; The first panel is focused now, so its buffer is current: the
          ;; second panel would otherwise belong to it and die with it.
          (setq second (etaf-posframe-show (etaf-view (text "second"))
                                           :key 'second :width 24 :height 2))
          (should (= 2 (length (etaf-posframe-panels))))
          (etaf-posframe-hide first)
          (should-not (etaf-posframe-live-p first))
          (should (etaf-posframe-live-p second))
          (kill-buffer buffer)
          (should-not (etaf-posframe-live-p second))
          (should-not (etaf-posframe-panels)))
      (ignore-errors (etaf-posframe-hide second))
      (ignore-errors (etaf-posframe-hide first))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest etaf-posframe-hiding-a-focused-panel-returns-focus ()
  "Hiding a focused panel selects the frame it came from, and the next show works.
`select-frame' alone leaves the window system without a key window, so the
command after a close used to freeze."
  (skip-unless (display-graphic-p))
  (let* ((view (etaf-view (text "panel")))
         (origin (selected-frame))
         (panel (etaf-posframe-show view :width 24 :height 3 :focusable t)))
    (unwind-protect
        (progn
          (should-not (eq (selected-frame) origin))
          (should (etaf-posframe-hide panel))
          (should (eq (selected-frame) origin))
          (should (window-live-p (selected-window)))
          (let ((again (with-timeout (5 (error "opening a panel again hung"))
                         (etaf-posframe-show view :width 24 :height 3))))
            (should (etaf-posframe-live-p again))
            (etaf-posframe-hide again)))
      (ignore-errors (etaf-posframe-hide panel)))))

(ert-deftest etaf-posframe-stacks-panels-at-the-same-anchor ()
  "Panels opened at one anchored place are laid out one below the other."
  (skip-unless (display-graphic-p))
  (let* ((first (etaf-posframe-show (etaf-view (text "first")) :key 'first
                                    :at 'frame-top-right :stack t
                                    :width 24 :height 3))
         (second (etaf-posframe-show (etaf-view (text "second")) :key 'second
                                     :at 'frame-top-right :stack t
                                     :width 24 :height 3))
         (third (etaf-posframe-show (etaf-view (text "third")) :key 'third
                                    :at 'frame-top-right :stack t
                                    :width 24 :height 3)))
    (unwind-protect
        (let ((y1 (frame-parameter (etaf-posframe-panel-frame first) 'top))
              (y2 (frame-parameter (etaf-posframe-panel-frame second) 'top))
              (y3 (frame-parameter (etaf-posframe-panel-frame third) 'top))
              (height (frame-pixel-height (etaf-posframe-panel-frame first)))
              (x1 (frame-parameter (etaf-posframe-panel-frame first) 'left))
              (x3 (frame-parameter (etaf-posframe-panel-frame third) 'left)))
          (should (= x1 x3))
          ;; Stacked downward, evenly, without overlapping.
          (should (< y1 y2 y3))
          (should (>= (- y2 y1) height))
          (should (= (- y2 y1) (- y3 y2))))
      (ignore-errors (etaf-posframe-hide third))
      (ignore-errors (etaf-posframe-hide second))
      (ignore-errors (etaf-posframe-hide first)))))

(ert-deftest etaf-posframe-draws-a-theme-bordered-panel ()
  "A panel carries a border in the given colour without losing content width."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (char (frame-char-width parent))
         (panel (etaf-posframe-show (etaf-view (text "x"))
                                    :width 24 :height 2
                                    :border-width 2 :border-color "#123456")))
    (unwind-protect
        (let ((frame (etaf-posframe-tests--panel-frame parent)))
          (should (= 2 (frame-parameter frame 'child-frame-border-width)))
          (should (= (* 24 char) (window-body-width
                                  (etaf-posframe-tests--panel-window frame) t)))
          (should (equal "#123456"
                         (face-attribute 'child-frame-border :background frame))))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-rejects-stack-without-an-anchor ()
  ":stack needs an anchored place, not a cell or a pixel pair."
  (let ((view (etaf-view (text "x"))))
    (dolist (options '((:stack t :cell (0 . 0))
                       (:stack t :at (10 . 10))))
      (should (string-match-p
               "stack"
               (error-message-string
                (should-error (apply #'etaf-posframe-show view options)
                              :type 'etaf-posframe-error)))))))

(ert-deftest etaf-posframe-registered-apps-open-with-one-call ()
  "A registered application opens and closes with one call, next to others."
  (skip-unless (display-graphic-p))
  (let ((saved-apps etaf-posframe-apps)
        (saved-map etaf-posframe-app-map)
        (first nil)
        (second nil))
    (unwind-protect
        (progn
          (etaf-posframe-register-app 'test-one
                                      :title "One" :key "1"
                                      :create #'ignore
                                      :view (lambda (_session) (etaf-view (text "one")))
                                      :width 20 :height 2)
          (etaf-posframe-register-app 'test-two
                                      :title "Two" :key "2"
                                      :create #'ignore
                                      :view (lambda (_session) (etaf-view (text "two")))
                                      :width 20 :height 2)
          (should (commandp (lookup-key etaf-posframe-app-map "1")))
          (should (commandp (lookup-key etaf-posframe-app-map "2")))
          (setq first (etaf-posframe-app 'test-one)
                second (etaf-posframe-app 'test-two))
          (should (etaf-posframe-live-p first))
          (should (etaf-posframe-live-p second))
          (should-not (eq (etaf-posframe-panel-frame first)
                          (etaf-posframe-panel-frame second)))
          (should-not (etaf-posframe-app 'test-one))
          (should-not (etaf-posframe-live-p first))
          (should (etaf-posframe-live-p second)))
      (ignore-errors (etaf-posframe-hide second))
      (ignore-errors (etaf-posframe-hide first))
      (setq etaf-posframe-apps saved-apps
            etaf-posframe-app-map saved-map))))

(ert-deftest etaf-posframe-cycle-walks-panels-and-back ()
  "Cycling focuses each panel in turn, then returns to the frame behind them."
  (skip-unless (display-graphic-p))
  (let* ((origin (selected-frame))
         (first (etaf-posframe-show (etaf-view (text "first")) :key 'cycle-one
                                    :width 24 :height 2 :pinned t))
         (second (etaf-posframe-show (etaf-view (text "second")) :key 'cycle-two
                                     :width 24 :height 2 :pinned t)))
    (unwind-protect
        (progn
          (etaf-posframe-cycle)
          (should (eq (selected-frame) (etaf-posframe-panel-frame second)))
          (etaf-posframe-cycle)
          (should (eq (selected-frame) (etaf-posframe-panel-frame first)))
          (etaf-posframe-cycle)
          (should (eq (selected-frame) origin)))
      (ignore-errors (etaf-posframe-hide second))
      (ignore-errors (etaf-posframe-hide first))
      (ignore-errors (select-frame-set-input-focus origin)))))

(ert-deftest etaf-posframe-focus-shows-in-the-border ()
  "The focused panel paints its border differently from the resting ones.
The accent follows the selection, so selecting a panel or the frame behind them
switches it without running any panel command."
  (skip-unless (display-graphic-p))
  (let ((origin (etaf-posframe-tests--top-frame)))
    (unless (eq (selected-frame) origin)
      (select-frame origin))
    (let* ((first (etaf-posframe-show (etaf-view (text "first"))
                                      :key 'border-one :width 24 :height 2
                                      :pinned t :focusable t))
           (second (etaf-posframe-show (etaf-view (text "second"))
                                       :key 'border-two :width 24 :height 2
                                       :pinned t :focusable t))
           (colour (lambda (panel)
                     (face-attribute 'child-frame-border :background
                                     (etaf-posframe-panel-frame panel)))))
      (unwind-protect
          (progn
            ;; Cycling focuses one panel at a time and its border differs from
            ;; the panel that does not have the focus.
            (dotimes (_ 3)
              (etaf-posframe-cycle)
              (with-timeout (2 nil) (sleep-for 0.1))
              (let ((selected (selected-frame)))
                (when (eq selected (etaf-posframe-panel-frame first))
                  (should-not (equal (funcall colour first)
                                     (funcall colour second))))
                (when (eq selected (etaf-posframe-panel-frame second))
                  (should-not (equal (funcall colour first)
                                     (funcall colour second))))))
            ;; Selecting a frame like a click does, then running a command,
            ;; moves the accent on its own: on the frame behind them both
            ;; panels look the same, on a panel it differs again.
            (select-frame origin)
            (run-hooks 'post-command-hook)
            (should (equal (funcall colour first) (funcall colour second)))
            (let ((resting (funcall colour second)))
              (select-frame (etaf-posframe-panel-frame first))
              (run-hooks 'post-command-hook)
              (should-not (equal resting (funcall colour first)))
              (should (equal resting (funcall colour second)))))
        (ignore-errors (etaf-posframe-hide second))
        (ignore-errors (etaf-posframe-hide first))
        (ignore-errors (select-frame-set-input-focus origin))))))

(ert-deftest etaf-posframe-fill-keeps-the-row-budget ()
  "A panel with :fill keeps the row budget although its content is shorter."
  (skip-unless (display-graphic-p))
  (let* ((parent (etaf-posframe-tests--top-frame))
         (rows 12)
         (panel (etaf-posframe-show (etaf-view (text "short"))
                                    :width 24 :height rows :fill t)))
    (unwind-protect
        (let* ((frame (etaf-posframe-tests--panel-frame parent))
               (window (etaf-posframe-tests--panel-window frame)))
          (should (>= (window-body-height window) (1- rows)))
          (should (< (* rows (frame-char-height parent))
                     (frame-pixel-height frame))))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-height-fits-the-parent-frame ()
  "A row budget larger than the parent frame is clamped to what fits."
  (skip-unless (display-graphic-p))
  (let* ((parent (etaf-posframe-tests--top-frame))
         (panel (etaf-posframe-show (etaf-view (text "short"))
                                    :width 24 :height 500 :fill t)))
    (unwind-protect
        (let ((frame (etaf-posframe-tests--panel-frame parent)))
          (should (<= (frame-pixel-height frame) (frame-pixel-height parent)))
          (should (> (window-body-height (etaf-posframe-tests--panel-window frame))
                     10)))
      (etaf-posframe-hide panel))))

(ert-deftest etaf-posframe-offset-shifts-an-anchor ()
  "An offset moves a panel by character cells from the anchor it chose."
  (skip-unless (display-graphic-p))
  (let* ((parent (etaf-posframe-tests--top-frame))
         (char-width (frame-char-width parent))
         (char-height (frame-char-height parent))
         (plain (etaf-posframe-tests--placement parent 20 2 :at 'frame-center))
         (origin (plist-get plain :at))
         (shifted (etaf-posframe-tests--placement parent 20 2 :at 'frame-center
                                                  :offset '(2 . -3)))
         (at (plist-get shifted :at)))
    (should (equal at (cons (- (car origin) (* 3 char-width))
                            (+ (cdr origin) (* 2 char-height)))))))

(ert-deftest etaf-posframe-rejects-a-bad-offset ()
  "An offset that is neither a pair of integers nor a function is rejected."
  (let ((view (etaf-view (text "x"))))
    (dolist (offset '(1 "2" (1.5 . 2) (a . b)))
      (should (string-match-p
               "offset"
               (error-message-string
                (should-error (etaf-posframe-show view :offset offset)
                              :type 'etaf-posframe-error)))))))

(ert-deftest etaf-posframe-hover-focuses-a-panel ()
  "The pointer on a panel focuses it when asked, and never a passive panel."
  (skip-unless (display-graphic-p))
  ;; The behaviour is opt-in: a resting pointer must not move the keyboard away
  ;; from another window.
  (let* ((etaf-posframe-focus-follows-mouse t)
         (origin (etaf-posframe-tests--top-frame))
         (panel (etaf-posframe-show (etaf-view (text "hover"))
                                    :key 'hover :width 24 :height 2
                                    :pinned t :focusable t))
         (frame (etaf-posframe-panel-frame panel)))
    (unwind-protect
        (progn
          (select-frame origin)
          (etaf-posframe-tests--with-pointer-on
           frame (lambda () (run-hooks 'post-command-hook)))
          (should (eq (selected-frame) frame))
          ;; A passive panel never takes the focus from the pointer.
          (etaf-posframe-hide panel)
          (setq panel (etaf-posframe-show (etaf-view (text "passive"))
                                          :key 'hover :width 24 :height 2
                                          :pinned t :focusable nil)
                frame (etaf-posframe-panel-frame panel))
          (select-frame origin)
          (etaf-posframe-tests--with-pointer-on
           frame (lambda () (run-hooks 'post-command-hook)))
          (should (eq (selected-frame) origin)))
      (ignore-errors (etaf-posframe-hide panel))
      (ignore-errors (select-frame-set-input-focus origin)))))

(ert-deftest etaf-posframe-hides-panels-while-emacs-is-inactive ()
  "Panels become invisible while Emacs is inactive and come back after.
A child frame is a window of its own, and a window manager that lists windows
would offer the panel as a target instead of the application behind it."
  (skip-unless (display-graphic-p))
  (skip-unless etaf-posframe-hide-inactive)
  (let* ((origin (etaf-posframe-tests--top-frame))
         (panel (etaf-posframe-show (etaf-view (text "inactive"))
                                    :key 'inactive :width 24 :height 2
                                    :pinned t))
         (frame (etaf-posframe-panel-frame panel)))
    (unwind-protect
        (progn
          (should (frame-parameter frame 'visibility))
          (cl-letf (((symbol-function 'frame-focus-state) (lambda (&rest _) nil)))
            (run-hooks 'post-command-hook))
          (should-not (frame-parameter frame 'visibility))
          (cl-letf (((symbol-function 'frame-focus-state) (lambda (&rest _) t)))
            (run-hooks 'post-command-hook))
          (should (frame-parameter frame 'visibility)))
      (etaf-posframe-hide panel)
      (ignore-errors (select-frame-set-input-focus origin)))))

(ert-deftest etaf-posframe-hover-paints-a-border-without-focus ()
  "The pointer on a panel paints its border accent while the keyboard stays."
  (skip-unless (display-graphic-p))
  (let* ((origin (etaf-posframe-tests--top-frame))
         (panel (etaf-posframe-show (etaf-view (text "hover"))
                                    :key 'hover-border :width 24 :height 2
                                    :pinned t :focusable t))
         (frame (etaf-posframe-panel-frame panel)))
    (unwind-protect
        (progn
          (select-frame origin)
          (etaf-posframe-tests--with-pointer-on
           origin (lambda () (run-hooks 'post-command-hook)))
          (let ((resting (face-attribute 'child-frame-border :background frame)))
            ;; The hint follows the pointer, not the keyboard: the panel is not
            ;; selected, and the pointer on it still paints the accent.
            (etaf-posframe-tests--with-pointer-on
             frame (lambda () (run-hooks 'post-command-hook)))
            (should (eq (selected-frame) origin))
            (let ((accent (face-attribute 'child-frame-border :background frame)))
              (should-not (equal resting accent))
              ;; Leaving a panel runs no command in the buffer the pointer lands
              ;; in, so the package reads the pointer itself while panels are
              ;; open, and the border returns to rest without a command.
              ;; `sleep-for' drives the timers whatever input is pending.
              (etaf-posframe-tests--with-pointer-on
               origin (lambda () (sleep-for 0.6)))
              (should (equal resting
                             (face-attribute 'child-frame-border :background
                                             frame))))))
      (etaf-posframe-hide panel)
      (ignore-errors (select-frame-set-input-focus origin)))))

(ert-deftest etaf-posframe-click-selects-a-panel ()
  "A mouse button anywhere in a panel selects it, and never a passive panel."
  (skip-unless (display-graphic-p))
  (let* ((origin (etaf-posframe-tests--top-frame))
         (panel (etaf-posframe-show (etaf-view (text "click"))
                                    :key 'click-panel :width 24 :height 2
                                    :pinned t :focusable t))
         (frame (etaf-posframe-panel-frame panel))
         (window (frame-root-window frame))
         (passive (etaf-posframe-show (etaf-view (text "passive"))
                                      :key 'click-passive :width 24 :height 2
                                      :pinned t :focusable nil))
         (passive-window (frame-root-window
                          (etaf-posframe-panel-frame passive))))
    (unwind-protect
        (progn
          (select-frame origin)
          ;; The click command has already run; the hook raises the clicked
          ;; panel and gives it the keyboard like a click on any window.
          (let ((last-command-event
                 (list 'mouse-1 (list window 1 '(1 . 1) 0))))
            (run-hooks 'post-command-hook))
          (should (eq (selected-frame) frame))
          ;; A passive panel is raised but never takes the keyboard.
          (select-frame origin)
          (let ((last-command-event
                 (list 'mouse-1 (list passive-window 1 '(1 . 1) 0))))
            (run-hooks 'post-command-hook))
          (should (eq (selected-frame) origin)))
      (ignore-errors (etaf-posframe-hide panel))
      (ignore-errors (etaf-posframe-hide passive))
      (ignore-errors (select-frame-set-input-focus origin)))))

(ert-deftest etaf-posframe-theme-pins-a-mode ()
  "A pinned Theme keeps its mode whatever the Emacs theme is."
  (let* ((dark (etaf-posframe-theme nil 'dark))
         (light (etaf-posframe-theme nil 'light))
         (mode (frame-parameter nil 'background-mode)))
    (unwind-protect
        (progn
          (should (< (etaf-posframe-tests--luminance (plist-get dark :ui-bg))
                     (etaf-posframe-tests--luminance (plist-get light :ui-bg))))
          ;; The Emacs theme does not move a pinned panel.
          (set-frame-parameter nil 'background-mode 'light)
          (should (equal (plist-get dark :ui-bg)
                         (plist-get (etaf-posframe-theme nil 'dark) :ui-bg)))
          (set-frame-parameter nil 'background-mode 'dark)
          (should (equal (plist-get light :ui-bg)
                         (plist-get (etaf-posframe-theme nil 'light) :ui-bg))))
      (set-frame-parameter nil 'background-mode mode))))

(ert-deftest etaf-posframe-hover-is-dimmer-than-focus ()
  "A hovered panel takes half the accent, so only focus paints it fully."
  (skip-unless (display-graphic-p))
  (let* ((origin (etaf-posframe-tests--top-frame))
         (panel (etaf-posframe-show (etaf-view (text "tone"))
                                    :key 'hover-tone :width 24 :height 2
                                    :pinned t :focusable t))
         (frame (etaf-posframe-panel-frame panel)))
    (unwind-protect
        (progn
          (should (eq (selected-frame) frame))
          (let ((focus (face-attribute 'child-frame-border :background frame)))
            (select-frame origin)
            (etaf-posframe-tests--with-pointer-on
             origin (lambda () (run-hooks 'post-command-hook)))
            (let ((resting (face-attribute 'child-frame-border :background frame)))
              (should-not (equal resting focus))
              (etaf-posframe-tests--with-pointer-on
               frame (lambda () (run-hooks 'post-command-hook)))
              (let ((hover (face-attribute 'child-frame-border :background frame)))
                (should-not (equal hover focus))
                (should-not (equal hover resting))))))
      (etaf-posframe-hide panel)
      (ignore-errors (select-frame-set-input-focus origin)))))

(provide 'etaf-posframe-tests)
;;; etaf-posframe-tests.el ends here
