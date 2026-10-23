;;; etaf-posframe-tests.el --- Public panel behaviour -*- lexical-binding: t; -*-

;; Copyright (C) 2026 ETAF contributors
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Public behaviour of `etaf-posframe'.  Cases that need a child frame are
;; skipped in batch Emacs and run in a graphical verification instance.

;;; Code:

(require 'ert)
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

(ert-deftest etaf-posframe-refresh-keeps-a-live-panel ()
  "Refresh reports success for a live panel and never signals."
  (skip-unless (display-graphic-p))
  (let* ((view (etaf-view (text "panel")))
         (panel (etaf-posframe-show view :width 24 :height 3)))
    (unwind-protect
        (should (etaf-posframe-refresh panel))
      (etaf-posframe-hide panel))))

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

(provide 'etaf-posframe-tests)
;;; etaf-posframe-tests.el ends here
