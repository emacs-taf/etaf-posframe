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

(provide 'etaf-posframe-tests)
;;; etaf-posframe-tests.el ends here
