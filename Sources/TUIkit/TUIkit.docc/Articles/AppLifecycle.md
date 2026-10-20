# App Lifecycle

Understand how a TUIkit application starts, runs, and shuts down.

## Overview

A TUIkit application follows a linear lifecycle: **launch → setup → main loop → cleanup**. The framework handles terminal configuration, signal handling, and the render-input cycle so you can focus on building views.

## Entry Point

Every TUIkit application starts with a type conforming to ``App``, annotated with `@main`:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello, TUIkit!")
        }
    }
}
```

The `@main` attribute tells Swift to call the static `main()` method provided by the ``App`` protocol. This method:

1. Creates an instance of your app via its parameterless `init()`
2. Creates an internal `AppRunner` that owns all subsystems
3. Calls `run()` to enter the main loop

```
@main → App.main() → Self() → AppRunner(app:) → run()
```

## Subsystem Initialization

`AppRunner.init()` creates and wires the core subsystems: Terminal, AppState, StatusBarState, FocusManager, TUIContext (containing LifecycleManager, KeyEventDispatcher, PreferenceStorage, StateStorage, and RenderCache, and holding the AppState, which is the app's own — there is no process-wide one), and two ThemeManagers (palette and appearance). `run()` then creates the remaining runtime components: InputHandler, RenderLoop, and CursorTimer (50 ms) — the one animation timer, behind two clocks: the focus-relative one the cursor's blink and every focus indicator's breath read, and the monotonic one every spinner and indeterminate bar reads.

@Image(source: "lifecycle-subsystem-init.svg", alt: "Diagram showing subsystem initialization: @main calls App.main(), which creates the app instance via Self(), then AppRunner.init() creates Terminal, AppState, StatusBarState, WindowChromeState, FocusManager, TUIContext with 5 children (LifecycleManager, KeyEventDispatcher, PreferenceStorage, StateStorage, RenderCache), and two ThemeManagers.")

@Image(source: "lifecycle-run-creates.svg", alt: "Diagram showing run() creating InputHandler, RenderLoop, and CursorTimer (50ms).")

The `AppRunner` is the sole owner of all subsystems. Dependencies flow through constructor injection and ``RenderContext``.

## Terminal Setup

Before the main loop starts, `run()` prepares the terminal:

| Step | What | Why |
|------|------|-----|
| 1 | Arm the signal sources | Observe SIGINT and SIGTERM (`kill`), resize (SIGWINCH) and job control (SIGTSTP / SIGCONT), and ignore SIGPIPE |
| 2 | Enter alternate screen | Preserve the user's existing terminal content |
| 3 | Hide cursor | Avoid cursor flicker during rendering |
| 4 | Enable raw mode | Disable line buffering and echo, and every signal character but the quit key, ⌃\\ |
| 4a | Ask about the kitty keyboard protocol | Where the terminal speaks it, push its flags, so key releases, repeats, modifier keys alone, Caps Lock and the keypad are reported (``EnvironmentValues/keyboardReporting``); one round trip where it does not |
| 5 | Register state observer | `AppState` changes set `appState.needsRender` and `wake()` the loop |
| 6 | Register focus observer | Focus changes restart the breath (so the newly focused control is at its brightest) and trigger re-renders |
| 7 | Prepare the animation clock | CursorTimer (50 ms), started on demand only while a rendered frame consumes it |
| 8 | Render first frame | Show the initial UI immediately |

### Raw Mode

In raw mode, the terminal delivers every keystroke immediately without waiting for Enter. TUIkit configures:

- **No echo**: typed characters are not displayed
- **No canonical mode**: input is byte-by-byte, not line-by-line
- **Every signal character off but the quit key**: ⌃C and ⌃Z arrive as keys, not as SIGINT and SIGTSTP. Nothing binds ⌃C unless the app does; ⌃Z is the app's undo by default, and suspends the app from Layer 4 where the app's undo keys leave it out (`Scene.undoShortcuts(_:)`). Signals themselves stay on, as the user had them, for the one character left: the user's quit key, ⌃\\, which the driver still turns into `SIGQUIT` (see the key table below)
- **Non-blocking reads**: input is drained without blocking; when nothing is pending the loop sleeps until woken rather than polling on a fixed timeout (see Main Loop)

The original terminal settings are saved and restored during cleanup.

## Main Loop

`AppRunner.run()` is `async` and **demand-driven**, not a fixed-rate poll. With nothing pending and nothing animating, the loop blocks in `await stdinArrival.waitForArrival(...)` until it is woken — by terminal input, a render request, or a signal (SIGWINCH / SIGINT / SIGTERM / SIGTSTP / SIGCONT arrive via libdispatch signal sources, whose main-queue handlers wake the loop) — so a static screen renders zero frames and uses no CPU. One wake draws nothing: while a view's `.terminalProgress(_:)` bar is up on a terminal that draws one, the loop wakes every five seconds to send it to the terminal again, because a terminal may take a bar no program has updated for a while for one left behind, and goes back to sleep without a frame (not under tmux, which keeps the bar itself). When work is pending it renders at most once per frame interval (`App.maxFrameRate`, default 60 FPS), coalescing a burst of requests into a single frame. Deciding *when* a frame is due is `FramePacer`'s whole job: it holds the cap, whether a frame is owed, and the soonest instant any live animation grid next fires, and folds them into one target for the loop to wait on — so a frame owed at an instant the cap could not serve is rendered as soon as the cap clears rather than dropped, and the loop waits once per render rather than waking to find nothing due. The wait is a real suspension point, so it releases the main actor and lets `Task`, `MainActor.run`, and `DispatchQueue.main` work run between frames. The loop runs until shutdown:

@Image(source: "lifecycle-main-loop.svg", alt: "Flowchart of the main loop: run() performs terminal setup, registers observers, prepares timers, renders the first frame, then loops checking shouldShutdown, consuming the resize flag to invalidate the diff cache, rendering at most once per frame interval when a render is pending, draining key and mouse events and dispatching them, and otherwise blocking until woken by input, a render request, or a signal. On shouldShutdown, cleanup restores the terminal and exits.")

### Re-render Triggers

Several sources cause a new frame to be rendered. Each sets state the loop checks and `wake()`s the loop if it is currently idle-blocked:

| Trigger | Path | Main loop check |
|---------|------|-----------------|
| SIGWINCH | Dispatch signal source sets the resize flag + wakes the loop | `consumeResizeFlag()` |
| @State mutation | `AppState.setNeedsRender()` sets the flag; observer wakes the loop | `appState.needsRender` |
| CursorTimer (while active) | Calls `appState.setNeedsAnimationTick(_:)`, naming the clock | `consumePendingAnimationClocks()` |
| Focus change | Calls `appState.setNeedsRender()` | `appState.needsRender` |

A clock tick is the one that is not simply a render request. It records which
clock ticked, and the loop first tries to serve it from the frame already on
screen — see <doc:RenderCycle> — rendering only when some view would build a
different picture from the new phase.

The rest set boolean flags and wake the loop; the actual rendering always happens in the main loop — a signal source's handler never renders directly.

## Signal Handling

`SignalManager` arms five libdispatch signal sources, and changes a sixth signal's disposition without watching it at all:

| Signal | Trigger | Effect |
|--------|---------|--------|
| `SIGINT` | `kill -INT` (in raw mode ⌃C is a key, not this signal) | Sets a shutdown flag → main loop exits |
| `SIGTERM` | `kill` | The same shutdown flag, so the terminal-restore teardown still runs |
| `SIGWINCH` | Terminal resize | Sets a re-render flag → next iteration re-renders |
| `SIGTSTP` | ⌃Z, re-raised by Layer 4 when no view claimed the key and the app's undo keys do not include it, or `kill -TSTP` | Sets a suspend flag. The default stop action is suppressed on purpose: stopping the moment the signal lands would strand the user's shell in raw mode on the alternate screen, so the loop hands the terminal back and only then stops for real |
| `SIGCONT` | `fg`, after an *external* `SIGSTOP` | Sets a repaint flag — nothing was torn down, but the screen may have been disturbed while the process slept. The suspend path's own `fg` is swallowed instead, so it does not repaint twice |
| `SIGPIPE` | A clipboard helper or a pty reader that went away mid-write | No source at all: `SIG_IGN`, process-wide. Nothing wants to *observe* it, only to survive it, so the write returns `EPIPE` instead of killing the app mid-raw-mode |

These are not C signal handlers, and that is the point: libdispatch delivers each signal as an ordinary queued event on the main queue, so each handler is normal main-actor code that sets a plain stored property and wakes the loop. No async-signal-safe restriction, no self-pipe, and no `nonisolated(unsafe)` flags to read torn. The main loop drains the flags each iteration and acts accordingly.

The signals that end the process with nothing run on the way out are the exception, because a queued event would never be read: a crash (`SIGSEGV`, `SIGABRT` and the rest), the terminations nothing handles (`SIGHUP`, `SIGUSR1`, …), and `SIGQUIT` — ⌃\\, which the terminal driver raises even while the main thread is stuck, unless the app binds it (see the key table). `FatalSignalTerminalRestore` takes them with a C handler that writes what the terminal is owed from a buffer filled in advance, puts the shell's termios back, and lets the signal do what it does. A crash leaves the alternate screen up, with its report on it. `SIGQUIT` (⌃\\, or `kill -QUIT`) is the user's quit, not a crash: it leaves the terminal as a quit does — the images the app put in it deleted, the alternate screen left, the cursor shown, every mode off — and ends by its default action, the shell's `Quit: 3`, without the Swift runtime's crash report. It runs nothing else of `cleanup()` (below): no focus is lost; a setting stored a moment before — persistence saves asynchronously — can go with the process, since a flush is no async-signal-safe call; and under tmux the client hooks stay installed until their next firing removes them, as after a crash (removing them forks tmux). Where ⌃\\ arrives as a kitty keyboard protocol report, which the input chain reads, the settings are flushed before the signal is sent. And `kill -QUIT` no longer gets the Swift runtime's crash report, a backtrace, out of a running app: it quits it. `kill -ABRT` still does — an abort is a crash, handed on to the runtime's reporter (its threads as `SWIFT_BACKTRACE` sets them), with the alternate screen left up and the report on it.

## Programmatic Exit

A view can exit the application from inside its event handlers by calling
the SwiftUI-parity ``DismissAction`` exposed at
``EnvironmentValues/dismiss``:

```swift
struct ContentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Quit") { dismiss() }
    }
}
```

`dismiss()` sets a flag on the app's own `AppState` that the main loop
notices on its next iteration. The terminal is restored to its prior
state and `App.main()` returns normally — exactly the same teardown path
the built-in `q` key and `SIGINT` follow. This is the recommended way to
exit; calling `exit(0)` skips the terminal-restore step and leaves the
terminal in alternate-screen / raw mode.

## Key Event Dispatch

When the terminal delivers a key event, the `InputHandler` dispatches it through five layers (plus three refinements: an ESC pre-route before Layer 1 when an open drop-down has claimed Escape, the mid-drag Layer 0.5, and a semantic-shortcut stage — Layer 3.5 — between Layers 3 and 4). Layer 0 and Layer 3 are mutually exclusive based on `focusManager.hasTextInputFocus`:

### The Focus Path: SwiftUI's onKeyPress

Before any layer, the `onKeyPress` handlers on the views that contain the focused control are asked, outermost first, until one answers `.handled` — SwiftUI's order. Being focus-gated, they may come before even a focused text input. Skipped while an open drop-down grabs the keyboard or a drag is in flight.

### Layer 0: Text Input (conditional)

When a text input element (TextField/SecureField) is focused, `focusManager.dispatchKeyEvent()` runs first. This ensures printable characters, backspace, delete, arrows, home, end, and enter reach the text field before any other layer. Only keys the text field does not consume (Escape, Tab, unhandled ⌃ chords) fall through.

One key is not offered to the text input at all: an Emacs editing chord that an app's `.keyboardShortcut` is registered on, such as ⌃F under an app's ⌘F. It goes on down the chain as a chord the text input does not bind would, and Layer 3.5 fires the shortcut. See <doc:KeyboardShortcuts> for which chords give way.

### Layer 0.5: Drag Navigators

While something is in hand, the arrow and paging keys scroll whatever the pointer is over — how you reach a drop destination that is off screen without letting go. This has to beat every layer below it, all of which would otherwise spend the key on the focused control: a page-level `onKeyEvent` returning to the menu, or the source list moving its own selection. It declines unless a drag is actually in flight *and* the pointer is over something that drag could land in.

### Layer 1: Status Bar Items

``StatusBarState`` checks if any status bar item matches the key. Items can match single characters, special keys (Escape, Enter), or arrow keys. If a match is found, the item's action runs and dispatch stops.

### Layer 2: View-Registered Handlers

The `KeyEventDispatcher` iterates handlers registered via `onKeyEvent()` modifiers: in reverse order (newest first). If a handler returns `true`, dispatch stops.

### Layer 2.5: An Open Menu's Type Select

An open pop-up menu holds the keyboard without holding the focus, so its type select is asked here, after its own keys (Layer 2) declined a typed character: the character moves the highlight to the row whose title it starts, in whichever menu or submenu the keys are in. It follows a focused list's rule (Layer 3): a prefix under way takes every character, and a prefix's first character gives way to a bare-key binding that claims it — a row's key equivalent, the quit key, the help key.

### Layer 3: Focus System (conditional)

Skipped when text input has focus (Layer 0 already ran). Otherwise, `focusManager.dispatchKeyEvent()` first delegates to the focused element's `handleKeyEvent()`, then offers what it declined to SwiftUI's move, exit and delete commands on the views containing it (innermost first — Layer 0 does the same for a text input), then handles ⇥/⇧⇥ for focus cycling, then arrow keys as section navigation fallback.

### Layer 3.5: Semantic Shortcut Actions

If the focused control let the key fall through, an app's `.keyboardShortcut` fires: Return the default button and Escape the cancel button — à la SwiftUI's `.keyboardShortcut(.defaultAction)` / `.keyboardShortcut(.cancelAction)` — and any other key equivalent on its key. A chord Layer 0 did not offer a focused text control, because it is an editing command that gives way to an app shortcut registered on it, arrives here too.

### Layer 4: Default Bindings

Built-in key bindings that apply when no handler consumed the event, and the one key no layer sees:

| Key | Action | Condition |
|-----|--------|-----------|
| `q` / `Q` | Quit application | `statusBar.isQuitAllowed` — offered even behind a modal, as its escape hatch |
| Undo, redo | The app's undo manager's undo and redo, on the scene's `UndoShortcuts`: by default ⌃Z, ⌃- and ⌃/ undo, ⌃⇧Z, ⌃_ and ⌥_ redo | Always, after the app's own shortcuts; a bound key is taken whether or not there is a step |
| ⌃Z | Suspend the app | Only where the undo keys leave it out (`.undoShortcuts([.undo: …])`). Raw mode turns `^Z` off as a signal character, so the driver never turns it into SIGTSTP; reaching layer 4 unbound means no view claimed it (a focused text field's or editor's undo wins), so it is re-raised as the signal |
| `t` / `T` | Cycle to next palette | `statusBar.showThemeItem`, and no transient surface has grabbed input |
| `a` / `A` | Cycle to next appearance | No transient surface has grabbed input — otherwise `a` would restyle the app from behind a modal the user cannot see the controls for |
| ⌃\\ | Quit — even when the app hangs (under the kitty keyboard protocol, at the second ⌃\\; below) | Unless the app binds it, or a chord its byte may stand for: until then the terminal driver turns it into `SIGQUIT` before the app sees it (below) |

**⌃\\ quits, even when the app hangs — unless the app binds it.** While nothing in the app is bound to it, it never reaches the chain: the terminal driver takes it before the app sees it — from a bracketed paste too, as in a shell, so pasted text holding a 0x1C quits the app. Raw mode keeps the line discipline's signals on with every signal character turned off but the quit key, so ⌃C and ⌃Z are keys while ⌃\\ is still `SIGQUIT`, as in a shell; the signal then leaves the terminal as a quit does (see Signal Handling above). A user who turned the quit key off (`stty quit undef`) or moved it keeps their setting.

An app's own binding overrides the quit. While the app declares one on ⌃\\ — a `.keyboardShortcut` (a menu item's among them), an `onKeyPress` on the key on the path to the focused view, the status bar's quit key or an item, an undo key — or, in the terminal's legacy encoding, on ⌃4, ⌃| or ⌃⇧\\, for which some terminals send ⌃\\'s byte (measured per chord for Apple Terminal, iTerm2, Warp and Ghostty on 2026-10-06 — Apple Terminal for ⌃⇧\\ only, Ghostty for ⌃4 only, iTerm2 and Warp for both — and assumed of a terminal not measured), the driver's quit is masked: asked after every frame, the line discipline set only when the answer changes. The byte then reaches the chain as ⌃\\, and the app's bindings have it first — an unbound one tried as ⌃4, ⌃| and ⌃⇧\\ in turn on the bindings declared for them (a handler that hears every key hears it once, as ⌃\\), a ⌃\\ binding winning over a ⌃4 one, since the bytes are the same — and where none takes it the chain raises `SIGQUIT` itself, so ⌃\\ still quits a responsive app. A handler that hears every key (`onKeyEvent`, `onKeyPress(phases:action:)`) cannot be read without running it, so it masks nothing, and does not hear ⌃\\ while the driver has it; nor does an `onKeyPress` on a set of characters, which asks for typed text, not chords (`.decimalDigits` would otherwise claim ⌃4), nor one on a key for a Control chord the key does not name: `onKeyPress("|")` counts for ⌃|, but a PIN field's `onKeyPress(keys:)` on the digits does not count for ⌃4, though it hears ⌃4 (its keys match without Control), so it neither masks the quit nor is offered ⌃\\ again as ⌃4. The price: while such a binding is on screen, a hung app does not quit by ⌃\\; `kill -QUIT` from another shell still ends it.

Where the terminal speaks the kitty keyboard protocol it sends ⌃\\ as a key report instead of the byte the driver acts on; the input chain offers it to the app's bindings, as any key, and raises the signal itself where none takes it. A hung app reads no report, so a thread of its own, the stall watchdog (`StallWatchdog`), watches for input the loop leaves unread: after 1.5 s it pops the protocol's flags, the terminal sends keys in its legacy encoding again, and the next ⌃\\ is the byte the driver quits on. So under the protocol a hung app quits at the second ⌃\\, about two seconds after the first; the first report is never read. A loop that was only slow — a frame that took two seconds — pushes the flags back at its next read, and the keys typed across read right in either encoding. The watchdog costs the loop one store an iteration and each write to the terminal a lock, which the pop is written under, so it never lands inside a frame; a main thread hung inside a write (a terminal not reading) leaves it waiting, and nothing is popped. It is armed only while popping can help: not while the quit key is off, nor while the app declares a binding that the legacy encoding the pop puts the terminal in would mask the quit for — ⌃\\, or ⌃4, ⌃| or ⌃⇧\\ where they may share its byte, though under the protocol those three leave the driver's quit live, since after a pop the user's ⌃4 would be the driver's 0x1C and quit the app — nor during a suspend.

## Render Pipeline

Each frame follows 12 steps inside `RenderLoop.render()`:

| Step | What |
|------|------|
| 1 | Clear per-frame state (key handlers, preferences, focus, status bar items, toolbar items) |
| 2 | Begin lifecycle, state, and cache tracking |
| 3 | Build ``EnvironmentValues`` from subsystem state |
| 4 | Create ``RenderContext`` with layout constraints |
| 5 | Evaluate `app.body` → ``WindowGroup`` |
| 6 | Render the scene — the view tree, framed by the window's bars — → ``FrameBuffer`` |
| 7 | Build terminal-ready output lines |
| 8 | Begin buffered frame (`Terminal.beginFrame()`) |
| 9 | Diff and write only the changed lines of the frame |
| 10 | Keep the frame, so an animation tick can patch it without a render |
| 11 | Flush entire frame in one `write()` syscall (`Terminal.endFrame()`) |
| 12 | End lifecycle tracking (fires `onDisappear` for removed views) |

Steps 8–11 are the output optimization layer: line-level diffing reduces writes by ~94% for static UIs, and frame buffering reduces syscalls from ~40+ to exactly 1.

> For full details on each step, see <doc:RenderCycle>.

## Cleanup

When the main loop exits: via SIGINT or SIGTERM, the quit key, or programmatic shutdown: `cleanup()` restores the terminal:

| Step | What | Why |
|------|------|-----|
| 1 | Disable raw mode | Pop the kitty keyboard protocol's flags, if they were pushed, while the alternate screen they were pushed on is still up; restore original terminal settings |
| 2 | Show cursor | Make the cursor visible again |
| 3 | Exit alternate screen | Restore the user's previous terminal content |
| 4 | Clear state observers | Remove `AppState` observer callbacks |
| 5 | Clear focus | Tell the focused element it lost focus (a field's last commit point), then remove all focus registrations |
| 6 | Reset TUIContext | Clear lifecycle, key handlers, and preferences |

The `Terminal` class also has a `deinit` safety net that disables raw mode if it was not explicitly restored.

A process that dies of a signal with no orderly way out — a trap, a bad access, an abort, and the quiet terminations nothing in TUIkit handles (`SIGHUP`, `SIGUSR1` and the like, where the app has installed no handler of its own) — runs none of this. A handler for those signals pays what it can before passing the signal on: it pops the kitty keyboard protocol's flags if they are pushed, because they make every key an escape code, Return included, and would leave a shell that cannot be typed at; turns off the other input modes the app turned on; shows the cursor; and puts the shell's terminal settings back. It leaves the alternate screen up, with a crash's report on it. A suspend (⌃Z, where it suspends) pops the flags too, and the resume pushes them again.

## Subsystem Dependency Graph

### Ownership

AppRunner creates and owns every subsystem. TUIContext acts as a secondary container for lifecycle, key dispatch, and preference storage.

@Image(source: "dep-graph-ownership.svg", alt: "Ownership diagram showing AppRunner owning all subsystems: SignalManager, Terminal, AppState, StatusBarState, WindowChromeState, FocusManager, both ThemeManagers, TUIContext, InputHandler, RenderLoop, and CursorTimer. TUIContext contains LifecycleManager, KeyEventDispatcher, PreferenceStorage, StateStorage, and RenderCache. SignalManager sends SIGINT and SIGWINCH flags back to AppRunner.")

### Runtime References

During each frame, RenderLoop and InputHandler reference shared subsystems to build the environment and dispatch key events.

@Image(source: "dep-graph-references.svg", alt: "Runtime reference diagram showing RenderLoop writing output to Terminal, injecting environment values from StatusBarState, WindowChromeState, FocusManager, and both ThemeManagers, calling begin/end pass on LifecycleManager, StateStorage, and RenderCache, begin pass on PreferenceStorage, and clearing handlers on KeyEventDispatcher. InputHandler dispatches through Layer 0+3 FocusManager, Layer 1 StatusBarState, Layer 2 KeyEventDispatcher, and Layer 4 both ThemeManagers.")
