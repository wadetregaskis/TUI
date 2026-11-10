# Running Your App in a Browser

Build your app for WebAssembly and run it in a terminal on a web page, with no server behind it.

## Overview

TUI builds for `wasm32-unknown-wasip1`, and the TUI repository has a page that runs such a program in a terminal made
with [xterm.js](https://xtermjs.org). It is how the [Example app runs in your browser](https://swift-tui.com/demo/).
Your own app runs on the same page: one script builds it, a second serves it, and the result can be published as
static files, on GitHub Pages for example.

The page passes the program the terminal's size, the keys pressed and the mouse, and draws what it writes. Nothing
runs on a server: the whole program, the Swift runtime and Foundation are downloaded and run by the browser.

## What You Need

Three things have to match, and the first two are not what you build the rest of your app with:

- **A swift.org toolchain, not Xcode's.** Xcode's compiler can't produce WebAssembly; it stops at
  `No available targets are compatible with triple wasm32-unknown-wasip1`.
- **Swift 6.3 or later.** 6.3.3 is the version TUI is built and measured with.
- **The WebAssembly SDK of exactly the same version.** A 6.2.4 SDK under a 6.3.3 toolchain can't load the standard
  library.

```bash
swiftly install 6.3.3
swift sdk install \
  https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum <the checksum swift.org publishes beside it>
```

[Binaryen](https://github.com/WebAssembly/binaryen)'s `wasm-opt` is optional. When it is installed, the build runs it
with `-Os`.

## Building and Serving

The page and its scripts are in TUI's repository, under `Tools/Web`. From a clone of it, name your package and your
executable:

```bash
Tools/Web/build.sh --package-path ~/MyApp --product MyApp
Tools/Web/serve.py
open http://127.0.0.1:8000/
```

Press *Run* on the page. `build.sh` with no options builds the Example. It writes everything the page needs into
`Tools/Web/site/`:

- `MyApp.wasm`, the program, built in release mode with the debug information stripped. `--debug` builds a debug
  build, and `--no-opt` skips `wasm-opt`.
- `resources/`, a copy of the resource bundles SwiftPM built, TUI's translations among them.
- `manifest.json`, which tells the page the module's name and where in the program's file system each resource goes.

`serve.py` is a small static server. It exists to send two headers, `Cross-Origin-Opener-Policy` and
`Cross-Origin-Embedder-Policy`, which `python3 -m http.server` can't. The page needs them: the program waits for a key
by blocking, which only a web worker may do, and the page hands it the keys through a `SharedArrayBuffer`, which a
browser allows only on a page those headers isolate.

Before *Run*, the page offers a few settings, each an environment variable it gives the program: how many colours the
terminal has (or `NO_COLOR`), `TUI_REDUCE_MOTION`, `TUI_PLAIN_TEXT` and `TUI_ARROW_FOCUS`. The choices are kept in
the address, so a link opens the page with the same ones. For the Example the page also offers its pages and its
languages, which `build.sh` reads from the Example's source. See <doc:EnvironmentVariables> for what each variable
does.

## What Works, and What Doesn't

The Example runs in full in a browser: every page, animation, the mouse, pictures drawn in characters, resizing,
`@AppStorage` for the length of a visit, all seven of its languages, and a clean exit on ⌃Q. Your app runs as it does
in a terminal, except for what a WebAssembly program in a browser can't do:

| | |
|---|---|
| Network | There are no sockets. `Image(url:)` reports that the platform has no URL loading; an image from a file works. |
| Clipboard | The program can't reach the browser's. A copy goes through the terminal's OSC 52, which the page's terminal doesn't write without an addon. |
| Opening URLs | There is no subprocess to open them with. A `Link` still works, because it also tells the terminal where it points (OSC 8), and the page opens that in a new tab. |
| Terminal graphics | xterm.js draws no pictures in pixels, so pictures are drawn in characters. |
| Some characters | Emoji newer than Unicode 15 and SF Symbols take a width the terminal doesn't agree with, and the rest of their row shifts. |

Two things about the platform reach your code:

- **`Int` is 32 bits.** An arithmetic overflow that can't happen on a 64-bit machine traps here. Seconds since 2001
  times a frame rate, for example, doesn't fit. Use `Int64` or `Double` where a value can grow that large.
- **The stack is set at link time.** WebAssembly's default stack is 64 KB, and views render by recursion: on it, a
  view tree only a few levels deep is cut short with a notice, as a tree too deep for any stack is. `build.sh` links
  with a 16 MB stack, which is what a native program's main thread has. If you build the module yourself, pass
  `-Xlinker -z -Xlinker stack-size=16777216`; when the build also links a macro for the host, whose linker takes no
  such option, put `-z` and `stack-size=16777216` in a toolset's `linker` options instead (`--toolset`), as TUI's own
  `Tools/Web/wasm-stack-toolset.json` does. A small stack matters more here than natively: there is no
  guard page below it, so recursion TUI doesn't guard, such as releasing a very long chain of views, writes over the
  program's memory instead of crashing.

## Publishing on GitHub Pages

Copy these files from `Tools/Web/site/` into the directory your site publishes:

- `index.html`, `worker.js`, `wasi.js` and `isolation-sw.js`, the page
- `MyApp.wasm`, `manifest.json` and `resources/`, from the same build

Keep the module and the manifest together. The resources' places in the manifest are the paths SwiftPM compiled into
that build, so a manifest from another build doesn't match.

GitHub Pages can't send the two headers the page needs. `isolation-sw.js` solves that: when a visitor presses *Run*,
the page installs it as a service worker, which adds the headers to every response from the page's directory, then
reloads once and arrives isolated. That happens once per browser. Where service workers are off, as in some private
windows, the page says that it can't run.

The page fetches nothing large until *Run* is pressed, so a visitor who only reads it doesn't download the program.
GitHub Pages compresses what it chooses to, so compress the module yourself: `gzip -9 -n` it to `MyApp.wasm.gz`, and
change `"wasm"` in `manifest.json` to name that file. The page inflates a `.gz` module as it downloads it. TUI's own
site does this in `Tools/Site/assemble.sh`, which also adds a version to every URL, so that a browser holding the
previous deploy doesn't pair a new page with an old module.

## Size

The program is large, because it carries everything it uses, statically linked: the Swift runtime, Foundation and its
Unicode data, and TUI. A 15-line app with two buttons is 86 MB of WebAssembly once stripped, and 27 MB gzipped. The
Example is 93 MB, and 29 MB gzipped. Most of it is Foundation and ICU. Both measured in November 2026 with Swift 6.3.3,
in release mode, without `wasm-opt`.

The browser compiles the module as it downloads it, so the wait after the download is short. A visitor downloads it
on every *Run* that their browser's cache doesn't answer.

## See Also

- <doc:ShippingAnApp>
- <doc:TerminalSupport>
- <doc:EnvironmentVariables>
