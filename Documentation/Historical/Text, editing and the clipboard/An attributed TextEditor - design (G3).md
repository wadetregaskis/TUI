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
caret's side at a run's edge and at a wrap, measured on macOS, is §8 (A-ATTRED-8 and 9, B-ATTRED-16 to 18).*

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
| `alignment` (a paragraph's) | Could be drawn per line in a wrapping editor | Not read | Ignored (A-ATTRED-3) |
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

## 6. Questions for the owner

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
**Default:** (a).

### A-ATTRED-9. Showing the typing attributes, or a side

- **(a) ★ In the formatting context menu, not on the caret.** L6's Bold, Italic, Underline and Strikethrough items
  are checked from the typing attributes, as macOS's Format menu and Font panel reflect them. The caret is drawn as
  today. **Price:** ¼ day in L6.
- **(b) The caret drawn in the typing attributes.** The block or underscore caret takes the typing foreground, and
  the block's character is drawn bold or italic as a typed one would be. **Price:** ½ day. It departs from the one
  focus ink on every caret (2026-09-28), so it needs the owner's word on that rule as well.
- **(c) An edge glyph for the side,** only with A-ATTRED-8 (b) or (c): ▕ on the cell before, ▎ on the cell after.
  **Price:** ½ day, and a row in the terminal compatibility survey for U+2595 in each terminal's fonts.

★ (a): it is how macOS shows typing attributes, and it keeps the caret's one focus identity. **Default:** (a).

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
