# Changelog

## Unreleased

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
- The panel surface lifts less from the frame background (4% instead of 10% in
  a dark theme), so the border defines it instead of a muddy tint;
  `etaf-posframe-surface-lift` tunes it.
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
