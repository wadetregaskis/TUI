# Completing the SwiftUI API: decisions from lane SP0

*Lane SP0 carried out steps 0b, 0c and A1 of the module-split plan: the owner's decision of 2026-10-07 to split
TUIkit into à-la-carte modules. The plan is the session notes' `buildtime/split2/plan.md`. A1 added
`Tools/ModuleMap`, which checks the planned map against today's single module; it changed no public API. This file
holds the judgement calls the work reached that the plan did not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SP0-n — needs your decision.** Nothing has shipped for these.
- **B-SP0-n — shipped the safe option.** Says what the fuller version would be, and its price.
- **C-SP0-n — declined.** With the reason.

## B. Shipped the safe option

### B-SP0-1. ViewRenderer stays in TUIkitBase, and K3 stays a refactor to do

*`Tools/ModuleMap/rules.json`, the `declarations` rule for `Rendering/ViewRenderer.swift`*

Plan §1 lists ViewRenderer under Base's rendering infrastructure. K3 then makes it take its terminal, with no
`Terminal()` default, and moves `renderOnce` to TUIkitApp.

Once `renderOnce` is pinned to App, nothing in Base uses ViewRenderer. The assigner then pushes it up into
TUIkitApp, and K3's upward reference disappears. ViewRenderer is now pinned to Base, as the plan says, and K3
stays a scheduled refactor.

**The alternative, and its price.** Let ViewRenderer go to TUIkitApp, and drop K3:
- It saves K3's refactor: two sites, plus `renderOnce` passing `Terminal()` explicitly.
- A headless renderer would then live only in the POSIX module. Today that matters for nothing: every app links
  TUIkitApp, and the test target can import it. It would matter for a future Windows console backend or a
  WASI host that wants ViewRenderer without App.

### B-SP0-2. Twelve pieces of public API stay above their type's module, recorded rather than moved

*`Tools/ModuleMap/rules.json`, `accepted`*

The `public-above` check lists public API placed above the module of the type it belongs to. Plan §4 reviewed
three such placements. One of them, `.safeAreaInset`, it pinned back to Base with a declaration rule, so the check
does not report it. At HEAD there are twelve findings. Each now has its reason in `rules.json`, and the map is
unchanged.
- The plan's other two: `.modal` in Presentation, and `.listStyle` with the row-selection modifiers in Lists.
- `TerminalClient`'s graphics-support API (`graphicsSupported` and its kin) goes to TUIkitApp. It reads what App's
  startup handshake records. Every app imports App, so no app loses it.
- `.automatic` for the List, Picker and NavigationSplitView styles stays in the leaf. It is usable only through
  the leaf's own modifier.
- `ForEach(_:editActions:content:)` and `ForEach(sections:content:)` stay in Lists.
- The four `SceneStorage` / `AppStorage` inits for tab and table customization stay in Tabs and Tables.

`asAnyView()` sits in its own `extension View` block in the same file as `.modal`, and stays in Base.

**The fuller version, and its price.** Move the sugar down beside the types it names at step A4. That means
`.automatic` beside the default styles in Base, and the graphics-support API split from what reads App's state.
It costs:
- about four more declaration-level placements;
- for the graphics API, an injected value in place of the static it reads.

It gains nothing for an app that uses the leaf: the sugar only works through the leaf's modifier anyway.

### B-SP0-3. The check reads the committed map, so a new reference is a finding, not a silent move

*`Tools/ModuleMap/modulemap.py check` against `map.json`*

The assigner moves declarations to make the map consistent. Say new code in Base starts using a Lists helper: if
the check re-ran the assigner, the helper would simply come down into Base and nothing would be reported.

Instead, the check reads the committed `map.json`, so that reference is reported as `upward`. Moving the helper
is then a reviewed edit: `assign`, read the diff, `assign --write`. New files and new declarations are placed by
the rules until the next `assign --write`.

**The alternative, and its price.** Run the assigner in CI (`check --fresh`) and report only what it cannot
resolve. There would be fewer findings, but Base would grow silently with every convenience reference, and the
à-la-carte savings in plan §2 would erode without anyone choosing it. The fresh run costs 0.2 s, so this is a
policy choice, not a cost one.

### B-SP0-4. TerminalHost's `pid_t` signatures are scheduled with K6, not left as a new finding

*`Tools/ModuleMap/rules.json`, `scheduled` K6 and `posix.c_symbols`*

The `posix` check's list lacked `pid_t`, although plan §4's K6 says Windows signatures must not use it. With
`pid_t` in the list, two declarations report it:
- ProcessAncestry, one of K6's two files. Its K6 entry now names `pid_t` beside `getpid`.
- TerminalHost (Rendering/TerminalHost.swift, all of it in TUIkitBase), which plan §4 does not list. About 18
  unguarded uses: the tmux client's `pid` field and the tmux hook and unhook argument builders.

An audit of every C symbol that a declaration outside TUIkitApp references outside a POSIX-only branch found no
other POSIX-only one; the rest are Foundation, Dispatch and libm. The only POSIX-only ones are `getpid` (K6),
`setenv` (K4) and `pid_t`.

The TerminalHost uses are now a second `scheduled` K6 entry. A2's K6 gives them the same Windows treatment as the
other two files. Until then the check reports them as scheduled, not new.

**The alternative, and its price.** Leave them as a new finding. Every CI run would then raise the same warning
until A2, and `check` would exit 1 on HEAD for everyone. The entry costs nothing to drop if you would rather track
it elsewhere. Either way, K6 in A2 grows from two files to three: TerminalHost needs Windows arms for its tmux
helpers, or a platform-neutral process-id type in their signatures.
