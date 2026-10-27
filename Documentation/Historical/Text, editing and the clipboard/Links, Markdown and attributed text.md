# Links, Markdown and attributed text

*How a `Text` draws links and Markdown, what a control's title key does with
Markdown, the attribute scope, and the typography declined. Ids: B84 to B88,
B85-KEYBOARD, B86, C8, C13, C14.*

## In short

A link in a `Text` is drawn and hyperlinked (OSC 8), and is a control: a Tab
stop that breathes, opened on Return or a click with the destination popover,
with `Link`'s menu on Shift-F10. TUI parses Markdown itself, and since
2026-10-26 decodes all 2,125 HTML named entities and reads link reference
definitions, as Foundation does. A bare URL whose host Foundation refuses is
drawn as text. A control's title key is parsed, though a column header and a
tab title draw only its words.

## How it unfolded

1. **B84 to B88** shipped the attribute scope, links, the parse and titles.
2. **2026-10-23, the owner:** full control for links (B85-KEYBOARD, built
   2026-10-24); asked about Foundation's parser and versions (B86).
3. **2026-10-26, B86: both now.** The entity table (stored compressed) and
   link reference definitions shipped. A fuzz run of 40,000 strings then found
   two more differences from Foundation; the autolink ones were fixed the same
   day.

## For a future reader

- **Open: Apple's `^[…](attrs)` syntax with unparseable attributes** — Foundation
  draws the bracket text alone, TUI keeps the literal (5 in 20,000 fuzz
  strings). Investigate Foundation's rule.

## The record

### B84. On macOS, SwiftUI's attribute scope is visible beside TUI's

*`AttributeScopes.SwiftUIAttributes` and its members, `AttributeScopes.swiftUI`,
`AttributeDynamicLookup.subscript(dynamicMember:)`*

TUI imports AppKit (for the `NSColor` and `NSImage` bridges), and AppKit
loads SwiftUICore. Swift makes every extension member of every loaded module
visible, so a TUI app on macOS sees SwiftUICore's
`AttributeScopes.SwiftUIAttributes` as well as TUI's. This is the same leak
B50 met with `SystemFormatStyle`'s statics.

**Since 2026-10-05 this applies only to an app that imports `TUIAppKit`
(or AppKit itself).** B50 shipped: the AppKit bridges are the `TUIAppKit`
module, no module TUI is built from imports AppKit (a test guards it), and
an app that imports TUI alone sees no SwiftUICore member. The rest of this
entry describes the app that imports the bridges too.

**Shipped:**

- **Setting and reading an attribute binds to TUI's.**
  `string.foregroundColor = .red` and the rest resolve here, because TUI
  declares one dynamic-member subscript per key where SwiftUI declares one
  generic subscript. A concrete overload outranks a generic one, so TUI's
  wins; two generic ones would tie and be ambiguous. (AppKit's own subscript is
  `@_disfavoredOverload`, which is how SwiftUI's beats AppKit's.) This was
  measured against a standalone module that imports AppKit, and it is pinned
  by the compile corpus.
- **Inside TUI, the leak is closed.** The TUI target turns on
  `MemberImportVisibility`, so SwiftUICore, which no TUI file imports, is
  invisible there. Without it, TUI could not spell its own scope in a type
  position.

**What remains, on macOS only:**

- **Naming the scope's types in a type position is ambiguous** in an app,
  for example `let key: AttributeScopes.SwiftUIAttributes.FontAttribute.Type`.
  The test suite reaches keys through the lookup for this reason.
- **An attribute only SwiftUI has, such as `kern`, compiles and then fails to
  link.** It binds to SwiftUICore's subscript, and SwiftUICore admits no
  direct clients. On Linux it fails to compile, as rule 2 wants.

**The fuller version** was B50's, and shipped with it on 2026-10-05: the AppKit
bridges (`Color(nsColor:)`, `NSColor(_:)`, the `CGColor` pair, `Image`'s
`NSImage`/`CGImage` initializers) are the `TUIAppKit` module. An
`internal import` of AppKit was not enough — it still loads SwiftUICore into
clients of a SwiftPM module — so TUI imports none.

### B85. A link in a `Text` is drawn and hyperlinked, and is a control

*`AttributeScopes.FoundationAttributes.link` as `Text` draws it; Markdown
`[label](<../../SwiftUI parity/Decisions/url>)` and autolinks*

SwiftUI makes a `Text`'s link clickable, and it opens through the
`OpenURLAction` in the environment.

**Shipped:** a link run is drawn as follows:

- **Colour:** the accent, which follows `.tint`, as SwiftUI's link colour does.
  The run's own colour wins over it, and the text's `.foregroundStyle` does not
  reach it, as measured.
- **Underline:** underlined, as `Link` is. This is TUI's deviation, for
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
2. ~~**Honour `.linkDisplay(.urlInParentheses)` and `.urlOnly` for text
   links.**~~ Built 2026-10-19 (lane TEXTEDIT, B85-LINKDISPLAY): under either
   mode a text's link writes its URL after its label or in its place, in the
   link's style and inside its hyperlink, so Terminal.app users can read it;
   the measure counts it. `.popover`, the default, leaves the link as it was.

