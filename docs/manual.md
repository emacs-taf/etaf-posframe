# Floating panels with ETAF

## What a panel is for

A panel puts an ETAF View in a child frame attached to the current window.  It
is the right shape when the content is about what the user is doing now: a
preview of the symbol at point, a status board, a small form, a detail card.
It is not a replacement for an application buffer that needs a mode line,
window management and a lifecycle of its own.

The View is mounted for the panel with its own Runtime.  Panels do not share
state with an application buffer, and an application does not need to know a
panel exists.

## Calling the API

`etaf-posframe-show` accepts a View or a zero-argument function returning one.
The function runs once, when the panel opens, before mounting; a command can use
it to collect the data it shows and to refuse when there is nothing to show:

```elisp
(defun my-panel-show ()
  (interactive)
  (etaf-posframe-toggle
   (lambda ()
     (let ((symbol (symbol-at-point)))
       (unless symbol (user-error "No symbol at point"))
       (my-panel-view symbol)))
   :width 56
   :at 'point
   :dismiss 'auto))
```

`etaf-posframe-toggle` hides the current buffer's open panel instead of stacking
a second one, and a second `etaf-posframe-show` for the same buffer replaces the
earlier panel.  `etaf-posframe-hide` closes a panel and releases its Runtime,
timer and frame; `etaf-posframe-panels` returns the live panels;
and `etaf-posframe-live-p` reports whether one panel is still alive.
`etaf-posframe-refresh` re-fits the frame to the content after a View changed
its style or height; the fit is deferred past the current event and render, so
a Button or timer may call it safely.  A panel keeps the size it opened with
otherwise: resizing its frame by hand is not a supported gesture.

### Hosting a complete app

A panel takes any View, including one that wraps a whole application.  The app
keeps its session, keys and internal scrolling; the panel only supplies the
frame, the palette and the row budget.  Opening the player is one call:

```elisp
(etaf-posframe-show (etaf-ncm-view (etaf-ncm-create))
                    :width 110 :height 30
                    :header "网易云音乐"
                    :pinned t :focusable t)
```

Pass the session in from outside: a View built inside the render may not create
refs, so `etaf-ncm-view` must receive the session `etaf-ncm-create` returned.
`:height` is the row budget such an app lays out for, `:width` is its column
budget, and `:focusable t` is what gives it the keyboard; a passive panel never
sees the app's keys.  The app scrolls its own lists inside the budget, so a
taller panel shows more rows instead of growing the frame.

Keep one session and ignore a repeat within a fraction of a second when a
command owns the panel.  Mounting an application is expensive, so a session per
`show` plus key repeat mounts it once per repeat and stalls Emacs:

```elisp
(defvar my-panel nil)
(defvar my-session nil)
(defvar my-toggled-at 0)

(defun my-panel-toggle (&optional close)
  "Open or close the application panel."
  (interactive "P")
  (let ((live (etaf-posframe-live-p my-panel))
        (now (float-time)))
    (if (or close live)
        (when live
          (setq my-toggled-at now)
          (etaf-posframe-hide my-panel))
      (unless (< (- now my-toggled-at) 0.3)
        (setq my-toggled-at now
              my-session (or my-session (etaf-ncm-create))
              my-panel (etaf-posframe-show
                        (etaf-ncm-view my-session)
                        :width 110 :height 30 :header "Player"
                        :pinned t :focusable t))))))
```

Sixteen presses in a row measured 0.68 s and 79 MB of allocation without that,
and 0.22 s with 28 MB and a single mount with it.

## Options

