# POD-COMPARE: how SwiftUI decides a view's plain-data field changed (O-26)

Measured 2026-11-21 on macOS 15.8.3 (24H241), SwiftUI 6.5.4 (the system framework), arm64; built
with Xcode 26.3 (17C529), Swift 6.2.4, macOS 26.2 SDK. Raw output: `probe.out` (default) and
`probe-sync.out` (run with `AG_ASYNC_LAYOUTS=0`).

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 6 -parse-as-library probe.swift -o probe
./probe > probe.out; AG_ASYNC_LAYOUTS=0 ./probe > probe-sync.out
```

Each case is hosted in an `NSHostingView` (`sizingOptions = []`, 300 x 120) in an offscreen
borderless `NSWindow`; the run loop spins after each write. "Child bodies" counts the child's
`body` runs per step. "Drawn" is found by rendering the hosting view's layer tree into a bitmap and
matching it against bitmaps of `Text(verbatim:)` references of every candidate string; in every
row of every run it matched the value the child's body last saw, so a body that did not re-run
always left the OLD value on screen.

Two parts, kept apart because they measure different compares:

- **Part A**: the value is the parent's own `@State<T>`. That is `@State`'s compare.
- **Part B**: the parent keeps the value in a reference box and bumps an `Int` `@State` tick, so the
  parent's body re-runs every step and the CHILD's view-value compare alone decides the child.

The types: `Item: Equatable { var id: Int; var name: Int }` with `==` comparing `id` only (POD);
`ItemS` the same plus `var note: String` (non-POD). A view is "POD" when every stored field is
(`Double`, `Int`, `Item`); a `String` field makes it non-POD.

## The rules (steady state)

| what is compared | `-0.0` over `0.0` | `.nan` over `.nan` | `Item` with only `name` changed | so the compare is |
|---|---|---|---|---|
| A: write to `@State<Double>` / `@State<Item>` | no re-run | **re-run** | no re-run (stale `name` drawn) | `==` only |
| B: POD view, not Equatable (D1, I1) | re-run | no re-run | re-run | bitwise |
| B: POD view, Equatable, no `.equatable()` (D3, I2) | re-run | no re-run | re-run | bitwise; the conformance is ignored |
| B: POD Equatable view + `.equatable()` or `EquatableView` (D4, I3, I4, I9) | no re-run | **no re-run** | no re-run (stale) | bitwise-equal OR `==` |
| B: non-POD view, not Equatable (D2, I5) | re-run | no re-run | re-run | field by field; POD fields bitwise |
| B: non-POD view, Equatable, no `.equatable()` (D5, I6, D7, I8) | no re-run | **re-run** | no re-run (stale) | the view's `==`, no bitwise short-cut |
| B: non-POD Equatable view + `.equatable()` (D6, I6e) | no re-run | re-run | no re-run (stale) | the view's `==` |
| B: non-POD view, not Equatable, holding a non-POD Equatable field `ItemS` (I7) | | | no re-run (stale) | field by field; that field by its `==` |

An unchanged value (bitwise identical) never re-ran a body in any case. Changing `id` always re-ran
and drew the new `name`. In Part B the parent re-ran exactly once per step in every case.

Reading the `.nan` column against the `-0.0` column separates the three compares: bitwise says
`-0.0 != 0.0` and `nan == nan`; `==` says the reverse; "bitwise-equal OR `==`" says equal to both.

## Surprise: the first compare of each type is bitwise (asynchronous compare layouts)

With the default environment, the FIRST compare SwiftUI makes of a given type in the process behaves
bitwise even where the steady state is `==`; from the second on, the table above holds:

| case | first `-0.0` / first `name` change | later `-0.0` / later `name` change |
|---|---|---|
| A1 `@State<Double>` (the first in the process) | re-run, drew `-0.0` | no re-run |
| A2 `@State<Double>` (the second) | no re-run | no re-run |
| A4 `@State<Item>` first / A5 second | re-run, drew `name=2` / no re-run | no re-run |
| D4, D5, D6 (each a new compared type) | re-run | no re-run |
| D7 = D5's type again | no re-run | no re-run |
| I3, I6, I6e, I7 (new types) | re-run, drew `name=2` | no re-run (`name=2` stays) |
| I8 = I6's type again, I9 = I3's | no re-run | no re-run |

Run with `AG_ASYNC_LAYOUTS=0` (AttributeGraph's switch for computing a type's compare layout
synchronously) and every one of those first rows becomes "no re-run"; nothing else in the output
changes (`diff probe.out probe-sync.out` shows only those rows). So the switch is measured to remove
the effect; that AttributeGraph compares bitwise while a type's layout is still being built in the
background is the explanation the measurement fits, not something read from its source. (I4's
`EquatableView<ItemViewEq>` showed no first-compare effect because I3's `.equatable()` had already
compared the same type.)

Consequence for apps: whether a `name`-only change to an `Item` reaches the screen can differ
between the first and second time a view type is compared, i.e. it is timing-dependent in SwiftUI.

## Not measured

- Views whose fields are closures, classes or existentials (only `Double`, `Int`, `String` and the
  two structs were tried).
- Whether the first-compare effect depends on wall-clock time (a type compared long after launch)
  rather than on order; only order was varied.
- Other platforms or SwiftUI versions: this is macOS 15's SwiftUI 6.5.4 only (the macOS 26 runtime
  was not available on this machine).
