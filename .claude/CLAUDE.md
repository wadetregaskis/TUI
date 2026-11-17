## RULES

### Compatibility (non-negotiable, with one known exception)
- **Swift 6.2 compatible**: `swift-tools-version: 6.2`.  Readily make use of language features up to 6.2, such as nonisolated on protocols / classes / structs / enums, test scoping traits, the `@concurrent` attribute, `InlineArray`, `@Observable` types and the `Observations` struct, raw identifier display names for unit tests, default values in string interpolations, weak let, global-actor isolated conformances, isolated synchronous deinit, task naming, regex lookbehind, non-escapable types, `Span` where it's available, etc.
  For yielding accessors use the underscored `_read` and `_modify`. SE-0474's `yielding borrow` / `yielding mutate` would be the official mechanism, but no compiler supports it properly yet: 6.2 and 6.3 accept only the older `read`/`modify` spelling, and 6.4 only `yielding`, and all three only behind `-enable-experimental-feature CoroutineAccessors` (measured 2026-10-09).
- **Cross-platform**: must build and run correctly on both macOS and Linux. CI
  tests macOS 15 and 26 (Xcode 26) and macOS 27 (Xcode 27), and Swift
  6.2/6.3/6.4 Linux containers on x86_64 plus 6.3 on arm64, with
  nightly-toolchain lanes as advisory.
  **Windows is being ported, and every module builds there** (since
  2026-11-16; Documentation/Windows port.md is the record): keep it so. A
  POSIX-only API (`termios`, `ioctl`, signals, `poll`, `DispatchSource` on
  stdin, `pid_t`, `setenv`) needs a Windows arm beside it — `#if
  os(Windows)`, in the file or in a `+Windows` file of its own — or an
  `#if !os(Windows)` with the reason, where Windows has no counterpart. The
  console layer — the run loop, the `Terminal` class and its raw mode, the
  signal handlers, the stdin source — is `TUIApp`; what is Windows's own
  there is in `WindowsConsole.swift`, `SignalManager+Windows.swift` and
  `FatalSignalTerminalRestore+Windows.swift`. On Windows the C library's
  POSIX names (`isatty`, `getenv`, `write`, `close`) are deprecated, so a
  call to one is a warning there; see those files for what to call instead.

### Architecture (non-negotiable)

