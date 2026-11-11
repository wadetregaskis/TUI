# Changelog

Every change a user would notice, newest first. Work not yet in a release sits under `## Unreleased`; cutting a
release (`Tools/Release/release.sh`, see [RELEASING.md](RELEASING.md)) renames that section `## X.Y.Z — YYYY-MM-DD`
and opens a new, empty `## Unreleased` above it, and the section's text becomes the release's notes word for word.

Entries are short paragraphs written for someone upgrading, each led by a bold sentence saying what changed, rather
than [Keep a Changelog](https://keepachangelog.com/)'s Added/Changed/Removed lists; a change that needs action from
an app says so, and the larger ones are gathered under `###` headings.

TUI itself has not been released yet and is pre-1.0: public API can change in any commit, and the project deletes
deprecated or superseded spellings outright instead of keeping compatibility shims. Versions follow
[Semantic Versioning](https://semver.org/) from 1.0. The `v0.2.0` to `v0.6.0` tags in the repository are releases of
[TUIkit](https://github.com/phranck/TUIkit), the project TUI grew from, and their notes are TUIkit's.

## Unreleased

**A playing picture converts its frames ahead, off the main actor, and no longer stutters when a setting changes.**
An animated `Image` drawn as glyphs converted each frame the first time it showed, in the render that showed it, so a
costly setting (`imageShapeAware`, a dither) made every frame of the first loop late, and again after each change.
Its frames are now converted in a background task, in the order they will show: after a change the old frames go on
playing until every new one is ready, and the first time round each is kept as soon as it is converted. A
shape-aware frame of the Example's bouncing ball costs 5 to 8 ms in a release build and 200 to 300 ms in a debug one.

**An idle app with a menu bar no longer holds a core on Ghostty, kitty or WezTerm.** Where the terminal reports a
modifier key held on its own, the menu bar's underlined letters (and any `modifierKeyAlternate`) kept the animation
clock ticking, and every tick drew the whole screen again instead of replaying the breathing focus: about 95% of a
core in the Example's debug build on Ghostty, against nearly none on Apple Terminal. Such a view now asks for a frame
only when the keys it shows change.

**TUI's settings are kept: for the program, and, if you like, for every TUI program.** A palette, border style,
control style or check chosen in the settings panel (F2) or the View menu wins for the rest of the run, as before,
and is now saved for the program's next runs, where a `TUI_*` variable set for that launch and the program's own
code win over it. Each of the panel's View and Accessibility settings has a box saying whether the program keeps it;
untick it to give the setting back. **Settings for All Programs…** turns the two tabs to your settings for every TUI
program, kept in one hand-editable file, `defaults.json` in TUI's configuration folder
(`~/Library/Application Support/TUI` on macOS, `~/.config/tui` elsewhere, `%APPDATA%\TUI` on Windows, moved by
`TUI_CONFIG_DIR`), which fills in what a program leaves unset, above the computer's own setting. A program's saved
settings are in its `@AppStorage` store under `TUISettings.` keys. An app's configuration folder on Windows is now
under `%APPDATA%`, as TUI's is.

**TUI says when macOS hides the notifications it posts itself.** On macOS, a notification TUI posts with `osascript`,
for a terminal that can't post one, is Script Editor's, and macOS keeps it unshown while System Settings ▸
Notifications ▸ Script Editor has notifications off. TUI now reads that setting and, where it's off, says so once
among its diagnostics. Ghostty and iTerm2, which post the notification themselves, show it only while their window
isn't in front, so `desktop: .always` reaches the desktop there only while another app is in front.

**A toast's emoji wait for its fade-in to finish.** An emoji is drawn in colours of its own, which no fade reaches, so
a toast's glyph appeared at full strength at once and its text and border faded in round it. Now every emoji in a
toast, its style's glyph and any in its message or views, is drawn only while the toast is fully opaque, and goes as
soon as it starts to fade out. Its cells stay blank meanwhile, so nothing moves.

**A toast's buttons sit at its trailing edge.** Its message still reads from the leading one.

**Under `TUI_PLAIN_TEXT`, controls show their state in ASCII.** Where the terminal is sent plain text, toggles draw
`[x]` and `[ ]`, radio buttons `(*)` and `( )`, spinners their own ASCII frames, a file panel `d`, `f` and `l` beside
each name, and a field's or a button's ends `[ ]`; before, `■` and `□` were both `#`, empty radio buttons and half the
spinners were blank, and a toggle in a menu read `:white_large_square:`. Under `TUI_PLAIN_TEXT=transliterate`, an SF
Symbol is spelled by its name, `:star:`, where it vanished, and `❤` typed without its selector is `<3`. Both remain for
testing; nothing changes without the variable.

**A dialog no longer jumps when a tooltip appears in the status bar.** A sheet, alert or other dialog centred over
the page stays where it is as help shows and goes in the status bar, and moves up only where the tooltip's rows
would cover it.
**The settings panel and the View menu offer the same settings, and the panel has a border.** The panel (F2)
is drawn as a titled dialog. Its View tab now holds Breathing Focus, Spell Out Keys, Focus Follows Pointer and the
new Arrows Follow Layout after the palette, border style and control style, and its Accessibility tab the four
accessibility checks; every menu bar's View menu offers all of them in the same order, Palette, Border Style and
Control Style included, so an app with a menu bar and no panel, or a panel and no menu bar, loses nothing.
`DisplayCommands` moves the three submenus to the top of the View menu in place of TUI's own. An app that states its
palette, border or control style at the scene and hands its state to `DisplayCommands` has the panel choose into
that state too; one that hands none has the panel say why the choice is disabled, under it.
**Arrows Follow Layout turns the geometric arrow keys on and off while the app runs.** It is
`TUI_ARROW_FOCUS=geometric`, an experiment, as a check in the settings panel and the View menu; the choice wins over
the variable until the app quits. It is off unless you turn it on.

**↑ on a menu bar menu's first item goes back to its title.** The menu stays open with nothing highlighted, and ←
and → then walk the menus without entering them, so an item with a submenu no longer catches →; ↓ enters the menu
again. From an item, ← and → step to the next menu as before. A pop-up `Menu`, a context menu and a submenu still stop
at their first item.

**A menu the keyboard opens shows its first enabled item highlighted at once.** A menu whose first item was disabled
— the Edit menu's Undo with nothing to undo — opened from F10 or by an arrow with no item highlighted, though Return
already chose the first enabled one, and a Down from there skipped it. The first enabled item is now lit on the frame
that opens the menu, past disabled items and dividers, as on a Mac: in the menu bar, a pop-up `Menu`, a context menu,
a toolbar pull-down and a submenu entered with →.

**`handOffTerminal(running:arguments:)` starts a program for a hand-off, and says how it ended.** It starts the
program as an interactive one must be — in the app's process group, every signal at its default, with `posix_spawn`
rather than Foundation's `Process`, whose group of its own stops an editor as it reads the keyboard — and returns
`.exit(status)` or `.uncaughtSignal(signal)`, throwing only when the program cannot be started. A program is
`.path(_:)` or `.name(_:)`, looked up in `PATH`; `$EDITOR`, which may carry arguments, runs through `/bin/sh -c` as
git runs it. A program that stops itself alone stops the app too, so the shell gets the job back. On WebAssembly it
throws `.unsupported`.

**An app whose input is already at its end no longer risks spinning on Linux.** Run with `< /dev/null` or a
finished pipe, an app watched its input for bytes that would never come, and on Linux the end could reach it as an
endless run of "bytes ready", holding a core. It now asks the input itself whether it has ended, at the start and at
every wake.

**An app can hand the terminal to another program — `$EDITOR`, a pager, `git commit` — and take it back.**
`@Environment(\.handOffTerminal)` gives a `HandOffTerminalAction`: `handOffTerminal { … }` runs its closure at once,
with the terminal as it was before the app started (main screen, the shell's settings, no mouse or other modes), and
takes it back after, as after ⌃Z: every mode set again, the size read again, every line drawn again. It returns what
the closure returns and throws what it throws. While it runs, ⌃C and ⌃\ end the other program and not the app, ⌃Z
stops the two together, and the scene is `.background`. Start an interactive program with `posix_spawn` in the app's
process group, not with Foundation's `Process`, which starts it in a group of its own where an editor is stopped as it
reads the keyboard; the action's documentation says how. Outside a running app the closure just runs. The Example's
Terminal page edits a note in your `$VISUAL` or `$EDITOR`.

**A redacted `TextEditor` hides its text too.** Like a redacted field, a redacted editor drew its text, copied and
cut it, kept its kills, moved by words, selected a word on a double-click, wrapped its rows at its word breaks and
lit up find matches where its words were. It now draws a glyph for each character with its line breaks kept, wraps
where the glyphs wrap, refuses copy and cut, keeps no kill, moves and deletes one character for a word, selects the
line on a double-click, and offers no find bar.

**A redacted `TextField` hides what was typed, as a `SecureField` does.** Under `.redacted(reason:)`, or marked
`.privacySensitive()` under `.redacted(reason: .privacy)`, a text field drew its text as it was, and copy, cut, Ctrl-K
and Ctrl-Y, Option-arrows and a double-click all worked on it as on any field. It now draws a glyph for each character
(spaces and wide characters included), its prompt is redacted too, and it behaves as a `SecureField`: nothing can be
copied or cut out of it, a kill is not kept, and word motions and a double-click show no word breaks. SwiftUI's
redacted field does none of this (deviation T12).

**`sensoryFeedback` rings the bell for `.error` and `.warning`.** SwiftUI's `sensoryFeedback(_:trigger:)`, its
`condition:` form and the forms whose closure answers a `SensoryFeedback?` used to fail to compile. They now ring the
terminal's bell when the trigger changes, for the two kinds that say something went wrong; every other kind
(`.success`, `.selection`, `.impact`, …) still fails to compile, with a message naming `.error`, `.warning` and
`\.ringBell`, because a terminal can't make it felt and a bell would say the opposite.

**`\.ringBell` rings the terminal's bell, to say input was refused.** TUI's own controls ring it when they turn
input away; a control of your own, an `onKeyPress` that takes a key it can do nothing with, now does the same with
`@Environment(\.ringBell) var ringBell` and `ringBell()`, instead of `requestAttention("")`. It rings with the next
frame, once however often it was rung, and is never a desktop notification: `requestAttention(_:)` stays the way to
say that something finished.

**`ProposedSize` is gone; write `ProposedViewSize`, SwiftUI's name, instead.** The one type had both names,
`ProposedViewSize` being an alias, so a 1.0 would have promised two spellings of it. Replace `ProposedSize` with
`ProposedViewSize` wherever it appears, as in `sizeThatFits(proposal: ProposedViewSize, subviews:cache:)`; nothing
else about it changes.

**The per-control text-style modifiers are gone; write `.style(.control(.button)) { … }` and its kind instead.**
`buttonTextStyle`, `toggleTextStyle`, `sliderTextStyle`, `stepperTextStyle`, `pickerTextStyle`,
`radioButtonTextStyle`, `secureFieldTextStyle` and `textFieldTextStyle` each forwarded to `.style(.control(.x))`, and
lists, tables and colour pickers had none. Replace `.toggleTextStyle { $0.italic = true }` with
`.style(.control(.toggle)) { $0.italic = true }`, and so on for each kind. One look of button takes the typed scope
`.style(.buttonVariant(.automatic)) { … }` where `.buttonTextStyle(.automatic) { … }` was. `StyleScope.controlVariant`,
which carried a button's look as a string, and `EnvironmentValues.controlVariant`, which nothing set, are removed too.

**A focused or disabled control shows it on a 16-colour terminal in every palette.** Rounded to a terminal's sixteen
colours, some palettes' states land on the colour the control rests in: in Silver Aerogel, whose accent becomes its
page, a focused slider, stepper, tab view, menu, `.button` toggle and bordered or prominent button drew as at rest;
Solid Colors' caret was the colour of its field; and in six palettes a disabled button drew as an enabled one. Where
a state's colour draws as the resting colour at the terminal's depth, the control now says it as it does on a
terminal with no colour: the focus in reverse video, disabled faint.

**Views draw their words without the escape sequences written into them.** `Text("x\u{1B}[31my")` drew in red, and
text from outside the app (a file name, a log line, network data) could change colours, set the window title or write
the clipboard. Every view now removes escape sequences and control characters other than tabs and line breaks from the
words it draws: a `Text`, labels and titles, table and list cells, tab titles and badges. An app that writes its own
colour codes into strings keeps them with `.textKeepsEscapeSequences()` on the views that show them.

**`TUI_NOTIFICATIONS=0` turns notifications off altogether.** It used to stop only those sent through the terminal,
and at your own computer the app still posted them itself (with `osascript` or `notify-send`) unless
`TUI_SYSTEM_NOTIFICATIONS=0` was set too. Now `0` means none at all; `TUI_SYSTEM_NOTIFICATIONS` still chooses the route
while notifications are on.

**A `Grid` narrower than its columns squeezes them instead of dropping them.** Columns were never squeezed, so a
grid offered less than its full width was drawn at that width and cut: at 5 cells only its first column showed. It
now shares the width among its columns as an `HStack` shares a row, as SwiftUI's grid does (measured): text in a
squeezed column wraps, or truncates under `lineLimit(1)`, a column made rigid with `fixedSize()` keeps its width, and
a column whose cells fill takes what the others leave, wider than the columns too. `GridLayout` does the same.

**A value an app appends to a bound path replaces the screen a view destination put on top, as in SwiftUI.** With
a `navigationDestination(isPresented:)` screen up, or a view-destination `NavigationLink`'s, a value the app appended
to the path went on top and Back returned to the screen. It now takes the screen's place, and the screen's flag is
set back to `false`. A value the screen pushes with `NavigationLink(value:)` still goes over it.

**A `NavigationPath` holds only the app's values.** A screen pushed by `navigationDestination(isPresented:)` or
`(item:)`, or by a `NavigationLink` with a view for its destination, went into a bound `NavigationPath`: its `count`
included the screen, and its `codable` became `nil`, so the path could not be saved while the screen was up. The
stack now keeps such a screen beside the path, as it already did for a typed path and as SwiftUI does; taking the
value it was pushed over off the path takes it off too, and pushing that value again no longer brings the screen
back with it, on either kind of path.

**`.dialogBorder(_:style:titleColor:)` styles every alert and confirmation dialog; `alert` no longer takes
`borderStyle:borderColor:titleColor:`.** Four of the fourteen `alert` forms took those three parameters after their
closures, and the other ten, the `confirmationDialog`s among them, could not be styled at all. Apply
`.dialogBorder(.palette.accent, style: .doubleLine, titleColor: …)` outside the `alert` or `confirmationDialog`
instead, as `dialogSeverity(_:)` is: it reaches every form presented within the view, and every `AlertPanel` drawn
there. `AlertPanel`, `Dialog`, `Card` and `Panel` keep their own parameters, which win.

**`FlowLayout` wraps its subviews onto lines, as text wraps words.** A row of chips, tags or key hints that needs more
width than the terminal has starts a new line where the next one would not fit: `FlowLayout(spacing: 1) { … }`, each
line as tall as its tallest member, used directly or through `AnyLayout`. SwiftUI has no such layout; this one is
TUI's own.

**A toggle's label wraps when it is wider than its space.** It was drawn on one line beside the box and cut off where
the toggle ended, its last words gone with no ellipsis: the Example's File Panels page lost "machine" from its ssh
toggle at 80 columns. It now wraps as a `Text` does, its first line beside the box and the rest under it, as SwiftUI's
checkbox label does.

**Tab comes back round a page in a window with bars.** A window's bars are focus sections of their own, so Tab past a
page's last control asked them for the focus, and where they had nothing to focus it stayed on that control: no number
of Tabs went back to the page's first, nor Shift-Tabs from its first to its last. The Example's Empty State page, with
one button in a page that scrolls, kept the focus on the page after one Tab. Tab now goes round the page's own controls
when no other section can take the focus.

**A menu that scrolls keeps its widest row on one line.** The scrollbar's column came out of the rows, which the menu
had sized to its widest label exactly, so that label wrapped onto a second line in every inline menu taller than its
space: the Example's main menu in Japanese showed "オーバーレイとモーダ" over "ル". The
menu now grows by the bar's column where there is room beside it, and takes it from the rows only where there is none.

**F2 opens the settings panel in the Example, as its Settings… item says.** The Example cycled its palette on F2, an
app binding that comes before TUI's settings key, so the panel never opened on its key on any page. The palette now
cycles on ⇧F2.

**`ProposedViewSize.replacingUnspecifiedDimensions(by:)`, as in SwiftUI.** A `Layout` that takes what it is offered
answers `proposal.replacingUnspecifiedDimensions()`: the proposal, with 10 cells, or the size given, for a dimension
left unspecified. A layout ported from SwiftUI that used it did not compile.

**A diagnostic written to stderr while an image is being drawn no longer ends the app on macOS.** Drawing a picture
points stderr at `/dev/null` for a moment, to hide a line Core Graphics prints, and a report written by another
thread in that moment failed with "Bad file descriptor", which ended the process. The two now take turns.

**A file panel in a narrow terminal puts its view switcher and Preview button on a row of their own.** At about 40
columns the List/Columns switcher was cut off and "Show Preview" wrapped onto two rows, squeezed by the path beside
them. Where the path's row cannot keep some of the path beside them, they now go below it, and below each other
narrower still.

**An empty `List`'s or `Table`'s placeholder wraps where it is too long for one row.** It was cut off at the edge, so
a file panel's "The folder … can't be opened." lost the reason after it. It now wraps onto the rows below, as many as
the list has, the last ending in an ellipsis if even those are too few.


**`.zIndex` orders the children of a `VStack`, an `HStack`, a `Grid` and a `Layout`, not only a `ZStack`'s.** A
view raised with `.zIndex(1)` was drawn under a later sibling an `.offset` or a negative padding moved onto it, and the
click there went to the sibling. It now stays on top and takes the clicks where it is drawn, as in SwiftUI.

**A `LazyVStack` and a `LazyHStack` order the rows they draw by `.zIndex` too.** A raised row went under the next row
an `.offset` moved onto it, and the click there went to that row, inside a `ScrollView` or not. It now stays on top,
as in the other stacks and in SwiftUI.

**A `keyframeAnimator` that has played out on its trigger lets a `TestApp` rest.** It stopped asking for frames from a
task a test's clock never ran, so `advance(by:)` went on drawing sixty frames a second of the end value, about six
hundred more for every ten seconds a test moved on. It now stops in the frame that draws the end, in a running app as
in a test.

**A `Text` of several lines gives up lines in a column too short for everything, as SwiftUI's does.** It kept every
line however little room there was, so a sibling with a higher `layoutPriority` got nothing beside it. Offered fewer
rows, a text now takes them, down to one (or the lines `lineLimit(2...)` or `reservesSpace:` keep), its last line
truncated, and `.fixedSize(horizontal: false, vertical: true)` still keeps them all.

**A file panel no longer opens on a folder that has gone.** Presented again, a panel opens on the folder of the last
choice made in it; once that folder had been deleted or moved, it opened there all the same, saying the folder
can't be opened. It now opens where it first did, as a panel with a `fileDialogCustomizationID` already did.

**A save panel asks before saving under the name of a link that leads nowhere.** Such a name looked free, so the
panel chose it without asking to replace it, and New Folder and saving several files offered it too; it is now taken,
as a file's name is.

**A file panel says why a folder it cannot read shows nothing, in the column view too.** A folder that could not be
read (no permission, or gone since it was listed) had a column saying "This folder is empty.", and once a column or
the list's outline had looked into it, opening it said the same, rather than that it can't be opened, and why.

**A disabled control looks disabled under the `Terminal` palette before the terminal reports its colours.** Its grey
can't be mixed until then, and on a host that never reports them, such as GNU screen, it came out as the plain
foreground, so a disabled button or text field looked enabled. It is drawn faint there, as on a terminal with no
colour.

**A disabled `TabView` looks disabled.** At any colour depth it drew exactly as an enabled one without the focus: its
strip greys only a tab disabled on its own. It is drawn faint at every depth now, as a disabled `List` or `Table` is.

**A disabled `List` or `Table` looks disabled.** At any colour depth it drew exactly as an enabled one without the
focus; only a terminal with no colour, or Differentiate Without Color, showed it faint. It is drawn faint at every
depth now.

**A focus held still shows on a checked checkbox, a switch that is on, a link and a radio group.** With
`TUI_BREATHING=0`, the View menu's Breathing Focus turned off or `.focusBreathing(false)`, the focus sits at the
bright end of its breath, which is the colour those controls rest in, so nothing showed which one had it. Their label
is now drawn in reverse video while they have the focus, as it is under Differentiate Without Color, and likewise under
the `Terminal` palette before the terminal reports its colours, where the breath can't move. A link inside a
`Text` does the same, and now also shows its focus on a terminal with no colour, where it showed none.

**A list or table whose last rows go from under its focused row moves the focus to the new last row.** It was left
past the end, where no row showed it and Space, Return and Delete did nothing until an arrow key brought it back.

**Return selects a leaf of a hierarchical `List`.** It opens and closes a branch, and on a leaf did nothing; it now
selects the leaf, as Space does and as Return does in a flat list. A `primaryAction` the app gives still takes Return.

**A list's or table's focused row stays focused when the rows change.** A row inserted or removed above it, or a
sort, left the focus where it was, on whichever row took that place, so Space, Return or Delete acted on a row you
never moved to: always at the top of a list, and anywhere for a change between the top row on screen and the focused
row. The focus now follows its row. When the focused row itself goes, the row after it takes the focus, as before.

**⌃\\ asks to quit in a `TestApp`, as in a running app.** The user's quit key did nothing in a test, so a test of an
app's quit confirmation could not press it. It asks first, and a second ⌃\\ quits, which `hasRequestedQuit` reports.

**F2 under the list of shortcuts leaves the settings panel up.** With F1's list over the panel, F2 closed the panel
out of sight, and taking the list down then showed the page. F2 does nothing while the list is up, as it does over the
page.

**A menu's item that removes the view its menu hangs from leaves the focus beside it.** Choosing Delete from a row's
`.contextMenu`, or an item of a pop-up `Menu` that hides the `Menu` itself, sent the focus to the first control on the
screen. It now goes to the next control, or the one before where there's none after, as when a focused control removes
itself.

**A shortcut works in the menu bar's F10 mode, and ⌃Q quits there.** With the titles lit by F10 and every menu closed,
any key left the mode and was spent on leaving it, so a command's shortcut, a page's, and the quit key did nothing.
A Control chord now leaves the mode and then goes on, as it goes past an open menu. A bare key is still spent on
leaving.

**`KeyboardShortcut.isDeliverableInTerminal` answers `false` for the chords a terminal sends as another key.** It said
`true` for Control with Shift (⌘⇧S under `.commandKey(.control)`, which arrives as ⌃S and fires ⌃S's binding), with a
digit or most punctuation (⌘1, which a legacy encoding sends as a plain 1, and ⌃, which it cannot send at all), for
Control or Shift on Return, Tab, Escape, Backspace and space, and for Shift on a character that isn't a letter. Each of
those now answers `false`, as Ctrl-H and Ctrl-4 already did. Shift-Tab, Option chords and the arrow, paging and
function keys still answer `true`.

**`Settings { SettingsView() }` shows its tab view's tabs as the settings panel's own.** Where the tab view was in the
body of a view of the app's own, SwiftUI's documented way to write settings, the panel showed one tab named after the
app with a second tab strip inside it; only a `TabView` written directly in the scene gave its tabs to the panel. The
panel now looks through such views, and through modifiers on the tab view, which apply to each tab's content, and the
view's `@State` is kept while the panel is up.

**Settings… shows F2 where the terminal can't send the Settings key.** Without the kitty keyboard protocol, the menu
bar's Settings… and F1's list of shortcuts named the `Settings` scene's key even where it couldn't arrive, such as ⌘H
under the default command key, which a terminal sends as Backspace. Both now name the key only where it can arrive, by
`KeyboardShortcut.isDeliverableInTerminal`, and show F2, the settings panel's own key, instead.

**A menu bar wider than the terminal scrolls to the title you're on.** F10 and ← → walked to titles past the right
edge, and Alt and a letter opened their menus, but the titles couldn't be seen and the menu hung from nowhere. The row
now scrolls to keep the highlighted or open title in view, with « and » where titles are hidden; a click on either
opens the hidden menu beside it. A title wider than the whole row is drawn from its start, as much as fits.

**An animation repeated an even number of times with `autoreverses` ends at the value the change set.** After
`.repeatCount(2, autoreverses: true)` played out and back, the view stayed where the last pass left it, at the value
before the change, for good, and a view inserted under one was never seen at all. It now snaps to the new value once the
passes have played, as SwiftUI's does.

**`.zIndex` orders the children of a `VStack`, an `HStack`, a `Grid` and a `Layout`, not only a `ZStack`'s.** A
view raised with `.zIndex(1)` was drawn under a later sibling an `.offset` or a negative padding moved onto it, and the
click there went to the sibling. It now stays on top and takes the clicks where it is drawn, as in SwiftUI. The lazy
stacks still draw their rows in order.

**`.truncationMode(.middle)` fills its width with wide text.** A cut that could not split a CJK character or an
emoji at the start's half left that cell blank, so `日本語テキスト` in seven cells drew `日…ト`; the spare cell now goes
to the end, `日…スト`.

**A `Label` whose title wraps keeps its icon beside the title's first line.** The default style centred the icon on
the whole title, so a title of three lines had its icon beside the second. It now lines the icon's middle up with
the middle of the title's first line, as SwiftUI does, which also keeps a one-line title at a tall icon's middle.

**A word longer than its line breaks across lines, as SwiftUI's `Text` does.** A long URL, path or identifier in a
narrow `Text`, multi-line `Table` cell or tooltip was put on a line of its own and cut there with an ellipsis, losing
the rest of the word even with rows to spare; it now breaks between characters (never inside a character with
combining marks) and is truncated only when it runs out of lines, as with `.lineLimit(1)`. A `.sizeDependent` text
still prefers a narrower spelling to breaking a word.

**The environment variables an app's man page lists are written for the person running it.** Each says, in plain
words, what it does to the screen, the keys or the mouse, its values, its default, and an example where one helps, and
they're grouped as that person looks for them: colour and appearance, motion, keyboard and mouse, text and language,
screen size and printed output, links and notifications, terminal quirks, saved settings and troubleshooting. The
end-user section from `swift run tui-environment-docs`, `TUIEnvironmentVariables.manPageSection` and `markdownSection`
now ends with what the person's terminal, tmux or ssh sets, such as `TERM_PROGRAM`, `TMUX` and `SSH_CONNECTION`.
`TUI_SCROLL_OUTPUT=0`, the way out for a terminal that gets scroll regions wrong, is documented for them too.
`TUIEnvironmentVariable.Topic`'s cases are the new groups, so code that switched over the old ones (`colour`,
`accessibility`, `behaviour`) needs the new names; regenerate a committed man page to pick up the text.

**Shift+Tab walks up through a `LazyVStack` in a `ScrollView`, scrolling each row in.** From the row it had just
scrolled in at the top, it went on to the control before the scroll view (or, with none, to the scroll view and then
the bottom of the window), so the rows above could be reached only by scrolling first. Tab downwards was unaffected.

**The scroll bar's arrow under the pointer lights as the bar arrives.** A bar drawn over the content appears on the
frame after the pointer comes over the view, and an arrow it put under a pointer that had not moved stayed unlit until
the pointer moved again. A frame that slides a control under a resting pointer, or off it, is now followed by the frame
that draws what that changed.

**A scroll view with `.scrollIndicatorPlacement(_:)` or `.scrollIndicators(_:)` written on it keeps its rows whole
in a `TabView`.** Under a header in a column, a row short of fitting, its bar took a column out of its rows ("row 10"
wrapped onto two lines), where the same placement set higher up did not: a modifier that only sets an environment
value hid from the column that the scroll view takes all the room it is offered.

**`Dialog.doubleLine(title:…)` and `Dialog.heavy(title:…)` are gone.** They were `Dialog(title:borderStyle:)` with
two of its seven border styles filled in; write `Dialog(title: "…", borderStyle: .doubleLine) { … }` instead.

**A custom `Layout` places a subview at a `CellPoint`, as SwiftUI's places one at a `CGPoint`.**
`LayoutSubview.place(at:anchor:proposal:)` no longer takes an `(x:y:)` tuple beside the `CellPoint`; write
`subview.place(at: CellPoint(x: x, y: y), proposal: …)`, or pass a `CellRect`'s `origin` as it is.

**A `Tab` takes swipe actions.** `swipeActions(edge:allowsFullSwipe:content:)` on a tab, as SwiftUI spells it, gives
its row in a `.sidebarAdaptable` sidebar the buttons a list row's swipe actions give it, revealed from the keyboard
(⇧→ and ⇧←) or a trackpad's sideways swipe in the same way. A tab bar has no rows to swipe and shows none.

**On WebAssembly, a symbolic link to a folder opens as a folder in the file panels.** It listed as a file there, as
Foundation on WASI does not resolve a link's path; the listing asks the file system, which follows it.

**On WebAssembly, a document saves, and a chosen language and a diagnostics file are written.** WASI has no atomic
write, and a `FileDocument` or `ReferenceFileDocument` save, the language `LocalizationService` keeps and the first
report to `TUI_DIAGNOSTICS_FILE` each asked for one, and wrote nothing. They write in place there now, as
`@AppStorage` and `fileExporter` already did; other platforms still write atomically.

**On WebAssembly, a view tree too deep for the stack is cut short instead of corrupting memory.** The stack guard,
which stops the descent with a notice where the stack runs low, had no bounds to measure there and was off, and wasm's
stack has no guard page: a tree deeper than it wrote over the program's data. It reads the linker's bounds now. On
wasm-ld's default 64 KB stack it trips a few levels down, so link with a bigger one (`-z stack-size=16777216`, as
`Tools/Web/build.sh` does).

**A customized toolbar's saved record reads without its list of shown items.** A writer that leaves out an empty
`shown` field no longer makes the whole record fail to decode, which used to lose the person's order of the items too.

**A settings file that a later TUI wrote is read, and is no longer wiped by the next save.** `settings.json` and
Linux's `UserDefaults.json` hold each key's value as base64 JSON. If any value in the file was something else, such as
one a later release might keep another way, the whole file read as empty, so every setting showed its default. The
next save then rewrote the file with only the keys this app had changed. Now each key that reads is read, and a save
leaves every other key as it was.

**On macOS, settings an earlier TUI saved in `UserDefaults` are read again.** Until 2026-10-14 TUI kept every
`@AppStorage` value there as its JSON encoding: by default from 2026-06-29, and in 0.6.0 and earlier for an app that
named `UserDefaultsStorage`. Since then a `Bool`, a number, a string or a raw value has been kept as itself, as SwiftUI
keeps it, and such a value saved earlier read as absent, so it showed its default. It is now read from its JSON. It
stays as it is until the next write, which keeps the value as itself.

**Typing in a `TextField(value:format:)` after Return goes on after the value.** Return, or leaving the field, writes
what was typed back formatted, "1234" as "1,234", and the caret stayed where it had been in the shorter text, so the
next digit went into the middle of the number. The caret now goes to the end of the text a commit rewrites.

**Return in a `TextField(value:format:)` with no `onSubmit` reaches the default button.** Its own commit of what
was typed counted as a submit action, so the field always kept Return, and in a dialog the button marked
`.keyboardShortcut(.defaultAction)` never heard it. Return now writes the value back and goes on to the button, as it
does from any field with no `onSubmit`, and the button reads the value just typed.

**Text fields and editors keep the accents, joiners and variation selectors typed after a character.** A terminal
sends what a keyboard, an input method or the emoji picker types a Unicode scalar at a time, and `TextField`,
`SecureField` and `TextEditor` dropped every scalar that was a mark or a format character on its own: 👨‍👩‍👧 went in
as 👨👩👧, ❤️ lost its emoji form, a Thai tone mark or a Persian zero-width non-joiner went missing, and an accent
typed decomposed vanished. They now type anything but a control character, as a paste always has.

**A tab keeps its state while another tab is shown.** Switching to another tab and back started the first tab's
content over: a counter's `@State` was back at zero, and a `NavigationStack` in it had lost the screen it had pushed.
A hidden tab's state is now kept, as SwiftUI's tab view keeps it and as `TabView`'s documentation said.

**The keyboard reaches a split view, a navigation stack or a `.focusSection` inside a sheet, an alert or a
popover.** Each makes focus sections of its own, and inside a presentation those were treated as the page's: Tab
never reached a `NavigationSplitView`'s columns or a `.focusSection`'s controls in a sheet, a screen pushed in a sheet
left the focus on the sheet's resize stop, Escape there closed the sheet instead of going back, and the key handlers
and keyboard shortcuts in those sections did nothing. They are now the presentation's: Tab goes round them with the
presentation's own controls, their keys work while it is up, Escape goes back before it closes the sheet, and
dismissing the sheet from one returns the focus to the control that opened it.

**A `NavigationStack` bound to a typed path shows the screens that are not values of its type.** A
`navigationDestination(isPresented:)` or `(item:)` screen, or a `NavigationLink` with a view for its destination, was
written into the binding and dropped there: the screen never came up, and the flag that asked for it went straight
back to `false`. The stack now keeps such a screen itself, over the values it was pushed on, as SwiftUI does; taking
one of those values off the binding takes it off too.

**A WebAssembly program no longer stops where TUI's resource bundle isn't at its build machine's path.** It looks
for `TUI_TUIStrings.resources` beside the program, as every other platform does, and reads TUI's own words in English
where it isn't there. `Tools/Web/build.sh` serves it beside the program. An app's own resources are still its own
`Bundle.module`'s to find.

**Scroll bars appear over the content while the pointer is over it, instead of in a column of their own.**
`.overContent` is now the default `scrollIndicatorPlacement`: a `ScrollView`, `List`, `Table` or `TextEditor` whose
content overflows draws its bar (or its "N more" lines) over the content's edge while the pointer is over it, and
nothing when it isn't, so the content keeps the whole width. While the view holds the focus the bar moves beside the
content, into a column of its own, as before, so a keyboard user still sees where they are without it covering
anything. A scroller that can never hold the focus, such as a tall menu's, keeps its bar beside its rows, so a keyboard
user still sees there is more. To keep the old layout, a column always reserved for the bar, write
`.scrollIndicatorPlacement(.besideContent)` at the top of the app. `scrollIndicatorsFlash` lights only indicators that
are drawn, so under the new default a flash shows nothing until the pointer or the focus brings them.

**A `MeshGradient` written with control points draws on WebAssembly.** One made with `bezierPoints:` stopped the
program on the first frame that drew it, as did any mesh 32 or more vertices across: the slots its animation
keeps were numbered for a 64-bit `Int`. Other platforms are unchanged.

**Repeating animations repeat on WebAssembly.** `repeatCount(_:autoreverses:)` and `repeatForever(autoreverses:)`
stopped at the end of their first pass there, and a spring ended a hair short of its target, because a cap meant
for a 64-bit `Int` came out as zero in a 32-bit one. Other platforms are unchanged.

**`UserDefaultsStorage` exists on WebAssembly.** It was declared for Apple platforms and Linux only, so an app that
named it did not compile for `wasm32-unknown-wasip1`. There it is Linux's: a JSON file per suite in the app's
configuration directory.

**Scrolling sends far fewer bytes.** Where most of the rows on screen moved, as when a list or scroll view scrolls,
TUI now has the terminal move them with a scroll region and writes only what the move exposed and what it got wrong,
rather than rewriting every row. Over the `Stress` sessions that is about 30% fewer bytes, and a wheel notch over
rows of dissimilar text sends about a tenth of what it did. What is on screen is the same. `TUI_SCROLL_OUTPUT=off`
restores the old output, should a terminal get scroll regions wrong.

**Scrolling a `List` or `Table` that isn't focused no longer keeps a row's size it shouldn't.** The wheel, or a
key, over such a list between frames draws the rows past the last one on screen to learn how far it can scroll. When
the frame before had kept the list from its cache, those rows were measured against the wrong frame's record of what
they read, so a row whose size depended on the time or an animation had that size kept as if it never changed, and a
debug build stopped on an assertion. Nothing is cached between frames now.

**`TestApp` counts the same on every machine.** A running app times its views and keeps more of those it finds slow;
`TestApp` did too, so a test counting how often a body ran or a view was drawn could pass on a fast machine and fail
on a slow or busy one. It now times nothing. Apps are unchanged.

**A picture from a file is kept at the size it's drawn, not the size it is.** A 1,024-pixel picture drawn four cells
wide kept all four megabytes of it in memory; it is now decoded at a power-of-two fraction of its size for its box (on
macOS straight to that size, so the decode's peak falls too), and decoded again when it's drawn larger or much
smaller. The image cache keeps each size under its own key. Layout is unchanged, since a picture is still laid out at
its own size, read from the file's header; glyph output can shift slightly where a picture is now drawn from fewer
pixels. A measure no longer decodes a file at all.

**Fourteen underscored types are no longer public.** `_AlignmentGuideView`, `_BackgroundStopsAtContent`,
`_ContainerValueView`, `_LayoutCore`, `_LayoutValueView`, `_MemoizedRow`, `_OutlineRow`, `_RowEditRestrictionView`,
`_StyleFillBlock`, `_SwipeActionsView`, `_TaggedView`, `_ValueMemoWrapping`, `_ValueScopedTransactionView` and
`_ZIndexView` were TUI's own plumbing, public by accident; the modifiers that return them still do, as `some View`.
SwiftUI has none of these names, so only code that spelled one out notices.

**`ForEach` tells ids apart by their value, not their description.** Two distinct ids that print alike (two `Date`s
within one second) used to share one row identity, so the second row read the first's `@State`, focus and memo. A
row is now keyed by its id's description followed by its hash value, unless the id is a `String`, an integer, a
`UUID`, a `Bool` or a `Character`, whose keys are unchanged; `.id(_:)` and scroll targets are keyed the same way.

**A pop to the root clears `navigationDestination(isPresented:)`'s flag.** A destination written on a pushed screen
used to keep its flag (or its `item:`) set when a breadcrumb or the app's path took the user back past that screen,
and the next visit to it pushed the destination straight back on. The stack now sets the binding back to `false`
(or `nil`) whatever route the screen left by, as SwiftUI does.

**A column header and a tab title draw their Markdown styles.** `TableColumn("**Name** *x*", value: \.name)` draws its
italic, as `Text` does, where it used to draw only the words; so does `Tab("*Inbox*", value: 1) { … }`. A tab with a
symbol or a picture still draws its words plain, and a header too narrow for its whole title cuts the plain words.

**Disappear, appear and scale symbol effects show.** `.symbolEffect(.disappear, isActive:)` now fades the symbol out
as it becomes active, and in as it stops, rather than blanking it at once; `.appear` fades it in as it becomes active;
`.scale` blinks it as it starts and stops, a glyph not being something a terminal can draw larger. macOS only, as the
symbol effects are.

**Rows fade in in lazy stacks, lists and tables.** Under `withAnimation`, a row a `ForEach`, an `if`/`else` or a
`switch` puts into a `LazyVStack`, a `LazyHStack`, a `List` or a `Table` now fades in where it lands, as it already did
in an eager stack, and a lazy stack's row with a `.transition` of its own plays it on the way out. A row that only
scrolls into view, or that a removal above it brings into view, is drawn as it is.

**A picture in a tab's label draws, and the image cache's `0` no longer decodes every frame.** A label of your own
(`Tab(value:content:label:)`) holding an `Image` drew its placeholder for good: the strip draws labels as measures,
which never started the picture's load. And with `TUI_IMAGE_CACHE_SIZE=0` a small picture laid out by a measure was
decoded again on every frame; the Example's Tab Views page peaked at around 200 MB instead of 75. A view now keeps
what its measure decoded when the cache doesn't, so `0` costs only the sharing between views.

**Keys read right in ASCII-only text.** With `TUI_PLAIN_TEXT=transliterate` the status bar's keys and any text naming
a key are spelled before layout: `⌃Q` as `^Q`, and the other modifiers and the keys that type nothing by name, `⌥F` as
`Alt-F`, `⇧⇥` as `Shift-Tab`. They used to come out blank, so the quit hint read ` Q quit`. With `TUI_PLAIN_TEXT=1`,
or a locale naming a character set other than UTF-8, the keys are spelled so too, and nothing else is: the rest of the
text is still folded to ASCII in the cells it was laid out in, which had no room for `Alt-` in the one cell `⌥` takes.

**Your app can run in a browser, and the browser demo takes settings.** `Tools/Web/build.sh --product NAME
--package-path DIR` builds any executable for the WebAssembly page, not only the Example, and the new article "Running
Your App in a Browser" covers what works there, the commands, publishing on GitHub Pages and the download's size. The
page now offers settings before *Run*: colours, reduced motion, ASCII-only text, arrow-key focus and, for the Example,
the page to open on and the language. The address keeps them, so a link opens the same configuration. The Example
opens on the page `TUI_EXAMPLE_PAGE` names, as `--page` already did.

**Focusable controls take far less memory.** A control's default focus id is its identity path, which
wrote each view's type in full, and a view's type names every view nested inside it: tens of kilobytes for a control
a few dozen views deep, kept for as long as the control is and hashed every frame. `ViewIdentity.path` now writes a
generic type's arguments as a 16-digit digest of its whole name (`ModifiedView<9f3a…>`), the same in every run. The
Example's peak memory over a tour of its pages fell from 82 to 69 MB, and its CPU time by nearly 4%.

**A menu bar costs a frame a quarter of what it did.** Every frame of an app with commands draws each
closed menu's items for the keyboard shortcuts they register, and throws the drawing away. Each row was measured
first, and each `Picker` among them (the display commands' palette, border and control style pickers) resolved its
options and drew every label, though a picker registers no shortcut. Neither happens now: a frame of an inbox under a
menu bar costs 30% less, and the menu bar's share of it fell from 35% to 12%.

**Documentation for readers who have never used SwiftUI.** The "New to SwiftUI" article explains views as values,
`body`, `some View`, view builders, modifiers and their order, `@State`, bindings, `@Observable`, the environment,
identity, focus and keys, each with an example to run. Getting Started, Building Your First App and the landing page
link to it. Coming from Bubble Tea maps Bubble Tea's model, messages, commands, Lip Gloss and Bubbles onto TUI, with
the same small app in both, Coming from Ratatui does the same for Ratatui's loop, layout constraints and widgets, and
Coming from Textual for Textual's widget tree, reactive attributes, messages and CSS, and Coming from Ink for Ink's
components, hooks and flexbox.

**`listRowInsets` written twice on a row: the inner one wins, as in SwiftUI.** The two added up, so a row given a
default and an override closer in got both. The inner statement now replaces the outer on the edges both name; an
edge only one names keeps its inset, and an inner `nil` sets the default on every edge.

**An edit a text binding refuses leaves the caret where it was.** A binding whose setter keeps the old text (a
digits-only field handed a letter) kept the text, but the caret moved as if the edit had been made, so the next
Delete or Backspace acted in the wrong place. In `TextField`, `SecureField` and `TextEditor`.

**`.disabled(false)` no longer re-enables a control already disabled.** `Button`, `Toggle`, `Slider`, `Stepper`,
`Picker`, `DatePicker`, radio buttons, `List`, `Table` and `ScrollView` each have a `disabled(_:)` of their own, and
the last call won: `.disabled(true).disabled(false)` was enabled. Each adds now, as SwiftUI's modifier does and the
text controls' already did.

**A focused, empty `SecureField` with a wide prompt keeps its width.** The prompt is drawn unmasked but was measured
as bullets, one cell a character, so each wide character in it pushed the field a cell wider and cut off its closing
cap.

**The graphical `DatePicker` lines up in Japanese and Chinese.** Its weekday initials and month title were cut and
padded in characters, so a two-cell initial made each weekday column four cells over a grid of three, the title
pushed its ▶ past the edge, and every Chinese initial read 周. They are measured in cells now, and where the cut
weekday names do not tell the days apart the very short ones are drawn.

**Typing a `DatePicker` component changes only that component.** Each digit was applied to the date the previous one
had written, so the partial values re-clamped the rest: typing the year 2027 in a range starting 15 March 2020 gave
15 March 2027, and typing 2024 over 29 February gave the 28th. Each digit is now applied to the date as it was before
the first.

**A click on another `DatePicker` component starts typing afresh there.** The digits half-typed into the component
left behind were kept, so the next digit was appended to them: "2" into the year, a click on the month and "5"
set the month to 25, clamped to 12.

**Two adaptive `GridItem`s fit the room they are given.** The gap between their two groups of columns was never set
aside, so the columns came to a cell more than the grid's width and the last one was cut.

**A `ZStackLayout` is as flexible as its layers.** It reported a rigid size whatever its layers were, so a filling
layer (a `Color`) could not share a row's slack with its siblings as it does in a `ZStack`.

**An `HStackLayout` row keeps a wrapped text's lines.** A subview given less than its ideal width was placed at the
narrower width but its one-line height, so a text that wrapped there lost every line after the first. It is
measured again at the width it gets, as in an `HStack`.

**`Divider(character:)` with a wide glyph draws a rule of the width it is given.** An ideograph or an emoji drew a
horizontal rule twice as wide as offered, and in a row a vertical rule two cells wide where the divider had said it
was one, over its neighbour. A glyph that takes no cell now draws the axis's own rule.

**A `scrollTo` made as a keyboard glide lands is the app's own.** It replaced the glide's parked landing but kept
its landing mark, so it was sought again by position and jumped to, whatever animation it was made in.

**Select-all and a range leave `.selectionDisabled()` rows out.** ⌃A, Shift with an arrow, Home or End, a Shift-click
and the extend mode selected every row they covered in a multi-selection `List` or `Table`, the locked ones
included, though a click or Return on such a row selected nothing. They skip it now, as SwiftUI's do.

**⌃R picks a row up in a refreshable list.** `.refreshable` took every ⌃R, ahead of the focused control, so a
reorderable `List` or `Table` (or a `.draggable` view) inside one could never pick a row up from the keyboard: the
refresh ran instead. The focused control now has the key first, and the refresh runs when it lets the key go.

**A palette's search index is built without holding up other palettes' lookups.** Building one held the
store's lock, so converting a picture with any other palette, on any thread, waited for it.

**Choosing a format in the save panel no longer keeps a trailing space before the extension.** "report "
saved as Markdown was `report .md`.

**`openDocument(at:)` no longer waits forever when Save As interrupts it.** Behind a save panel opened for
its unsaved changes, it never returned if Save As, or another save, took the panel over; it now throws
`CancellationError`.

**`Spring(duration: 0)` arrives at once.** Its `value(target:time:)` was NaN, and a negative duration
never moved.

**A root title that changes while screens are pushed keeps the breadcrumb trail.** The crumbs between
the root and the screen on top turned into "…".

**A pushed screen keeps its `@State` while another is pushed over it.** It came back reset, or with the
state of the screen that had covered it, and a screen pushed over another of its type started with that one's state.
The same in a collapsed split view's linked screens.

**A NaN or infinite fraction no longer traps.** `.presentationDetents([.fraction(x)])` and
`.scrollFollowMargin(.fraction(x))` with `x` NaN (a 0 / 0 ratio), infinite or huge crashed; the detent now resolves
within the screen and the margin to none.

**An app that has run leaves ⌃C, `kill` and ⌃Z working** (macOS). The signals it watched stayed ignored
after it stopped, for the rest of the process and anything it launched.

**Modifiers on a `Form` row keep all their settings.** On a row in a form, `.onContinuousHover` reported
whole-cell locations, `.task(name:)` lost its name, a key-titled `.alert` stopped following a subtree's `\.locale`,
and a sheet ignored its size classes.

**A JSON-file `@AppStorage` store no longer reverts another instance's newer value.** A flush wrote back
every key the instance had ever written, so after a second instance (another terminal tab) changed a setting, the
first one's next unrelated write put the old value back. A flush now writes only what changed since the last one.

**F2 opens a settings panel in every app, with or without a menu bar.** Its tabs are the app's `Settings` scene first
(a `TabView`'s `Tab`s one each, any other content one tab named after the app), then TUI's View (palette, border style,
control style) and Accessibility (the View menu's seven checks), after a divider. TUI's choices override the system,
the `TUI_*` variables and the scene's modifiers for the run, are never saved, and are the menu bar's own, so the two
agree. ⌃, opens it too where the terminal sends it (the kitty keyboard protocol), as `openSettings`, `SettingsLink` and
the menu bar's Settings… do, now in every app. An app's own binding on F2 or ⌃, comes first;
`.settingsPanelKey(_:)` moves F2, and `.builtInSettingsTab(_:visibility:)` and `.builtInSettingsTab(_:content:)` hide or
replace TUI's tabs. F1's list names F2. TUIApp links TUIPickers and TUIForms for the panel. See "The Settings Panel" in
the KeyboardShortcuts article.

**A `Divider` among a segmented picker's options sets the groups apart.** It draws a heavier rule, `┃`, between the
segments either side, where it drew nothing; a menu-style picker still draws it as a separator.

**An animated picture plays even when the frame it is first shown in draws it twice.** A geometry owner above it (a
`coordinateSpace`, a scroll view, a matched geometry effect) that drew its subtree again in that frame, as it does when
a reader inside drew from a wrong answer, left the picture on its first frame for good. The file panels' preview met it
now and then, under load.

**An active `.symbolEffect(.disappear)` hides the symbol** (macOS). The glyph's cells are left blank while it is active,
at once, where SF Symbols draws the symbol off; it was drawn as if no effect were set.

**A `List` row's `.badge(_:)` with a modifier after it is still drawn.** `Text("Inbox").badge(5).padding()`, or with a
`.foregroundStyle` or an `.onTapGesture` after the badge, drew the row with no badge; only environment writes were read
through. A `.badgeProminence(_:)` written around such a modifier reaches the badge, as SwiftUI's does.

**`.onAppear`, `.onDisappear`, `.task`, `.onChange`, the gestures and `.keyboardShortcut` on several views leave them
side by side.** `HStack { Group { a; b }.onAppear { … } }` drew `a` over `b`, and a `GridRow` carrying one of them left
the grid's columns; now the members reach the stack or grid one by one, as SwiftUI's do, and the lifecycle actions still
run once for the group (a `ForEach` of fifty rows with a `.task` starts one task). A gesture is each member's, and a
shortcut still goes to the first control among them.

**`TUI_ARROW_FOCUS=geometric` tries out arrow keys that go by the screen.** An experiment, off by default: an arrow the
focused control doesn't use moves to the nearest control in its direction, one overlapping the focused control's
columns (or rows) first, then the nearer, then the earlier in Tab order; with none it stays put, at the end of a row or
the foot of a column, rather than wrapping on in Tab order.
Tab is unchanged, and arrows still stay inside the active section and a sheet. The Example's Focus page has a grid to
try it on. See `Documentation/Input and focus/Geometric arrow focus.md`. The arrows reach controls a `ScrollView` has
scrolled out of sight too, and the scroll views around one bring it into view, so a grid much larger than its scroll
view is walked with the arrows alone.

**`TUI_PLAIN_TEXT=transliterate` tries spelling text in ASCII before layout, an experiment.** For a terminal that shows
only ASCII, every `Text`, button title, table cell and header, panel title and field prompt is spelled in Latin letters
before it's measured, so `你好` is `ni hao` in six cells, where `TUI_PLAIN_TEXT=1` (and a non-UTF-8 locale) cut it to
`niha` in the four it was laid out in. So is every string the framework draws without a `Text`: tab titles and badges,
list badges and placeholders, status bar items, tooltips, navigation crumbs, a spinner's label, a stepper's read-out, a
date picker's month. Japanese is read as Japanese (`日本語` `nippon go`, on macOS), Cyrillic by BGN/PCGN (`Имя`
`Imya`), Greek by UNGEGN, emoji as short ASCII (`🙂` `:)`, `🚀` `:rocket:`). `TestApp` and `renderOnce` honour it too.
What's typed into a field keeps its own characters. Off unless named, and free when off; the folding at output stays
for everything else. See `Documentation/Historical/Text, editing and the clipboard/ASCII
transliteration before layout.md`.

**Every menu bar's View menu turns the accessibility and display preferences on and off.** Differentiate Without Color,
Reduce Motion, Reduce Transparency, Increase Contrast, Breathing Focus, Spell Out Keys and Focus Follows Pointer, each a
check showing whether it is on. A choice there wins over the system's setting, the `TUI_*` variable and the app's own
modifiers (`.reduceMotion(_:)` and the like) until the app quits, and isn't saved. They are TUI's default commands in a
placement of their own, `CommandGroupPlacement.accessibility`, which `CommandGroup(replacing: .accessibility) {}` or
`commandsRemoved()` takes away. An app with no commands has no menu bar, and so no View menu.

**The async `KittyGraphics.withSupport(_:compression:operation:)` runs its operation on the caller's actor.** It is
`nonisolated(nonsending)`, and its `isolation:` parameter is gone; a call with a trailing closure compiles as before. It
was the cause of two of Swift 6.4's deprecation warnings, which now has none.

**`TUI_DEBUG_FOCUS` no longer writes to a fixed `/tmp/tui-debug.log`.** It writes to the file `TUI_DIAGNOSTICS_FILE`
names, else to `tui-debug-<user>.log` in the temporary directory, so people sharing a machine don't share one log.

**On Linux, `UserDefaultsStorage` keeps its file with the app's other settings.** It was
`$XDG_DATA_HOME/<app>/UserDefaults.json` (else `~/.local/share/<app>/…`), while `@AppStorage`'s default store was in
the configuration directory. It is now `UserDefaults.json` (or `UserDefaults-<suite>.json`) in
`$XDG_CONFIG_HOME/<app>` (else `~/.config/<app>`), where the XDG specification puts settings, beside `settings.json`,
and `TUI_CONFIG_DIR` moves it with them. Nothing is migrated: to keep values saved before, move the file from
`~/.local/share/<app>/` to `~/.config/<app>/`. TUI no longer reads `XDG_DATA_HOME`.

**`@SceneStorage` is kept per terminal session, falling back to the last saved.** Each value has a copy for the
terminal window, tab or pane the app runs in (a tmux pane, `TERM_SESSION_ID`, `ITERM_SESSION_ID`, `KITTY_WINDOW_ID`,
`WEZTERM_PANE`, `WT_SESSION` and the like) and a copy last saved from any session. A read takes the session's copy, else
the last saved, else the default. Running the app again in the same window puts back where it was there, two windows
running it at once no longer overwrite each other, and a new window starts from the last saved. Without a session, as
over a plain ssh connection, it works as before. A store keeps each session for 30 days after its last write, however
many there are. See `Documentation/Historical/State and dynamic properties/Scene storage per terminal session.md`.

**`@SceneStorage` uses the store `defaultAppStorage(_:)` sets, as `@AppStorage` does.** It used the process's default
store whatever the environment said, so in `TestApp` it wrote your real preferences where `@AppStorage` stayed in
memory.

**Differentiate without colour now changes how TUI's controls draw.** With macOS's setting on (when you're at the
machine the app runs on) or `TUI_DIFFERENTIATE_WITHOUT_COLOR=1`, the controls say their state as they do on a terminal
without colour, over their colours: the focus in reverse video, a disabled control faint, a `Table`'s selected rows
marked `●`, and a radio button's `●` only on the selected option. Off by default.

**A graphical `DatePicker` draws today in bold.** It was told apart by the accent colour alone, a difference of hue that
colour-vision deficiency loses and that a terminal without colour doesn't draw at all.

**A standard menu whose every group is replaced with nothing leaves the menu bar.** `CommandGroup(replacing: .help) {}`
left Help's title in the bar over an empty menu, and an empty group between two others drew a second separator. As
on macOS, where replacing each of File's groups with nothing takes File away, a declaration whose views make no row
(empty content, or an `if` that is false) now counts as nothing. A `CommandMenu` is still a menu even empty, as there.

**A disabled control stays visibly disabled in Warp's light theme.** Warp draws faint (SGR 2) darker there rather than
fainter, and its black default foreground not at all, so at no colour a disabled control looked enabled. On Warp with
a light background, disabled is now faint and italic, for a control at no colour and for a row under
`.selectionDisabled(_:)` at any depth. So is a text field's prompt at no colour, which faint alone told from text
somebody typed. Every other host, and Warp in a dark theme, draws exactly what it did.

**`TUI_CURSOR_FOLLOWS_FOCUS=1` tries out the terminal's own cursor on the focused control.** An experiment, off by
default, for judging what screen readers, braille displays and magnifiers make of it: after each frame the real cursor
goes to the focused control's first cell (a text field's insertion point, as before) and is shown there; `hidden` puts it
there and keeps it hidden. See `Documentation/Input and focus/Cursor follows focus (proof of concept).md`.

**The focus can follow the mouse pointer.** With `TUI_FOCUS_FOLLOWS_POINTER=1`, or the app's
`Scene.focusFollowsPointer()`, the control the pointer moves onto takes the focus, as a click there would, without
pressing it. A resting pointer takes nothing back from the keyboard; its next move does. A text field you've typed in
keeps the focus until a click or the keyboard moves it; while a sheet, an alert or a popover is up the pointer moves the
focus only within it, and while a menu is open, not at all. Off by default: it has the terminal report every move.

**`TUI_BREATHING=0` holds every focus indication still.** The control that has the keyboard is picked out by colour
and bold alone, rather than breathing or blinking; the text cursor still blinks. An app can do the same with
`Scene.focusBreathing(false)`, which can't undo the person's `0`. Reduce Motion still leaves the breath alone.

**A notification can also be posted on the desktop, through the terminal.** `post(_:desktop:)` takes
`NotificationDesktopDelivery.always`, or `.whenInactive` for only while the terminal's window doesn't have the focus.
It sends the message as `OSC 9` with the frame that draws the toast, to the terminals that post one (Ghostty and iTerm2,
or any terminal under `TUI_NOTIFICATIONS=1`). Where the terminal posts none, the machine posts it itself — `osascript`
on macOS, `notify-send` on a Linux desktop — but only when TUI can tell you're at this machine, never over ssh; one
route or the other, never both. `TUI_SYSTEM_NOTIFICATIONS=0` turns that off, and `1` turns it on where TUI can't tell.
Unlike `requestAttention(_:)`, it never rings the bell instead. It is one-way: the desktop notification has no buttons,
and nothing reports whether the person saw it.

**Notifications can carry buttons, and the keyboard reaches them.** `post(_:actions:)` takes `NotificationAction`s, each
a title, an optional `ButtonRole` and an action; choosing one runs it and dismisses the toast. F6 moves the focus to the
newest toast with a button, F6 again to the next older one, and past the oldest back where it was. Escape dismisses the
toast holding the focus, and Tab reaches toasts after the page. The status bar shows "F6 notification" while a toast has
a button. A toast does not fade while its button has the focus. A toast posted with `duration: nil` and no actions gets a
Close button.

**A notification can go above or below sheets, alerts and dialogs.** `post(_:layer:)` takes `.abovePresentations`, drawn
over anything presented with its buttons reachable by F6 while it's up (Escape still closes the sheet unless the toast
has the focus), or `.belowPresentations`, drawn under it with its buttons out of reach and its timer stopped until it
closes. Without one, a post through `NotificationService.current` goes above; one through a view's
`@Environment(\.notificationService)` belongs to that view's window, or to the sheet or alert it's in, and goes under
whatever is presented over that. A toast posted for a window that isn't in front waits for it the same way.

**A notification can draw any views.** `post(style:duration:placement:content:)` takes a `@ViewBuilder` closure in place
of a message. It is called each frame the toast is drawn, so the toast shows what its content reads now, such as a
download's progress.

**Notifications can go to any of six places, several at once.** `post(_:placement:)` takes a `NotificationPlacement`:
a corner, or the middle of the top or bottom edge. Each placement stacks its own toasts with the newest nearest its edge,
so an app can show progress at the bottom and errors at the top right. `defaultPlacement` sets where posts that name
none go (top right unless changed), `width` sets how wide toasts are, and `dismissAll(at:)` clears one placement. A
stack taller than the window shows its newest toasts that fit, and no toast is cut in half.

**A notification can stay until it is dismissed, and code can dismiss it.** `post` returns a `NotificationID`;
`dismiss(_:)` fades that toast out at once, and `dismissAll()` fades out every one. `duration: nil` keeps a toast up
until something dismisses it. While toasts are up but none is fading, TUI no longer redraws the screen four times a second.

**A notification can say what it is about.** `post("Upload failed", style: .error)` draws the toast's border and a
leading emoji: `.info` (ℹ️), `.success` (✅), `.warning` (⚠️) or `.error` (❌), the border in the palette's colour for
it. The glyph's shape means the style never rests on colour alone; a terminal that shows only ASCII gets `i`, `ok`, `!`
and `X`. `.plain`, the default, looks as toasts did. A long message now wraps as any `Text` does.

**Notifications show with no host to add.** Every scene draws the toasts `NotificationService` holds over its content,
between the window's bars and above any sheet or alert, so a post shows whatever the app's views are. A page smaller
than the window no longer moves when a toast appears. `.notificationHost(width:)` is gone: delete it from your root
view, where it would now draw every toast twice.

**A sheet can be resized and moved from the keyboard, and shows where to grab it.** A sheet's bottom and right edges
and its corner carry the grips a `.userResizable()` view draws, lit under the pointer. Tab now ends a sheet's focus
order with two more stops. On **Resize** the grips breathe, the arrows change the size as dragging the edge does (Shift
for five), and Home puts the sheet back at its own size, which also makes an open or save panel forget the size it
saved. On **Move** the border breathes, the arrows move the sheet within the screen, and Home centres it. The status bar
names the keys while either stop has the focus. A one-row sheet has only Move. Alerts and confirmation dialogs have
neither stop and no grips.

**`Self._printChanges()` and `_logChanges()` say why a body ran, as in SwiftUI.** Called in a view's `body` or a
modifier's `body(content:)`, each evaluation writes a line such as `Counter: _count changed.`, naming the `@State` written,
`@self` for a new value from the parent, `@identity` for a new view, an `@Environment` property whose value moved
(`_colorScheme`), `an @Observable property` for one the body read being written (SwiftUI names it, `\Model.count`,
through API private to SwiftUI), or `unchanged.`. It never says
`unchanged.` when it can't tell: where only something it can't compare could have changed, such as a closure or a
`Binding` in the view, it says `@self may have changed.`. The lines go to `TUI_DIAGNOSTICS_FILE`, or to stderr once the
app quits; `_logChanges()` uses the unified log on a Mac. Code that calls them now compiles.

**`.onScrollWheel { direction in … }` can decline a wheel tick.** Return `false` and the `ScrollView` or `List` behind
the view scrolls instead, so a pane that scrolls something itself can give way at its ends. `.onScrollGesture` still takes
every tick.

**`renderOnceToString(width:height:output:colorDepth:content:)` returns what `renderOnce` would print.** For a test,
a log or a table inside your own output: plain text by default, at the width and height you give, or with its escape
sequences at a colour depth you choose.

**`Path.interpolated(towards:amount:)` morphs one outline into another.** Give a custom `Shape` a progress as its
`animatableData` and return the interpolated path from `path(in:)`. Paths built the same way move point by point, control
points included; paths built differently swap at the halfway mark rather than being resampled. TUI's own; SwiftUI's `Path`
doesn't animate, and TUI's still doesn't by itself.

**OKLab and OKLCh are public on `Color`.** `Color.oklab(_:_:_:)` and `Color.oklch(_:_:_:)` make a colour from CSS's
numbers, `Color.rgbToOKLab(red:green:blue:)` and `Color.rgbToOKLCh(red:green:blue:)` go the other way, and
`color.deltaE(other)` says how different two colours look (ΔEOK: 1 is black against white, about 0.02 the least
anyone sees). They're the conversions TUI's gradients and colour mapping already used.

**`TUI_REDUCE_MOTION`, `COLUMNS` and `LINES` beat what TUI reads from the system.** `TUI_REDUCE_MOTION=0`, and `=0` on `TUI_REDUCE_TRANSPARENCY`, `TUI_DIFFERENTIATE_WITHOUT_COLOR` and `TUI_INCREASE_CONTRAST`, turns off a
machine-wide Reduce Motion, as `=1` already turned it on. `COLUMNS` and `LINES`, each on its own axis, now win over the size
the terminal reports, where they used to be only a fallback, so an export left over from a window since resized pins the size:
if a program draws at the wrong size, look there first. An in-band resize report still outranks them, so the browser page's
guest goes on following the page.

**A terminal can play an animated picture by itself, if you ask.** With `TUI_GRAPHICS_PLAYBACK=1`, the frames are handed
to the terminal after one pass, and from then on a tick costs no bytes and no wake (7,243 bytes a tick for a picture of
40 x 16 cells before). The picture still stops when nothing on screen shows it. This is off by default: Ghostty 1.4.0 and
kitty both take the commands, but nobody has yet seen them draw this way. iTerm2 3.7.6 and Warp ignore or refuse them.

**An animated picture can play under Reduce Motion.** It still shows its first frame by default, which suits chrome.
`.imageAnimationRespectsReduceMotion(false)`, on a picture or a subtree, says this one is the app's content and should
play regardless. To choose for yourself, read `\.accessibilityReduceMotion`, as in SwiftUI.

**Pictures draw in real pixels on a terminal with Sixel and no Kitty graphics.** TUI asks: no answer to its Kitty
questions and attribute 4 in the terminal's device attributes, outside tmux. Foot, mintty, mlterm and, once TUI runs on
Windows, Windows Terminal should all get pictures this way; it has only been run on iTerm2, with Kitty hidden from it.
`TUI_GRAPHICS=sixel` asks for it anywhere. A picture is sent again only for the cells that need it, so a menu opening
over one costs nothing and closing it costs what it uncovered, and at most about a megabyte a second goes out: a picture
moving faster than that keeps its last frame, or shows text characters, until it can catch up. Other terminals write the
same bytes as before, apart from one short question at startup on a terminal with no Kitty graphics.

**On Warp, a picture partly covered or clipped draws the part that shows.** Warp ignores a placement's source rectangle, so
a picture with a view over it, or scrolled partly out of sight, used to be blank until it was whole again. What is left of it
now goes as images of just those pixels, one for each rectangle of cells, kept for when they are asked for again. No other
terminal is sent a byte more.

**A view of yours doesn't run `body` on a frame where nothing it depends on changed, as in SwiftUI.** What it holds is
compared, field by field, with no `Equatable` asked of it, and the picture it drew is handed back: two sibling bodies of
50 ms beside a written leaf took 201 ms a key before this and take 1 ms. A closure or a `Binding` it holds counts as
changed only below a write. A read in `body` that nothing tracks, of a global, a plain class or the clock, now stays as it
was drawn, as in SwiftUI, and a body's side effects don't happen on a frame that serves it. If part of a screen goes
stale, `TUI_RUN_BODY_ON_EVERY_FRAME=1` runs every `body` on every frame, and `TUI_VERIFY_RENDER_MEMO=1` names the view.

**`App.run()` runs an app you made yourself.** A program that works something out before starting its app, such as from
its command line, makes the app with those values and calls `await Viewer(path: path).run()`, with no global to carry
them. See `Starting an App Yourself` in `Scenes and Quitting`.

**`maxFrameRate` counts from the start of a frame.** It counted from the end, so a frame's own time was added to the
interval: a screen taking 22 ms a frame drew 25 frames a second under a cap of 60, and a key pressed in the gap waited
for it. With a ticker keeping the program busy, key to frame on a 1,920-cell screen goes from about 42 to 24 ms, and
with a 50 ms body from 99 to 51. A program that asks for frames without pause now draws in the time it was leaving idle,
so it uses more CPU (52% to 90% on that screen). A lower `maxFrameRate` gives that back.

**`TUI_FRAME_TRACE=<path>` says what each frame was for.** One tab-separated line per frame: when it began, how long
it took, the bytes it sent, its render cache hits and misses, and what caused it. See `Keeping Your App Fast`.

**A page on keeping an app fast.** What an author can do, and how to find out which of it a screen needs:
`Keeping Your App Fast` in the documentation.

**A terminal that can only show ASCII gets the best ASCII we can give it.** Where the locale names a character
set other than UTF-8, each character goes out as ASCII in the cells it had: `é` as `e`, a box's corners as `+`, and
`你` as `ni`. This isn't a mode to choose.

**The pointer's locations have SwiftUI's types.** `DragGesture.Value` (`location`, `startLocation`: `CGPoint`;
`translation`, `velocity` and the predictions: `CGPoint` and `CGSize`), `DragGesture.minimumDistance` (`CGFloat`),
`SpatialTapGesture.Value.location`, `HoverPhase.active`, the action of `onTapGesture(count:coordinateSpace:perform:)`,
and `DragSession`, `DropSession`, `DropInfo` and `onDrop`'s locations, all measured in cells. A ported drag compiles
untouched, with new overloads `offset(_: CGSize)`, `offset(x: CGFloat, y: CGFloat)` and `position(_: CGPoint)`.
Code that wants a cell writes `CellPoint(location)`, the cell a location falls in, or `CellSize(translation)`.

**The pixel mouse.** Where a terminal can report the mouse in pixels (xterm's SGR-Pixels, `?1016`), a gesture's or a
`onContinuousHover`'s location is fractional, in cells. Measured on Ghostty 1.4.0 and iTerm2 3.7.6; asked by DECRQM of
those, of xterm.js, and of kitty, WezTerm, foot and xterm when the environment names them; every other terminal reports
whole cells as before. It is on only while such a view is on screen, or under the new `MouseSupport.subCellLocations`
for an `onMouseEvent` handler, which reads the new `MouseEvent.preciseX` and `preciseY`. Hit tests stay on whole cells.
`TUI_PIXEL_MOUSE=0` turns it off.

These notes cover the change from the single-module package (a `TUI` target plus `TUICore`, `TUIStyling`, `TUIView` and `TUIImage`, as of 1 October 2026) to current `main` (29 October 2026). The module split itself landed between 8 and 19 October. If you were already building against a commit from after 8 October, skip the parts that describe things you already have. What changed from 23 to 29 October that an existing app may notice, and is not described elsewhere, is under "Since 23 October" in the upgrade-affecting changes.

### TUIkit is now TUI

The project, its package, products and modules are renamed (25 October 2026). Every name drops the "kit": the
package `TUIkit` is `TUI`, the umbrella `import TUIkit` is `import TUI`, and each module `TUIkitX` is `TUIX`
(`TUIkitApp` is `TUIApp`, `TUIkitTables` is `TUITables`, and so on). Type names are unchanged. These notes use the
new names throughout, for the package as it was on 1 October as well.

- Change each `import TUIkit…` to `import TUI…`, and each `.product(name: "TUIkit…", …)` to
  `.product(name: "TUI…", …)`. The repository is renamed too (29 October): depend on
  `https://github.com/wadetregaskis/TUI.git`. The `package:` argument is the package's identity, which SwiftPM
  takes from that URL, so it is `"TUI"`: `.product(name: "TUI", package: "TUI")`. GitHub redirects the old URL,
  but a dependency that still names it keeps the identity `TUIkit`, and its `package:` arguments must say so.
- The trait `UnexportTUIkitSymbols` is `UnexportTUISymbols`. A dependency that names its traits
  (`traits: […]`) must use the new name.
- The resource bundle that ships beside an app is `TUI_TUIStrings.bundle`, not `TUIkit_TUIkitStrings.bundle`.
- The documentation's paths are `/documentation/tui/…`, not `/documentation/tuikit/…`.
- Every environment variable's `TUIKIT_` prefix is `TUI_` (`TUIKIT_CONFIG_DIR` is `TUI_CONFIG_DIR`, and so on), and
  so is the `TUIKIT_TEST_SUPPORT` compilation condition; the old names are not read.
- Unchanged: the folders and defaults keys where an app's settings are kept, so nothing a user saved is lost.

### `DocumentGroup`, and `FileDocument` on Linux

`DocumentGroup` is new (product `TUIDocuments`, in the umbrella), with SwiftUI's signatures: `DocumentGroup(newDocument:editor:)`
and `DocumentGroup(viewing:viewer:)`, for a `FileDocument` and a `ReferenceFileDocument`; `FileDocumentConfiguration`,
`ReferenceFileDocumentConfiguration`, `DocumentConfiguration`, and the `newDocument`, `openDocument` and `documentConfiguration`
environment values. File has New, Open…, Save and Save As…, through the file panels. A terminal has one window, so one document
is open at a time: opening or creating another replaces it, after asking Save, Don't Save or Cancel, and so does quitting.

- `FileDocument`, and the `fileExporter` forms that write one, now exist on Linux, over a `FileWrapper` of TUI's with
  Foundation's API. Remove any `#if canImport(ObjectiveC)` around them. Apple platforms keep Foundation's.
- `ReferenceFileDocument` is new, and so are the four `fileExporter` forms that write one.
- `swift run DocumentEditor` is a small text editor written with it.

### If you only need the short version

- If your target depends on the `TUI` product and writes `import TUI`, it still compiles the same framework with the same names. Nothing about the split forces a change.
- Check the "Upgrade-affecting changes" list below. The ones most likely to bite are the renamed resource bundle, the opt-in status bar and toolbars, the AppKit bridges that need `import TUIAppKit`, and the removed spellings.
- If you want a smaller app, depend on the module products you use instead of `TUI`.
- Two package traits are on by default and change how your macOS release build is linked. They are described below, with the opt-outs.

### The module split

TUI is now 32 library products. Before, there were five (`TUI`, `TUICore`, `TUIStyling`, `TUIView`, `TUIImage`).

#### The umbrella still works

- `import TUI` is the whole framework, as `import SwiftUI` is SwiftUI. The `TUI` module declares nothing itself. It re-exports every other module except `TUIAppKit`, `TUIFilePanelsAppKit` and `TUIMacros`, which you import separately.
- `import TUI` also re-exports Foundation, as `import SwiftUI` does, so a file ported from SwiftUI that names `CGRect`, `URL` or `Date` needs no `import Foundation`. The module products do not re-export it.
- Qualified names such as `TUI.Label` or `TUI.ColorPicker` still resolve, through the umbrella's re-exports. The test suite pins this for types from many of the modules.
- `TUI` is still the right default for an app. The README and the docs assume it.

#### Depending on fewer modules

- Each module an app might want alone is a library product with the module's own name. List the products you use in your target's `dependencies:` and import those modules.
- SwiftPM compiles and links the products your target lists, plus what they are built on. Your `import` lines decide only which names your files can see. A target that depends on `TUI` and imports only `TUITables` still builds and links all of TUI.
- Every app needs `TUIApp` (`App`, `Scene`, `WindowGroup`, the run loop and the terminal). Add the product of each module whose names you use.
- Each module re-exports the modules it is built on, so `import TUITables` also gives you `List`.
- Measured on a hello-world app with Swift 6.4.0, stripped, default traits: `TUI` is 9,241,968 bytes. `TUIApp` alone is 5,751,768 bytes (-37.8%), compiling 8 TUI modules instead of 25.
- If you forget a product, the compiler says `cannot find 'Table' in scope` or `value of type 'Text' has no member 'tableStyle'`, and does not name a module. The documentation has a "Which Module Provides It" page that lists every public name with its module and product.
- Mixing `TUI` with module products in one app is safe. Each module is linked once.
- If you write a library on top of TUI, depend on module products (or `TUIFoundation`), never on `TUI`. Anything in an app's graph that depends on `TUI` gives that app the whole framework.
- Do not build a `.dynamic` library product from TUI's modules while an app also links a TUI product statically. SwiftPM's own build system gives the app two copies of the shared modules. Swift Build makes them dynamic libraries the app must ship.
- Module and product names are now part of what you depend on. Before 1.0, types can move between modules, and a `Package.swift` that lists a module changes if that module is renamed or split. An app on `TUI` never sees such a change.

```swift
.executableTarget(
    name: "YourApp",
    dependencies: [
        .product(name: "TUIApp", package: "TUI"),
        .product(name: "TUITables", package: "TUI"),
    ]
)
```

```swift
import TUIApp
import TUITables
```

#### The products

Foundation and app:

- `TUI`: the umbrella. Everything below except `TUIAppKit`, `TUIFilePanelsAppKit`, `TUIMacros` and `TUITesting`.
- `TUIApp`: `App`, `Scene`, `WindowGroup` and the scene modifiers, the run loop, the terminal (POSIX only), and `renderOnce`. Re-exports `TUIChrome` and `TUIFoundation`.
- `TUIFoundation`: what everything else is built on: `View`, `Text`, stacks, `ScrollView`, `Button`, `Toggle`, `Label`, `Image(systemName:)`, layout, state, the environment, focus and rendering. It cannot run an app on its own. It re-exports `TUICore`, `TUIStyling`, `TUIView`, and two modules that have no product of their own: `TUIStrings` (localization, string tables, SF Symbols names, the resource bundle) and `TUITerminalHost` (the terminal's identity, quirks and capabilities).

Feature modules:

- `TUIBitmaps`: `Image` from a file, URL or bundle, `AsyncImage`, the `.image*` options. Re-exports `TUIImage`.
- `TUIChrome`: the `StatusBar` view, toolbars, notifications, tooltips and `.help`. `TUIApp` and `TUIPresentation` re-export it.
- `TUIColorPicker`: `ColorPicker`, `ColorPickerPanel`, `GradientEditorPanel`.
- `TUICommands`: `Commands`, `CommandMenu`, `CommandGroup` and the placements, and the menu bar they draw. Re-exports `TUIApp` and `TUIPresentation`.
- `TUICurveEditors`: the tone-curve and channel-curve editor panels.
- `TUIEffects`: transitions, content transitions, `.symbolEffect`, `.visualEffect`, `.scrollTransition`, matched geometry.
- `TUIFilePanels`: `fileImporter`, `fileExporter`, `fileMover`, the `fileDialog` modifiers, and the open and save panels. Re-exports the modules its panels are built from: `TUINavigation`, `TUIPickers`, `TUIPresentation`, `TUITables` and `TUITextInput`.
- `TUIFilePanelImages`: `fileDialogPicturePreviews()`, which previews a selected picture in the file panels. Re-exports `TUIBitmaps` and `TUIFilePanels`, and is a product of its own so that an app with file panels and no pictures carries no image decoders, and one showing pictures no file panels.
- `TUIForms`: `Form`, `LabeledContent`, `GroupBox`, `Card`, `Panel`.
- `TUIGrid`: `Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid`.
- `TUILists`: `List`, `OutlineGroup`, `EditMode`, list styles and row modifiers.
- `TUIMenus`: `Menu`, `ControlGroup`, `.contextMenu`, menu styles.
- `TUINavigation`: `NavigationStack`, `NavigationPath`, `NavigationLink`, split views, the inspector.
- `TUINumericControls`: `Slider`, `Stepper`, `Gauge`, `ProgressView`.
- `TUIPickers`: `Picker`, `RadioButtonGroup`, `DatePicker`.
- `TUIPresentation`: `alert`, `confirmationDialog`, `Dialog`, `sheet`, `fullScreenCover`, `modal`.
- `TUIScenes`: the `Settings` scene (shown as a sheet) and `AlertScene`.
- `TUISearch`: `.searchable`, search tokens and scopes, `searchSuggestions`, `dismissSearch`.
- `TUITables`: `Table`, columns, rows, styles, row drag and drop. Re-exports `TUILists`.
- `TUITabs`: `TabView`, `Tab`, `TabSection`, tab styles. Re-exports `TUILists`, and `TUIPresentation`, whose sheet a tab's popover becomes in a compact size class.
- `TUITabImages`: `Tab(_:image:…)`, the tabs whose picture is an image resource named by a string. Re-exports `TUIBitmaps` and `TUITabs`, and is a product of its own so that an app showing images pays nothing for tabs, and one using tabs nothing for image decoding.
- `TUITextInput`: `TextField`, `SecureField`, `TextEditor`.

Opt-in (not in the umbrella):

- `TUIAppKit`: `Color(nsColor:)`, `NSColor(_:)` and `Image(nsImage:)`, and compiled asset catalogue reading. Apple platforms only; empty elsewhere.
- `TUIFilePanelsAppKit`: `fileDialogSystemIcons()`, which draws the file panels' items with the Finder's icons. Built on `TUIAppKit` and `TUIFilePanels`, and a product of its own so that an app that takes `TUIAppKit` for `Color(nsColor:)` does not link the file panels (+29% in an app that does). Apple platforms only; empty elsewhere.
- `TUIMacros`: the `@Animatable`, `@AnimatableIgnored` and `@Entry` macros.
- `TUITesting`: `TestApp`, which runs an app or a view in a unit test with no terminal: press keys, click, move a clock by hand and read the screen. For test targets, so a shipping app carries none of it. See [Testing Your App](https://swift-tui.com/docs/documentation/tui/testingyourapp).

Low-level, as before:

- `TUICore`, `TUIStyling`, `TUIView`, `TUIImage`. These four build on Windows. `TUIView` and `TUIImage` now re-export the lower modules their API names, so one import covers either.

Executable products for trying things out: `Example`, `Stress`, and the development tools `EmojiBugScanner`, `EmojiBenchmark`, `RenderHarness` and `ImageHarness`.

### Package traits: smaller macOS release builds

Two traits are enabled by default. Both apply only to macOS release builds. Debug builds, `swift test` and documentation builds compile and link as before. Neither is applied on Linux or Windows, where they have not been measured. Both apply to every module that a library product ships.

**`DeadStripUnusedAPI`**

- Swift marks every public symbol so the linker keeps it, called or not. With this trait TUI's modules are compiled with `-internalize-at-link`, and your app's linker keeps only the TUI API your app reaches.
- `swift build -c release` passes `-dead_strip`. An Xcode app needs `DEAD_CODE_STRIPPING = YES`, which is not Xcode's default.
- Measured (stripped, 2026-10-11): a hello-world app is 14.7% smaller and `Stress` 12.1% smaller on Swift 6.4.0. On Xcode's Swift 6.2.4 it is 14.9% and 12.3%.
- What it breaks: a statically linked app that `dlopen`s a plugin which calls TUI API the app never calls itself. That symbol is gone from the app and the plugin fails to load.

**`UnexportTUISymbols`**

- A program exports every external symbol it defines, including TUI's. This trait passes one `-unexported_symbol` pattern per TUI module to the linker, which removes them from the export table (bytes that `strip` leaves in place).
- Measured (stripped, 2026-10-12, on top of `DeadStripUnusedAPI`): a hello-world app is a further 3.2% smaller and `Stress` 2.9%, on both toolchains.
- What it breaks:
  - A plugin loaded with `dlopen` into a statically linked app that calls any TUI API through the app fails to load ("symbol not found in flat namespace").
  - A `.dynamic` library that contains TUI exports none of TUI's symbols. A client that uses TUI through it fails to link, or fails at launch if it was linked against an older build of the library.
  - Your own extensions of TUI's types and protocols (`extension View { func card() }`, `extension Color { static var brand }`), and your conformances of TUI types to your protocols, are not exported either, because Swift names those symbols after the TUI module. A client in another module that calls one fails to link, unless the compiler copied its body into the client.
  - The linker refuses `-unexported_symbol` beside an export list. A link that passes `-no_exported_symbols`, `-exported_symbol` or `-exported_symbols_list` (as Xcode's `LD_EXPORT_SYMBOLS = NO` and `EXPORTED_SYMBOLS_FILE` do) stops with "-unexported_symbol cannot be used with -exported_symbol*".

**Opting out**

- `traits: []` on the dependency turns off every default trait of TUI's (today these two).
- `traits: ["DeadStripUnusedAPI"]` keeps dead stripping and turns off the symbol-hiding trait. Use this if your link needs an export list.
- No compiler or linker flag undoes what the traits do. The traits are the only way out.

```swift
.package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main", traits: [])
```

```swift
.package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main", traits: ["DeadStripUnusedAPI"])
```

### Upgrade-affecting changes

#### Because of the module split

- **The resource bundle is now `TUI_TUIStrings`.** It was `TUIkit_TUIkit` when the resources belonged to the umbrella target, and `TUIkit_TUIkitStrings` from the module split to the rename. It is `TUI_TUIStrings.bundle` on macOS and `TUI_TUIStrings.resources` elsewhere. If you ship TUI's bundle beside your executable (an archive, an installer, a Homebrew formula), copy the new name. The bundle holds the translations (German, French, Italian, Spanish, Chinese, Japanese) and the version.
- **A missing bundle no longer stops the program at launch.** TUI's words then read in English, whatever language the user asks for, and `tuiVersion` reads `unknown`. A program copied out of `.build` no longer finds the bundle left in `.build`. It reads the bundle beside it or none.
- **Type names seen at runtime name the declaring module, not `TUI`.** `String(reflecting:)`, `dump` and the debugger show `TUILists.List<...>`, `TUIApp.WindowGroup<...>` and `TUIFoundation.Text`. This is true whichever products you depend on. Code that matches on those strings needs updating.
- **A saved `NavigationPath.codable` representation is tied to module names.** It stores each value's type by its mangled name, which includes the module. A saved path holding a TUI type that has moved to another module stops decoding. This already affected `LocalizationService.Language` and the system format styles, which moved to `TUIStrings`. Types can still move before 1.0, so do not keep such a path across versions.
- **`renderOnce(content:)` is in `TUIApp`.** A tool that uses only it depends on `TUIApp`. With `import TUI` nothing changes.
- **`ASCIIConverter` and the rest of `TUIImage` are not re-exported by `TUIFoundation`.** With `import TUI` you still get them. An app on module products adds `TUIImage` (or `TUIBitmaps`, which re-exports it).
- **MemberImportVisibility is on for TUI's own modules.** Every carved module, `TUIFoundation`, `TUIAppKit` and `TUIFilePanelsAppKit` compile with Swift's `MemberImportVisibility` upcoming feature. It does not apply to your code unless you enable it yourself. If you do, a call to a member that a module adds in an extension needs `import` of the module that declares it in that file. `import TUI` covers every module except `TUIAppKit`, `TUIFilePanelsAppKit` and `TUIMacros`. On an app built from module products, the compiler's fix-it names the module to add, but only when that module is already loaded. One effect you get without turning anything on: because TUI's modules use it, SwiftUICore's extension members no longer reach an app through TUI.
- **The AppKit bridges need `import TUIAppKit`.** `Color(nsColor:)`, `NSColor(_:)` and `Image(nsImage:)` (and compiled asset catalogue reading) are in the separate `TUIAppKit` product, because a module that imports AppKit makes every importing app see SwiftUICore's extension members. Without this split, `FormatStyle.offset(to:)` and similar SwiftUI members were ambiguous in apps importing TUI. The Core Graphics bridges (`Color(cgColor:)`, `Color.Resolved.cgColor`, `Image(_:scale:orientation:label:)`, `Image(decorative:scale:orientation:)`) need only TUI.
- **swift-syntax is resolved for every client**, although only apps that depend on `TUIMacros` build it (see Dependencies).

#### API removed or renamed before the split began (3 to 7 October)

All of these are pre-1.0 changes with no old spelling kept.

- **Window chrome is opt-in.** The status bar no longer draws itself. Place `StatusBar()` in the window's bottom bar, for example `ToolbarItem(placement: .bottomBar) { StatusBar() }`. A bare `WindowGroup` now draws on every row with no key-hint line. The `a` (appearance) key is opt-in too.
- **`.appHeader` is removed.** Use `.navigationTitle`, `.navigationSubtitle` and `.toolbar` items.
- **`Scene.chromeStyle(_:)` and `chromeStyle(appHeader:statusBar:)` are removed.** Use `.windowToolbarStyle(_:)`.
- **`onDragGesture` and `DragGestureEvent` are removed.** Use `DragGesture(minimumDistance: 0)` with `onChanged` and `onEnded`, or `updating`.
- **`onRowActivate` on `List` and `Table` is removed.** Use `primaryAction` of `contextMenu(forSelectionType:menu:primaryAction:)`.
- **`onTapGesture`'s `(x, y)` overload is removed.** Use the closure that takes a `CellPoint`, or one with no argument.
- **TUI's focus-blind key handlers are renamed `onKeyEvent`.** `onKeyPress` is now SwiftUI's: focus-gated, with `KeyPress` and `KeyPress.Result`.
- **TUI's buffer-level modifier protocol is renamed `BufferModifier`.** `ViewModifier` is SwiftUI's, with `body(content:)`.
- **Button styles use SwiftUI's names:** `automatic`, `bordered`, `borderedProminent`, `borderless`, `plain`, `link`, `accessoryBar`, `accessoryBarAction`. TUI's `.default` and `.primary` are gone. `.plain` now means SwiftUI's undecorated plain; the old accent-tinted `.plain` is `.borderless`.
- **`ProgressViewStyle` is SwiftUI's protocol.** A bar's track is set with `trackStyle(_:)`, not `progressViewStyle(_:)`.
- **`TabViewStyle` is a protocol** (`DefaultTabViewStyle`, `CompactTabViewStyle`, `BorderedTabViewStyle`), no longer an enum.
- **`PresentationDetent` is a struct**, no longer an enum.
- **`Table` columns have SwiftUI's shape.** `TableColumn<RowValue, Sort, Content, Label>` with a content closure that builds a view. The String-returning closure columns are gone. `Table` no longer requires `Sendable` rows. A column's alignment is a `TableColumnAlignment`.
- **`Gauge` has SwiftUI's fourth type parameter.** The three-parameter spelling is gone.
- **`onHover` takes its closure as `perform:`.**
- **A popover attaches to any rectangle:** `attachmentAnchor` takes `.rect(...)`, and `PopoverAttachmentRect` is gone.
- **`ScrollGranularity.row` is replaced by `.scrollTargetBehavior(.viewAligned)`.** `.paging` is built in too.
- **Keys are drawn with macOS's symbols** (`⌃ ⌥ ⇧ ⌘`, then the key). `Shortcut.returnKey` is gone, and `Shortcut.enter`, `.home`, `.end`, `.shiftTab` and `.space` have new glyphs or words.
- **`ContextMenuModifier` is no longer public.**
- **The AppKit bridges moved to `TUIAppKit`** (see above).

#### API removed or renamed with and after the split (8 to 23 October)

- **`AppState.shared` is removed**, along with `AppState.setLanguage(_:)` and `currentLanguage`. Every app owns its render state. `DismissAction()` and `LocalizationService.setLanguage(_:)` act on the running app. Still process-wide: the localization service, the notification queue and the default `@AppStorage` store.
- **`Text + Text` is removed** (see the deprecated list below). Interpolate a styled `Text` into another `Text` instead.
- **The row-level drop closure takes its payloads first, then the index:** `([Payload], Int)`. This applies to `ForEach`, `DynamicTableRowContent` and the `Table`-level `dropDestination`. Before it was `(Int, [Payload])`.
- **`@AppStorage` on `UserDefaults` keeps property-list values as themselves.** A `Bool`, `Int`, `Double`, `String`, `Date`, `Data`, `URL`, a raw-representable value, or an optional of these is stored natively, so `UserDefaults.standard.bool(forKey:)` reads what `@AppStorage` wrote. Values written earlier (as JSON) read as absent. There is no migration. `@AppStorage` and `@SceneStorage` take raw-representable values, stored as their raw value. Other `Codable` values are still JSON.
- **`.automatic` picker style's type is `DefaultPickerStyle`**, not `AutomaticPickerStyle`.
- **`.memoized(id:)` returns `_MemoizedView<Self, ID>`**, not `EquatableView<_MemoizedView<Self, ID>>`, and `_MemoizedView` is no longer `Equatable`. The token is the memo's key, not the view's equality, so nothing can mistake it for a re-check of the view. Code that spelled out the old type names the new one; code that used `some View` is unaffected.
- **`TextContentType.url` is `.URL`.** Every `NSTextContentType` is now a `TextContentType`.
- **`Spacer.minLength` is a public `var`** under SwiftUI's name. `SpacerProtocol`'s requirement is `minLength`, not `spacerMinLength`.
- **`UnitCurve.easeInEaseOut`, `WindowGroup.init(content:)` and the `CoordinateSpace`-enum overloads are removed or made internal** (see below).
- **TUI's alert panel view is `AlertPanel`**, no longer `Alert`, whose name read as SwiftUI's retired value type. `.alert(…)` is unchanged; only code that names the view (`Alert(title:message:)`, `Alert.warning(…)`) changes. Its `.warning`, `.error`, `.info` and `.success` presets now start their titles with ⚠️, 🛑, ℹ️ and ✅.
- **`\.terminalFeatures` (`TerminalFeatures`) and `\.keyboardReporting` (`KeyboardReporting`) are no longer public.** `\.terminalCapabilities` answers what they did: `.pointerShapes`, `.progressReports` and `.notifications` for `pointerShapes`, `showsProgress` and `postsNotifications`, and `.disambiguatedKeys`, `.shiftedKeys`, `.keyRepeats`, `.keyReleases`, `.modifierKeys`, `.capsLock` and `.numericPad` for the seven `reports…`/`disambiguatesKeys` properties. Ask `terminal.supports(.keyReleases)` where you read `keyboard.reportsReleases`. A feature can also be undetermined where nobody knows, such as pointer shapes under tmux, where `pointerShapes` read `true` or `false` by what TUI sends. `KeyboardReporting.isEnhanced` has no single replacement: ask about the feature you need, as a terminal can speak the kitty protocol and take only some of it.
- **`URLImageCache.shared` is removed.** Each app has its own URL image cache, which `Image` and `AsyncImage` find through the environment; `.urlImageCache(_:)` hands a subtree a different one (a test's own, say). The cache is bounded now, at `URLImageCache.defaultByteLimit` (64 MiB) unless made with `URLImageCache(byteLimit:)`, the least recently used images going first. `PlatformImageLoader.loadImage(fromURL:cache:…)` takes an optional cache, and caches nothing without one. Outside an app (a one-off render) nothing is cached.
- **`UndoShortcuts.hint(for:on:commandKey:)` takes the `TerminalCapabilities`** (`\.terminalCapabilities`) where it took a `KeyboardReporting`.

#### Behaviour changes you may notice

- A `ForEach` row whose view is `Equatable`, or a view in `.equatable()`, is kept when its parent writes — its own `@State`, or an `@Observable` property its body read — and served if its rebuilt value compares equal and its environment is unchanged, as SwiftUI does; before, every row below the write was drawn again. A long log or chat draws in about three quarters of the time or less. A row's `==` must cover everything the row draws: one that leaves something out now shows the old picture after its parent writes, as it would in SwiftUI. `TUI_VERIFY_RENDER_MEMO=1` finds such a row, and `TUI_OPTION_C=0` turns the re-check off to compare. See "Re-checking Rows After a Parent Writes" in the render cycle article.

- The Violet palette draws success green, warning amber and error red, as every other palette does. Its semantic colours were colour-theory offsets from violet, so success was orange and error lime green.

- Inside GNU screen a copy is sent to the terminal through screen's passthrough and reported "Sent", where it was "Not copied". In a tmux pane whose `allow-passthrough` is on, a copy goes through tmux's passthrough when `set-clipboard` is not `on`, and is reported "Sent". Measured on screen 4.00.03 and tmux 3.7c with `Tools/TerminalProbes/keeper_passthrough_probe.py`.

- The page behind a sheet or an alert stays visible: everything on it keeps its glyphs and attributes, and each colour keeps 40% of its saturation (`FrameBuffer.modalVeilSaturation`) and is then laid at a quarter strength (`FrameBuffer.modalVeilOpacity`) over the palette's overlay colour, where the page used to be redrawn as plain text in two colours, with pictures drawn in text cells, bars and borders left blank. A terminal picture on the page is veiled the same way, pixel by pixel. It is still inert. `.dimmed()` keeps the two-colour look.

- `TextEditor` selects from the keyboard, as `TextField` does: Shift-←/→ a character, Shift-Option-←/→ a word, Shift-↑/↓ a line, Shift-Page Up/Down a page, Shift-Home/End to the document's ends. A plain ← or → with a selection lands at its start or end. It used to select only with the mouse, and Shift-arrows just moved the caret.

- A focused radio group, or a segmented picker, moves its cursor onto a selection made elsewhere: a menu, a shortcut, another control over the same binding. It used to keep its cursor where it was and mark two options, the new selection and the focused one, with the same bullet.

- A view with a `@Bindable` property is made with the model itself, `AccountView(account: account)`, as in SwiftUI. Its memberwise initialiser used to ask for a `Bindable<Account>`.

- On Apple Terminal and Warp a flag emoji is drawn as its country code, `JP` for 🇯🇵, in the same two cells. Terminal 455.1 draws the flag either as a boxed letter (after the repair TUI used to send) or shifted, with the rest of its row one cell left (sent bare), and Warp draws its two letters in boxes. Other terminals draw the flag. `TerminalQuirks.flagsAsCountryCodes` asks for this on a terminal you describe yourself.

- `.textSelection(.enabled)` on one `Table` cell's `Text` makes that cell's text selectable and nothing else: a click on another column's text selects the row again, and a drag there selects nothing. Around the whole table, a drag still selects across a row's columns.

- A drag selection begun inside a bordered container (`.border()`, `Box`, `Card`, `Panel`, `GroupBox`, a dialog, an alert) keeps to the container's interior, leaving out its border, its title and the page around it. A drag begun on the border or outside the container crosses it, and `.textSelectionScope(.pane)` turns the rule off for a subtree. As an experiment, a drag that goes more than 3 rows above or below the interior, or more than 6 columns beside it, widens to what the container sits in (the box around it, an enabled `textSelection`, or the pane) and stays widened until the release.

- A title key that reads the clock — `Button("Ends \(deadline, style: .relative)") {}` — stays live in a button's and a colour picker's title, a text, secure or value field's placeholder (and a `prompt:` `Text`), and a table column's header, as SwiftUI's does: each draws the frame's reading and wakes at the next change. A navigation title, an alert's title and message, help and a tab's title still read it once. `SecureField` and `TextField(_:value:format:)` parse their title key's Markdown, as `TextField` does.

- A number interpolated into a key with no specifier is written in the locale, as SwiftUI writes it: `Text("\(count) rows")` draws `1,234,567 rows` in English, `1.234.567` in German and `1 234 567` (a narrow no-break space) in French, where it drew `1234567`. A floating-point number has at most six fraction digits and no trailing zeros, so `\(3.5)` is `3.5` (`3,5` in German), not SwiftUI's `3.500000`, a deliberate deviation. The locale is `\.locale`: the app's, or the one a subtree sets for its `Text`s. The key is unchanged (`%lld`, `%lf` as SwiftUI spells it), so translations still match. Interpolate a `String` (`\(String(year))`) or use `Text(verbatim:)` for a number that must not be grouped, such as a year or a port.

- A number interpolated with a specifier, `Text("\(price, specifier: "%.2f")")`, follows `\.locale` too: it is written by exactly that conversion (`String(format:locale:)`) in the app's locale, `3.14` in English and `3,14` in German, and again in a subtree's own `\.locale` where its `Text` draws, as a bare number is. It was written once in the process's locale, so under an app-chosen language its numbers could differ from a bare one's. The key keeps the specifier as SwiftUI's does, so translations match.

- `Text("… \(value)")` (and every other key) of a value SwiftUI has no interpolation for — a `Bool`, an `Optional`, an enum, an array, a value typed `Any` — warns, as SwiftUI 26 does: "Localized string interpolation produces an unlocalized, debug description for this type of value." It still writes the description. Interpolate a `String` (`\(String(flag))`, `\(value.name)`) to say what you mean. SwiftUI's typed interpolations are all there: a `Substring`, an `AttributedString` (its looks kept), a `Date`, `URL` or other `ReferenceConvertible` value or an `NSObject` with an optional `formatter:`, and a `TimeDataSource` with `format:` are new. `\(value, specifier:)` takes a number only, as SwiftUI's does, where it took any `CVarArg`.

- On Ghostty, a `List` draws SwiftUI's separators by default: a line a pixel or two thick along the top of each row, drawn with Kitty graphics and taking no row, under `.automatic`, `.inset`, `.bordered`, `.plain` and `.surface` (not `.sidebar` or `.insetGrouped`), and not beside the focused or a selected row. A separator an app asks for with `.listRowSeparator(.visible)` is such a line there too, where it was a rule line of its own. Every other terminal draws lists as before. `.listSeparatorStyle(.line)` keeps the rule line on every terminal, `.listSeparatorStyle(.hairline)` asks for the thin line everywhere (drawn only where the terminal can), and `TUI_HAIRLINES=1` or `0` answers for a terminal TUI has not measured (decisions A-D6L-2). A prototype: the lines are hidden, not dimmed, under a fade or a sheet's backdrop.
- A `Table` stripes every other row by default.
- A sheet's, full-screen cover's or popover's content is built only while it is presented, and a dismissed one loses its `@State`, as in SwiftUI.
- `onChange(of:)` on an optional that starts set no longer fires on its first render.
- Effects run after the walk of a frame, as SwiftUI runs them after its update, and their state shows in the same frame. `onAppear`, `onChange`, `onPreferenceChange`, `onGeometryChange`, a `.task`'s start, the scroll observers and a bound `ScrollPosition`'s report used to run where their view was in the walk, so a view drawn before one showed the old state for a frame beside views after it that showed the new, and an `onChange`'s derived value or a size fed back through a preference reached the screen a frame late. Now they run once the walk is done — geometry first, then preferences, then `onAppear`, then `onChange`, as SwiftUI orders them — and if they wrote state the frame is walked again before it is written, at most twice. The first frame of a page that loads in `onAppear` shows what it loaded. A view drawn after an effect no longer sees what the effect wrote in that same walk, only in the walk made again. A chain of effects longer than two continues a step a frame, as before. An `onChange` or `onPreferenceChange` action that keeps triggering itself runs twice a frame and then not again for that change, and an `onGeometryChange` whose action sends its view back to the size before last is cut off, each with SwiftUI's warning ("… tried to update multiple times per frame.", "Geometry action is cycling between duplicate values.") on the diagnostic channel; such a loop used to run a step a frame until it ended. A trigger-less `PhaseAnimator`'s first frame shows its second phase's content, its animated values starting from the first phase.
- A view in a subtree that geometry correction draws twice in one frame acts once, for the drawing that reaches the screen. This is a reader of a named space, `.scrollView` or `.global` on its first frame, or on a frame something its prediction does not follow moves it. Its `onChange`, `onPreferenceChange`, `onGeometryChange`, `onAppear`, `onDisappear`, `.task`, `onModifierKeysChanged`, `onInteractiveResizeChange`, scroll observers and bound `ScrollPosition` used to act for both drawings. A reader's first frame no longer fires `.onChange(of: proxy.frame(in: …).minY)` from its guess to its answer, as SwiftUI fires nothing, and a view only the guess drew no longer appears.
- `Animation.default` is SwiftUI's: the no-bounce spring at the default pace.
- A `ScrollView`'s `proxy.scrollTo(_:anchor:)` (a row, or a purely horizontal view's column), `ScrollPosition` request (a row, an edge or an offset, either axis) or written `anchorPosition` edge made inside `withAnimation` glides to its target a line or column at a time along the animation's curve, as SwiftUI's animates, where it jumped, and `onScrollPhaseChange` reports `.animating` until it lands. `withAnimation`'s completion fires when it lands. The wheel, a key or a focus move stops it where it is. A `List`'s or a `Table`'s glides too, a row at a time, leaving the cursor and the selection, and both now report their scroll phases to `onScrollPhaseChange`. Under reduce motion it still jumps.
- `.scrollKeyboardAnimation(_:)` (TUI-specific) makes a `ScrollView`'s Page Up/Down, Home and End glide to where they land — the page a scroll target behaviour picks, an edge, the tail — rather than jump, and a `List`'s or a `Table`'s glide the rows to where the cursor's reveal puts them, the cursor moving at once; a key pressed during the glide counts from its target. Without it the keys jump, as before.
- Controls' faces — bordered buttons, pop-up pickers, combo boxes, text fields' caps — follow a new `ControlStyle` (`.controlStyle(_:)`), apart from the border's `Appearance`: filled by default (`.automatic`), or `.lines` in the border's own lines, `.braille(thickness:)` or `.blank`. Under `.automatic` the `.braille` and `.blank` appearances still set the controls' look too. For a week from 15 October the face followed the appearance, lines by default; `.controlStyle(.lines)` brings that look back.
- Segmented and palette pickers, and a compact `TabView`'s chips (the colour picker's mode tabs among them), end in the caps a button has in the control style and `buttonBorderShape` in force. By default nothing changes; under `.controlStyle(.lines)` a segmented picker is `( S │ M │ L )` with no field, and the selected tab's chip `( title )`. A focused strip's selected chip breathes those caps with its title, as a lines button breathes its caps with its label.
- A `.switch` toggle under `.controlStyle(.lines)` is a knob between the caps of the `buttonBorderShape` in force, four cells in every shape: `(○ )` off and `( ●)` on in a capsule (the default shape), `⦗● ⦘` / `⦗ ●⦘` in a rounded rectangle, `│● │` / `│ ●│` with square corners, and between a `.brackets` pair's glyphs. The caps breathe the accent while it holds the focus. Under Braille it takes the shape's dotted ends, under `.blank` the knob alone (`○ ` / ` ●`). Filled controls, the default, keep the coloured track, and the `.ascii` character set keeps `[o ]` everywhere.
- A `.bordered` (or `.grouped`) `TabView` draws its folder tabs and content box in the border of the `Appearance` in force — square under `.line`, heavy, double, Braille dots, blocks or nothing — where it was always rounded lines.
- A `ControlGroup` draws its buttons as one segmented face, as a segmented picker is drawn: caps only at the two ends and a rule between buttons, `▐ − │ 100% │ + ▌`, where each button drew its own caps (`▐ − ▌▐ 100% ▌▐ + ▌`). Its buttons stay one row at `.large` and `.extraLarge`, as a segmented picker does.
- A `List` row's `.standard` (and `.increased`) badge sits in a capsule, as macOS draws it: on a tinted field a cell wider each side, ` 12 `, or between the control family's caps under `.controlStyle(.lines)`, `(12)`. A badged row's badge is two cells wider, so a list that hugs its rows is two cells wider for it; a `.decreased` badge stays plain text.
- A `.buttonBorderShape(.underline)` button drawn in lines keeps its underline at `.controlSize(.mini)`, where it was the bare label: the line takes no cell.
- A large or extra-large filled `.circle` button is a disc rather than a plus: its label's row is the one-row circle's `▐ + ▌`, and the rows above and below are cut on the diagonal with `◢ ◣` / `◥ ◤` (Ghostty, iTerm2), `▄`/`▀` half blocks (Warp), or whole cells (Apple Terminal).
- On Apple Terminal, a large or extra-large rounded or capsule button keeps its shape: its face leaves out the corner cells the curve only nicks, where it was drawn as the same square block as a square button.
- A branch an `if`/`else` flips to, a `switch` case or a `ForEach` row that a change puts in under an animation fades in. One taken out goes at once, unless it carries a transition of its own.
- `.contentTransition(_:)` is read by each `Text` and image inside it, as in SwiftUI, rather than dissolving everything it wraps: an inner `.contentTransition(.identity)` now exempts its part, and a shape or colour under the modifier animates its own change instead of dissolving.
- On terminals whose Block Elements fill the line (all but Apple Terminal), a gradient or mesh that changes down a column draws each blank cell it fills as two samples, `▄` in the bottom half's colour over the top half's: gradient views, `.background(gradient)` behind blank cells and rectangle-family gradient fills. Copying such a region gives `▄` rather than spaces.
- A material (and glass) frosts what is behind it: the glyphs beneath are dropped and each cell takes the average of a box of its neighbours' colours before the tint is laid over, so text behind a material reads as a wash of colour rather than as letters. A thicker material blurs a larger box, as SwiftUI's do: 3 × 1 cells for `.ultraThinMaterial` up to 11 × 5 for `.ultraThickMaterial`; glass blurs as a material one thickness thinner. `.materialFrost(_:)` (TUI-specific) sets the box for a subtree: `.radius(columns:rows:)`, or `.none` for the glyphs dropped and nothing blurred. Over the page alone a material looks as before.
- `\.accessibilityReduceTransparency`, `\.accessibilityDifferentiateWithoutColor` and `\.colorSchemeContrast` follow the user: `TUI_REDUCE_TRANSPARENCY=1`, `TUI_DIFFERENTIATE_WITHOUT_COLOR=1`, `TUI_INCREASE_CONTRAST=1`, or the macOS (or GNOME high-contrast) setting where TUI is sure the session is local, as reduce motion does. Under reduced transparency materials and glass are opaque. `\.colorSchemeContrast` is no longer always `.standard`.
- A paste of any size now arrives whole. The earlier 16 MiB limit is gone.
- A popover attached with `.rect(.rect(_:))` that is wider than its rectangle starts where the rectangle starts, as a menu and a tooltip do, rather than centring on it: a link's destination popover inside a `Text` now lines up with the link as a `Link`'s does.
- A link inside a `Text` (from Markdown or an attributed string) is a control, as a `Link` is: Tab reaches it, Return or a click opens it and shows its destination in a popover, and Shift+F10 or a right-click opens `Link`'s menu. A page with inline links gains a Tab stop per link. Not where `.linkDisplay` writes the URL out, in a disabled subtree, or in a list's row.
- The status bar draws an item's one-letter key as a macOS menu draws it: `Q quit` for `"q"`, `⇧N` for an item on `"N"`, matching `⌃Z undo` beside it. The item's string still binds the key. `.statusBarKeySpelling(.asTyped)` draws the strings as typed, as before.
- ⌃Y redoes, the one redo key every terminal sends, except in a focused text field or editor, where it is still the yank. The status bar's and the menu bar's redo hint names ⌃Y, and another redo key while a text control has the focus.
- While a `List`, a `Table`, an open `Picker` drop-down or an open menu has the keyboard, its type select takes every bare character, the first of a prefix included. TUI's `q`, `t`, `a` and help key, an app's bare `.keyboardShortcut`, a menu row's bare key equivalent and a status-bar item's bare key no longer fire there, and the status bar leaves those items out meanwhile. Before, the first character of a prefix gave way to such a binding. A modified key, an F-key or the menu bar still reaches its command.
- Under the kitty keyboard protocol, a ⌘ chord the terminal lets through (kitty and Ghostty pass some) reaches `onKeyPress` with `.command` in its modifiers, where it was dropped. It reaches nothing that matches a bare key, so ⌘K types nothing into a field. A `.keyboardShortcut` written with ⌘ still fires on its `.commandKey(_:)` stand-in (Control by default), and on a real ⌘ as well only under the new `.keyboardShortcutsMatchCommand()`. `KeyEvent` has a `command` field.
- A hierarchical `Table(_:children:)` keeps its outline from frame to frame while its rows (the same array) and its open branches are the same, so a frame costs what a flat table's does: 1.66 ms where it took 41.8 ms at 20,000 rows (debug build). A file panel's list view is now an outline for a folder of any size, where one of more than 5,000 items was drawn flat.
- A paused drag activates a spring-loaded control after the user's spring-loading delay (System Settings ▸ Accessibility ▸ Pointer Control) where TUI is sure the user is at the machine the app runs on, and after half a second elsewhere, as before. `TUI_SPRING_LOADING_DELAY=0.3` (seconds) sets it for a run, and the new `.springLoadingDelay(_:)` sets it for a subtree. A `ColorPicker`'s well no longer spring-loads under `.springLoadingBehavior(.enabled)`, as SwiftUI's does not.
- A spring-loaded control a paused drag rests on draws as hovered while the pause runs, and as pressed for a tenth of a second as it fires, as macOS highlights it. A button style of your own sees it as `isHovered` and `isPressed`.
- A debug build stops (a `SoftTrap`) where a `Picker` leaves out a member of its content with no tag of the selection's type, and where an alert or confirmation dialog leaves out a `TextField`, `SecureField` or `Toggle` among its actions. SwiftUI shows both, so they were silent gaps. A release build reports each once and draws as before. Tag a picker's items with values of the selection's type.
- A list section's `.sectionActions` show only while the section is in use: the focused list's cursor is on one of its rows, the focus is on one of the actions, or the pointer is over the section. They were always shown, each a Tab stop. Tab from the list reaches the actions of the section the cursor is in. Hidden, their cells stay blank, so nothing moves as they come and go.
- An empty `List`'s or `Table`'s placeholder ("No items", or `.listEmptyPlaceholder(_:)`'s) is in the secondary ink and starts where a row's text would, no longer flush against the border.
- A `Stepper` with bounds reserves the width of the wider of its two ends, so ▶ no longer moves as the value gains a digit; a narrower value stands at the trailing edge. `.stepperValueWidth(_:)` sets the reservation (`0` for none).
- `Color.red`, `.blue` and the other named colours (all but `.white`, `.black` and TUI's `.magenta`) take Apple's dark values where they are drawn under a dark colour scheme, as SwiftUI's do: on a dark palette, and in a subtree pinned with `.environment(\.colorScheme, .dark)`. Most palettes are dark, so `.red` draws `#FF453A` there, not `#FF3B30`. What a body computes from one (`rgbComponents`, `opacity(_:over:)`, `mix(with:by:)`) still uses the light value. A named colour no longer equals the RGB it was (`Color.red != Color.hex(0xFF3B30)`), and it describes itself by name (`"red"`).
- A colour from an asset catalogue (`Color(_:bundle:)`, compiled catalogues included) and a dynamic `NSColor` (`Color(nsColor:)`) draw their light or dark variant by the colour scheme where they are drawn, as SwiftUI's do: the palette's, or a `.environment(\.colorScheme, …)` pin's, even when the colour was made outside the pinned subtree. Before, the variant was chosen when the colour was made, by the default palette's scheme. A body that measures one reads its light variant. Two variants that differ in opacity, or that are not plain colours, are still chosen when the colour is made, as is every new pair once a process has made 65,536 different ones. Such a colour no longer equals either variant's RGB, and describes itself by both (`"#CC6633FF light, #1080FFFF dark"`).

#### Since 23 October

What landed from 23 to 29 October that an existing app may notice, beyond the rename at the top and the lists above. Nothing here keeps an old spelling.

API, environment and requirements:

- **An app with no terminal says so and exits.** With stdout or stdin not a terminal, or `TERM=dumb`, `App.main()` used to enter the alternate screen anyway and sit there, writing escape codes down the pipe. It now prints one line to stderr and exits with status 1. An app with an alternate way of running implements `App.runWithoutTerminal(_:)`, which is told what is missing (`NoTerminal`) and returns an exit status, or `.drawOnControllingTerminal` to draw on `/dev/tty` while its pipes stay reachable, as `fzf` does.
- **`renderOnce` draws where the cursor is.** It no longer moves the cursor to the top of the screen and draws over what was there: it draws from the current line, gives the view the height it asks for rather than the screen's, and ends with a newline, so what the program prints next follows on. When stdout isn't a terminal it writes plain text. `renderOnce(output: .escapeSequences)`, `TUI_FORCE_ESCAPES` and `FORCE_COLOR` keep the escape sequences down a pipe, and `NO_COLOR` leaves the colours out (`RenderOnceOutput`).
- **⌃\\ asks before it quits.** It raised `SIGQUIT` at once. Where nothing of the app's takes it, it now puts up a dialog (Return or Escape stays; Tab then Return quits). Pressing it again while it's up quits at once, and a ⌃\\ at an app that doesn't read it within two seconds quits too, with the terminal restored; `kill -QUIT` never asks. While it is to ask, the app has the key rather than the driver, so the first ⌃\\ leaves the app's child processes alone and pasted text holding 0x1C no longer quits. `Scene.quitConfirmation(.whenWarned)` gives the key back, `.always` has ⌃Q and the menu's Quit ask too, and `View.quitWarning(_:isActive:)` has every quit ask and name what would be lost. `TUIApp` now links `TUIPresentation` for the alert.
- **Control-Q quits, not `q`.** A bare `q` was typed by a focused text field and searched for by a focused list, so an app could have no way to quit from where it opened. The status bar and the menu bar's Quit now say ⌃Q. For an app with nothing to type into, `statusBar.quitShortcut = .q` gives the old key back; `QuitShortcut.q` is still there. Raw mode already had flow control off, so ⌃Q reaches the app rather than being taken for XON.
- **`TUI_POINTER_SHAPES` takes `1`, `0` or `apps`.** `1` and `0` turn pointer shapes on or off whatever TUI detected; `apps` turns them on and keeps them to the app's own `pointerStyle(_:)`. The value `all` is gone: TUI's own shapes (the I-beam over a text field, the hand over a link, the resize arrows over dividers, column edges, grips and a sheet's grabber) are now on wherever the terminal takes shapes, where they were on only for iTerm2 or under `all`. `TerminalClient.pointerShapeSupport` still overrides the variable.
- **The pointing hand is over links only, by default.** A button no longer turns the pointer into a hand; a `Link`, a link inside a `Text` and a `.link`-styled button do, as on a Mac. `.pointingHandCursor(over: .everythingClickable)` gives the hand to everything that acts on a click, as a web page does (`PointingHandCursorScope`, `\.pointingHandCursorScope`). A view's own `pointerStyle(_:)` wins over either.
- **`import TUI` re-exports Foundation** (see "The umbrella still works").
- **The framework's working parts are no longer public.** 78 types and functions that only TUI's own modules use are now `package`, along with what names them: the stores (`StateStorage`, `RenderCache`, `AppState` and the like), the `*Modifier` wrappers behind the modifiers (`PaddingModifier`, `OverlayModifier`), the child helpers (`renderChild`, `measureChild`), `.onRenderPass`, `String.hyperlinked(to:)` and `TerminalQuirks.widthTraits`. The modifiers themselves are unchanged, and a custom view has every route in the Custom Views article: composition, `ViewModifier`, `BufferModifier` and `Renderable`, with `FrameBuffer` and `RenderContext`.
- **On macOS, TUI supports only an SDK from Xcode 26 or Command Line Tools 26 or later.** The macOS 15 SDKs (Command Line Tools 16.x) carry Swift 6.1's interfaces and are neither built nor tested.
- **The app's language is its scene's root `\.locale`.** `WindowGroup { … }.environment(\.locale, Locale(identifier: "de"))` now also sets the language of the words TUI reads where no view is drawing: the bars' labels, undo titles, clipboard notes. A scene that sets no locale is unchanged.
- **More words follow a subtree's `\.locale`**, where they were read once in the app's language: `Text(localized:)` of TUI's own keys, a `Button` titled from a key (TUI's own buttons among them), an `AlertPanel`'s title and message and its presets' titles, and the key-titled `.alert`, `.confirmationDialog` and `.dismissalConfirmationDialog` forms.

Keys:

- **Behind a sheet, an alert or another modal, only the modal's own keyboard shortcuts and status-bar items work**, as behind macOS's app-modal alert. A shortcut or status-bar item declared outside the view that presents the sheet used to show and fire behind it. The menu bar is drawn faint, as a disabled control is, while a modal holds the input.
- **Ctrl-U kills from the caret to the start of its line, and Ctrl-W kills the word before the caret**, in every text control, as readline does: each one undo step, kept for Ctrl-Y (a `SecureField` keeps nothing). Ctrl-U used to erase a field's whole text and do nothing in a `TextEditor`. An app's ⌘U or ⌘W, which arrive as these chords under `.commandKey(.control)`, comes first, as every Control or Command shortcut does over a text control's editing chord (select-all and the editor's Ctrl-A and Ctrl-E included); only the clipboard and undo chords stay the control's.
- **Ctrl-J (LF) is a key of its own.** A vertical `TextField` inserts a newline for it; where nothing takes it, it acts as Return, as before. Automation that sends LF to mean Return should send CR.
- **Under the kitty keyboard protocol, Ctrl-Return goes to the app first** (its key handlers and shortcuts, so an app's ⌘↩ fires under `.commandKey(.control)`), then opens a context menu on the focused view, then makes a vertical `TextField` insert a line break, and only then acts as Return. It used to be Return.
- **F10 enters the menu bar's bar mode.** It lights the first title and opens nothing, with every title's letter underlined; ↓, Return, Space or a title's letter opens a menu. F10 then ↓ is what F10 alone used to do.
- **View ▸ Customize Toolbar… is in the menu bar wherever the page shows a customizable toolbar** (`toolbar(id:)`), so F10, then View, reaches the customization panel from the keyboard. It needed `ToolbarCommands`, as on macOS; an app with a menu bar and a customizable toolbar but no `ToolbarCommands` now has a View menu holding it. With `ToolbarCommands` the menu still has one. A scene with no `commands` has no menu bar: the bar's right-click, or Shift+F10 on one of its items, opens it there.
- **Each menu-bar title has an Option letter of its own**: in bar order, the first letter of its title that no earlier title has taken, so two titles that start alike (File and Format) no longer share one. While a text control has the focus, a title whose letter the control edits with (Option-F, Option-B) takes its next free letter. Where the terminal reports Option held on its own, the letters are underlined while it is held.
- **Find (⌃F under the default command key) moves the focus to a `.searchable` view's field**, as ⌘F does in a Mac window. An app's own shortcut on those keys wins, and so do a text field's ⌃F (forward a character) and a `TextEditor`'s own find.
- **Where the terminal composes a character with Option** (Ghostty's default, under the kitty keyboard protocol: ⌥F arrives as `ƒ`), **the Option chord on its key still fires** when nothing takes the character: a menu's letter, ⌥? for every tooltip, ⌥⇧- for redo, an app's ⌥ shortcut. A focused text field still types the character, and a list's or a menu's type select leaves it to the chord.
- **Built-in controls register undo steps.** A person's change to a `Toggle`, a menu, segmented or radio `Picker`, a `Slider`, a `Stepper`, a `DatePicker` (its fields and its graphical calendar), a `ColorPicker`'s grids or a tone curve editor's stops is undone by ⌃Z and Edit ▸ Undo; a run of changes to a continuous control is one step. The app's own writes are not steps. SwiftUI's controls register nothing.

Pointer, drag and drop:

- **A control's action is drawn before the next input event is read.** A `.disabled(isSaving)` an action writes now stops a second press that arrived with the first, by keyboard, mouse or shortcut, as in SwiftUI, where a burst used to run the action twice. An alert or menu an action opens is what the next key reaches, too. Typing, arrow keys, scrolling, drags and pastes still batch. A key held on a button that stays enabled gets a frame per press, up to a quarter of a second behind.
- **A press released off a control acts on nothing.** A `Button`, a `Toggle`, a radio or segmented option, a link in a `Text`, a tab, a swatch, a status-bar item or a calendar day used to act on a release anywhere after its press. Now, as on macOS, a release elsewhere cancels it, and a button's pressed look follows the pointer off and back. A gesture attached to the control hears the press once the control's click fails.
- **Dragging a selected row of a `List` or `Table` with a `Set` selection carries every selected row**, in the container's order, as Finder does, and each destination is handed all the payloads in one call: a destination that expected one value per drop can now get several. Shift held as the drag starts extends the selection to the row first. From the keyboard, Ctrl-R on a selected row carries the whole selection too; Copy takes the focused row alone.
- **The preview of a selection's drag shows the grabbed row and a "+N more" line for the rest.** The new `.dragPreviewRowLimit(_:)`, on the `List` or `Table` or a view around it, lets up to that many of the carried rows ride the pointer, stacked in the container's order with the grabbed row still under the pointer, before the rest are counted; `nil` shows every row, and a limit below 1 is taken as 1.
- **Ctrl-R on a `.draggable` row of a `List` or `Table`, or on a `.draggable` tab, carries it from the keyboard** (it used to need the mouse), and Copy copies its payload. On such a row Ctrl-R always carries, as the pointer's drag does; where the list also accepts its own rows, the list is one of the carry's places, so Up and Down choose the landing slot and Return reorders. Rows without a drag keep the old keyboard move.
- **`.tabViewSearchActivation(.searchTabSelection)` goes back to the previous tab only when the search is dismissed**: when the field gives up the focus with nothing in it, as `dismissSearch` and Escape leave it. Tab from a field that holds a query into the search tab's results keeps the tab.
- **A drop's operation follows macOS's three-party model.** The source states what it allows with the new `dragConfiguration(_:)` (a copy by default; a list's, table's or sidebar's reorder is a move); a drop into the container the drag came from proposes a move and anywhere else a copy; the modifier the terminal delivers flips the two. A plain `dropDestination` now shows the + badge for a copy.

Drawing and layout:

- **A faint level is never invisible.** At 16 colours, a `foregroundStyle`'s `.secondary` and fainter levels that would land on their own background, or at full strength, are drawn in their own colour with SGR 2 (faint); at 256 colours such an ink steps toward full strength until the palette has an entry apart from the background. At 16 colours `.tertiary` and below drew as the page and `.secondary` as `.primary`. Truecolour is unchanged, and a layer's `.opacity` still fades to nothing.
- **A list separator with no `listRowSeparatorTint(_:edges:)` is fainter**: the border's ink faded half way into the page, where it was the border's own.
- **`.redacted(reason: .privacy)` masks text with ●**, as a `SecureField` masks its text, so hidden data no longer looks like a loading placeholder (░). Where both reasons apply, the placeholder wins. SwiftUI draws both alike.
- **A `.graphical` `DatePicker` draws the weekend in the secondary text colour**, its days taken from the environment's calendar (Friday and Saturday in Saudi Arabia). `.datePickerDistinguishesWeekends(false)` turns it off, and `.datePickerDistinguishesPastDays()` draws the days before today faint.
- **A column shares an overfull height by flexibility**, as SwiftUI's does: children of one layout priority each give up room, where the leading ones took their height and the trailing ones were cut. A `Table` reports a flexible height, as a `List` does, so it takes the share it is offered and scrolls the rest; one whose rows fit still hugs them.
- **A column that has room for all its children keeps each at its natural height**, and only views that grow share what is left; the flexibility rule above applies only once the column is overfull. A column beside a view that fills any height was shrunk, and a `ScrollView`'s content cut (the Example's Colors page lost its mesh gradient).
- **Lengths an app states are held to 65,536 cells.** A frame, padding, offset, position, spacing, a `Spacer`'s minimum, a grid's or a table's widths past that, and NaN or infinite values, used to trap or build strings of billions of blanks. A negative stack `spacing` overlaps the neighbour, as SwiftUI's does.
- **A negative `padding` works as SwiftUI's does.** The view reports a frame that many cells smaller on each edge (never below zero), its content is offered that many more and is drawn at its full size past the frame: over the views before it, under the views after it. `Text("Hello").padding(.horizontal, -1)` is three columns wide and draws all five letters. A negative inset used to trap.
- **A bare `Button` in a `Form` goes where SwiftUI's does**: in a `.columns` form's control column, and at a `.grouped` form's row's leading edge. It stood at the trailing edge; `.formRowAlignment(.trailing)` gives that look.
- **A background on a bordered view reaches the border's line.** `.background(m).border()` left the blank cell TUI keeps inside the line unfilled; `.backgroundStopsAtContent()` keeps it clear.
- **A focus section's breathing ● is drawn only by a border around the whole section**, no longer by each bordered view inside one.
- **A dialog's footer is laid out across its whole inner width**, so an alert's buttons stand as far from the right border as from the left, where they stood two cells further in. The "Do not ask again" toggle is centred over the buttons, with a blank row between.
- **A circular `Gauge` centres its value in the ring** (`│ 7% │`), by its figures: a sign or a unit hangs outside them, and where the range goes below zero a minus's cell is kept so the figures stand still. Its label is centred under the ring. The value was right-aligned.
- **A stated `.tint` colours gauges and progress bars**, and `.tint` takes any `ShapeStyle`: a gradient runs along a bar or around a ring. With no tint they keep their quiet secondary ink.
- **Glass and materials stay frosted in an inactive window**, their surface half way to opaque, where they went flat, and a tinted glass greys toward a quarter of its colour rather than brightening.
- **Under a scroll target behaviour, an "N more" line with nothing past it is blank** rather than "▲ 0 more". Under `.paging`, the pair comes and goes over content that does not size itself against the scroll view, so each page starts on the line after the last one read; over a `scrollTargetLayout` whose rows are taller than a line, a page never cuts a row, but leaves it blank and starts the next page on it.
- **A later view shows an unclipped scroll view's overflow through the blank cells between its words**, as SwiftUI shows it between its glyphs, where it hid the overflow from its first painted cell to its last on each line.
- **A `Tab` whose label is a view of its own draws that view whole in its chip**, several rows tall if it is, where only its first line was taken as text.
- **`TrackStyle.threeSegment`'s background pattern stays put as the fill grows**, laid from the track's first cell, where it was laid again from wherever the fill ended.

Pictures:

- **`Image(.file(path))` of an animated file plays by itself.** GIF everywhere (ImageIO on Apple platforms, the bundled stb_image elsewhere), APNG and animated WebP on Apple platforms only, with the file's delays and loop count. On the animation clock, so nothing wakes for a picture that is not drawn or has finished, or for a page with none. Reduce Motion shows the first frame. An animated file that holds more than 64 MiB of frames has them scaled down to fit, and past 1,024 frames some are dropped. No new API. A URL's picture, or a format with no decoder on the platform, shows its first frame as before.
- **A picture keeps its own aspect at every size.** `.scaledToFit()`, and a picture at its natural size, letterbox within the cell box (up to half a cell shows the page); `.scaledToFill()` crops to the box; `.resizable()` with no aspect ratio stretches. Each used to be stretched slightly to the box's aspect, differently at each size.
- **A picture file of up to 256 KB draws on the frame that first shows it**, as SwiftUI's `Image` of a local file does, where it showed a placeholder while a task decoded it. `.imageSynchronousDecodeLimit(_:)` sets the size in bytes, `0` for every file in a task. A picture another view has already shown draws at once, whatever the size of its file.
- **Braille in colour paints each cell's background** in the average of its unlit pixels, so tones below the threshold no longer vanish into the page. Shape-aware glyphs ink a cell by its brightness, as the character ramps do, where a white ground drew black.

Fixes an app may have worked around:

- **A long list of pictures holds at most the image cache's bytes of pixels** (64 MiB unless `.urlImageCache(_:)` gives another). A row keeps its state for as long as its list lives, as in SwiftUI, and that state used to hold the row's decoded picture, so every picture a list had ever drawn stayed in memory. A picture loaded from a file or a URL is now kept by the cache, and its view holds it only while drawn. One drawn again after the cache let it go loads again: a small file on that frame, as before; a larger file or a URL in a task, the row showing what it last drew meanwhile (its placeholder, where the terminal drew it as a picture). A picture made from pixels in memory is kept by its view, as before.
- **The app's own image cache can be given another bound without code**: `TUI_IMAGE_CACHE_SIZE=256M` (bytes, or KiB, MiB or GiB with a `K`, `M` or `G` suffix; `0` keeps nothing). In code, an app hands its views a cache of its own with `.urlImageCache(_:)`, made once (a `let` on the `App`, or `@State`), not in a `body`, which would make a new, empty one on each evaluation.
- **An app that calls `exit()` hands the terminal back** (raw mode, the alternate screen, the cursor, mouse reporting, the kitty keyboard flags) as a quit does; so does a stack overflow in a frame, and resuming after an external `SIGSTOP` takes the terminal back as resuming after ⌃Z does. Quitting puts xterm's `modifyCursorKeys` back to its initial value, where it set it to 0.
- **`TimelineView(.periodic(from:by:))` with an interval of 0, below 0 or NaN gives one entry** instead of stopping the app, and one too long or too short for the date to move ends its entries instead of hanging. Animations, timelines and notifications take any duration without trapping.
- **A picture file that is a named pipe or a device is refused** rather than opened, which froze the app waiting for a writer.
- **An `Image` whose source changes is laid out at the new picture's size on that frame.** A viewer stepping from one photo to the next drew each new one in the last one's box for a frame, then snapped it to its own.
- **An `.offset` view that comes or goes with a transition moves and stays in place as it should.** Under `.move` or `.offset` its picture stood still where it ended and a blank box of its size was drawn where it was laid out; under a fade, an overlay that centred it drew it half its width aside until the fade was over (a toast `.offset` into place and moved in from the bottom jumped sideways as it settled).
- **A focused toggle's breathing no longer flickers in Ghostty**: every frame that draws a row now holds the terminal's display (synchronized output), one row included.
- **A `@FocusState` set before its control has registered focuses the control when it does**: `.onAppear { field = .email }` on a view that has just appeared takes the focus from another control, as in SwiftUI. The write was dropped.
- **A write made outside an event (a timer, a `Task`, a network reply) asks for a frame** when what it changed was read only by a top-level control's `Binding`, a custom style's `makeBody` or the app's body. The control used to show the old value until something else drew.
- **Where several views hold one object, an `@Environment` the object reads in a closure** (a key or mouse handler, a gesture's callback, a `.task`) is the environment of the view the closure runs for, where it was the first holder's: a sheet sharing its page's object now dismisses the sheet. Timers, detached tasks and hover handlers still read the first holder's.
- **A URL image answered with a failure status fails as a download.** A 404's page used to go to the decoder, which reported `ImageLoadError.decodingFailed`; it is now `.downloadFailed`, naming the status, even when the response's body is a picture.

#### Since 29 October

- **A page nested too deeply to draw is no longer blank, and no longer crashes.** Past the depth the stack allows (about 800 levels of `VStack` in a release build, 700 through `AnyView`), the part of the page above draws as usual, and "⋯ nested too deeply to draw" takes the place of what is below, or the last row of the screen where that place has no room. It is reported once, through `TUI_DIAGNOSTICS_FILE` or stderr, with why and what to do. A view below the limit keeps its `@State`, and comes back when the page is shallower. Before this, a page that held nothing above the limit drew nothing, with no message, and a recursive view with no container in it (a `body` that is itself with a modifier, a `Group`, an `if`, a `Section`, a `GeometryReader`, a `NavigationStack`) ran off the end of the stack and crashed. A recursive view that holds itself more than once, or a `ForEach` in itself, no longer hangs on its first frame. The Troubleshooting article has what to do about it.
- **`List(data, selection:)` takes a selection of any type**, as SwiftUI's does, in every form: `Identifiable` data, an `id:` key path, a `Range<Int>`, a tree (`children:`), a binding to a tree or to editable data (`editActions:`), and the non-optional selection. A row's value for the selection is its `.tag(_:)` or link value, else its element's `id` where that is of the selection's type. One source change: `List(items, selection: nil) { … }` can no longer infer a selection type from the `id`, as in SwiftUI; write `selection: nil as Binding<MyID?>?`, or leave the argument out.
- **A `NavigationLink(value:)` names its row in a selecting `List`**, so `List(categories, selection: $category) { NavigationLink($0.name, value: $0) }` selects with Return, Space or a click and a `NavigationSplitView`'s next column switches. Such a row draws the link as its label, with no button and no Tab stop. In a `NavigationStack`, selecting the row also follows its link.
- **Return or Space on a `List`'s cursor follows a `NavigationLink` in that row**, in a list with no selection, with no Tab to the link first. The link keeps its button there, and Tab still reaches it.
- **A row of a windowed `List` whose tag or link value says nothing for the selection, after row 0 said something, no longer stops the app.** It draws and selects nothing.
- **The geometry of a custom `Layout` fits together.** `LayoutSubview.place(at:anchor:proposal:)` takes a `CellPoint`, such as `bounds.origin`, beside its tuple; `CellSize.zero` and `ViewSize.zero` exist; `ProposedSize(_:)` makes a proposal of a `ViewSize` or a `CellSize`, and `ProposedViewSize` is SwiftUI's name for `ProposedSize`. `ViewSize` and `CellSize` stay apart, since a `ViewSize` also says which axes can grow, and `CellSize(_:)` and `ViewSize(_:)` convert.
- **`.overlay(.red)` takes a style with no `in:`**, as `.background(.red)` does, filling the view's frame.
- **`.refreshable`'s action inherits the actor it is written on**, as SwiftUI's does. Written in a `body` it can write `@State`, and it runs on the main actor, so long synchronous work belongs in a `Task` of its own or a `nonisolated` function.
- **`onAppear(perform:)` and `onDisappear(perform:)` take an optional closure, defaulting to none**, as SwiftUI's do.
- **No synchronized output under tmux.** tmux answers the end of a held frame by repainting the whole pane at its client, so one changed cell cost 6,198 bytes against 38, and an idle Example 153 KB/s against 2 KB/s. `TUI_SYNCHRONIZED_OUTPUT=1` asks for it anyway.
- **F1 lists the keyboard shortcuts in force.** A sheet, with no code from you: the page's `.keyboardShortcut`s, the menu bar's commands, the status bar's items and TUI's own keys, by section, keyboard-scrollable, taken down by Escape or F1, and also at Help ▸ Keyboard Shortcuts. Anything of the app's on F1 comes first, and `Scene.keyboardShortcutOverlayDisabled()` turns it off. On a default Mac keyboard the key is fn-F1.
- **A `KeyboardShortcut` can name a function key,** by AppKit's scalars, as SwiftUI source does: `KeyEquivalent("\u{F704}")` is F1, up to F20. They fired nothing before.
- **xterm.js is a known host.** Named by `TERM_PROGRAM=xterm.js` or its Device Attributes, it gets OSC 8 hyperlinks, its underline styles, and CUF repairs for what it advances short of TUI's widths (SF Symbols, bare pictographs, a lone regional indicator, emoji of Unicode 15 and later, spacing vowel signs).
- **A running app reads `NO_COLOR`, `FORCE_COLOR`, `CLICOLOR_FORCE` and `CLICOLOR`.** `ColorDepth.detect` reads them before `TERM` and `COLORTERM`, and `renderOnce` now goes by the same reading. `NO_COLOR` keeps bold, underline and italics, and beats `FORCE_COLOR`. `FORCE_COLOR=1`, `2` or `3` asks for at least 16, 256 or millions of colours, and never lowers what the terminal has. Set `ColorDepth.current` to overrule the environment, as for a `--color=always` flag; `ColorDepth.cap` still only lowers. A full app still needs a terminal whatever `FORCE_COLOR` says. The Terminal Support article has the whole table.
- **`renderOnce` changes that follow.** `NO_COLOR` with `FORCE_COLOR` down a pipe is plain text: `FORCE_COLOR` used to win. `FORCE_COLOR=1` down a pipe is 16 colours. `TUI_FORCE_ESCAPES=1` no longer brings back the colours `NO_COLOR` took away.
- **Controls show their state without colour.** At `.noColor`, however it was reached, most controls showed neither the focus nor being disabled. The focus is now reverse video, on a button's or tab's face, a toggle's or radio option's label, a stepper, a slider's arrows or a link. A disabled control is faint. A text field's caret, its selection and its prompt each show, where the first two were invisible and the prompt read as typed text. A scroll bar's thumb is a shade glyph, where it was invisible, and it turns solid with the focus. A radio option's ● no longer also means focus there, which made it look selected. An indeterminate `ProgressView` in `.pulse` or `.gradient` sweeps, where it stood still. A gradient drawn as a picture goes back to cells at `.noColor`, and a list's hairlines go. An `Image` keeps its pixels.
- **Every environment variable is on one page, with one rule for which setting wins.** What your code states wins over a variable, and a variable wins over what TUI would otherwise do. The exception is what someone asks for so that they can use the program at all, which code can add to and not take away, and an app's ordinary drawing doesn't count as choosing: `.foregroundStyle(.red)` stays colourless under `NO_COLOR`, whereas assigning `ColorDepth.current` overrides it. See the Environment Variables article, which also lists what code can do about each one.
- **`TERM=` counts as unset**, as every other variable's empty value does: millions of colours, where it was 16.
- **Only `TUI_RECORD_SNAPSHOTS=1` records snapshots.** `0` and an empty value used to record too, writing over every snapshot and passing.
- **Your app's man page can list them.** `swift run tui-environment-docs --format man` prints an ENVIRONMENT section in `man(7)`, and `--format mdoc` or `--format markdown` the others, so upgrading TUI updates your documentation when your build script regenerates it. `TUIEnvironmentVariables`, in the new `TUIEnvironmentDocs` product, returns the same text. An app that uses neither carries nothing for them. See "Documenting Environment Variables" in the Building and Shipping an App article.

### Removed deprecated spellings

The project removes SwiftUI API that SwiftUI itself has deprecated, and does not add it. The spellings real code uses most, and the modifiers a terminal can't honour, now get a compile error saying what to use instead (`'cornerRadius(_:antialiased:)' is unavailable: A cell has square corners...`), on the line that used them, in under a second. They were 10 to 20 seconds of "unable to type-check this expression" at `var body`. They don't appear in code completion or the documentation. These went:

- `Text + Text`, deprecated in SwiftUI on macOS 26. An interpolated `Text` keeps its fragments' styling, which replaces it.
- `UnitCurve.easeInEaseOut`, renamed `easeInOut` in SwiftUI.
- `WindowGroup.init(content:)`, replaced by `init(makeContent:)`. A call written `WindowGroup { ... }` binds either.
- The `CoordinateSpace`-enum overloads of `GeometryProxy.frame(in:)`, `onTapGesture(count:coordinateSpace:perform:)`, `onContinuousHover(coordinateSpace:perform:)`, `DragGesture.init` and `SpatialTapGesture.init`. They are internal now. The `some CoordinateSpaceProtocol` forms are public, and `.local`, `.global`, `.named(_:)` and `.scrollView` bind to them.

Deprecated SwiftUI spellings TUI still has, on purpose:

- The soft-deprecated `dropDestination(for:action:isTargeted:)`, until the drag-session work.
- The catch-all `Text("... \(anything)")` string interpolation, deprecated as SwiftUI deprecates it on the macOS 26 SDK: it compiles and warns.
- The `.roundedBorder` and `.squareBorder` text field styles, which SwiftUI deprecates in macOS 27. TUI's parity baseline is the macOS 26 SDK.

`Tools/APIParity/api_parity.py --deprecated` lists the SwiftUI declarations deprecated on macOS that TUI still implements (23 against the macOS 26.2 SDK). Most are cases where TUI has the live overload and SwiftUI's deprecated one shares its name.

### Concurrency

The compiler now checks what `@unchecked Sendable` used to assert. If your code stops compiling, it was relying on one of these:

- `EnvironmentValues`, `DropInfo`, `ToolbarItemPlacement`, `ToolbarPlacement` and `RenameAction` are not `Sendable`, as SwiftUI declares them not to be. Their built-in placements are computed, so `static let favorites = ToolbarItemPlacement.accessoryBar(id: "f")` of your own needs to be a `static var`, as it does on SwiftUI in Swift 6 mode. So are `PreferenceValues`, `ThemeManager`, `FocusManager`, `StateStorage`, `RenderCache`, `TUIContext`, `TooltipState`, `StatusBarState`, `StatusBarItem`, and `RequestAttentionAction`, and an `EnvironmentKey`'s default of one of them has to be computed.
- `GestureState` is no longer `Sendable`, where SwiftUI's is `@unchecked` when its value is. It holds a `State`, which never was.
- `Focusable.handleKeyEvent(_:)` and `MouseEventDispatcher.dispatch(_:)` are `@MainActor`, where the run loop always called them.
- An animation completion is `@MainActor`. `withAnimation(_:completionCriteria:_:completion:isolation:)`, and `withTransaction(_:_:isolation:)`, have a defaulted `isolation:`, so a completion can run at once where the caller is on the main actor; elsewhere it runs as soon as the main actor can take it. A closure literal compiles as before. A completion held in a variable is written `{ done() }`.
- `Lock` is built on `Mutex`, and is no longer re-entrant anywhere, as it was not on macOS. On macOS re-entering one ends the process with a SIGKILL.
- `CustomPresentationDetent` refines `SendableMetatype`.

### Dependencies and requirements

- Swift: `swift-tools-version: 6.2`. The README says Swift 6.2 or later. CI builds with Xcode 26 and 27 on macOS and with Swift 6.2, 6.3 and 6.4 on Linux. The tools version is unchanged by the split. On macOS the SDK must be Xcode 26's or Command Line Tools 26's or newer; the macOS 15 SDKs are not supported.
- Platforms: macOS 15 or later (`.macOS(.v15)`, raised from macOS 14: a package below it gets SwiftPM's "requires macos 15.0" error, and adding the line, or raising it, is the fix), and Linux (no platform declaration needed). The package also builds for `wasm32-unknown-wasip1` (the README describes a browser build of the Example app). On Windows, the four lowest modules (`TUICore`, `TUIStyling`, `TUIView`, `TUIImage`) build, and the rest do not yet.
- **swift-docc-plugin** (from 1.4.3): documentation. No target uses it.
- **swift-syntax** (`602.0.0` up to, not including, `700.0.0`): added for the compiler plugin behind `TUIMacros`. It is built only for an app that depends on that product. Every client still resolves and fetches it, because SwiftPM resolves by package. The range is wide so that TUI does not refuse an app whose other packages want a newer swift-syntax. SwiftPM uses a prebuilt swift-syntax only where one is published for the version and toolchain: 602.0.0 on Swift 6.2, and 604.0.0 on swift.org's Swift 6.4.0 on macOS. An app on Swift 6.2 that wants prebuilts can pin `exact: "602.0.0"`.
- **swift-collections** is no longer a dependency. TUI used its `UniqueDeque` for input buffering. Linking swift-collections' `DequeModule` pulled in a reference to `libswiftCompatibilitySpan.dylib`, which macOS has only from version 26, so a release program copied out of `.build` failed at launch on macOS 14 and 15. `TUIApp` now has its own input buffers. If your own program uses the standard library's `Span` types or links swift-collections 1.4 or later, see [Building and Shipping an App](https://swift-tui.com/docs/documentation/tui/shippinganapp) for what to ship.
- `ordo-one/benchmark` is added only when `TUI_BENCHMARKS` is set in the environment.
- The repository no longer tracks `Package.resolved`. SwiftPM never read a dependency's pins, so nothing changes for an app.
- The `tuikit` project generator (`project-template/`, installed with `curl … | bash`) is removed. A new app needs only the two lines of `Package.swift` that the README's "Getting started" gives, and the README's sample is a whole app. A `tuikit` command already installed goes on working, as it was; nothing will update it.

### Highlights since the split

- A slow `body` runs once a frame, where it ran twice: to be measured, and again to be drawn. Two sibling bodies of 50 ms beside a written leaf cost 101 ms a key where they cost 201. Only a view of the app's own, seen to take the time. `TUI_KEEP_BODIES=0` turns it off. A `body` that counts its runs sees the difference.
- A menu bar. A scene that declares `commands` gets a menu bar on the window's top row, with `CommandMenu`, `CommandGroup`, the standard command sets, and TUI's own app, File (Close and Close All, for an app that can have more than one window), Edit, View, Window and Help menus. Menus open by click, by F10 and the arrows, or by Option and a title's letter. As on a Mac, a press on a title dragged down its menu runs the item it is let go on, and with one menu open the pointer on another title opens that title's. About shows the app's name, version, credits and copyright, as the scene's `aboutPanel(applicationName:applicationVersion:version:copyright:credits:)` or the bundle's Info.plist states them. Help ▸ Show Tooltips turns tooltips off and on, and Show All Tooltips (⌥?, or Shift-F1 on any terminal) shows every one on the screen at once. TUI's own `DisplayCommands()` adds View ▸ Palette, Border Style and Control Style, each a submenu of the built-in choices: it chooses through the app's palette and appearance managers and a new control style manager (`\.controlStyleManager`), disables a submenu whose value the scene sets itself, and writes the app's own state instead where it is given a binding (`DisplayCommands(palette:appearance:controlStyle:)`).
- Several scenes and windows. A body can declare more than one scene. `openWindow`, `dismissWindow`, windows presenting data, a `Settings` scene shown as a sheet (`openSettings`), `AlertScene`, per-window `@SceneStorage`, and the terminal's title following the window in front.
- Toolbars. SwiftUI's `.toolbar` places items in the top and bottom bars by placement. Window toolbar styles, accessory bars, title menus, `toolbar(id:)` customization from a panel, and tab view sidebar toolbars. While the Customize Toolbar panel is open, the bar's customizable items are dragged in the bar to move them, or off it to take them out (in macOS's puff of smoke), and each of the panel's rows has a grip to drag it into place.
- File panels. `fileImporter`, `fileExporter`, `fileMover` and the `fileDialog` modifiers present open and save panels that TUI draws, in the new `TUIFilePanels` module. Each item is drawn after an icon of its kind; `fileDialogIcon(_:)` draws an app's own instead, and `fileDialogSystemIcons()`, from `TUIFilePanelsAppKit`, the Finder's, where the terminal draws pictures. A panel browsing a machine the user is not at (over ssh or mosh, or from a tmux client attached from one) says so in a line above the path, which `fileDialogRemoteNotice(_:)` hides.
  - The path is a segmented path control, a segment per folder, after a ↰ button to the enclosing folder.
  - The list view is an outline: → opens a folder in place, ← closes it, Backspace goes up. A switcher beside the path chooses it or a column view, as Finder's, and the choice is kept per app (per `fileDialogCustomizationID(_:)` where one is set). In the column view → opens a folder, and going up keeps the way back down beside the folder come from.
  - A preview pane shows the item selected: behind a splitter in the list view (open by default where the panel is wide enough, and kept as chosen), and as a column of its own in the column view. It shows a text file's opening lines and the item's name, kind, size and date, with an app's own view above them from `fileDialogPreview(_:)`, or a picture under `fileDialogPicturePreviews()`, from `TUIFilePanelImages`.
  - A panel with more than one type has a pop-up of them, Show to open and Format to save; `fileDialogContentTypePicker(_:)` shows or hides it.
  - A save panel, and a mover's, has New Folder (or `+` in the folder). An open panel has none, even one that chooses folders. A folder that can't be made says why in the sheet, which stays up with the name to change.
  - Finder's chords, written with ⌘ and resolved through the command key (⌃ by default): ⌘2 and ⌘3 for the views, ⇧⌘P the preview, ⌘↑ and ⌘↓, ⇧⌘G to go to a folder, ⇧⌘H, ⇧⌘D, ⌥⌘L, ⇧⌘O and ⇧⌘A for the home, Desktop, Downloads, Documents and Applications folders, ⇧⌘N New Folder, ⇧⌘. hidden files and ⌘. cancel. The status bar names only those the terminal can send.
  - Two TUI-only `fileExporter` forms save on every platform, Linux included, where SwiftUI's take a `Transferable` or a `FileDocument`: `fileExporter(isPresented:contents:contentType:defaultFilename:onCompletion:onCancellation:)` takes `Data`, a `String` or a type of the app's own (`FileExportContents`), and `fileExporter(isPresented:encoding:contentType:defaultFilename:onCompletion:onCancellation:)` any `Encodable` value, written as JSON or a property list.
- Shapes and paths. Shapes are views, drawn in box glyphs or rasterized, with `Path`, container shapes, and shapes as backgrounds, overlays, clips and hit areas. `mask(alignment:_:)` keeps a view's cells where another view draws (`gradient.mask { Text(…) }` draws gradient text), and `drawingGroup(opaque:colorMode:)` blends in linear light inside the group under `ColorRenderingMode.linear`.
- `Canvas` and the whole of `GraphicsContext`: paths, shadings, images, text, symbols, clips, layers, blend modes and filters. It draws in the terminal's own pixels where it places pictures, and otherwise in a cell's two colours over a grain of glyphs. `.canvasGrain(_:)` chooses the glyphs (half blocks, quadrants, sextants, octants, Braille), and `pixelGrid`, `setPixel(x:y:to:)`, `drawLine(from:to:with:)`, `drawPixels(_:width:height:in:)` and `setCell(column:row:to:foreground:background:)` reach the grid directly. A `TextRenderer` can now `fill` and `stroke` too. A layer in a `TextRenderer`'s context now starts at an opacity of 1 and takes the context's own as it lands, as SwiftUI's does.
- Materials, glass, shadows and blend modes. Materials as translucent surfaces, `GlassEffectContainer` that joins glass, drop and inner shadows (animatable), `View.blendMode`, `ShapeStyle.blendMode`, and image paints. A material or glass over a terminal picture frosts the picture itself, and `.materialFrostResolution(_:)` (TUI-specific) draws that frost at more of the terminal's pixels: `.native`, or `.downsampled(by:)` a factor.
- Stacks of fades. A `ZStack` of translucent layers that each cover it, blended or not, is drawn in cells rather than through their bytes. The same cells come out, and thirty blended gradients at 200 × 48 render about thirteen times faster.
- Animation. Branch fades, matched geometry, the zoom navigation transition, `.blurReplace` (its scale and a fade, the blur drawn as the fade), `CustomAnimation`, animations that carry their motion when interrupted, and stacks whose children glide when a view comes or goes. A grid's cells glide when its lattice changes, a view leaving a `Layout` gives its room back at once while the others glide over it, a strikethrough changed under an animation is drawn along its text and taken back, and a navigation zoom scales and moves the terminal pictures it reveals or folds away.
- Scrolling. Scroll target behaviours (`.paging`, `.viewAligned`), bound scroll positions that `List` and `Table` follow, and horizontal scroll fixes. `.scrollIndicatorPlacement(.overContent)` (TUI-specific) takes no room for the indicators and draws them over the content's edge while the pointer is over a `ScrollView`, `List`, `Table` or `TextEditor` whose content overflows, and beside the content, as `.besideContent` draws them, while the view has the focus; `.besideContent`, the default, keeps them in room of their own.
- Pictures. Each cell's background in coloured braille, `.imageInkThreshold(_:)` to state where braille's dots and a mono picture's ink begin (measured from the picture by default), `.imageAdjustments(_:)` (`ImageAdjustments`: exposure, black point, highlights and contrast), and `.imagePosterization(levels:)`, which reduces each channel to a few levels and gives `.imageDithering(_:)` something to spread in true colour, all TUI-specific. A terminal picture that changes is swapped in one held update without a blank frame, and one at rest is sent again at its box's exact size. A terminal picture faded with `.opacity`, recoloured by a colour effect, under glass or behind a modal draws a changed copy of itself instead of being left as it was or blanked.
- Lists, tables and navigation. SwiftUI-shaped `Table` columns, `OutlineGroup` over a binding to a tree, `sidebarAdaptable` tab views with a customizable sidebar, `HSplitView`, `VSplitView` and the inspector, and compact-size adaptation for popovers, tables, split views and tab bars (`tabBarMinimizeBehavior`). A list row's `swipeActions(edge:allowsFullSwipe:content:)` are revealed by ⇧→ and ⇧← (or ⌃L and ⌃T, rebindable as `RowAction`s), again for the full swipe, or by a sideways swipe where the terminal reports one as the horizontal wheel. An `HSplitView`'s or `VSplitView`'s divider takes Home and End.
- Drag and drop. A focused `.draggable` copies its payload with Copy and a focused drop destination takes it with Paste, and Ctrl-R picks a `.draggable` up to carry it from the keyboard: Tab and the arrows move among the places that accept it, each marked ‹, Return drops it, Space flips copy and move, and Escape puts it back.
- Search. `tabViewSearchActivation(_:)` with `.searchTabSelection` (SwiftUI's `TabSearchActivation`) moves the focus to the search field when a `Tab(role: .search)` is selected, and selects the tab before it again when that search ends. Find (⌃F) reaches a `.searchable` field from anywhere in its view.
- Controls. A radio group's option can be disabled alone (`RadioButtonItem.disabled(_:)`). A `.graphical` `DatePicker` tells the weekend and, where asked, past days apart. A slider's fill from its neutral value starts within a cell under `.blockFine`.
- Control sizes. Text fields, sliders, steppers and segmented pickers follow `controlSize` from mini to extra large, and a bare picker, slider or stepper in a `Form` is a field row.
- Text. `AttributedString` runs, `Text` that keeps its styling when interpolated, Markdown in control titles, underline patterns and colours, and `MeshGradient`. SwiftUI's `TextRenderer` (`View.textRenderer(_:)`, `TextProxy`), `Text.Layout` with its lines, runs and glyphs, `Text.customAttribute(_:)` and the part of `GraphicsContext` that text needs, in cells: a renderer redraws a text from its layout, glyph by glyph, and is interpolated under an animation. TUI adds `GraphicsContext.drawSubstituting(_:for:options:)`, which draws a glyph as another character, and `textAttributes` for bold, italic, underline and the rest per glyph. Inline Markdown reaches everything a `Text` can do to its words, through Apple's `^[text](key: value)` syntax with TUI's own keys (colours, underline and strikethrough styles and colours, font, weight, dim, blink, inverse and text scale), decodes all 2,125 of HTML's named character references, and reads link reference definitions as Foundation does.
- Text input and undo. Typing is grouped into undo steps as macOS does, Ctrl-Z and the undo and redo keys, Option-drag block selection in `TextEditor`, and content-type filters. `TextEditor`'s find bar (`findNavigator`) opens with Ctrl-F, finds the next match with Ctrl-G, tints every match and has macOS's options; the wheel scrolls an editor and a capped vertical field; a search field shows a ✗ that empties it. Selected text dragged elsewhere in a `TextEditor` moves there, as one undo step. A caret at a soft wrap leans to the end of the earlier row or the start of the later one as macOS's does, by the key or click that put it there.
- Screen selection. A drag selection's highlight keeps to the text it crosses: each `Text` it crosses lights its own frame, so a card's padding, the blanks past a short line and the gap between two texts side by side stay unlit. What is copied is unchanged.
- Tasks. SwiftUI's `task(name:priority:file:line:_:)`, `task(id:name:priority:file:line:_:)` and `task(name:executorPreference:priority:file:line:action:)`, which name the task they start.
- Terminal integration. Pointer shapes (`pointerStyle`, and TUI's own over its controls, with the hand placed by `pointingHandCursor(over:)`), a progress bar on the terminal's tab (`.terminalProgress`), desktop attention notifications, OSC 52 and OSC 5522 clipboard with HTML, RTF and images, and the kitty keyboard protocol. `\.terminalCapabilities` tells an app what the terminal can do, feature by feature (curly underlines, pictures, links, key releases, Option as Meta and more), as supported, unsupported or undetermined, so a page can say "this terminal does not draw that" only where it is true.
- Platforms. GNOME Terminal (VTE) is recognized and compensated for, and there are fixes for Linux and WebAssembly (WASI).
- Macros. The `TUIMacros` product adds `@Animatable`, `@AnimatableIgnored` and `@Entry`.
- Documentation. A "Choosing Products" article, a generated "Which Module Provides It" page, and CI that builds one small app for each library product.
