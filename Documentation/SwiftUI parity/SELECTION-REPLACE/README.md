# SELECTION-REPLACE: what macOS text views do with the selection when the app edits the text (O-28)

Measured 2026-11-21 on macOS 15.8.3 (24H241), SwiftUI 6.5.4 (the system framework), arm64; built
with Xcode 26.3 (17C529), Swift 6.2.4, macOS 26.2 SDK. Raw output: `probe.out`, and
`probe-past-end.out` for the two cases that trap.

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 6 -parse-as-library probe.swift -o probe
./probe > probe.out
PROBE_EDGES=1 ./probe > probe-edges.out                                  # Part 1b alone
PROBE_PAST_END=TextEditor ./probe; PROBE_PAST_END=TextField ./probe     # each traps, see Part 4
```

Every case starts fresh: `"abcdefghij"` with the selection `{2,5}` (`"cdefg"`, i.e. 2..<7), in its
own offscreen titled `NSWindow` (titled, so it can hold a first responder), the view first
responder. For SwiftUI the selection is set with `setSelectedRange` on the `NSTextView` that
`TextEditor` hosts, or on a `TextField`'s field editor; SwiftUI picked it up (the selection binding
read 2..<7). Ranges are `{location,length}` in UTF-16; the text is ASCII.

## Part 1: NSTextView (TextKit 1 and TextKit 2 identical)

| edit | text after | selectedRange |
|---|---|---|
| (a) `textView.string = "0123456789"` (same length) | `0123456789` | {10,0} |
| (a') `textView.string = "0123"` | `0123` | {4,0} |
| (a'') `textView.string = "0123456789ABCDEF"` | `0123456789ABCDEF` | {16,0} |
| (b) `textStorage.replaceCharacters({0,0}, "XY")` (insert before) | `XYabcdefghij` | {4,5} |
| (b') `replaceCharacters({1,0}, "XY")` (insert just before) | `aXYbcdefghij` | {4,5} |
| (c) `replaceCharacters({3,2}, "Z")` (inside, shrinks) | `abcZfghij` | {4,0} |
| (c') `replaceCharacters({3,2}, "ZZZZ")` (inside, grows) | `abcZZZZfghij` | {7,0} |
| (c'') `replaceCharacters({1,3}, "Q")` (straddles the start) | `aQefghij` | {2,0} |
| (c''') `replaceCharacters({6,3}, "Q")` (straddles the end) | `abcdefQj` | {7,0} |
| (d) `replaceCharacters({10,0}, "XYZ")` (append) | `abcdefghijXYZ` | {2,5} |
| (e) `replaceCharacters({0,10}, "0123456789ABCDEF")` (whole, longer) | `0123456789ABCDEF` | {16,0} |
| (e') `replaceCharacters({0,10}, "012")` (whole, shorter) | `012` | {3,0} |
| (e'') `textStorage.setAttributedString("0123456789")` | `0123456789` | {10,0} |
| (f) `textView.replaceCharacters({0,0}, "XY")` (NSText) | `XYabcdefghij` | {4,5} |
| (g) `textView.insertText("XY", replacementRange: {0,0})` | `XYabcdefghij` | {4,5} |

The rule: an edit wholly before the selection shifts it; an edit wholly after leaves it; an edit
that touches the selection at all collapses it to a caret at the END of the replacement text. A
whole-text replacement (`string =`, `setAttributedString`, or `replaceCharacters` over all of it) is
that last case: a caret at the end of the new text.

## Part 1b: NSTextView, edits that meet the selection at an edge

Added 2026-11-23 for O-28 (a), on the same machine and toolchain: Part 1 leaves open what an edit
ending at the selection's start, starting at its end, or meeting a caret does. `PROBE_EDGES=1 ./probe`
runs this part alone; raw output `probe-edges.out`. Each row is a `textStorage.replaceCharacters`.

| edit | selection before | replaced | with | text after | TextKit 1 | TextKit 2 |
|---|---|---|---|---|---|---|
| insert at the selection's start | {2,5} | {2,0} | "XY" | "abXYcdefghij" | {4,5} | {4,5} |
| insert at the selection's end | {2,5} | {7,0} | "XY" | "abcdefgXYhij" | {2,5} | {2,5} |
| replace ending at the start | {2,5} | {0,2} | "Q" | "Qcdefghij" | {1,5} | {1,5} |
| replace starting at the end | {2,5} | {7,2} | "Q" | "abcdefgQj" | {2,5} | {2,5} |
| delete ending at the start | {2,5} | {0,2} | "" | "cdefghij" | {0,5} | {0,5} |
| delete starting at the end | {2,5} | {7,2} | "" | "abcdefgj" | {2,5} | {2,5} |
| delete inside | {2,5} | {3,2} | "" | "abcfghij" | {3,0} | {3,0} |
| insert inside | {2,5} | {4,0} | "XY" | "abcdXYefghij" | {6,0} | {6,0} |
| delete the selection exactly | {2,5} | {2,5} | "" | "abhij" | {2,0} | {2,0} |
| insert at a caret | {5,0} | {5,0} | "XY" | "abcdeXYfghij" | {7,0} | {7,0} |
| replace starting at a caret | {5,0} | {5,2} | "Q" | "abcdeQhij" | {6,0} | {6,0} |
| replace ending at a caret | {5,0} | {3,2} | "Q" | "abcQfghij" | {4,0} | {4,0} |
| replace across a caret | {5,0} | {4,2} | "Q" | "abcdQghij" | {5,0} | {5,0} |
| append at a caret at the end | {10,0} | {10,0} | "XY" | "abcdefghijXY" | {12,0} | {12,0} |
| insert at 0, caret at 0 | {0,0} | {0,0} | "XY" | "XYabcdefghij" | {2,0} | {2,0} |

So "wholly before" takes in an edit ending at the selection's start (an insertion there too), and
"wholly after" one starting at its end. A caret differs at one edge only: an insertion at it moves it
(it is before), and a replacement starting at it collapses it to the replacement's end (it touches).
An insertion inside a selection touches it. TUI's `AppTextEdit` is these rules, and
`AppTextEditSelectionTests` has a case for each row of Parts 1 and 1b.

## Part 2: NSTextField with its field editor active

| assignment | field editor kept | editor text | selectedRange |
|---|---|---|---|
| `stringValue = "0123456789"` | yes | `0123456789` | {2,5} |
| `stringValue = "abcdefghijXYZ"` | yes | `abcdefghijXYZ` | {2,5} |
| `stringValue = "XYabcdefghij"` | yes | `XYabcdefghij` | {2,5} (not shifted) |
| `stringValue = "012"` | yes | `012` | {2,1} (clamped) |

`stringValue =` keeps the selection's numbers, clamped to the new length; it never shifts it.

## Part 3: SwiftUI `TextEditor(text:)` / `TextField(text:)`, the app sets the `@State`

| new text | TextEditor selectedRange | TextField selectedRange |
|---|---|---|
| `"0123456789"` | {10,0} | {10,0} |
| old + `"XYZ"` (append) | {13,0} | {13,0} |
| `"XY"` + old (insert before) | {12,0} | {12,0} |
| `"012"` | {3,0} | {3,0} |
| the same string again | {2,5} | {2,5} |

Any change at all, even a pure append, puts a caret at the end of the new text; only an unchanged
value keeps the selection. (The text view's text matched the new value in every row.)

## Part 4: `TextEditor(text:selection:)` / `TextField(text:selection:)` (macOS 15 API)

`@State var selection: TextSelection?`. "Binding" is the `@State` read back after the update.

| app writes | view selectedRange | binding selection (TextEditor / TextField) |
|---|---|---|
| selection only: 4..<6 | {4,2} | 4..<6 |
| text only: `"XY"` + old | {2,5} (not shifted) | 2..<7, unchanged |
| text `"XY"` + old AND selection 4..<9, in one update | {4,5} | 4..<9 |
| text only: old + `"XYZ"` | {2,5} | 2..<7 |
| text only: `"0123456789"` | {2,5} | 2..<7 |
| text only: `"012"` (the selection now runs past the end) | **traps** | |
| text `"012"` and selection `nil` | {3,0} | insertion 3 / `nil` |
| text `"XY"` + old, then the selection 4..<9 in a later update | {2,5}, then {4,5} | 2..<7, then 4..<9 |

Identical for `TextEditor` and `TextField` except the `nil` row: `TextEditor` writes the caret back
into the binding (insertion at 3), `TextField` leaves it `nil`.

With a selection binding the binding wins: a text-only write keeps the binding's selection, applied
by position to the new text (the `String.Index` values still come from the old string; SwiftUI
neither shifts nor clears them). Writing text and selection together in one update shows exactly
the app's selection, so an app that wants the selection to follow an insertion must shift it itself.

**Surprise: shortening the text under a selection that then runs past its end crashes SwiftUI.**
Both views trap with `Swift/StringUTF16View.swift:372: Fatal error: String index is out of bounds`:

```
frame #7: Foundation`_NSRange.init(_:in:)
frame #8: SwiftUI`NSTextView.setTextSelection(_:affinity:)
frame #9: SwiftUI`AppKitTextEditorAdaptor.Coordinator.update(...)     (TextField: PlatformTextFieldCoordinator.update())
```

SwiftUI converts the stale `TextSelection` into an `NSRange` against the new, shorter string
without clamping it. Without the selection binding (Part 3) the same write is safe.

## Part 5: macOS 26 API: compiles, not runnable here

These compile against the macOS 26.2 SDK (all `@available(macOS 26, *)`):

- `TextEditor(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>?)`
- SwiftUI's `AttributedString.transform(updating: inout AttributedTextSelection, body:)`
- Foundation's `AttributedString.transform(updating: inout Range<AttributedString.Index>, body:)`
  (and the `[Range]` and returning variants)

None can run on this machine's macOS 15.8.3 runtime, so whether `transform(updating:)` keeps a
selection across an edit, and whether writing an `AttributedString` and its selection together
keeps the app's selection, is **unmeasured**. The probe's Part 5 inserts `"XY"` at 0 under the
selection 2..<7 through both `transform(updating:)` spellings and prints the result when run on
macOS 26; no Linux runtime (where swift-foundation's version would run) was available either.

## Not measured

- Edits typed by the user (only app-side writes were made); undo grouping.
- Multi-range selections, non-ASCII text, marked (IME) text.
- iOS / UIKit-backed views, and SwiftUI on macOS 26.
