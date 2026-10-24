# etaf-posframe

Show any ETAF View in a floating child frame.  A panel does not take a window,
does not replace the current buffer and does not disturb the user's layout, so
ETAF content can appear next to ordinary editing work: a preview, a status
board, a detail card or a small form.

Requires Emacs 29.1 or newer, ETAF 0.3 and [Posframe](https://github.com/tumashu/posframe).
Graphical frames only; a text terminal has no child frames.

```elisp
(require 'etaf-posframe)

(etaf-posframe-show
 (etaf-view
  (column :item-gap '(lh 0)
          (text :font-weight 'bold "Build finished")
          (text "3 tests failed in parser-tests")))
 :at 'window-top-right
 :width 36
 :auto-hide 6)
```

A panel is passive by default: it takes no keyboard focus and hides as soon as
the user works elsewhere.  `:focusable t` gives it the keyboard and
`:focus-on-open` decides whether it is selected on open; `:auto-hide nil` keeps
it until it is closed, `:draggable t` moves it by its title bar, and several
panels can be open at once.  The [manual](docs/manual.md) documents
the options, lifecycle, failures and the Theme contract.

The [symbol card](examples/etaf-symbol-card.el) example uses the catalog from
`etaf-ui` and answers "what is this symbol, how is it called here, where do I go
next" in one keypress.  A pinned, draggable timer with three styles lives in its
own package, [etaf-pomodoro](https://github.com/emacs-taf/etaf-pomodoro).

The [entry Commentary](etaf-posframe.el) is the supported API inventory.
Requires Emacs 29.1+, ETAF and Posframe on `load-path`; install from the ETAF
package archive once released, or add this checkout to `load-path`:

```elisp
(add-to-list 'load-path "/path/to/etaf-posframe")
```

## Checks

```sh
make check          # structure, compile, acceptance, API
make acceptance     # public behaviour scenarios
make compile        # byte-compile with warnings as errors
```

`make` needs Posframe discoverable.  It defaults to the newest
`~/.emacs.d/elpa/posframe-*`; set `POSFRAME_DIR=/path/to/posframe` for another
location.  GUI cases in the acceptance suite skip in batch Emacs and run in a
graphical verification instance.

## License

GPL-3.0-or-later; see [LICENSE](LICENSE).
