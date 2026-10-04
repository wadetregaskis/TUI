# Wave 17t: attributed text — decisions for review

*Wave 17t acted on refusal review P8: `Text(AttributedString)`, SwiftUI's
attribute scope and its dynamic lookup, and the Markdown SwiftUI applies to a
`Text` made from a key. These entries fold into
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md)
in its format. SwiftUI's behaviour was measured on macOS 15.8 (SDK 26.2) by
rendering both spellings of each case in an offscreen `NSHostingView` and
comparing the bitmaps; the probes are in the session notes, `w17t/probe`.*

**Shipped:** `Text(_:)` for an `AttributedString`;
`AttributeScopes.SwiftUIAttributes` with `foregroundColor`, `backgroundColor`,
`font`, `underlineStyle`, `strikethroughStyle` and `foundation`, their five key
types, `AttributeScopes.swiftUI`, `AttributeDynamicLookup.subscript(dynamicMember:)`;
`Text.LineStyle` with `.single`; Foundation's `link` drawn as a link with an
OSC 8 hyperlink, and its `inlinePresentationIntent` where Foundation has it;
Markdown in a `Text` made from a key; `Text(_:format:)` drawing an attributed
output's attributes. `api_parity.py`: 26 symbols move from explained to
shared, `Text.LineStyle` and `.single` close, no new gaps, no stale entries.

---

## A. Needs your decision

None.

---

## B. Shipped the safe option

### B-W17t-1. On macOS, SwiftUI's attribute scope is visible beside TUIkit's

*`AttributeScopes.SwiftUIAttributes` and its members, `AttributeScopes.swiftUI`,
`AttributeDynamicLookup.subscript(dynamicMember:)`*

TUIkit imports AppKit (for the `NSColor` and `NSImage` bridges), and AppKit
loads SwiftUICore. Swift makes every extension member of every loaded module
visible, so a TUIkit app on macOS sees SwiftUICore's
`AttributeScopes.SwiftUIAttributes` as well as TUIkit's. This is the same leak
B50 met with `SystemFormatStyle`'s statics.

**Shipped:**

- **Setting and reading an attribute binds to TUIkit's.**
  `string.foregroundColor = .red` and the rest resolve here, because TUIkit
  declares one dynamic-member subscript per key where SwiftUI declares one
  generic subscript. A concrete overload outranks a generic one, so TUIkit's
  wins; two generic ones would tie and be ambiguous. (AppKit's own subscript is
  `@_disfavoredOverload`, which is how SwiftUI's beats AppKit's.) This was
  measured against a standalone module that imports AppKit, and it is pinned
  by the compile corpus.
- **Inside TUIkit, the leak is closed.** The TUIkit target turns on
  `MemberImportVisibility`, so SwiftUICore, which no TUIkit file imports, is
  invisible there. Without it, TUIkit could not spell its own scope in a type
  position.

**What remains, on macOS only:**

- **Naming the scope's types in a type position is ambiguous** in an app,
  for example `let key: AttributeScopes.SwiftUIAttributes.FontAttribute.Type`.
  The test suite reaches keys through the lookup for this reason.
- **An attribute only SwiftUI has, such as `kern`, compiles and then fails to
  link.** It binds to SwiftUICore's subscript, and SwiftUICore admits no
  direct clients. On Linux it fails to compile, as rule 2 wants.

**The fuller version** is B50's: move the AppKit bridges (`Color(nsColor:)`,
`NSColor(_:)`, the `CGColor` pair, `Image`'s `NSImage`/`CGImage` initializers)
into a module of their own. TUIkit could then import AppKit internally, and no
SwiftUICore member would reach an app. That fixes this and B50 together. It
costs half a day with the documentation, plus one more product to import for
the bridges.

### B-W17t-2. A link in a `Text` is drawn and hyperlinked, but is not a control

*`AttributeScopes.FoundationAttributes.link` as `Text` draws it; Markdown
`[label](url)` and autolinks*

SwiftUI makes a `Text`'s link clickable, and it opens through the
`OpenURLAction` in the environment.

**Shipped:** a link run is drawn as follows:

- **Colour:** the accent, which follows `.tint`, as SwiftUI's link colour does.
  The run's own colour wins over it, and the text's `.foregroundStyle` does not
  reach it, as measured.
