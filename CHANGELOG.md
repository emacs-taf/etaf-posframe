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
- Ship the symbol card example under `examples/`.