| Option | Meaning |
| --- | --- |
| `:at` | Placement.  `frame-PLACE` inside the parent frame, `window-PLACE` inside the current window's text area, `point` (default), `point-top`, a `(X . Y)` pixel pair, or a Posframe poshandler. |
| `:cell` | Absolute `(ROW . COLUMN)` in character cells from the top left of the window's text area, counted from zero.  Wins over `:at`. |
| `:width` | Content columns.  Defaults to `etaf-posframe-default-width`, clamped to the parent frame. |
| `:height` | Maximum content lines.  Taller content clips; the frame still shrinks to the content. |
| `:header` | Header line text.  Without it the panel has no header line and cannot be dragged. |
| `:draggable` | Move the panel by dragging the header.  Defaults to `:pinned`. |
| `:pinned` | Keep the panel open regardless of `:dismiss`. |
| `:focusable` | Give the child frame keyboard focus, so the View's `:keys`, text inputs and buttons work. |
| `:auto-focus` | Select the panel on open so its keys work without a click.  Defaults to `:focusable`; nil leaves it unfocused until clicked. |
| `:dismiss` | `'auto` (default) hides before the next command outside the panel, `'focus-out` hides when focus leaves, nil keeps it. |
| `:timeout` | Seconds after which the panel hides by itself. |
| `:theme` | ETAF UI Theme plist; defaults to `etaf-posframe-theme` for the current frame. |
| `:on-close` | Function called with the panel after it is hidden. |
| `:key` | Identity of the panel.  A show with a live key replaces that panel; different keys, or no key, coexist. |
| `:border-width` | Border around the frame in pixels, default `etaf-posframe-border-width` (1).  `0` draws none. |
| `:border-color` | Border colour; defaults to the Theme's panel border. |
| `:stack` | With an anchor `:at`, place the panel clear of the panels already there, one gap below (or above, for a `bottom-*` anchor). |

Unknown keys, non-positive sizes, an unsupported `:dismiss` value and an
unsupported `:at` signal `etaf-posframe-error` before any frame is created.

## Several panels at once

Panels are independent: each keeps its own child frame, Runtime, Theme, keys and
position, and several stay open together.  `:key` identifies a panel, so
showing the same key again replaces that panel and leaves the others alone.

```elisp
(etaf-posframe-show (etaf-ncm-view session) :key 'music :width 110 :height 30)
(etaf-pomodoro-start)                  ;; :key 'pomodoro, its own frame
(etaf-symbol-card-show)                ;; :key 'symbol-card, at point
```

A view without a `:key` shares the nil identity, so repeated shows without a key
replace each other, which is what a preview panel wants.  Give an application
panel a key: otherwise opening another keyless panel replaces it.
`etaf-posframe-panels` lists everything alive, `etaf-posframe-hide` closes one
of them, and `etaf-posframe-toggle` with a key only touches that key's panel.

## Placement

`:at` names a rectangle and a place inside it.  The rectangle is the parent
frame (`frame-`) or the current window's text area (`window-`); the place is one
of nine:

```text
top-left       top-center       top-right
center-left    center           center-right
bottom-left    bottom-center    bottom-right
```

so `frame-center` is the middle of the frame, `window-top-right` the top right
of the window's text area, `window-center-left` the middle of its left edge.
The panel keeps a margin to the edge it is anchored to (8 px inside the frame, 4
px inside the window), so it never sits on the parent's scroll bar or border.
`point` (the default) and `point-top` follow point, a `(X . Y)` cons is frame
pixels, and a function is a Posframe poshandler.

`:cell` places the panel at an absolute character cell:

```elisp
(etaf-posframe-show view :cell '(0 . 0))   ;; first cell of the window
(etaf-posframe-show view :cell '(3 . 5))   ;; fourth row, sixth column
```

Rows and columns count from zero at the top left of the window's text area and
follow the parent frame's character metrics, so the same `:cell` lands on the
same cell whatever the panel's own size is.  `:cell` wins over `:at`.

`:stack` turns an anchor into a run of panels: the next panel opened at the same
anchor is placed clear of the ones already there, `etaf-posframe--stack-gap`
pixels below (or above, when the anchor starts at the bottom edge).  It needs a
symbol anchor, not a fixed position:

```elisp
(etaf-posframe-show music :key 'music :at 'frame-top-right :stack t)
(etaf-posframe-show lyrics :key 'lyrics :at 'frame-top-right :stack t)
```

```text
+---------------------+
|        panel 1      |  <- frame-top-right, :stack t
+---------------------+
|        panel 2      |
+---------------------+
```

## Look

Every panel draws a one pixel border in the Theme's panel border colour, so it
reads as a surface above the buffer rather than a hole in it.  `:border-width`
changes or removes it and `:border-color` overrides the colour; both keep the
content width exact, because the border is painted outside the text area.

## Lifecycle and ownership

Showing a panel creates a hidden buffer, mounts the View with a fixed viewport,
measures the rendered rows, shows the frame, and fits the panel to the settled
window width.  Hiding deletes the frame, unmounts the Runtime and kills the
buffer.  A failed show cleans up before re-signaling, so a stale panel is never
returned.

