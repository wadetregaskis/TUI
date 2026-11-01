# Compiled hot reload: the design

**Status:** a design, for after 1.0. Nothing here is built, and no source in `Sources/` changes with this
document. The owner decided on 2026-11-01 that TUI should have this feature, after the initial release.
Measured against `main` at `611339da1`, on 2026-11-01. The [Future
options](<Future options.md#compiled-hot-reload>) entry links here.

**How far to trust a statement:**

| Mark | Meaning |
|---|---|
| **[measured]** | I built it and ran it, on this machine, for this document. Probes are described in [How this was measured](#how-this-was-measured). |
| **[read]** | I read it in source: TUI's at the commit above, SwiftTUI's at `207913d23`, InjectionLite's at `4b08bd3`. |
| **[doc]** | The project's own documentation or a named forum post says so. Not checked further. |
| **[inferred]** | My reasoning. Nobody has run it. |

## The answer, first

1. **The mechanism is the one Xcode Previews uses: function replacement.** The app's targets are built with
   `-enable-implicit-dynamic`. When a file is edited, a generated module holding `@_dynamicReplacement`
   versions of the file's functions is compiled against the app's module and `dlopen`ed. It is not what
   SwiftTUI does, which is to recompile the whole target under a new name.
2. **It settles the owner's objection to hot restart.** The app's types stay the same types, so every object
   the app has made, in any target, stays alive and usable, and runs the new code on its next call; globals
   keep their values; tasks keep running. SwiftTUI's mechanism strands exactly these for an app with one
   target, and a probe of it shows that [measured]. **What is still lost** is said plainly in section 1:
   mainly, a class whose *stored properties* change cannot keep its existing objects. Every tool that keeps
   objects alive has that limit.
3. **It works.** `Example`, the real app, with two compiler flags on its target and one attribute on `View`,
   loaded a hand-written replacement of `SliderPage` while running, in a PTY: the screen changed, `@State`
   kept the value the keys had moved it to, the keys still worked, and a second generation loaded over the
   first [measured]. The generator that would write those thunks does not exist.
4. **One to two seconds looks reachable, and it is close to being comfortably so.** On this busy machine, with
   Swift 6.2.4: compiling and linking one typical file into an image takes **0.63 s** at the median across
   `Example`'s files, 1.6 s at the 90th percentile, and both of those include time that can be removed,
   0.3–0.7 s on the files timed separately. Save to redraw adds about 0.3 s to that. In contrast, the whole
   target takes 22–74 s to compile and a `swift build` that does nothing takes 6–20 s, so anything going
   through SwiftPM or compiling the target cannot make the budget: the per-file path is not an optimisation
   but the only route. Section 5 has the breakdown, and what to do about the files that overrun.
5. **`SIGHUP` is the wrong signal.** It is the only thing that ends a TUI app when its terminal closes:
   standard input's hang-up does not. Taking it for reloads would leave orphaned apps running. `SIGUSR1`
   instead, section 4.
6. **The riskiest assumptions:** Linux has not been run, only reasoned about from an upstream test and
   SwiftTUI's driver. The mechanism rests on underscored compiler features. And Swift 6.4's default build
   system applies the `UnexportTUISymbols` trait's link flags to debug builds, so an image cannot load until
   that trait is turned off, which is section 5's finding and may be of interest apart from all this. Stage 0
   of the plan (section 8) is one week spent on exactly these before anything else.
7. **About three months** to the end of stage 4, with a useful tool after five to seven weeks.

Section 10 lists what the owner decides. Section 9, separately, lists what to keep true before 1.0.

## 1. What survives, precisely

### The fact that decides everything: same types, or new types

With an in-process reload the process lives on, so its memory does. That is necessary, and it is not enough.
What matters is whether the *new code can use* what is in that memory, and that depends on one thing: whether
the types in the reloaded code are the same types as before, or new ones with the same names.

**New types: the SwiftTUI mechanism.** It compiles the whole target again under a new ABI name
(`compileApplicationImage` in `ReloadDriver.swift`) [read]. I built that in miniature (probe B), an app whose
`Model` class and globals live in the executable target, with a library beside it:

```
host:  Model.self = App.Model     4337140584         appGlobal = 500   initRuns = 1   LibModel.shared.n = 10
image: Model.self = App_R1.Model  4337681376         appGlobal = 100   initRuns = 0
image: host's model as? Model: false
image: after touching Model.shared, initRuns = 1
image: LibModel.shared.n = 11
```

So the old `Model` object is alive and the new code cannot touch it. The new image has its own `appGlobal` at
its initial value and its own `Model.shared`, whose initializer ran again. Only what lives in *another*
module, here `LibModel`, carries over. SwiftTUI's docs say the same: a reference decodes into a new instance,
and state otherwise passes through `Codable` or resets (`Compiled-Hot-Reload.md`) [doc]. **For an app with one
executable target, which is every small app and `Example`, this is close to the hot restart the owner
rejected:** the process survives, and the app's own objects are stranded in it. It does keep what the app has
put in dependencies.

**The same types: function replacement.** The types stay where they are, in the original image, and only the
bodies of functions change. The same probe's equivalent (probe A):

```
--- before
model: old describe 41 shared== true         global: 101 initRuns: 1
Screen id: 4375659320 Model id: 4375676224 model as? Model: true
--- after loading libR1.dylib
model: NEW describe 42 shared== true         global: 102 initRuns: 1
Screen id: 4375659320 Model id: 4375676224 model as? Model: true
closure: closure made by OLD code
```

The object created before the load runs new code, keeps its data, and still casts. The metatype has not moved,
the global kept its value, and the lazy static's initializer did not run again. This is why section 2 chooses
it.

### Case by case

"This design" is function replacement (section 2). Marks: **[measured]** from the probes, **[read]** from
source, **[inferred]** otherwise.

| What | In this design | In the SwiftTUI mechanism |
|---|---|---|
| An instance of a class in the reloaded file, stored properties unchanged | **Survives.** Same object, same metatype. Every method runs the new code on its next call, final and non-final alike, and `super` calls too [measured, probes A and D]. An `@Observable` class is the same [measured, D] | Stranded. `as?` fails [measured, B] |
| The same class with a stored property added, removed or retyped | **Cannot be reloaded in place.** Old objects have the old layout, and no mechanism fixes that. Old code keeps running, and the banner says "`Model`'s stored properties changed: relaunch". InjectionIII cannot do it either (see the comparison below). The choice of what else to offer is HR-3 (section 10) | Not a special case: a new `Model` starts empty |
| A model in a dependency, or anywhere outside the reloaded targets | **Survives untouched**, and keeps running the old code, since it was not recompiled [measured, A] | The same [measured, B] |
| A model in a *local* library target that the developer is editing | Reloadable like the app's own target, once stage 5 handles several targets. Until then an edit there says "relaunch" | Restart required (`validateChangedSources`) [read] |
| `@State` of an app-defined value type, shape unchanged | **Survives**, without `Codable`: the box and its value are simply still there, since the type has not changed [measured for `Double` in `Example`; an app-defined type is the same code path, inferred] | Round trip through `Codable`, or reset [doc] |
| `@State` of an app-defined value type whose fields changed | Re-declared as a new type: converted field by field by name where it can be, by `Codable` next, otherwise reset, and reported (section 3) | Reset, unless it has the same `Codable` schema [doc] |
| `@State` holding a class instance | **The same instance** [inferred from the two rows above] | A new instance, if it is `Codable` at all [doc] |
| A global or `static` | **Keeps its value.** Storage stays in the original image. Its initializer does not run again, so *an edit to the initial value has no effect*, and the report says so. Flutter's documentation sets the same rule, treating globals and statics as state [measured, A and D] | A fresh copy, initializer re-run [measured, B] |
| A *new* global or static added by the edit | Lives in the image, and starts at its initial value. If its file is compiled again in a later generation, it starts again (section 2) | The same |
| A task already running | **Runs on, in the old body.** A running function's frame is not replaced, but what it calls is: [measured, probe E] `loop text is OLD, callee says: NEW tick 4`. A new call to the function runs the new body. `.task` modifiers: section 3 | Old lifecycle work is cancelled, new work starts [doc] |
| A closure already stored | **Keeps running the code it was made with**, which stays mapped because images are never unloaded [measured, A]. Calls it makes to functions get the new ones. The framework's own closures (button actions, handlers, disappear callbacks) are registered again each frame the view draws, so they become new on the next frame (`LifecycleManager.registerDisappear`'s "they register every frame") [read]. A closure the *app* stored in a model stays old until the app stores another | Old closures stay valid, but they belong to the old types [doc] |
| `@AppStorage`, `@SceneStorage`, files, sockets, child processes, the terminal and its modes, the scene phase | **Survive.** The process, its descriptors and the render loop never stopped. | The same |
| The navigation stack, open sheets, the focused control, a scroll position | **Survive**, being state in the store under stable keys (section 3) [measured for `currentPage` in `ContentView`; the rest inferred] | Replayed where `Codable`; focus and scroll have their own replay [doc] |

### What is still lost: the honest list

Even with the strongest mechanism available, these do not survive or do not take effect:

1. **Objects of a class whose stored properties changed.** This is the big one. If a developer adds a field to
   a model class, those objects cannot gain it. The tool refuses rather than crash. This is a real limit, and
   it is the same one InjectionIII and Subsecond state. The alternative is a relaunch, or the fallback of
   HR-3.
2. **Changes to initial values.** `static let limit = 10` edited to `20` does nothing until a relaunch, and
   the report says so. So does a stored property's default in a class, and `@State var x = 1`'s `1` once the
   box exists, which is what SwiftUI does on a redraw anyway.
3. **Code already running.** The rest of an `await`ing function, a `while` loop's own body, an `.onAppear`
   that has fired. The `main.swift` top level and `App.init` never run again.
4. **A class's designated `init` and any `deinit`.** The compiler refuses a replacement of a designated
   initializer ("replaced initializer 'init(a:)' is not marked as convenience") and `deinit` has no syntax for
   it [measured, D]. Editing either is a class shape change for these purposes.
5. **Default arguments.** They are computed at the call site, and a caller compiled earlier keeps the old one
   [measured, D: `got old default arg`]. Callers in the file being reloaded get the new one. The report can
   flag it.
6. **State below a change of identity.** Replacing a view with a different one still resets what that view
   held, as it does in SwiftUI. Section 3 narrows this to real changes rather than artefacts of generic type
   names.
7. **Whatever the generation does not contain.** A file removed stays compiled in. A protocol conformance
   removed stays in effect. C targets, resources and manifests need a relaunch.

And there is one way it costs more than a relaunch: a wrong classification can crash the process, losing
everything (section 8's risks).

### What others do

| Tool | Mechanism | What it says happens to state | Source |
|---|---|---|---|
| **Xcode Previews** | Generates a `*.preview-thunk.swift` per file, replacing `body` and the rest with `@_dynamicReplacement`, using `@_private(sourceFile:)` to reach private declarations and `#sourceLocation` to keep line numbers; compiles it to a dylib, or JITs it since Xcode 16 where conditions allow; relies on the `View` eraser to change body types. **This is the mechanism chosen here.** | Apple documents no contract that I could find. Joe Groff describes previews as reloading views in place after edits, and an in-place reload keeps the process's memory [inferred]. **I did not verify the behaviour in Xcode**; only the mechanism, from third-party write-ups and swift-build's source, where `SWIFT_ENABLE_OPAQUE_TYPE_ERASURE` is noted as needed to substitute view bodies and a JIT mode leaves `thunkLibrary` empty | [fatbobman, 2023](https://fatbobman.com/en/posts/how-swiftui-preview-works), [Guardsquare, 2019](https://www.guardsquare.com/blog/behind-swiftui-previews), [swift-build `SWBPreviewSupport.swift`](https://sources.debian.org/src/swiftlang/6.2.3-1/swift-build/Sources/SwiftBuild/SWBPreviewSupport.swift), [forum, Joe Groff](https://forums.swift.org/t/any-info-on-the-typeeraser-attribute/37826) |
| **InjectionIII**, **InjectionNext**, **InjectionLite** | Recompiles one file under its own module name, into a dylib. Rebinds calls with fishhook through `-Xlinker -interposable`, patches class vtables, and swizzles Objective-C. Types in the file get a second copy (`Reloader.loadAndPatch` tells the user to ignore the duplicate-class messages) with the old class's vtable pointed at the new code | Function bodies only, by InjectionNext's README: no adding, removing or renaming stored properties, no adding methods to non-final classes, no signature changes. Size changes are detected and block the load (`Reloader.dyload`). **Statics are re-initialized by default**: preserving them is `INJECTION_PRESERVE_STATICS`. InjectionIII's README counts a body's type change as a layout change that may crash, hence `.enableInjection()`, which wraps in `AnyView`. It says `private` members cannot be injected directly. Default arguments can fail the load. Darwin only | [InjectionIII README](https://github.com/johnno1962/InjectionIII), [InjectionNext README](https://github.com/johnno1962/InjectionNext), [InjectionLite `Reloader.swift`](https://github.com/johnno1962/InjectionLite) at `4b08bd3` [read] |
| **Inject** | A thin layer on InjectionIII: `@ObserveInjection` and `.enableInjection()`, which compile away in release | As InjectionIII | [README](https://github.com/krzysztofzablocki/Inject) |
| **SwiftTUI** | Whole target under a new ABI name, `dlopen`, swap root, replay `@State` through `Codable` | Described above; a slot that is not `Codable`, or whose schema changed or is ambiguous, resets with a diagnostic | `Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Compiled-Hot-Reload.md` at `207913d23` [read] |
| **Flutter** | A VM swaps classes in place | Globals and statics count as state and are not re-initialized, `main()` and `initState()` are not re-run, and generic or enum shape changes need a restart | [Flutter docs](https://docs.flutter.dev/tools/hot-reload) |
| **Subsecond** (Rust, Dioxus) | Detours calls through a jump table, with a linker built for it | A changed static initializer is not observed; struct layout changes are unsupported, and frameworks discard old state for that reason, detecting it by the `TypeID` | [docs](https://docs.rs/subsecond/0.7.10/subsecond/) |

Two things stand out. Everyone who keeps objects alive has this document's limit on stored properties: it is
not a weakness of Swift's replacement mechanism. And nobody else in Swift's world has a Linux story except
SwiftTUI, which pays for it with state.

## 2. The mechanism

### The options

| Option | Needs on macOS | Needs on Linux | Limits, and what stops it | Verdict |
|---|---|---|---|---|
| **A. Whole target under a new ABI name, `dlopen`** (SwiftTUI) | `-module-abi-name`, `-undefined dynamic_lookup`, an executable that exports its symbols (`-export_dynamic`) [read] | `--export-dynamic`, `-Bsymbolic` [read]; SwiftTUI runs there [doc] | No hidden compiler feature but `-module-abi-name`, the simplest by far, and any edit works. But every app type is a new type: the app's objects and globals are stranded (section 1). The whole target compiles on every edit: 22–74 s for `Example` (section 5). | **Not the main path**, for both reasons. Kept as an explicit fallback for what B must refuse (stage 5). |
| **B. Function replacement** (Xcode Previews): `@_dynamicReplacement` in a generated module, with the app built under `-enable-implicit-dynamic` | Those flags, `-enable-private-imports`, `@_typeEraser` on `View`, a source generator; **works today on `Example`** [measured] | The same in principle: upstream's `test/Interpreter/dynamic_replacement.swift` covers Linux and Windows and excludes only wasm [doc]. **Not run here**; stage 0 does | Types and globals are untouched, and one file compiles in under a second against the module. Cannot change layouts, a class's designated `init`, `deinit`, or a default argument in a caller already compiled. Rests on underscored features. Needs a generator that knows Swift's declarations. | **Chosen.** |
| **C. Interposing and vtable patching** (InjectionIII): the same file, same module name, new dylib | `-Xlinker -interposable` so calls go through a writable table, fishhook, walking `objc_copyClassList` [read] | No equivalent. An ELF executable's internal calls are direct. Would need an app built as a shared library with semantic interposition, GOT rewriting, and a Swift-class walk with no Objective-C runtime to ask [inferred] | The new image has its own copy of each type in the file, so metatypes split: `ViewIdentity` steps and `as?` both see two `Foo`s, unless reverse-patched. Statics re-initialize by default. Needs no source generator. | **No.** Darwin-only as it stands, and the split metatypes are the very problem B avoids. |
| **D. Patching function entry points** (Live++ style; Subsecond's docs contrast themselves with such "detour" libraries) | Writable text pages under W^X and code signing on arm64 [inferred, not tried] | `mprotect`, and a jump sequence per architecture, in functions short enough that a jump may not fit [inferred] | Same-name recompile, so the same split metatypes as C. Machine-specific, per-architecture code. | **No.** |
| **E. A JIT** (Xcode's XOJIT, LLDB's expressions) | Xcode's is private. Building one means linking LLVM's ORC into the app, and registering Swift metadata by hand [inferred] | The same | Compile time unchanged (the time is in the front end, section 5). A very large dependency in the process. | **No.** Nothing to reuse, and it buys only link and load, which cost little. |
| **F. Hot restart:** quit, relaunch, restore `@State` from a snapshot | Nothing | Nothing | **Rejected by the owner:** "it would only preserve state that TUI knows about… Any other app state would be lost… in any real app, I fear that would be untenable and make it a useless feature." Also slower: relaunching needs a link of the whole app, 3.3 s for `Example` [measured], where B links 126 KB. Recorded here because the working notes' Question 4 recommended it first. | **No.** One narrow use remains as a convenience: section 8's relaunch-in-place, for an edit nothing else can apply, offered as what it is. |
| **G. App logic in a dynamic library, reload the library** | SwiftPM `.dynamic` product, restructured app | The same | Option A in another shape, and the same stranding. `ENABLE_DEBUG_DYLIB` in Xcode is this idea for a different purpose. | **No.** It asks every app to restructure. |

**Windows, later.** `TUIApp` has no Windows build, so this waits for that port. Replacement itself is covered
by the upstream test on Windows (`LoadLibraryA`) [doc]. The hard part is that a DLL cannot have undefined
symbols, so a replacement image needs an import library for the executable, with everything `dllexport`ed,
which is more than `-enable-testing` gives [inferred]. `ReadDirectoryChangesW` is the watcher. None of the
design above prevents it, and the parts in `TUICore` and `TUIView` stay free of POSIX.

### Why B

1. **It is the only option that keeps the app's objects, which is what the owner asked for.** Section 1, probe
   A.
2. **Its compile is one file against the module**, not a target. Section 5 has the numbers, and they are the
   difference between inside and outside the budget.
3. **It needs no new entry point in the app**, because `App.body` and the root view are replaced like anything
   else. Three of Question 4's problems go away: `RenderLoop<A: App>` being generic over the scene, the root
   export, and much of the type-erased root host.
4. **Its limits are visible before anything loads.** The compiler rejects what it cannot do, and the
   classifier sees what it should not try.
5. **It has a large, motivated other user**, so it is less exposed than its underscores suggest.

The price is a source generator and a dependency on those underscores. Both are real; see section 8.

### How it works

**The build.** The app's targets are compiled with `-enable-implicit-dynamic`, which puts every function,
including accessors, behind a replaceable entry, and with `-enable-private-imports`, which lets another module
reach `private` declarations. `-enable-testing` is already in SwiftPM's debug command [read:
`description.json`]. Nothing else differs, and these flags apply only to the app's own targets. Rebuilding
`Example`'s target with them cost 35 s once, and added 24 KB to the 74 MB binary [measured].

**The eraser.** `@_typeEraser(AnyView)` on `View`. With it, a `dynamic` function returning `some View` is
compiled to wrap its result in `AnyView(erasing:)`, which `AnyView` already has for SwiftUI's sake
(`PrimitiveViews.swift`) [measured: that one attribute is all it took on `Example`]. So `V.Body` is `AnyView`
in reload mode, a replacement can return anything, and generic framework code that has read `V.Body` once, as
`renderToBuffer` and every static-member walk do, is never wrong about it. **This is not optional:** the same
probe without the eraser, where a replacement changes `body`'s concrete type from `String` to a larger struct,
ends in `Segmentation fault: 11` [measured]. Joe Groff says as much: without it, a replacement must return the
same type (section 1's source).

The same goes for every protocol whose `body` an app writes: `ViewModifier` and the style protocols return
`some View`, so they are covered. `Scene`, `Commands` and `Keyframes` need erasers of their own, which TUI
does not have yet: `AnyGesture`, `AnyShape` and `AnyLayout` exist, `AnyScene` and `AnyCommands` do not. Until
they do, an edit that changes `App.body`'s structure is "relaunch". Swift 6.2 allows several `@_typeEraser` on
one protocol, which is how SwiftUI gained `DebugReplaceableView` beside `AnyView` on its 26 SDKs, to make this
cheaper ([Kyle Ye's
write-up](https://kyle-ye-github-io.pages.dev/posts/debugreplaceableview-multiple-type-erasers)) [doc,
unverified]. Worth a look later, if erasure's cost in a session matters.

**The generator.** On an edit, `tui-dev compile` parses the old and new text of each changed file with
swift-syntax's parser, and compares their declarations. For a file whose declarations are unchanged in shape
it writes a thunk such as this, which is the one that ran:

```swift
@_private(sourceFile: "SliderPage.swift") import Example
import TUI

extension SliderPage {
    @_dynamicReplacement(for: body)
    private var __r_body: some View {
        ScrollView { content }
            .navigationTitle("menu.item.sliders")
    }

    @_dynamicReplacement(for: caption(_:))
    private func __r_caption(_ textKey: LocalizedStringKey) -> some View {
        Text(textKey).foregroundStyle(.palette.accent)
    }

    @_dynamicReplacement(for: content)
    @ViewBuilder private var __r_content: some View { /* the edited body */ }
}
```

Everything needed comes from the module: `private` properties, `$volume`, `caption`, other files'
`DemoSection`, all unchanged. With `#sourceLocation` around each body, as Previews does, compiler errors and
crash reports name the original file and line. At first every function in the file is replaced, not only the
ones the diff found, which is simplest. A replacement's name must be unique across a class hierarchy, since a
subclass's `__r_who` otherwise reads as an override of its superclass's [measured: "instance method … cannot
be overridden"], so names include the type.

**The image.** The thunks for the generation's files compile to one image, `<Module>_R<n>`, a new module that
imports the app's module, with the target's own flags and a private module cache: `swiftc -c -module-name
Example_R1 -I <Modules> … SliderPage.thunk.swift`, then a link of the objects as a library with no `-g`, on
macOS with `-undefined dynamic_lookup`. Two steps because the one-step form spends 0.3–0.7 s on a dSYM nobody
needs (section 5).

**The load.** `dlopen`, on the main actor, between frames. The replacements take effect during `dlopen`, as
the Swift runtime registers the image [doc: the pitch]. A later image over an earlier one simply wins, with or
without `-enable-dynamic-replacement-chaining`, and the two probes' output was identical [measured]. Images
are never closed.

### What each edit becomes

| The edit | Becomes | Evidence |
|---|---|---|
| The body of a method, function, computed property or subscript, `static` or `class` too, generic or not, `async`, `mutating`, on a struct, class, enum or actor, `private` or not, an extension of a type from another module (`Int`), a protocol extension's default, a protocol witness, a global computed property | **Replacement** | [measured, D] |
| A new function, computed property, nested type or global function | A new declaration in the image. Visible to replaced code in this generation; stays in the set until a relaunch, so that later generations see it | [measured, A: `BrandNew`] |
| A new struct, enum or class | The same | [measured, A] |
| A struct's `init` with arguments | **Replacement**, by delegating (run) or assigning fields directly (type-checked only). Not the synthesised memberwise `init`: a replacement of that compiles, and has no effect | [measured, D] |
| A struct's or class's `init()` with no arguments | Value type: re-declare (next row). Class: relaunch. The replacement would have the same name as its target, and the compiler stops with a "circular reference" | [measured, D] |
| A stored property added, removed, retyped, or its default or `didSet` changed, an enum case changed, a conformance list or generic parameter changed, **on a value type** | **Re-declare the type** in the image and shadow the original, and add every file that mentions its name to the generation, since their code knows the old layout. The old values are converted (section 3). Stage 4 | [measured, A: `Child` with a field added shows through a replaced `Parent.body`] |
| The same **on a class**; a designated `init`, a `deinit`, a `lazy` or observed property's accessor | **Relaunch needed**, with old code still running | [measured, D: "replaced getter for 'observed' is not explicitly defined"] |
| A global's or static's initial value | Ignored, reported | [measured, A, D] |
| A default argument | The new value reaches callers compiled in this generation; others keep the old | [measured, D] |
| `some P` with no eraser for `P`, other than a same-type edit | **Relaunch needed**, since a changed underlying type is the segfault above. Cannot be told from syntax alone, so all of these are treated that way | [measured, noeraser] |
| A macro-attached declaration changed (`@Entry`, an `@Observable` class's stored properties) | Relaunch needed. An `@Observable` class's *methods* are ordinary | [measured, D] |
| A file added | A generation file with only new declarations. Stage 5 | [inferred] |
| Anything `@objc`, a C target, `Package.swift`, `Package.resolved`, a resource, a dependency's sources | Relaunch needed | [inferred] |

**What goes in a generation.** A file whose thunk replaced functions and added nothing can leave the set
straight away: its replacements stay applied forever, whether or not it is compiled again. A file that added
declarations stays, because a later generation's code may call them, and every generation re-declares them.
That has one consequence worth stating: a global *added* during the session starts over each time its file is
compiled again.

**What this compile does not check.** It sees the old module's declarations. Delete a function used by another
file, and the image still compiles, the other file still calling the old one. The real build is the authority:
`tui-dev` can run one when the session ends, and it should say so.

## 3. Identity and state

### What is true in the code today

The leads in Question 4 of the working notes, checked against `main` at `611339da1`:

| Lead | Now |
|---|---|
| `ViewIdentity` compares metatypes | **True.** `IdentityNode.Step` holds `.typed(Any.Type, index:)` and `.keyed(Any.Type, key:)`; `stepsEqual` and the hash use `ObjectIdentifier` of the type (`Sources/TUICore/Rendering/ViewIdentity.swift`). |
| `StateKey` uses declaration order | **True.** `PropertyWalk.applyLeaf` gives `@State`, `@FocusState` and `@Namespace` the next `ownIndex`. `StateKey.propertyIndex` is that number. Nested properties are keyed by `scope`, which `NestedScope.container(at:ofType:in:)` folds from a position and a *metatype address*. Negative indices are reserved for the framework (the table on `StateKey`). |
| A changed type at a key | **Handled, by dropping.** `StateStorage.box(for:default:softly:)`: `values[key] as? StateBox<Value>` fails, a fresh box replaces it, and the old one is `markDropped()`. That is the natural place for a conversion. |
| Static caches keyed by type | **True, but mostly harmless under B.** See the table below. `ValueHashPlans` is no longer process-wide: `TUIContext` makes one per context (`.tui()`). The process-wide ones are `PropertyPlans`, `BodyWitnessMemo`, `HandOverAnswers`, `typeNameCache`, and small `verified`/`descending` sets. |
| `RenderLoop` generic over the scene | **True** (`RenderLoop<A: App>`), and **it no longer matters**: under B, `A` does not change. |
| Lifecycle tokens are path strings | **True.** `lifecycleToken(_:_:)` is `"\(prefix)-\(identity.path)"`. |
| The traits remove what an image needs | **In release, by design.** But on Swift 6.4's default build system in debug too: section 5. |

And one lead that was missing: **`V.Body.self` is in the identity chain.** `renderToBuffer` descends with
`context.withChildIdentity(type: V.Body.self)` (`Renderable.swift`), and `V.Body` for a stack is a deep
generic type holding everything below it. Adding a `Text` to a `VStack` changes that step's metatype, and with
it the identity of everything below it, whichever mechanism is used. Erasure stops this at the app's own
`body`, which becomes `AnyView`, but not at the framework's `VStack<Content>`, which is not erased.

### Stable keys in a session

SwiftTUI translates: a snapshot, a rehearsal render to find the new tree, and a matching of old owners to new
(`HotReloadReplay`, `HotReloadSession.replace`). Question 4 proposed the same for TUI. But there is a simpler
way: **in a session, make the keys stable in the first place, so there is nothing to translate.** The app
launches in session mode, and identities are built that way from the first frame.

None of this subsection has been built [inferred]. The proof of concept ran without it: `SliderPage`'s
`@State` survived because its identity sits above the edit, while anything held below the edited `VStack`
would have reset.

**Identity by logical name.** In a session, an `IdentityNode` step compares and hashes not by the metatype but
by a small integer for the type's *logical name*: `String(reflecting:)`, minus generic arguments, minus any
`_R<n>` module suffix. So `VStack<TupleView<(Text, Child)>>` and `VStack<TupleView<(Text, Text, Child)>>` are
the same step, and so are `Example.Child` and `Example_R3.Child`. The mapping is a pure function of the type,
memoised by metatype address, in the same way as `typeNameCache`: the exemption in the "no singletons" rule
for a private, bounded, process-wide memo of a pure function, and it is bounded because generations are
capped. `renderPath` uses the same names. Two strings built from it then also stop changing with a body edit:
**focus IDs** (`"button-\(context.identity.path)"`) and **lifecycle tokens**. That removes most of what would
otherwise need translating, at one site.

**State by property name.** In a session, `PropertyWalk.applyLeaf` keys an own property not by `ownIndex` but
by an integer interned from the property's *name* (`_volume`), taken from `RuntimeFields`, which already reads
field names from the runtime's metadata, starting well above the small constants the cores use. Adding a
`@State` above another, reordering them or removing one changes no other key. `NestedScope.container` folds
the field's name and logical type rather than the position and address, and `enumCase` already folds a label.

**Both are one `#if DEBUG` branch at the place the key is made**, read from a flag set once at launch. Outside
a session they are what they are today. In release they do not exist, so the frame budget is not touched: no
field on `RenderContext`, whose cost this project has measured, and no cost on any path that a release build
runs.

What this does not cover is **a sibling index that shifts**: adding a `Text` before a stateful `Child` in a
`VStack` moves it from `Child.1` to `Child.2`, a real change of structural identity. A narrow rule handles it:
during the reload frame only, when a box misses at a key and an unclaimed old box exists under the same parent
with the same logical type and property name, take the lowest-index one. The walk visits in order, so this
gives the matching one would expect, and keys that hit exactly are reserved first, so that a failed match
cannot steal a box another view still owns (SwiftTUI reserves exact owners first too) [read]. Two children of
one type with one inserted before both still shift by one, and that is accepted.

An identity's `String(reflecting:)` is safe to use like this, since `Example_R1.Child`'s reflected name
includes the image's module name [measured, B: `App_R1.Model`], and private types' discriminators come from
the file name, not the generation [inferred].

**How this is tested:** the whole suite and `Stress --selfcheck` with the flag on (section 7). Anything that
fails shows where something relied on a metatype in a step, for instance a state reset across `Foo<A>` to
`Foo<B>` at one position, where a session would keep the box if the value type is unchanged. That is a
difference only in a debug session, and arguably what one wants there.

### What happens to values

At `StateStorage.box(for:default:softly:)`, where today's code drops a box of the wrong type, a session asks
in turn:

1. **The same `Value` metatype:** the box is reused, as it is on every frame. This covers `Int`, `String`,
   `[String]`, `Date`, every dependency's types and, under B, every app type that was not re-declared. No
   `Codable`, no copying.
2. **The same logical type, a different metatype** (a type re-declared in this generation, or one declared in
   an earlier image): convert. **Memberwise by name** first: walk old and new fields with `RuntimeFields`, and
   where every field in the new type has an old one of the same name and either the same metatype or a
   convertible one, build the new value and copy each field with its value witnesses. New fields need their
   default, which reflection cannot run, so a new field without a value blocks this unless the new default
   `init()` exists to start from. Then **`Codable`**, if both are, for what memberwise cannot do. SwiftTUI's
   `SnapshotEncoder` shows the machinery; `JSONEncoder` is enough here. Otherwise reset.
3. **Anything else:** reset to the new default, and report.

**Reporting.** Every reset is one line in `diagnostics.log`, with the view's path, the property, and why:
`SliderPage._volume: reset (Double → Int)`. The banner counts them: `✓ reloaded in 1.1 s · 2 values reset`. A
property newly added is not a reset, and one that went away is noted at the end of the frame. `events.jsonl`
keeps the same for tests.

### What must be cleared, and what need not be

Under B the metatypes of unchanged types do not change, and no image is ever unmapped, so **a cache whose
answer is a fact about a type stays right**. New types add entries. What must go is anything derived from
running app code. Inventory, with where each lives:

| Store | Scope | At a reload | Why |
|---|---|---|---|
| `RenderCache`: entries, size entries, `erasedContent`, `appliedEnvironment`, `hostedMembers`, leases, revalidation | per `TUIContext` | **`reset()`** | These are drawings made by the old code, keyed by type, identity and value, none of which changed. Measured in `Example`: 0.07–0.8 ms, and the first frame after it was 14–50 ms under load |
| `MemoizedView`'s and `ValueMemo`'s entries | in `RenderCache` | Goes with it | The same |
| `ValueHashPlans` | per `TUIContext`, keyed by metadata address | Keep | "A plan is a fact about the type" (its doc comment), and the type's layout has not changed. A re-declared type is a new address |
| `PropertyPlans`, `TypeWalk.verdicts`, `EnvironmentStamp`'s rules, `RenderCache`'s `eligibilities` and `equalities`, `typeNameCache`, `PropertyWalk+Access`'s `verified`, `StaticMemberCount.descending` | process or context, keyed by metatype | Keep | The same |
| `BodyWitnessMemo`'s permanent memos, `HandOverAnswers` | process, keyed by metatype | Keep **because of the eraser** | Their answers read through `V.Body`. In a session `V.Body` is `AnyView` for every app view, before and after, so the answer cannot change. Without the eraser these would be wrong, and they have no clear path |
| `TextWrapping`'s, `Text+Markdown`'s, the colour and ramp caches, `ASCIIPalette`'s index, `AssetCatalog`, `LightDarkColorTable` | process | Keep | Pure functions of values, with no app code in them |
| `StateStorage.values`, the boxes | per context | **Keep**: this is the point | |
| `objectHubs` | per context, keyed by object | Keep | An object's hub is about the object, which has not changed |
| `trackedValues` (`onChange`) | per context | Keep | So `onChange` does not fire for a value that did not change. A new `onChange` starts with no tracked value, as it does now |
| `lastConditionalCase`, `optionalPresence` | per context | Clear | They only save work; a miss costs one flip's bookkeeping |
| `AnimationStore`, `DepartureStore`, `PlacementStore`, `AnimationCompletionTracker` | in `StateStorage` | Clear; completions fire now | See below |
| `KeyEventDispatcher`, mouse regions, the shortcut registry, the focus registrations | per frame | Nothing | Rebuilt by the walk |
| `NavigationCoordinator.builders` | per stack | Keep | Re-registered as the destination modifier renders; one from old code is valid until then |
| `CustomAnimation`'s registry | process, keyed by value | Keep | A curve is a function of the value |

`StateStorage.reset()` and `LifecycleManager.reset()` are not what is wanted, since both throw state away. A
session adds one small function, `prepareForReload()`, beside them. A store that holds drawings or closures
from app code and is not on this list is a bug, which is why section 9 asks new ones to follow the same
pattern.

### Focus

`FocusManager.focusedID` is a string, by default `"prefix-\(identity.path)"`, or the app's `.focusID`. With
logical names the default stays the same across any body edit that keeps the control's position, so focus
simply stays [inferred]. If the control has gone, the existing recovery runs (`FocusManager.endRenderPass`) as
it does when any focused view leaves. An explicit `.focusID` is unaffected throughout. The `FocusState` slots
are ordinary state, keyed by name.

### Scroll offsets

`ScrollViewHandler` and `ItemListHandler` are objects kept in the state store under the view's identity, with
stable keys, so they are simply still there, offset included, and clamped on the next frame if the content
shrank (`clampScrollOffset`) [inferred]. Nothing is needed. Scroll anchoring's state is the same.

### Animations in flight

A reload is a jump cut. An animation's `from` and `to` were computed by old code, and there is no sensible way
to continue it, so: clear the three stores, run the completions, and draw the reload frame with animations
disabled, so that a layout change does not glide. Repeating animations restart from the new code on that
frame. `TimelineView` and the pulse have no state to lose.

### Lifecycle

| | After a reload | Why |
|---|---|---|
| `onAppear` | **Not re-fired** for a view that keeps its identity | The view has not appeared. It may have set state up, which would be done twice. Flutter does the same for `initState` |
| `onDisappear` | Not fired, unless the view is really gone from the new tree, and then yes, with whatever closure was last registered | Tokens are stable under logical names |
| `.task`, `.task(id:)` | **Cancelled and restarted if the owning view's code was replaced in this generation**; otherwise left running. `TaskModifier` compares the generation stamped on the running task with the generation of its view's file, which the session knows | An edit to a `.task` body should do something, and a task must already tolerate cancellation. The alternative, leaving it, is that editing a loop in a `.task` has no effect, which is the first thing someone would try. This is HR-4 |
| A new `onAppear` or `.task` on a view that already existed | A new token, so it fires | It is new |
| `App.init`, `@main`, `main.swift` | Never again | |
| Scene phase | Unchanged | |

**`effectStage`:** none of this touches the discard machinery, since the reload frame is a normal frame.

### When the swap happens

At the top of `AppRunner.runLoop`'s iteration, beside `signals.consumeResizeFlag()`, on the main actor. There
is no render in progress, nothing is borrowed, and `dlopen` runs to completion before the next render. A task
on another thread can observe the moment when some of an image's replacements are in and others not, which is
harmless: each is a single pointer write, and the two halves are valid functions [inferred; the runtime's
registration was not read]. A `Mutex` the app holds across a call is not disturbed.

Reload during ⌃Z, which stops the process: the compile finishes and the image waits for the resume. With a
sheet open, or during a drag: the state is state, and the walk redraws it.

## 4. The trigger

The owner's order of preference: the app, launched in this mode, watches the files itself with what the OS
offers; polling where that is missing or troublesome; and a signal as the backstop, on which it checks
modification dates itself. This section is that, with one change: the signal is not `SIGHUP`.

### Which files

The session's manifest (section 6) lists the source directories of the reloadable targets, which is every
Swift target of the root package except test targets, and the files that make any change a relaunch:
`Package.swift`, `Package.resolved`, `.swift-version`. Watching a directory rather than a file matters,
because most editors save by writing a temporary and renaming it over the original, which ends a watch held on
the file.

A change event only says *look*. What decides whether there is an edit is the file's content hash against the
last one compiled, since a format-on-save writes twice, `git checkout` touches files it does not change, and a
modification date can go backwards. SwiftTUI's driver re-reads every file in every source directory and every
dependency every 50 ms (`sourceSnapshot`, `dependencySnapshot` in `ReloadDriver.swift`) [read]. That is simple
and it works; nothing here does that, because the watchers make it unnecessary, and in the polling fallback a
`stat` of each file is enough to know which to read.

### The watchers

Nothing like this exists in the tree yet: a search of `Sources` and `Tools` for `FSEvent`, `inotify`,
`kqueue`, `makeFileSystemObjectSource` finds only the comments in `StdinArrivalStream.swift` and
`SignalManager.swift` about how libdispatch works [read]. So this is new code, with one small protocol,
`SourceWatcher`, and an arm per platform, all in `Sources/TUIApp/App/HotReload/`, each in its own file, as the
project's rule for POSIX-only code asks.

| Platform | Watcher | Notes |
|---|---|---|
| macOS | FSEvents: `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`, `FSEventStreamSetDispatchQueue` | Part of CoreServices on every macOS TUI supports, so no new dependency; recursive with one stream. From a write to the callback, plain or by rename: 12 ms median, 88 ms worst of 40, with a 50 ms latency setting and `kFSEventStreamCreateFlagNoDefer` [measured]. A latency setting of 0 was oddly slower, at about 70 ms. |
| Linux | `inotify_init1(IN_NONBLOCK \| IN_CLOEXEC)`, read through a `DispatchSource` read source | In Glibc and Musl, so no new dependency. Not recursive: one `inotify_add_watch` per directory, and `IN_CREATE` of a directory adds another. Watch for `IN_CLOSE_WRITE`, `IN_MOVED_TO`, `IN_DELETE`, `IN_CREATE`. `ENOSPC` means `fs.inotify.max_user_watches` is used up: fall back to polling and say so. [inferred: not run; no Linux box was reachable for this document] |
| Anywhere else, or either of the above failing | Polling: every 500 ms, `stat` each known file and list each directory | Also the choice wherever events do not arrive: a network volume, a bind mount into a container, WSL's `/mnt/c`. `TUI_HOT_RELOAD_POLL=1` asks for it outright. A hundred-odd files is a negligible cost at that rate [inferred]. |
| Windows (later) | `ReadDirectoryChangesW` | `TUIApp` has no Windows build, so this waits for it. |

A watcher that starts and then hears nothing cannot be told from a developer who is not typing, so the
banner's first line after launch says which watcher is running, which tells someone on a network volume why
nothing happens.

### The signal: `SIGUSR1`, not `SIGHUP`

`SIGHUP` is wrong here, for a reason specific to how TUI behaves:

- `SIGHUP` is what a terminal closing sends. Closing the window or losing the SSH connection delivers it to
  the session's foreground process group.
- TUI has no handler of its own for it. `FatalSignalTerminalRestore.terminatingSignals` lists it among "the
  quiet terminations": taken only where the disposition is still the default, the debt to the terminal paid,
  and the signal raised again so that the process ends [read: `FatalSignalTerminalRestore.swift`,
  `installIfNeeded`]. The docs say the same (`AppLifecycle.md`).
- And `SIGHUP` is the *only* thing that ends the app when the terminal goes. A hang-up on standard input does
  not: `StdinArrivalStream.handleReadable(reportedBytes:)` cancels the read source at end of input and
  deliberately wakes nothing, and the loop runs on, and I found nothing else that exits on a hang-up [read].
  So an app that took `SIGHUP` as "check for changes" would, when its terminal closed, stay alive for good
  with no terminal, holding its watchers and starting compiles.

One could tell the two apart by asking whether the terminal is still there (`tcgetattr` on standard input
fails once it has gone) [inferred], but that is a race and a heuristic in the path that decides whether a
process dies, to save nothing: the daemon convention `SIGHUP` borrows from is for processes with no terminal.

So: **`SIGUSR1`**, registered through the same `SignalManager.register` as the others, as a new `Kind`, only
in a session. SwiftTUI's driver uses `SIGUSR1` as well, though for delivery rather than as a backstop
(`ReloadDriver.runSession`, `kill(process.processIdentifier, SIGUSR1)`) [read]. What it costs and how each
cost is met:

- Its default action terminates, so a `kill -USR1` sent to the same app *not* in a session ends it (terminal
  restored, through the same `FatalSignalTerminalRestore` path). That is why `TerminalHost.swift`'s tmux hooks
  chose `SIGWINCH` instead, for a PID that may have been recycled [read]. The cost is acceptable for a command
  a developer types at their own debug app. `tui-dev signal` looks the PID up in the session directory rather
  than asking for it.
- The app might use `SIGUSR1` itself. `TUI_HOT_RELOAD_SIGNAL=USR2` picks the other one. A session never takes
  a signal whose disposition is no longer the default at launch, and says so on the banner.
- Install order is already right: `AppRunner.runLoop` calls `signals.install` before
  `terminal.enableRawMode()`, and `installIfNeeded` skips a signal that no longer has its default disposition.
  `SignalManager.register` sets `SIG_IGN` on Darwin, and libdispatch installs its handler on Linux, so
  `FatalSignalTerminalRestore` leaves it alone on both [read; the Linux half inferred from `SignalManager`'s
  comment].

What the signal does is what the owner asked: walk the known files, compare modification dates and sizes, read
and hash what differs, and proceed as if a watcher had said so. It also resets a stuck state: a compile that
has not returned in 60 seconds is killed.

### Debouncing

- **100 ms of quiet** after the last event of a burst, restarted by each new event. An editor's save, a
  formatter's second write and a burst of `git checkout` all land within that. SwiftTUI uses 200 ms [read];
  this budget cannot afford it.
- **A new edit during a compile cancels that compile** (`SIGTERM` to the process group) and starts again,
  keeping the time of the first unreloaded edit. A result whose inputs have changed since it started is thrown
  away rather than loaded, which SwiftTUI's driver also checks, repeatedly (`observed != candidate`) [read].
- **A burst of many files** (more than, say, 20) is a branch switch or a refactor, and the banner says "many
  files changed: relaunch" rather than trying.

### When the build fails

The old code keeps running, the app stays fully interactive, and nothing is loaded. An app that stays usable
through a typo is half of what makes this nicer than a relaunch.

The errors must not wreck the screen. TUI owns the alternate screen, and anything written to `stderr` lands in
the middle of the frame with nothing to erase it, which is what `SystemURLOpener`'s comment records for a
child's output [read]. So:

1. The compile's output goes to `<session>/diagnostics.log` in full, and the child's standard input, output
   and error are never the terminal. It runs in a process group of its own, so that it cannot be stopped by
   touching the terminal, and so that it can be cancelled whole.
2. A **banner**, one row, drawn by the render loop into the frame as the status bar is
   (`RenderLoop+StatusBar.swift`), so through `FrameDiffWriter` and not around it: `✗ SliderPage.swift:42:
   cannot find 'volumee' in scope (+2 more) — old code running`. It carries the `file:line` as an OSC 8 link
   where the terminal has them (`TerminalHyperlink.swift`), and it does not take a row from the page: it draws
   over the bottom row, because a banner that re-lays out the page would make every keystroke in a broken file
   reflow the app being looked at.
3. A session key, `⌃⌥E` by default and only in a session, opens the whole diagnostics in a full-screen
   scrolling overlay, closed with Esc. This is the keyboard route the project's rule asks for. An app that
   binds the chord wins; the banner names the key in use.
4. `tui-dev logs` in a second terminal follows `diagnostics.log`. On exit, an unresolved failure is printed to
   `stderr` after the terminal is handed back, through the same path as `SoftTrap.holdUntilTerminalRestored`.
5. When a later compile succeeds, the banner says `✓ reloaded in 1.1 s` for three seconds and goes.

The same banner carries the other reports: what reset (section 3), what needs a relaunch, and that a manifest
changed.

## 5. The time budget

The owner's limit: "if it takes more than a second or two, then it becomes an irritation". This is the
riskiest part of the design, so this section is all numbers, and they are from a busy machine. **Every figure
below was taken while other agents were building and testing on the same 14 cores**, at a load average mostly
around 7–16, with Xcode's Swift 6.2.4 unless stated. They are single runs or small handfuls, not benchmarks,
so read them as "about this much", and expect a quiet machine to do better [inferred].

### What `Example` is

34,000 lines in 136 Swift files, about 14,000 of them generated localization tables, with a 74 MB debug binary
and about 30 modules of TUI under it. A realistic app, on the view-heavy side. No third-party app was
measured.

### Going through SwiftPM, or compiling the target: not possible

| What | Time |
|---|---|
| `swift build`, clean, `-j 6`, all modules | 120 s |
| `swift build` with nothing changed | 6.1 s, and 20.5 s on another run |
| `swift build`, a one-line change in a `body`, small page (128 lines) | 9.9 s |
| `swift build`, a one-line change in a `body`, the largest page (817 lines) | 6.5 s |
| `swift build`, a new member on `DemoSection`, used by most pages | 11.1 s |
| The final link alone, from SwiftPM's own plan | 3.3 s |
| **The whole target compiled into one image**, the SwiftTUI mechanism: 136 files, no batch mode | **70 s** objects + 0.3 s link |
| The same, batch mode, `-j 6` | **74 s** + 0.3 s |
| The same, `-wmo -num-threads 6` | **22 s** |

So **a whole-target recompile cannot make this budget on an app this size, by a factor of ten or more**, on
any setting, and going through `swift build` cannot either, with the overhead of planning and of linking a 74
MB binary. This is the measurement Question 4 asked to be made first. The reload path must call the compiler
directly and link only a small image. SwiftTUI's `compileApplicationImage` does call it directly, but with the
whole target, and also starts `swiftly run swift --version` twice around each compile [read; its cost not
measured].

### One file: comfortably possible

| What | Time |
|---|---|
| An empty file importing nothing, compiled and linked into an image | 0.22 s |
| An empty file `import TUI`, type-check only | 0.14 s |
| An empty file `import TUI`, compiled and linked into an image | 0.43 s |
| **The real thunks of `SliderPage`** (three replacements, and one) against `Example`'s module, compiled and linked in one step, about 20 runs outside the window described below | **0.46–1.39 s, typically 0.6–0.9** |
| The same on Swift 6.4.0, native build system, 5 runs | 0.60–1.43 s |
| The same on Swift 6.4.0, default build system, 9 runs | 0.56–1.77 s |
| The normal per-file compile for comparison: one `-primary-file`, the other 135 files parsed, object only | 0.42–0.58 s `SliderPage`, 0.83–0.96 s `LayoutPage` (817 lines), 0.68–0.95 s `ButtonsPage` (648 lines) |

So importing the framework is cheap, because module loading is lazy: 0.2 s over importing nothing. Importing
`Example`'s own module on top of that costs next to nothing. That is why this should not grow with the size of
the app [inferred, from `Example`'s size alone].

**Across every file.** To see more than one file, I compiled each of `Example`'s 134 files on its own as the
source of an image, against the module, with reload flags: the whole file re-declared under a new module name,
which is the same type-checking and code generation as a thunk of every function in it, with no generator
needed. 124 compiled; 10 did not. The one I looked at, `LayoutPage.swift`, stopped at "cannot find
'lazyGridsSection' in scope": a re-declared type loses the members its other files add, which is what section
2's mention closure is for.

| Of the 124 files | Compile and link one image |
|---|---|
| Median | **0.63 s** |
| 75th percentile | 0.94 s |
| 90th percentile | 1.63 s |
| Under 1 s | 97 |
| Under 2 s | 113 |
| The largest hand-written pages | `OverlaysPage` (691 lines) 1.11 s, `MousePage` (679) 1.04 s, `ButtonsPage` (648) 1.83 s, `ProgressViewPage` (521) 1.23 s |
| The largest generated file, `Strings_g1` (2,545 lines) | 7.5 s |

Of the eleven over 2 s, seven (`ShapesPage` 49 s, `ShadowsDemo` 34 s, `SpinnersPage` 8 s, `ShortcutsDemo` 8 s,
`ScrollViewPage` 7 s, `TextEffectsDemo+Matrix` 5 s, `SliderPage` 4 s) fell in one window of about two minutes
in which everything slowed: the same `SliderPage` is 0.6 s every other time, and a separate job running at
about that time took 50 s and 29 s for its usual 0.6 s compile (I did not line up their clocks), at a *low*
load average of 4–7. I do not know what that window was. It looks like waiting rather than work. Both jobs
shared a module cache and that is one suspect, but it is not established. A window like that, in real use,
would simply be a slow reload; with the cancel-on-new-edit rule nothing is corrupted by it.

**Cold caches.** The first compile with a given set of flags takes 10–20 s (9.5 s, 12.0 s, 13.8 s and 20.4 s,
measured) because the compiler builds the SDK's Clang modules for those flags. After that it is quick. So:
`tui-dev` warms a **private module cache** at session start with one empty compile, and every reload uses the
same flags. *Private* because after thunks compiled with SwiftPM's `-module-cache-path`, the next `swift
build` recompiled everything, 1,453 compile jobs and 210 s. That happened once and its cause is not
established. Not sharing the cache removes the question.

### Where one image's time goes

| | Type-check only | Object (type-check and code generation) | Link alone | One step, `swiftc -emit-library -g` | One step, no `-g` |
|---|---|---|---|---|---|
| `SliderPage` thunk | 0.17–0.41 s | 0.22–0.50 s | 0.17–0.27 s | 0.66–1.25 s | 0.27–0.39 s |
| `ButtonsPage`, whole file | 0.27–0.38 s | 0.47–1.0 s, 2.2 s once | 0.17–0.32 s | 1.03–2.0 s | 0.70–1.0 s |
| `MousePage`, whole file | 0.34–0.56 s | 0.53–0.76 s | 0.17–0.25 s | 1.14–2.2 s, 4.3 s once | 0.56–1.0 s |

Each cell is four to eight runs in two batches, at load averages of 6–16, and a few stray high values are left
out of the no-`-g` column. Look at the object, link and one-step columns together: **object plus link is less
than the one step, by 0.3–0.7 s**. The object with and without `-g` costs the same, so debug information
itself is not the cost. `swiftc -emit-library -g` also runs `dsymutil` at the end (its job list shows one)
[measured]. A reload does not need a dSYM, since lldb can read the object's debug info where it lies. **So the
session should compile and link as two steps, and this document's "one step" figures, including the 0.63 s
median, are pessimistic by about that much.** With two steps the three files above come to about 0.45 s, 0.65
s and 0.75 s [sum of measured steps; not run as one sequence].

### The breakdown: edit to redraw

| Step | Time | Mark |
|---|---|---|
| Save to watcher's callback, FSEvents with a 50 ms latency and `NoDefer` | 12 ms median, 88 ms worst, of 40 | measured |
| Debounce | 100 ms | a choice |
| Spawn `tui-dev compile`, parse the file old and new, classify, generate | about 50 ms | inferred, not built. SwiftParser is fast on one file; process start is the larger part |
| Compile the thunk to an object | 0.25–1.0 s; a typical file 0.5 s | measured |
| Link | 0.2 s | measured |
| `dlopen` of a freshly written image | **0.10–0.14 s** typically. 16 samples: 11 in that range, 2 at 0.2–0.3 s, 3 at 0.9, 2.7 and 3.9 s, the last three in the first two cycles | measured |
| State translation | Nothing as a step, since keys are stable (section 3). A conversion happens inside the frame, for a re-declared type only | inferred |
| `RenderCache.reset()` | under 1 ms | measured |
| First frame with new code | 12–52 ms on `SliderPage`, and one of 333 ms at a load average of 34 | measured |
| **Total, typical file** | **about 1 s** | |
| **Total, 90th-percentile file** | **about 1.5–2 s** | |
| A large or slow-type-checking file | 2–3 s | |

So the budget looks reachable for most edits and is at risk for the largest files. The `dlopen` figure is
interesting: the same images load in 0.4–3 ms when they have been loaded before, in the same run or another,
so the 100 ms is not symbol binding; it is something the system does once per new file, plausibly a
code-signature or policy check [inferred]. It is a tenth of the budget, and worth a look in stage 1, and the
multi-second outliers more so, but neither decides anything.

### Is the budget met for what people actually edit?

The figures above replace or re-declare *every* function in a file. An edit changes one. Unchanged functions
need no replacement at all, since the old versions are correct, so stage 3 can **generate replacements only
for what the diff says changed**, and the time then follows the size of the edit rather than the size of the
file. That is the first thing to do if large files overrun. The floor is about 0.4 s plus the edited
function's own type-checking. Not measured, because the generator does not exist, but the empty-file row above
is the floor's measurement, and it is what makes this believable.

**If that is still not enough, in order of what they would buy:**

| Remedy | Would buy | Cost | Evidence |
|---|---|---|---|
| Compile and link in two steps, no dSYM | 0.3–0.7 s | Nothing | measured above. **Do this from stage 1** |
| Replace only changed functions | Most of a large file's time | A little more classifier | inferred |
| Several files in one generation: one frontend per file in parallel, `-j` | Keeps a multi-file generation near the time of its slowest file | Nothing | inferred |
| A private, warm module cache | Avoids the 10–20 s and the rebuild above | Nothing | measured above |
| Narrower imports in the thunk, as Previews does (`import struct X.Y`) | A share of `import TUI`'s 0.2 s | It can break a thunk: the same write-up blames it for a preview crash | doc, not measured |
| Less debug info: `-gline-tables-only` | Little: object time did not change with `-g` at all | Worse debugging | inferred from the table above |
| A compile server: a long-lived process with the imports loaded | At most the 0.2 s of import plus process start | Large. `swift-frontend` has no such mode, and it would be a compiler change or a fork-server hack around one. **Not justified by these numbers** | inferred |
| Explicitly built modules | Removes the module-cache question | SwiftPM's support changes between versions, and swiftbuild's defaults differ | not measured |

**Not a remedy:** batch mode or `-wmo` for the whole target. Those help a target compile, which cannot reach
the budget anyway.

### Swift 6.4, and a problem found there

The owner's priority for compile time is 6.4, and the small probe applies its replacements the same way on
6.2.4, 6.3.3 and 6.4.0. `Example` built and reloaded on 6.4.0 with `--build-system native`, end to end, and
the thunk took 0.60–1.43 s, the same order as 6.2.4 [measured].

**On 6.4's default build system, Swift Build, the app built but the image would not load:** `symbol not found
in flat namespace '_$s13TUIFoundation10ScrollViewVMn'`. This has three parts, all measured:

1. `swift build --help` on 6.4.0 lists `swiftbuild` as the default and `native` as "deprecated", and Swift
   Build writes **no `description.json`**. So a driver that depends on that file, as SwiftTUI's does, has a
   limited future, which section 6 allows for by reading compile commands from `-v` output instead. The module
   files are elsewhere too: `Example.swiftmodule` sits under `out/Intermediates.noindex/`, not beside the
   others.
2. The debug link there carried `-unexported_symbol _$s13TUIFoundation*` and its siblings. **The trait
   `UnexportTUISymbols` is being applied in a debug build.** `Package.swift` conditions it on
   `.when(platforms: [.macOS], configuration: .release, traits: ["UnexportTUISymbols"])`, and its comment says
   debug builds "compile and link as before". That holds on the native build system and, on this evidence, not
   on Swift Build. `-internalize-at-link` did not appear in the compile commands. This matters beyond hot
   reload, since the trait's documented behaviour differs between build systems, and it is worth checking
   separately whether it is SwiftPM ignoring the configuration condition for linker settings under Swift
   Build.
3. **With the traits off it works:** `--disable-default-traits` on the build, and `Example` reloaded end to
   end on 6.4.0 with Swift Build (`dlopen` took 2.0 s and 1.0 s that once, which is one more for the outliers
   above). `tui-dev` uses its own scratch path, so it can pass that flag at no cost to anything else.

## 6. Developer experience

### What a developer does

```sh
swift run tui-dev MyApp -- --their --own --arguments
```

(`swift run` can run an executable product of a dependency [inferred, not tried with this package].) That
builds the app in reload mode, runs it in this terminal, and from then on saving a file updates the screen.
`⌃C`, the quit key and everything else behave as they do without it.

Two rules from the owner's brief shape this. There is no swift-argument-parser requirement on anything, and
TUI does not parse an app's arguments: `tui-dev`'s own few options are read by hand up to the `--`, and
whatever follows goes to the app untouched. The app learns it is in a session from one environment variable,
the same kind of thing as the other `TUI_` variables (`TUI_CONFIG_DIR`, `TUI_REDUCE_MOTION`).

### What is in the package

| Piece | Where | Compiled when |
|---|---|---|
| `tui-dev`, an executable product: the first build, the session directory, and `tui-dev compile`, which holds the classifier and the generator and depends on swift-syntax's parser | `Tools/TUIDev` | Only when asked for: SwiftPM builds by target (the note on `TUIMacros` in `Package.swift`). swift-syntax is already resolved for `TUIMacros`, and this adds nothing to a client of `TUI` that does not run it |
| The session: watchers, loader, banner, the frame-boundary swap | `Sources/TUIApp/App/HotReload/`, all under `#if DEBUG` | Debug builds. Absent from release |
| Stable session keys: the logical-identity switch, the name-keyed state index | `IdentityNode` in `TUICore`, `PropertyWalk` in `TUIView`, under `#if DEBUG` | Debug builds. A `#if` around a branch, so absent from release |
| `@_typeEraser(AnyView)` on `View`, and erasers for the other `body` protocols | `TUIView` and each protocol's module | Always, as a declaration. It generates nothing for a function that is not `dynamic`: Joe Groff's description of it says the wrapper is applied for `dynamic` declarations (see the citation in section 1) [doc]. Stage 0 confirms with `nm` that a release binary does not change |

The modules that must keep building on Windows (`TUICore`, `TUIStyling`, `TUIView`, `TUIImage`) get only the
identity and naming switch, which has no POSIX in it.

### How an app opts in

A few lines in its manifest, and no change to its source:

```swift
// What `swift run tui-dev` needs. Nothing here applies to any other build.
let hotReload: [SwiftSetting] = Context.environment["TUI_DEV_BUILD"] == nil ? [] : [
    .unsafeFlags(["-Xfrontend", "-enable-implicit-dynamic", "-Xfrontend", "-enable-private-imports"]),
]
…
.executableTarget(name: "MyApp", dependencies: ["TUI"], swiftSettings: hotReload),
```

`unsafeFlags` is allowed here because the root package is the one using it. SwiftTUI's user adds a `@_cdecl`
root export to their source, guarded by `#if` (`Compiled-Hot-Reload.md`) [read]. Here there is no root export,
because the app's own `body` is replaced like anything else, and the render loop's `RenderLoop<A: App>` never
sees a new type.

`tui-dev` checks that the flags took effect, by looking in the binary for the replaceable entry of the app's
`App.body` (a symbol ending `TX`, from what I read of the compiler's output; to be confirmed), and if they did
not, prints the snippet rather than failing obscurely.

The alternatives are a decision for the owner (section 10):

- **No manifest edit, with `-Xswiftc` applying the flags to everything.** SwiftPM has no per-target flag on
  its command line, so TUI's own modules would be compiled with implicit dynamic too. That makes the first
  build longer, and every call in the framework slower in that build by an amount not measured here. In
  return, editing TUI's own sources would reload as well, which would be useful to the framework's own
  development.
- **The driver compiles the app's targets itself** after a normal `swift build`, from `description.json` and
  the llbuild manifest. No manifest edit and TUI is unaffected, at the price of depending on SwiftPM internals
  that only the native build system writes, and 6.4 calls that system deprecated [measured]. (SwiftTUI's
  `CHANGELOG` records staying on it for this reason [read].)

### A session, in order

1. `tui-dev` sets `TUI_DEV_BUILD=1` and runs `swift build --product MyApp --scratch-path .build/tui-dev
   --disable-default-traits`, a scratch path of its own, so that a normal build and a reload-mode build do not
   rebuild each other. The first one costs a full debug build of TUI once. Afterwards it is incremental.
2. It writes the session directory, mode 0700, under the scratch path: the compile command for each reloadable
   target (from the build's `-v` output, since `description.json` exists only on the native build system), a
   baseline copy of each source, `diagnostics.log`, `events.jsonl`.
3. It `execve`s the app, with `TUI_HOT_RELOAD=<session directory>`. **There is no parent process left**: the
   app is the foreground process, with no driver to hand the terminal back and forth, which SwiftTUI's driver
   has to do with `tcsetpgrp` and which is a source of trouble [read: `ReloadDriver.runSession`]. Signals and
   the exit status are simply the app's.
4. In `App.main`, under `#if DEBUG`, the app reads `TUI_HOT_RELOAD`. Unset, nothing further happens: one
   `getenv` at launch in a debug build. Set, it validates the directory as SwiftTUI's loader does
   (`HotReloadLoader.init`: owned by this user, mode 0700, no symlink [read]), because what is in it is about
   to be loaded and run, and it starts the watcher.
5. On an edit it spawns `tui-dev compile` with the session directory and the changed paths, with standard
   streams that are not the terminal. That process classifies, generates and compiles, and leaves
   `images/gen-N.dylib` plus a small report.
6. At the next iteration of the run loop (`AppRunner.runLoop`, beside `signals.consumeResizeFlag()`), with no
   frame in progress, the app calls `dlopen`, which applies the replacements, clears what section 3 lists, and
   asks for a frame.

### What is stripped from release

Everything in the session is inside `#if DEBUG`, as SwiftTUI's `HotReloadLoader` is. The traits
`DeadStripUnusedAPI` and `UnexportTUISymbols` stay as they are and are not in the way: they apply only
`.when(platforms: [.macOS], configuration: .release, …)` (`Package.swift`, at the end) [read], so a debug
build keeps every symbol. That is true on SwiftPM's native build system, where Question 4's note that the
driver must turn them off does not apply [measured]. On Swift 6.4's default, Swift Build, the trait's link
flags reach a debug build, and `tui-dev` must pass `--disable-default-traits` [measured, section 5].
`ShippingAnApp.md`'s table of what a `dlopen`ed plugin loses describes the release case. Section 9 lists what
to keep true here.

Setting `TUI_HOT_RELOAD` on a release binary does nothing, because the code that reads it is not there. A test
checks that (section 7).

### The umbrella and à-la-carte products

Nothing depends on which is used. The session lives in `TUIApp`, which `ChoosingProducts.md` says every app
needs, whether it arrives through the umbrella or as its own product. A view library that depends on
`TUIFoundation` and no `TUIApp` gets the switch in `TUICore`, inert. The generated thunks import what the
edited file imported, since they keep its `import` lines (with the file's narrow `import struct X.Y` forms, if
any) and add a private import of the module. `Tools/ProductSmoke` is the place to check a session from an
à-la-carte app.

### Where `TUIMacros` helps, and where it does not

A macro sees one declaration and can neither compile nor load anything, so it is not how a reload happens.
SwiftTUI's `@_cdecl` export is the kind of boilerplate a macro could write, as Question 4 suggested, but this
design has no export to write. Reload needs no annotation in the source, which is better than a macro.

`TUIMacros` matters in one direction: `@Entry` and `@Animatable` are in apps' sources, so the reload compile
needs the plugin flags. They are in the target's compile command, and the compile keeps them. (SwiftTUI
refuses any target using `-load-plugin-executable` or friends; `loadApplicationCommand` [read].) How a
macro-attached declaration is classified is in section 2.

### An optional API, later

Flutter has `reassemble()` and InjectionIII has `@objc func injected()`: a place for an app to redo something
a reload did not re-run. A TUI-specific modifier, `.onHotReload { … }`, separate from any SwiftUI API, would
do; it compiles to nothing in release and runs after the frame that shows the new code. It is not needed for
the first stages, and it is not required for anything else here.

### Xcode

A project built by Xcode is out of scope at first: its build settings, not SwiftPM's, decide the flags. The
mechanism does not care who built the binary, so it is a later addition if anyone asks.

## 7. Testing

Hot reload is hard to test because its failures are memory-unsafe and because a passing unit test proves
little about a real image in a real process. So most of the weight goes on real compiles in real terminals,
with cheaper layers below to catch what they can.

1. **The compiler still does this.** The small programs behind section 1's tables become a canary: compile a
   base, compile a replacement, load it, compare printed output. They take seconds, run on every lane
   including nightly, and they are what warns that an underscored attribute or a hidden flag has moved. On a
   compiler where the canary fails, a session says so and exits rather than loading anything.
2. **The classifier and generator, as plain functions.** Old source and new source in, a level and thunk text
   out. Every row of the table in section 2 is a test, and every language form the generator claims to handle
   has a golden file. These need no compiler, so they are quick. The compiled form of the goldens is checked
   by layer 4.
3. **Session keys change nothing until a reload.** The whole suite and `Stress --selfcheck` run with the
   logical-identity switch on, and the same for the eraser in a target built with implicit dynamic. Frames are
   compared byte for byte against the switch off, over `Stress`'s scenarios and the golden snapshots. Any
   difference is a bug in the switch or in `AnyView`'s parity with what it erases, and the latter is worth
   fixing regardless.
4. **Scenarios: a real compile in a real terminal.** A small fixture package, a script of edits, a PTY and
   pyte, on the pattern of `Tools/Smoke/tui_screens.py`; headless rendering differs from live rendering in
   ways that have bitten before, so these do not go through `TUITesting`. Each scenario gives: edit, expected
   screen, expected report lines. The list starts as:
   - a literal; a modifier; a structural change to a `body`; a helper added and used in the same file;
   - `@State` added above another, removed, renamed, retyped; a class in `@State` keeps its identity;
   - a model in a dependency, a global, a static, a running task, a stored closure: each of section 1's table
     rows;
   - a class's stored property added: refused, old code still running, report says why;
   - a compile error: screen untouched, app interactive, banner right; fix it; reload;
   - rapid edits cancel; a formatter's second write does not reload twice; a file added, a file removed, the
     manifest changed;
   - `SIGUSR1` with the watcher disabled, and polling with the watcher disabled;
   - **closing the terminal ends the process**, which is the regression the choice of signal is there to
     prevent;
   - reload with a sheet open, a menu open, a second window in front, mid-drag, mid-animation, and suspended
     with ⌃Z;
   - focus and scroll position held, in `ScrollView`, `List` and `Table`;
   - a hundred reloads: memory growth, and the "relaunch" notice at the limit.
5. **A differential oracle.** After a reload, the screen must equal what a fresh process shows, given the same
   state. The corpus is free: replay the git history of `Sources/Example/Pages` as a sequence of edits, reload
   after each, and compare with a fresh build at that commit. Where a commit changes a default, or anything
   else a reload deliberately ignores, the report must say so. This finds what nobody thought to write a
   scenario for.
6. **Memos stay honest.** Scenarios also run with `TUI_VERIFY_RENDER_MEMO` and `TUI_VERIFY_MEASURE_MEMO`
   armed, since a stale memo after a reload is the bug class to fear. Those verifiers compare buffers and do
   not see side effects, so they do not replace the scenarios above.
7. **Sanitizers.** Scenarios under AddressSanitizer and ThreadSanitizer on the periodic sweep, with the
   toolchain the sweep already uses for them.
8. **Release is untouched.** `nm` of a release `Example` finds no session symbol; setting `TUI_HOT_RELOAD` on
   it changes nothing; the stripped size is unchanged within rounding. This goes beside the checks in
   `Tools/validate-package-manifest.sh`.
9. **The budget is recorded, not asserted.** Every reload writes its timings to `events.jsonl` (section 5),
   and `tui-dev bench` applies N edits and reports the median and worst. CI does not fail on a clock, since an
   absolute budget tests the machine. What CI does assert is a count: an edit to one file compiled one file,
   and a reload loaded one image.

Lanes: macOS and Linux, on 6.2, 6.3 and 6.4, and the nightlies as advisory. Layers 1 to 3 run per commit, once
the code exists, and layers 4 to 7 on the periodic sweep, since they compile a lot. Windows and WebAssembly do
not run any of it.

## 8. Plan, estimates and risks

Estimates are for one person who knows TUI's code [inferred; nobody has built this]. They are longer than
Question 4's "3 to 5 weeks", and that is the price of the mechanism: Question 4 priced a port of SwiftTUI's
driver and `Codable` replay, which is about stage 5's fallback alone, whereas this needs a source generator
that has to understand a good deal of Swift.

| Stage | What | Useful on its own because | Estimate |
|---|---|---|---|
| 0. Prove it | The canary on every lane, Linux first. `@_typeEraser(AnyView)` and the other erasers. Example's pages and `Stress`'s scenarios rendered with and without erasure, and the differences fixed. This document's compile numbers again on 6.4, and on a real app if one exists by then. | `AnyView` parity bugs are bugs anyway. It finds out cheaply whether Linux works, whether anything has moved since these measurements, and whether the budget holds. **If Linux fails here, the plan changes before much is spent.** | 1 week |
| 1. Body reload | `tui-dev`, the classifier (bodies changed, or "relaunch needed"), the generator for the forms in section 2's table, the `dlopen` at the frame boundary, `RenderCache.reset()` and the store clears, `.task` restart, the report in a log. Polling only, `SIGUSR1`. | The most frequent edits: text, colours, layout tweaks, helper functions. State above an edit survives, state below a structural edit resets and says so. | 3–4 weeks |
| 2. Stable keys | The logical-identity switch and name-keyed `@State`, tested by the suite running with them on. | State survives structural edits and declaration changes. Focus, scroll and lifecycle tokens stop churning. | 1–2 weeks |
| 3. Feels finished | FSEvents, inotify, the debounce with cancellation, the banner, the diagnostics overlay, `tui-dev logs` and `bench`, the scenario suite in CI. A decision on compile speed from real numbers. | It is now something to hand to someone else. | 2 weeks |
| 4. Value types change shape | Re-declaration of value types and the mention closure; value conversion (memberwise, `Codable`, reset). | Adding a `@State` or a `let` to a view stops needing a relaunch, which is one of the most common edits. | 2–3 weeks |
| 5. Reach | New files in a target; more than one target, in dependency order; the whole-target image as an explicit fallback for class changes; relaunch-in-place by `execve` after a rebuild; `.onHotReload`. Each is separable. | Each removes one "relaunch needed". | 3–4 weeks, a la carte |

That is about 3 months to the end of stage 4, with a working, useful tool at the end of stage 2, five to seven
weeks in.

Stage 1 alone is not much more than a demo without stage 2, for state under a structural edit, but its reports
are honest about that. If compile speed disappoints in stage 0 on a real app, stage 3 grows by whichever of
section 5's remedies is needed. A compile server is not in these numbers.

### Risks

| Risk | How bad | What is done about it |
|---|---|---|
| **The underscored parts change or go.** `@_dynamicReplacement`, `@_typeEraser`, `@_private`, `-enable-implicit-dynamic`, `-enable-private-imports`: the compiler's own guide calls use of such attributes outside its repository "STRONGLY DISCOURAGED", and warns that their semantics may change [doc]. | Serious, but debug-only: it would cost the feature, never a shipped app. | Xcode Previews depends on them, so Apple has reason not to break them on Darwin. Upstream's `dynamic_replacement.swift` test runs them on Linux and Windows [doc]. The canary catches a change on the nightly lane, months early. A session refuses to start on a compiler where its canary fails. The whole-target path needs none of them, except `-module-abi-name`, so it stays available as a worse fallback. |
| **Linux does not work as hoped.** Nothing here was run on Linux. The ELF details (an executable's symbols are not in the dynamic table without `--export-dynamic`) are known from SwiftTUI's driver, which does run there [read, doc]. | Would limit it to macOS, which TUI's rules do not accept for long. | Stage 0 tests it first. |
| **Compile time on a real app's big files.** See section 5. | The owner's stated limit: above two seconds it becomes an irritation. | Measured, with remedies priced, in section 5. |
| **Erasure changes behaviour.** `AnyView` in every `body` is not what a release build runs. A debug session laying out differently from a release build would undermine the tool. There is an anecdote of exactly this in SwiftUI (lazy loading in a `List`; a forum post a search surfaced, which I could not find again) [unverified]. | Real: AnyView's measure traps are known in this project. | Stage 0's comparison. A difference is a bug to fix, as it already is for anyone writing `AnyView` by hand. |
| **Misclassification leads to memory corruption.** The probe without an eraser did segfault [measured]. A shape change classified as a body edit would read a field that is not there. | A crash in a debug session. Terminal restored by `FatalSignalTerminalRestore`. | The classifier is conservative: anything other than a function's own body is not a body edit. Before loading, compare the metadata's size and field names, from `RuntimeFields`, against what the generator believed; InjectionIII's equivalent is to compare sizes and block the load (`Reloader.dyload`) [read]. |
| **The generator meets Swift it cannot handle.** `#if` around members, macros, nested types in generic extensions, conformances with `where` clauses, private types with the same name in two files. | Annoying rather than dangerous: the compile fails or the file is refused. | Fall back to "relaunch needed", naming the construct. The differential corpus (section 7) finds the common ones first. |
| **SwiftPM moves.** `description.json` is absent under Swift Build, 6.4's default [measured]; `-v` output has no format promise; and the traits' flags already behave differently there (section 5). | Moderate. | Parse `-v`, as InjectionLite parses Xcode's logs [read]. Check on every toolchain lane. If the format becomes a burden, the manifest snippet can pass what is needed. |
| **Stale things.** A memo keyed by a type whose answer changed; a closure from a previous generation. | The bug class this project already knows. | Section 3's table, `TUI_VERIFY_RENDER_MEMO`, and section 7's differential oracle. |
| **Memory over a long session.** Images are never unloaded, and tables keyed by type grow with re-declarations. | Small: one image was 127 KB in the proof of concept. | A limit (100, as SwiftTUI) and a "relaunch" notice. |

## 9. What to keep true before 1.0

None of this is the feature. It costs little or nothing now, and each item would make the feature much harder
if it went the other way. Nothing here needs doing today, apart from keeping it in mind in review.

**Keep as they are:**

1. **A release-only scope for the two traits.** `DeadStripUnusedAPI` and `UnexportTUISymbols` are meant for
   macOS release builds. A replacement image cannot resolve TUI's symbols otherwise. **This is already not
   true of `UnexportTUISymbols` on Swift 6.4's default build system** (section 5), and it is worth finding out
   why, for its own sake, whatever happens here. SwiftPM's debug default of `-enable-testing` is load-bearing
   for the same reason.
2. **Types in `IdentityNode`.** The `Step` cases carry an `Any.Type`, which is what the logical-identity
   switch maps to a name. An optimisation that replaced it with a hash, or with an interned integer that
   throws the type away, would need a debug escape.
3. **One way into the state store.** Everything reaches a box through `StateStorage.box(for:default:softly:)`
   or `existingStorage(for:)`. That is the single place a conversion can go. A new store of per-view values
   should go through these rather than growing its own dictionary keyed by identity; and one that does need
   its own should forget in the same path as the others (`reset`, `endRenderPass`).
4. **Keys built by `StateKey`, from the walk.** `NestedScope.container(at:ofType:in:)` folds in a metatype's
   address. That is fine, because the switch changes that one function. A second place computing such a hash
   would need the same treatment.
5. **Closures refreshed by rendering.** The framework's stored closures (handlers, disappear callbacks,
   navigation builders) are registered again each frame the view draws. A cache that holds an app's closure
   across frames without that makes it a place where old code outlives a reload. This is the rule `cross-frame
   id capture` already teaches for another reason.
6. **Permanent memos answer questions about types, and hold nothing of the app's.** `PropertyPlans`,
   `ValueHashPlans`, `TypeWalk`, `typeNameCache` and `RenderCache`'s eligibility tables are all facts about a
   type, so they stay right through any reload. A new permanent memo should be the same, or be listed with the
   ones section 3 clears. `BodyWitnessMemo` and `HandOverAnswers` are the ones to watch: they read through
   `V.Body`, which is what the eraser fixes. Those tables also grow with each new type, and are bounded only
   because generations are capped.
7. **No `dlclose` anywhere.** `typeNameCache`'s doc comment already relies on this. Images stay mapped.
8. **The signal table's rule.** `FatalSignalTerminalRestore` takes the "quiet terminations" only where their
   disposition is still the default. That is what lets a session have `SIGUSR1`.
9. **Inputs and effects stay on the run loop's iteration.** The swap needs a moment with no frame in progress
   and no walk under way. Everything being on the main actor, and walks being synchronous, gives that for
   free, and it is worth keeping.

**Cheap to do, if someone is there anyway:**

10. **Fix `AnyView` differences as they are found.** An `AnyView` body must lay out and behave as what it
    erases. Every such difference is a SwiftUI parity bug already (`Tools/SwiftUIProbes` can settle what
    SwiftUI does), and erasure will expose them all at once otherwise. A test that renders Example's pages
    with and without erasure can be written at any time; it needs only a target built with
    `-enable-implicit-dynamic`, and it would be a useful parity check on its own.
11. **Give `Scene`, `Commands` and the other `body` protocols an eraser.** SwiftUI's `View` has one for this
    reason. TUI has `AnyGesture`, `AnyShape` and `AnyLayout`, but no `AnyScene` or `AnyCommands`. Not needed
    before the feature; just don't design them out.
12. **Reserve the names:** `TUI_HOT_RELOAD`, `TUI_DEV_BUILD`, `tui-dev`. Don't use them for anything else.

**To avoid:**

13. **Baking generic type names into anything durable.** `identity.path` holds `String(describing:)` of each
    type. A key persisted to disk from it would change with the switch on. `SceneStorage.swift` and
    `AppStorage.swift` do not read one, and a search found nothing else that does, though that was not an
    exhaustive audit.

## 10. What the owner decides, when this is picked up

Each has a default that the rest of this document assumes.

| Id | Question | Default here | Why you might not |
|---|---|---|---|
| HR-1 | Dynamic replacement rests on underscored attributes and hidden frontend flags, which the compiler's own guide discourages outside its repository. Accept that for a debug-only tool, with a canary on every lane, on the strength of Xcode Previews relying on the same things? | Yes | It could be withdrawn or changed. The fallback is the SwiftTUI mechanism, which has none of this dependency and the weaker survival. |
| HR-2 | How an app opts in: a few manifest lines; or `-Xswiftc` on everything, no manifest edit, TUI's own modules slower in that build and reloadable; or the driver compiling the targets itself, depending on SwiftPM internals. | The manifest lines | No edit at all is nicer for a first-run tutorial. The reloadable-framework variant would serve your own work on TUI. |
| HR-3 | When a class's stored properties change, and nothing can keep the existing objects: tell the developer and keep the old code running; or also offer the whole-target image, which loads the new code at once and orphans the app target's objects. | Tell, and keep running. Stage 5 adds the other as an explicit choice | If you find the refusal more annoying than the loss. |
| HR-4 | Lifecycle after a reload: `onAppear` not re-fired, `.task` restarted where the owning view's code was replaced. | As stated | Keeping every task running is more conservative. Restarting everything is simpler to explain. |
| HR-5 | The signal: `SIGUSR1`. You suggested `SIGHUP` "maybe", and section 4 explains why not. | `SIGUSR1` | You may prefer `SIGUSR2`, or no default signal without `tui-dev signal`. |
| HR-6 | Whether to spend on a compile server (section 5) if the plain compile proves too slow on a real app's large files, or to accept the budget being missed for them. | Decide at stage 3 with numbers from a real app | It is the largest item that is not certain to be needed. |

## How this was measured

All on this machine: Apple silicon, 14 cores, 32 GiB, macOS 15, on 2026-11-01, using a scratch clone of `main`
at `611339da1` so that the worktree stayed clean. Builds went through the build slot (`Documentation/Working
notes/plan/slot.py`), with Xcode's Swift 6.2.4 unless a figure says otherwise. **The machine was shared with
other agents throughout**: the load average was between 4 and 34, mostly around 10–15 on 14 cores, and each
row of section 5 gives it where it mattered. The probes and scripts are kept in `Documentation/Working
notes/hot-reload-probes/`, which is not in the repository.

| Probe | What it is | Used for |
|---|---|---|
| A (`a_rep`) | A library, an app with `Screen`, `Parent`, `Child`, `Model`, `Base`/`Derived`, an enum, a generic, globals and a `private` helper; replacement modules R1 and R2, loaded in turn | Section 1, 2. Also run on swiftly's 6.2.4 (an assertions build), 6.3.3 and 6.4.0, where the replacements applied the same way. Without `@_typeEraser`: segmentation fault. With `-enable-dynamic-replacement-chaining`: the same output. |
| B (`b_abi`) | `Feature.swift` from probe A, compiled whole under `-module-abi-name App_R1` into a library, as SwiftTUI's driver does | Section 1 |
| D (`d_forms`) | Each declaration form, replaced; and those the compiler refuses | Section 2's table |
| E (`e_task`) | A running task across a load | Section 1 |
| The proof of concept (`poc`) | The scratch clone with `@_typeEraser(AnyView)` on `View`, `-enable-implicit-dynamic -enable-private-imports` on the `Example` target, about twenty lines in `SignalManager` and `AppRunner.runLoop` that on `SIGUSR1` `dlopen` the next image, call `RenderCache.reset()` and draw a frame. Driven in a PTY with pyte; two hand-written thunks of `SliderPage` | The claims about `Example` |
| Parity (`poc/compare.py`) | Every page of `Example`, opened by `--page`, in the plain and reload-mode builds, comparing pyte's *characters* (not colours) | 37 of 38 pages identical. The other, Progress & Gauges, shows a bar animated by the clock. This is the first screen of each page only, with no interaction: encouraging, and not the proof that stage 0 needs. |
| FSEvents (`fsevents`) | Write-to-callback latency, plain write and rename-over | Section 4 |

**Not done:** nothing ran on Linux or Windows. No real third-party app was tried. The thunks were written by
hand. `Example`'s pages were compiled whole for the distribution in section 5, as a stand-in for a thunk: the
same type-checking and code generation.

## Sources outside the repository

- SwiftTUI, MIT, `https://github.com/SwiftTUI/swift-tui` at `207913d23`:
  `Tools/SwiftTUIDev/ReloadDriver.swift`, `Sources/SwiftTUIRuntime/HotReload/`,
  `Sources/SwiftTUIGraph/HotReload/`, `Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Compiled-Hot-Reload.md`
- InjectionIII, InjectionNext, InjectionLite (at `4b08bd3`, `Sources/InjectionImpl/Reloader.swift`), Inject:
  `https://github.com/johnno1962/`, `https://github.com/krzysztofzablocki/Inject`
- [Underscored attributes
  reference](https://github.com/swiftlang/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md), and
  [`test/Interpreter/dynamic_replacement.swift`](https://github.com/swiftlang/swift/blob/main/test/Interpreter/dynamic_replacement.swift),
  Swift's repository
- [Dynamic method replacement](https://forums.swift.org/t/dynamic-method-replacement/16619) (the pitch), [Any
  info on the _typeEraser attribute](https://forums.swift.org/t/any-info-on-the-typeeraser-attribute/37826)
  (Joe Groff), Swift forums
- [`SWBPreviewSupport.swift`](https://sources.debian.org/src/swiftlang/6.2.3-1/swift-build/Sources/SwiftBuild/SWBPreviewSupport.swift),
  swift-build 6.2.3
- [How SwiftUI Previews work](https://fatbobman.com/en/posts/how-swiftui-preview-works), Fatbobman, 2023.
  [Behind SwiftUI Previews](https://www.guardsquare.com/blog/behind-swiftui-previews), Guardsquare, 2019.
  [DebugReplaceableView](https://kyle-ye-github-io.pages.dev/posts/debugreplaceableview-multiple-type-erasers),
  Kyle Ye. Third-party accounts of a private system, not Apple's own.
- [Flutter hot reload](https://docs.flutter.dev/tools/hot-reload),
  [Subsecond](https://docs.rs/subsecond/0.7.10/subsecond/)
- Question 4 of `Documentation/Working notes/swifttui-answers-features.md`, the working notes this began from,
  not in the repository. Its recommendation of hot restart first was declined by the owner. Its facts about
  TUI were checked in section 3.
