# Strict memory safety: the last `@safe`, and printf formats

How the package came to build under strict memory safety (SE-0458) with no type marked `@safe`, and how it writes numbers
without a printf format. The rules themselves are in [CONTRIBUTING](<../../../CONTRIBUTING.md>), "Memory safety".

## The `@safe` exception: `ValueHashPlans` (2026-11-08)

**What it was.** `ValueHashPlans` is the per-type table of value-hash plans every render cache keys views by: an
open-addressing table looked up once per measured view, each plan a list of byte runs to hash and of typed steps (an
optional's case, an existential's payload). It kept the table, the plans and their lists in memory it allocated, owned
and freed itself, behind `UnsafeMutablePointer`s, and handed a plan out as an `UnsafePointer` that stayed good while the
table grew. Strict memory safety made that storage an unsafe type, so the class had to be `@unsafe` — and then so
would `RenderCache`, `TUIContext` and every use of them — or `@safe`, a claim the checker takes on trust. It was
`@safe`, the package's one: the SwiftLint rule `safe_escape` refuses the attribute, and `Tools/check-ratchets.py`
counted this exception.

**The owner's ruling.** "Explore whether there's an intrinsically safe way to implement it without a performance
impact; otherwise keep the exception."

**What the Swift 6.4 study had found.** [Raising the minimum Swift to 6.4](<../../Swift language/Raising the minimum Swift to 6.4.md>)
looked for a safe owned buffer: `UniqueArray` is macOS 27, `InlineArray` and `Array.span` macOS 26, and a type of our
own that hands out a `Span` needs the experimental `Lifetimes` feature. It concluded that 6.4 makes a safe table no
more possible. It did not try plain arrays, because a plan read out of an array is either copied, with reference
counting, or indexed, with bounds checks, in the hash's inner loop.

**What was done.** The table on arrays, shaped so that neither cost lands where it was feared:

- Each slot holds its plan's *entry* by value: the shape, the size, and two ranges — where its runs lie in one list
  of every plan's runs, and where its steps lie in one list of every plan's steps. An entry is 24 bytes of integers;
  a lookup copies one out of the slot, retaining nothing.
- The lists only ever have more appended, so a range an entry names stays good while a step plans a new type and
  grows them. The step loop reads each step from the list afresh, by its place.
- A step is an offset and metatypes only. An existential opener was a struct holding a closure that took the field's
  address — an unsafe type, so every holder was unsafe. It is now a protocol a caseless enum conforms to
  (`ValueHashOpener`), held as a metatype: nothing to retain or release, nothing captured to leak.
- The lists, the table and the stack-guard state are stored variables marked `@exclusivity(unchecked)`, the pattern
  CONTRIBUTING gives for skipping the run-time exclusivity check on a class's state. Each access is one read or one
  write that calls nothing while it lasts, so no two can overlap.

Nothing the class stores is an unsafe type, so it needs neither `@safe` nor `@unsafe`. What stays `unsafe` is what
always was: reading a value's bytes at offsets the runtime's metadata gives (raw pointers, existential loads), and
each access to an `@exclusivity(unchecked)` variable, which the compiler asks to be marked. Tests read a plan as a
plain value (`plan(for:)`), with no `.pointee` and no table that must outlive it.

**What it cost.** Nothing measurable. `ab_bench.py` on the scenarios the render cache dominates, the old table
against the new (release, Xcode's 6.2.4, `slot.py --exclusive`, 10 paired reps, cpu-per-frame; the box was busy, load
average 16, so read a point either way as noise unless it repeats):