A panel belongs to the buffer that was current when it was shown.  That buffer
owns a `kill-buffer-hook`, so killing it hides the panel and releases its
Runtime.  Only one panel is kept per buffer: showing another replaces the
first.

`etaf-posframe-panel-keys` is active while a focusable panel has focus and
closes it on `q`, `ESC` and `C-g`; it outranks the renderer's own map for those
three keys.  The View's own `:keys` handle the rest.  A focusable panel selects
itself on open (`:auto-focus`), and hiding returns focus to the frame that was
selected before.  Passive panels never see the keyboard: the next command runs
in the buffer that owns point and the panel hides.

## Sizing

A panel renders at the width it is given, so its height follows the content.
`:height` caps that height; content above the cap is clipped by the Runtime's
viewport.  Width is clamped to the parent frame, so a wide request still fits.
The frame is sized in pixels from the rendered content, so a row taller than the
canonical line (a large clock, an icon) is never cut, and a trailing blank row
left by the renderer is trimmed before measuring.  The panel re-fits when the
parent frame changes size and after a theme switch.

A panel whose own frame is resized from outside adopts that size: the View is
laid out again at the new width and rows, the content reflows, the title bar
repaints to the new column count and the height follows the new content.  Both
dimensions are remembered, so a later re-fit and `etaf-posframe-refresh' keep
them instead of snapping the frame back to the columns and rows the panel
opened with.

A panel that has to fit itself more than 20 times within a second backs off for
two seconds and reports the count on the echo area, so a condition that keeps
resizing a panel cannot run away with the CPU.

A wider or taller resize always becomes the new budget.  A shorter one only
does when it cuts into the content, because the panel's own fit sets the frame
to the content height: a View with intrinsic height, such as a card, stays as
tall as its content however far its frame is stretched, while a View that fills
its viewport, such as a complete app, follows the new height and shows more or
fewer rows.

## Theme

`etaf-posframe-theme` derives the catalog tokens from the frame's default face,
so `etaf-ui` Components match the user's light or dark theme without the caller
repeating colors.  `etaf-posframe-show` applies it by default as a reactive
Theme: loading another theme re-derives the palette and restyles every live
panel through `enable-theme-functions`, and the panel re-fits its height for the
new faces.  The header line is a full-width title bar painted with the same
surface and border colors as the panel; it keeps those colors and fills every
column even when the frame's own `header-line` face is inverted.

A panel that builds its own themed boundary must pass the View as a component
property and render it inside the component, not through the default slot:

```elisp
(etaf-define-component my-surface (&key theme content)
  :setup (etaf-theme-provide theme)
  :render (etaf-view (expr content)))

(etaf-view (my-surface :theme theme :content view))
```

A View passed through a default slot is owned by the caller, so its deferred
tokens resolve in the caller's context and the Theme provided by the wrapper
does not reach it.  A property value is rendered by the component, which is the
context that provides the Theme.

## Failures

- Non-graphical frame: `etaf-posframe-error`, because a child frame needs a
  window system.
- Unknown option or invalid value: `etaf-posframe-error` naming the option.
- The View function returns nil: `etaf-posframe-error`.
- The View does not mount: the buffer and frame are deleted and the error is
  re-signaled.
- `:on-close` errors are reported in the echo area and do not block teardown.

## Example

`examples/etaf-symbol-card.el` shows the symbol card and can be loaded on its
own:

```elisp
(add-to-list 'load-path "/path/to/etaf-posframe/examples")
(require 'etaf-symbol-card)
(global-set-key (kbd "C-c h") #'etaf-symbol-card-show)
```

The card answers one question: what is this symbol, how is it called in this
file, and where do I go next.  It shows the documentation's first paragraph,
up to three call sites with line numbers, the definition location, and the
`M-.` / `M-?` destinations.

## Validation

`make check` runs the structure gate, a warnings-as-errors byte compilation, the
public acceptance scenarios and the entry API check.  The acceptance suite
covers option validation, Theme derivation and, in a graphical frame, the
show/hide and toggle lifecycle.  GUI appearance and interaction latency are
verified in a real graphical session; batch tests do not certify them.
