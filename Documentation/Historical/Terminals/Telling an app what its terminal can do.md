# Telling an app what its terminal can do

*How `\.terminalCapabilities` came to be: a read-only, settling answer to
"does this terminal draw patterned underlines, overlines, blink, graphics…",
so a page can say what its terminal does not draw. Ids: TERMCAPS-API (item
#9); the proposal of 2026-10-23, appended.*

## In short

`\.terminalCapabilities` answers supported, unsupported or undetermined per
feature, settling as replies and observations arrive: one `OptionSet` with a
member per style and group constants, colour depth passed through from
`ColorDepth`. Built 2026-10-24 as the owner answered the proposal's questions.



## Appendix: terminal capabilities for apps, the proposal (2026-10-23)

> **Historical: built 2026-10-24** (decisions TERMCAPS-API; `git log --grep TERMCAPS-API`). The owner
> answered the open questions on 2026-10-24, and the API differs from this draft where he did:
>
> - **Names** as drafted: `\.terminalCapabilities`, `TerminalCapabilities.Feature`.
> - **Colour depth** stays `ColorDepth`; `TerminalCapabilities.colorDepth` passes `ColorDepth.current`
>   through, so there is no copy.
> - **Granularity:** one `OptionSet` (UInt64) with a member per style (`.curlyUnderline`,
>   `.dottedUnderline`, `.dashedUnderline`, not one `patternedUnderline` case), and groups for asking
>   broadly (`.patternedUnderline`, `.textDecorations`, `.hostIntegration`, `.keyboard`), with
>   `supports(_:)` and `supportsAny(of:)`.
> - **Three states** as drafted, named `Status` (`.supported`, `.unsupported`, `.undetermined`), held as
>   `supported` and `unsupported` sets and asked with `status(of:)` rather than a subscript.
> - **Scope** includes input where a query or the person's input settles it reliably: the seven
>   keyboard features the kitty protocol's negotiation decides, and Option as Meta, learnt from an
>   Option chord that arrives as one (never settled as unsupported: a composed character cannot be told
>   from one typed on a layout that has it).
> - **Not built:** `terminalName` and `explanation(for:)`. TUI names the terminal through
>   `TerminalClient.current`, and the Example writes its own words (`CapabilityNote`, the Terminal
>   page's list), so no explanation strings were added to TUI's tables.
>
> Each feature's documentation (`Sources/TUITerminalHost/Capabilities/TerminalCapabilities+Feature.swift`)
> says how it is determined; the survey's "Where the adaptations live" lists the sources.

The owner's item 9: the Example should say, only where it is true, that a feature it shows
does not work in the terminal in front of you. For example, the Text Styles page's patterned
underlines should carry a quiet note under Apple Terminal, which paints `4:3` as a coloured
background. Today the Example hard-codes such notes for everyone. Doing it properly needs a way
for an app to ask TUI what this terminal does. The owner worried that such an API might be
invasive or complex, and asked for a draft to see how it would work. This is that draft. Nothing
is built.

### What TUI already knows

TUI already decides each of these per host, from measured tables in TUITerminalHost and
TUICore, and uses the answer to avoid sending what a terminal would misdraw:

| Feature | Where the answer lives today | Public? |
|---|---|---|
| Double, patterned (curly, dotted, dashed) underlines; underline colour; strikethrough colour | `TerminalHost.lineStyles(for:)` → `LineStyleSupport` | package |
| OSC 8 hyperlinks | `TerminalClient.honoursHyperlinks(_:)`, `TerminalHyperlink.isSupported` | public |
| Pictures (kitty graphics) | `KittyGraphics.isSupported` (asked at startup) | public |
| OSC 52 clipboard writes | `TerminalClient.honoursClipboardWrites(_:)`, `clipboardWrites` | public |
| Desktop notifications (OSC 9 / 777) | `TerminalClient.honoursNotifications(_:)` | public |
| Progress on the tab (OSC 9;4) | `TerminalClient.honoursProgressReports(_:)` | public |
| Emoji-repertoire chrome | `TerminalHost.supportsEmojiChrome` | package |
| Colour depth (16 / 256 / 24-bit) | `ColorDepth.current` | public |
| Pointer shapes (OSC 22) | the pointer-shape table (decisions O12) | package |
| Key reports with every modifier (kitty keyboard protocol) | the startup negotiation | package |

So the facts exist, and most are public already, but they are scattered across a handful of
types and spelled differently (`isSupported`, `honours…(_:)`, `supports…`). An app has no single
place to ask, and no words to show a person.

### The proposal

One read-only value in the environment, TUI-specific, for asking what the terminal draws or does:

```swift
@Environment(\.terminalCapabilities) private var terminal

if terminal[.patternedUnderline] == .unsupported {
    Text(terminal.explanation(for: .patternedUnderline))   // "Apple Terminal draws only a plain underline"
        .foregroundStyle(.tertiary)
}
```

```swift
public struct TerminalCapabilities: Sendable, Equatable {
    public enum Feature: Sendable, CaseIterable {
        case doubleUnderline, patternedUnderline, underlineColor, strikethroughColor
        case hyperlinks, pictures, clipboardWrites, notifications, progressReports
        case pointerShapes, colorDepth24Bit, colorDepth256, modifierKeyReports
    }
    public enum Support: Sendable { case supported, unsupported, unknown }

    /// The terminal's name as a person knows it ("Apple Terminal", "Ghostty"), or nil.
    public var terminalName: String? { get }
    public subscript(_ feature: Feature) -> Support { get }
    /// A short, localised sentence for a person: what this terminal does instead.
    public func explanation(for feature: Feature) -> LocalizedStringKey { get }
}
```

- **Three answers, not two.** `.unknown` covers a terminal TUI has not measured: it draws a
  plain underline there, as it does today, but an app should not claim the terminal "does not
  support" something nobody has checked.
- **Read-only, and the same answers TUI itself acts on.** Each subscript reads the table the
  renderer already uses, so the app's note can never disagree with what is drawn. An app that
  wants to *change* behaviour keeps the existing switches (`terminalHyperlinks(_:)`,
  `terminalGraphics(_:)`), which this does not replace.
- **Words included.** `explanation(for:)` returns TUI's own sentence, translated with its other
  strings, built from the measured facts: "Apple Terminal paints this as a coloured background, so
  TUI draws a plain underline". That keeps the wording, and its accuracy, in one place.
- **Not a detection API.** It says what TUI concluded, and how it named the terminal stays
  `TerminalClient.current`.

### How the Example would use it

A small Example-only view, so pages stay readable:

```swift
Text("Dotted").underline(pattern: .dot)
    .capabilityNote(.patternedUnderline)   // Example's own modifier
```

`capabilityNote` adds a quiet suffix such as "(not in Apple Terminal)" only when the answer is
`.unsupported`. Its help text (`.help`) carries the full explanation. The owner's alternative, a
💔 marker with a legend once per page, is a style choice of the same modifier. Under a terminal
that draws everything, nothing appears. The hard-coded notes on the Text Styles, Links and Image
pages move to it.

### Cost and invasiveness

- **Runtime:** the value is built once per frame from tables that are already computed
  (`TerminalClient.current` is cached), a struct of a dozen enums. It is `Equatable`, so memos
  below it stay valid, unlike the uncomparable environment writes that turned caching off before
  (memory: environment-existential-memo-blocker). Only views that read it pay.
- **Code:** one file in TUIFoundation for the type and the environment key, plus the
  localisation keys for the explanations (seven languages). No renderer changes.
- **Upkeep:** each new measured feature adds a case. The explanations sit next to the tables,
  so a re-measured host updates both. A test can check that every feature has an explanation for
  every program.

### Open questions for the owner

1. **Naming:** `terminalCapabilities` and `Feature` or something shorter; and whether colour
   depth belongs here (it can change at run time when a user forces it) or stays `ColorDepth`.
2. **Granularity:** is `patternedUnderline` (curly, dotted and dashed together) fine, or one case
   per shape? Every measured terminal so far treats them as a group.
3. **Scope:** expose only what TUI measures, or also keys an app might want (the kitty
   keyboard protocol's modifier-only reports, which item 25's underlines would use)?

**Recommendation:** build it as above, at about a day including the Example's notes and the
seven languages. It is additive, TUI-specific and read-only, and it reuses the tables TUI
already maintains.

