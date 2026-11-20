# An attributed TextEditor: design (G3)

*The design for `TextEditor(text: Binding<AttributedString>, selection:)`, which A42 decided to build on
2026-10-04 and which has not started, brought up to date with the editor as it is now (EDITOR-SPLICE,
EDITOR-FIRST) and priced against the document that asked for it again: tuitree's source pane, a 3.2 MB JSON or
plist file it wants to colour and whose parse error it wants to mark (tuitree's `TUI-FEEDBACK.md`, Milestone 4
item 4; G3 in the lead's list). Written 2026-11-16 against `main` at 137a7b068. Nothing here is built. SwiftUI's
signatures are read from the macOS 26.2 SDK's interfaces in Xcode 26.3; the costs of `AttributedString` were
measured on this machine (macOS 15.8.3, Foundation's own `AttributedString`, Xcode's Swift 6.2.4, `-O`); what
SwiftUI's own editor does was not measured, because macOS 26 does not run here. Ids: A-ATTRED-1 to 4 (for the
owner), B-ATTRED-1 to 7 (decided here).*

*Updated 2026-11-17: the owner ruled on A-ATTRED-1 to 4 (§7). The per-line styler is withdrawn. The deeper design
that replaces it is [Highlighting a large source in TextEditor: design (G3,
A-ATTRED-1)](<Highlighting a large source in TextEditor - design (G3, A-ATTRED-1).md>) (A-ATTRED-5 to 7). The
caret's side at a run's edge and at a wrap, measured on macOS, is §8 (A-ATTRED-8 and 9, B-ATTRED-16 to 18). L3, the selection API, is built (§5),
and what its macOS 15 fallbacks cost is §9. L4's editor is built but for line height (§5), and
B-ATTRED-4's price is measured there.*

*Updated 2026-11-19: the owner ruled on attralign (§7). On the macOS 26 SDK a paragraph's `alignment` is Core
Text's own, macOS 26 only as in SwiftUI; TUI declares the same names only where no SDK does; and TUI's own
`paragraphAlignment` aligns a paragraph on every platform and macOS. Line height stays unbuilt: Core Text's factor
cannot be read back with what runs here (§5, A-ATTRED-13).*