| Scenario | Warm | 95% CI | Cold | 95% CI |
|---|---|---|---|---|
| megalist | +1.0% | −0.9 … +2.9 | +1.0% | −0.3 … +2.1 |
| table | +0.0% | −1.7 … +3.6 | +0.6% | −0.4 … +1.4 |
| dashboard | +0.3% | −3.3 … +3.4 | −0.5% | −0.8 … +0.9 |
| grids | +0.0% | −1.2 … +2.0 | +0.4% | −0.5 … +1.4 |
| deep | +0.2% | −2.8 … +2.8 | −0.2% | −1.0 … +0.4 |
| fanout | +0.8% | −1.0 … +1.3 | −0.2% | −1.5 … +1.7 |
| textwall | +1.0% | +0.4 … +2.5 | +1.3% | +0.5 … +2.2 |
| modifiers | −0.3% | −1.0 … +1.0 | +1.2% | −0.2 … +2.2 |
| menus | −0.8% | −1.4 … +2.1 | −0.2% | −1.1 … +0.8 |
| anyview | +0.6% | −0.3 … +1.5 | +0.1% | −1.7 … +0.7 |

Only `textwall` moved, about 1% slower both warm and cold, inside the owner's tolerance of a few percent. The run
loop of a plan with runs or steps (`mix(at:entry:into:)`) has no `swift_retain`, `swift_release` or
`swift_beginAccess` left in it, read from the release binary; its bounds checks are 14 trap branches, never taken. The
stripped `Stress` binary grew by 224 bytes.

**Decision.** The exception is gone: `ValueHashPlans` is not `@safe`, and the ratchet on `safe_escape` exceptions is
0. A new type with unsafe storage takes the same route first — arrays and `@exclusivity(unchecked)`, values rather than
pointers handed out, a protocol metatype rather than a stored closure over a pointer — before it asks for an
exception.

## Printf formats: `String(unsafeFormat:)` (2026-11-08)

**What it was.** Apple's Foundation declares `String(format:)` `@unsafe` and swift-corelibs-foundation doesn't, so
the `unsafe` Swift 6.4 wants on macOS is an "unnecessary `unsafe`" warning on Linux and WebAssembly. A shared helper,
`String(unsafeFormat:)` in TUICore, unsafe everywhere, gave the package one spelling; 77 calls used it.

**The owner's ruling.** He disliked the helper and asked for a more elegant route, with the helper acceptable as a
fallback.

**What was done.** Each call went the way of what it wrote:

| What | Now | Why |
|---|---|---|
| A number for a person (the Example's readouts) | `.formatted(.number.precision(.fractionLength(n)))` | The locale's own marks, as a SwiftUI app writes it |
| A number a program reads back, or a frame a checksum covers (Stress's reports and scenarios, the tools, the gradient codecs) | `.formatted(.fixed(n))`, a TUICore style | A full stop, no grouping, in every locale (`en_US_POSIX`) |
| Hex, and integers padded with zeros or spaces | `digits(width:radix:uppercase:padding:)` on `BinaryInteger`, TUICore | `String(_:radix:)` and the padding, which several files wrote by hand |
| A translation's `%@` (the file panels) | `LocalizedStringKey.substituting(_:into:)` | Already the package's substitution, `%1$@` included |

What stays on the helper needs printf itself: `Text`'s `specifier:`, a format chosen at run time that SwiftUI
documents as printf's (`FormatSpecifiable`, `InterpolatedNumber`), and `Path`'s description, which writes C's `%g`, whose
switch to an exponent by magnitude no `FormatStyle` writes.

**Two differences, both accepted.** `FormatStyle` rounds the shortest decimal half to even, where printf rounds the
binary value exactly: 0.05 at one place is `0.0` here and `0.1` from `%.1f`. Nothing converted depends on such a tie.
And the Example's numbers now follow the locale: `0,50` in German.

**What it cost.** Measured on macOS, `-O`, 200,000 calls each, on a loaded box: `%.1f` 890 ns, `.fixed(1)` 737 ns,
`.number.precision(.fractionLength(1))` 817 ns; `%7d` 797 ns, `digits(width: 7, padding: " ")` 55 ns. So the Stress
scenarios that format every frame (the processes table, the log view's line numbers) cost no more than they did.
FormatStyle builds on Linux and WebAssembly (it is FoundationInternationalization, which both SDKs ship; TUIFoundation
already used it).
