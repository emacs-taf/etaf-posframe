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
   :auto-hide t))
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
                    :title "网易云音乐"
                    :focusable t)
```

Pass the session in from outside: a View built inside the render may not create
refs, so `etaf-ncm-view` must receive the session `etaf-ncm-create` returned.
`:height` is the row budget such an app lays out for, `:width` is its column
budget, and `:focusable t` is what gives it the keyboard; a passive panel never
sees the app's keys.  A click anywhere in a panel raises it above the other
panels; a passive one is raised without taking the keyboard.  The app scrolls
its own lists inside the budget, so a taller panel shows more rows instead of
growing the frame.

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
                        :width 110 :height 30 :title "Player"
                        :focusable t))))))
```

Sixteen presses in a row measured 0.68 s and 79 MB of allocation without that,
and 0.22 s with 28 MB and a single mount with it.

## Options

| Option | Values | Default | Meaning |
| --- | --- | --- | --- |
| `:at` | anchor; `(ANCHOR ROWS COLS)`; `(cells ROW COL)`; `(pixels X . Y)`; function | `point` | Where the panel goes.  An anchor names a frame or window place (`frame-top-right`, `window-center`, `point`); `(ANCHOR ROWS COLS)` shifts that anchor by character cells; `(cells ROW COL)` is an absolute character cell of the current window; `(pixels X . Y)` is frame pixels; a function is a Posframe poshandler. |
| `:stack` | `t` / `nil` | `nil` | With an anchored `:at`, place the panel clear of the panels already there: downward from a top or centre anchor, upward from a bottom one. |
| `:width` | integer cells; `(fraction F)` | `etaf-posframe-default-width` | Content columns, or `F` of the parent frame's width.  Clamped to the parent frame; a frame resized from outside becomes the width instead. |
| `:height` | integer rows; `(fraction F)` | `etaf-posframe-default-max-height` | Row budget: the content lines the View lays out for, or `F` of the parent frame's height.  Taller content clips; a frame resized from outside becomes the budget. |
| `:fill-height` | `t` / `nil` | `nil` | Keep the frame at the row budget instead of shrinking to the content, so an application with a fixed-size board fills the stage it asked for. |
| `:title` | string | none | Title-bar text.  Without it there is no header line and the panel cannot be dragged. |
| `:draggable` | `t` / `nil` | `nil` | Move the panel by dragging its title bar.  Needs `:title`. |
| `:focusable` | `t` / `nil` | `nil` (`t` for registered apps) | Let the panel take the keyboard, so its View's `:keys`, text inputs and buttons receive input.  A click anywhere in a panel raises it either way. |
| `:focus-on-open` | `t` / `nil` | same as `:focusable` | Select the panel when it opens.  Nil on a focusable panel leaves it unfocused until it is clicked; it means nothing on a non-focusable panel. |
| `:auto-hide` | `nil` / `t` / positive number | `nil` (focusable), `t` (passive) | `nil` keeps the panel until it is closed; `t` hides it as soon as the user works elsewhere (a preview disappears when the pointer or the keyboard moves on); a number hides it after that many seconds. |
| `:theme` | `auto` / `light` / `dark` / Theme plist or ref | `auto` | `auto` follows the Emacs theme; `light` or `dark` pin the panel to that palette; a Theme plist or a reactive ref uses that palette as it is. |
| `:border` | plist `(:width W :color C :focus F :hover H)` | 1 px, theme colours | Frame border: W pixels 0..19, the resting colour, the focused colour and the hovered colour.  The focused default is the Theme's accent; the hovered default is the accent at 45% over the surface, so hovering hints and clicking commits. |
| `:key` | symbol | none | Identity of the panel.  A show with a live key replaces that panel; different keys keep their own frame, Runtime and position. |

Unknown keys, a size that is neither a positive cell count nor a fraction, an
unsupported `:at` and an invalid `:border` signal `etaf-posframe-error` before
any frame is created.

## Registering an application

The framework owns the per-application boilerplate: register an application once
and open its panel with a single call.

```elisp
(etaf-posframe-register-app 'music
                            :title "网易云音乐"
                            :create #'etaf-ncm-create
                            :view #'etaf-ncm-view
                            :require 'etaf-ncm
                            :width 100 :height 24
                            :shortcut "m"
                            :at 'frame-top-right :stack t)

(global-set-key (kbd "C-c p") #'etaf-posframe-app-prefix)

(etaf-posframe-app 'music)   ;; or M-x etaf-posframe-app, or C-c p m
```