*Updated 2026-11-19, later: the owner ruled A-ATTRED-13 (b), and line height is built (§5, "As built: a paragraph's
line height"): Core Text's `lineHeight` on macOS 26, read by `==` against a grid of factors, TUI's identical type
elsewhere, no attribute of TUI's own; each line takes its factor's rows, rounded.*

## In short

SwiftUI's attributed editor is one initializer, a selection type that carries typing attributes, five
`AttributedString` mutators that keep a selection valid, and formatting definitions that constrain which
attributes an edit may set. A terminal draws the attributes that are colours and cell styles (foreground,
background, bold, italic, underline in five shapes where the terminal has them, strikethrough) and none of the
ones that are geometry (kerning, tracking, baseline offset, line height, a font's size or family, Genmoji).

The 2026-10-04 design (one editor over a storage enum, R1) still fits the editor, which has since become a layout
of lines kept between keys. What has changed is the price. Foundation offers no cheap way to tell whether an
`AttributedString` an app wrote back has the same characters as the one the editor wrote: comparing them is
O(n), measured at about 230 ns a character (442 ms for a 1.9 MB text). An app that colours its source
re-writes the value after every key, so on tuitree's 3.2 MB file the editor would spend about three quarters of a
second a key finding out that only colours changed, and the coloured value itself holds about 250 bytes a run
(78 bytes a character for JSON coloured token by token). SwiftUI's API is the right one for prose and small
sources and should be built as A42 decided; it cannot serve tuitree's file.

**Recommended (A-ATTRED-1):** build SwiftUI's API, and beside it a TUI-specific per-line styler on the `String`
editor: a function from a line's text to its styled runs, called for the lines drawn and kept while a line is
unchanged, plus marks the app states by range (the parse error). That costs nothing for lines off screen and
leaves a key at today's 2.6 ms. About 10 lane-days for everything, 4 of them for what tuitree needs.
*(Not taken: the owner ruled on 2026-11-17 that a per-line styler is too limited, §7.)*

## The problem

tuitree's source pane shows the document's text in a `TextEditor` bound to a `String`. It wants JSON and XML
coloured by token, and the span of a parse error underlined, as an editor would show them; today the text is one
ink and the error is in a problems list beside it. SwiftUI (macOS 26) has
`TextEditor(text: Binding<AttributedString>, selection:)` for this, and TUI has the `String` initializers only
(`Sources/TUITextInput/Views/TextEditor.swift:148`, `:164`).

A42 (in [Text fields and the wrapping editor](<Text fields and the wrapping editor.md#a42-rich-text-editing-now-that-p8-has-shipped>))
decided on 2026-10-04 to build SwiftUI's rich-text editing, about three days then, with the design in §7 of the
[2026-10-04 design study](<../../SwiftUI parity/Design studies/Text selection and editing design study, A13, A42 and A43 (2026-10-04).md>),
and A42-Q8 (2026-10-23) put the formatting commands in the editor's context menu. Since then the editor has
changed under it: it wraps (A43), keeps its layout between keys and splices an edit's lines into it
(EDITOR-SPLICE), and lays its text out once in its first frame (EDITOR-FIRST). And the document asking for it
now is 3.2 MB, where the study had prose in mind.

## 1. What SwiftUI offers

Read from `SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface` and `SwiftUICore.swiftmodule/…` in the
macOS 26.2 SDK (Xcode 26.3); line numbers are the interfaces'.

**The editor** (SwiftUI, line 3225), beside the two `String` initializers:

```swift
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable) @available(watchOS, unavailable)
public init(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>? = nil)
```

The selection binding is optional and not optional-valued, unlike the `String` editor's
`Binding<TextSelection?>`.

**The selection** (SwiftUI, 15977–16041), all macOS 26:

```swift
public struct AttributedTextSelection: Equatable, Sendable {
    @frozen public enum Indices: Equatable, Sendable {
        case insertionPoint(AttributedString.Index)
        case ranges(RangeSet<AttributedString.Index>)
    }
    public init()
    public init(insertionPoint: AttributedString.Index, typingAttributes: AttributeContainer? = nil)
    public init(ranges: RangeSet<AttributedString.Index>)
    public init(range: Range<AttributedString.Index>)
    public func indices(in text: AttributedString) -> Indices
    public func affinity(in text: AttributedString) -> TextSelectionAffinity
    public func typingAttributes(in text: AttributedString) -> AttributeContainer
    public func attributes(in text: AttributedString) -> Attributes<AttributedString>
    public struct Attributes<Text>: Sequence {   // of AttributeContainer
        public subscript<K>(type: KeyPath<AttributeDynamicLookup, K>) -> some Sequence<K.Value?>
        public subscript<K>(type: K.Type) -> some Sequence<K.Value?>
    }
}

extension AttributedString {
    public mutating func transform<E>(updating selection: inout AttributedTextSelection,
                                      body: (inout AttributedString) throws(E) -> Void) throws(E)
    public subscript(selection: AttributedTextSelection) -> DiscontiguousAttributedSubstring { get }
    public mutating func transformAttributes<E>(in selection: inout AttributedTextSelection,
                                                body: (inout AttributeContainer) throws(E) -> Void) throws(E)
    public mutating func replaceSelection(_ selection: inout AttributedTextSelection,
                                          withCharacters newContent: some Collection<Character>)
    public mutating func replaceSelection(_ selection: inout AttributedTextSelection,
                                          with newContent: some AttributedStringProtocol)
}
```

**Formatting definitions** (SwiftUICore, 9483–9680): `AttributedTextFormattingDefinition<Scope>` (a `body`
built by `AttributedTextFormatting.DefinitionBuilder<Scope>`, a result builder whose `buildBlock` is a parameter
pack into `TupleDefinition`), `AttributedTextValueConstraint` (an `AttributeKey`, and
`constrain(_ container: inout Attributes)` over an `AttributeContainerProxy`), `EmptyDefinition`,
`AnyDefinition`, `ValueConstraint`, `Optional` as a definition, and three
`View.attributedTextFormattingDefinition(_:)` overloads (a definition, a scope type, a key path to a scope).

**The commands and the controls:** `TextFormattingCommands` (SwiftUI, 14395) and
`View.textInputFormattingControlVisibility(_:for:)` (SwiftUI, 8249).

**The attributes** the editor's scope declares (`AttributeScopes.SwiftUIAttributes`, SwiftUICore 7697): `font`,
`foregroundColor`, `backgroundColor`, `strikethroughStyle`, `underlineStyle`, `kern`, `tracking`,
`baselineOffset`, `alignment` and `lineHeight` (both macOS 26, Core Text's), `adaptiveImageGlyph` (Genmoji, macOS
15), and the `accessibility` and `foundation` scopes (links among them).

TUI has none of this yet but `TextSelection` and its affinity; the parity baseline lists the selection's members
as gaps (`Tools/APIParity/baseline.json`).

## 2. What a terminal can draw of it

| Attribute | In a terminal | `Text(AttributedString)` today | In the editor |
|---|---|---|---|
| `foregroundColor`, `backgroundColor` | Yes, at the palette's depth (24-bit, 256, 16) | Drawn | Drawn; a selection's colours win over them, as the find bar's match tint does |
| `font`: bold, italic | SGR 1 and 3; a weight from semibold up is bold | Drawn | Drawn |
| `font`: size, family, width, leading | No: one cell, one face | Ignored | Ignored |
| `underlineStyle` | Single everywhere; double, curly, dotted, dashed (`4:2`–`4:5`) and a colour (SGR 58) where `LineStyleSupport` says the host draws them, a straight line elsewhere | Drawn (TUI's `.curly` too) | Drawn: a parse error can be a red curl |
| `strikethroughStyle` | SGR 9; its own colour on iTerm2 only | Drawn | Drawn |
| `link` | Styled as a link; OSC 8 where the host honours it | A link and a control (B85) | Styled, no OSC 8: the terminal would take ⌘-click inside an editable field (the 2026-10-04 design, kept) |
| `inlinePresentationIntent` (Darwin) | Bold, italic, strikethrough | Drawn | Drawn |
| `kern`, `tracking`, `baselineOffset`, `lineHeight` | No: the grid fixes them | Ignored | Ignored |
| `alignment` (a paragraph's) | Drawn per line (A-ATTRED-3, as built in L4); Core Text's on the macOS 26 SDK, so macOS 26 only, and TUI's `paragraphAlignment` on every macOS (attralign) | Each line aligned within the text's width | Each row aligned within the editor's width |
| `adaptiveImageGlyph` | No | Ignored | Ignored |

So everything tuitree asks for is in the drawable half: colours per token, and an underline (curly where the
terminal has it) or a background over the error's span.

## 3. Where it sits on TUI's editor

The editor today (`Sources/TUITextInput/Focus/EditorLayout.swift`, `TextEditorHandler.swift`,
`Views/TextEditor+Rows.swift`):

- **The text** is the bound `String`, and beside it the layout's `lines: [[Character]]` (16 bytes a
  character), each line's start in bytes and in characters, and one or more wrappings that keep each
  character's width in a byte. tuitree measured about 20 bytes a character in all (M5).
- **A key** edits the lines, splices the changed ones into the text's bytes, re-wraps only those lines, and
  writes the binding (EDITOR-SPLICE): 2.6 ms a key on a 40,000-line document. The text read back is compared by
  its storage first, so the editor's own write costs no comparison.
- **A row** is drawn by `styledRow`, character by character, through `RunAccumulator`, which knows an ink, a
  field and a reversal. The find bar's matches are already ranges of a line drawn in another field.

The 2026-10-04 design (R1) stands, and these decisions fit it to that editor:

### B-ATTRED-1. One editor over a storage enum, as A42's design has it

`_TextEditorCore` holds `String` or `AttributedString` (and its optional selection binding) in an enum, so the
`String` path pays a switch and stays specialised; every edit in `TextEditorHandler` becomes a replacement of a
range, so an attributed edit keeps its neighbours' attributes. A second editor core would copy about 4,700 lines
(the editor's views and handler files today), more than the 1,600 that ruled R2 out in October.

*As built in L1 (2026-11-17):* every edit the handler makes is one or more `TextEditorReplacement`s (a range of
line and column positions and the lines that take its place) made through `writeReplacing(_:)`, which applies
them to the lines and writes those as before, so a `String`'s bytes and layout are made exactly as they were.
Several in one write are made in order, each on the lines the one before left: a block's rows go last first.
Only an undo or redo and the find bar's Replace All replace the text whole (B-ATTRED-4's path). The history is
generic over its text (`TextUndoHistory<Text: UndoableText, Caret>`, `String` keeping `TextEdit`). The storage
enum itself waits for L4, where its second case arrives: with one case it would be a switch with nothing to choose.

### B-ATTRED-2. Styles are read for the lines drawn, never for the document

The layout keeps the `AttributedString` it was built from. A drawn line's runs are read from it when the line is
first drawn (an index for the line's start, then its runs: 0.25 ms for a 4,000-character screenful's 1,169 runs,
measured) and kept per line, as interned styles, until an edit changes that line. A document's attributes are
never all read: on tuitree's file that would be 3 to 4 seconds and over 100 MB of the editor's own.

### B-ATTRED-3. The editor's own edits go into the value in place

A key edits the lines as today and the `AttributedString` too, at the index of the edit's character offset,
with the typing attributes; the binding is written and the value remembered. Read back unchanged, it is the same
storage, and `==` answers in 3 µs (measured). An insert in the middle of 1.9 MB costs 0.04 to 0.16 ms, 2.9 ms
when the value's storage is shared with a copy and its path through the tree is copied first; finding the index
of a character offset through the character view costs up to 1.8 ms (three quarters of the way in), which the
UTF-8 view of macOS 26 and swift-foundation should cut (measured in L0).

### B-ATTRED-4. Any other value is taken whole

A value the app wrote (a recolour after `onChange`, a new document) is compared and laid out afresh, O(n), as a
new `String` is today, at most once a frame however many writes the frame saw. Foundation gives no way to learn
that only attributes changed: the character views are not `Equatable`, and nothing exposes their storage. The
cost is documented on the initializer with the measured rate, about 230 ns a character on macOS 15.8.3
(`elementsEqual` of the characters: 442 ms for 1.9 MB; `String(characters)`, which a fresh layout needs, 302 ms).
That is a few milliseconds for prose and three quarters of a second a key for tuitree's file, which is what
A-ATTRED-1 is about.

### B-ATTRED-5. A run's style rides the row's run accumulator

`RunAccumulator` carries bold, italic, underline (shape and colour) and strikethrough beside its ink and field,
and closes a run where any of them changes. The selection replaces the colours and keeps the rest; a find match
tints the field and keeps the rest; the caret flips its cell as today.

*As built in L2 (2026-11-17):* a line's styles are `EditorStyledRun`s (columns of the line, an ink and a field
that may be `nil` for the editor's own, and a `CellDecoration`: bold, faint, italic, an underline and a
strikethrough as `Text.LineStyle`s). The handler reads them from `lineStyler`, the package seam L4's attributed
source will fill, once a line drawn, into `EditorLineStyleCache` (B-ATTRED-2): an edit drops the lines it replaced
and moves those after them, and a text replaced whole drops them all. A run with no decoration is spelled exactly
as before (`ANSIRenderer.colorize`), so an editor with no styler draws the same bytes. Hidden text
(`hidingGlyph`) draws no styles, whose colours would show where its words are. `CellDecoration.fitted(to:)` fits
the lines to the terminal's `LineStyleSupport` (B-ATTRED-6); the source applies it when it makes the runs. Reading
an `AttributedString`'s runs into these, fonts included (A-ATTRED-3's mapping), is L4's.

### B-ATTRED-6. An underline's shape falls back as `Text`'s does

Through `LineStyleSupport`: curly, dotted, dashed and double where the host draws them, a straight line
elsewhere, and its colour only where SGR 58 is honoured. TUI's `.curly`, which SwiftUI's `Text.LineStyle` lacks,
works in an `AttributedString`'s `underlineStyle` as in `Text`'s modifier.

### B-ATTRED-7. A link is styled, not hyperlinked

As the 2026-10-04 design has it: inside an editable field the terminal would take a ⌘-click on an OSC 8 link,
and the editor's own click places the caret.

## 4. What it costs

**Memory, a character** (JSON, 1.9 MB, 40,002 lines, 400,002 tokens, measured):

| | Bytes a character | tuitree's 3.2 MB |
|---|---|---|
| The `String` editor today (tuitree's M5 measure) | about 20 | about 64 MB |
| A plain `AttributedString` of the text, the app's | 1.4 | 4.5 MB |
| The same, one attribute on every token (580,003 runs) | 78 | 250 MB |
| The same, two attributes on every token | 106 | 340 MB |
| The editor's per-line style cache (B-ATTRED-2) | a screenful's runs | under 0.1 MB |

A run costs about 250 bytes with one attribute: each holds its own attribute storage. Colouring every token once
took 3.3 to 3.9 seconds.

**Time, a key** (the editor's work only; tuitree's own parse is 22 ms more):

| | Prose, 20 KB | tuitree's 3.2 MB |
|---|---|---|
| `String` editor today | under 1 ms | 2.6 ms |
| Attributed, the editor's own write read back (B-ATTRED-3) | under 1 ms | about 5 to 8 ms, estimated from its parts |
| Attributed, the app recolours after the key (B-ATTRED-4): comparing the characters | about 5 ms | about 740 ms |
| The per-line styler (A-ATTRED-1 (b)) | under 1 ms | 2.6 ms, plus the app's lexing of the lines drawn |

These are this machine's Foundation on macOS 15.8.3, outside TUI. swift-foundation on Linux is expected to be
the same code, and macOS 26's `AttributedString` may differ; L0 measures both before L4 is built.

### L0: what each platform's Foundation has (2026-11-17)

Read from the interfaces, not run: this machine has no macOS 26 to run on and no Linux, and the static Linux SDK
was off the disk. macOS from the macOS 26.2 SDK in Xcode 26.3 (`Foundation.swiftmodule` and `Swift.swiftmodule`);
Linux from swift-foundation's `release/6.2` branch (`Sources/FoundationEssentials/AttributedString/`), whose
`@available(FoundationPreview 6.2, *)` constrains Apple platforms only, so on Linux every 6.2 toolchain has it.

| What L3 and L4 use | macOS (TUI deploys to 15) | Linux, Swift 6.2 | Windows, Swift 6.4 |
|---|---|---|---|
| `RangeSet` | macOS 15 (the standard library) | Yes | Yes |
| `AttributedString.transform(updating:body:)`, its four forms: index tracking | macOS 26 | Yes (`AttributedString+IndexTracking.swift`) | Yes (swift-foundation from 6.2 on) |
| `DiscontiguousAttributedSubstring`, `subscript(_: RangeSet<Index>)`, `removeSubranges(_:)` | macOS 26 | Yes | Yes |
| `AttributedString.UTF8View` (`utf8`), the cheap way to an offset's index | macOS 26 | Yes | Yes |
| `Index.isValid(within:)`, `Range.isValid(within:)` | macOS 26 | Yes | Yes |
| `AttributedString.characters.replaceSubrange`, runs, `AttributeContainer` | macOS 12 | Yes | Yes |

So what follows for the lanes:

- **L3's selection type and its members build on macOS 15** except one: `subscript(_: AttributedTextSelection) ->
  DiscontiguousAttributedSubstring`, whose result type is Foundation's macOS 26 type, carries
  `@available(macOS 26, …)` on Apple platforms. TUI's other macOS 26 SwiftUI APIs (`ConcentricRectangle`,
  `Edge.Corner`, the drag configurations) are declared with no gate, since TUI implements them itself; this is the
  one that cannot be.
- **`transform(updating:body:)` tracks through Foundation where it can** (macOS 26, Linux, Windows) and falls back
  on macOS 15 to character offsets: the selection's offsets before the body, moved by the edit the body made, found
  by the characters' common start and end, as TUI's own undo finds an edit (`TextEdit`). That is the study's
  §7.3 fallback, and it is exact for one contiguous edit, which is what the editor's own transforms are.
- **The cost probe is not rebuilt in this lane**: nothing in L1 to L3 depends on its numbers, and its one open
  question, macOS 26's `AttributedString` and its UTF-8 view, needs a machine this one is not. It is L4's, before
  B-ATTRED-4's price is written into the initializer's documentation.

## 5. Staged lanes

One commit a step, the docs in the step whose behaviour they describe. Gates for every lane: the 6.2.4 build and
the suite; Stress `--selfcheck` for the drawing lanes; the Linux cross-compile for the formatting builder.

| Lane | What | Days | Tests and measures |
|---|---|---|---|
| **L0** | Availability and cost: index tracking, `DiscontiguousAttributedSubstring` and `RangeSet` in the 6.2 Linux swift-foundation and the macOS 15 SDK (the 2026-10-04 study's §7.3); this document's cost probe on Linux and, when one is at hand, macOS 26. B84's fuller version, the study's step R0, is done (B50, the `TUIAppKit` split) | ½ | Numbers into this document |
| **L1** | The storage enum (B-ATTRED-1) as a pure refactor on `String`: every edit a range replacement, `TextUndoHistory` generic over its snapshot | 1 | Byte-identical frames; A/B `notes`, `text-editor-typing`, `bigtext`, expecting nothing |
| **L2** | Styled rows (B-ATTRED-5, 6): the run accumulator's styles, the per-line style cache (B-ATTRED-2), the selection and find tint over styles; fed through a package seam | 1 | Golden rows; A/B `text-editor`, `bigtext` |
| **L3** | `AttributedTextSelection` and the five `AttributedString` members, with the offset fallback where index tracking is missing | 1½ | `AttributedTextSelectionTests`, `AttributedStringSelectionEditTests` |
| **L4** | `TextEditor(text: Binding<AttributedString>, selection:)`: edits in place (B-ATTRED-3), values taken whole (B-ATTRED-4), typing attributes (A-ATTRED-4), undo restoring attributes; CHANGELOG | 1½ | `RichTextEditorTests`; compile corpus: SwiftUI's bold-toggle example; Stress `text-editor-rich` and a `bigtext-rich` session pricing B-ATTRED-4 |
| **L5** | If A-ATTRED-1 is (b): the per-line styler and the marks on the `String` editor, TUI-specific; CHANGELOG | 2 | `TextEditorLineStyleTests` (a line restyled only when it changes; marks across lines; the cache dropped for edited lines); `bigtext` with a styler, against `bigtext` |
| **L6** | The formatting context menu (A42-Q8) and the `TypedClipboard` round trip | 1 | Shift-F10 and pointer routes |
| **L7** | Formatting definitions: the protocols, the builder, the three modifiers; `constrain` on edits and on the lines drawn | 1½ | `FormattingDefinitionTests`; the Linux cross-compile; the release-build guard |

**About 10 lane-days** (8 without L5), against the study's 6½ for the same ground: L2 and B-ATTRED-4's
measuring are new, and L5 is new. **For tuitree, L1, L2 and L5 are enough: 4 days.** L4 alone would give it
SwiftUI's spelling at B-ATTRED-4's price, workable only on a small file.

*As built in L3 (2026-11-17):* `AttributedTextSelection` (its four initializers, `indices(in:)`,
`affinity(in:)`, `typingAttributes(in:)`, `attributes(in:)` and `Attributes`) and `AttributedString`'s
`transform(updating:body:)`, `subscript(_:)`, `transformAttributes(in:body:)` and both `replaceSelection`s, in
`Sources/TUITextInput/AttributedText/`, with SwiftUI's signatures from the macOS 26.2 SDK. Apple's documentation
fixes two choices: `init()` is an insertion point at the end of the text, and `indices(in:)` gives "a valid fallback
index" for indices that no longer fit, which here is that same insertion point at the end. Typing attributes follow
B-ATTRED-16, and `affinity(in:)` reports `.upstream` for a selection the app made (B-ATTRED-17), the editor setting
its lean in L4. Where Foundation has them (macOS 26, Linux, Windows) validity is `isValid(within:)` and tracking is
Foundation's own, behaviour and all: a body Foundation cannot track (one that assigns the text whole) leaves the
selection to `indices(in:)`'s fallback rather than crashing as Foundation's `inout` form would. `replaceSelection`
removes the ranges and then inserts under tracking, so the caret lands after the new text, and
`transformAttributes` sets each run's attributes under tracking, which renews the indices. Only the subscript is
`@available(macOS 26, …)`. macOS 15 gets the fallbacks in one file, `AttributedTextSelection+MacOS15Fallbacks.swift`,
priced in §9. Tests: `AttributedTextSelectionTests` and `AttributedStringSelectionEditTests`, which run the
tracking cases through the platform's path and through the fallback directly, and on macOS 26, Linux and Windows hold
the fallback to Foundation's answers over 400 random single changes.

*As built in L4 (2026-11-17), the first part:* `TextEditor(text: Binding<AttributedString>, selection:
Binding<AttributedTextSelection>? = nil)`, the macOS 26.2 SDK's one attributed initializer, in
`Sources/TUITextInput/Views/TextEditor+Attributed.swift`. The storage enum of B-ATTRED-1 became an optional source
on the handler rather than an enum in the core: `AttributedTextSource` keeps the value and the `String` of its
characters, and the handler edits that `String` through a binding over the source exactly as it edits a bound
`String`, so the keys, the layout, the wrapping and the drawing are the one code. A write of that binding hands the app
the value the edit made in place (B-ATTRED-3: `stage(_:in:)` makes each `TextEditorReplacement` in the value, the
inserted text taking B-ATTRED-16's typing attributes, held across a selection's removal when typed over it; Ctrl-T
swaps two characters with their own attributes). An undo hands the value its step kept: the history's text is
`EditorUndoText`, a `String` kept as byte edits as before, or an `AttributedString` kept whole, which shares with the
value every part an edit did not touch. A text with mixed line breaks, which the editor joins afresh, and the find
bar's Replace are made as one replacement between the old and new text's common start and end. The lines' styles are
read through L2's seam with `Text(AttributedString)`'s own mapping (`Text.cellStyle(of:environmentFont:)`, so the
two agree): colours, a font's tier and weight as bold or faint, italic, the lines fitted to the terminal, a link in the
accent and underlined. The selection binding is a `_TextSelectionChannel` over the source, rewritten after every
edit, since the app's indices belong to the value before it. Tests: `RichTextEditorTests`; the compile corpus has
WWDC25's bold toggle.

**B-ATTRED-4's price, measured** (2026-11-17, macOS 15.8.3, Xcode 26.3's Swift 6.2.4 at -O, the L0 probe rebuilt
in the scratchpad, not kept: 40,002 lines of JSON records, 2,373,383 characters, 320,002 tokens each coloured, 640,003
runs; best of five):

| | Time | A character |
|---|---|---|
| `==`, the same storage | 0.001 ms | |
| `==`, equal values in different storage, plain | 300 ms | 126 ns |
| `==`, equal values in different storage, coloured | 858 ms | 362 ns |
| `==`, one recoloured at its end or its start | 0.001 ms | |
| `characters.elementsEqual`, different storage | 562 ms | 237 ns |
| `String(text.characters)` | 312 ms | 132 ns |
| `String(text.characters[...])`, a slice | 0.45 ms | 0.2 ns |
| `String(text[whole range].characters)` | 347 ms | 146 ns |
| `String ==`, different storage | 0.044 ms | |
| One character inserted mid-text, unshared and shared | 0.011, 0.016 ms | |

So the editor never asks `==` of a value the app wrote: an equal value rebuilt in new storage, which is what an app
recolouring after each key often writes, costs it a character at a time. It tells its own write read back by the one
reference an `AttributedString` holds (`AttributedTextSource.isIdentical`, a bit comparison, `==` where Foundation
lays the type out otherwise), and reads any other value's characters through a slice of the character view, which
copies the storage's chunks: about 0.2 ns a character, 0.5 ms for this text, then a fresh layout if the characters
changed (as a `String` editor's) and a screenful's styles read again (0.25 ms, B-ATTRED-2). That is the price the
initializer's documentation states. The three-quarters of a second a key of §4 was `elementsEqual`'s; the slice makes
the comparison three orders of magnitude cheaper, and leaves the fresh layout of a changed text, which the `String`
editor pays as well, as what a large source costs.

*As built in L4 (2026-11-17), a paragraph's alignment (§7, A-ATTRED-3), and as the owner then ruled (attralign,
2026-11-19):* SwiftUI's scope declares `alignment: AttributeScopes.CoreTextAttributes.TextAlignmentAttribute`, whose
value is Core Text's `AttributedString.TextAlignment` (`left`, `center`, `right`; macOS 26, read from the 26.2 SDK's
Core Text interface). L4 first declared both under those names itself, on every platform. That cost one thing,
measured: on macOS, Core Text's declarations are visible beside TUI's wherever Core Text is loaded, and TUI loads it
(`TUIStrings`' SF Symbols table), so an app that NAMED the type (`let a: AttributedString.TextAlignment`) beside
AppKit got "ambiguous type name". That broke the rule that nothing TUI adds may make a SwiftUI declaration
ambiguous, and went to the owner, who ruled "(a) but provide our own version anywhere that Core Text doesn't (e.g.
macOS 15) if possible". As built now, in `Sources/TUIFoundation/Views/AttributeScopes+CoreText.swift`, with the
compile probes in `Tools/SwiftUIProbes/Paragraph attribute types (attralign)/`:

| Where | `alignment` | Naming `AttributedString.TextAlignment` | TUI's `paragraphAlignment` |
|---|---|---|---|
| macOS 26 SDK, run on macOS 26 | Core Text's, drawn | One declaration, Core Text's: never ambiguous, with AppKit or `MemberImportVisibility` too | Drawn; `alignment` wins where a paragraph states both |
| macOS 26 SDK, run on macOS 15 | Needs `if #available(macOS 26, *)`, as SwiftUI's does; unreachable before it | As above | Drawn: the fallback |
| macOS 15 SDK (Command Line Tools 16) | TUI's own, under Core Text's names, no gate: that SDK declares none | TUI's, the only one | Drawn |
| Linux, Windows, WebAssembly | TUI's own, no gate | TUI's, the only one | Drawn |

The macOS 26 SDK is told from the 15 SDKs by FoundationModels, as `AttributedTextSelection`'s macOS 26 arms are
(§9; the ledger's row S4); both arrive with that SDK. On it TUIFoundation re-exports Core Text, because a SwiftUI file
built with `MemberImportVisibility` names the type and its cases with `import SwiftUI` alone, and without the
re-export a TUI one could not (the probe: "missing import of defining module 'CoreText'"). The scope's `alignment` is
a computed property there, because a stored property cannot be newer than its type; Foundation finds a scope's keys
through its stored properties, so decoding with `\.swiftUI`'s scope leaves the alignment out on that SDK (not
measured: decoding needs macOS 26; deviation T14, put to the owner as A-ATTRED-14). Elsewhere it is stored, under TUI's key name `"TUI.TextAlignment"`.

**The fallback** is TUI's own attribute under a name SwiftUI does not use, so it shadows nothing: `paragraphAlignment`
(`AttributeScopes.SwiftUIAttributes.ParagraphAlignmentAttribute`, valued TUI's `TextAlignment`, the
`multilineTextAlignment` type: `leading`, `center`, `trailing`), bounded by paragraphs as `alignment` is. It compiles
with no guard on every SDK and platform, beside AppKit too. TUI draws `alignment` where the platform has it and
`paragraphAlignment` otherwise (`AttributedSubstring.drawnParagraphAlignment`), so `Text` and the editor keep
one internal type, TUI's `TextAlignment`. **What a program on macOS 15 cannot do:** use SwiftUI's spelling at all
(SwiftUI's own cannot either), and so share that line with a SwiftUI build; it writes `paragraphAlignment`, which a
SwiftUI build does not have. The tests (`TextParagraphAlignmentTests`, `RichTextEditorAlignmentTests`) run each case
through both spellings where both exist and through `paragraphAlignment` alone on a Mac before macOS 26, and the
compile corpus names the type beside AppKit.

A `Text` aligns each line of the paragraph within its own width (the widest line), as
`multilineTextAlignment` aligns all of them, and a paragraph's alignment wins over that modifier for its own lines:
`Text.Run` carries the paragraph's alignment, and `Text+ParagraphStyle.swift` finds each wrapped line's paragraph
from the paragraphs' wrapped line counts (`TextWrapping.paragraphLineCounts`), which only a text whose runs state an
alignment asks for. The editor reads a line's alignment from its paragraph's first character (its newline, where it
is empty), once a line, kept with its styles in `EditorLineStyleCache` and dropped with them
(`TextEditorHandler+Alignment.swift`). A wrapping editor centres or right-aligns each row within its width less the
caret's margin cell, counting a wrapped row's text without the spaces left hanging at its end; one that scrolls
sideways aligns a line that fits in that width and leaves a longer one to scroll. The row is drawn after that many
blank cells in the well's field (`styledRow`'s `leadingCells`: the window starts that many cells before the line, so
the caret's, the selection's, the matches' and the tab stops' columns stay the line's own). The caret's parked
cell, a click, a drag, a Shift-click, an Option-drag's block and Up, Down and the page keys go by the cells as drawn:
the column the vertical keys keep is across the editor, not in the row. Tests: `TextParagraphAlignmentTests`
(TUIFoundation) and `RichTextEditorAlignmentTests`.

**Fonts (§7, checked in L4):** the mapping L4 shares with `Text` (`Text.cellStyle`, through `Font.defaultAttributes`)
already is the ruling's: a semantic style draws as its tier (titles and headline bold, footnotes and captions faint),
a weight from semibold up bold and from light down faint (`.weight(_:)`, `.bold()`, `Font.system(_:design:weight:)`),
and `.italic()` italic, in a font value set as the `font` attribute as in a `font(_:)` modifier. Nothing was missing
that TUI's `Font` can carry: it has no size, family, width or leading to ignore (`Font.system(size:)` and
`Font.custom` do not exist here), its `design` is ignored, and `monospaced()` returns the font unchanged, every cell
being one already. Kerning, tracking and a baseline offset stay out of the scope, so setting one does not compile.

**Not yet built (L4's remainder):** Stress's `text-editor-rich` and `bigtext-rich` cases.

*As built: a paragraph's line height (A-ATTRED-13 (b), ruled 2026-11-19).* SwiftUI's scope declares `lineHeight:
AttributeScopes.CoreTextAttributes.LineHeightAttribute`, valued Core Text's `AttributedString.LineHeight`, both macOS 26.
Its 26.2 SDK interface has the presets `variable`, `normal`, `tight` and `loose`, the makers `multiple(factor:)`,
`leading(increase:)` and `exact(points:)`, `==`, `hash(into:)` and Codable, and no accessor; the key is a plain
`AttributedStringKey`, not Codable, unlike alignment's. In `Sources/TUIFoundation/Views/AttributeScopes+LineHeight.swift`,
on the same basis as alignment:

| Where | `lineHeight` | How the factor is read |
|---|---|---|
| Apple platforms, macOS 26 | Core Text's; the scope's member computed (T14, which the owner's approval covers) | `==` against the presets, then `.multiple(factor:)` of every multiple of 0.05 from 1.5 to 8.45 (`ParagraphLineRows.readableTwentieths`): any other factor draws one row |
| Apple platforms, before macOS 26 | Absent, as in SwiftUI; no TUI attribute (the ruling says none) | Nothing to read: one row a line |
| Linux, Windows, WebAssembly | TUI's identical type and key (`"TUI.LineHeight"`, bounded by paragraphs), stored in the scope | Directly: TUI's type keeps what it was made as |

**The rounding (`ParagraphLineRows`, shared by `Text` and the editor and tested on every platform):** a line of a
paragraph at `.multiple(factor:)` takes `factor` rows, rounded half away from zero, at least 1 and at most 8; the rows
past the first are blank, after the line's text. So 1.5 and 2 put one blank row after each line, 2.5 and 3 two, and
1.2 or 1.4 none; past 8.5 it is 8, so a factor of a million cannot ask for a million rows a line. Every other value
takes one row: the presets (typographic nudges a cell grid cannot show), and `leading(increase:)` and
`exact(points:)`, because a terminal row's height in points is the terminal's font's, which TUI does not know, and on
Apple platforms the points cannot be read back anyway, so a point value draws alike everywhere. Half away from zero is
Swift's `rounded()`, and puts 1.5, the commonest "airy" factor, at two rows: one row would draw it as nothing at all.
The grid starts at 1.5 because every factor below draws one row whatever it is, and ends at 8.45, the last factor
below the cap's rounding; it is 140 comparisons at worst, made only for a run that states a line height. **What
differs by platform:** a factor off the grid (2.33, 100) draws one row on a Mac and its rows elsewhere; the tests hold
each side to its own answer. Not measured here (macOS 26 does not run on this machine): whether Core Text's key is
bounded by paragraphs (the tests that set it on a word assert so, on CI's macOS 26 lane), and whether `==` on Core
Text's value compares its factor exactly as made (they assert `.multiple(factor: 1.5)` and the rest of the table).

**`Text`** reads each run's rows a line once, when it is made (`Text.Run.lineRows`, `nil` for one), so a text that
states none pays one flag. `Text+ParagraphStyle.swift`'s `lineGaps` gives each wrapped line its paragraph's blank rows
by the paragraphs' wrapped line counts, as alignment finds a line's paragraph, and `LineSpacingRows` interleaves them
after each line but the last, on top of `.lineSpacing(_:)`'s, in the measure as in the drawing: the rows a height
budget holds, a line limit (which counts lines, as SwiftUI's does) and a link's rows (`TextLinkSpans`) all go through
it, so the measure reports what the render draws.

**The editor** reads a line's line height as it reads its styles and its alignment (B-ATTRED-2): from its first
character's run, once, for the lines a frame shows from the top and the caret's, kept in `EditorLineStyleCache` and
moved or dropped with the lines an edit changes (`TextEditorHandler+LineHeight.swift`). A line never shown counts as
one row a line, so the rows below the screen are provisional: a paragraph of more than one row a line adds its blank
rows when it is first shown, and the scroll bar's extent grows by them then; the frame that scrolls it on screen
follows the caret again on the rows it makes. What is on screen, the caret's row and the keys' steps are exact. Not
the whole value at once, which the first build of this did, because of what it cost (measured 2026-11-19, macOS
15.8.3, Xcode's Swift 6.2.4, -O, a probe kept out of the repository, 40,000 JSON-like lines of 16 runs): Foundation's
runs of one key (`runs[\.lineHeight]`, or a slice's) take time growing with the square of the runs, 3.9 s for 40,000
runs and 18.9 s for 80,000, so hours for `bigtext-rich`'s 640,003; every run's container read is about 0.23 µs a run
(150 ms), and every paragraph's first character about 0.65 µs a line (26 ms), against 12.5 ms for the rest of taking
that value (its characters read and compared). Read lazily, taking it costs 0.05 ms more with no line height (+0.4%)
and 0.08 ms with every paragraph at two rows a line (+0.7%, the gaps and the rows' starts made again). The Mac's
grid read could not be run here (macOS 26): a stand-in of Core Text's shape, a maker and `==` not inlined, takes 69
ns for a factor of 2 and 339 ns for one off the grid, so 0.002 to 0.009 ms for a screen's lines. A text that states
no line height keeps `nil`, and its rows are the wrapping as before. `WrappedRows` counts the blank rows as rows (`spaced(by:)`, the row starts made again in one pass,
kept beside the wrapping while the gaps array is the same), so the scroll, its bar, the page keys and the screen
count them; a blank row belongs to the text row above it (`location(ofRow:)`, so a click there lands on that row, as
§7 ruled), the caret's row is always a text row, Down onto blank rows goes on to the next text row and Up onto them to
the row they belong to, a block takes no row from them, and no blank row follows the document's last. The top of the
view may be a blank row (`scrollBlankRows`), so the wheel moves one row at a time and the caret at the bottom stays on
screen. Where the editor scrolls sideways, each line is followed by its blank rows the same way (one row a line, so the
gap is per line). Measured on this machine: nothing; the read of a whole value's line heights walks Foundation's
runs of that one key, which for `bigtext`'s 640,003 runs is not measured, and is paid once for each value taken whole,
not for the editor's own edits. A test seam, `lineRowsOfRun`, lets the drawing tests run on a Mac before macOS 26 through
an attribute of their own (`RichTextEditorLineHeightTests`, which runs every case through `lineHeight` too where it
exists); `TextParagraphLineHeightTests` runs the rule everywhere, `Text`'s rows through its runs, and Core Text's
reading under `#available(macOS 26, *)`.

**Why line height was not built at first (attralign, 2026-11-19).** The ruling's basis would be Core Text's
`AttributedString.LineHeight` on the macOS 26 SDK and a TUI-named fallback elsewhere, as for alignment. The crude
drawing needs the factor of `.multiple(factor:)`, and Core Text gives no way to read it that can be measured here.
Its interface (26.2 SDK) declares the makers (`multiple(factor:)`, `leading(increase:)`, `exact(points:)`, `normal`,
`tight`, `loose`, `variable`), `==`, `hash(into:)` and Codable, and no accessor. Three ways in, all type-checked in
the probe folder's `LineHeightReading.swift`, none runnable on this macOS 15.8 machine:

- **`==` against a grid of made values** (1, 1.5, … 4): public API, so reliable for exactly those values. Any other
  factor, and every `leading` and `exact` value, reads as unknown, drawn as one row.
- **Codable**: encode the value and read the factor out. Exact for every factor if the encoding carries it, but the
  encoding is undocumented and its shape unmeasured; a test on CI's macOS 26 lane would have to pin it, and a later
  macOS could change it.
- **Reflection** (`Mirror`): private, unversioned layout; not robust.

On a Mac before macOS 26 there is no `LineHeight` at all, so the fallback would be a TUI-named attribute of TUI's own
(a row count, say), as `paragraphAlignment` is. The owner's question is A-ATTRED-13 (§6). Line height is unlike alignment in one way that matters for a large text: a paragraph's blank
rows move every row after it, so the editor's rows (`WrappedRows.rowStarts`, which the scroll, the scroll bar's extent,
the caret's row and every click go through) need every paragraph's line height, where alignment needs only the lines
drawn. The way in that keeps B-ATTRED-2: `LineHeightAttribute` bounded by paragraphs like alignment, so
`value.runs[LineHeightAttribute.self]` yields one run per stretch of paragraphs that share a value (one run for a text
that sets none); `WrappedRows` keeping a rows-per-row factor per line, made from those runs when a value is taken whole
and from the edited lines' paragraphs after an edit; `location(ofRow:)` flooring a blank row to the row above (the
ruling's "belong to the row above"), Up and Down stepping by drawn rows, and the top row rounded up off a blank one so
the caret's row stays on screen. Not yet measured: what that runs walk costs on `bigtext`'s 640,003 runs, which a
recolour without a character change would pay on every write (a probe building that text with per-token attributes
did not finish inside five minutes and was stopped). `Text` would interleave a paragraph's blank rows as
`lineSpacing`'s are (`LineSpacingRows`), in its measure as in its drawing.

## 6. Questions for the owner

**A-ATTRED-13 (ruled (b) 2026-11-19, built: §5, "As built: a paragraph's line height"): line height, now that Core
Text's factor is unreadable here.** Options, each on
top of the editor work §5 sketches (a rows-per-row factor per line in `WrappedRows`, blank rows belonging to the row
above, the vertical keys stepping over them, `Text` interleaving them as `lineSpacing`'s rows), which is about 1 to
1½ lane-days whichever is picked:

- **(a) A TUI-named attribute only** (`paragraphLineRows`, an `Int`, say), on every platform and macOS; SwiftUI's
  `lineHeight` stays absent, so setting it does not compile. No reading of Core Text at all. About ¼ day beyond the
  editor work.
- **(b) (a) plus SwiftUI's `lineHeight` read by `==` against a grid** of `.multiple(factor:)` values on macOS 26;
  any other value draws one row. About ½ day beyond the editor work, and a macOS 26 CI run to see it work.
- **(c) (a) plus `lineHeight` read through its Codable encoding**: exact, but the encoding is undocumented and
  unmeasured. About ¾ day, a macOS 26 CI round trip first to learn the encoding, and a test that pins it on the
  macOS 26 and 27 lanes.
- **(d) Not yet**: leave line height unbuilt until a macOS 26 machine can measure Core Text, or the owner drops
  macOS 15.

Recommended: (a) now if tuitree or an app wants it, (b) on top only if a SwiftUI program's `lineHeight` matters;
otherwise (d). If you don't answer: (d).

### A-ATTRED-1. Colouring a large source: SwiftUI's API alone, or a per-line styler too

*tuitree's 3.2 MB JSON or plist, coloured by token, its parse error underlined.*

- **(a) SwiftUI's API alone.** An app colours an `AttributedString` and the editor draws it. **Price:** L1–L4,
  5½ days. On a large source each key costs the editor O(n) (about 740 ms at 3.2 MB) and the value 78 bytes a
  character; an app with such a file stays plain, as tuitree is today.
- **(b) ★ SwiftUI's API, and a TUI-specific per-line styler on the `String` editor.** A modifier gives the
  editor a function from a line's text to that line as an `AttributedString`, called only for lines drawn and
  kept until the line changes; a second modifier states marks as ranges of the text with their attributes (the
  parse error), compared by value each frame. Sketch, names for L5 to settle:
  `.textEditorLineStyle { line in JSONColours.style(line) }` and
  `.textEditorMarks([TextEditorMark(range: errorRange, underline: .init(pattern: .curly, color: .red))])`.
  **Price:** 2 days more (L5). A key stays at 2.6 ms plus the app's lexing of the lines drawn; no memory beyond a
  screenful. A line is styled from its own text, so a construct that spans lines (an XML comment) is styled line
  by line; carrying a lexer's state from one line to the next is about a day more, not proposed until an app
  needs it. It is an addition under its own names, not a change to SwiftUI's API.
- **(c) Neither now.** A42 waits; tuitree stays plain. **Price:** none.

★ (b): SwiftUI's API is the parity A42 decided and serves prose and small files; the styler is what makes a
large source usable, at no cost to anyone who does not use it, and a SwiftUI port of the app keeps using SwiftUI's
spelling. **Default if unanswered:** (a), since (b) adds public API.

### A-ATTRED-2. Which lands first

- **(a) The study's order:** L0, L1, L3, L4 (with L2 inside it), L6, L7, then L5 if approved.
- **(b) ★ The shared pieces, then what tuitree uses:** L0, L1, L2, then L5 if A-ATTRED-1 is (b), then L3, L4,
  L6, L7.

★ (b): L5 needs only L1 and L2, so tuitree has colour after 2½ days instead of 7. **Default:** (b) without L5
until A-ATTRED-1 is answered, which is (a)'s order with L2 split out.

### A-ATTRED-3. Attributes the grid cannot draw, and a paragraph's alignment

- **(a) ★ Ignore them,** as `Text(AttributedString)` does: kerning, tracking, baseline offset, line height, a
  font's size and family, Genmoji, and a paragraph's `alignment`. **Price:** none.
- **(b) Ignore them, but draw a paragraph's alignment** (centred or trailing lines in a wrapping editor; the caret
  and the vertical keys map through the offset). **Price:** about ½ day in L4.
- **(c) As (a), with a runtime warning** the first time each is met. **Price:** ¼ day; a warning an app cannot
  act on.

★ (a): an editor of source or prose in a terminal has no use for centred paragraphs yet. **Default:** (a).

### A-ATTRED-4. The typing attributes at a run's edge

*Typing after a red token, or at the start of a line that begins with one: which attributes does the new
character take?* macOS 26 decides this, and this machine (macOS 15.8.3) cannot run it to measure.

- **(a) ★ `NSTextView`'s rule,** as the study proposed: an `AttributedTextSelection` built with typing
  attributes uses them; otherwise the attributes of the character before the caret, or of the one after it at a
  paragraph's start. Probed when a macOS 26 machine is at hand, and changed then if SwiftUI differs.
  **Price:** none now.
- **(b) Wait for the probe** before L4. **Price:** L4 waits for a machine.

★ (a): it is AppKit's long-standing rule, which SwiftUI's editor on macOS is built on. **Default:** (a).

## 7. The owner's rulings (2026-11-17)

- **A-ATTRED-1: neither (b) as proposed.** The per-line styler, a function from one line's text to its runs, is too
  limited: a line's styling can depend on earlier lines, such as a string or a comment opened above. Syntax
  highlighting is a solved problem in many editors, so dig deeper and design a more scalable, robust solution.
  *What follows:* L5 is withdrawn. The deeper design is [Highlighting a large source in TextEditor: design (G3,
  A-ATTRED-1)](<Highlighting a large source in TextEditor - design (G3, A-ATTRED-1).md>): a line lexer carrying each
  line's end state, re-lexed from an edit until the state converges, the viewport first, the catch-up in slices,
  and marks carried through edits, behind a seam a tree-sitter styler could use. Its questions are A-ATTRED-5 to 7,
  and its lanes H0 to H7 replace L5.
- **A-ATTRED-2: SwiftUI's APIs first.** TUI will need them anyway, and building them may teach something that
  changes the plan. *What follows:* the order is L0, L1, L2, L3, L4, L6, L7, then the H lanes. That is (a)'s
  order, with L2's styled rows ahead of L3 because L4 and the H lanes both draw through them.
- **A-ATTRED-3: draw what can be approximated.** Support a paragraph's alignment. Support line height crudely: a
  line height of 2 puts a blank row between drawn lines. Approximate font information with bold, dim and the like
  where reasonable. Ignore kerning, tracking, baseline offset and the like. *What follows, in L4:*
  - **Alignment** (`AttributedString.TextAlignment`, which has `left`, `center` and `right` only, read from the
    macOS 26.2 SDK's Core Text interface): each row of a paragraph is offset in a wrapping editor, and in an
    unwrapped one where the line is narrower than the editor. Carets, clicks, drags and the vertical keys map
    through the offset. `Text`'s `multilineTextAlignment` already offsets wrapped rows this way.
  - **Line height** (`AttributedString.LineHeight`): `.multiple(factor:)` draws `max(1, factor.rounded())` rows a
    row, the extra ones blank. `.normal`, `.tight`, `.loose`, `.variable`, `.leading(increase:)` and
    `.exact(points:)` draw one, since a grid has no points to count. The blank rows belong to the row above for
    clicks, and the vertical keys step over them.
  - **Fonts**: weights from semibold up draw bold (as today), and light, thin and ultra-light weights draw dim
    (SGR 2). Italic draws italic. Semantic styles draw as `Text`'s three tiers draw them. Size, family, width and
    monospacing are ignored. `Text(AttributedString)` takes the same mapping, so the editor and a `Text` of the same
    value agree. Its golden snapshots are checked in the lane.
  - **Price:** about 1 day more in L4 (alignment ½, line height ¼, fonts ¼), so L4 is 2½ days.
- **A-ATTRED-4: mimic macOS.** The owner asks whether TUI can also have a caret that, at one position, is attached
  either to the character or run before it or to the one after it (upstream or downstream affinity), and whether a
  terminal has the fidelity to show it. *What follows:* §8, measured on this machine's macOS.

**The sum:** SwiftUI's API (L0–L4, L6, L7) about 9 lane-days, then the highlighter (H0–H6, ★) about 7. tuitree has
colour 4½ days after the SwiftUI part.

**attralign (2026-11-19).** Asked whether TUI should keep declaring Core Text's `AttributedString.TextAlignment`
itself (working on macOS 15, but ambiguous when an app names it beside Core Text) or use Core Text's own on Apple
platforms (macOS 26 only, as SwiftUI's), the owner ruled: "(a) but provide our own version anywhere that Core Text
doesn't (e.g. macOS 15) if possible." *What follows:* Core Text's types on the macOS 26 SDK, TUI's identical ones
where no SDK declares them (the macOS 15 SDKs, Linux, Windows, WebAssembly), and, for a program built with the 26
SDK and run on macOS 15, where TUI cannot declare the names without bringing the ambiguity back, TUI's own
`paragraphAlignment` under a name SwiftUI does not use (§5, as built). Line height on the same basis waited on
A-ATTRED-13 (§6), ruled (b) the same day and built (§5): Core Text's `lineHeight` on macOS 26, TUI's identical type
where there is no Core Text, and no attribute of TUI's own.

## 8. The caret's side: affinity and typing attributes

### What macOS does

One offset carries two separate things on macOS.

- **Affinity** says where an offset is *drawn* when it has two places: at a soft wrap, where it is both the end of
  the earlier row and the start of the later one, and at a change of direction in bidirectional text.
  `NSTextView.selectionAffinity` and TextKit 2's `NSTextSelection.affinity` both document it that way. SwiftUI's
  `TextSelectionAffinity` and `AttributedTextSelection.affinity(in:)` carry the same thing.
- **Typing attributes** say what a typed character takes. `NSTextView` resets them whenever the selection changes.
  `NSTextSelection.typingAttributes` and SwiftUI's `AttributedTextSelection.typingAttributes(in:)` carry them per
  selection.

Measured 2026-11-17 on macOS 15.8.3 with an `NSTextView` under TextKit 1 and under TextKit 2 (two standalone
scripts, `xcrun swift`; not kept). The text was "aaa" red, "bbb" blue, a line break orange, "ccc" green. A second
text had an empty paragraph between two lines. TextKit 1 and 2 gave the same typing attributes in every case:

| The caret | Typing attributes |
|---|---|
| At the red–blue edge, come to by Right from inside the red | red |
| The same, come to by Left from inside the blue | red |
| The same, set by the program | red |
| At the document's start | red: its first character's |
| At the second paragraph's start, by Left, by Right or set | green: the paragraph's first character's, not the line break's |
| In an empty paragraph | that paragraph's own line break's |
| Before a line break; at the document's end | the character before |
| After `typingAttributes` was set to green, without moving | green, and a character typed is green |
| A selection, or typing over one | its first character's |
| A selection collapsed by Left or by Right | the character before the new caret |

The affinity reported after those motions differs between the two systems. TextKit 1 reports downstream after
either arrow and upstream when the program set the caret, and TextKit 2 reports upstream for all three. Where no
row wraps, both draw the same, so the difference cannot be seen there.

So **macOS keeps no side at a run's edge.** How the caret got there makes no difference. The character before it
decides, except at a paragraph's start, where the paragraph's first character decides. The only way to type other
attributes at an edge is to set them without moving (⌘B, a colour from the Font panel), and they last until the
caret moves. **At a soft wrap it does keep a side, and draws it.** TUI already does the same, per caret, from the
motions measured on this macOS (`CaretLean`, lane LEAN, 2026-10-27, in
[Text fields and the wrapping editor](<Text fields and the wrapping editor.md#b-d4x-16-upstream-a-caret-moved-onto-a-wrapped-row-lands-after-its-first-character>)).
SwiftUI's macOS 26 editor, which sits on `NSTextView`, is still not measured here. L0 probes it when a macOS 26
machine is at hand.

**Editors that do keep a side** are not Mac ones. Firefox's editable content gives a formatting boundary two caret
positions (as reported on the ProseMirror forum). The ProseMirror plugin `prosemirror-codemark` draws a stand-in
caret, and at an inline code span's edge it makes Left or Right first switch whether the next character is code,
without moving ([curvenote/prosemirror-codemark](https://github.com/curvenote/prosemirror-codemark)). Emacs keeps a side per text property rather than per caret: properties are
rear-sticky by default, so a typed character takes those of the one before it
([Stickiness](https://www.gnu.org/software/emacs/manual/html_node/elisp/Stickiness.html)).

### What a terminal can show

- **A cell, never a gap.** A caret between two characters can only be drawn on a cell: the one after it, as TUI's
  block, underscore and bar are today (the bar glyph ▎ sits at the cell's left edge and reads "before this
  character"), or the one before it.
- **The terminal's own cursor** (shown under `TUI_TEXT_CURSOR_FOLLOWS_FOCUS=show`) has `DECSCUSR`'s shapes: a
  block, an underline or a bar, each steady or blinking, with the bar at the cell's left edge
  ([xterm control sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)). Its one colour, set by
  OSC 12, is the whole terminal's and must be restored at exit. It cannot sit between cells either, or past the last
  column.
- **A wrap has two cells to choose from:** the end of the earlier row, where `SoftWrapLayout`'s margin keeps a cell
  free, and the start of the later one. So a wrap's affinity can be shown in full, and it is.
- **A run's edge has one gap and two neighbours.** A side can only be shown by marking one neighbour. One way is a
  glyph: a right-edge bar (▕, U+2595, in the common block-element fonts) on the cell before for "after the earlier
  run", and the left bar ▎ on the cell after for "before the later run". Each covers the character under it, as the
  bar caret does today. The other way is colour: the caret drawn in the typing attributes' foreground. Colour
  shows only a difference of colour (not bold against plain), and it breaks the owner's rule that every caret
  wears the one focus ink (2026-09-28).

So a terminal has the fidelity for a wrap's affinity, which TUI already draws, and only part of it for a side at a
run's edge.

### B-ATTRED-16. Typing attributes follow the measured rule

A new character takes the attributes of the character before the caret. At a paragraph's start it takes those of
the paragraph's first character (its line break if the paragraph is empty), and at the document's start those of
the first character. Typed over a selection, it takes the selection's first character's. Attributes set at a
caret (`AttributedTextSelection(insertionPoint:typingAttributes:)`, a formatting command with no selection) last
until the caret moves. An empty document uses the editor's own. This replaces A-ATTRED-4 (a)'s description,
which was written before it was measured.

### B-ATTRED-17. `affinity(in:)` reports the caret's lean

`AttributedTextSelection.affinity(in:)` returns the lean `CaretLean` keeps: downstream after the arrows and a
click, upstream after an edit and Ctrl-E. That is TextKit 1's report. TextKit 2 reports upstream after the arrows
too, so the L0 probe on macOS 26 decides which SwiftUI follows, and this changes if it differs. Nothing drawn
depends on it except at a wrap, where TUI already draws the lean.

### B-ATTRED-18. The wrap's affinity is drawn as it is

Unchanged from lane LEAN: upstream at the end of the earlier row, downstream at the start of the later one.

### A-ATTRED-8. A side at a run's edge

- **(a) ★ None, as macOS has.** B-ATTRED-16's rule. **Price:** none.
- **(b) A side per caret,** as Firefox and `prosemirror-codemark` keep. A caret that comes to an edge by Right is
  attached to the run before it, and one that comes by Left to the run after it. At an edge, Left or Right first
  switches the side and then moves. This would be a deliberate deviation from macOS, and from SwiftUI on macOS: it
  changes what a typed character takes, and how many presses an arrow needs. **Price:** 1½ days (the handler, the
  selection's typing attributes, undo), and A-ATTRED-9 (c) to show it. Recorded in *Deliberate deviations* if
  chosen.
- **(c) As (b), behind a TUI modifier** (a sketch: `.textEditorTypingSide(.followsMotion)`), with macOS's rule by
  default. **Price:** 2 days and one more modifier. No deviation by default.

★ (a): the owner asked TUI to mimic macOS, and macOS has no such side. A source editor, the driver here, never
types into a token's attributes, since highlighting is a layer (B-ATTRED-8 in the highlighting design).
**Default:** (a). **Ruled 2026-11-18: (a), "for now".** No side at a run's edge, as macOS; the owner may revisit it.

### A-ATTRED-9. Showing the typing attributes, or a side

- **(a) ★ In the formatting context menu, not on the caret.** L6's Bold, Italic, Underline and Strikethrough items
  are checked from the typing attributes, as macOS's Format menu and Font panel reflect them. The caret is drawn as
  today. **Price:** ¼ day in L6.
- **(b) The caret drawn in the typing attributes.** The block or underscore caret takes the typing foreground, and
  the block's character is drawn bold or italic as a typed one would be. **Price:** ½ day. It departs from the one
  focus ink on every caret (2026-09-28), so it needs the owner's word on that rule as well.
- **(c) An edge glyph for the side,** only with A-ATTRED-8 (b) or (c): ▕ on the cell before, ▎ on the cell after.
  **Price:** ½ day, and a row in the terminal compatibility survey for U+2595 in each terminal's fonts.

★ (a): it is how macOS shows typing attributes, and it keeps the caret's one focus identity. **Default:** (a). **Ruled 2026-11-18: (a).** L6's context menu checks Bold, Italic, Underline and Strikethrough from the typing attributes; the caret keeps its one focus ink.

## 9. What macOS 15 costs (L3)

The owner asked on 2026-11-17 for a ledger of what supporting Swift 6.2's macOS 15 costs. For L3 it is one file,
`Sources/TUITextInput/AttributedText/AttributedTextSelection+MacOS15Fallbacks.swift` (218 lines, 111 of them code
and the rest the documentation of what each approximates), and the `else` arm of four `#available` checks that
call it. Dropping macOS 15 deletes the file and those arms. Linux and Windows never run it: swift-foundation has everything from Swift 6.2 (§L0).

| What macOS 15 lacks | The fallback | What it approximates | Its cost |
|---|---|---|---|
| `Range.isValid(within:)` | Whether the range falls inside the text | An index made from another text, or from this one before a change, is taken as valid if it falls inside it, even inside a character | Two comparisons |
| `transform(updating:body:)` (index tracking) | Runs the body, finds the one span between the longest common start and end of the text before and after, and moves the bounds through it by Foundation's rules (`IndexTracking.swift`'s prepare and finalize steps) | Exact for one contiguous change. Several disjoint changes count as one span, so a bound between them closes up to the span's start or end. A change whose text repeats its neighbours' is placed as late as possible. A change that writes back the same text is not seen. A body that assigns a whole new text is still compared, where Foundation loses track | One copy of the text's storage made shared, so the body's first change copies its path through the tree (0.01 to 0.02 ms for one inserted character here; §4 measured 2.9 ms for an insert into shared storage); both texts read into `String`s; one pass over their UTF-8. Measured on a 3.07 MB document shaped as `bigtext`'s, -O, best of five: 2.6 ms for an insert near the start, 2.9 ms in the middle and at the end, where Foundation's work is per change and bound |
| `removeSubranges(_:)`, and tracking for `replaceSelection` | Removes the ranges from the last, inserts at the first's offset, finds the caret by offset | Nothing: the change is known | A scalar offset to an index for each bound and two more (0.013 ms at the end of 3.07 MB) |
| Tracking in `transformAttributes(in:body:)` | Sets the runs' attributes and keeps the indices | Nothing: setting attributes moves no character, and a macOS 15 index is its offset | None |

**L4 adds no fallback.** The attributed editor reads the app's selection through `indices(in:)`, whose validity on
macOS 15 is the bounds check above, and finds an offset's index through the character view, which costs a
microsecond there (below). Its edits are made by offset, not tracked, so they need no tracking fallback. A paragraph's alignment costs macOS
15 SwiftUI's spelling (attralign, §5 as built): a program built with the 26 SDK sets Core Text's `alignment` only on
macOS 26, and on macOS 15 sets TUI's `paragraphAlignment` instead. The ledger's row M11 counts it.

**The offset-to-index walk** (the owner's question): on macOS 15.8.3 Foundation's `AttributedString` finds an index
from a character or scalar offset through its rope, so no walk happens. Without the UTF-8 view, on a
3,074,445-byte document shaped as `bigtext`'s (40,000 JSON records, one a line; a standalone probe, not kept,
built with Xcode's Swift 6.2.4 at -O, best of five, while other lanes built):

| Conversion | At the document's end | Three quarters in |
|---|---|---|
| `characters.index(_:offsetBy:)` | 0.001 ms | 0.001 ms |
| `unicodeScalars.index(_:offsetBy:)` | 0.001 ms | |
| `characters.distance(from:to:)` (index to offset) | 0.001 ms | |

The same held with accented letters, combining marks and emoji spread through the text. So B-ATTRED-3's "up to
1.8 ms (three quarters of the way in)" is not what macOS 15.8.3's Foundation does for an offset; whatever that probe
walked, the L4 editor can map a character offset to an index for about a microsecond on macOS 15, and does not need
the UTF-8 view for it.

**What is slow is reading the characters one by one.** Comparing two 3 MB texts element by element through the
views took 0.9 to 1.2 s through the scalar view and 1.7 to 2.2 s through the character view, which is what a naive
common-start-and-end comparison would cost. Foundation's `String(_:)` of a character-view slice copies the rope's
chunks instead (0.56 ms for the whole text), so the fallback reads both texts into `String`s and compares
their UTF-8 bytes.

## For a future reader

- **B-ATTRED-4's price is Foundation's, not TUI's.** If a later Foundation gives `AttributedString`'s character
  view an identity check or `Equatable` with a fast path, an attribute-only write becomes cheap, and L5's styler
  would matter less; measure again then.
- **The cost probe** is not kept in the repository: it built a 1.9 MB JSON text of 40,002 lines, coloured each
  of its 400,002 tokens with one or two custom attributes through the unicode-scalar view (the UTF-8 view needs
  macOS 26), and timed one insert in the middle, `==`, `String(characters)`, `elementsEqual` of the characters,
  a screenful's runs and a line's recolour, reading the process's `phys_footprint` for memory. L0 rebuilds it.
- **EDITOR-SPLICE's open item** (the text held as lines of `Character`, 16 bytes a character) is untouched by
  this design and independent of it.