- **Underline:** underlined, as `Link` is. This is TUIkit's deviation, for
  `Link`'s reason. `.linkUnderline(false)` removes it.
- **Hyperlink:** an OSC 8 hyperlink under `Link`'s three conditions:
  - the host honours OSC 8;
  - `.terminalHyperlinks` allows it;
  - the text is enabled.

  It is emitted as one balanced pair per line, with an id when the link wraps.

The destination is the terminal's to show and open. The link takes no focus
and no click, so on a host without OSC 8 (Apple Terminal) the destination
cannot be reached from the text.

**The fuller version:**

1. **Make a text's links reachable from the keyboard.**
   - Each link registers a focus stop (`text-link-<identity path>#<run>`), and
     Tab moves through them.
   - A focused link's words breathe, as `Link`'s `.text` indicator does.
   - Return opens the link through `OpenURLAction` and raises `Link`'s
     destination popover.
   - A click on a link fragment does the same. That needs a hit region per
     fragment, which the render already knows.

   About two days. The work is a leaf `Text` that registers focus and animates
   one run. The keyboard part is not optional: a click-only link would break
   the no-mouse-only rule.
2. **Honour `.linkDisplay(.urlInParentheses)` and `.urlOnly` for text links.**
   The URL would be written after or instead of the label, so Terminal.app
   users can read it. Half a day. The measure has to see the added text.

**Recommendation:** 2 now if Terminal.app matters; 1 when an app needs inline
links it can activate.

### B-W17t-3. TUIkit's Markdown parse is its own, with two known differences

*Markdown in `Text(_ key: LocalizedStringKey)`*

Foundation's Markdown parser is Darwin-only. swift-foundation has neither
`AttributedString(markdown:)` nor `InlinePresentationIntent`; this was checked
on the 6.3.3 static Linux SDK. TUIkit therefore parses with `InlineMarkdown`:

- CommonMark's inline algorithm;
- cmark-gfm's strikethrough and autolink extensions;
- Foundation's own quirks, each one measured:
  - a tilde is a skip character;
  - emphasis nested in emphasis ends the outer one;
  - openers are keyed in the pre-0.30 way;
  - an unbalanced `(` is allowed in a bare destination;
  - the email scan's carried dot count;
  - link text drops its emphasis;
  - an image with no alt text becomes U+FFFC.

It agrees with Foundation on a 138-case table and on 550,000 random strings,
with two exceptions:

1. **Named character references beyond about 140 common ones.** `&Aacute;`
   draws as written; Foundation knows all 2,125 HTML names. The full table is
   20 KB of generated source and an hour's work.
2. **Link reference definitions.** In inline-only mode Foundation still
   consumes a `[label]: destination` line and makes `[label]` elsewhere a link.
   TUIkit draws both as text. Definitions and reference links would take half
   a day. A UI string that starts with `[x]: …` is rare.

**Two places where TUIkit draws differently, neither a parse difference:**

- **`^[text](inflect: true)`** (automatic grammar agreement) draws its text
  without inflecting it. TUIkit has no inflection engine. SwiftUI also draws
  "2 apple" when it has no localized bundle, as measured.
- **A code span** draws as plain text, because every cell is monospaced
  already.

**Cost:** a key whose resolved text holds none of the bytes a construct starts
with, no `://` and no `www.` pays one allocation-free byte scan and takes the
old path. A Markdown text's runs are a fresh array each frame, so the
per-pass value memo misses on such a text. That is already true of every
concatenated text.

The memo counters agree with that. `Stress --bench`, 200 iterations, was run
before this wave and after it on `textwall`, `fanout`, `menus`, `kitchensink`
and `dashboard`:

- Every checksum is identical.
- Every memo count is identical. On `kitchensink` and `dashboard` that took a
  second run of the base build, whose first run differed by the run-to-run
  variation the Stress README describes.
- `Text`'s stored size is unchanged (56 bytes, the `TextLayoutPaddingTests`
  pin).

**An A/B on a quiet machine is owed.**

**Recommendation:** leave both differences until a translation needs them.

### B-W17t-4. Markdown in the title keys of controls other than `Text` is not parsed yet

*`Button(_:action:)` and the other `LocalizedStringKey` initializers*

