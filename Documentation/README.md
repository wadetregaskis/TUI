# Documentation for TUI's developers

This folder is for people developing TUI: designs, investigations, measurements, reviews and the record of past
decisions. It is not built into the documentation site.

To use TUI in an app, read the [user documentation](https://swift-tui.com/docs/documentation/tui/) instead. It is built
from [`Sources/TUI/TUI.docc`](../Sources/TUI/TUI.docc), and a page written for someone using TUI belongs there, not here.

## What is here

Every top-level document and folder. The folders describe TUI as it is, or a design not yet built; the story of
how something came to be, and the decisions behind it, is in [Historical](<Historical/>).

### Documents

| Document | What it is |
|---|---|
| [Open owner decisions](<Open owner decisions.md>) | The questions waiting on the owner, each with a recommendation and a default. Open ones only: answers move to the decision records in Historical. |
| [API stability policy (draft)](<API stability policy (draft).md>) | What 1.0 would promise about the public API and what it would not, the deprecation and minimum-version options after 1.0, and the decisions it waits on. Not yet approved. |
| [Future options](<Future options.md>) | Ideas measured or designed and deliberately not taken, each with why not now and what would reopen it. |
| [Environment variables for developing TUI](<Environment variables for developing TUI.md>) | The variables read only by TUI's own tests, tools and demos; those for an app's users are in the DocC article. |
| [Compiled hot reload](<Compiled hot reload.md>) | The design for updating a running app from a saved source file, its state intact; wanted after the first release. |
| [Partial TUI](<Partial TUI.md>) | The design for an app drawn in a few rows at the foot of the terminal, scrollback above; after the first release. |
| [WebAssembly port](<WebAssembly port.md>) | What building for `wasm32-unknown-wasip1` and running the Example in a browser took, what works, and why. |

### Folders

| Folder | What it holds |
|---|---|
| [Colour and styling](<Colour and styling/>) | Styling and theming, opacity as composition, gradients, out-of-band styling, the colour-only cues audit. |
| [Controls and presentation](<Controls and presentation/>) | Notifications, tooltips and help, unifying the menu implementations. |
| [Images and terminal graphics](<Images and terminal graphics/>) | The terminal graphics protocols, image palette mapping, compressed image transfer. |
| [Input and focus](<Input and focus/>) | Focus indication, geometric arrow focus, the cursor following focus, keyboard drag and drop, keyboard screen selection, the input-reader loop, the find pasteboard. |
| [Layout and scrolling](<Layout and scrolling/>) | The layout constraint system, scroll anchoring, resizable views, locating things without drawing them, `List` and `Table` on `ScrollView`. |
| [Performance](<Performance/>) | Profiles and passes, what makes a page slow, output diffing and scroll regions, optimisations that did not pay, benchmark coverage. |
| [SwiftUI parity](<SwiftUI parity/>) | The SwiftUI compatibility guide, the deliberate deviations, the API completion plan, and design studies. |
| [Swift language](<Swift language/>) | Language and toolchain notes and studies: static tables, closures, raising the macOS floor and the Swift minimum. |
| [Terminals](<Terminals/>) | The terminal compatibility survey (the canonical record of measured terminal behaviour) and the Ghostty adoption study. |
| [Investigations](<Investigations/>) | One-page summaries of questions that took measuring or probing to answer. |
| [Reviews](<Reviews/>) | The full logs of the review batches (their stories are in Historical), the SwiftLint rule review, and the upstream review ledger. |
| [Historical](<Historical/>) | How TUI came to be the way it is, by topic: the problems, what was measured, what was decided and by whom. |

The maintainers' working notes are not part of the repository; a document that cites one names its path there.
