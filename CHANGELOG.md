# Changelog

## Unreleased

### Changed

- The panel vocabulary now has one option per concept.  Renames and merges:
  `:header` becomes `:title`; `:focusable` and `:auto-focus` become
  `:focusable` and `:focus-on-open`; `:dismiss` and `:timeout` become
  `:auto-hide` (`nil`, `t` or seconds); `:theme` takes `auto`, `light`, `dark`
  or a palette; `:at` takes `(ANCHOR ROWS COLS)`, `(cells ROW COL)` or
  `(pixels X . Y)`, so `:cell` and `:offset` are gone; the four border options
  become one `:border` plist; `:fill` becomes `:fill-height`; `:pinned` is
  `:auto-hide nil`; the registration `:key` is `:shortcut`.
- `:width` and `:height` accept `(fraction F)`, a share of the parent frame.
- `:keep-alive` keeps an application running while its panel is hidden and
  `:on-stop` releases it; `etaf-posframe-app-quit` stops it explicitly.

- Panels hide while Emacs is inactive, so a window manager that lists child
  frames (macOS Mission Control) cannot offer them in place of the application
  behind them; `etaf-posframe-hide-inactive` turns it off.
- The panel border follows the mouse pointer: the panel under the pointer
  paints its hover accent without taking the keyboard, so hovering it and then
  clicking it changes nothing.  The position comes from the window system,
  which reports a child frame; a 0.2 s reading while panels exist clears the
  hint when the pointer leaves, because a pointer leaving a buffer runs no
  command.
- A click anywhere in a panel raises it above the other panels.  Emacs selects
the clicked child frame but leaves the stacking order alone, so a panel behind
another stayed covered even while it held the keyboard; only an explicit raise
puts it in front.
- The hover border is the resting border mixed half-way to the accent, and a
focused panel paints the full accent, so hovering hints and clicking commits
instead of looking focused before the click.
- `:theme-mode` pins a panel (or a registered application) to `light` or `dark`:
the panel keeps that palette when the Emacs theme changes.  The default `auto`
follows the Emacs theme as before.  The palette carries `:ui-mode`, so a View
with its own light and dark palettes can follow the panel's mode.
- The title bar sits on its own surface, lifted toward the foreground, so it
reads as chrome instead of merging into the panel body.
- `etaf-posframe-focus-follows-mouse` focuses the panel under the pointer.  It
  defaults to nil, so a resting pointer does not move the keyboard away from
  another window.

- `:offset` shifts a panel by `(ROWS . COLUMNS)` character cells from whatever
  `:at`, `:cell` or `:stack` chose, so a caller writes "centred, one row up"
  instead of counting a position; a function may compute the pair.
- The focus border follows the real selection, so clicking a panel or the frame
  behind it moves the accent, not only the cycling command.

- The title bar keeps the panel's own surface colors and fills every column in
  a theme whose `header-line` face is inverted, instead of showing an inverted,
  partly filled bar.
- A panel whose frame is resized from outside becomes that wide: the View is
  laid out again, the content reflows, the title bar repaints to the new column
  count and the height follows the new content.  The width is remembered across
  `etaf-posframe-refresh' instead of snapping back to the opening columns.
- Closing a focused panel hands the window system's input focus back to the
  frame it was opened from.  `select-frame' alone left macOS without a key
  window, so the next command froze until the user clicked the parent frame.
- `:fill t` keeps a panel at its row budget instead of shrinking to its content,
  for applications whose board has a fixed size; the surface paints the rest of
  the stage.
- A row budget taller than the parent frame is clamped so the panel stays on
  screen.
- The panel holding the input focus paints its border in the Theme accent, so
  the active application is visible among several open panels;
  `:focus-border-color` overrides it and nil turns it off.
- `etaf-posframe-cycle' walks the input focus through the open panels and back
  to the frame behind them, so one key switches between the applications and the
  buffer they float over.
- Applications register once with `etaf-posframe-register-app' and open with one
  `etaf-posframe-app' call; `etaf-posframe-app-prefix' dispatches the registered
  shortcuts, so a caller writes one line per application instead of its own
  command, session bookkeeping and repeat guard.
- A dark panel paints the flat near-black surface family that dark
  applications use (the NetEase player's `#191a1c`), so a panel and such an
  application read as one design; the frame paint matches the canvas, so no
  second colour shows at the edges.  `etaf-posframe-dark-shade',
  `etaf-posframe-dark-surface' and `etaf-posframe-surface-lift' tune it.
- Panels draw a one pixel border in the Theme's panel border colour, so they
  read as surfaces above the buffer.  `:border-width` and `:border-color` change
  it; the border is painted outside the text area, so the content keeps its
  width.
- `:stack t` with an anchor `:at` places a new panel clear of the panels already
  at that anchor, one gap below (or above, for a `bottom-*` anchor).
- A resize re-fits at the next timer tick instead of after 50 ms, so dragging a
  panel edge no longer shows a stretched old layout for long.
- A returned panel prints as one readable line.  Its Runtime and Theme ref
  used to live in the struct, so printing the value of an
  `etaf-posframe-show` call (`C-x C-e`, a log line) followed a cycle.
- A panel that would fit itself more than 20 times in a second backs off for
  two seconds and reports it, so a condition that keeps resizing it cannot
  spin the CPU.
- `:height` is the row budget the View lays out for, and it caps the frame: a
  View that fills its viewport, such as a whole application, no longer
  stretches the frame to the measuring height (a 110x30 panel stayed 770x6416).
- A frame resized from outside also adopts a new height as the row budget, so a
  taller panel of a viewport-filling View shows more rows.  A card with
  intrinsic height stays as tall as its content.
- A style switch in the Pomodoro example keeps the width the user gave the
  panel, so a resized panel does not snap back to the example's columns.
- Document hosting a complete app in a panel; `etaf-ncm` opens this way with
  `etaf-posframe-show` over `etaf-ncm-view`.
- Cover the panel surface with tests that pin the frame to the canvas: exact
  content width, no empty rows below a short panel, an outside resize adopting
  its width and its rows, and the title bar painting every column.

## 0.1.0

- First release: `etaf-posframe-show`, `etaf-posframe-hide`,
  `etaf-posframe-toggle`, `etaf-posframe-panels`, `etaf-posframe-live-p` and
  `etaf-posframe-theme`.
- Panels mount an ETAF View in a child frame, size the frame from the rendered
  content, hide before the next outside command, and support focus, pinning,
  header-line dragging, a timeout and an `on-close` callback.
- `:auto-focus` selects a focusable panel on open and hiding restores the
  previous frame; `q`, `ESC` and `C-g` close it from inside the panel.
- One panel per buffer: showing another replaces the first, and killing the
  parent buffer hides its panel.
- Panels follow the Emacs theme: loading a theme re-derives the palette and
  restyles live panels, including the title bar.
- Frame height follows the rendered pixels, so rows taller than the canonical
  line are not clipped; trailing blank rows are trimmed.
- Add `frame-top-right` and `frame-bottom-right` anchors and a pointer-free
  panel surface (no cursor).
- Ship the symbol card and the three-style Pomodoro examples under `examples/`.