#### General Principles
- No Singletons
  - A cache that holds anything an app or a test can see, such as downloaded
    images, is not exempt: it travels through the environment (or the render
    context), so an app can give its views a different one.
  - The one exemption is a private, bounded, process-wide memo of a pure
    function: the same inputs always give the same output, and nothing outside
    the memo can tell a hit from a miss. There is nothing to inject, because
    nothing observable differs. The ASCII palette's search-index store is the
    example (`ASCIIPalette+SearchIndex.swift`). Key such a memo by everything
    its function reads.
  - The owner also granted (2026-10-24, ruling B-D6M-1) a value-keyed,
    append-only interner whose places a value carries:
    `LightDarkColorTable.shared`, the (light, dark) pairs a five-byte `Color`
    names by a two-byte place. It is keyed by the value alone (never a bundle,
    a name or an app), a place never changes once given, and it is bounded, so
    every test and app in the process can share it without one seeing
    another. A new interner of this kind still needs the owner's grant.
  - And three process-wide statics (2026-10-27, A-APPSTATE-2): the
    notification queue (`NotificationService.current`), the store
    `@AppStorage` reads when none is named (`StorageDefaults.backend`, as
    SwiftUI's is `UserDefaults.standard`) and the running app's URL opener
    (`TerminalURLOpening.runLoopOpener`). One app runs per process, none of
    them makes a test depend on another, and making them per app would only
    make them harder to reach. Revisit if one starts doing either.
- **Before implementing ANYTHING NEW: Search the codebase** for similar patterns, reusable code, existing solutions
- Consolidate and reuse before adding new functions or types
- "Reinventing the wheel" is a code smell: investigate why it exists first

#### Code Reuse Checklist
1. Does a similar feature exist? Use it or extend it
2. Can I reuse a helper function/extension/modifier? Do it
3. Does a pattern already exist? Follow it exactly
4. Am I duplicating logic? Refactor into a shared utility
5. **Never implement features in isolation**: maximize consistency and minimize maintenance burden

### Workflow
- **NEVER merge PRs autonomously**: stop after creating, let user merge

### Performance & profiling (non-negotiable)
- **Profile with the committed tools.** `Tools/Profiling/` records an
  Instruments Time Profiler trace of `Example` driven through a PTY
  (`record.sh`) and ranks the hot functions (`analyze_timeprofile.py`).
  See `Tools/Profiling/README.md`. Extend these rather than hand-rolling
  one-off profiling.
- **The profiling record lives in the commit message, not in the repo.**
  Raw `.trace` bundles are large (~14 MB; ~5 MB compressed) and
  git-ignored — NEVER commit them; they would bloat the clone for every
  downstream package consumer forever.
- **A change motivated or informed by profiling MUST, in its commit
  message:**
  1. quote the relevant profiling excerpts / numbers — the
     `analyze_timeprofile.py` lines that matter (self / inclusive %, the
     hot functions, module split), and
  2. explain how that profile data informed the change: what was hot, why
     this change addresses it, and the before/after numbers when available.

  This keeps the rationale attached to the change it produced and
  discoverable via `git log` / `git blame`, at zero repo cost. (Commits
  not motivated by profiling — tooling, unrelated fixes — are exempt.)

### Terminal-specific behaviour (non-negotiable)
- **Consult and update `Documentation/Terminals/Terminal compatibility survey.md`** for any
  change that relies on terminal-specific behaviour (`TerminalHost`, cursor
  advance models, `FrameDiffWriter` compensation, chrome glyph selection).
  It is the canonical, version-stamped record of measured terminal
  behaviour; new observations about any terminal go there, measured with
  the probes in `Tools/TerminalProbes/` where possible.

### SwiftUI API Parity (non-negotiable)
Public APIs MUST match SwiftUI signatures exactly unless terminal constraints require deviation (document why in comments).

| Aspect | Requirement |
|--------|-------------|
| Parameter names | Exact (`isPresented`, not `isVisible`) |
| Parameter order | Exact (title, binding, actions, message) |
| Parameter types | Match closely (ViewBuilder closures, not pre-built values) |
| Trailing closures | `@ViewBuilder () -> T`, not `String` |

**Before implementing:** Look up exact SwiftUI signature first.
**TUI-specific APIs:** OK to add as modifiers, extra initialisers or defaulted parameters on SwiftUI's own
initialisers, so long as no SwiftUI declaration is shadowed, renamed or made ambiguous ("Extending SwiftUI's API" below).

### View Architecture (non-negotiable)

#### Public API: Every control is a View with a real body

**The Rule:**
- Every **public** control MUST be a `View` with a real `body: some View`
- The `body` MUST return actual Views (not `Never`, not `fatalError()`)
- All modifiers MUST propagate through the entire View hierarchy
- Environment values MUST flow down automatically

**Why this matters:**
```swift
// This MUST work exactly like SwiftUI:
List("Items", selection: $selection) {
    ForEach(items) { item in
        Text(item.name)
    }
}
.foregroundColor(.red)  // MUST affect all Text inside!
.disabled(true)         // MUST disable the entire List!
```

#### Renderable: When and where it is allowed

Terminal UI requires procedural buffer assembly (ANSI codes, Unicode borders,
buffer overlays). `Renderable` is the mechanism for this. It is allowed in
these cases:

| Layer | Example | Renderable? |
|-------|---------|-------------|
| **Leaf nodes** | `Text`, `Spacer`, `Divider` | Yes (terminal primitives) |
| **Private `_*Core` views** | `_ButtonCore`, `_VStackCore` | Yes (procedural ANSI rendering) |
| **Layout primitives** | `_VStackCore`, `_HStackCore` | Yes + `Layoutable` (two-pass layout) |
| **Modifier infrastructure** | `ModifiedView`, `EnvironmentModifier` | Yes (context/buffer pipeline) |
| **Public controls** | `Button`, `VStack`, `List` | **No** (must use `body: some View`) |

**The `_*Core` pattern:**
```swift
// Public View: real body, environment flows through
public struct MyControl<Content: View>: View {
    let content: Content

    public var body: some View {
        _MyControlCore(content: content)
    }
}

// Private Core: Renderable for terminal-specific rendering
private struct _MyControlCore<Content: View>: View, Renderable {
    let content: Content
    var body: Never { fatalError("_MyControlCore renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Read environment from context, render with ANSI codes
    }
}
```

**Preferred: Pure composition (Box.swift is the reference):**
```swift
public struct MyControl<Content: View>: View {
    let content: Content

    public var body: some View {
        content
            .padding()
            .border()
    }
}
```

When possible, prefer composition over `_*Core`. Use `_*Core` + `Renderable`
only when the rendering requires procedural buffer manipulation that cannot
be expressed as View composition.

**WRONG Pattern (public control with Renderable):**
```swift
public struct MyControl: View {
    public var body: Never { fatalError() }  // WRONG!
}

extension MyControl: Renderable {  // WRONG - public types must not be Renderable!
    func renderToBuffer() { ... }
}
```

**Before implementing ANY control:**
1. Can it be composed from existing Views + modifiers? (preferred)
2. If not, does the public View have a real `body` wrapping a private `_*Core`?
3. Does `_*Core` read environment values from `RenderContext`?
4. Test: `.foregroundColor()` on the control affects its content?
5. Test: `.disabled()` on the control disables interactions?

### Interactive Views: Focus & State (non-negotiable)

All interactive views (Button, TextField, Toggle, Slider, etc.) that participate
in the focus system MUST follow these rules:

#### FocusID generation
- Default focusIDs MUST use `context.identity.path`, never user-facing data
- Pattern: `"\(prefix)-\(context.identity.path)"` (e.g. `"button-\(context.identity.path)"`)
- Never use label text, titles, or other user content for focusIDs (collision risk)

#### Focus registration
- Use the shared `FocusRegistration` helper for all focus setup
- Do NOT duplicate focus registration boilerplate in individual views
- Registration, disabled-state check, and isFocused query are one operation

#### StateStorage property indices
- Every `_*Core` view MUST document its property indices with named constants:
```swift
private enum StateIndex {
    static let focusID = 0
    static let handler = 1
}
```
- Never use bare integer literals for `propertyIndex`
- **Indices `0...` belong to composite `@State`.** A wrapper that renders
  caller-supplied content at its OWN identity (no `withChildIdentity`) must
  use **negative** indices from a reserved range — the table lives on
  `StateStorage.StateKey` — or the content's first `@State` aliases the
  wrapper's box. Leaf cores whose slots can never share an identity with
  composite content keep `0...`.

#### Disabled state
- Disabled views MUST NOT register with the focus system
- Check `isDisabled` BEFORE calling `focusManager.register()`
- Disabled styling MUST be visually consistent across all interactive views

### SwiftUI API Design (non-negotiable)

#### Extending SwiftUI's API: never shadow or break it
The rule is SwiftUI compatibility, not a particular shape (owner, 2026-11-16): a
SwiftUI call site must compile and behave exactly as it does in SwiftUI, and
nothing TUI adds may shadow, rename or make ambiguous a SwiftUI declaration.
Within that, a TUI-specific option or extension may take whatever shape suits it:

- **A modifier.** The natural shape for an option that should reach a subtree
  (focusID, emptyPlaceholder, styles, etc.), since an init parameter reaches only
  its own view.
- **An extra initialiser** of TUI's own, beside SwiftUI's. It leaves SwiftUI's
  untouched and costs nothing when unused.
- **An extra parameter on a SwiftUI initialiser,** provided it has a default
  argument, so every SwiftUI call site stays source-compatible.

What stays fixed:
- SwiftUI's own signatures keep SwiftUI's parameter names, order and types
  exactly (see "SwiftUI API Parity" above); a TUI parameter is added, never
  substituted, and always defaulted.
- Minimize init overloads (each extra one costs type-checking time and risks
  ambiguity); prefer `@ViewBuilder` label variants over String convenience inits.
  Check that a new init or parameter makes no existing SwiftUI call ambiguous.

**Deliberate deviations need the owner's approval.** TUI does sometimes depart
from SwiftUI's API on purpose: leaving a SwiftUI API unimplemented, or
implementing a source-incompatible version of one. That is permitted, and at
times necessary and worth it, but only once the owner has reviewed it and
explicitly approved it. Put it to the owner as a question (what SwiftUI has,
what TUI would do instead, why, and what a SwiftUI program would have to
change), never decide it yourself, and record the ruling with its date in
`Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` and in the
declaration's own doc comment.

**Fine:**
```swift
List(selection: $selection) { content }
    .focusID("my-list")                  // a modifier: reaches the subtree
Table(rows, children: \.children, expansion: $open) { columns }   // illustrative: a defaulted
                                         // TUI parameter on SwiftUI's init
```

**Wrong:**
```swift
// A required (undefaulted) TUI parameter: SwiftUI's own call no longer compiles.
public init(selection: Binding<Selection>, focusID: String, @ViewBuilder content: () -> Content)
// A renamed SwiftUI parameter, or an overload that makes `List(selection:)` ambiguous.
```

#### Modifier-first for subtree-wide behaviour
TUI-specific behavior that SwiftUI handles via modifiers, or that should apply
to a whole view hierarchy, SHOULD be a modifier:
- Focus identity: `.focusID(_:)`
- Placeholder text: `.listEmptyPlaceholder(_:)`
- Visual customization: `.trackStyle(_:)`, `.buttonStyle(_:)`, etc.

### File Organization

- Source files SHOULD stay under 500 lines
- If a file exceeds 500 lines, consider splitting: public API in one file, `_*Core` in another
- One view per file (do not combine VStack + HStack + ZStack in one file)
