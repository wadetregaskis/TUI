# The menu bar behaves as macOS's, and says what it offers: decisions for review

*The MENUBAR lane's companion to
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>),
in its format, for the owner's items of 2026-10-23 on the menu bar (#1, #2,
#3–#8, #25–#27), following [`The menu bar (O13).md`](<The menu bar (O13).md>).
2026-10-24.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** See below, each with its fuller version and
  price.
- **C. Declined without asking.** None.

## B. Shipped the safe option

### B-MENUBAR-1. Find… and Find Next are validated; Cut, Copy and Paste are not

*`TextEditingCommands`, the scene's own `pasteboard` group*

**Shipped:** Edit ▸ Find… and Find Next are disabled unless the focus is in a
`TextEditor` that can find, through a package focused value the editor
publishes (`FocusedValues.textFinding`), as AppKit validates them against the
responder chain. The other standard items that act on the focused view were
already validated: Show/Hide Sidebar and Inspector (no panel), Undo and Redo
(nothing to undo), Close Window (may not close).

**The fuller version:** validate Cut, Copy and Paste the same way, enabled only
where something focused takes ⌘X, ⌘C, ⌘V — and, as on a Mac, Cut and Copy only
with a selection. What takes them is spread out: `TextField`, `SecureField` and
`TextEditor` (each with its own selection), `onCopyCommand` / `onCutCommand` /
`onPasteCommand`, `copyable` / `cuttable` / `pasteDestination`, a `List` or
`Table` selection with those, and the screen selection, which Copy reaches
from anywhere. Each would publish what it can do this frame (a small
`OptionSet` focused value), and the screen selection would be read beside it.
About a day with tests; the Edit menu then reads like a Mac's, where today
Cut, Copy and Paste on a page with nothing to take them press a key nothing
takes.

### B-MENUBAR-2. About says what the scene states, then the Info.plist, then the process

*`Scene.aboutPanel(applicationName:applicationVersion:version:copyright:credits:)`, TUIkit-only*

**Shipped:** a scene modifier, named after AppKit's About panel option keys
(SwiftUI has no spelling: a Mac app says more about itself through AppKit's
`orderFrontStandardAboutPanel(options:)`). Each value left `nil` comes from
the main bundle's Info.plist — `CFBundleDisplayName` then `CFBundleName`,
`CFBundleShortVersionString`, `CFBundleVersion`, `NSHumanReadableCopyright`,
the keys macOS's panel reads — and the name, failing both, from the process.
The alert shows the name, "Version 1.2 (42)" (the build only where it differs),
the credits and the copyright. The name titles the app's menu and its About
and Quit items too. A modifier rather than an environment value of the app's:
it is the scene's to say, once, and it reaches the chrome-drawn menu bar
through the scene's environment. The Example states its name, TUIkit's version
and its authors.

**The fuller version:** credits as `Text` (styled, with a link), an
application icon drawn from the app's image (Kitty graphics where the terminal
has them), and a Credits.rtf / Credits.html read from the bundle as macOS does.
Half a day for `Text` credits; the icon waits on a decision about what an
app's icon is in a terminal.
