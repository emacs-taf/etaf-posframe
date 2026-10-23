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

(defvar etaf-pomodoro--restarting nil
  "Non-nil while the panel is remounted for a style change.")

(defun etaf-pomodoro--clock (seconds)
  "Format SECONDS as MM:SS."
  (format "%02d:%02d" (/ seconds 60) (% seconds 60)))

(defun etaf-pomodoro--colors ()
  "Return the live card colors derived from the current frame."
  (let ((theme (etaf-posframe-theme)))
    (list :ink (or (plist-get theme :ui-panel-fg) "#E9F0F4")
          :muted (or (plist-get theme :ui-muted-fg) "#93A3AA")
          :track (or (plist-get theme :ui-disabled-bg) "#39464C")
          :accent (or (plist-get theme :ui-accent) "#7FD1AE")
          :soft (or (plist-get theme :ui-accent-soft-bg) "#233A32")
          :border (or (plist-get theme :ui-panel-border) "#3A474E"))))

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
  "Switch to the next visual style and fit the panel again."
  (when-let* ((state etaf-pomodoro--state))
    (let* ((style (plist-get state :style))
           (next (car (or (cdr (memq (etaf-value style)
                                      etaf-pomodoro--styles))
                          etaf-pomodoro--styles))))
      (etaf-batch (setf (etaf-value style) next))
      (etaf-pomodoro--remount))))

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

(defun etaf-pomodoro--progress-line (fraction colors)
  "Return a thin FRACTION progress line with COLORS."
  (let* ((width 38)
         (filled (max 0 (min width (round (* width fraction)))))
         (filled-text (make-string filled 9473))
         (empty-text (make-string (- width filled) 9472)))
    (etaf-view
     (flex :column-gap '(ch 0) :align-items 'center
           (text :color (plist-get colors :accent) :font-weight 'bold
                 (expr filled-text))
           (text :color (plist-get colors :track)
                 (expr empty-text))))))

(defun etaf-pomodoro--buttons ()
  "Return the action row."
  (etaf-view
   (flex :column-gap '(ch 1) :align-items 'center
         (etaf-button :label "暂停" :variant 'primary
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

(defun etaf-pomodoro--minimal (left on fraction colors)
  "Return the minimal style view."
  (etaf-view
   (column :item-gap '(lh 0) :width 'stretch
           (text :font-size 32 :font-weight 'bold
                 :color (plist-get colors :ink)
                 (expr (etaf-pomodoro--clock left)))
           (text :font-size 11 :color (plist-get colors :muted)
                 (expr (etaf-pomodoro--status left on)))
           (expr (etaf-pomodoro--progress-line fraction colors))
           (expr (etaf-pomodoro--buttons)))))

(defun etaf-pomodoro--ring-view (left on fraction colors)
  "Return the ring style view."
  (etaf-view
   (column :item-gap '(lh 0) :width 'stretch
           (flex :column-gap '(ch 2) :align-items 'center
                 (image :src (etaf-pomodoro--ring fraction colors)
                        :columns 8 :rows 4)
                 (column :item-gap '(lh 0)
                         (text :font-size 26 :font-weight 'bold
                               :color (plist-get colors :ink)
                               (expr (etaf-pomodoro--clock left)))
                         (text :font-size 11 :color (plist-get colors :muted)
                               (expr (format "%d%% · %s"
                                             (round (* 100 fraction))
                                             (if on "专注中" "已暂停"))))))
           (expr (etaf-pomodoro--buttons)))))

(defun etaf-pomodoro--card (left fraction colors)
  "Return the card style view."
  (etaf-view
   (column :item-gap '(lh 0) :width 'stretch
           (flex :justify-content 'space-between :align-items 'center
                 :padding '((lh 0) (ch 1))
                 :background-color (plist-get colors :soft)
                 :border-radius '(px 6)
                 (text :font-size 11 :color (plist-get colors :accent)
                       "番茄 · 第 1 个")
                 (text :font-size 24 :font-weight 'bold
                       :color (plist-get colors :ink)
                       (expr (etaf-pomodoro--clock left))))
           (expr (etaf-pomodoro--progress-line fraction colors))
           (expr (etaf-pomodoro--buttons)))))

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
                      ('minimal (etaf-pomodoro--minimal left on fraction colors))
                      ('ring (etaf-pomodoro--ring-view
                              left on fraction colors))
                      (_ (etaf-pomodoro--card left fraction colors))))
              (etaf-divider)
              (flex :justify-content 'space-between :align-items 'center
                    (etaf-label :text (format "%d 分钟"
                                              (round total-seconds 60))
                                :variant 'muted)
                    (etaf-label :text "拖动标题栏 · q 关闭" :variant 'muted)))))))

(defun etaf-pomodoro--open (state)
  "Mount the panel for STATE and return it."
  (etaf-posframe-show
   (lambda ()
     (etaf-view
      (etaf-pomodoro--view
       :remaining (plist-get state :remaining)
       :total (plist-get state :total)
       :running (plist-get state :running)
       :style (plist-get state :style))))
   :at 'frame-top-right
   :width etaf-pomodoro--width
   :header "≡ 番茄钟"
   :draggable t
   :pinned t
   :focusable t
   :on-close #'etaf-pomodoro--close))

(defun etaf-pomodoro--remount ()
  "Remount the panel so a different style starts from a clean surface."
  (when (etaf-posframe-live-p etaf-pomodoro--panel)
    (let ((etaf-pomodoro--restarting t))
      (etaf-posframe-hide etaf-pomodoro--panel)))
  (when etaf-pomodoro--state
    (setq etaf-pomodoro--panel (etaf-pomodoro--open etaf-pomodoro--state))))

(defun etaf-pomodoro--close (&optional _panel)
  "Stop the tick timer and forget the panel."
  (unless etaf-pomodoro--restarting
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
  "Close the Pomodoro panel."
  (interactive)
  (if (etaf-posframe-live-p etaf-pomodoro--panel)
      (etaf-posframe-hide etaf-pomodoro--panel)
    (etaf-pomodoro--close)))

(provide 'etaf-pomodoro)
;;; etaf-pomodoro.el ends here
