# Changelog

## Unreleased

## 0.1.0

- First release: `etaf-posframe-show`, `etaf-posframe-hide`,
  `etaf-posframe-toggle`, `etaf-posframe-panels`, `etaf-posframe-live-p` and
  `etaf-posframe-theme`.
- Panels mount an ETAF View in a child frame, size the frame from the rendered
  content, hide before the next outside command, and support focus, pinning,
  header-line dragging, a timeout and an `on-close` callback.
- `:auto-focus` selects a focusable panel on open and hiding restores the
  previous frame; `q`, `ESC` and `C-g` close it from inside the panel.
- `etaf-posframe-refresh` re-measures the content and fits the frame.
- One panel per buffer: showing another replaces the first, and killing the
  parent buffer hides its panel.
- Panels follow the Emacs theme: loading a theme re-derives the palette and
  restyles live panels, including the title bar.
- Frame height follows the rendered pixels, so rows taller than the canonical
  line are not clipped; trailing blank rows are trimmed.
- Add `frame-top-right` and `frame-bottom-right` anchors and a pointer-free
  panel surface (no cursor).
- Ship the symbol card and the three-style Pomodoro examples under `examples/`.
