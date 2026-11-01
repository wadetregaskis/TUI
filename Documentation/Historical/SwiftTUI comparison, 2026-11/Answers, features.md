# TUI and SwiftTUI: feature questions answered

Date: 2026-10-31. Written for TUI's owner. Nothing here is in the repo.

**What is compared**
- **SwiftTUI** is `github.com/SwiftTUI/swift-tui`, at `207913d`, just after release 0.20.0. Site: swifttui.sh. "ST:" below means that repo's root.
- **TUI** is your local `main`, at `3d605c2c4`. Where a lane has changed something and it has not landed, I say so.

**How far to trust each statement**
| Mark | Meaning |
|---|---|
| **[V]** | I read it in source this session. |
| **[R]** | I built and ran it this session. See "What I ran" just below. |
| **[D]** | The project's own docs or README say so. Not checked further. |
| **[T]** | A third party says so (web). Not checked. |
| **[I]** | My inference or judgement. |

Effort figures are rough, for one person who knows TUI's code, and are **[I]** throughout.

**What I ran.** A small test app on a PTY, for `--reader`, `--no-color`, `--ascii` and the `?1016` handshake. Those results are marked [R]. The rest of this file is from source and docs. The engine and size measurements are in `swifttui-answers-engine.md`.

---

## 1. Render switches: `--no-color`, `--force-color`, `--ascii`, `--reduce-motion`, `--stable-output`

**Answer.** All five are worth having in some form. In TUI, `NO_COLOR` is an afternoon, and it is missing today, which contradicts the earlier report. The right control is environment variables first, a Scene-level API second, and an optional, dependency-free flag helper third. TUI should not make `App` an argument parser.

### Why they exist

| Switch | What it asks for | Who wants it |
|---|---|---|
| `--no-color` / `NO_COLOR` | No colour | Users who set `NO_COLOR` once in their shell profile; people on monochrome or colour-themed terminals; people whose terminal palette makes an app's colours unreadable; log capture |
| `--force-color` / `FORCE_COLOR` | Colour even when output is not a terminal | CI logs that render ANSI, such as GitHub Actions, where stdout is a pipe; `app \| less -R`; `docker run` without a TTY |
| `--ascii` | 7-bit characters only | Serial consoles and rescue shells; `LANG=C`; fonts without box drawing; PuTTY with the wrong charset; **screen-reader and braille users**, who may otherwise hear or feel box-drawing characters; pasting output into plain-text tickets |
| `--reduce-motion` | Less movement | Vestibular disorders; photosensitivity (a blink or a fast pulse can be a trigger); screen readers, where a spinner is repeated noise; slow links such as ssh over mobile, where every spinner tick costs bytes; battery |
| `--stable-output` | The same output every run, with no time-driven change | CI snapshots; screenshots and README clips; recording demos; piping |

The convention text matters here. no-color.org says an app should check for `NO_COLOR` when non-empty, that any non-empty value counts, that explicit flags and user config may override it, and that it **does not** turn off bold, underline or italic [T: no-color.org].

### What SwiftTUI does [V]

All of this is in `ST:Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions+Resolution.swift`, `ST:Sources/SwiftTUIRuntime/Configuration/EnvironmentResolver.swift` and `TerminalCapabilityProfile.swift`.

- **Order:** flag, then environment, then TTY detection, then default.
- **`--no-color` removes more than the convention asks.** It sets `colorLevel = .none` **and** `emitsStyleEscapeSequences = false`. Their comment says `.never` "still disables all styling". So bold and reverse go too. **On a PTY** [R]: no colour and no reverse video were sent, and focus stays visible, because it is drawn as a `▌` glyph beside the control.
- **`--force-color` is only ever 16 colours when piped.** `.always` raises `.none` to `.ansi16`. It does not restore truecolor.
- **`CLICOLOR=0` and `CLICOLOR_FORCE` are also read.**
- **`--ascii` works at the very last step.** `TerminalCellTextRenderer.degradedASCIIText` maps each cell: `│`→`|`, `┌`→`+`, `●`→`o`, `…`→`~`, and **anything else non-ASCII becomes `?`**, including the app's own text. **On a PTY** [R]: `Café ● ✓ 你好 heading` came out as `Caf? o ? ???? heading`. It also turns on by itself when `LC_ALL`, `LC_CTYPE` or `LANG` does not mention UTF-8.
- **`--reduce-motion`** is a real accessibility preference, visible to apps as `accessibilityReduceMotion`. Built-in animations settle at their end, `Spinner` draws static text, `PhaseAnimator` holds phase one, `AnimatedImage` shows frame one, blink text loses its blink.
- **`--stable-output`** does the same to built-in views through one package-level flag, `renderingReduceMotion = accessibilityReduceMotion || stableOutput`, but apps see no preference. **It turns on by itself when `CI` is set or stdout is not a TTY.**
- **`--accessible`** is `--reduce-motion` plus `--cursor-follows-focus`. It does not imply reader mode.
- **More of the same family:** `--motion-preference`, `--contrast-preference`, `--differentiate-without-color`, `--reduce-transparency`, and `--color-profile` (monochrome, protanopia, deuteranopia, tritanopia; see question 27).

### What TUI has today [V]

| Item | State on `main` |
|---|---|
| `NO_COLOR` | **Not read by a running app.** `renderOnce` reads it (next row). |
| `FORCE_COLOR`, `CLICOLOR` | Not read. |
| `renderOnce` | Reads `TUI_FORCE_ESCAPES`, `FORCE_COLOR` and `NO_COLOR`, landed this weekend. |
| `.noColor` depth | Exists. `ColorDepth.cap` is public and composes with detection. Selection rows, shapes, glass and row backgrounds already adapt when `ColorDepth.current == .noColor` (`RowSelectionIndicator.swift:136`, `_ShapeCore.swift:150`, `GlassCells.swift:89`, `RowBackground.swift:176`). Text attributes survive, which is what no-color.org asks for. |
| Reduce motion | `TUI_REDUCE_MOTION=1`, the host setting on macOS and GNOME when the session is provably local, and `Scene.reduceMotion(_:)`, which can only add. |
| What reduce motion covers | **Spatial motion only.** Your ruling A-D3M-1 (2026-10-05): "breathing, spinners, progress bars and the like are not motion here". An app's own animations are not held (C-FU2-1). |
| Three siblings | `TUI_REDUCE_TRANSPARENCY`, `TUI_DIFFERENTIATE_WITHOUT_COLOR`, `TUI_INCREASE_CONTRAST`, read as reduce motion is. |
| Terminal overrides | `TUI_GRAPHICS`, `TUI_HYPERLINKS`, `TUI_KEYBOARD_PROTOCOL`, `TUI_TERM_PROGRAM`, `TUI_KEY_SYMBOLS`, `TUI_OSC52` and others. So the `TUI_` environment convention is already the house style. |
| ASCII mode | None. No `LANG` check for glyphs. `BorderStyle` has no ASCII set. `TUI_KEY_SYMBOLS=0` spells keys out, which is the same idea for one small area. |
| Stable output | None for a running app. `TUITesting`'s frozen clock covers tests. |
| CLI flags | None. `App` does not parse arguments; `ComingFromSwiftUI.md:192` tells apps to read `CommandLine.arguments` themselves. |

### How TUI should implement each

| Switch | Where it goes | Notes | Effort |
|---|---|---|---|
| `NO_COLOR` | Set `processCap = .noColor` at launch in `ColorDepth`, or from the app runner | Non-empty only, per the convention. Attributes stay, so focus stays visible. Needs an audit by eye of the Example at `.noColor`, since few people run it. | ½–1 day |
| `FORCE_COLOR` | For a running app, as a depth override: `1` 16 colours, `2` 256, `3` truecolor (the common Node convention [I]). Add `TUI_COLOR_DEPTH` if you want one spelling of your own. | On a terminal, the only useful meaning is "my `TERM` lies". Down a pipe, only `renderOnce` applies, since a full app now says there's no terminal and exits, unless it chooses otherwise. | ½ day |
| `CLICOLOR` | Beside it | Cheap and harmless | ½ hour |
| ASCII | **Writer-level table first.** `FrameDiffWriter` sees every line last. Map box drawing, blocks, Braille, arrows and geometric shapes, cell for cell, keeping widths. | **Do better than SwiftTUI: leave letters alone.** Translate only the chrome ranges, and keep `é` and CJK. Width is preserved, so hit tests, diffing and memos do not change. Honour `TUI_ASCII=1`, and `LANG`/`LC_*` without UTF-8 as an opt-out-able default. | 2–3 days |
| ASCII, better look | Then raise chrome that reads badly: `BorderStyle.ascii`, `[x]` toggles, `#=` tracks, `\|/-` spinner, scroll bars | I counted 323 code lines with a non-ASCII string literal across 70 files, of which 70 are one generated calibration table and 40 are `BorderStyle.swift`. Maybe 40 sites need real thought. Half-block shapes and Braille appearances need a stated fallback. | 1 week more, optional |
| Reduce motion | Exists | The owner's ruling stands for what it was about. But see the next row: the people it does not serve need another switch. | 0 |
| "Still": no animation at all | One package flag, `TUI_STILL=1` or `TUI_STABLE_OUTPUT=1`, gated where TUI has one door: `RenderContext.requestAnimation(token:frameTicks:)` and the transaction's animations. Spinner shows a static frame, breathing holds its mid value, the caret stops blinking, `.blink` is dropped. Apps see nothing, as in SwiftTUI. | This is the switch for photosensitive users, screen readers, CI, screenshots and slow links. It must also cover the focus breathing, or a screen reader hears a change every tick beside the cursor (question 25). Your clip tooling could use it too. | 2–4 days plus an audit |
| Auto-detection | Do **not** copy "on when `CI` is set". TUI already declines to run a full app without a terminal, and a PTY test on CI should see what users see. | [I] | 0 |

**What could go wrong.** `ColorDepth.detect` latches once per process and `.swiftlint.yml` guards against fake `TERM` values, so `NO_COLOR` should be read at the same point and posed on a dictionary for tests. `.noColor` is lightly exercised, so expect a handful of states that only colour distinguished. Kitty pictures and gradients are not text attributes: decide whether `NO_COLOR` also turns them off. I would say gradient chrome yes, an app's `Image` no.

### How to control them: my recommendation

| Route | For | Keep? |
|---|---|---|
| **Environment variables** | **The user**, and the only route that reaches them without the app author doing anything. A blind user sets them once in `~/.zshrc` and every TUI app obeys. | **Yes, primary.** Standard names where they exist (`NO_COLOR`, `FORCE_COLOR`, `CLICOLOR`), `TUI_*` for the rest, as now. |
| **Scene or static API** | **The app**, including a settings page. `.reduceMotion(_:)` and `ColorDepth.cap` already exist. | **Yes.** Same rule as today: an app may ask for less, not override a user asking for less. |
| **Flags in every app** | One-off use and `--help` discoverability | **Optional helper only** |

Why not SwiftTUI's way, where `App` refines `AsyncParsableCommand`:
- Every app gets about 25 reserved long flags, among them `--debug`, `--json`, `--port`, `--open`, `--web`, `--scene`, `--bind` (`SwiftTUIOptions.swift`: "All long flag names declared by this struct are reserved"). Those are common names for an app's own flags.
- It forces a dependency on swift-argument-parser and changes how `main()` works. `MyApp.main()` needs a dedicated trap to give a sensible error [V: `ST:Sources/SwiftTUI/App.swift`].
- SwiftUI's `App` has no such thing. A SwiftUI program ported to TUI should not change meaning because a flag exists.
- A flag cannot be set once for all programs; the environment can, and `NO_COLOR=1 myapp` is already a one-off.

**What flags do buy:** `myapp --help` lists them and `myapp --no-color` is easy to explain. So provide a tiny opt-in helper in `TUIApp` with no new dependency: `TUIRuntimeOptions.consume(&arguments)`, which recognises the handful of flags, removes them, and returns help text the app can print. An ArgumentParser app can wrap the same type in five lines. It should be a day's work. A documented page listing every variable is more valuable than the helper: `TerminalSupport.md:104` has a partial table today.

---

## 2. Accessibility in SwiftTUI: `--reader`, `--accessible`, `accessibility*`, the semantic tree

**Answer.** SwiftTUI builds a real semantic tree each frame and offers it four ways: a command-line "reader" in normal scrollback, a moved hardware cursor, ARIA in a browser, and native overlays. The reader is a sound idea for how blind terminal users work, and much better than pretending a full-screen grid can be read. But it is unqualified with real screen readers by its own admission, and the most useful route for many users is probably the browser. TUI could do a comparable reader in stages over one to two months, and could do the cheap half in a week.

### What each part is [V]

