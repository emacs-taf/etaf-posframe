# Floating panels with ETAF

## What a panel is for

A panel puts an ETAF View in a child frame attached to the current window.  It
is the right shape when the content is about what the user is doing now: a
preview of the symbol at point, a status board, a small form, a detail card.
It is not a replacement for an application buffer, which owns a window, a mode
and a lifecycle of its own.

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

## Options

| Option | Meaning |
| --- | --- |
| `:at` | `'point` (default), `'point-top`, window anchors, `'frame-top-right`, `'frame-bottom-right`, `'frame-center`, an absolute `(X . Y)` pixel pair, or a Posframe poshandler. |
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

Unknown keys, non-positive sizes, an unsupported `:dismiss` value and an
unsupported `:at` signal `etaf-posframe-error` before any frame is created.

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

## Theme

`etaf-posframe-theme` derives the catalog tokens from the frame's default face,
so `etaf-ui` Components match the user's light or dark theme without the caller
repeating colors.  `etaf-posframe-show` applies it by default as a reactive
Theme: loading another theme re-derives the palette and restyles every live
panel through `enable-theme-functions`, and the panel re-fits its height for the
new faces.  The header line is a full-width title bar painted with the same
surface and border colors as the panel.

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
