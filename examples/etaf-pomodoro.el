;;; etaf-pomodoro.el --- A focus timer in a floating panel -*- lexical-binding: t; -*-

;; Copyright (C) 2026 ETAF contributors
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; A pinned, draggable, focusable Pomodoro panel with three visual styles.
;; It demonstrates the interactive side of `etaf-posframe': a retained View
;; reads reactive refs, a one-second timer publishes the remaining time,
;; catalog Buttons pause, reset, extend and restyle the session, and the
;; colors follow the Emacs theme in both light and dark sessions.
;;
;;   (add-to-list 'load-path "/path/to/etaf-posframe/examples")
;;   (require 'etaf-pomodoro)
;;   (global-set-key (kbd "C-c t") #'etaf-pomodoro-start)
;;
;; Drag the panel by its header line.  `q', `ESC' or `C-g' close it; the
;; timer stops with the panel.  The 风格 button cycles minimal, ring, card.

;;; Code:

(require 'etaf)
(require 'etaf-ui)
(require 'etaf-posframe)

(defgroup etaf-pomodoro nil
  "Floating Pomodoro timer."
  :group 'etaf
  :prefix "etaf-pomodoro-")

(defconst etaf-pomodoro--width 42
  "Panel width in columns.")

(defconst etaf-pomodoro--default-minutes 25
  "Focus length in minutes when the caller does not pass one.")

(defconst etaf-pomodoro--styles '(minimal ring card)
  "Visual styles, in cycling order.")

(defvar etaf-pomodoro--state nil
  "Refs of the running timer, or nil.")

(defvar etaf-pomodoro--timer nil
  "One-second tick timer, or nil.")

(defvar etaf-pomodoro--panel nil
  "Open panel, or nil.")

(defvar etaf-pomodoro--keep nil
  "Non-nil while the panel is remounted for another style.")

(defun etaf-pomodoro--clock (seconds)
  "Format SECONDS as MM:SS."
  (format "%02d:%02d" (/ seconds 60) (% seconds 60)))

(defun etaf-pomodoro--colors ()
  "Return the card colors of the panel that is rendering."
  (let ((theme (or (etaf-posframe-current-theme)
                   (etaf-posframe-theme))))
    (list :ink (or (plist-get theme :ui-panel-fg) "#E9F0F4")
          :muted (or (plist-get theme :ui-muted-fg) "#93A3AA")
          :track (or (plist-get theme :ui-disabled-bg) "#39464C")
          :accent (or (plist-get theme :ui-accent) "#7FD1AE")
          :soft (or (plist-get theme :ui-accent-soft-bg) "#233A32"))))

(defun etaf-pomodoro--toggle ()
  "Start or pause the countdown."
  (when-let* ((state etaf-pomodoro--state))
    (let ((running (plist-get state :running)))
      (etaf-batch
        (setf (etaf-value running) (not (etaf-value running)))))))

(defun etaf-pomodoro--reset ()
  "Return the countdown to its full length."
  (when-let* ((state etaf-pomodoro--state))
    (etaf-batch
      (setf (etaf-value (plist-get state :remaining))
            (etaf-value (plist-get state :total)))
      (setf (etaf-value (plist-get state :running)) nil))))

(defun etaf-pomodoro--extend ()
  "Add five minutes to the session."
  (when-let* ((state etaf-pomodoro--state))
    (etaf-batch
      (setf (etaf-value (plist-get state :total))
            (+ (etaf-value (plist-get state :total)) 300))
      (setf (etaf-value (plist-get state :remaining))
            (+ (etaf-value (plist-get state :remaining)) 300)))))

(defun etaf-pomodoro--next-style ()
  "Rebuild the panel in the next visual style."
  (when-let* ((state etaf-pomodoro--state))
    (let* ((style (plist-get state :style))
           (next (car (or (cdr (memq (etaf-value style)
                                      etaf-pomodoro--styles))
                          etaf-pomodoro--styles))))
      (run-at-time 0.05 nil
                   (lambda () (etaf-pomodoro--remount next))))))

(defun etaf-pomodoro--tick ()
  "Advance the countdown by one second while running."
  (when-let* ((state etaf-pomodoro--state))
    (let ((running (plist-get state :running))
          (remaining (plist-get state :remaining)))
      (when (etaf-value running)
        (let ((left (1- (etaf-value remaining))))
          (if (> left 0)
              (etaf-batch (setf (etaf-value remaining) left))
            (etaf-batch
              (setf (etaf-value remaining) 0)
              (setf (etaf-value running) nil)
              (message "番茄完成，起来走走"))))))))

(defun etaf-pomodoro--ring (fraction colors)
  "Return an SVG ring filled FRACTION of the way round with COLORS."
  (let* ((size 56)
         (center 28)
         (radius 22)
         (circumference (* 2 float-pi radius))
         (filled (* circumference (max 0.0 (min 1.0 fraction)))))
    (etaf-ui-svg-image
     (concat
      (etaf-ui-svg-circle center center radius
                          :fill "none"
                          :stroke (plist-get colors :track)
                          :stroke-width 4)
      (etaf-ui-svg-circle center center radius
                          :fill "none"
                          :stroke (plist-get colors :accent)
                          :stroke-width 4
                          :stroke-linecap "round"
                          :stroke-dasharray
                          (format "%.2f %.2f" filled circumference)
                          :transform (format "rotate(-90 %d %d)"
                                             center center)))
     size size (list 0 0 size size))))

(defun etaf-pomodoro--progress-line (fraction)
  "Return a thin FRACTION progress line."
  (let* ((width 38)
         (filled (max 0 (min width (round (* width fraction)))))
         (filled-text (make-string filled 9473))
         (empty-text (make-string (- width filled) 9472)))
    (etaf-view
     (flex :column-gap '(ch 0) :align-items 'center
           (text :color (etaf-theme-token :ui-accent "#7FD1AE")
                 :font-weight 'bold
                 (expr filled-text))
           (text :color (etaf-theme-token :ui-disabled-bg "#39464C")
                 (expr empty-text))))))

(defun etaf-pomodoro--buttons (on)
  "Return the action row for the running state ON."
  (etaf-view
   (flex :column-gap '(ch 1) :align-items 'center
         (etaf-button :label (if on "暂停" "开始") :variant 'primary
                      :on-press #'etaf-pomodoro--toggle)
         (etaf-button :label "重置" :variant 'ghost
                      :on-press #'etaf-pomodoro--reset)
         (etaf-button :label "+5" :variant 'ghost
                      :on-press #'etaf-pomodoro--extend)
         (etaf-button :label "风格" :variant 'ghost
                      :on-press #'etaf-pomodoro--next-style))))

(defun etaf-pomodoro--status (left on)
  "Return the status line for LEFT seconds while ON."
  (format "%s · 剩余 %d 分钟" (if on "专注中" "已暂停") (ceiling left 60)))

(defun etaf-pomodoro--minimal (left on fraction)
  "Return the minimal style view."
  (etaf-view
   (column :item-gap '(lh 0) :width 'stretch
           (text :font-size 32 :font-weight 'bold
                 :color (etaf-theme-token :ui-panel-fg "#E9F0F4")
                 (expr (etaf-pomodoro--clock left)))
           (text :font-size 11
                 :color (etaf-theme-token :ui-muted-fg "#93A3AA")
                 (expr (etaf-pomodoro--status left on)))
           (expr (etaf-pomodoro--progress-line fraction))
           (expr (etaf-pomodoro--buttons on)))))

(defun etaf-pomodoro--ring-view (left on fraction colors)
  "Return the ring style view."
  (etaf-view
   (column :item-gap '(lh 0) :width 'stretch
           (flex :column-gap '(ch 2) :align-items 'center
                 (image :src (etaf-pomodoro--ring fraction colors)
                        :columns 8 :rows 4)
                 (column :item-gap '(lh 0)
                         (text :font-size 26 :font-weight 'bold
                               :color (etaf-theme-token :ui-panel-fg "#E9F0F4")
                               (expr (etaf-pomodoro--clock left)))
                         (text :font-size 11
                               :color (etaf-theme-token :ui-muted-fg "#93A3AA")
                               (expr (format "%d%% · %s"
                                             (round (* 100 fraction))
                                             (if on "专注中" "已暂停"))))))
           (expr (etaf-pomodoro--progress-line fraction))
           (expr (etaf-pomodoro--buttons on)))))

(defun etaf-pomodoro--card (left on fraction)
  "Return the card style view."
  (etaf-view
   (column :item-gap '(lh 0) :width 'stretch
           (flex :justify-content 'space-between :align-items 'center
                 :padding '((lh 0) (ch 1))
                 :background-color (etaf-theme-token :ui-accent-soft-bg
                                                     "#233A32")
                 :border-radius '(px 6)
                 (text :font-size 11
                       :color (etaf-theme-token :ui-accent "#7FD1AE")
                       "专注")
                 (text :font-size 24 :font-weight 'bold
                       :color (etaf-theme-token :ui-panel-fg "#E9F0F4")
                       (expr (etaf-pomodoro--clock left))))
           (expr (etaf-pomodoro--progress-line fraction))
           (expr (etaf-pomodoro--buttons on)))))

(etaf-define-component etaf-pomodoro--view
    (&key remaining total running style)
  "Render the timer from REMAINING, TOTAL, RUNNING and STYLE refs."
  :render
  (let* ((left (etaf-value remaining))
         (total-seconds (max 1 (etaf-value total)))
         (on (etaf-value running))
         (fraction (/ (float left) total-seconds))
         (mode (etaf-value style))
         (colors (etaf-pomodoro--colors)))
    (etaf-view
     (etaf-card
      (column :item-gap '(lh 0) :width 'stretch
              (expr (pcase mode
                      ('minimal (etaf-pomodoro--minimal left on fraction))
                      ('ring (etaf-pomodoro--ring-view
                              left on fraction colors))
                      (_ (etaf-pomodoro--card left on fraction))))
              (etaf-divider)
              (flex :justify-content 'space-between :align-items 'center
                    (etaf-label :text (format "%d 分钟"
                                              (round total-seconds 60))
                                :variant 'muted)
                    (etaf-label :text "拖动标题栏 · q 关闭" :variant 'muted)))))))

(defun etaf-pomodoro--open (state &optional position width)
  "Mount the panel for STATE at POSITION and WIDTH columns and return it."
  (etaf-posframe-show
   (lambda ()
     (etaf-view
      (etaf-pomodoro--view
       :remaining (plist-get state :remaining)
       :total (plist-get state :total)
       :running (plist-get state :running)
       :style (plist-get state :style))))
   :key 'pomodoro
   :at (or position 'frame-top-right)
   :width (or width etaf-pomodoro--width)
   :header "≡ 番茄钟"
   :draggable t
   :pinned t
   :focusable t
   :on-close #'etaf-pomodoro--close))

(defun etaf-pomodoro--remount (style)
  "Remount the panel in STYLE at its current position.
The retained renderer appends rows when a style subtree changes height, and a
panel's size is settled when it opens, so a style change starts a new panel.
The countdown carries over and the refs are recreated with the new Runtime.
The new panel keeps POSITION and the width the old frame had, so a panel the
user resized does not snap back to the example's columns."
  (let* ((state etaf-pomodoro--state)
         (panel etaf-pomodoro--panel)
         (frame (and (etaf-posframe-live-p panel)
                     (etaf-posframe--panel-frame panel)))
         (position (and frame (cons (frame-parameter frame 'left)
                                    (frame-parameter frame 'top))))
         (width (and frame (round (/ (frame-pixel-width frame)
                                     (float (frame-char-width frame))))))
         (remaining (etaf-value (plist-get state :remaining)))
         (total (etaf-value (plist-get state :total)))
         (running (etaf-value (plist-get state :running))))
    (when panel
      (let ((etaf-pomodoro--keep t))
        (etaf-posframe-hide panel)))
    (setq etaf-pomodoro--state
          (list :remaining (etaf-ref remaining)
                :total (etaf-ref total)
                :running (etaf-ref running)
                :style (etaf-ref style)))
    (setq etaf-pomodoro--panel
          (etaf-pomodoro--open etaf-pomodoro--state position width))))

(defun etaf-pomodoro--close (&optional _panel)
  "Stop the tick timer and forget the panel."
  (unless etaf-pomodoro--keep
    (when (timerp etaf-pomodoro--timer)
      (cancel-timer etaf-pomodoro--timer))
    (setq etaf-pomodoro--timer nil
          etaf-pomodoro--state nil
          etaf-pomodoro--panel nil)))
;;;###autoload
(defun etaf-pomodoro-start (&optional minutes)
  "Open the Pomodoro panel for MINUTES of focus, default 25.
The panel is pinned, draggable and focusable; `q', `ESC' or `C-g' close it."
  (interactive)
  (when (etaf-posframe-live-p etaf-pomodoro--panel)
    (etaf-posframe-hide etaf-pomodoro--panel))
  (let* ((seconds (* 60 (or minutes etaf-pomodoro--default-minutes)))
         (state (list :remaining (etaf-ref seconds)
                      :total (etaf-ref seconds)
                      :running (etaf-ref nil)
                      :style (etaf-ref 'minimal))))
    (setq etaf-pomodoro--state state)
    (setq etaf-pomodoro--panel (etaf-pomodoro--open state))
    (setq etaf-pomodoro--timer
          (run-at-time 1 1 #'etaf-pomodoro--tick))
    etaf-pomodoro--panel))

;;;###autoload
(defun etaf-pomodoro-stop ()
  "Close the Pomodoro panel and stop the timer."
  (interactive)
  (when (etaf-posframe-live-p etaf-pomodoro--panel)
    (etaf-posframe-hide etaf-pomodoro--panel))
  (etaf-pomodoro--close))

(provide 'etaf-pomodoro)
;;; etaf-pomodoro.el ends here