**Recommendation:** 2 now if Terminal.app matters; 1 when an app needs inline
links it can activate.

**1 ruled (owner, 2026-10-23, B85-KEYBOARD: "Full control"), and built (lane
KEYS, 2026-10-24).** Where a `Link` is a control — `.linkDisplay(.popover)`,
the default — so is each link in a `Text`:

- **A Tab stop**, `text-link-<identity path>#<run>`, in reading order with the
  page's other stops. A link the text wraps is one stop.
- **Breathes** while it holds the focus, as a `Link`'s words do
  (`BreathingLabel`): the text drawn once per colour of the breath, its rows
  that the link reaches replayed, the rest still.
- **Return, Space or a click** (press and release over it) does what
  activating a `Link` does: opens the destination through `OpenURLAction`, or
  copies it under `.linkActivation(.copy)`, and raises the destination's
  popover, anchored at the link's first row. A held Return opens once
  (`LinkActivationGate`).
- **Shift+F10, the Menu key or a right-click** opens `Link`'s menu on it:
  Show Link, Copy Link, Copy Label, Copy as Markdown. A right-click on the
  text's other words opens nothing: the menu's pointer trigger lies over the
  links alone (`ContextMenuModifier.KeyboardRoute.contentStopRegions`), and a
  right-click gives the link the focus first, so the menu is that link's.

Not a stop, as `Link` is not a control there: under `.linkDisplay(.urlOnly)`
and `.urlInParentheses`; in a disabled subtree, or one whose focus is
suppressed; in a list's or table's row, where the list is the stop; outside a
running app. Known, and left: a link inside another control's label — a
`Button` titled with a Markdown link — is a stop of its own beside the
control's, because telling a label apart would cost every control an
environment write per frame.

The text draws through a private composite (`_TextLinks`, at a child
identity) only when it has a link, so a text with none pays a nil check. One
with links pays, per frame, the composite, its menu and popover modifiers and
a focus registration, a pointer region and a menu key per link — all
replayed from a memo where it is served — and, while a link holds the focus,
a drawing of the text per colour of the breath.
`TextLinkStopsTests` pins all of it through the app; the Example's Buttons
page has one (`page.buttons.links.textLink`).

### B86. TUI's Markdown parse is its own, with two known differences

*Markdown in `Text(_ key: LocalizedStringKey)`*

Foundation's Markdown parser is Darwin-only. swift-foundation has neither
`AttributedString(markdown:)` nor `InlinePresentationIntent`; this was checked
on the 6.3.3 static Linux SDK. TUI therefore parses with `InlineMarkdown`:

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
   TUI draws both as text. Definitions and reference links would take half
   a day. A UI string that starts with `[x]: …` is rare.

**Two places where TUI draws differently, neither a parse difference:**

- **`^[text](inflect: true)`** (automatic grammar agreement) draws its text
  without inflecting it. TUI has no inflection engine. SwiftUI also draws
  "2 apple" when it has no localized bundle, as measured.
- **A code span** draws as plain text, because every cell is monospaced
  already.

**Cost:** a key whose resolved text holds none of the bytes a construct starts
with, no `://`, no `www.` and no `@` after an address character pays one
allocation-free byte scan and takes the old path. A Markdown text's runs are a fresh array each frame, so the
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

**The A/B, run in the performance pass (quiet machine, `ab_bench.py`), found
the scan letting every interpolated key through.** An interpolation's
placeholder is `%@`, and the scan took any `@` as a possible email address, so
`Text("#\(index)")` ran the whole parse on every construction:
`scrollfollow` +53%, `churn` +18% and `gradients` +12% against the build before
this lane. The scan now takes an `@` only after a byte an address's local part
can end with, as the email scan itself requires; that recovered `scrollfollow`
−33%, `churn` −14%, `gradients` −9%. A key that really holds Markdown parses
its template once: the parse never reads a value, so it is kept per resolved
template (`MarkdownTemplate`, with whether the key has values), and each
construction only puts its values in.

**Recommendation:** leave both differences until a translation needs them.