A registration records the title, the session factory, the View accessor, the
size, the placement, an optional shortcut and the application's behaviour.
`etaf-posframe-app` opens or closes that application's panel, replacing only its
own panel.  The behaviour options are the four a registration can answer:

| Option | Values | Default | Meaning |
| --- | --- | --- | --- |
| `:focusable` | `t` / `nil` | `t` | Give the panel the keyboard. |
| `:focus-on-open` | `t` / `nil` | `t` | Select it when it opens; nil on a focusable panel means the keyboard arrives only when it is clicked. |
| `:auto-hide` | `nil` / `t` / seconds | `nil` | Hide it when the user works elsewhere, or after that many seconds. |
| `:keep-alive` | `t` / `nil` | `nil` | `t` hides the panel on close and keeps the session, so music or a game continues and the next open resumes it; `nil` stops the application with the panel. |
| `:on-stop` | function (session) | none | Called when the application really stops, to release its backend. |

A fresh session is created on every open unless `:keep-alive` is set, in which
case the session survives the hidden panel and the next open reuses it.
`etaf-posframe-app-quit` hides the panel, calls `:on-stop` and drops the session,
so a background application can still be stopped for real.

`etaf-posframe-app-prefix` reads one key and dispatches it through the
registrations, so the caller binds a single prefix and never rebuilds a keymap.
Every application registered this way stacks with the others: opening the player
and then a reader tiles both beside each other.

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

`(cells ROW COL)` places the panel at an absolute character cell, counted from
zero at the top left of the current window's text area:

```elisp
(etaf-posframe-show view :at '(cells 0 0))   ;; first cell of the window
(etaf-posframe-show view :at '(cells 3 5))   ;; fourth row, sixth column
```

`(ANCHOR ROWS COLS)` starts from an anchor and moves by character cells: rows
positive go down and columns positive go right, so `(frame-center -3 0)` is the
middle of the frame three rows up and `(frame-top-right 2 -4)` sits two rows
below the corner and four columns to its left.  A cell or pixel position is
already exact and takes no offset; `(pixels X . Y)` is frame pixels and a
function is a Posframe poshandler.

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
reads as a surface above the buffer rather than a hole in it.  The panel that
holds the input focus paints its border in the Theme's accent instead, which is
how you see where the keyboard is while several panels are open; a hovered panel
takes the accent at 45% over its surface, so hovering hints and clicking
commits.  `:border` sets the width and the resting, focused and hovered colours
in one plist; the border is painted outside the text area, so the content width
stays exact.  Clicking a panel focuses it and the border follows the selection,
so the hint always matches where the keyboard goes.

A panel does not enable buffer-level `track-mouse`: Emacs then selects the frame
under the pointer whenever it moves, so leaving a panel would take the keyboard
with the pointer.  The hover border reads the pointer from a 0.2 s timer
instead, and a click remains the only thing that moves the keyboard.

`etaf-posframe-focus-follows-mouse` (default nil) additionally focuses the panel
under the pointer.  Emacs reports the child frame under the pointer through
`mouse-pixel-position`, so the reading is exact; it is off by default because a
resting pointer should not move the keyboard away from another window.  A click
always focuses a focusable panel, and the accent follows the selection, so
clicking a panel or the frame behind it moves it without running a panel
command.

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
itself on open unless `:focus-on-open' is nil, and hiding returns focus to the
frame that was selected before.  Passive panels never see the keyboard: the next command runs
in the buffer that owns point and the panel hides.

## Sizing

A panel renders at the width it is given, so its height follows the content.
`:height` caps that height; content above the cap is clipped by the Runtime's
viewport, and a budget taller than the parent frame is clamped to the rows that
fit on screen.  A panel that must be exactly its budget tall, such as a game
board on a fixed grid, passes `:fill-height t`: the frame keeps every row and
the surface paints the rest.  Both `:width` and `:height` also take
`(fraction F)`, a share of the parent frame's width or height, so a panel can
open at half the window without counting columns.  Width is clamped to the
parent frame, so a wide request still fits.
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
new faces.  `:theme 'light` or `:theme 'dark` pins a panel instead: it keeps
that palette whoever the Emacs theme is (the frame's accent still
follows), while the default `'auto` follows the frame.  Every palette carries
`:ui-mode` (`light` or `dark`), so a View that owns its own light and dark
palettes can read the panel's mode instead of the frame's `background-mode`.  The header line is a
full-width title bar: a surface lifted 7% toward the foreground separates it
from the panel body, and it keeps the panel's colors and fills every column
even when the frame's own `header-line` face is inverted.

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
- An application `:on-stop` error is reported in the echo area and does not
  block teardown.

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