SwiftUI parses Markdown in a control's title key. Measured: `Button("**Save**")
{}`, `Toggle`, `Label`, `Link` and `LabeledContent` all draw the bold. TUIkit's
controls resolve the key eagerly to a `String` (`key.localized`) and draw it as
written, so the asterisks show. This gap existed before this wave. It is more
visible now that `Text("**Save**")` is bold.

**The fuller version:** each control whose SwiftUI label is a `Text` builds its
label with `Text(titleKey)`.

- **Scope:** about 30 initializers across about 20 controls, including
  `Button`, `Toggle`, `Label`, `Link`, `LabeledContent`, `Section`, `Picker`,
  `Menu` and `DisclosureGroup`.
- **Prerequisite:** some of these store the title as a `String` and measure or
  truncate it, `Button`'s `label` among them. They would store a `Text` and
  measure that instead.
- **Price:** about a day with the tests. The `LocalizedTitleTests` round trips
  would each gain a Markdown case.
- **What stays as is:** TUIkit's own chrome (status-bar labels, `Alert`,
  `Card`, `Dialog` titles) has no SwiftUI meaning to match.

**Recommendation:** do it for the SwiftUI controls listed above.

### B-W17t-5. A live text with an attributed format draws the characters only

*`Text(_:format:)` over a `TimeDataSource` with an `AttributedString` output;
`LocalizedStringKey.StringInterpolation.appendInterpolation(_:format:)` with
one*

The one-off `Text(_:format:)` now draws an attributed output's attributes.
The live form reads only words at each frame (a `LiveTextSource` returns a
`String`), and an interpolation's arguments are strings. Neither draws the
attributes.

Foundation's own attributed styles set only field attributes, which say what a
run is (a year, a day) rather than how it looks, and SwiftUI ignores them too.
So the only difference is for a custom style that colours its output.

**The fuller version:** a live source that returns runs. About half a day.

---

## C. Declined without asking

### C-W17t-1. Sub-cell typography and paragraph metrics in the scope

*`AttributeScopes.SwiftUIAttributes.kern`, `.tracking`, `.baselineOffset`,
`.lineHeight`, `.alignment`, and `KerningAttribute`, `TrackingAttribute`,
`BaselineOffsetAttribute` with their members*

These are the attributed-string form of the `View` modifiers C8 declined. A
cell grid has one advance per cell, one baseline and one line height.

A run's paragraph `alignment` has nothing to carry it either. A `Text` aligns
its lines as one block (`multilineTextAlignment`), never paragraph by
paragraph, and `alignment` is macOS 26's, typed as a CoreText scope Linux does
not have.

Omitting them means setting one fails to compile on Linux. On macOS it fails to
link; see B-W17t-1. `parity-map.json` has a family entry for them.

### C-W17t-2. The adaptive image glyph

*`AttributeScopes.SwiftUIAttributes.adaptiveImageGlyph`,
`AdaptiveImageGlyphAttribute` and its members*

A Genmoji is a multi-resolution bitmap drawn inline at the font's size. A cell
holds a character. The image protocols that can place a picture do so at block
level, not as glyphs in a run of text. `parity-map.json` has a family entry.

`AttributeScopes.SwiftUIAttributes.accessibility` needed no entry of its own.
The existing Accessibility family covers it.

---

## D. Deferred to other waves

- **`AttributedTextFormatting*`** (macOS 26 rich-text editing) stays with
  **A42**, which waits on an attributed `TextEditor`. `Text(AttributedString)`
  now exists for that editor to build on. The family entry stays, with its
  reason corrected.
- **`Text.LineStyle`'s patterns and colours** (`init(pattern:color:)`,
  `Pattern`, `init?(nsUnderlineStyle:)`, and the `underline`/`strikethrough`
  overloads that take them) belong to **Wave 11b**, which waits on terminal
  measurements of `4:x` and SGR 58. This wave's `Text.LineStyle` is the type
  11b extends, in `Text+LineStyle.swift`.
- **The keys' `Codable` conformances** (`encode(_:to:)`/`decode(from:)` on the
  five keys, which are macOS 26's) need `Codable` values. TUIkit's `Color` can
  name a palette role or carry a gradient, and neither it nor `Font` is
  `Codable`. Making both `Codable` takes about half a day, and no wave owns it.
  `parity-map.json` has a family entry, with that reason.
