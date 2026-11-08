# The settings panel on F2

*How a person changes how any TUI app is drawn — its palette, borders, control
style and accessibility preferences — without a menu bar, and how an app's own
`Settings` scene joins in. Decided by the owner on 2026-11-08; built the same
day.*

## In short

F2 opens a small tabbed panel in every app, menu bar or not. An app's
`Settings` scene supplies its first tabs; TUI's **View** (palette, border
style, control style) and **Accessibility** (the View menu's seven checks)
follow, after a divider. ⌃, (SwiftUI's ⌘, through the command key) opens the
same panel where the terminal can send it. Both keys come after the app's
own: an app that binds either keeps it. TUI's choices last for the run and are
never saved; the app's own settings persist however the app chooses.

## How it unfolded

1. **2026-11-08, the owner, on the menu bar:** "we should never force apps to
   have a menu bar; that's not a universal convention in terminal UIs. Having
   other ways to adjust view settings, like themes, palettes, accessibility
   settings, would be good. The main issue may just be figuring out what
   shortcut key… fairly distinctive and easy to remember, so that it can become
   canonical, but also not take a shortcut that apps themselves are likely to
   want to use."
2. **The key, the same day:** "maybe F2, then? If we're going to take multiple
   F-keys it'd make some sense to have them together (and start from the
   beginning)", and "supporting control-, as the terminal analogue of the Mac
   convention would be good, too". "The command list from hitting F1 should of
   course include that shortcut."
3. **Persistence:** TUI's own choices are not saved, as the View menu's
   aren't ("for now let's not persist them").
4. **The design, approved the same day:** the app's `Settings` scene supplies
   the panel's first tabs; TUI's two follow after a divider; settings are
   app-wide, never contributed from deep in the view tree ("This is global app
   settings… and shouldn't be sensitive like that to where the app is in its
   navigation"); and the app author may hide or replace either of TUI's tabs
   ("They may have good reason to do so; we shouldn't nanny them. We just make
   it easy to do the default right thing").

## The record

### Why F2

F1 is already TUI's (the list of shortcuts, 2026-11-01), so F2 keeps TUI's
keys together at the start of the row, as the owner asked. It arrives the way
F1 does: `ESC O Q` in every legacy encoding, `CSI Q` or `CSI 1 Q` under the
kitty keyboard protocol. Whether a host binds it was not read or pressed
(the terminal survey's key section). On a Mac keyboard it is fn-F2 unless the function keys are set to be
standard keys; macOS's own Control-F2 (move the focus to the menu bar)
belongs to the terminal, not the app, and is not used.

### Why ⌃, too, and where it arrives

⌘, is the Mac's Settings key; TUI's command key stands Control in for ⌘ by
default, so the `Settings` scene's key is ⌃,. Legacy encodings have no byte
for Control with a comma: only the kitty keyboard protocol's disambiguate mode
sends it (`CSI 44;5u`). So F2 is the key that works everywhere, and ⌃, is
listed among the keys in force only where the terminal took that mode. The
scene's `.keyboardShortcut` moves it, as in SwiftUI.

### Why the last layer, and the app-claim rule

Both keys are defaults, never claims: F2 is answered in the input chain's
last layer, as F1 is, so an app's `onKeyPress`, `onKeyEvent`, status-bar item
or `.keyboardShortcut` on F2 takes it first; ⌃, is registered as the scene's
command key, which the window's own shortcuts on the same chord come before.
An app that takes F2 keeps it, and the panel is still reached by ⌃,, the menu
bar's Settings…, a `SettingsLink` or `openSettings`; the list of shortcuts then
names the app's F2, not TUI's. An app that wants the panel on another key
moves it with `.settingsPanelKey(_:)`, or takes the key away with `nil`, as
`tooltipState.helpKey` moves the help key.

### Why the app's tabs come first

The person opening Settings in an app is most often after the app's own
settings; TUI's are the same in every app and come last, after a divider that
says where the app's end. A `TabView` of `Tab`s becomes one tab each; any other
content becomes a single tab named after the app.

### Why TUIApp links Picker and Form

The panel is in every app, so it is built in TUIApp, the module every app
links; its View tab is made of `Picker`s, as `DisplayCommands`' submenus are
(one model, `DisplayChoices`, so menu and panel agree), and laid out in a
`Form`, so an app's own settings and TUI's look alike. That puts TUIPickers
and TUIForms in every app; TUITabs, with the lists under it, stays out (the
tab strip is a segmented `Picker`).