- **The semantic tree.** After layout, `SemanticExtractor` walks placed views and produces a flat `SemanticSnapshot` of `AccessibilityNode` values: label, role, hint, value, rectangle, actions, parent link. Built-in controls publish roles and actions themselves. `Text` publishes its full source string, untruncated.
- **`accessibility*` modifiers.** `accessibilityLabel`, `Hint`, `Value`, `Hidden`, `Role`, `LiveRegion`, `Element(children:)`, `SortPriority`, `Representation`, `Children`, `Action`, `AdjustableAction`, `AddTraits`, `CursorAnchor`, `NavigationCategory`. They write metadata; they draw nothing. `AccessibilityAnnouncer` queues spoken announcements.
- **Typed actions.** A node advertises focus, activate, increment, decrement, setValue, editText, selectText through an opaque per-control token. The runtime rejects stale, disabled, hidden or out-of-range requests. They do not synthesise keystrokes. See `ST:docs/ACCESSIBILITY.md`.
- **`--reader`** (also `SWIFTTUI_READER=1`, or F12 to toggle while running). `TerminalReaderSurface` swallows all grid output: no alternate screen, no cursor moves. It switches to line input and prints plain lines to normal scrollback. It "does not start a speech engine": the user's screen reader reads the text.
  - Commands, typed with Enter: `read`, `next`, `previous`, `up`, `down`, `find TEXT`, `categories`, `actions`, `activate`, `+`/`-`, `set VALUE`, `options`, `choose N`, `edit` with `insert`/`delete`/`save`, `updates`, `policy announce|quiet`, `history`, `scenes`, `grid`, `help`, `quit`.
  - Review position is separate from keyboard focus. Repaints do not re-read. Modals constrain review. Progress updates coalesce. Secure fields never echo. Control and bidi characters are stripped.
  - It is about 1,600 lines in `ST:Sources/SwiftTUIRuntime/Accessibility/`.
- **`--accessible`** is only `--reduce-motion` plus `--cursor-follows-focus`. The name oversells it.
- **Their honesty.** "Actual screen-reader, SSH, multiplexer, and alternative-input qualification is recorded separately for each release" [D]. The gaps register says "No WCAG conformance suite or automated screen-reader testing" and that "candidate-pin browser, VoiceOver, TalkBack, and terminal observations remain pending" [D].

**I ran `--reader`** [R] on a small test app. It takes over nothing: no alternate screen, no colour, plain lines. An extract, with my typing after `Command:`:
```
Current 1 of 8. heading(level: 1). Probe heading
Command: next
Current 2 of 8. button. Increment. Use actions for available operations
Command: activate
Action submitted.
Action accepted. Use read for current state.
Updates queued. Use updates to review.
Command: next
Current 3 of 8. group. Count: 1
```
It does what it says, and it reads well as linear text. The count shows `1` after activating, so the action really ran. Every default app also prints this line before it starts: `Terminal reader available: start with --reader or press F12 in the running app.` I had no screen reader to test with, so whether it's pleasant in VoiceOver or Orca is still open.

### How screen-reader users really use terminals

| Tool | How it works | What that means for a TUI |
|---|---|---|
| **VoiceOver** with Terminal.app or iTerm2 | Reads the terminal's text area through macOS accessibility. It sees a grid of text and a caret. | No element tree can reach it: the parity map is right that far. |
| **Orca** with GNOME Terminal | Reads through AT-SPI: inserted text and caret moves from VTE. | Same. Caret position and what just changed are the signals. |
| **NVDA** with Windows Terminal or conhost | UI Automation, with a review cursor, and reads dynamic changes. | Same. |
| **TDSR** | A wrapper around a shell using a terminal parser; has a review cursor and cursor tracking; on macOS and Linux [T: its README]. | Reads the same grid, line by line. |
| **Speakup** | Linux kernel console reader; reads what changes and what is under the cursor. | A cursor that jumps to update a timer makes it read fragments [T: the essay below]. |
| **BRLTTY** | Braille display showing a window of the screen, which tracks the cursor. | A hidden or parked cursor means the window goes to the wrong place. [I from how it works; I could not fetch the page] |

The picture from users is consistent. The essay "The text mode lie" (Speakup and NVDA user) reports full-screen tools being painful because a redraw moves the cursor to write a spinner and back, so the reader speaks fragments of history. Each keystroke redraws, with lag. It praises `menuconfig` because the cursor stays on the selected row and `irssi` because it uses scroll regions, and says linear output beats a redrawing TUI [T: xogium.me, not independently tested; a Lobsters commenter disputes some of the technical account]. Charm's `huh` form library has `WithAccessible`, which "drops" the TUI for plain prompts, enabled by an environment variable [T: its README]. Gemini CLI, built on Ink, has a `--screen-reader` mode that swaps spinners for text [T: PR 7307].

### How well it suits the purpose [I]

| Good | Weak |
|---|---|
| **Line-oriented output in scrollback** is what every tool above reads best. | **A command language.** The user learns `next`, `read`, `activate`. That is a real barrier, and is not how they run other apps. It resembles `ed`, not a form. Fine for power users. |
| **No alternate screen**, so scrollback and review work. | **No built-in single-key navigation.** Each step costs a word and Enter, so slow for browsing. |
| **Update policy is quiet by default**, avoiding the spinner problem. | **Not validated with real screen readers** [D]. No user reports found. |
| **Actions are typed**, so a Slider is `set 7`, not guessing arrow keys. | Custom controls need author labels. A custom canvas is one unlabelled node. |
| **Works over ssh** with no extra stack. | A 2D layout is flattened. That is unavoidable. |
| F12 keeps state while switching. | It is on by default in every `App`, with a line printed at startup. |

The browser companion (question 9) probably gives a better experience for someone sitting at a machine with a browser, since ARIA reaches the real assistive stack. The reader is for ssh, consoles and braille.

**So TUI's parity-map reason is half right.** `parity-map.json:27` says "A terminal has no assistive-technology stack… The screen reader IS the terminal's own, driven by the text TUI already emits". True for the first sentence. But the second implies the text TUI emits is readable, and a full-screen frame with a hidden cursor and diffs is the worst case in the table above. TUI's cursor is hidden for the whole run (`App.swift:441`) and text fields draw a synthetic caret, so a screen reader cannot even follow typing. SwiftTUI shows the real cursor at a text field's caret **by default** (`RunLoop+Presentation.swift:93-110`) [V]. That one is an easy, separate gain.

### Could TUI do comparable things, and how

TUI has no semantic tree. It renders bottom-up to `FrameBuffer`s of ANSI strings, which also carry hit-test regions with `focusID`s. Memos carry those too. That gives a cheap path:

| Stage | What | How | Effort |
|---|---|---|---|
| A | **Real cursor at the caret; cursor follows focus** | Question 25 | 2–4 days |
| B | **No flashing noise**: the "still" switch of question 1, with spinner labels | Question 1 | 2–4 days |
| C | **Linear frame mode without a tree**: `TUI_READER=1` keeps the normal render, and instead of writing the grid, prints changed rows as plain text to scrollback, with the focused control's text. Row text and the first hit-test region for `focusID` already exist on the root buffer. A control's name can be read from the cells in its region. | No semantic tree, so no API. Crude, and it gets you "what changed" and "what has focus" over ssh. | 1 week |
| D | **`accessibility*` modifiers that really store** | Add a payload to `FrameBuffer`, travelling exactly as `hitTestRegions` does: shifted by combine, kept by memos, composited at the root. Empty and nearly free when not used. The `RenderContext field cost` note says fields are not free, so keep it on the buffer, read only at a frame's end. Controls publish role, label, value, actions at the existing `FocusRegistration` helper. | 2–3 weeks. Reverses the parity map's refusal, and adds a real `.accessibilityLabel` that today fails to compile, which helps compile-as-is too. |
| E | **Command reader** like theirs, over D | Their 1,600 lines are MIT and readable; the model is small. | 2 weeks |
| F | Browser ARIA | TUI's WASM port renders through xterm.js, which has its own screen-reader mode. Not comparable, and not now. | L |

**What could go wrong.** A payload on `FrameBuffer` costs a little in the hot path, so A/B it. Labels for lists: windowed rows mean off-screen rows are not in the frame. SwiftTUI has "collection review controls" for this. Custom `Renderable`s that build a bare `FrameBuffer(lines:)` drop payloads, the same class your `container-payload-audit` note describes. And "qualified with VoiceOver" takes real testing, ideally with blind users; nothing replaces that.

---

## 3. "Native hosts" and "native browser" in platform support

**Answer.** They mean running a SwiftTUI app **with no terminal at all**. The same view tree renders as a grid of styled cells, painted by a SwiftUI view, an Android Compose view, or a browser canvas. It is a retro look inside a normal app, not a terminal emulator.

| Host | Product | How it runs | Input | Status |
|---|---|---|---|---|
| Terminal | `SwiftTUICLI` | Normal terminal app | Terminal | Main path |
| **Native SwiftUI** (macOS 15, iOS 18) | `SwiftUIHost`, separate repo | Runtime in-process. `SwiftUIHostAppView` is an ordinary SwiftUI `View` in your window. Cells drawn with a bundled font. Damage-based repaint. | AppKit/UIKit keyboard, pointer, touch, clipboard | Preview [D] |
| **Android** | `SwiftTUIAndroidHost`, separate Gradle plugin | Swift cross-compiled, called through JNI. Compose draws cells and bitmaps. | Keys, soft keyboard, touch | arm64 preview; runtime acceptance "not closed" [D] |
| **Browser, static WASI** | `SwiftTUIWASI` plus npm `@swifttui/web` | Swift compiled to WebAssembly, in the page. Canvas by default, experimental DOM. No xterm.js. No server. | Browser | Preview [D] |
| **Browser, localhost WebHost** | `SwiftTUIWebHost` | Native process, embedded HTTP and WebSocket server, browser paints frames | Browser | `--web`; also the companion (question 9) |

How they connect [V]: the render pipeline produces a committed frame as structured data: raster cells, images, and semantic nodes. A host presents that. There is a documented "host wire" (`ST:docs/HOST-WIRE-CONTRACT.md`) with versions and delta frames. A terminal is just one presenter. TUI's pipeline emits ANSI strings, which is why it has no such option today [V for TUI; the first report §14 reached the same view].

**Who would want them** [I]
- A team that has a terminal tool and wants a "desktop" or web version without a rewrite.
- Embedding a terminal-style pane in a Mac or iOS app: a log view, a game, a retro look.
- A browser demo on a landing page with no server. Their home page does this [D].
- Someone who has no reason to want terminal cells at all should use SwiftUI itself. On a Mac, the host gives you a cell-grid UI where you could have had real controls. So its reach is real but narrow.

**For TUI.** TUI's WASM port runs inside xterm.js, which is simpler and gives a browser version. It is XL to add structured hosts, and I would not chase it. Note the "native browser" phrase: it just means browser without a terminal emulator.

---

## 4. Compiled hot reload

**Answer.** Their tool recompiles only your executable target into a new dynamic library, loads it into the running process, and swaps the root view, keeping state that can round-trip through `Codable`. TUI could support this: 3 to 5 weeks. Its identity design is the main obstacle, because `ViewIdentity` compares metatypes, and a reloaded image has new ones. A cheaper "hot restart" would get most of the value in about a week.

### How theirs works [V]: `ST:Tools/SwiftTUIDev/ReloadDriver.swift` (632 lines), `Sources/SwiftTUIRuntime/HotReload/`, `Sources/SwiftTUIGraph/HotReload/`

1. **You add a small export** guarded by `#if DEBUG && SWIFTTUI_HOT_RELOAD`:
   `@_cdecl("swifttui_hot_reload_root") ... HotReloadExport.retainedRoot { MyRootView() }`.
