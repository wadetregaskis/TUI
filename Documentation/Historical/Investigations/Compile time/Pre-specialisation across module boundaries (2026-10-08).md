# Pre-specialisation across module boundaries (2026-10-08)

> **Status:** decided 2026-10-08: adopt neither attribute; `@inlinable` (the split plan's tier 2) stays the remedy
> for a hot generic call that crosses a module boundary. Two small non-generic rewrites it suggested landed during
> the split. **Decided:** recommended 2026-10-08 and reported to the owner; the coordinator's ledger records the
> question as decided (no ruling text of the owner's is quoted here). **Working notes** (not in git):
> `PRESPEC/recommendation.md` (with `research.md`, `experiment.md` and the crossing-by-crossing `inventory.md`).

## Question

Once TUI is split into modules, a generic function called from another module runs unspecialised unless the
caller can see its body. Could pre-made specialisations, `@_specialize(exported: true, where …)` or SE-0460's
`@specialized` behind an `#if`, recover the cost instead? The owner, 2026-10-08, asked for an evaluation, and set
its limit: it "only really works if the specializations … are relatively few and predictable".

## Answer

- **SE-0460's `@specialized` does not help other modules.** It first shipped in Swift 6.3, it specialises only
  inside the defining module (a type check at the start of the generic function), and callers in other modules
  still call the generic entry point. On 6.2 it needs `#if compiler(>=6.3)`; `#if hasAttribute(specialized)` is
  false on 6.2.4, 6.3.3 and 6.4.0.
- **`@_specialize(exported:)` does help, narrowly.** It emits a public specialised symbol, and an optimised client
  whose call names exactly that type calls it directly; every other type, every `-Onone` client and every call
  through a witness table gets the generic entry point. It also switches off default cross-module optimisation for
  that function, so a small function that would have been inlined gets an opaque call instead.
- **None of TUI's hot crossings fits.** They are generic over the caller's own views, data and IDs, which
  TUIFoundation cannot name. The few closed sets are better served by an `@inlinable` shim, by making the function
  non-generic, or by nothing.

## Key measurements

A toy library and client, release (whole module, default cross-module optimisation), on Swift 6.2.4, 6.3.3 and 6.4.0,
on the development machine (arm64 macOS 15.8.1 VM); compiler source read at each tag. The crossings come from an
inventory of the split's call sites at main c25452779: 392 callees with 1,846 sites, 95 of them protocol
requirements or stored properties.

| call from the client | what it calls (all three compilers) |
|---|---|
| `f(3)`, with `@_specialize(exported: true, where T == Int)` | the specialised symbol, directly |
| `f("s")`, no `String` specialisation | the generic entry point |
| a library type made generic over a client type | generic |
| a partial specialisation (`T: _Trivial(64)`) called with concrete types | the optimised client's compiler crashes |

Each pre-made body is code every app keeps, used or not, unless TUI is compiled with `-internalize-at-link` (on
macOS release builds by default since 2026-10-11): in the toy, six bodies were about 1,004 B, and the linked
`__text` grew by 868 B.

## Reasoning

A crossing fits an exported specialisation only when it is generic, hot, has a few type arguments TUIFoundation
can name, and has concrete callers. Measured against the inventory:

- **Containers, modifiers, stacks, `Button.init`:** the type arguments are the caller's views; nothing writable.
- **Render-walk entry points:** every view type, and they crossed modules before the split too.
- **The seven `init<S: StringProtocol>` overloads:** `S == String` at every site checked, and the attribute would
  bind on five of them, but an `@inlinable` shim onto a concrete `String` core, as step A3 wrote for `Text`, is
  better: it keeps cross-module optimisation, specialises `Substring` too, and can be written for all seven.
- **`StateStorage.storage<Value>`:** `Value == Bool` for `Button`, `Toggle` and `Picker` would bind; left as a
  candidate to measure first.
- **`TimeSpanSpelling.init` and `TerminalImageStore.placeholderRows`:** generic only in name; made non-generic
  instead.

## What landed

- `ebebe1e42`: `TimeSpanSpelling.init` takes an array of units, which every caller passes.
- `77f690ffa`: a picture's Kitty placement erases its signature in its own module and calls the image store's
  non-generic core (step B5c).
- `_OpacityView.fading`, also generic only in name, was left generic: its one cross-module caller calls it out of
  line, as before the split (decisions
  C-SPB5c-1 in [SPB5c](<../../../SwiftUI parity/Decisions/Module split/Step B5c, carving TUIBitmaps (SPB5c).md>)).
- No `@_specialize` or `@specialized` in `Sources` at 5369ea867. The split's own recoveries used `@inlinable`
  ([the module split's run-time cost](<../Module split/The module split's run-time cost, step by step (2026-10-10).md>)).

Related: [selective optimisation attributes](<Selective optimisation attributes (2026-10-08).md>), and the split
plan, which held `@_specialize(exported:)` in reserve:
[Module split plan, revision 4](<../../Module split plan, revision 4 (2026-10-07).md>).
