# Tools/Web — the Example app, or yours, in a browser

```sh
Tools/Web/build.sh          # compile to wasm, collect resources, write the manifest
Tools/Web/serve.py          # serve it, cross-origin isolated
open http://127.0.0.1:8000/          # and press Run
```

Your own app instead of the Example, from its own package:

```sh
Tools/Web/build.sh --package-path ~/MyApp --product MyApp
```

The DocC article *Running Your App in a Browser*
(`Sources/TUI/TUI.docc/Articles/RunningInABrowser.md`) is the guide for an app's
author: what works, the commands, publishing on GitHub Pages, and the sizes.

The same page is published on the project's GitHub Pages site, under `demo/`
— see [`Tools/Site/README.md`](../Site/README.md).

The design, the toolchain requirements and the list of what does not work are in
[`Documentation/WebAssembly port.md`](<../../Documentation/WebAssembly port.md>). This file
is the map of the directory.

| File | What it is |
|---|---|
| `build.sh` | builds `Example.wasm` (or `NAME.wasm`, with `--product NAME`, from the package `--package-path` names, into the build directory `--scratch-path` names) with a swift.org 6.3+ toolchain and the WebAssembly SDK, runs `wasm-opt` when it is installed, copies the SwiftPM resource bundles into `site/resources/`, and writes `site/manifest.json` |
| `example_gallery.py` | run by `build.sh` for the Example alone: adds its pages (the cases of `DemoPage`, titled as its menu titles them) and its languages to the manifest, read from its source, for the page's start-page and language settings |
| `serve.py` | a static server that sets `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy`. The demo needs `SharedArrayBuffer`, which needs those headers, which `python3 -m http.server` cannot send |
| `site/index.html` | the page: the settings, an xterm.js terminal, the keystroke ring, and the worker. Fetches nothing large until *Run* is pressed |
| `site/worker.js` | instantiates the module and runs it; owns stdout batching. Inflates the module as it streams when it is a `.gz` (the published copy) |
| `site/isolation-sw.js` | a service worker that adds the cross-origin isolation headers to every response from the page's directory, for hosts that cannot send them (GitHub Pages). The page installs it on *Run* only when it is not isolated already, then reloads once |
| `site/wasi.js` | the WASI preview1 implementation — about 35 calls, the ones a Swift executable imports |
| `glyph-probe.html` | measures the browser terminal against the shared width corpus and the records of real terminals, and asks it the capability questions the framework asks at startup. Open it after `build.sh` and press *save* to write a record into `Tools/TerminalProbes/data/` |
| `site/manifest.json` | generated; names the module, maps each resource file to the guest path the binary looks for it at, and for the Example lists its pages and languages (`gallery`) |
| `site/probe-data/` | generated; copies of `Tools/TerminalProbes/data/` so the probe can read them |
| `site/Example.wasm` | generated; `NAME.wasm` for another product |

`site/*.wasm`, `site/resources/` and `site/manifest.json` are build
products and are not committed — run `build.sh` to make them.

## The settings

Before *Run*, the page offers settings, each an environment variable it starts
the program with. They are kept in the address's `#`, so a link opens the page
with the same ones (`#page=buttons&lang=de&colors=256`); *change settings*,
under a running program, reloads the page to them.

| Setting | `#` key | What it sets |
|---|---|---|
| Start page | `page` | the variable the manifest's `gallery.variable` names, `TUI_EXAMPLE_PAGE` for the Example. Offered only when the manifest lists pages |
| Language | `lang` | `LANG`, as `de_DE.UTF-8`. Offered only when the manifest lists languages; by default the first of the browser's languages the app has, else English |
| Colours | `colors` | `256` takes `COLORTERM` away, `16` also sets `TERM=xterm-16color`, `none` sets `NO_COLOR` |
| Motion | `motion` | `TUI_REDUCE_MOTION`; by default `1` when the browser prefers reduced motion |
| Characters | `text` | `TUI_PLAIN_TEXT`: `ascii` is `1`, `transliterate` is itself |
| Arrow keys | `arrows` | `TUI_ARROW_FOCUS=geometric` |

The worker sets the defaults under them (`TERM`, `COLORTERM`, `TERM_PROGRAM`,
`COLUMNS`, `LINES`, `LANG`, `TUI_CONFIG_DIR`); a setting of `null` takes one
away.

## Poking at it

The page exposes a small handle for when something does not arrive:

```js
__tuikit.pending()      // keystroke bytes the guest has not taken yet
__tuikit.indices()      // [wake sequence, write index, read index, spare]
__tuikit.send("q")      // put bytes in without going through the keyboard
__tuikit.writes()       // batches of output so far: a rate says whether frames are flowing
__tuikit.screen()       // the screen as text, whichever renderer is drawing it
```

## Emoji

The demo loads `@xterm/addon-unicode-graphemes` deliberately. Without it
xterm.js uses Unicode 6 widths, an emoji occupies one cell, and everything after
it on the row shifts left — see `Documentation/WebAssembly port.md` and the
`xterm.js` section of `Documentation/Terminals/Terminal compatibility survey.md` for the
measurements.

If the terminal stays blank, check the status line under it: `fetching…` and
`compiling…` come from the worker, and anything after `running` means the guest
started. If the page says it is not isolated, it was not served by `serve.py`
and the browser would not install `isolation-sw.js` either (a private window,
or service workers turned off).