2. **`swifttui-dev --package-path X --product Y`** builds the app once with `-DSWIFTTUI_HOT_RELOAD` and `-export_dynamic` (so the app's framework symbols can be found), and runs it with a private spool directory, mode 0700.
3. **It watches your sources** (debounce 200 ms). It reads the real compiler command from SwiftPM's `description.json`.
4. **On an edit** it runs `swiftc -emit-library -module-name <YourModule>_SwiftTUIReload_N`, plus `-undefined dynamic_lookup` on macOS. The unique module name prevents duplicate type registration. Only the executable target's existing files are recompiled. Dependency, manifest, new-file, resource or toolchain changes need a restart.
5. **It publishes the image** atomically and signals the app. The app's loader validates owner and mode, `dlopen`s it with `RTLD_LOCAL`, checks ABI and toolchain scalar exports, then calls your export. **Loaded images are never unloaded**, since Swift metadata can outlive them. After 100 reloads it asks for a restart.
6. **The swap.** It rehearses the new root to find its `@State` declarations ("schema discovery"), then matches old slots to new.
7. **State survives only through `Codable`.** `SnapshotEncoder` and `SnapshotDecoder` round-trip values, with type names compared after stripping the reload module alias. Focus, scroll offsets and inactive-tab values are replayed too. Non-Codable values, changed types and ambiguous owners reset to their initial value, with a diagnostic. Matching uses declaration names, so moving lines or adding a `@State` keeps the others.
8. **Build failures leave the old generation running.** Compiler errors go to a log file, since the app owns the screen.

Limits [D]: debug only, macOS and Linux terminal sessions, root content only (scene declarations stay), one target, Swift 6.4 under swiftly.

### Could TUI do it, given identity-keyed `@State`?

Yes, but these bite [V for the code facts]:

| Problem in TUI | Why | Remedy |
|---|---|---|
| **Identities change** | `ViewIdentity` is a chain of `IdentityNode`s holding **metatypes**, compared by `ObjectIdentifier` (`ViewIdentity.swift`). A view type in a reloaded image is a different metatype. So every key in `StateStorage`, every memo, every focus id misses. | At reload, translate: walk the old store by `renderPath()`, a string of names, strip the reload module alias, and match the new frame's paths. A one-shot translation at a frame boundary; no cost in normal frames. |
| **`propertyIndex` is declaration order** | `StateKey` is identity plus index, so adding a `@State` above another shifts everything. | Capture labels from the property walk (`Mirror`) at both ends and map by name. |
| **Values** | `StateBox<Value>` is generic, and user types are new types in the new image. | **Better than SwiftTUI in one way:** a value of a type not from the app's module (`Int`, `String`, `[String]`, `Date`) has the same metatype in both images, so reuse the box and no `Codable` is needed. App types need `Codable` round trip, or reset. |
| **Static caches keyed by type** | `ValueHashPlans`, `RenderCache`, measure memos, the static-witness providers | Clear them all at the swap. Cheap, since it is a debug path. Some are process-wide and need a clear hook. |
| **Root** | `RenderLoop` is generic over the scene. | Wrap the root in a type-erased host in debug, as they do, with a `@_cdecl` export. A `TUIMacros` macro could write the export. |
| **Lifecycle** | Old `.task`s must cancel. `onAppear` must fire or not. | `LifecycleManager` tokens are path strings, so it can retire and restart. Decide the semantics. |
| **Symbols** | The traits `DeadStripUnusedAPI` and `UnexportTUISymbols` exist to remove exactly what a `dlopen`ed image needs; `ShippingAnApp.md:121` says a plugin stops loading. | The driver builds with `--disable-default-traits`-style settings, `-export_dynamic`. `Package.swift:1060-1080` documents this. |
| **Driver** | | Their driver is MIT, 729 lines, self-contained. Adapting it is about a week. |

**Effort:** driver 1 week; state translation 1–2 weeks; caches, lifecycle, focus and scroll 1–2 weeks. About 3–5 weeks, and it will take a while to be trusted. **Risks:** stale-cache bugs you already know as a class (`stored-property-layout-stale-build`, `memo key hashes an address`); `-undefined dynamic_lookup` turning missing symbols into runtime aborts; debug link time of a 73 MB binary is not paid (only the image links), but generic specialisation across images may be slow; `Sendable` and actor isolation are unaffected.

**A cheaper alternative [I]: hot restart.** On an edit, `swift build`, then quit and relaunch the app, restoring `@State` from a snapshot file by path and name. About a week, shares the translation logic above, needs no `dlopen`, and works for dependency and new-file changes too. It loses process state, and a rebuild is slower: measure a debug incremental link of `Example` first. I would try this first and see whether the owner still wants the dlopen version.

---

## 5. The embedded terminal: `TerminalView`

**Answer.** `TerminalView` is a view that runs a real program, such as a shell, in a pseudo-terminal and shows its screen inside your layout. Its use case is multiplexers, dev tools with a shell pane, previews with `less`, and IDE-like layouts. It lives in a separate package and uses the SwiftTerm emulator.

- **API** [V: `swift-tui-terminal-view/Sources/SwiftTUITerminalView/TerminalView.swift`]: `TerminalView(session: TerminalProcessSession(command: "/bin/zsh", initialSize: …))`, with `keyRouting:` to let the host keep a key such as Escape, `onTitleChange`, `onExit`, and `.hostFocused($focus, equals:)`. `TerminalSession` is a protocol, so a session can be ssh, a recording, or a remote multiplexer pane.
- **Behaviour** [D]: scrollback 2,000 lines by default, selection and copy, wheel history, Kitty keyboard flags 1, 8 and 16, pane-owned Sixel and Kitty images, OSC 99 notifications. Output coalesces into snapshots at 16 ms.
- **Doc inconsistency in their repo** [V]: the framework's gaps register says "No Sixel/Kitty graphics inside embedded panes", "No Kitty keyboard", "No pane-local selection". The terminal-view README says release 0.16.0 added all of those. The register looks stale. The source has `TerminalGraphicsStore.swift`, `TerminalSixelPreflight.swift` and `TerminalTextSelection.swift`, which supports the README.
- **Accessibility** [V]: the pane has a real semantic representation, with frozen review, line submission, and copy.
- **Example:** `terminal-workspace` in their examples repo: tabs, splits, a `Ctrl+K` palette, persisted layout. No detach and reattach.
- **Who wants it** [I]: people building tmux-likes, Claude-Code-style agents with a shell pane, a TUI IDE, a deployment tool that shows a live build. It is rare, but nothing else can do it, and it is a strong differentiator for those people.

See question 36 for what it would take in TUI.

---

## 6. Sixel: the decision and whether to revisit it

**Answer.** The decision is in `Documentation/Images and terminal graphics/Terminal graphics protocols.md` §6: "Do not ship Sixel", 2026-09. It is still right for now, with one thing to do first: finish Kitty *classic* placements for `Image`, which that document's §12 calls the cheapest coverage available and which is half built. Then revisit Sixel if and when Windows matters, because Windows Terminal draws Sixel and no Kitty.

### The recorded reasoning

- §6: "One unique host (tmux, useful only into iTerm2, which Kitty already covers), no alpha, no retained images, no placements — and it *prints* on Apple Terminal."
- §4: TUI's whole pipeline is defined on cells. Unicode placeholders put a picture in the grid. Sixel draws pixels at the cursor.
- §3.2: 14 terminals draw Sixel or iTerm2 images and no Kitty, but "the largest single group of hosts it misses is not the Sixel crowd": it is six that speak Kitty but not its placeholders.
- §11 (2026-09-05): the cell objection can be worked around by substituting at the writer, after clipping and compositing, but it costs an encoder, a damage model and repairs "one-to-two orders of magnitude" more expensive: about 12 bytes against 2,170 to repair a Retina cell. "The recommendation in §6 does not change on this analysis alone."
- §12: classic placements take TUI from 5 terminals to 11. §13 (2026-10-24): the writer substitution now exists, for hairline separators. **`Image` still draws only through placeholders.**

### Who draws what

From §3.2 of that document, surveyed 2026-09-05 from each project's source. Ghostty's position rechecked today [T].

| | Terminals | Default on? |
|---|---|---|
| **Kitty placeholders, no Sixel** | kitty, Ghostty, patched st | Yes |
| **Kitty placeholders and Sixel** | iTerm2, Rio | Yes |
| **Kitty classic and Sixel, no placeholders** | WezTerm, Konsole, Contour, Zellij | Yes |
| **Kitty classic only** | Warp, partly xterm.js + addon (which also has Sixel) | Yes |
| **Sixel, no Kitty** | **Windows Terminal, foot**, mintty, mlterm, DomTerm, Yaft, Tabby, Eat | Yes |
| **Sixel behind a switch** | xterm (needs `-ti vt340`), VTE/GNOME Terminal (build flag off), Black Box, VS Code (setting off), Hyper, tmux (build flag) | No |
| **Neither** | Apple Terminal, Alacritty, screen, PuTTY, Zed, JetBrains | |

Ghostty's maintainer said in November 2024 that it will not support Sixel, "not final" [T: discussion 2496].

### Who does Sixel serve?

Mainly: **Windows Terminal** users, **foot** users on Wayland, **mintty** (Git Bash, Cygwin), and legacy-minded users on mlterm. Those are real groups, though few overlap with TUI's macOS and Linux desktop audience today, except foot. tmux with Sixel enabled reaches them through a multiplexer. SwiftTUI needs Sixel because it ships Windows; TUI does not yet [I].

### Should it be revisited? [I]

**Order of work:**
1. **Kitty classic placements for `Image`.** Reuses encoder, store, compression and the writer substitution that hairlines built. It adds WezTerm, Konsole, Warp, Zellij, Contour, xterm.js. The last matters for your own browser demo. About 1–2 weeks, plus per-host measurement of `C=1` and `x,y,w,h` (§12.4). SwiftTUI uses exactly `a=T`, `a=p`, `C=1` and source rectangles (`TerminalImageKittyRendering.swift`) [V], so at least one project relies on them on those hosts.
2. **Sixel, on the same writer substitution.** §11.4: `ASCIIPalette+Adaptive` already does median cut in OKLab, so the palette work is mostly there. The encoder is small (their `TerminalImageSixelRendering.swift` is 275 lines [V]). Detection is DA1 parameter 4, which TUI already reads in probes, plus XTSMGRAPHICS. The cost is the damage model, the bottom-row scroll hazard (DECSDM's sense is inverted between versions), and no retained store, so every scroll retransmits. About 2–3 weeks after step 1.
3. **Trigger:** the Windows port reaching `TUIApp`, or a user asking on foot.

**What could go wrong.** Sixel has no alpha, no deletion and no z-order. A modal over a picture repaints it. Scrolling a picture list is very expensive. On a slow link it should auto-downgrade to glyphs. And §2.3 records the hazard: a Sixel sent to a terminal without it prints about 21 cells of garbage, so only send on positive evidence.

Also: `Terminal compatibility survey.md` lines 2670 and 4197 hold the measurements, which must be updated by any change here.

---

## 7. The command palette

**Answer.** A searchable sheet of named commands, as in VS Code's Ctrl-Shift-P. Commands are declared with a modifier beside the views they belong to, and bubble up to a sheet that you present. TUI has nothing named this, though it has most of the parts.

**API** [V: `ST:Sources/SwiftTUIViews/ActionScopes/PaletteCommandModifier.swift`, `Commands-And-Key-Input.md:211`]

```swift
sectionContent
  .panel(id: "root")
  .keyCommand("Command palette", key: .character("k"), modifiers: .ctrl) { showsPalette = true }
  .paletteCommand(name: "Reload data", description: "Fetch the latest snapshot") { reload() }
  .paletteSheet("Command palette", isPresented: $showsPalette)
```

- `paletteCommand(name:description:isEnabled:action:)` and `paletteSheet(_:isPresented:onDismiss:)` are on `ActionScope`, their term for a view that hosts commands such as `Panel`. Neither is a SwiftUI API.
- `DefaultPaletteStyle`: filter field with **fuzzy matching**; up and down, or Tab and Shift-Tab, to move; Return to run. At most twelve rows. Escape closes it. Needs at least eight terminal rows.
- It updates live as the subtree changes.
- `.paletteStyle(MyStyle())` replaces the look. `PaletteStyleConfiguration` gives commands with stable ids, `perform()`, `route { }`, `dismiss()`.

**For TUI [I].** It would suit TUI *better* than it does SwiftTUI, since TUI already has `Commands`, `CommandMenu`, `keyboardShortcut` and a menu bar (`TUICommands/`). A palette could list every menu command automatically through `CommandsCollector`, with their shortcuts shown. That beats declaring things twice. Add `.paletteCommand` for extras. Draw it in `Sheet`, reuse `searchable`'s field and matching. It is TUI-only, so it stays apart from SwiftUI names, per project rules: a modifier such as `.commandPalette(isPresented:)`. About a week, and a good visible feature. Fuzzy matching needs a small scorer; `TUISearch` may have none, I did not check.

---

## 8. `Canvas`

**Answer.** SwiftTUI has a `Canvas` that is its own design, with a different signature from SwiftUI's. TUI has no `Canvas`. Its `GraphicsContext` has only the text half, and its docs and your owner note ("Canvas later on the same context") plan the rest. A SwiftUI-signature `Canvas` is about two to four weeks, and most of the hard parts already exist in the shape rasterizer.

### SwiftUI's `Canvas` [V: sdoc]

`Canvas(opaque:colorMode:rendersAsynchronously:renderer:)`, where `renderer` is `(inout GraphicsContext, CGSize) -> Void`, plus a `symbols:` builder to draw views as images. It is immediate-mode: a closure draws paths, images, text and resolved symbols, with fills, strokes, gradients, clipping, blend modes, filters and layers.

### SwiftTUI's [V: `ST:Sources/SwiftTUIViews/Canvas.swift`, `CanvasContext` in Primitives]

- `Canvas(_ drawing: some CanvasDrawing, grid: .braille2x4)`, or a closure `Canvas(grid:) { (inout CanvasContext) in … }`, or keyed by an input.
- Coordinates are **continuous cells**. `Point(x: 4.5, y: 2.5)` is the middle of a cell.
- `CanvasGrid` chooses how in-cell samples turn into glyphs: Braille 2×4, octant 2×4, sextant 2×3, quadrant 2×2, half blocks, full cell.
- `CanvasContext` has `line`, `fillRect`, `strokeRect`, `fillCircle`, `strokeCircle`, `fillEllipse`, `strokeEllipse`, `setPixel`, `clearPixel`, `setCell`, `fillCell`, `setSample`, `foreground`, `background`.
- `Canvas.pixelGrid(width:height:pixels:mode:)` for a dense bitmap.
- **Different from SwiftUI's.** No `GraphicsContext`, no `Path` drawing in the same call. SwiftUI `Canvas { context, size in … }` code does not compile unchanged, though a size overload is close.
- Value drawings are `Equatable` so a canvas can be skipped when unchanged.

### TUI today [V]

- `Canvas` does not exist. `parity-map.json:895`: "Renderable + FrameBuffer… A SwiftUI-shaped `Canvas` over a `GraphicsContext` waits on shapes". **Shapes have shipped**, so that wait is over: the map entry is out of date in spirit.
- `Sources/TUIFoundation/Views/GraphicsContext.swift` has opacity, transforms, colour filters, layers, drawing text lines, runs and slices. Its header says: "`Canvas` will draw with the same context, with paths and images, later."
- The parity map's family note at line 556 lists the missing half: paths, shadings, images, resolved text, clipping, blend modes. `TextRenderer design study, O16`, phase 2. Decision D3 in the refusal review: "implementable (L). Decide after W1".
- `ShapeRaster`, `ShapeStroker`, `ShapeHalfBlocks` and `ShapeCells` already rasterise any `Path` at half-block resolution, with coverage as alpha. `ImageTileRaster`, `GradientRaster` and `MeshRaster` handle paints. `OpacityBlend` composites.

### What it would take [I]

| Piece | Work | Effort |
|---|---|---|
| `Canvas` view with SwiftUI's exact init | `_CanvasCore`, a `Renderable` per project rules. `opaque`, `colorMode`, `rendersAsynchronously` accepted; `colorMode` honoured only as far as the opacity rules allow. | 2 days |
| `fill`, `stroke` with `Shading` (`color`, gradients, `style`) | Reuse `ShapeRaster` and `ShapeStroker` | 3–5 days |
| `clip(to:)` and `clipToLayer` | Coverage mask combined | 3 days |
| `draw(Image)`, `draw(Text)`, `resolve`, resolved `symbols:` | Text exists; picture path for images is the hard one, since a Kitty picture cannot be drawn into cells: fall to glyph rendering | 1 week |
| `blendMode` | Reuse per-cell blend | 2 days |
| TUI extra: choose resolution | `.canvasResolution(.braille)`: half blocks are colourful but 1×2; Braille is 2×4 and one colour per cell. Their `CanvasGrid` shows the range. | 3 days, as a modifier |

**Total about 2–4 weeks.** Coordinates: `CGSize` is square-unit in your `Shape` world (O0), so use the same units as `Shape.path(in:)`. **What could go wrong:** Path boolean operations are declined and should stay so. A `withCGContext` route is Apple-only. Closures cannot memo, so a Canvas re-renders each time it is drawn, unless an extra Equatable input is added. A plotting user will want Braille plus per-cell colour, which is a known visual compromise.

**Why bother:** sparklines, plots, a charts module would stand on it. SwiftUI programs using `Canvas` today fail to compile on TUI. It closes a parity hole and the visible gap at once.

---

## 9. The local web server

**Answer.** Every interactive SwiftTUI app, by default, starts an embedded HTTP and WebSocket server on `127.0.0.1` with a random port, and prints a URL holding a secret token. Opening it shows the same running app in a browser, mainly to give screen-reader users real ARIA. `--companion off` turns it off.

**Why it exists** [D, I]: the "browser companion" is their accessibility story. A browser has a real assistive stack; a terminal does not. It also gives a nicer pointer, a second view, and remote use through an ssh tunnel. The same code serves `--web`, which runs browser-only with no terminal.

**What it does** [V: `ST:Platforms/WebHost/Sources/SwiftTUIWebHost/`]
- In-tree HTTP/1.1 and WebSocket server: no NIO, no Foundation networking. GET and upgrades only.
- Serves a packaged Canvas page, with a semantic ARIA sidecar.
- It adds presentation and input, "never creates a second app". Same run loop, same state. When both are attached, the grid is the smaller of the two sizes, so opening a small browser shrinks the terminal's layout [D].
- `myapp --companion-url` prints running instances' URLs. The Unix discovery socket is at `/tmp/swifttui/<app>/<id>.sock`, chmod 600 [V].

**Why on by default** [I]: because someone who needs it cannot be expected to opt in before they can use the app. A blind user can read the URL line from scrollback before the screen is taken. Their docs do not state a reason beyond that. It is `auto`: only when stdin and stdout are terminals; never with `--json` or the terminal-only `SwiftTUICLI` product.

**Security model** [V]

| Layer | What it does |
|---|---|
| Bind | Companion is hard-coded to `127.0.0.1` (`WebHostCompanion.swift`). `--bind` applies only to `--web`. |
| Token | 122 random bits from `UUID()`, as hex (`WebHostToken.swift`). Compared in constant time. |
| Token carriage | URL query `?token=…`, then a cookie: `SameSite=Strict; HttpOnly`. No `Secure`, since it is HTTP on loopback. `Cache-Control: no-store`. |
| WebSocket | Requires the token **and** an `Origin` check (`WebHostOriginPolicy`). A cross-site page cannot drive it. Missing `Origin` is allowed, as non-browser clients have none. |
| Limits | Bounded ingress queue, record sizes, duplicate-header rejection. A retired connection cannot act. |
| Discovery | Owner-only socket; Windows registry ACL. |
| Stale pages | Reconnect refuses an outdated adapter. |

**The trade-offs [I]**
- **Each default app has a listening socket** in the process. Local-only, and token-gated, so a remote attacker needs the token. Other local users on a shared machine can reach the port, but not without the token.
- **The token is a bearer secret.** It is in terminal scrollback, in browser history, in tmux logs, and can go to `script` recordings. Anyone with it can operate the app, and read what the app shows. Their docs say "Keep the token private".
- **`--web` with `--bind 0.0.0.0`** is plain HTTP on a network, so the token travels unencrypted. That is the user's choice and is not the default.
- **Surprise factor.** Corporate security tools and a code reviewer may object to a terminal app opening a port. The default product also links the bundle.
- **Printed line.** A URL appears before full-screen mode. It disappears from sight once the alternate screen opens.

**How to turn it off.** `--companion off`, `SWIFTTUI_COMPANION=off`, `RuntimeConfiguration.builder().companion(.off)`, or link `SwiftTUICLI` rather than `SwiftTUI`. `--companion-port` pins a port.

**For TUI [I].** Evidence.md advised against a default-on server, and I agree. If TUI ever has a browser route, make it opt-in with an environment variable.

---

## 10. Why TUI has no `DocumentGroup`

**Answer.** Recorded reason: a `DocumentGroup` opens a window per document, and a terminal app has one surface, so it is a scene TUI declines. The original reason, `FileWrapper` missing on Linux, was overtaken: `FileDocument` itself shipped later.

| Source | What it says |
|---|---|
| `Tools/APIParity/parity-map.json:262-280` (current) | "DocumentGroup and its configurations… open, edit and save documents in windows of their own, one per document; a terminal app has one surface, the terminal (the same reason as the scene family above), and a document scene is a scene… The file panels themselves ship… and FileDocument with them, on Apple platforms." |
| `Historical/Presentation and windows/File panels.md:346-351`, decision C-O10-1 | "`DocumentGroup` and its configurations stay declined in the document family: they open a window per document, and a terminal app has one surface." Its `ReferenceFileDocument` is an `ObservableObject`, and exists for undo and autosave TUI lacks. |
| `Historical/SwiftUI parity process/The refusals re-examined (wave 17).md:847-855`, P16 | "CONFIRM: DocumentGroup, FileDocument, ReferenceFileDocument… They read and write through `FileWrapper`, which is absent on Linux (verified)." |
| `Historical/Presentation and windows/Windows - several scenes on one surface.md:512` | "not this lane's: they need the file panels of refusal review O10." |
| `Sources/TUI/TUI.docc/Articles/ComingFromSwiftUI.md:191` | Replacement: "A `WindowGroup`, with `.fileImporter` and `.fileExporter`." |
| `Documentation/Open owner decisions.md` | No open item on it. [V by grep] |

**A note [I].** The first reason is thin now. Since then, TUI has shipped `Window`, multiple scenes on one surface, and `FileDocument` on Apple platforms. A `DocumentGroup` that shows one document at a time, with `File > New/Open/Save` commands and a dirty flag, would compile SwiftUI document apps as written, which is your stated main goal. It is not obviously wrong for a terminal. It would be a medium job, and a call for the owner. `FileWrapper` on Linux is still the blocker for parity there.

---

## 11. "Hosted services or AI features": what was searched

**Answer.** It meant neither project sells or calls a service, and neither has AI as a product feature. Both are libraries that make no outbound network calls of their own. The earlier report did not list its search terms, so I searched again today and list them here.

| What I looked for | How | SwiftTUI | TUI |
|---|---|---|---|
| Cloud render, paid tier, pricing | Grep site text and sibling READMEs: `pricing`, `cloud`, `hosted`, `paid`, `enterprise`, `sponsor` | Nothing | Nothing |
| LLM integration | Grep sources, tools, examples: `OpenAI`, `Anthropic`, `LLM`, `Copilot`, `ChatGPT`, `Claude` | Nothing (`AGENTS.md`, `CLAUDE.md` guide contributors) | Nothing in `Sources` (`.claude/` guides contributors) |
| Telemetry | `telemetry`, `analytics`, `PostHog`, `Sentry`, `Mixpanel`, `Amplitude` | Nothing. The one hit, `Amplitude`, is a spring solver's variable. | Nothing, apart from a sample toggle `"Share usage data"` in `Sources/Stress/Sessions/SettingsSession.swift:80`, which does nothing. |
| Licence keys | `licenseKey`, `license key`, `API key`, `apiKey` | Nothing | A sample `apiKey` `SecureField` in `Example` |
| Copilot-style scaffolding, project generator | Their CLI surfaces; earlier report's check for a scaffold CLI | None. `swifttui-web build` builds web bundles; `swifttui-dev` is hot reload. | None |
| Outbound network | Grep `URLSession`, `URLRequest`, `NWConnection`, `connect(` | No `URLSession` or `URLRequest` outside tests. `connect` only for the Unix discovery socket and its own loopback tests. | `URLSession` only in `TUIImage/ImageLoader.swift`, for an image the app asks to load |
| Package dependencies | Manifests | collections, async-algorithms, argument-parser, docc plugin | swift-syntax, docc plugin, benchmark (opt-in) |

[V for all greps. This is by name, so it would miss a differently named feature. Their private coordination repo is not visible.]

**Scope of the word "none".** It does not mean AI is unrelated: both projects are visibly built with AI assistance. And `optional.dev`, SwiftTUI's author's site, lists no paid offering [earlier report, D].

---

## 12. "Pixel mouse": SGR-pixel mode (`?1016`)

**Answer.** Normally a terminal reports the mouse by character cell. xterm's mode 1016, "SGR-Pixels", reports it in pixels. SwiftTUI turns that into fractional cell coordinates, where it can prove the terminal supports it. Question 19 covers what that buys.

**The mechanism.** The app sends `CSI ? 1006 h` for SGR encoding, and `CSI ? 1016 h` in addition. Reports then have the same format as SGR mouse reports (`CSI < b ; x ; y M`), but `x` and `y` are pixels.

**What SwiftTUI does** [V: `TerminalMouseCoordinateResolution.swift`, `PointerPrecisionPolicy.swift`, `TerminalHostEscapeSequences.swift:89-107`]
1. **Needs cell pixel size first** (`trustedCellPixelMetrics`). Without it, cells.
2. **Asks the terminal.** A DECRQM query for mode 1016: "do you know this mode?" Yes means pixels; no means cells. **On a PTY** [R]: it sent `?1016$p`, then sent `?1016h` only when my harness answered yes. With no answer, it never turned the mode on.
3. **If unanswered,** falls back to a table with source URLs: xterm, xterm.js, foot, kitty, WezTerm, iTerm2. Under tmux or screen, it returns no.
4. **Converts** pixels to continuous cell coordinates: `Point(x: 4.5, y: 2.5)`, the centre of a cell. `DragGesture.Value.location`, `startLocation`, `translation` are `Double` based. On a cell-only terminal, they get the centre of the reported cell.
5. **Exposes it:** `PointerInputCapabilities.supportsSubCellLocation` tells an app, and `PointerPath` keeps samples.
6. **Teardown:** `?1016l` then `?1006l`.

**Used by** [V]: `Slider` (`Slider.swift:155`), scroll indicators (`ScrollIndicatorSupport.swift:118-121`), `Canvas` gestures.

**TUI:** none. `?1016` only appears in `Documentation/Future options.md:318`, as a declined option, with named hazards.

---

## 17. What are FIGlet banners?

**Answer.** FIGlet is a 1991 program, and a font format, that draws large letters out of ordinary characters. A word becomes a multi-line ASCII-art banner. It is what you see at the top of many command-line tools.

```
 _   _ ___
| | | |_ _|
| |_| || |
 \___/|___|
```

**SwiftTUI** [V]: `TextFigure("Deploy", font: .standard, colorMode: .authored)` in `ST:Sources/SwiftTUIViews/Primitives/TextFigure.swift`. Vendored `swift-figlet` (MIT, OPTIONAL.DEV), **290 font files, 7.2 MB in the repo**, embedded. `TextFigure.availableFonts` lists them. It is the "big text" story in a framework with no `Font`. Their `--ascii` table exists partly because some fonts use box and block characters.

**TUI** [V]: nothing by that name. `figlet` appears in no source or historical doc. `.font(.largeTitle)` maps to three text tiers, not big letters.

**Worth it? [I]** A cheap, charming feature for a splash screen or header. As a separate optional module, with a handful of fonts, it's two days. Fonts are public-domain-ish but with mixed provenance: check each one's licence. Keep it out of the default product because of bytes: 7 MB in a repo also reaches all clone users.

---

## 18. Animated images

**Answer.** `AnimatedImage` is simple: it decodes a GIF into RGBA frames, PNG-encodes each frame once, and on a timer swaps the `Image` it shows. It goes through whichever path a static image uses: Kitty, Sixel or cell art. It does not use Kitty's animation protocol. TUI could add this in about a week, and would do better on memory and bytes on Ghostty, kitty and iTerm2.

### What SwiftTUI does [V: `ST:Sources/SwiftTUIAnimatedImage/`, 681 lines]

- **Decoding:** vendored `swift-gif`. Only GIF. `AnimatedImage(gifData:)`, `AnimatedImage(gifContentsOf:)`, or `AnimatedImage(frames:framesPerSecond:)` from your own frames. `AnimatedGIF.encode` also writes GIFs, used by the GIF editor example.
- **Timing:** a `.task` runs `AnimatedImagePlayback`: `Task.sleep` per frame's delay, sets `@State frameIndex`. Zero delay becomes 100 ms, floors at 20 ms. Honours loop count. Reduced motion or stable output shows frame one.
- **Each tick is a normal `Image` change:** `Image(data: sequence.encodedImageData(at: frameIndex))`, PNG cached per frame.
- **Kitty path:** `a=T` to transmit the first time an image id is seen, `a=p` to re-place thereafter (`TerminalImageKittyRendering.swift:318, 361`). So with a repeating GIF, frames are retained by id in the terminal. First loop costs bytes; later loops only placement commands. **No `a=f` or `a=a`:** the comment at line 323 mentions the animation protocol, and no code uses it (grep across `Sources` and `Platforms`).
- **Sixel path:** no retained store, so **every frame is re-sent**, every tick. [V by protocol and `TerminalImageRendering`; the payload is cached in-process, not on the terminal.]
- **Cell-art path:** half-blocks or ASCII at 16, 256, truecolor, re-sampled per frame, cached, and written as ordinary cells.

### Could TUI? Yes

TUI's picture store retains by id, and placeholders are cells. Plan:

| Piece | How | Effort |
|---|---|---|
| View | TUI-specific `AnimatedImage` in `TUIBitmaps`, per the project rule for TUI-only APIs. SwiftUI's `Image` does not animate GIFs; no parity conflict. | 1 day |
| Timing | Use the animation scheduler, not `Task.sleep`, with the 60 Hz multiple rule. Round a frame's delay up to a multiple of 1/60 s. | 1 day |
| Decode | Below | 1–2 days |
| Kitty, placeholders | Transmit each frame under its own id, once; then rewrite placeholder cells to name the current id. **About 12 bytes a cell per tick** for a repair (`Terminal graphics protocols.md` §11.5). A 49×17 picture is about 10 KB per tick, against about 1.8 MB raw to send a frame the first time. | 2 days |
| Kitty, better | **Keep one placeholder id and change what it shows:** kitty's `a=a,c=N` sets the current frame, and the terminal stores frames with `a=f`. Then bytes per tick are ~30, or zero with a terminal-driven loop (`s=3`). Doc §5 says only "defer". | Measure first: which terminals implement it? WezTerm "animation absent" per §3.2. Ghostty is unmeasured here. 3 days |
| Glyph fallback | `ASCIIConverter` per frame, cached | Exists; only caching |
| Reduce motion | Your A-D3M-1 separates spatial motion from "breathing". Is a playing GIF motion? **I would stop it**: it is decorative. Ask. | |

### Format and decoder options

| Format | Apple | Linux, WASM | Notes |
|---|---|---|---|
| **GIF** | ImageIO `CGImageSourceGetCount` and the `kCGImagePropertyGIFDictionary` delays. Handles frame disposal. | **stb_image `stbi_load_gif_from_memory`, already vendored** in `Sources/CSTBImage/include/stb_image.h:433`. Returns composited frames and delays. | Easy everywhere, no new dependency |
| **APNG** | ImageIO: `kCGImagePropertyAPNGDelayTime`, `APNGFrameInfoArray`, in the SDK header [V] | stb reads only the default image. Options: a small APNG chunk reader (`acTL`, `fcTL`, `fdAT`) rebuilding PNGs for stb: 200 lines. | Medium |
| **WebP** | ImageIO: `kCGImagePropertyWebPDictionary`, macOS 11, in the SDK header [V]. Animated decode not tried here. | Needs `libwebp`, vendored C (`libwebpdemux`, several MB). Against your "no dependency" instincts. Or `dlopen` like `SystemZlib`. | Opportunistic `dlopen` fits the house pattern. |
| **HEIC sequences** | ImageIO | None | Apple only; fine as a free extra |
| Swift libraries | `tayloraswift/swift-png`, `swift-gif`, as SwiftTUI vendors | | Adds a package for what stb does already. No. |

**Recommendation [I]:** GIF on all platforms, using ImageIO on Apple and stb elsewhere, matching `ImageLoader.swift`'s existing split. APNG and WebP through ImageIO on Apple only, at first, and say so in docs. That is a natural `Image`-file parity: `WorkingWithImages.md:35` already says "on a Mac, so does anything else the system can read".

**What could go wrong.** Memory: 100 frames of 1000×1000 RGBA is 400 MB. Decode lazily or cap with `TUI_IMAGE_CACHE_SIZE`. stb composites frames eagerly. Terminal stores have quotas, kitty's defaults to 320 MB, and a long GIF may evict. Frames at 10 Hz wake the render loop, so idle CPU is non-zero when one plays: keep it to the view's lifetime, and stop when off-screen.

---

## 19. What SGR pixels buys over what TUI has

**Answer.** Finer dragging and hovering: at best 8–16× finer horizontally and about 16–34× vertically, on controls whose *drawing* already has that precision. In practice that is a slider, a scroll bar and curve-editor handles. It buys nothing for clicks on buttons, lists, tabs or text. It is a real but small gain; your earlier "not now" still seems right, until `Canvas` lands.

**Today in TUI.** `MouseEvent` has `x: Int, y: Int` cells [V: `TUICore/Input/MouseEvent.swift:106`]. `DragGesture.Value.location` is `CellPoint`, and `translation` is `CellSize`, integers. (SwiftUI's are `CGPoint`; a recorded deviation.)

**Which controls would benefit** [V for what they draw; I for benefit]

| Control | Drawing precision | Pointer today | With pixels |
|---|---|---|---|
| `Slider`, `Gauge`, progress tracks | Sub-cell ramp: `TrackRenderer` "A ramp of n glyphs gives n+1 sub-cell steps", typically 8 | Whole cell | A 20-cell slider goes from 20 to 160 reachable values by mouse. **The clearest win.** |
| Scroll bar thumb | Sub-cell glyphs if style has them; scroll position in rows | Whole cell | Smooth long-document dragging: one cell of thumb may be 200 rows, and pixels give finer. |
| `TUICurveEditors` handles | Half block or Braille | Whole cell | Dragging a curve point at dot precision. |
| `TUIColorPicker` field | Half blocks | Whole cell | One more colour per half row. |
| `Shape` hit tests, `contentShape` | Half-block coverage | Cell | Marginal |
| `HSplitView` dividers, tabs, buttons, lists, text selection | Whole cell | Whole cell | **Nothing.** A cell's the smallest thing they can do. |
| A future `Canvas`, sketching | Braille 2×4 | Cell | **Big**: drawing lines by hand. |
| Pictures | Kitty pixels | Cell | Crop handles, eyedropper |

**Terminal support.** iTerm2, Ghostty, kitty, foot, WezTerm, from each terminal's source (`Future options.md:320`, 2026-10-12). SwiftTUI's table adds xterm and xterm.js [V]. Not Apple Terminal or Warp, as far as anything here shows [I]. Under tmux, not at all, per SwiftTUI's own gating [V].

**TUI's recorded hazards** (`Future options.md:326-330`): 1006 and 1016 are one setting and the last set wins; TUI re-sends `?1006h` on every tracking-mode change, which would drop a 1016 session to cells; teardown needs `?1016l`; iTerm2 reports 1016 in points but its 2048 sizes in device pixels (2× apart on Retina), so cell size must come from elsewhere. **Good news:** `TerminalCellPoints.swift` already calibrates exactly this per host.

**Effort [I]:** 3–5 days. Add fractional fields to `MouseEvent` (additive), negotiate with DECRQM, fix re-sending, add `DragGesture.Value.preciseLocation` as a TUI extra, because the `CellPoint` API stays. Slider uses it. Measure in each terminal and update the survey (mandatory). **Risk:** a report arriving in pixels without the mode set is parsed as a far-away cell, hence a guard.

**Reopen trigger, as `Future options.md` already says:** "A feature that needs sub-cell pointer positions". That would be `Canvas`.

---

## 20. "Typed composition" of gestures

**Answer.** The earlier report's phrase was misleading. SwiftTUI has the same three combinators as SwiftUI and TUI, and is **less** typed on one of them. There's no advantage over TUI here.

| | SwiftUI | TUI | SwiftTUI |
|---|---|---|---|
| `simultaneously(with:)` | `SimultaneousGesture.Value` with optional `first`, `second` | Same [V] | Same [V] |
| `sequenced(before:)` | enum `.first(A)`, `.second(A, B?)` | Same [V: `CompositeGestures.swift:126-132`] | Same [V] |
| `exclusively(before:)` | enum `.first(A)`, `.second(B)` | Same [V: line 172-177] | **Requires `First.Value == Second.Value`, and `Value = First.Value`** [V: `ExclusiveGesture.swift:9-11`]. Cannot combine a `TapGesture` with a `DragGesture`. The enum is gone. |
| `map`, `updating`, `@GestureState`, `onEnded` | Yes | Yes | Yes |
| `GestureMask` | Yes | Yes | Yes |
| Behaviour source | | "each as measured on macOS 15.8" with many documented edge cases | Their own, with cell defaults |

"Typed" there means only: a composed gesture's value type is generic, which all three do.

**Worth stating.** TUI's are closer to SwiftUI's than SwiftTUI's, in signature and in measured behaviour. SwiftTUI's defaults differ too (`DragGesture.minimumDistance` 0, not 10) [V: gaps register].

---

## 21. `onScrollWheel`

**Answer.** It is not a SwiftUI API. `sdoc.py` finds no `onScrollWheel`, and SwiftUI's interface has only `onScrollGeometryChange`, `onScrollPhaseChange`, `onScrollVisibilityChange` and `onScrollTargetVisibilityChange` [V]. It offers one small thing over TUI: a "not mine" return that hands the wheel to an outer scroll view. TUI already has that in `.onMouseEvent`.

| | SwiftTUI `onScrollWheel` | TUI `onScrollGesture` | TUI `onMouseEvent` |
|---|---|---|---|
| Value | `ScrollWheelEvent(deltaX: Int, deltaY: Int)`, cells | `ScrollDirection` | `MouseEvent`, `.scrollUp` etc |
| Can decline | `.ignored` or `.handled` | No, always consumes [V: `View+Events.swift:205-218`] | Yes, returns Bool |
| Both axes | Yes | Yes, as four directions | Yes |
| Modifiers | Not in event | Not in the event | Yes |
| Coalesced | [I] Their runtime merges same-cell scrolls (`TerminalInputCoalescing.swift`) | One report per call | One per call |

Terminals send no delta, phase or velocity: `Terminal compatibility survey.md:6377` records it. So their `deltaX` and `deltaY` derive from counting reports, not from a trackpad's real amount [I from that record].

**Benefit [I]:** none significant. It's a slightly nicer spelling. TUI could give `onScrollGesture`'s closure a `Bool`-returning overload in an hour, so that a nested pane gives way at its edge, which is the use. SwiftTUI's own `TerminalView` uses it that way.

---

## 22. Geometry-aware traversal, `FocusContainment`, `focusScope`

**Answer.** Most of this was overrated. TUI already has SwiftUI's `focusScope(_:)`, `prefersDefaultFocus`, `resetFocus` and `focusSection`. The one thing SwiftTUI really does that TUI does not is **arrow keys that move by screen position**. That is useful in 2D layouts and has a real cost-benefit case. `FocusContainment` is a small extra.

### The three pieces

| Item | SwiftTUI [V] | TUI [V] | SwiftUI [V: sdoc] |
|---|---|---|---|
| **Tab order** | Top-most, nearest the leading edge first, by layout order; wraps | Render order (`focus-section-cycling-boundary` note), sections cycle at the ends | System order |
| **Arrow keys** | `FocusTracker.moveFocus(.right…)`: picks the nearest control **in that direction**: prefers same section, shared scope, overlap on the other axis, then distance | Down and Right are next, Up and Left previous, within the section, not wrapping. Exception: `NavigationSplitView` moves between columns | Mainly tvOS; arrow navigation differs per platform |
| **`focusSection()`** | Enlarges a movement target, as on tvOS | `focusSection(_ id: String? = nil)`: groups a region; Tab enters at an edge; arrows stay inside; a breathing ● on its border | tvOS and macOS: guides movement |
| **`focusScope(namespace)`** | Yes, with `prefersDefaultFocus`, `resetFocus` | **Yes** (`FocusScope.swift:45`) | Yes |
| **`focusScope()` no argument** | Scope boundary metadata, TUI-unknown spelling | No | No |
| **`FocusContainment`** | `Panel.focusContainment(.sealed)`: Tab skips the panel's contents. "A future design will add a drill-in mechanism" | No such API | No |
| **`onMoveCommand`** | | Yes | Yes |

### What it means in practice [I]

**Directional arrows matter where controls are on a grid.**
```
[ Save ] [ Cancel ]
[ Name.............. ]
```
From Save, Down in SwiftTUI goes to Name, directly below. In TUI, Down goes to the next in order, which is Cancel. Now two columns:
```
[ A ]   [ X ]
[ B ]   [ Y ]
```
From A, Right in SwiftTUI goes to X, and Down to B. In TUI, Down goes to B (order) and Right also goes to B. If `.focusSection` wraps each column, arrows stay inside, so Right never reaches X and Tab must be used. For a calendar, a keypad, a colour swatch grid, or a dashboard of panes, this is a visible difference. Text-based users of tools like `lazygit` expect it.

**`.sealed`:** Tab treats a card as one stop. Real but rare. There's no way in yet, by their own note. TUI can get close with `.focusable(false)`-style composition, or a section.

### Could TUI do it?

`hitTestRegions` carry positions and `focusID`s for the last frame [V]. A directional move at key time: find current region, score candidates like their function (about 60 lines, `FocusTracker.swift:367-430`). The manager falls back to it only "once the control has let the key go". **Effort: 2–3 days.** Project question: does it change defaults? Make "by position" the behaviour of `.focusSection` grids, or the global default? SwiftUI on macOS has no such arrow moves at all, so TUI already chose its own rule; a change does not break parity. **Risk:** repeated `first(where:)` confusion: a List emits two regions for one id (`reveal-two-targets`), so pick the whole-control region. Also regions under modal veils need excluding.

**Worth doing [I]:** yes, it is cheap and people notice it.

---

## 23. Browser ARIA

**Answer.** ARIA is the web's standard for telling assistive technology what a thing is: a role ("button"), a name, a state. Here it means SwiftTUI paints its cells on a canvas, and beside it builds an invisible tree of real HTML elements carrying those attributes, so VoiceOver, NVDA or JAWS can read and operate the app in a browser.

- **Why it's needed.** A `<canvas>` is a picture to a screen reader. Text and controls need real elements.
- **How.** Each frame's semantic nodes go down the host wire. `@swifttui/web` "mounts a real ARIA accessibility tree": reading order, names, roles, hidden state, announcements, focus. Links are real anchors; numeric controls have `aria-valuetext` [D: swift-tui-web README].
- **Actions come back.** Assistive activation, focus, adjustment and value edits become typed `accessibility:<token>:activate` records over the WebSocket, not fake keystrokes [V: `ST:docs/ACCESSIBILITY.md`].
- **Status.** "Bounded Safari/VoiceOver control journeys are qualified, while the complete assistive matrix remains open"; DOM renderer is experimental [D: gaps register].

**For TUI [I].** TUI's browser build uses xterm.js. xterm.js has its own screen-reader mode, which exposes rows as text. TUI's survey covers xterm.js, but I did not find that mode measured. It's a cheap thing to try: one option to `new Terminal({screenReaderMode: true})` in `Tools/Web`. It gets line reading, not roles.

---

## 24. "Native overlays" for assistive runtime

**Answer.** It's the same idea as browser ARIA, for native apps. Over the painted cell grid, the host places a transparent layer of real platform accessibility elements (`NSAccessibility` on macOS, `UIAccessibility` on iOS, Compose semantics on Android), so VoiceOver or TalkBack can find them.

| Host | Overlay | Direction, per their docs |
|---|---|---|
| macOS, iOS (`SwiftUIHost`) | AppKit/UIKit accessibility elements for roles, labels, hints, enabled state, runtime focus | **One-way.** "assistive-origin focus and control actions are not yet routed back into SwiftTUI" [D: README]. So VoiceOver can read it and not operate it. |
| Android (Compose) | "A transparent TalkBack semantics overlay" | Focus goes to TalkBack; TalkBack focus does not come back; provider actions exist; acceptance "has not passed" [D] |
| Browser | ARIA sidecar | Two-way for listed controls |

"Assistive runtime" in the earlier report just meant the set of things that serve those users at run time: reader, cursor mode, overlays.

**For TUI:** none. They need a native host. TUI has none, and I would not chase this. See question 3.

---

## 25. Cursor-follows-focus

**Answer.** Easy: about 2–4 days. And it makes more sense in TUI than the framing suggests, **precisely because of side-by-side views**: the cursor's column is the only signal a line-based screen reader, a braille window or a magnifier has for which pane you are in. It is the best value-for-effort accessibility item here. One condition: focus breathing must stop while it is on.

### What it does

The terminal's own hardware cursor is the one thing every assistive tool watches. Today TUI hides it for the entire run (`App.swift:441`, restored only at exit) and draws a synthetic caret in text fields. So nothing outside can tell where focus is, or where you are typing.

Cursor-follows-focus: after each frame, move the real cursor to the focused control, and show it.

**In SwiftTUI** [V: `RunLoop+Presentation.swift:93-110`, `AccessibilityRuntimePolicy.swift`]: `focusedCursorPoint` picks the focused node's `cursorAnchor` or its rectangle's origin. It writes `CUP` + `?25h`. Off by default; `--cursor-follows-focus` or `--accessible`. **Even with it off, a focused text input's caret shows the real cursor.** `.accessibilityCursorAnchor(_:)` lets a custom control choose. The synthetic caret is skipped when the cursor mode is on. Their docs warn: "Emits terminal bytes, not a semantic tree or spoken announcement. Reader compatibility requires testing."

### Why side-by-side makes it matter more [I, from how those tools work]

| Tool | One column of content | Two panes side by side |
|---|---|---|
| **Speakup, Orca, NVDA, TDSR** | Speaking the line tells you all you need | The line runs through both panes. Word-by-word and character review start at the cursor, so the cursor picks the pane. Without it, you cannot tell which half you're in. |
| **BRLTTY**, 40-cell display | Window shows the cursor's part | Window jumps to the column of the cursor. Without it, you read the left pane forever. |
| **Magnifier** (Zoom, GNOME's, Windows') | Follows the caret or insertion point where the terminal exposes one [I] | The viewport has to jump across. This is the case where it's essential. A magnified user cannot see the other half of the screen at all. |
| **Sighted, big terminal** | | Also a clear "where am I". |

So overlap is not the point; there are no overlapping windows. It's that a single row holds several independent things, and only a cursor column separates them. Your framing holds: "we certainly have side-by-side views all the time". The full-line reading will still mix panes, and that's what a reader mode is for.

The essay's praise for `menuconfig` is the single-column version of the same point [T].

### In TUI

| Step | Where | Effort |
|---|---|---|
| After a frame's write, look up the focused id's first hit-test region on the root buffer: that is already the row for `List` and `Table`, and the control otherwise (`ScrollViewReveal` relies on it) | `RenderLoop` after `FrameDiffWriter` | ½ day |
| Write `CUP` + `?25h` only if frame or focus changed. Wrap in sync output (mode 2026) with the frame, to avoid a visible hop. | `Terminal` | ½ day |
| Controls choose a better spot: text fields their caret, toggles their mark | `FocusRegistration` helper, plus a `.cursorAnchor(_:)` modifier, TUI-specific | 1 day |
| Text fields: skip the synthetic caret, use the real one. The real cursor at the caret should probably be **on by default** as SwiftTUI's is, given `TextCursorStyle` needs `DECSCUSR` handling. Owner's call: it changes the look. | `TextFieldContentRenderer` | 1 day |
| Environment: `TUI_CURSOR_FOLLOWS_FOCUS=1`, and `TUI_ACCESSIBLE=1` bundling it with "still" | As other `TUI_*` | ½ hour |
| Survey | Rule: measure per terminal, and record | ½ day |

**What could go wrong**
- **Focus breathing.** "One focus identity, in-palette, always breathes" (your `focus-selection-colour-rules`). Each breath is a write near the cursor: a VTE-based reader sees changed text and a cursor round trip. **So it must stop under this switch**, and A-D3M-1 says reduce motion does not stop it. Hence the "still" switch in question 1.
- **Other writers.** Any spinner or timer moves the cursor to write, then back. Sync output may hide that from the terminal's display, but I don't know if accessibility layers see the intermediate state [I]. Needs testing with one real reader.
- **Terminal.app and advance compensation.** `CUP` positions are absolute, so safe.
- **Cursor look.** A block cursor on a coloured focused row can obscure it. Use a bar shape via `DECSCUSR`, and restore it at exit, beside the `showCursor` TUI already owes (`Terminal.swift:1037`).
- **Memo.** It reads final-frame regions, so memos are fine.

---

## 27. Colour science

**Answer.** For rendering, no: on the question that shows on screen, mapping truecolour down to 256, TUI is better than SwiftTUI. SwiftTUI's public API has a lot TUI lacks, for colour *tools*. The one thing with real user value is its colour-blindness profile.

### What each has [V]

| | SwiftTUI | TUI |
|---|---|---|
| **Truecolour to 256** | **RGB distance**, cube against grey (`TerminalCellTextRenderer+ColorCodes.swift:107`) | **OKLab, hue-weighted**, with no grey for a colour that has hue (`Color+Downsampling.swift:392`). Plus a contrast-preserving ramp repair. |
| **To 16** | `deltaE` among slots, cached | `palette256ToANSI16` table; `.ansi` slots follow the user's palette |
| **Contrast** | `contrastRatio(to:)`, `accessibleTextColor(light:dark:)` | `contrastRatio`, `ensuringContrast`, `ensuringRenderedContrast`, which measures after the cube moves both colours. `labelContrastFloor`. Tested across 16 palettes. |
| **Blending space** | Linear sRGB for images, configurable working space, OKLab for animated colour | Encoded sRGB by decision (`Opacity as composition`) |
| **Gradients** | Perceptual options | OKLab internally; `Gradient`, `MeshGradient` |
| **Public `Color.oklab()`, `oklch()`, `lab()`, `lch()`, `xyz()`** | Yes | **No.** `oklab(red:green:blue:)` is `package`. HSL, HSB and CMYK are public. |
| **`deltaE(to:method:)`**: cie76, cie94, ciede2000, ok | Yes | No public one |
| **`isApproximatelyEqual`**, `isInGamut`, `mapped(to:)`, `GamutMappingPolicy` (clip, compress, colorimetric) | Yes | No |
| **Profiles**: Display P3 and more; `RGBColorProfile` struct, chromatic adaptation | Yes | sRGB only in storage, plus SwiftUI's `RGBColorSpace` init |
| **`Color.mix(with:by:in:)`** | `mixed(with:amount:method:)`, different name | **Yes, SwiftUI's name** |
| **`AccessibilityColorProfile`** protanopia, deuteranopia, tritanopia, monochrome | Yes. Remaps to Okabe-Ito-style palettes at raster time (`Theme.swift:227`) | **No.** `accessibilityDifferentiateWithoutColor` exists, and TUI's drawing does not act on it yet |

### Real uses for that API [I]

- **Colour tools and pickers**: showing OKLCH, gamut warnings. TUI's `ColorPicker` could use it internally already.
- **Theme generators**: derive shades with even perceived steps. TUI's palette derivation has this inside.
- **"Are these two colours distinguishable?"**: `deltaE` in a data-viz library or a charts package.
- **Display P3:** every terminal takes sRGB bytes. SwiftTUI itself converts to sRGB at output (`directColorBytes`). A P3 colour in a terminal is only a source format.
- **Lab, LCH, ciede2000:** niche. For a terminal UI framework, an API with this reach is more than most apps will touch.

### What TUI should take [I]

| Item | Why | Effort |
|---|---|---|
| **Colour-blind palettes**: `TUI_COLOR_PROFILE=deuteranopia` or built-in palettes | Real benefit: about 8% of men have a red-green deficiency. TUI's themes rely on hue for error, warning, success. With 17 palettes, adding a safe one is the simplest route. | 2–3 days for one palette; 1 week for a remap at resolve time |
| **Public `oklab()` and `oklch()`** on `Color`, and `deltaE(.ok)` | The internals exist. Cost: API surface, and it isn't SwiftUI's. Only if a charts or colour module needs it. | ½ day |
| Rest | Skip | |

**Don't:** switch your quantiser to theirs.

---

## 28. Path morphing

**Answer.** It's animating one `Path` into another by interpolating points. SwiftUI's `Path` does **not** do it: its `animatableData` is `EmptyAnimatableData` [V: sdoc]. In SwiftUI you morph by giving a custom `Shape` numeric `animatableData`. TUI matches that. TUI should not add path morphing as a default, because that'd make a SwiftUI program behave differently, though a small extra `interpolated` method is harmless.

**SwiftTUI** [V: `Shapes.md:129-142`, gaps register line 818]: `Path` conforms to `Animatable`. Two paths with **identical ordered element kinds** (move with move, line with line, quadratic, cubic, close) interpolate anchor and control points during an animation. If kinds differ, it snaps. `start.isInterpolable(to:)` and `start.interpolated(to:progress:)` are public. Changing an arc's sweep may change its segment count and so snap. It's useful when a custom shape's `path(in:)` returns similar paths for different states: no `animatableData` needed.

**TUI** [V]: `RoundedRectangle`, `RotatedShape`, `ScaledShape`, `OffsetShape` and others have `animatableData`, the SwiftUI way. A custom `Shape` with `animatableData` animates. `Path` has none of its own. I did not run this.

**Should TUI have it? [I]**
- **Automatic morph:** No. A SwiftUI program where a shape's path changes jumps at once; on TUI it'd glide. Your rule ("change only if a SwiftUI program would misbehave") argues against: it'd be a difference for no parity reason, and not harmful either, so it isn't important.
- **A method:** `Path.interpolated(to:progress:)` as a TUI extra is 30 lines and enables custom morphs in `animatableData`. Reasonable if someone asks.
- **In a cell world:** half-block resolution of 2 rows per cell makes the visual benefit small for small shapes. Low priority.

---

## 29. `RenderOnce`, `renderOnce`, and "stable output"

**Answer.** TUI has an equivalent: `renderOnce { … }`, which now prints at the cursor and writes plain text to pipes, since this weekend's change closed most of the gap. "Stable output" in SwiftTUI is unrelated to one-shot rendering: it means built-in animation is frozen, for capture.

| | SwiftTUI `RenderOnce` [V: `Platforms/CLI/.../RenderOnce.swift`] | TUI `renderOnce` [V] |
|---|---|---|
| Call | `RenderOnce.print(view, width:, options:, environment:, isStdoutTTY:)`, `RenderOnce.render(...) -> String` | `renderOnce(output:) { view }` |
| Returns a string | **Yes** | No: it writes |
| Position | Prints where the cursor is; `\n` line ends | From the cursor line; ends with a newline |
| Height | Natural extent, up to 65,536 cells and 1,048,576 total | Asks for the height it wants |
| Width | Live width, `$COLUMNS`, 80; or a parameter | Terminal's; piped: `COLUMNS`, or 80 |
| To a pipe | No TTY means no colour and no styling, so plain text | **Plain text, no trailing spaces** |
| Control | `options:` flags; env dictionary as a parameter, good for tests | `.automatic`, `.plainText`, `.escapeSequences`; `TUI_FORCE_ESCAPES`, `FORCE_COLOR`, `NO_COLOR` |
| `NO_COLOR` | Removes all styling | Keeps bold, as no-color.org asks. **Better.** |
| `TERM=dumb` | No styling, no hyperlinks, no mouse | Plain |
| `onAppear`, `.task` | Do not run | Do not run |

**Gaps left [I]:** a string-returning variant, useful for tests and for embedding in a larger output; a `width:` parameter. Both trivial. `TestApp.screen.text` covers tests.

**What "stable output" means** [V: `RuntimePolicyEnvironment.swift:48-56`, gaps register line 1006, `Testing-Your-App.md`]: a runtime policy, `--stable-output` or `SWIFTTUI_STABLE_OUTPUT=1`, on by itself when `CI` is set or stdout is not a TTY. It sets `renderingReduceMotion`, so built-in animated views take their static form, while `accessibilityReduceMotion`, which apps read, stays false. So "stable" means no time-based visual change from the framework. It does **not** mean byte-for-byte stable across terminals or runs; for that they also advise pinning `NO_COLOR`, `LANG` and `width`.

---

## 33. Testing affordances beyond `TUITesting`

**Answer.** `TUITesting` is already the stronger tool for testing interactions. SwiftTUI's own doc says its in-process renderer is "not an interaction tool", and it sends you to a PTY for that. What's worth taking: asking what colour a cell is, a real-terminal smoke helper, and, later, semantic assertions.

### What each offers [V: `ST:Sources/SwiftTUI/SwiftTUI.docc/Testing-Your-App.md`; TUI: `Sources/TUITesting`, `TestingYourApp.md`]

| Need | TUITesting | SwiftTUI |
|---|---|---|
| Press keys, type, paste | `app.press`, `app.type`, in-process | PTY bytes only |
| Click by text, scroll, drag, hover | Yes | PTY bytes |
| Frozen clock, advance animation exactly | `app.advance(by:)` | No; `SWIFTTUI_STABLE_OUTPUT` freezes, and PTY tests wait in real time |
| Fake clock for app tasks | `TestClock` | No |
| Wait for text or condition | `app.wait(for:)` | `waitForANSIVisibleScreen` on real fds |
| Read focused id | `app.focusedID` | No |
| Stored snapshots | `compareToSnapshot`, `TUI_RECORD_SNAPSHOTS=1` | Do it yourself |
| Run the whole `App` | `TestApp(MyApp())` | PTY |
| Isolated `@AppStorage` | Yes | n/a |
| One-frame string, no runtime | Same effect | `RenderOnce.render` |
| **Per-cell style** | **No.** "TUI has no API for asking what colour a cell is." Compare `styledLines`. | **`rasterSurface.lines` and `styleRuns`, from `DefaultRenderer`** |
| **Real terminal bytes, real PTY** | **No.** "It doesn't check what a terminal does with the output." | **`RealTerminalPTYPair`, `ANSIVisibleScreen`** |
| **Style fixtures** | Test through a control in `TestApp` | `@_spi(StyleFixtures)`: construct a style configuration directly: focused, disabled, pressed |
| **Accessibility output** | No (no tree) | `renderLinearAccessibilityOutput` |
| **Runtime-progress budgets** | `wait` has a long timeout | `StageClock`, `withStageBudget`, `AsyncEvent`, `ConditionSignal`: bound waits by progress, not wall clock |

All of `SwiftTUITestSupport` is `@_spi(Testing)` and "expect it to move faster" [D]. So it isn't a stable product.

### Which would significantly benefit TUI [I]

1. **`TestScreen` cell attributes.** `screen.style(at:)` giving foreground, background, bold, inverse, by reading `styledLines` the way the opacity and veil code already reads SGR. Most tests of "is it highlighted", "is it disabled", "is the row red" need it. **High value, 1–2 days.** Their state-independent resolved style has no equivalent in TUI, so parse.
2. **A real-terminal smoke helper.** `TestTerminal.run(executable:)`: PTY, send keys, read a VT-modelled screen, check it restores on exit. TUI's Python tools do this for itself; a user has nothing. Catches startup, raw mode, "quits cleanly", and bytes actually written. **Medium value, about 1 week**, needing a small Swift VT parser. If question 36's emulator is adopted, reuse it.
3. **Semantic assertions.** Only after question 2's stage D.
4. **Style fixtures.** Skip. SwiftUI configurations aren't constructible, and `TestApp` tests a style through a control.
5. **Progress-budget waits.** TUI's internal `timed-wake` and `plateau` notes suggest value for the test suite, not for app authors.

And the converse, for your docs: nothing in SwiftTUI's testing beats `TestApp` for interaction, and the page should say what it does, once landed.

---

## 34. `_printChanges`, `_logChanges`, `--debug`, runtime issues, `SWIFTTUI_PROFILE`, frame sink

**Answer.** `_printChanges` is a real SwiftUI API (`_logChanges` too): public, underscored, and missing from TUI. TUI has good tools of other kinds, but none answers "why did this body run?", none gathers everything in one place, and no profiling ships for app authors. `_printChanges` is the one to add: 3–5 days, a compile-as-is gain.

**Is it SwiftUI?** Yes [V: `MacOSX.sdk/.../SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface:5851-5859`, `SwiftUICore` at 14992]: `View._printChanges()` and `ViewModifier._printChanges()` since macOS 12; `_logChanges()` since 14.1. `sdoc.py` shows nothing since symbol graphs skip underscored names, so **TUI's parity tool cannot see them** [I]. TUI has none, and code using them fails to compile. It's common in SwiftUI debugging: Apple's own WWDC 2023 session is cited in `Historical/State and dynamic properties/The update model`.

### How SwiftTUI's work [V: `Logging-And-Diagnostics.md`, `Sources/SwiftTUIRuntime/Diagnostics/`, `Sources/SwiftTUIProfiling/`]

| Feature | What it does |
|---|---|
| `Self._printChanges()` in a `body` | Writes why this evaluation happened: `@identity` at first, an exact `state` cause naming `_count`, `@self` on a trusted input change, environment reads, observation by owner only. No values. Bounded at 8 KiB, 64 causes, 4,096 bodies. Debug framework only. |
| `Self._logChanges()` | The same as JSONL, or to the unified log: subsystem `sh.swifttui`, category `Changed Body Properties` |
| `--debug`, `SWIFTTUI_DEBUG=1`, `SWIFTTUI_DEBUG_DIR` | A **debug bundle**: one directory with `manifest.txt`, `frames.tsv`, `diagnostics.tsv`, `memo.log`, `reuse.log`, `inval.log`, `soundness.log`, `profile.tsv`, `runtime-issues.log`, `changes.log`. Printed path at exit. |
| `SWIFTTUI_TRACE` | Names which internal streams to arm. |
| **Runtime issues** | `RuntimeIssue` with severity, stable code such as `forEach.staleElementBindingWrite`, optional path and source. Public `RuntimeIssueSink`, so apps can report through it. Deduplicated per session. Routed safely: bundle, or stderr if not the owned terminal, or a bounded buffer flushed at exit. |
| `.profiling()` scene modifier, `SWIFTTUI_PROFILE="frames,memory@1s;tsv=/tmp/run.tsv"` | A separate product. Signals: frames, memory, CPU. Sinks: TSV, JSONL, summary. A no-op unless set. |
| Frame diagnostics sink | `@_spi(Runners) FrameDiagnosticSink`: `record(_ sample: RuntimeFrameSample)` for each committed, cancelled or dropped frame. What the profiling product consumes. |

### TUI's equivalents [V]

| Need | TUI | Verdict |
|---|---|---|
| Why did this body run? | **None** | Gap |
| State written during a body | `TUI_DIAGNOSE_BODY_MUTATION=1`, with subtree name; also effect-driven re-walks | **TUI has this, and it's good**; SwiftTUI's runtime issues differ |
| Is the memo stale? | `TUI_VERIFY_RENDER_MEMO=path`, `TUI_VERIFY_MEASURE_MEMO=path` re-render and compare | Comparable to their soundness oracles; better documented for app authors (`RenderCycle.md:872`) |
| Cache stats per frame | `TUI_DEBUG_RENDER=1` | Yes |
| See the frame | `TUI_DEBUG_FRAME_DUMP=1`, backtick dumps a frame | Different. No exact equal in theirs. |
| Focus trace | `TUI_DEBUG_FOCUS=1`, `/tmp/tuikit-debug.log` (`TUIFoundation/TUI.swift:40`) | Yes. **The path still says `tuikit`.** |
| Misuse messages | `SoftTrap`, `SoftTrap.warn`, once per message, held until the terminal is restored, or `TUI_DIAGNOSTICS_FILE` | Same idea. **Not public**: `package`, no stable code, no sink for apps or hosts |
| One-stop capture | `TUI_DIAGNOSTICS_FILE` is one file for reports; others go to stderr or `/tmp` | Partial |
| Live view in a second terminal | `TUI_DEBUG_RENDER` and the body-mutation report write to stderr, so `2>/dev/ttysNNN` works for them. `SoftTrap` reports are held until exit unless `TUI_DIAGNOSTICS_FILE` is set. Not documented as a workflow. | Partial |
| Frames, memory, CPU for app authors | `Tools/Profiling` (Instruments), `Stress`, `TUIBenchmarks`: for framework developers | Gap |

### What it would take in TUI [I]

| Item | How | Effort |
|---|---|---|
| **`_printChanges`, `_logChanges`** | Add static methods with SwiftUI's signature on `View` and `ViewModifier`. In debug, `renderToBuffer` publishes the current identity; at the call, compare with what's stored for it: value hash (`ValueHashPlans` exist), which `StateBox`es were written since (each write already invalidates through `RenderCache`), observation tracker fired. Print to `DiagnosticChannel`. Release: empty. TUI walks the whole tree, so "skipped" means memo hit; those print nothing, as in SwiftUI. | 3–5 days |
| **Add to parity check** | Tell `Tools/APIParity` to read underscored names from the interface, or list these by hand. Others may hide there too. | ½ day |
| **Debug bundle** `TUI_DEBUG_DIR` | One directory: route `DiagnosticChannel`, focus log, render log, manifest | 1–2 days |
| **Public `RuntimeIssue`** | Promote `SoftTrap.warn`, stable codes | 2 days, plus names for what exists |
| **`TUI_PROFILE`** | A frame record (time, bytes written, memo hits) to TSV from `RenderLoop`. Keep it in a separate product if it grows. | 3–5 days |

**Risks:** small. `_printChanges` in release must compile to nothing. A hash cause is approximate, so label it. Keep your rule: no framework code on the hot path when off.

---

## 35. Scene attach

**Answer.** A running app can have several scenes, and from another terminal `myapp attach <scene>` shows one of them there, live, in the same process with the same state. It's like a tmux pane that the app itself provides. It's POSIX only, and I expect few people need it.

**The commands** [V: `Platforms/CLI/Sources/SwiftTUITerminalCLI/RunnerCLI.swift`]: `myapp instances`, `myapp scenes [--pid|--instance]`, `myapp attach <id> [--pid|--instance]`, and `myapp --instance NAME` to name a run.

**How it's built** [V: `Platforms/CLI/Sources/SwiftTUICLIAttach/`, 986 lines, plus `Sources/SwiftTUIRuntime/Scenes/SharedScene*.swift`]
1. **One scene is primary** and draws on your terminal. Every other `WindowGroup` runs its own run loop and graph, drawing to a **pseudo-terminal the app opens for itself** (`ScenePty`), with no one watching.
2. **Discovery.** Each running app binds a Unix socket at `/tmp/swifttui/<app>/<id>.sock`, chmod 600. A line protocol answers `SCENES`, `ATTACH <id>`.
3. **Attach.** The second process asks the socket, gets the PTY slave path, sets its own terminal raw, copies window size, and shuttles bytes between its stdin/stdout and the PTY (`AttachProxy`). It relays `SIGWINCH`.
4. **Detaching** leaves the scene running, and state is retained. `hasAttachedClient` polls for hangup on the PTY.
5. **In the browser,** the companion shows the same scenes in a selector.

**Who wants it [I]:** dashboards with a second monitor's terminal: main UI here, logs there. A dev tool whose inspector opens in a second pane or a second tmux window. Multi-monitor users. It doesn't survive the app restarting, and it isn't a daemon. For most apps, a tmux split with two processes is similar, except for shared state.

**In TUI.** TUI's `Window`s share one surface, by design (`Windows - several scenes on one surface.md`), with a policy for which shows. Attach would need one render loop per terminal: `TUIContext` per app, `Terminal`, focus and so on are instanced, so that's possible, but `NotificationService.current`, `StorageDefaults.backend` statics are per process, which fits one app, two views. **Effort L, 3–4 weeks.** I wouldn't [I]; owner may disagree if a multi-terminal app appeals.

---

## 36. What `TerminalView` would take in TUI

**Answer.** It needs real terminal emulation. It can't be a pass-through, because a child program's output is a stream of commands for moving a cursor around a screen, and only an interpreter can turn that into a grid of cells that fits in part of your layout. With SwiftTerm, about 2–4 weeks for a good first version, as a separate module.

### Why not a pass-through? [I, plain reasoning]

Say a child runs in an 80×24 pane at column 40, row 5. It writes `ESC[H`, "go to row 1, column 1". Passed through, that writes on the **whole screen's** corner, over your UI. So would `ESC[2J` (clear screen), scrolling at the bottom row, `ESC[?1049h` (alternate screen), `ESC[?25l`, colour left on, mouse modes, a resize query. There's no way to give a child a window onto a terminal. tmux, screen, and every IDE's terminal all interpret the stream into their own grid, then draw that. Also: TUI's frame is rebuilt every frame and diffed. It needs the child's state *as cells* to draw any frame, clip it, overlay a menu on it, and it needs to know what's there without asking the child.

So: **PTY → bytes → VT parser → screen model (cells, attributes, cursor, scrollback, modes) → read a snapshot → draw into a `FrameBuffer`.**

### The pieces

| Piece | What | How in TUI | Effort |
|---|---|---|---|
| **PTY** | `forkpty`/`posix_openpt`, exec, `TIOCSWINSZ`, `SIGCHLD`, read loop | New; POSIX-only, so its own module per project rules, and never in the four Windows-building modules. SwiftTerm also has `LocalProcess`/`Pty`. | 2 days |
| **Emulator** | Parser, screen buffers, scrollback, wide chars, reflow, SGR, modes | **SwiftTerm** (below), or write one (no) | 1 day to adopt |
| **Compositing** | Each snapshot row becomes one ANSI string, for `FrameBuffer(lines:)`. `_TerminalCore: Renderable`. | Walk cells, emit SGR by run, keep widths. **Your rule "cells not characters" applies**, and SwiftTerm's width tables differ from TUI's and the host's. A mismatch breaks a row. Decide: trust TUI's `displayWidth`, and pad. | 3–4 days |
| **Colour** | Child's 16 colours should map to the host's, `.ansi` slot to slot; 256 and RGB pass on; depth caps apply | `Color` already has `.ansi`, `.palette256`, `.rgb` | 1 day |
| **Keyboard** | Focused pane encodes `KeyEvent` to bytes. App-cursor mode, bracketed paste, modifiers, Kitty if child asks. TUI gets rich key events and must re-encode. Host keys vs child keys: a `keyRouting` hook is a must. | New, plus `onKeyPress` | 3–4 days |
| **Mouse** | Translate to pane-relative, re-encode in the child's chosen mode (SGR, X10…). Only if child asked. Otherwise selection, wheel = scrollback. | `TUIFoundation` mouse dispatch | 2–3 days |
| **Resize** | Layout gives a size → `terminal.resize` + `TIOCSWINSZ` → child redraws. Not during measure. | `onGeometryChange`-like, with `!isMeasuring` gate (your bug class) | 1–2 days |
| **Waking** | Output arrives off-main; coalesce to frames (16 ms) and invalidate. | The render loop's wake plumbing exists | 1–2 days |
| **Memo** | Must not memo stale. Generation number on the snapshot goes in the value. | | ½ day |
| **Selection, copy, scrollback UI** | TUI has `SelectingText` machinery for frames | Hook in | 3 days |
| **Replies** | Child asks `DA1`, `CPR`, colour queries. Emulator answers, must not reach the real terminal. | SwiftTerm does this | ½ day |
| **Graphics inside** | Kitty and Sixel from the child | Skip at first. SwiftTUI added them later with `TerminalGraphicsStore`. | later |
| **Accessibility** | Frozen review etc | After question 2's stage D | later |

**Total about 2–4 weeks** for shell, vim, htop, less working, without graphics. **Testing** is real: vim, tmux inside, `top`, unicode, resize storms. Your PTY harness and survey help.

### SwiftTerm [V: cloned today]

- **Licence: MIT**, by Miguel de Icaza; also carries xterm.js's MIT notice. Fine.
- **Size:** about 38,000 lines in `Sources/SwiftTerm`. Very active: last commit 2026-10-31.
- **Tools version 6.2**, so it matches TUI's floor. **Linux works**: `platformExcludes = ["Apple","Mac","iOS"]` on Linux and Windows. Has `Embedded` and `Wasm` traits. Has a build plugin (`SwiftTermBuildInfoPlugin`). Depends on `swift-png` for portable graphics behind a trait.
- **Fit.** SwiftTerm's `Terminal` is a headless class with a delegate. SwiftTUI's wrapper `TerminalEmulator` is 635 lines, an `actor`, and it had to add a `TerminalBackendSequenceFilter` (rewriting SGR sequences SwiftTerm mishandles) and `TerminalControlFramer` to intercept OSC, APC and DCS. So expect some of that work [V].
- **Dependency cost.** Put it in its own product, like `TUIMacros` with swift-syntax. Every client *resolves* it, not builds it: consider a separate package, `TUITerminalView`, exactly as SwiftTUI did. That keeps it out of `Package.resolved` for everyone. Recommended.

### Alternatives

| Option | Comment |
|---|---|
| Write an emulator | Months for correctness. No. |
| libghostty-vt | Zig, C API. Good correctness; a build dependency. Survey-level interest only [I]. |
| Trim: "log pane" | Show a child's plain line output in a `ScrollView`, with SGR parsed, no cursor control. **A far smaller feature: 2–3 days**, and for a build log it's what people want. Worth doing even if the real one isn't. |

**What could go wrong.** Width disagreement is the top risk; TUI's measured approach is deeper than SwiftTerm's. Performance: `yes` in a pane produces gigabytes; SwiftTUI's reader isn't bounded by the snapshot rate. Keys TUI's own chrome takes, such as the quit key. Terminal-in-terminal is a nesting of quirks.

---

## 37. Toasts

**Answer.** The earlier report was wrong to list "toast" among things TUI lacks. TUI has an equivalent: `NotificationService` with `.notificationHost()`, and its docs call them "toast-style". The two differ in API: SwiftTUI's is declarative, with a binding, four tones and custom content; TUI's is imperative and text-only. A SwiftUI-free gap remains: no tone, no custom view.

| | SwiftTUI [V: `Presentation/ToastPresentation.swift`] | TUI [V: `TUIChrome/Notification/`, 728 lines] |
|---|---|---|
| **Call** | `.toast("Saved", isPresented: $show, style: .success, duration: 3, onDismiss:)`, or with `@ViewBuilder` content | `NotificationService.current.post("Saved!", duration: 2.0)` from anywhere; `@Environment(\.notificationService)` |
| **Host** | The modifier | `.notificationHost(width: 40)` once at the root. Only `Example` in the repo calls it. **Forget it, and nothing shows.** |
| **Model** | Declarative, a binding | Fire and forget, from any thread |
| **Survives navigation** | Tied to the view holding the modifier | **Yes, independent of the poster** |
| **Tone** | `info`, `success`, `warning`, `danger`, custom `ToastStyle` | None |
| **Content** | Text or any view | `LocalizedStringKey` or `String` |
| **Position** | Bottom-leading stack | Always top-right (`notificationOffset`) |
| **Duration** | Seconds; `nil` until dismissed | Seconds; fades 0.2 s in, 0.3 s out |
| **Input** | Never takes focus or blocks | Same |
| **Localised** | No | **Yes** |
| **Sticky** | Yes, `nil` duration | No |
| **Dismiss by code** | Clear binding | `clear()` is internal |
| **Style protocol** | Yes | No |
| **Desktop notification** | Separate | Separate: OSC 9, `TUI_NOTIFICATIONS`, with a per-terminal table |
| **Screen reader** | Role `.status`, polite live region, a named Dismiss action (`ToastPresentation.swift:840-843`) | No |

Neither is a SwiftUI API: SwiftUI has no toast. Note `NotificationService.current` is one of your three granted statics (A-APPSTATE-2).

**If you want to close the differences [I]:** add `style:` (`.info/.success/.warning/.error`) to `post`, and `duration: nil`. About a day. A view-builder `.toast(isPresented:)` beside it for those coming from SwiftUI toast libraries is another 1–2 days. **Worth saying in the first report's table:** the §6 row was right ("Notification service, not `toast`"), and §12 item 13 was wrong.

---

## Corrections to the earlier report (the first report)

| Where | It said | Actually |
|---|---|---|
| §9, "Plain options" | "`NO_COLOR` read [V: `ColorDepth.swift`]" | Not read anywhere on `main` |
| §2 row 8 and §7 | "typed composition" as an extra | SwiftTUI has the same set; its `exclusively` is narrower |
| §7 | `focusScope` as a SwiftTUI item | TUI has it, with SwiftUI's signature |
| §12 item 13 | toast among what TUI "lacks entirely" | TUI has `NotificationService` |
| §7 | "`Scroll wheel`: also public `onScrollWheel`" | Not SwiftUI; TUI has `onMouseEvent`, with the same hand-off |
| §11 | "TUI's `renderOnce`… overwrites the screen (not rechecked)" | True on `main`; a lane fixes it |
| §8, "Colour science" | TUI: "encoded sRGB blending" | Understates TUI: it has OKLab internally, with a better 256 mapping than SwiftTUI's |
