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
         (panel (etaf-posframe-show view :width 24 :height 3 :timeout 0.2)))
    (should (etaf-posframe-live-p panel))
    (sleep-for 0.5)
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

(defun etaf-posframe-tests--panel-window (frame)
  "Return the window FRAME shows its panel in."
  (frame-root-window frame))

(defun etaf-posframe-tests--panel-buffer (frame)
  "Return the buffer FRAME displays."
  (window-buffer (etaf-posframe-tests--panel-window frame)))

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
        (let ((frame (etaf-posframe-tests--panel-frame parent)))
          (should (= (* columns char) (frame-pixel-width frame)))
          (should (= (frame-pixel-width frame) (frame-text-width frame)))
          (should (= columns (window-body-width
                              (etaf-posframe-tests--panel-window frame)))))
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

(ert-deftest etaf-posframe-refresh-restores-a-stretched-frame ()
  "A frame stretched from outside returns to its panel size on refresh."
  (skip-unless (display-graphic-p))
  (let* ((parent (selected-frame))
         (char (frame-char-width parent))
         (columns (max 20 (- (/ (frame-pixel-width parent) char) 8)))
         (panel (etaf-posframe-show (etaf-view (text "panel")) :width columns)))
    (unwind-protect
        (let ((frame (etaf-posframe-tests--panel-frame parent)))
          (set-frame-size frame (+ (* columns char) (* 25 char)) 400 t)
          (should (> (frame-pixel-width frame) (* columns char)))
          (etaf-posframe-refresh panel)
          (sleep-for 0.3)
          (should (= (* columns char) (frame-pixel-width frame)))
          (should (< (frame-pixel-height frame) 400)))
      (etaf-posframe-hide panel))))

(provide 'etaf-posframe-tests)
;;; etaf-posframe-tests.el ends here