**Since closed, the first (owner ruling B86, 2026-10-26: "support the full
entity table … now"):** all 2,125 named references decode
(`HTMLEntities`), generated from Python's `html.entities.html5` by
`Tools/GenerateHTMLEntities/generate.py` and stored front-coded as the SF
Symbols table is (`FrontCodedNames`): 12,242 bytes of names and 8,341 of
values, compile-time data a lookup reads in place. DEFLATE would halve it but
put the inflated table in dirty memory in every process. `HTMLEntitiesTests`
checks every name against Foundation's parser on Darwin.

**Since closed, the second (the same ruling):** link reference definitions
at the start of a key, and the full, collapsed and shortcut references that
use them, read as Foundation reads them in inline-only mode
(`InlineMarkdownParser+ReferenceDefinitions.swift`, which states the rules
measured: definitions only at the very start, a destination that runs into
the end making none, labels fully case-folded, the first definition of a label
used, an undefined full reference left as text, image references drawn as
their alt text). `InlineMarkdownReferenceTests` holds the 41 measured cases
and checks each against Foundation live on Darwin; a run of 40,000 random
strings of reference syntax against Foundation found no difference in
references, and one elsewhere: a bare URL holding `"` or `>` was linked here
and left unlinked by Foundation. Fixed the same day. Foundation makes a link
only where `URL(string:)` accepts the destination, and what it refuses is a
host holding `"`, `<`, `>`, `\`, `^`, a backtick, `{`, `|`, `}`, `[`, `]` or a
stray `%`, or a port that is not all digits; the rest of a destination,
user information included, is percent-encoded. So every kind of link with
such a host is its text alone, here as there
(`InlineMarkdownParser.hasLinkableAuthority`,
`InlineMarkdownLinkAuthorityTests`, 34 measured cases).

### B87. Markdown in a control's title key: parsed, though a column header and a tab title draw only its words

*`Button(_:action:)` and the other `LocalizedStringKey` initializers*

SwiftUI parses Markdown in a control's title key. Measured: `Button("**Save**")
{}`, `Toggle`, `Label`, `Link` and `LabeledContent` all draw the bold. TUI's
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
- **What stays as is:** TUI's own chrome (status-bar labels, `AlertPanel`,
  `Card`, `Dialog` titles) has no SwiftUI meaning to match.

**Recommendation:** do it for the SwiftUI controls listed above.

**Shipped 2026-10-15.** Every control whose SwiftUI label is a `Text` made from
the key builds it with `Text(titleKey)`: `Toggle`, `Label`, `Link`, `Section`,
`LabeledContent`, `Picker`, `Menu`, `NavigationLink`, `Stepper`, `Slider`,
`ProgressView`, `Gauge`, `DatePicker`, `ContentUnavailableView` and the
`systemImage:` forms (`DisclosureGroup`, `GroupBox` and `ControlGroup` already
did). `Button` and `ColorPicker` keep their title as a `String`: a key whose
Markdown styles it is drawn as its `Text`, and its plain words stay the title.
A plain key costs the byte scan `Text` already pays. Not done: a `TextField`'s
title (drawn as its placeholder), a `TableColumn`'s header and a `Tab`'s title,
which are measured and drawn as strings; and TUI's own chrome, as above.
Tests: `MarkdownTitleTests`.

**2026-10-18 (lane PARITYMISC):** the three are parsed. A `TextField`'s title is
its `Text`, and its placeholder draws the words plain, as SwiftUI's does
(measured); a header and a tab title draw the words in their own style, the
styles not yet
([B-PARITYMISC-3](<../../SwiftUI parity/Decisions/Small parity items (PARITYMISC).md#b-paritymisc-3-a-column-header-and-a-tab-title-draw-their-keys-markdown-words-not-its-styles>)).

### B88. An attributed format interpolated into a key draws the characters only

*`Text(_:format:)` over a `TimeDataSource` with an `AttributedString` output;
`LocalizedStringKey.StringInterpolation.appendInterpolation(_:format:)` with
one*

The one-off `Text(_:format:)` now draws an attributed output's attributes.
An interpolation's arguments are strings, so
`appendInterpolation(_:format:)` draws only the characters.

**Built 2026-10-19** (lane TEXTEDIT): the live form over a `TimeDataSource`
draws them too. A live source may return styled runs as well as words, and
the attributed format's source returns the runs `Text(_:)` keeps of its
output at each frame, over the live run's own style. A plain output, and every
other live source, reads words as before.

Foundation's own attributed styles set only field attributes, which say what a
run is (a year, a day) rather than how it looks, and SwiftUI ignores them too.
So the only difference is for a custom style that colours its output.

**The fuller version:** an interpolation that keeps an attributed argument's
runs, which needs the key's substitution to splice runs. Not priced.

### C8. `TypesettingLanguage`

*`TypesettingLanguage` (`.automatic`, `.explicit(_:)`),
`View.typesettingLanguage(_:isEnabled:)` and `Text.typesettingLanguage(_:isEnabled:)`
in both forms*

The language a run is typeset in sets its line height (taller for Thai, say),
its line breaking and its spacing. Line height is the terminal's row, and
spacing is whole cells. TUI's word wrapper breaks at spaces and at
characters a line cannot hold, whatever the language, so a language would
change none of the three, and accepting one would be the quiet no-op the
parity rules forbid. If the wrapper ever learns dictionary-based breaking
(Thai, Khmer and Lao have no spaces between words), this becomes its
modifier.

### C13. Sub-cell typography and paragraph metrics in the scope

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
link; see B84. `parity-map.json` has a family entry for them.

### C14. The adaptive image glyph

*`AttributeScopes.SwiftUIAttributes.adaptiveImageGlyph`,
`AdaptiveImageGlyphAttribute` and its members*

A Genmoji is a multi-resolution bitmap drawn inline at the font's size. A cell
holds a character. The image protocols that can place a picture do so at block
level, not as glyphs in a run of text. `parity-map.json` has a family entry.

`AttributeScopes.SwiftUIAttributes.accessibility` needed no entry of its own.
The existing Accessibility family covers it.
