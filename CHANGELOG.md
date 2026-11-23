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

**On Windows, closing the app's window or tab quits it in order.** Closing conhost's window or Windows Terminal's
tab stalled the teardown until the system ended the app five seconds later, so it never got to its exit: settings
not yet saved were lost, and code after `App.main()` never ran. The teardown now finishes at once.

**An animating screen wakes the run loop once a tick, not twice.** Every render request made a `Task` to wake
the loop, and each one after the first left the loop a wake to find after its frame, so a page whose only activity
was a spinner went round the loop twice for each tick, and a key that changed state went round once or twice more
with nothing to do. Requests now share one wake a pass, and one the pass has already read wakes nothing.

**Keys typed behind ⌃Q are no longer handled.** ⌃Q and a Return read together (typed quickly, over ssh, during a
slow frame) ran the focused button's action, and could draw a frame, in an app that was quitting; anything else
typed behind it reached the app too. A quit now ends the reading of input where it is read, and the app leaves at
once, dropping the rest, as it already did when the keys arrived a moment later.

**A sectioned table's scrollbar stands in its column on the section headers' lines.** In a `Table` with sections
whose rows overflow, with the bar beside the rows, each section header's line drew the bar's cell straight after the
header's text (`Fruits▲`) rather than at the right edge. And a table with a bar measured one cell narrower than it
drew under `.scrollbarWidth(2)`, or, with wrapping columns or sections, at the default `.scrollbarSpacing`, wherever
its column headers were hidden: a parent sizing it by the measure gave it a cell too few.

**A focused value whose publisher stops publishing is gone from the next frame.** When a view publishing a
`.focusedValue` or a `.focusedSceneValue` was taken away, or published `nil`, every `@FocusedValue` reader went on
reading its old value, and no frame was asked for to show it gone: a command written `.disabled(selection == nil)`
stayed enabled, its shortcut working, until some other event drew a frame. The end of the frame now checks the
readings against what this frame published alone, and asks for the one frame that shows the value gone; a reader
drawn after a publisher of `nil` reads nothing at once.

**`@FocusedValue` readers share one reading.** Each read of a `@FocusedValue` merged, filtered and sorted every
publication afresh; a reading is now kept until a publication or the focus changes it, so a frame with thirty
readers (menu commands, toolbar buttons) makes two readings rather than a hundred and twenty.

**The menu bar keeps the same menu open when a menu comes or goes to its left.** The open menu was held by its place
in the bar, so a menu that appears conditionally (`if` in a `commands` body, or a standard menu whose items all went
away) put a different menu under the open one's highlight. The bar now holds the open menu, and the title the F10 bar
mode is on, by the menu itself; one that goes away closes, as before.

**A radio group knows its options by value.** An option's label and content were kept at its place in the group, so
a group built from changing data moved an option's `@State` (a slider's drag, a field's draft) to whichever option
came to stand there; they now go with the option, as a `ForEach` row's go with its id. The keyboard's cursor goes
with its option too, and onto the last option when the options shrink from under it, where a focused group showed
the focus on no option until a key was pressed. And an option whose label takes several lines is chosen by a click
on any of them, not on its first line alone; where the focus is drawn in reverse, all of them are reversed.

**Tabs whose values print alike keep state of their own.** A tab's content, its label and its context menu were
kept at an identity made from its value's `description`, so tabs over a `Hashable` class with no description of its
own (every instance prints as the type's name), two `Date`s in one second, or an enum case wrapping either shared one
`@State`, focus and kept subtree: a draft typed in one document's tab showed in the next. A tab is now known by its
value as a `ForEach` row is by its id; a `String`, `Int` or `UUID` value keys as before.

**Each text a `Canvas` draws keeps its own state, and is measured once.** Every text in a canvas shared one place,
so under a dissolving content transition (`.contentTransition(.opacity)`) and an animation each label dissolved from
the label drawn before it, and two labels with a strikethrough that changed retargeted each other's sweep. Each text
now keeps its state at its place among the canvas's texts, as an image does, so reordering the draws moves it with
the order. `draw(_:at:anchor:)` measured a text twice before drawing it; it measures it once.

**A `TextRenderer` keeps the text's own translucent colours, and a focused link's breath.** Under `.textRenderer(_:)`,
`Text("Ghost").foregroundStyle(.red.opacity(0.3))` was drawn full-strength red: the text writes a translucent colour
opaque and states its alpha beside it, and the renderer's redrawing kept only the words. Each glyph now carries its
text's alpha with it, wherever the renderer draws it. A focused link in the text breathes again where the renderer
draws its words as the text did; where it draws them otherwise, the breath stays off, so it cannot draw the words
back over the renderer's.

**A zero-width character no longer takes a cell in a `Canvas`'s text or under a `TextRenderer`.** A zero-width space
or a bidi mark (U+200B, U+200E/F, U+2066 to U+2069, as formatted dates and pasted names carry) was given a cell of its
own, so the rest of its row was drawn a column right of where the text was measured, and the row was a column
narrower on screen than it claimed: what was right of it on that terminal row moved left. It now rides with the glyph
before it, as the terminal draws it, and still counts as a character of the words (`Text.Layout.CharacterIndex`).

**A faint paint in a `Canvas` no longer erases the text under it.** A fill or stroke drawn over a glyph removed it
wherever its shape covered half the cell, at any opacity: a highlight at `opacity = 0.15`, a colour at 20 % and a
fill at opacity 0, which paints nothing, all deleted the labels beneath. A paint now covers a glyph where it hides at
least half the cell, its share of the cell times its alpha and the context's opacity, through a filter or a layer
too. The glyph it leaves keeps its ink untinted, with the paint as its field (a cell is a glyph or pixels), where
SwiftUI's text shows through tinted; `DrawingWithCanvas` says why the line is at half.

**A text field's suggestion fills it with all of its label's words.** A suggestion with no `textInputCompletion`
filled its field with the first row of its label as the menu drew it, so a label longer than the screen was wide, or
one that wrapped, wrote cut text to the binding, and a `.textCase(.uppercase)` above it wrote capitals. Its completion
is now its label's words as written: a `Text`'s, a `Label`'s title's, or what any other view draws at its ideal width.
SwiftUI shows such a suggestion but leaves it inert; TUI keeps it pickable, a deliberate deviation by the owner's
ruling of 2026-11-23.

**`fg` after a ⌃Z in a handed-off program continues the app too.** A program started with
`handOffTerminal(running:arguments:)` and stopped by ⌃Z could, on a busy machine, leave the app stopped again after
`fg` while the program ran on: the app asked whether the program had been continued before `fg` had reached it. It
now asks for 50 ms before it stops with a program that stopped alone.

**An app drawing on its controlling terminal hears its keys again on macOS.** An app in a pipeline (`cat data |
app`) that answered `runWithoutTerminal` with `.drawOnControllingTerminal` drew, but no key reached it, ⌃Q included,
since 2026-11-10: its stdin was pointed at `/dev/tty`, which macOS's `poll` and `kqueue` cannot wait on, and the
loop took it for input at its end. Stdin and stdout are now pointed at the terminal's own device (`/dev/ttys005`), as
`ps` names it, on macOS; Linux keeps `/dev/tty`, which it waits on as any terminal.

**A selection follows the app's edits of the text, as in an `NSTextView`.** When an app changes the text bound to a
`TextField`, a `SecureField` or a `TextEditor` — lines appended to a log, another user's change synced in, a reformat
— an edit before the selection shifts it, one after it leaves it, and one that touches it leaves a caret at the end of
what it put in, so a text replaced whole leaves a caret at its end. A selection was kept by its numbers while they
fitted the new text, and the next key replaced text nobody had selected. A selection the app writes in the same update
(`selection:`) still wins; a text-only write now shifts the selection where SwiftUI keeps its numbers (and traps when
they no longer fit), and SwiftUI's `TextEditor(text:)` puts the caret at the end on any change: both are deliberate
deviations, by the owner's ruling of 2026-11-22. A binding that formats as it is typed (a hyphen put in a phone
number) leaves the caret after the character typed, not before it.

**A drag carried from the keyboard drops on a disabled destination, as the pointer's does.** A `dropDestination` or
`onDrop` view under `.disabled(true)` takes the pointer's drop, as SwiftUI's does, but a carry (Ctrl-R, then Tab)
passed it by, so only the mouse could drop there. A carry now stops there too and Return drops on it; it still takes
no focus, so Tab outside a carry skips it and Paste does not reach it (owner's ruling of 2026-11-23).

**A disabled view starts no drag from the pointer either.** `.disabled(true)` stopped a `draggable(_:)` or `onDrag`
view's Copy and Ctrl-R, but a press and a drag still picked it up. Now it starts no drag at all, as in SwiftUI, where
the disabled scope covers the modifier: `.disabled(true).draggable(x)` still drags, as SwiftUI's does. A drop
destination under `.disabled(true)` still takes the pointer's drop, which SwiftUI's does too. A disabled draggable
or destination now keeps its place in the focus order without taking the focus, so the focus leaving one goes to its
neighbour.

**An `onDrop` view takes a drop from the keyboard.** It was no focus stop, so a drag carried with Ctrl-R could not
reach it and Paste never landed there: only the pointer could drop on it. It is a stop now, as a `dropDestination` is,
or answers on its content's own: a carried drag stops there and Return drops it, and Paste drops what was copied, as
the item providers a drag of it would carry, so a `DropDelegate` hears the whole of a drop's calls.

**A picture shrunk to its box averages every pixel it covers.** A URL's picture, a decoded image and an animation's
frames were shrunk by a bilinear read of 2 × 2 source pixels per target pixel however large the source, so a
4000 × 3000 photo in a 40 × 12 box saw about one pixel in ten and fine lines broke up; a file's picture was averaged
down by whole blocks first and then read the same way. Every picture now goes through one resampler, an area average
in one pass: each pixel of the glyph grid, or of what a graphics protocol is sent, is the average of every source
pixel it covers, weighted by how much of each it covers and by its alpha, so a transparent pixel lends no colour.
Enlarging is as it was, and `imageSupersampling` now only softens an enlargement, a shrink having nothing left for it
to average. An image's `.interpolation(.none)` or `.antialiased(false)` reads each sample from the one pixel it falls
on, SwiftUI's nearest-neighbour read, where it used to mean that 2 × 2 read. A picture drawn smaller than it is comes out slightly different; a large one costs what its size says
(7.6 ms to shrink a 4000 × 3000 photo to 80 × 48 in release, where the bilinear read took 0.03 ms and the old file
path 17.6 ms). `RGBAImage.scaledBilinear(to:_:)` and `RGBAImage.boxReduced(by:)` are gone: call
`resampled(to:_:)`.

**On Linux, WebAssembly and Windows, every `UserDefaultsStorage` over one suite is one store.** A suite there is a
JSON file of TUI's own, and each `UserDefaultsStorage(suiteName:)` loaded the file and kept a copy of its own, so
`@AppStorage("theme", store: UserDefaultsStorage(suiteName: "prefs"))`, which makes a store with every view, read
another view's write only once it had loaded the file again, redrew nothing for it, and raced its save. Every store
over one suite now shares the file's one copy, its saves and its readers while any of them is alive, as two
`UserDefaults` over one suite do on Apple platforms: a write through any is read through every other at once.

**A `Data` an app kept in `@AppStorage` under TUI 0.6.0 reads back as itself on macOS.** 0.6.0 kept every value as
its JSON, a `Data` as a JSON string of base64, and the current build took those bytes for the value: `[1, 2, 3]` read
as the six bytes of `"AQID"`. Bytes that are such a string are read as that now, and a write keeps the value as
itself. A `URL` 0.6.0 kept was already read right; it is no longer handed to `UserDefaults.url(forKey:)` first.

**A `JSONFileStorage` let go with a write still unsaved saves it.** A write is saved on a queue that holds the store
weakly, so a store made in a function, written to and let go before the save ran wrote nothing and reported nothing.
It writes what is unsaved as it goes now.

**Scene state written just before a quit is saved.** Quitting flushed only the default store, and `@SceneStorage`
keeps its values in a store of their own beside it, saved on a queue of that store's own, so a scene's last write
could miss its file and the next launch restored the place before it. A store's `synchronize()` now flushes its
scene state too, and quitting flushes every store a scene names with `.defaultAppStorage(_:)` as well as the
default. A store a view's own `.defaultAppStorage(_:)` or a property's `store:` names is still the app's to flush.

**A large `TextEditor` holds a fifth of the memory it did.** Its lines were kept as arrays of `Character`, 16 bytes a
character beside the text itself; they are kept as UTF-8 now. A 10 MB document of 353,000 lines took about 224 MB of
heap once its editor had drawn, and takes about 44 MB (665 to 129 bytes a line; the lines' own share went from 518 to
79, and a line that fits its row keeps no wrapping data but its length). Opening one takes 92% less time, as its lines
are cut from the text's bytes and wrapped from them, and laying out a text an app replaces whole two thirds less. A line
of ASCII is wrapped and drawn from its bytes, without a `Character` made, compared and measured for each: wrapping a
whole document again, as a click into a large editor does, takes a thirtieth of the time it did (102 to 4 ms for
Stress's 3.2 MB `bigtext-find`), and a key in Stress's `bigtext` costs 18% less. A vertical `TextField` lays its text
out the same way. Nothing an app sees changes.

**SwiftUI's endless list runs in an app.** `ScrollView { LazyVStack { ForEach(0..<Int.max, id: \.self) { … } } }`
trapped on an app's first frame, and a lazy stack of ten million rows built ten million on it: the walk the first
frame makes of the page to learn its bars drew the stack's top screenful from every one of its rows. Past 256 rows,
a lazy stack drawn from its first row now builds only the rows down to the first that does not fit, so the first
frame builds about a screenful, and so do End, Page Down and a scrollbar drag.

**Every toast of a burst is shown: those that don't fit wait their turn, their timers too.** A stack showed the
newest toasts that fit, and the older ones aged off screen, so in a burst (ten uploads failing at once) most expired
unseen. A stack now shows the oldest toasts that fit, and the others wait for room with their timers stopped, so
each is shown for its whole duration. The newest toast is no longer always the one on screen.

**A body's reads of a `@State` all agree, however a background task writes it.** A write from a detached task that
landed while a body ran could change the value between two of that body's reads, so `if !items.isEmpty {
Text(items[0]) }` could find the array empty at the subscript and stop the program, and a child reading the state
through a `Binding` could see a different value from its parent's. Every read in a frame now gives the value the
frame's first read gave; a write from another thread shows in the next frame, which it asks for. A body that writes
its own state still reads its write back.

**Scrolling moves rows with a scroll region only on terminals TUI recognises and has measured.** Apple Terminal,
iTerm2, Ghostty, Warp and tmux are unchanged. Any other terminal, including one TUI could not identify, such as one
reached over ssh that names itself only as `xterm-256color`, now has a scrolled list's rows redrawn rather than moved,
which sends more bytes. A terminal that ignored the scroll command would have shown old and new rows mixed.
`TUI_SCROLL_OUTPUT=1` asks such a terminal to move them anyway.

**A toast from a sheet presented over a sheet stays on top once its sheet closes.** A sheet over a sheet that
posted "Removed" and closed left the toast drawn dimmed under the sheet beneath, its timer stopped until that sheet
closed too. A closed presentation's toasts now belong to what was beneath it.

**A toast posted from a window that then closes is shown in the window in front.** Posting "Saved" and calling
`dismissWindow()` left the toast waiting for good for a window that never came back: it was never shown, never went,
and kept the app waking four times a second. A closed window's toasts are now drawn by the window in front.

**A toast's action runs once, however quickly its button is clicked again.** A toast fades out for 0.3 seconds
after one of its buttons is chosen, drawn as it was, and a second click in that moment (a double click on Undo) ran
the action again. Choosing a button on a toast already dismissed now does nothing.

**The colour picker's channel fields read digits of any script, and fractions.** Typing "٥٠" or "５０" into a
channel set it to its maximum, and "12.5" in a percentage field read as 125, so 100%. Digits are now read by value,
in any script, and a point, a comma or the Arabic decimal separator starts a fraction, as macOS's colour panel takes
one: "12.5" is 12.5.

**The 256-colour grid's cursor stays on the swatch picked when the binding stores RGB.** A `ColorPicker` bound
through a store that keeps red, green and blue (a hex string in `@AppStorage`, a model's `r`, `g`, `b`) handed a
picked system colour back as RGB, and the grid moved its cursor to the nearest cube cell, so the arrows went on from
there. The cursor now stays where it is while its swatch is the bound colour.

**The Web Safe and Crayons tabs mark, and Crayons names, the swatch picked at any opacity.** With the colour
picker's opacity below full (opacity is on by default), picking a Web Safe or Crayons swatch drew no check on it, so
the arrow keys moved a cursor nobody could see, and Crayons showed no name. A swatch is now matched by its colour
alone.

**A following list with nothing selected answers ⌃A, ⌃V, the sort chords and Escape again.** Under
`.selectionFollowsCursor()`, a list or table whose cursor is on no row (nothing selected yet, or the app cleared the
selection) took every row chord and did nothing with it, where it meant to refuse only the row-moving ones: ⌃A
selected nothing, ⌃V entered no extend mode, ⌃S and ⌃D did not sort a table, and Escape stopped at the list instead
of going on to the page. Only the move chords are refused there now; ⌃V starts on the first row.

**After an app clears a following list's selection, the page keys start from the top.** Under
`.selectionFollowsCursor()`, a selection the app empties forgets the cursor, and Down and Up already started afresh,
but Page Down selected a page below the forgotten row and Page Up a page above it, and Shift with an arrow spanned
from it. They now act as on a list nobody has touched: Page Down selects a page below the first row and Page Up the
first, and Shift with an arrow starts from the first row.

**Several rows moved from the keyboard stay in their own section.** With two rows of a section in hand, End (or
Down past the section's last row) drew the landing slot under the next section's header, and Return left the cursor
on that header, though the rows landed at the end of their own section. In a list without sections the extra places
were a dead zone: Up had to be pressed once per extra row before the slot moved. An element of several rows nudged
down from the end of its section fired a move that went nowhere and put the cursor on the next section's rows, and
a drag held at the list's edge could carry its slot one place past its section. All of them now stop at the
section's last place.

**A list first drawn with a `nil` `Set` binding selects once it is given one.** `List(selection: isEditing ?
$picked : nil)`, SwiftUI's edit-mode idiom, took its kind of selection from the first frame, where the binding was
`nil`, and kept it: once editing began, no row drew selected and Space, clicks, Shift with an arrow and ⌃A did
nothing until the list's identity changed. A `List` now takes its kind from the initializer called, and a list or
table takes it again every frame, so a `Table` rebuilt at the same place from `Table(_:columns:)` to a `Set`
`selection:` initializer selects too.

**Mid-drag, the arrow, paging, Home and End keys scroll the view under the pointer with a text field focused too.** A
`.draggable` takes no focus, so a `TextField` or `TextEditor` focused before the drag kept it and took those keys
for its caret, and the view the drag was aimed into never moved. They now reach the drag first, as they do with
anything else focused; typing still goes to the field.

**A drag of a `List`'s selection carries it all, however fast it is dropped.** A press, a drag and a release read
together — on a slow frame, or over a link that delivers the reports in one burst — dropped the grabbed row alone and
left the rest of the selection behind, because a list learns its selected rows' values on the frame after the drag
begins. A drop that comes before that frame now waits for it.

**A drag whose release was lost ends at the next press.** When the terminal never reported the button coming up —
let go outside the window, or behind a multiplexer — the drag stayed in flight for good: the source drawn blank, the
destination targeted, `onKeyPress` handlers deaf, and nothing but another drag to end it. The next press now ends it
as a release over nothing does, the preview walking home, and then does what it would have done.

**A drop destination scrolled under a still pointer is targeted.** A drag held still at a scroll view's edge
auto-scrolls it, and the wheel and the paging keys move the page under it too; the destination it was over when the
pointer last moved kept `isTargeted` and the badge as it scrolled away, the one under the pointer was never told, and
an `onDrop` delegate heard neither leave nor enter. Each frame now asks again what is under the pointer.

**A `Table` row that takes a drop is lit while the drag is over it, whichever row has scrolled there.** With a drag
held over a row's `dropDestination`, rows scrolled under the pointer by the wheel, the edge auto-scroll or a paging
key left the first row lit as it scrolled away and the row under the pointer unlit, however the pointer moved along
the line afterwards, and after the drop the first row could stay drawn as selected until the next drag. The row under
the pointer is now the one lit, and none stays lit.

**A colour in the colon form (`38:5:n`, `48:2::r:g:b`) ends at its `39` or `49`.** Kept escapes spelling a
foreground or background colour as ITU T.416 does were passed through as codes TUI does not know, which only a full
reset ends, so the `39` or `49` after one was netted away as a change of nothing and the colour ran on. Such a colour is
now read as the colour it names and written in the semicolon form.

**A row's fill, faint, bold or reversal carries on after git's and grep's `ESC[m`.** Text drawn with
`.textKeepsEscapeSequences()` keeps the tool's own resets, and only `ESC[0m` (and the collapsed `ESC[0;…m`) was
recognised as one: after a bare `ESC[m`, `ESC[00m`, `ESC[;1m` or a reset after another parameter (`ESC[1;0m`), a
selected list row's highlight stopped in the middle of the text, a disabled row lost its faint, and the rest of the
row showed the terminal's own background instead of the page's. Every spelling of SGR 0 is now a reset there.

**A view cut to fit no longer paints its background, underline or reversal over what comes after it.** A child
drawn wider than the room it was given, a negative stack `spacing`, and every other clip of a line cut a styled run's
closing reset off with the rest of the line, so a sibling to its right, the gap before it and the row's padding out
to the terminal's edge were drawn in the run's background, underline or reverse video. A cut now closes what it
leaves open, and a wide character it splits is left as a blank cell in the view's own styling, so a filled view is
filled right up to the cut rather than one cell short. Lines that were already closed where they were cut are written
exactly as before.

**A pane served after its page's write keeps the memos inside it.** When a page's `@State` changed and a pane below
it compared unchanged, the pane was served, but every row memoized inside it was thrown away at the end of the
frame, so the next change inside the pane (a hover, a selection, one row's data) drew all its rows again. Those rows
are now kept, and that change draws only the row it touched: one row instead of 200 on a pane of 200 rows.

**A tinted glass keeps its tint's transparency while the window is inactive.** `.glassEffect(.regular.tint(…))` with a
translucent tint went more solid as the terminal lost focus, because greying the tint dropped its alpha. The colour
effects' arithmetic now keeps a colour's alpha.

**A palette whose roles are named colours builds its faces and fills from their dark values on a dark page.** A
`Palette` of an app's own with, say, `var accent: Color { .mint }` drew marks in the accent's dark value but mixed a
button's faces, the focus breaths, the selected and cursor rows' fills and the stripe from its light value, so a
focused control breathed between two hues. Every such derivation now resolves the roles for the palette's scheme
first. The shipped palettes, and `.tint(_:)`, are unchanged.

**`.colorMultiply(_:)` by a palette role multiplies, and a named colour multiplies by the value it draws as.**
`.colorMultiply(.accentColor)`, or by any palette role, changed nothing, text or picture, and
`.colorMultiply(.orange)` multiplied by orange's light value on a dark palette. The tint is now resolved against the
palette first, as every colour drawn is. The same for a `Canvas`'s `GraphicsContext.Filter.colorMultiply(_:)`.

**A gradient of named colours takes the dark values on a dark palette.** `LinearGradient(colors: [.mint, .blue], …)`,
and any gradient whose stops were all named colours (`Color.red`, `.mint` and the others) or asset catalogue colours,
drew their light values on every dark palette, while the same colour on its own drew its dark value. Its stops are
now chosen for the palette's scheme as a lone colour is, so such a gradient changes on a dark palette.

**An arrow key or mouse report split across two reads is no longer read as Escape and typing.** The input parser's
waits for a lone `ESC`, an unfinished sequence and a paste that pauses were counted in passes of the run loop, and any
wake of the loop is a pass: on a screen that animates or writes state from a task, an arrow whose `ESC` and `[A`
arrived in separate reads (over ssh, under tmux) could become Escape, `[` and `A`, a split mouse report could type its
coordinates, and a paste that paused could be ended with its rest typed as keys. The waits are timed on the clock
now, from when what they wait on arrived: 50 ms for a lone `ESC` (the Escape key lands 50 to 75 ms after the press),
200 ms for an unfinished sequence, and a second after a paste's last byte. A whole sequence behind one a new `ESC` cut
short is read at once, rather than at the next poll.

**A modifier-key alternate gives the focus back in a running app.** Under the kitty keyboard protocol, with
`Button("Forward") {}.modifierKeyAlternate(.option) { Text("Go to…") }` focused, holding Option for more than a frame
and letting go left the focus on the control the alternate had moved it to, instead of returning it to "Forward". The
run loop starts each frame's walk twice, and the held focus was aged by those starts rather than by frames, so it was
forgotten on the second frame. The tests drove one start a frame and passed.

**A negative `Grid` row spacing overlaps the rows; a negative column spacing is held at zero.**
`Grid(verticalSpacing: -1)` drew its rows apart while reporting them overlapped, and every row's buttons after the
first answered clicks a line above where they were drawn; the rows now overlap, the later on top, as a column's
children do. `Grid(horizontalSpacing: -5)` reported a width short by the overlap and drew nothing once that went below
zero; columns do not overlap yet, so a negative column spacing is held at zero. A `LazyVGrid` or `LazyHGrid` whose
spacing outweighs its lines no longer reports a negative size.

**A lazy stack whose spacing comes to minus its row height no longer crashes.** In
`ScrollView { LazyVStack(spacing: compact ? -1 : 0) { … } }` over one-line rows, the frame `compact` became true
divided by zero.

**A negative `spacing` in a column overlaps its rows, as SwiftUI's does.** `VStack(spacing: -1) { Text("a\nb\nc");
Button("x") {} }` drew four rows while reporting three, with the button's click region a row above where it was drawn,
and a parent that gave the column the rows it reported cut its last row off. Each child is now pulled up over the rows
before it and drawn on top of them, as in SwiftUI: the column reports, is dealt and draws the same rows, so two
bordered boxes at `spacing: -1` share a border row; clicks, focus pulses and fades land where the child is drawn; and
the column settles where an animation glided it instead of jumping a row the frame it lands. A spacing that outweighs
the content no longer reports a negative size, which made the stack vanish inside another: in a column and in a row, a
pull reaches back no further than the stack's first row or column.

**A row that draws nothing takes no line in a lazy stack of more than 256 rows.** In
`LazyVStack(spacing: 1) { ForEach(items) { RowView($0) } }`, a row whose body is empty, or framed to no height,
took no line and no gap at 200 rows, as in a `VStack`, but past 256 it was a blank line and a gap: the list grew
holes as it grew. It now takes none at any count.

**A long lazy stack's scrollbar reads its rows, not how long it sat on one screen.** Past 256 rows of several
heights, the rows not yet drawn are priced at the mean pitch of those drawn, and that mean counted a row once for
every frame it was drawn: a stack that sat on a screen of one-line rows while something animated above it went on
pricing the five-line rows paged through after it at one line, so the thumb, "N more below" and a scrollbar jump were
out by a factor of five. The mean is now one sample a row, it is taken at its fraction rather than rounded to a whole
line (rows of 1.4 lines priced at 1 put the total 29% short), and it starts afresh when the rows are replaced or the
width re-wraps them; an append keeps it.

**A lazy stack's estimate of the rows it has not drawn no longer overflows.** Past 256 rows, the lines of the rows
not yet drawn were `count × pitch`, which trapped for SwiftUI's endless-list idiom, `ForEach(0..<Int.max)`, unless
every row was one line with no spacing. The estimates are now held at a quarter of `Int`'s range, which the rows past
it are not reached by.

**Every row of a long lazy stack of mixed heights can be scrolled back to after End or a scrollbar jump.** In
`ScrollView { LazyVStack { ForEach(…) } }` past 256 rows of several heights, the scroll offset beyond the rows
drawn is an estimate, and scrolling up from the end could bring it to 0 with the first rows still above, out of
reach of every key, the wheel and Home; or bring the first row on top with lines still reported above it, which
the next scrolls up did not move. The offset is now reconciled where the rows reach the top: the first row is on
top exactly at offset 0.

**The programs TUI starts for a link, a paste or a question to tmux read none of your keys.** `open`/`xdg-open`, the
clipboard's paste helpers, and `tmux` and `gsettings` were started with the app's own input, the terminal in raw mode,
so one that read it could take keys meant for the app or change the terminal's mode under it: a terminal browser
that `xdg-open` falls back to without a desktop would have done both. Their input is now the null device, as
`notify-send`'s already was.

**On Linux, the clipboard helpers and `xdg-open` are found on `PATH`.** `wl-copy`, `wl-paste`, `xclip` and `xsel`
were looked for in `/usr/bin` (and `wl-copy` in `/usr/local/bin`) only, and `xdg-open` in `/usr/bin` only, so one
installed anywhere else, such as a Nix or Homebrew profile or `~/.local/bin`, was not used: copies went nowhere and
links did not open. They are now looked for as a shell looks for a command, as `notify-send` already was. macOS's
`pbcopy`, `pbpaste` and `open` are still taken from `/usr/bin`.

**A paste from this machine's clipboard keeps the line break it ends with.** A paste read through `pbpaste`,
`xclip` or `xsel` dropped one line break from its end, on the belief that the helper had added it, which none does:
a whole line cut and pasted elsewhere was joined to the line after it, on macOS too. The text now comes as the
clipboard holds it.

**`copyToClipboard` is called on the main actor, and a call from elsewhere no longer compiles and then ends the
app.** `CopyToClipboardAction.callAsFunction(_:)` was nonisolated, so a call from a detached task or another actor
compiled, and stopped the process at the copy, which runs on the main actor. It is now `@MainActor`, as every other
environment action's call is. Source-breaking for a call outside the main actor: hop to it, with `await copy(text)`
in a task or `MainActor.run`. A call in a view's or a command's action, the usual place, is unchanged.

**A picture inside a repeating fade, or behind one, keeps drawing.** On a terminal that draws pictures, a
`repeatForever` `.opacity` breath over an `Image`, or a breathing scrim laid over one, sent a copy of the picture for
every level of the breath on every row at each render, megabytes in one frame, and its frames named copies already
deleted, so the picture vanished for most of the breath. A picture under a repeating fade now fades in eight steps,
each copy is sent once, and every frame names one the terminal still holds.

**A view with a fade of its own inside a repeating `.opacity` breathes with it.** In
`VStack { Text("a"); Text("b").opacity(0.5) }.opacity(on ? 0.3 : 1)` under `.repeatForever`, `a` breathed and `b`
stood still at whatever value the last render drew, jumping when anything else rendered. The same held for
`.opacity(1)` over a background, an `.offset` child with its own fade, a translucent fill or a gradient's alpha inside
the breath. Each now follows the breath, at its own alpha times the breath's.

**Only the view whose tooltip is waiting asks for the frame that shows it.** While a tooltip waited out its delay,
every view with help that drew asked for a wake of its own at the same instant, and declared a side effect that kept
the render memo from storing any view containing it; a page with many views with help, a toolbar or a form, gave up
its memo for every frame drawn during the delay. Now the view whose tooltip it is asks, and the run loop's own wake
does the rest.

**A hover tooltip is matched to its view, not to its text.** Help on a view inside a view with the same help took the
outer view's tooltip away when the pointer left the inner one for the rest of the outer, until the pointer left and
came back; and under `.tooltipStyle(.popover)` hovering one button of a list whose rows' buttons share their help drew
a panel at every row. The pointer's tooltip is now found by the view that published it, and its text is compared only
for the focused control's tooltip.

**A popover tooltip is no longer wrapped to the width of its control.** Help on a view in an `HStack`, a toolbar or a
fixed `.frame(width:)` was wrapped at the few cells the view was given, so `Button("Save") {}.help("Save the document
to disk")` in a row showed its help a word or a fragment per row, and Help ▸ Show All Tooltips (Shift-F1) did so for
every toolbar button. The panel now wraps to the terminal's width, capped at 44 cells as before.

**A scroll view that draws its content twice in a frame reports only what the second drawing shows.** When a scroll
view drew its content again in the same frame (a seek whose measure turned out wrong, a focus reveal), the rows only
the first drawing had drawn were reported anyway: an `onGeometryChange` asking `.scrollView` was told where a row the
frame never showed was, and an `onScrollVisibilityChange` observer measured in that drawing could be told it appeared.

**A lazy stack whose rows watch their geometry no longer keeps an entry per row each time one scrolls out of its
window.** A row with `onScrollVisibilityChange`, `onGeometryChange` asking another coordinate space, or a
`GeometryReader` that left a `LazyVStack`'s window and came back left what had been kept for it behind, for as long as
the stack lived, and every later frame walked all of it: a hundred trips over one screenful of rows kept some 1,300.
They now go when the row's marker does.

**A row's `onScrollVisibilityChange` is no longer told `true` and then `false` while it is on screen.** Once a
`ForEach` row had been served from its memo, the next time it was drawn afresh (a terminal resize did it for every
row, as did a change to the row) its observer was reported as a newly appeared view, and its earlier registration as
one that had left, so the app went on believing a visible row was hidden. A mouse handler written outermost on such a
row lost its owner the same way while the row was served.

**A suggested token's view holding `@State` no longer breaks the search field's suggestions menu.** The `token`
view of `searchable(text:tokens:suggestedTokens:token:)` was drawn, for each suggested token in the menu, where the
field keeps its own state, so its first `@State` took the place of the field's, and the menu never stayed open; every
token's view shared one state besides. Each is now drawn at a place of its own, keyed by its token, so its state stays
with its token as the ones before it are chosen.

**A `Picker`'s `currentValueLabel` holding `@State` no longer breaks the picker.** A menu picker drew the view it
shows as its current value where it keeps its own state, so the label's first `@State` took the place of the picker's,
the label lost its state every frame and the drop-down never stayed open. The label is now drawn at a place of its
own, and keeps its state while the picker shows it.

**A highlighter whose publish is refused for an older text is asked for its lines again.** Under the highlighting
seam's SPI, the lines a publish refused for a text the editor has moved on from named are listed in the next update's
`linesToStyle`, where the window holds them, moved through the edits since. They held the tokens the refused publish
said were stale, and a parse's changed ranges, of the tree it had just made, no longer named them, so a highlighter had
to remember them itself, or publish its whole window after each refusal.

**Rows stay whole on a terminal set to draw ambiguous characters wide.** Where iTerm2's "Ambiguous characters are
double-width", or Apple Terminal's or GNOME Terminal's equivalent, is on, box drawing, arrows, `●`, Greek and Cyrillic
advance two cells, and a part of a row rewritten on its own landed left of where the row was drawn, leaving old glyphs
beside the new. TUI now asks at startup, inside an exchange it already makes, and on such a terminal rewrites changed
rows whole. Layout still counts those characters one cell there.

**An `AnyView` whose content changes type starts the new content's state afresh.** In
`loggedIn ? AnyView(Home()) : AnyView(Login())`, or a wizard's `AnyView` steps, the view swapped in was handed the
`@State` of the one it replaced wherever their states lined up, so text typed in one screen showed in the next,
and a screen swapped back found what it had held. Content of another type is now a new view, as in SwiftUI; the
same type wrapped in a new `AnyView` keeps its state, as before. Only what the content made is dropped: a control
that draws erased labels at its own place, as a search field's suggestions menu does, keeps its own state.

**A view of plain data is compared by its bits, as SwiftUI compares it.** A view holding a `Double` that went from
`0.0` to `-0.0` kept showing `0.0`, a view holding `.nan` ran its `body` on every frame, and a view holding a struct
whose `==` compares an id alone was served stale when another of its fields changed. A field of plain data every byte
of which is defined (numbers, `Bool`s and structs of them, with no padding) is now compared by its bytes, `Equatable`
or not, and an `.equatable()` view is unchanged when its bytes or its `==` say so, as measured on SwiftUI. Anything
else, a `String` above all, is compared by its `==` as before.

**A test can ask what a cell is drawn in.** `TestScreen.style(at:)` and `style(of:)` give a cell's foreground and
background as the terminal is sent them, and whether it is bold, faint, italic, underlined (and in which shape),
struck through or reversed, so a test of colour no longer parses escape codes out of `styledLines`.

**A highlighter can ask whether its text is still the editor's.** Under the highlighting seam's SPI, a session's
`isCurrent(_:)` says whether a version is the one a publish would be taken for, so a long parse can stop for a newer
text without publishing to find out.

**A highlighter can be tested without an editor.** Under the highlighting seam's SPI, TUITesting's
`TestHighlightSession` plays the editor (an edit, a whole write, a scroll) exactly as a `TextEditor` tells its
highlighter of them, runs a highlighter and steps it until it waits for the next update, and reads back the tokens
and marks it published and every publish's outcome. `TextEditorText(_:version:)` makes a text as an editor hands it
over, and `TextEditorTokens` reads back as a collection of offsets and tokens. TUITesting now depends on
TUITextInput.

**A `TextEditor`'s highlighter can mark ranges of the text itself, such as its parse's errors.** Through the
highlighting seam (SPI), `publish(marks:of:)` gives the editor ranges of a version of its text, each drawn in a
token's style over the highlighting and under the app's own `.textEditorMarks`. The editor carries them through its
edits, its undo and redo, and the app's writes, as it carries an app's marks, so a highlighter publishes them again
only when they change, and no longer has to send them round through the app's state and a view's body. It returns
a `TextEditorPublishOutcome`, as a publish of tokens does: `.kept` of every line of the text, or `.refused`.

**Undo and redo in a highlighted `TextEditor` keep the colours of the lines they don't touch.** They write the text
whole, as an app's write to the binding does, and the editor forgot every line's highlighting at once, so the whole
pane drew plain until the highlighter answered, and the highlighter was told the text was all new. The editor now
finds the lines a text written whole changed, from what it shares with the text before at either end: the other
lines keep their colours, a line changed in place keeps its own shifted until the highlighter restyles it, and the
highlighter is given the change, as for a key.

**A `TextEditor`'s highlighter is told which lines it must style.** Through the highlighting seam (SPI), each
update now carries the `window` of lines the editor keeps tokens for, and `linesToStyle`, the lines of it the editor
holds no tokens of the update's text for: lines never styled, lines an edit put in or edited in place, and lines
scrolled out of the window and back. A highlighter that published only the lines its parse said changed left those
last drawn plain until each changed again. `publish` returns a `TextEditorPublishOutcome` rather than a `Bool`:
`.kept(lines)`, the lines the window held, which a publish for lines the editor has scrolled away from leaves
empty, or `.refused`; a highlighter that tested the `Bool` tests `isRefused`.

**A list's locked rows stay locked when they are out of sight.** A row's `.deleteDisabled()`, `.moveDisabled()` and
`.selectionDisabled()` were known to its `List` only while the row was drawn, so once the mouse wheel had scrolled the
cursor row away, Delete deleted a `.deleteDisabled()` row and Ctrl+Down moved a `.moveDisabled()` one, a drag of the
selection carried a pinned row that was off screen, and Select All or Shift+End selected the `.selectionDisabled()`
rows off screen. A list now remembers what each row refused by its id until the row draws without it or leaves the
data, and the keys that act on rows it has never drawn (Delete, the move keys, Select All, a Shift range) look at those
rows first, without drawing anything. Select All over a long list pays for that once, on the key. Up/Down still pass
over a `.selectionDisabled()` row only once it has been drawn.

**A link in a `Text` read in a subtree's language opens what it says and breathes when focused.** A key-made `Text`
with a link, under `.environment(\.locale, …)` naming another language, routed its links by the runs of the app's
language: a translation with its link in another run crashed, one that swapped two links opened the other, and a
focused link had no focus look in colour. The links are now the ones drawn.

**A `Stepper` drawn where one over another value type was steps its own value.** Two steppers at one place, say an
`AnyView` choosing between one over an `Int` and one over a `Double`, kept the first one's handler: the arrows
stepped the old binding within the old bounds while the read-out showed the new value.

**A `Form`'s `ForEach` rows keep their controls' state by element.** In `Form { ForEach(items) { … }; Button("Add")
{ … } }`, removing an item left its row's drawn state (a `DisclosureGroup`'s expansion, a field's caret, the focus)
to the row that took its place, and each item added moved the button after the loop, so the focus left it at every
press. A loop's rows are now drawn under their elements' ids, as in a `VStack`, and what follows the loop keeps its
place, in both form styles and in a long windowed columns form.

**A view after an `if` keeps its state when a view of several is drawn whole.** In an `AnyView` of a view whose
body is `Text("a"); if c { X(); Y() }; Counter()`, as in a menu's items, the counter was reset, and lost the focus,
each time the `if` flipped, and so did a view after a builder `for` loop when the loop grew. It now keeps its place,
as in a stack and in SwiftUI.

**A theme's button style now wins over a primitive button style set further out.** `Theme(buttonStyle:)` on a panel
inside a `.buttonStyle(.glass)`, or inside any custom `PrimitiveButtonStyle`, left the panel's buttons in the outer
style. It now ends it, as `.buttonStyle(_:)` naming any style does.

**A button under a primitive button style keeps its focus id and its menu.** Under `.glass`, `.glassProminent` or a
custom `PrimitiveButtonStyle`, the button `Button(configuration)` builds lost the button's `.focusID(_:)`, so
`focus(id:)` found nothing, and a pop-up menu's trigger opened on the release instead of the press. A press in a
menu also closed the menu twice. `Button(configuration)` now keeps all three as the button had them.

**A custom `ButtonStyle` can hold `@State` of its own.** Its body is drawn where the button keeps its own focus id,
hover and press, and its first `@State` took the button's focus id: of another type, the two replaced each other
every frame and the style's state reset; of the same type, a debug build stopped on an assertion. The button now keeps
its own state where no view's `@State` can reach it.

**A table's column menu, scrolled sideways, marks every column the table shows.** It took the columns on screen for
the shown ones: a column scrolled out of sight was listed unmarked, choosing it did nothing, and with one column in
sight Hide and every entry were off. Choosing a shown column off screen now hides it.

**A table keeps a column's cell state and its `.fit` width with the column when a condition before it changes.**
Both were kept by the column's position among the columns built, so `if showKind { TableColumn("Kind", …) }` turned
off handed the next column the `@State`, focus and memos of Kind's cells, and Kind's `.fit` width, which a check of
the rows on screen could accept: a `.fit` column then cut a long value off screen with `…`. They are now kept by the
column's place in the column closure, as a width a user gives a column already was.

**A table whose columns all show a key path redraws every row when the columns move or change key path.** A table
of `Equatable` rows keeps each row's line while the row is unchanged, and moving a column in its customization,
choosing a column's key path by a condition (`value: metric ? \.metres : \.feet`) or swapping two like columns with
an `if`/`else` left every kept row drawing the old cells under the new headers, until its data changed.

**A frame larger than its space now keeps its content in sight.** A frame whose minimum or fixed size is more than it
is given, such as `.frame(minWidth: 400, minHeight: 300)` on a macOS root view, is cut to the space it has, and its
alignment placed the content in the whole frame before the cut: centred, the content was drawn past the edge, and on
an 80×24 terminal that frame drew a blank screen. Its alignment now places the content in the part that is drawn, so
`Text("Hello world").frame(minWidth: 20)` in 12 columns draws `Hello world` rather than `    Hello wo`.

**A focused scroll bar is no longer drawn again for every key.** A focused `ScrollView`'s or `TextEditor`'s bar
breathes, and the bar kept from one frame to the next was kept only while the breath's clock had not moved, which it
does every 50 ms: so a key typed in a focused editor drew the bar again, and its sixteen frames of breath, almost
every time. The bar is now kept until something it is drawn from changes, and shows the frame of its breath the clock
is on. A bar under a still focus style (`.selectionIndicatorStyle(.none)`, or breathing off) also now dims and
brightens with the window as the other focus indicators do.

**A `TextEditor` bound to an `AttributedString` and an `AttributedTextSelection` keeps its selection binding while the
find bar is up and after it closes.** The bar showed its matches through a selection of its own, put in the app's
place, so from the moment it came up the app's selection was neither written nor read: a Bold button acting on it
made bold whatever was selected before Ctrl-F.

**Replace All no longer hangs on a large text, and keeps the styling between its matches.** It replaced each match
in a fresh copy of the whole text, found by walking it from its start, so thousands of matches in a large document
took minutes; it is now one edit, made in one pass, and still one step to undo. In an editor bound to an
`AttributedString`, every character from the first match to the last took the attributes of the first: each match
now takes those of the text it replaces, and the text between them keeps its own. Replace (of the current match)
is made the same way, so it no longer lays the whole document out again either.

**Typing with the find bar up costs what it costs with the bar down.** The bar's matches were found again by a
search of the whole document every time the editor's view was evaluated, twice, so with the bar up each key in a
large text was a search of all of it: 1.6 s a key in a 3.2 MB document with a match on every line. They are now found
once for a query and carried through each edit, searching again only the lines it touched.

**What a `GeometryReader`'s content draws follows a size that an `onAppear` or `onChange` moved in the same frame.**
When an effect changed the layout around a reader, such as an `onAppear` loading a saved sidebar width, the frame was
laid out again with the reader at its new size, but kept rows below the reader were drawn as they were at the old one,
and stayed so until something else drew a frame; the next frame then also redrew them for no reason. They now follow
the size the frame is written with.

**A `ForEach` row reading an `@Observable` its parent's `body` doesn't read keeps updating.** A row closure such as
`Text(selection.current == item.id ? "▶" : " ")`, where only the closure read `selection`, stopped being redrawn
after one change that left every row on screen as it was (a selection moved to a row out of sight, a title set for
one): the next change, even to a row in sight, was never drawn. The rows checked after such a change now go on
watching what their closure read.

**`.animation(_:value:)` animates a change in a row that was kept from an earlier frame.** A `ForEach` row over
`Equatable` data, a view in `.equatable()` or a view of the app's own that TUI kept forgot the value its
`.animation(_:value:)` watched on the first frame something else on the page drew, so the next change to it jumped
to its end instead of animating. The value is now remembered for as long as the view is on screen, drawn or kept, and
a view that left and comes back still appears without animating.

**A number that is not a number, infinite, enormous or negative no longer crashes the app, wherever it is handed
in.** About thirty places turned an app's `Double`, `UnitPoint`, `Date` or stated length into a count of cells or
nanoseconds with a conversion that traps, and an ordinary slip reached each: `index / (count - 1)` with one element,
`remaining / rate` with a rate of 0, a ratio guide on a row squeezed to no height. Each now gives the least surprising
answer instead. A wait that is infinite is never: `LongPressGesture(minimumDuration: .infinity)` (SwiftUI's idiom for
"tell me while it is pressed"), `tooltipDelay = .infinity` and an animation, completion or scroll glide longer than
292 years never run out, where a wait just short of that used to fire at once. An anchor that is not a number is the
leading edge, and one that is infinite reaches as far as anything can (`scrollTo(_:anchor:)`,
`.scrollPosition(id:anchor:)`, `.defaultScrollAnchor`, `.viewAligned(anchor:)`, `LayoutSubview.place`,
`gridCellAnchor`, `popover(attachmentAnchor: .point(_:))`, `matchedGeometryEffect(anchor:)`,
`.transition(.scale(anchor:))`, which also stays inside its view). A timer over an interval that ends at an infinite
`Date` (`Text(timerInterval:)`, `Text(_:style: .timer)`, `ProgressView(timerInterval:)`, the timer and stopwatch
formats) shows the longest face there is and stops. A negative size is none (`Spacer(minLength: -1)` on its own, a
`safeAreaInset` spacing past both views), and a huge stated length is held to 65,536 cells as every other one already
was (`VStackLayout`, `HStackLayout` and `FlowLayout` spacing, a `Spacer` or `GridItem` changed after `init`, a
visual-effect or transition offset, nested `safeAreaPadding`, a decoded `TableColumnCustomization` width). End on a
size-to-fit split view's divider widens the sidebar as far as the detail's minimum allows. Also: a separator alignment
guide, a canvas shadow's offset, a curve editor's point and its percent read-out (held to 0...100%), a custom
animation at an infinite speed, a symbol effect's near-zero speed, a huge spring-loading delay preference, a pixel
mouse geometry reply past any display, and `.opacity(.nan)`, which drew whole over the page and not at all over a
sibling and is now invisible on both. `TimelineView(.animation(minimumInterval:))` with an interval below a `Date`'s
resolution no longer hangs its first frame, nor does a `ProgressView(timerInterval:)` whose start is too far off
for whole seconds.

**F1's list of shortcuts can show the keys you read with `onKeyPress`.** Give an `onKeyPress` on a key or a set of
keys a `label`, TUI's own parameter, and F1's list shows its keys under that label in the page's section while its
view is on the screen: `.onKeyPress(keys: [.leftArrow, .rightArrow], phases: .all, label: Text("Steer")) { … }` is
listed as `← →  Steer`. The label defaults to `nil`, so code written for SwiftUI is unchanged and lists nothing. The
`onKeyPress` on a set of characters and the one on any key take no label, since they name no key to show.

**An app can send a key through the whole input chain with `@Environment(\.postKeyEvent)`.** A key posted with it
goes where a typed key goes, the `onKeyPress` handlers round the focused view, the focused control, the status bar,
the shortcuts and TUI's own keys, so another device's presses, such as a gamepad's buttons, can stand for keys
without a path of their own. Its phase is delivered as posted: a release reaches the handlers that ask for `.up`
even where the terminal reports none. It is delivered once the frame being drawn is on the screen, and a key posted
from inside a key handler waits for the next frame instead of running the chain inside itself.
`FocusManager.dispatchKeyEvent(_:)` is unchanged: it is the focus system's layer alone.

**An object handed down with `.environment(\.key, object)` no longer makes every body below it run every frame.**
A value set under an `EnvironmentValues` key that isn't `Equatable`, such as a model object or an `Optional` of one
set to `nil`, couldn't be compared from one frame to the next, so nothing below it was ever kept: beside a running
`TimelineView` every body under it ran twice a frame, 125 times a second where 4 ran without it. It is now compared as
SwiftUI compares it: an object by identity, so a mutation inside the object (observed, for an `@Observable`, by what
read it) is not a change to the environment, and a different object is. A value nothing can compare, such as a
closure or a struct that isn't `Equatable`, still can't be.

**Below an environment value that can't be compared, each body runs once a frame, not twice.** Under a value set
with `.environment(\.key, value)` that nothing can compare, a closure or a struct that isn't `Equatable`, no memo
keeps anything, so each of an app's views below it ran its `body` to be measured and again to be drawn, every frame.
The body a measure ran is now kept for the draw that follows it.

**`Tools/Web/build.sh` builds your app's browser page into your package, not into TUI's checkout.** With
`--package-path`, the module, its resources, the manifest and a copy of the page now go into the package's own
`.build/web/`, or the directory the new `--site DIR` names, and `Tools/Web/serve.py --site DIR` serves them. Before,
they always went into TUI's `Tools/Web/site/`, replacing the Example's build there, and into a SwiftPM checkout of TUI
when the app depended on it by URL. A directory `--site` names must be empty or an earlier build's; a rebuild replaces
only that build's module and resources. With no options the script builds the Example into `Tools/Web/site/` as
before.

**A key in a `TextEditor` taller than its view no longer draws the scroll bar again.** The bar, and the frames of its
breath while the editor holds the focus, were drawn afresh every frame, every cell spelled anew, though a key rarely
moves the scroll: a sixth of a key's cost in a 3.2 MB document. The editor now keeps its bar with what it was drawn
from, as a `ScrollView` keeps its own, and draws it again only when one of those moves. A key in that document costs
about a fifth less, and in a wrapping editor of two thousand lines about a third less (release build).

**A scroll view disabled while it does not hold the focus shows a pinned thumb without colour.** Its bar was kept
from the frame before, when the view was enabled, so on a terminal with no colour the thumb stayed `▒` where a
disabled view's is `░`.

**A menu item whose key is Return or Escape shows `↩` or `⎋`.** A bare Return or Escape is the default or the cancel
action, in SwiftUI and here, and `KeyboardShortcut.displayString` was `nil` for those two roles, so a menu row bound to
either, with `.keyboardShortcut` or `keyboardShortcutHint(_:)`, showed no key. They are now drawn as a macOS menu draws
them, and as the shortcut overlay already did: `↩` and `⎋`, or `Return` and `Esc` where keys are spelled out
(`TUI_KEY_SYMBOLS=0`) or in ASCII (`TUI_PLAIN_TEXT`). `displayString` is no longer optional, since every shortcut now
has one: drop a `?? ""` written after it.

**A table's or a list's selection menu is wide enough for each item's key.** A
`contextMenu(forSelectionType:menu:primaryAction:)` menu was drawn as wide as its widest title alone, so an item with a
key equivalent or a `keyboardShortcutHint(_:)` had its title cut to make room for the key (`Show in Fi… ⌃N`), where a
`.contextMenu` drew the same items whole. The question asked before the menu opens, whether its items draw anything,
held each item's key, and the menu then measured its rows without them. It is now as wide as each title and its key,
as every other menu is, and cuts a title only where the screen is too narrow.

**A focused `.focusable()` view shows that it has the focus.** It draws the standard focus tint behind its cells,
breathing on the same clock and in the same colour as a list's cursor row, where SwiftUI on macOS draws a focus ring
round it; until now it took Tab and the keys and looked exactly as it did unfocused. This changes the look of every
`.focusable()` view while it is focused. A view that already draws its own focus look, from `@FocusState` or
`\.isFocused`, should add `.focusEffectDisabled()` outside its `.focusable()` to keep only its own; the Focus System
article's "Your own focus look" shows the recommended ways. Cells that paint their own background, such as a filled
`Canvas`, don't show the tint. A control inside a focusable container still draws its own focus when it holds it, and
the container then draws none.

**A `TextEditor` draws marks: ranges of its text an app styles, such as a parse error's underline.**
`.textEditorMarks(_:in:)` gives the editors below a list of `TextEditorMark`s, each a range and the attributes to
draw it in, together with the text the ranges were found in. That text may be a few keys behind the editor's: the
editor carries the marks through its own edits since, so an app's parse can lag the typing without its marks landing
in the wrong place, and a mark whose text was deleted goes. Marks are drawn over the text, its attributes and its
highlighting, and under the selection and the find bar's matches, and are never written into the text. SwiftUI has
nothing like them; they are TUI's own, and public.

**A `TextEditor` can be highlighted by a styler of the app's own, through a seam that is SPI for now.** With
`@_spi(TextEditorHighlighting) import TUITextInput`, `.textEditorHighlighter(_:style:)` gives the editors below a
`TextEditorHighlighter`: a tree-sitter adapter, say, run in a task of its own off the main actor, which takes the
editor's text as it changes (every edit since the last as one change by whole lines, in UTF-8 bytes) and publishes
tokens for the lines on screen, which the editor draws over its text without writing them into it. The editor never
waits for it, and keeps a line's tokens, moved with the edit, until the styler publishes the line again. Being SPI,
all of it is outside the API stability policy and may change in any release, minor ones included, until it is made
public. The Example's Text Input page shows both: JSON highlighted through the seam, its brackets that don't match
marked.

**A `Canvas`'s text stays inside the canvas.** A glyph drawn at the canvas's right or bottom edge, `x: size.width` or
`y: size.height`, landed in the column or row past it, and a wide glyph in the last column ran a cell over, so the
canvas came out a cell wider or taller than its frame, and where its frame cut a wide glyph back the row was left a
cell short. A glyph that doesn't fit wholly inside the canvas is now not drawn, as the canvas already clipped
everything else it draws.

**Text drawn in a `Canvas` costs far less.** Each piece of text a canvas draws, with `context.draw(Text(…), at:)` or
`draw(_:in:)`, was laid over the canvas's cells by rebuilding and re-measuring every row of the canvas, so a treemap's
few dozen names cost more than all its fills. Each run of text now rewrites only its own row. A page-filling canvas of
40 fills and 40 short labels redrawn every frame takes 10.2 ms a frame where it took 17.4 ms (the same canvas without
its labels takes 5.4 ms); what it draws is unchanged.

**The help key shows a `help` written inside a `.focusable()` view.** Only a `.help` written outside the modifier
reached the keyboard: `Rectangle().help("…").focusable()` showed its tooltip under the pointer, but `?` showed nothing
when the view had the focus. A view now has one help however its modifiers are ordered; of a help inside the
modifier and one outside it, the inner one shows, as under the pointer. A help on a control inside a focusable
container, `Button("…").help("…")`, stays the control's.

**An `onMouseEvent` handler leaves the hover to the views inside it.** Its region was the control under the pointer,
so an `onHover`, `onContinuousHover` or `help` inside it, and a `Button`'s hover face, heard nothing, though the
handler returned `false` for every event; `onScrollWheel`, which is built on it, did the same. The handler now hears
the pointer come and go as `onHover` does, beside the views inside it, whatever it returns; presses are offered to it
as before.

**A click on a `.focusable()` view reaches what is inside it.** The modifier's click-to-focus (its `.edit`
interaction, one of the defaults) put a region in front of the view that took every left press and the hover, so a tap
gesture on the view, an `onHover` or `onContinuousHover`, a `help` tooltip under the pointer, and an `onMouseEvent`
inside it never ran, in whichever order the modifiers were written. As on macOS, the click now focuses the view and
reaches them too: `Canvas { … }.onTapGesture { location in … }.focusable()` runs its tap and takes the focus. A left
press focuses the view as it comes down, rather than on the release. A control inside the view that takes the click
as its own, a `Button`, keeps it, and the view doesn't take the focus from it.

**A toast fades over the page instead of out of a blank box.** A toast's fade was spent against its own surface,
which a floating layer paints opaque, so the frame a toast was posted on drew an empty box over the window, neither
the toast nor what was under it, and both its fades drew the toast coming out of and going back into that box. The
fade is now the toast's layer's: at the start of its fade-in and the end of its fade-out the window shows through
unchanged, and half way the two are mixed. Its buttons stay reachable throughout.

**A test can read the progress bar and the desktop notifications an app sends.** `TestApp.terminalProgress` is the
progress the app's views state with `.terminalProgress(_:)` (what a terminal that draws a bar is sent), or `nil` while
none states one, and `TestApp.desktopNotifications` lists the toasts posted on the desktop too, whichever route a
running app would send them by. Neither is on the screen, so a test could check only the model behind them.

**A `TestApp` draws toasts of its own, on its test clock.** A toast posted in a `TestApp` was stamped by the machine's
clock and faded by the test's, so its box was drawn blank over the window until the two clocks agreed, and again
after its time until real seconds had passed; and every `TestApp` in a process drew the same queue, so tests running
at once drew each other's toasts. Each `TestApp` now puts a queue of its own at `\.notificationService`, as it has
its own `@AppStorage` store and undo manager: a toast fades in from the instant it is posted and has gone once
`advance(by:)` has passed its fades and its duration. A running app still draws `NotificationService.current`. A
test sees what its app posts through `@Environment(\.notificationService)`; a post through
`NotificationService.current` goes to the process's queue, which no `TestApp` draws, so a test that read such a toast
on the screen should have the view post through the environment.

**A view's `.foregroundStyle(.foreground)` is the default foreground, as in SwiftUI.** It drew the style in force,
red under `.foregroundStyle(.red)`, where SwiftUI draws the default foreground whatever is above (#272727, measured on
macOS 15.8.3), and the levels inside it as the plain levels. It now states no style at all: text below draws the
palette's foreground, and a `Text`'s own or a view's `.secondary` inside it the palette's secondary tier. A `Text`'s own `.foregroundStyle(.foreground)` still draws the style in
force, as SwiftUI's does.

**A view's content level under a view's level replaces it, as in SwiftUI.** `VStack { … }.foregroundStyle(.secondary)`
inside a view with `.foregroundStyle(.secondary)` drew the outer secondary at half strength again, where SwiftUI draws
the plain secondary (#808080, measured on macOS 15.8.3); under `.secondary` below `.foregroundStyle(.red)`, an inner
`.primary` drew the secondary red where SwiftUI draws red. A view's level, and a shape's `.fill(.secondary)`, is now a
level of the style the level above it was a level of: the palette's tiers under a level of no style, red's under a
level of red or under `.red.secondary`, and under `.foregroundStyle(.red, .blue)` the primary red and the secondary
the named blue, through any level between. A `Text`'s own level is unchanged.

**A bold under a medium `fontWeight` stays medium, as in SwiftUI.** `Text("x").bold()` inside a view with
`.fontWeight(.medium)` drew bold, where SwiftUI keeps it medium (measured on macOS 15.8.3). TUI draws medium as it
draws regular, since a terminal has only bold, normal and faint and medium is far nearer regular, so the text now draws
normal, like the medium text beside it. The same goes for a Markdown `**` span, bold fragments of a joined text, a
view's `.bold()` nearer than the weight, and a text's own `bold().fontWeight(.medium)`. A view's `.bold()` farther out
than a medium or light weight does make a text's own `bold()` below it bold, as in SwiftUI, where TUI drew it faint
under a light weight; a text with no bold of its own still draws the weight.

**A bold under a light `fontWeight` stays light, as in SwiftUI.** `Text("x").bold()` inside a view with
`.fontWeight(.ultraLight)`, `.thin` or `.light` drew bold and faint, where SwiftUI draws it ultralight (measured on
macOS 15.8.3): a bold applies to the weight in force. It is now drawn faint, and so is a Markdown `**` span, a bold
fragment of a joined text, and a view's `.bold()` on either side of the light weight. A text's own `fontWeight` still
decides for itself, and a faint that is not a weight, a caption's or `.dim()`'s, still takes a bold.

**A `Text`'s own `.secondary` under a view's `.foregroundStyle(.secondary)` is the plain secondary, as in
SwiftUI.** It was the view's secondary at half strength again, a paler grey than SwiftUI draws (#808080, measured on
macOS 15.8.3), and the text's `.primary` there was the view's secondary rather than the foreground. Under a view's
content level with no style above it, a text's own level now replaces that level, every level from `.primary` to
`.quinary`, for a fragment of a joined text too. Under a view's level of a colour, such as a `.secondary` below
`.foregroundStyle(.red)`, a text's own level is still a level of that secondary red, as in SwiftUI.

**A focused `List` whose rows are redrawn every frame no longer builds its cursor row's whole breath each frame.**
The cursor row of a focused list breathes by handing the run loop every frame of its breath, sixteen copies of its
lines, to replay between renders. In a list of live previews, a `TimelineView` in each row, the list is drawn again
on every tick, before any of those frames is replayed, and building them was a tenth of the frame. Where the list
will be drawn again before its breath next steps, it now draws the row at the step on screen and builds no other;
what the terminal shows is unchanged.

**Building TUI on macOS requires the macOS 26 SDK (Xcode 26, or Command Line Tools 26); macOS 15 still runs it.** An
app built with Xcode 26's SDK still deploys to macOS 15, as before. The macOS 15 SDKs (Command Line Tools 16.x), never
supported, no longer build TUI at all: a Mac with only those Command Line Tools needs Xcode 26 or Command Line Tools
26. With that SDK alone, `AttributedString`'s `subscript(_:)` with an `AttributedTextSelection` is always there on
macOS 26, and a change made through `transform(updating:body:)` is tracked by Foundation on macOS 26 in every build.

**A disabled `TextEditor` or `Slider` no longer looks live on a 16- or 256-colour terminal.** Both fade their
colours toward the page when disabled, but such a terminal can round the faded colour to the same palette entry as
the original: an editor's highlighted run then drew exactly as enabled, and at 16 colours a `.knob` or `.marker`
slider with its value hidden drew disabled exactly as enabled on the Man Page, Silver Aerogel and Solid Colors
palettes. Where the terminal rounds away the fade of a colour the control actually draws (a run the editor shows,
the colours a slider's track style and ticks are drawn in), the control is now drawn faint, as other disabled controls
already are where their grey rounds to their enabled colour; a colour it doesn't draw, a hidden value's grey
included, doesn't count. Enabled controls, and 24-bit terminals, draw as before.

**`TUI_PLAIN_TEXT=transliterate` is a supported option, no longer an experiment.** Spelling other scripts in Latin
letters before layout, for a terminal that shows only ASCII, keeps its default (off unless named) and does what it
did, but it now falls under the API stability promise, as the rest of the end-user variables do. `TUI_PLAIN_TEXT`,
with its `1` and `0`, moves from the variables for developing TUI to the end-user table, so an app's generated man
page and the EnvironmentVariables article list it under Text and language. No experiment is left.

**A frame no longer reads the whole process environment.** Each frame looked up which terminal it was drawing for, to
say which underline styles it draws, and that copied every environment variable the program has. The answer is now
read once, when the app starts drawing, as the rest of what TUI knows about the terminal is.

**Frames under a running `TimelineView` spend less time comparing environments.** Each view kept above a running
timeline is checked against the environment it was built under at every frame, and the first such check in a frame
sorted that environment's values in a way that copied each of them many times over. It now sorts only their keys, and
a frame of an animated tile launcher costs about 7% less.

**A `ZStack` beside a running `TimelineView` no longer composites its layers again at each entry when none moved.** A
launcher's animated preview, a picture with its loop's timeline in a `ZStack`, was put together cell by cell at every
frame of every preview on the page. While a timeline is live the composite is now kept with everything it was made
from and served while none of it has changed. `TUI_KEEP_TIMELINE_ANCESTORS=0` turns this off with the rest of the
timeline's keeping, to compare.

**A `.frame(width:height:)` no longer measures what it holds.** A frame pinned on both axes is its pins whatever its
content measures, and its measure now says so without asking the content. Beside a running `TimelineView` this is most
of what an entry cost: a timeline's measure reads the clock, so every measure above it was taken again at each entry,
and a launcher's row of bordered tiles, each with an animated preview in a fixed frame, measured every tile through
its focus modifiers and its border at every frame of every preview. Now the measures above a pinned frame are kept.
What the frame holds is drawn as before.

**A disabled `TextEditor` fades its coloured runs too.** Its plain text went to the palette's tertiary tier, but a
run's own colour, in an editor over an `AttributedString` or one with highlighting, kept its full strength, so the
editor was half faded and its coloured words looked live. Now each run's ink, background and line colours keep their
hue faded toward the page, as a disabled slider's accent is; re-enabled, they are drawn as stated. SwiftUI's disabled
`TextEditor` (macOS 15) fades nothing at all; this is a deliberate difference, the owner's ruling of 2026-11-19
(Deliberate deviations from SwiftUI, T13).

**A focused `List` draws its selected row once a frame.** The row under the cursor of a focused list, where it
was selected, was drawn twice on every frame on which nothing could serve it: once at the standard background
prominence, while the list learned whether its rows overflow, and again when the list raised it. In a list of live
previews that was one row in eight drawn again every frame, 5% of the frame. The row is now raised before it is
first drawn.

**Of two of a `Text`'s own modifiers of one kind, the first written wins, as in SwiftUI.** TUI kept the last:
`Text("x").foregroundStyle(.red).foregroundStyle(.blue)` drew blue where SwiftUI draws red, and the same went for
`font`, `fontWeight`, `bold`, `italic`, `underline`, `strikethrough`, `textScale`, `dim`, `lineLimit` and
`truncationMode` (measured on macOS 15.8.3). A level written first is now a level of the style written after it
(`.foregroundStyle(.secondary).foregroundStyle(.blue)` is the secondary blue), and a `bold()` before a weight applies
to it (`.bold().fontWeight(.light)` is light). `fontWeight(nil)` is the font's own weight, over a weight or bold
stated after it or above it, as in SwiftUI, where it was no statement at all. `customAttribute(_:)` goes the other
way, as SwiftUI's does: the last of a type written wins, a whole concatenation's over a fragment's own. An app that
restyled a `Text` by writing a second modifier after the first should write the one it wants first, or put the
second on a view around it.

**`Text`'s own `foregroundStyle(_:)` takes any `ShapeStyle` and returns a `Text`, as SwiftUI's does, and its
`.secondary` is a level of the style above it.** It took only a `Color`, so `Text("x").foregroundStyle(.secondary)`
was `Color.secondary`, the palette's fixed secondary tier, whatever style was stated above; SwiftUI draws the stated
style at the secondary level there (red at half strength under `.foregroundStyle(.red)`, measured). The content levels
(`.primary` … `.quinary`) now resolve where the text is drawn, against the style in force: with none stated they are
the palette's tiers, as before. A level named by `foregroundStyle(_:_:)` plays no part in a text's own, as in SwiftUI.
Any other style — `.tint`, `.foreground`, a gradient — keeps the result a `Text`, so it can be interpolated into
another; a gradient on one fragment bands across the text. A `Text` is no bigger and no slower for it.

**An outline `List` whose selection cannot name its rows draws them.** A `List(_:children:selection:)`, or a
`List` holding an `OutlineGroup`, whose selection's type was not its nodes' id type drew no rows at all, where a flat
list's rows are drawn and select nothing. The outline's rows are now drawn the same way, and a debug build warns
about the mismatch as it does for a flat list.

**A `Toggle`'s subtitle takes a stated `.foregroundStyle`.** The second view of a toggle's label, the subtitle
under its title, was always drawn in the palette's secondary tier, over any style the app stated: under
`.foregroundStyle(.red)` the title was red and the subtitle grey. It is now secondary only where no style is stated,
and takes a stated one whole, as the title does, as SwiftUI's does on macOS 15.8 (checkbox and switch, bare and in a
grouped `Form`; under `.foregroundStyle(.red, .blue)` both lines are red).

**A click after a Tab into a `LazyVStack` keeps the focus where it was clicked.** Where a Tab into a lazy stack in a
`ScrollView` and a click on one of its rows were read in the same batch of input, before a frame between them, the
frame after took the focus back from the clicked row to the stack's first row, the row the Tab alone would have
landed on; an arrow key or a `@FocusState` write after the Tab was undone the same way. The frame now carries a Tab
on only while the focus is still where the Tab left it.

**A view with a running `TimelineView` in its `.background` or `.overlay` no longer composites the two again at each
entry.** The view itself was already served, but the modifier put it over (or under) the timeline's layer afresh at
every entry, cell by cell: three quarters of each frame of a game board with its loop in its background, for the
picture the entry before had made. Now, while a timeline is live, the composite is kept with everything it was made
from and served while none of it has changed. `TUI_KEEP_TIMELINE_ANCESTORS=0` turns this off with the rest of the
timeline's keeping, to compare.

**A `List` or a `Button` beside a running `TimelineView` is no longer drawn at each of its entries.** Their rows'
and labels' content was already served, but the controls themselves drew again whole at every entry: a list listed,
laid out and composed its rows, and a button measured and drew its label, about a fifth of each frame of a launcher
of previews beside a 60 Hz loop. Now, while a timeline is live, each is memoized at its own identity as a view of the
app's own is, and served while its value, its environment and what it reads are unchanged, as in SwiftUI. A control
that holds the focus is still drawn at each entry, as it was. `TUI_KEEP_TIMELINE_ANCESTORS=0` turns this off with the
rest of the timeline's keeping, to compare.

**Tab reaches a link in a `Text` far down a `LazyVStack`.** A link inside a `Text` is a focus stop, and an eager
`VStack`'s Tab and Shift-Tab land on one however far off screen, but a lazy stack's way in passed it by: the rows it
looks through for something to focus are drawn with no mouse handling, and a link was a stop only where there was
some. Tab from a button over a thousand lines of text went to the scroll view, not to the link on line 300. A link is
now a stop wherever there is a focus system, as a button is; one on screen takes a click and shows the pointing hand
as before.

**A menu opened from the keyboard keeps its highlight until the pointer moves.** A pop-up menu, a context menu, a
submenu, a picker's drop-down or a field's suggestions opened by a key under a pointer resting where it last moved to
lit its first row, and then took the row under the pointer, so Down and Return went on from a row the keyboard never
chose. It now takes no row from the pointer until the pointer moves, as a macOS menu does; the first move lights the
row under it, the row it rested on included. A menu the pointer opens follows it as before.

**What a frame changes under the resting pointer after it is drawn is drawn before the next key.** A frame's hit
regions re-resolve the hover under a pointer that has not moved, and what that changed — a menu's highlight moved to
the row under the pointer, a hover lit — waited for a frame while a key already waiting was handled first: Return
could run a menu row the screen had not lit. The run loop now draws that frame before it reads on.

**A click forgets where the pointer last moved to when it lands elsewhere.** TUI counted the pointer as resting on
the cell of its last reported move until the next one, so with the moves between unreported, a menu opened by a click
on its trigger could light the row under that old cell as it opened: Down then went to the row after it, and Return
ran that. A press, a release or a wheel tick at another cell now says the pointer has left it.

**A `TimelineView`'s entry runs the timeline's content, and nothing above or beside it that has not changed.** At
each entry of a running timeline TUI ran the `body` of every view above it, up to the app's (and whatever their
initialisers made, sixty times a second under `.animation`); drew again the view a timeline in its `.background` or
`.overlay` is drawn behind or over, `.equatable()` or not; and handed a slower timeline's content a new date whenever
anything else drew, so `.animation(minimumInterval: 0.2)` beside a 60 Hz timeline stepped at 60 Hz. Now, as in
SwiftUI, the views above a live timeline keep what their bodies built from one entry to the next while their values,
environment, state and what they read are unchanged; a timeline's entry drops only what is drawn inside it; and an
animation schedule's content sees the date of its current entry until the next one. `TUI_KEEP_TIMELINE_ANCESTORS=0`
runs the bodies above a timeline at every entry again, to compare.

**A `Table`'s column titles take the `.foregroundStyle` in force.** They were drawn in the palette's secondary tier
whatever the style said, while the cells below took it; now the titles take it too, as SwiftUI's header does (measured
on macOS 15.8). A chosen column's title keeps the selected row's colours. Only a style the app states: a container's
default for its text, such as a grouped form value's secondary tier, leaves the titles their own colour, as it leaves a
button's label or a field's text.

**A `ColorPicker`'s label takes the `.foregroundStyle` in force.** It was always drawn in the palette's secondary tier;
it still is where no style is stated, and takes the style where one is, as SwiftUI's label does (measured on macOS
15.8).

**A button's label, and a `Link`, take the `.foregroundStyle` in force.** A button's label was drawn in its style's own
colour whatever `.foregroundStyle(_:)` said, in every button style, and a `Link` in the accent; now the label is drawn
in the style, as SwiftUI's borderless, plain and link buttons and its `Link` draw it (measured on macOS 15.8), and as
its bordered buttons do on iOS. A `.style(.control(.button))` foreground still wins over it, and a destructive role's
colour over both. What is built from buttons follows: a `DisclosureGroup`'s label, a `Menu`'s, a `.button` toggle's,
a `.menu` picker's value and a `NavigationLink`. Hover still lifts the colour in force, and a disabled button still
draws in the tertiary tier. A button in a form value's place keeps its own colour under the value's secondary tier,
as a field does. The search field's ✗ is drawn in the secondary ink it always asked for. macOS draws its bordered
buttons, menus and pop-ups with AppKit, which ignores the style; the compatibility guide lists them.

**A `TextField`'s and a `SecureField`'s text take the `.foregroundStyle` in force.** What was typed (or its bullets)
was drawn in the palette's foreground whatever `.foregroundStyle(_:)` said, in every field style and in a vertical
field; now it is drawn in that style, as SwiftUI's is (measured on macOS 15.8). A `.style(.control(.textField))` or
`.style(.control(.secureField))` foreground still wins over it. The prompt, the caret and the selection keep their own
colours, as SwiftUI's prompt does, and a disabled field still draws its text in the palette's tertiary tier. A field
as a form value keeps its own colour under the value's secondary tier, as SwiftUI's does. A `TextEditor` keeps its own
there too.

**A form value takes a stated `.foregroundStyle` whole.** A `LabeledContent`'s value in a grouped `Form` or a list's
row is drawn in the secondary tier; under a `.foregroundStyle(_:)` it took a secondary level of that style, and now it
takes the style itself, as SwiftUI's value does (measured on macOS 15.8). Without one it is still the secondary tier.

**The focus goes straight to a `LazyVStack`'s row on the way in.** Where a Tab or Shift-Tab went into a lazy stack
whose rows on screen had nothing to focus (below), the key moved the focus to the scroll view or the control past the
stack, and only the frame after it found the row and took the focus on: one frame showed it on the way, an
`.onChange(of:)` of a `@FocusState`, and a `@FocusedValue`, saw it pass through there, a text field there saw
`onEditingChanged` fire, and a key typed in the same instant as the Tab went to it. Now the frame before the key walks
the stack in wherever the focus stands beside it, so the key lands on the row. The price: a stack with nothing to
focus has all its rows asked once, on the first frame the focus stands beside it, and again only when its data
changes (a button over 10,000 lines of text: 10,014 rows built on that frame). The first key after launch, read before
a second frame is drawn, and a Tab behind another key in the same batch that moved the focus, still go the old way,
with no frame showing the focus on the way.

**Tab from a control above a `LazyVStack` in the same `ScrollView` reaches the stack's first row however far
down.** With a button over the stack — `ScrollView { VStack { Button(…); LazyVStack { … } } }` — Tab from the button
looked no further than 64 rows into the stack for a row with something to focus, and past more rows with nothing to
focus it left for the scroll view; Shift-Tab from a button under the stack likewise. And Tab from outside the scroll
view passed no more than 64 views with nothing to focus over the stack. Both now go however far, as in a `VStack`.

**Tab finds a `LazyVStack`'s first row under a header in its `ScrollView` too.** The way into a lazy stack from
outside its scroll view (below) worked only where the stack was the scroll view's whole content. Under a header with
nothing to focus — `ScrollView { VStack { Text("Header"); LazyVStack { … } } }` — Tab stopped on the scroll view when
the rows on screen had nothing to focus, and landed on the first row on screen when they had, instead of going on to
the stack's first row with something to focus; Shift-Tab past a footer likewise. Now a stack among other views of the
scroll content is walked into as one that is the content is; a header or footer with a control keeps the focus on
that control.

**A disabled vertical `TextField` looks disabled wherever a one-line one does.** A disabled field drawn without
colour, or in a palette whose dimmed text is its normal text at 16 colours, is drawn faint; a field made with
`axis: .vertical` was not, and looked enabled there. It is now drawn exactly as a disabled one-line field is.

**A `TextField` or `SecureField` written directly in a `Form` puts its title in the label column.** It was a plain
row, drawn full width, whose title was only the empty field's hint, so the row lost its title as soon as anything was
typed. Now `TextField("Name", text: $name)` in a form is a field row, as in SwiftUI's form on macOS: the title in the
label column, right-aligned with the others (leading the row in a grouped form), and the field in the value column,
the same row `LabeledContent("Name") { TextField("", text: $name) }` draws. As in SwiftUI, the title is then not also
the hint: an empty field shows its prompt, or nothing. A field with an empty title sits in the value column, and
`.labelsHidden()` hides the title altogether.

**Tab into a `LazyVStack` from outside its `ScrollView` lands on the stack's first row, and Shift-Tab on its
last.** Coming in from the control before the scroll view, the focus landed on the first row on screen, and Shift-Tab
from the scroll view or the control after it on the last row on screen, then went round only those rows, as SwiftUI's
lazy stack does. It now lands on the stack's first or last row with something to focus, however far off screen and
past however many rows with nothing to focus, and scrolls it in, as in a `VStack`; a stack with nothing to focus is
passed by. The rows looked at on the way run no `onAppear`, so a "load more" on the last row runs only once it is on
screen. Rows whose controls have an explicit `.focusID(_:)` are now walked like any others: the arrows and Tab could
leave the stack for a control outside it before reaching its last row.

**A `TextEditor`'s text takes the `.foregroundStyle` in force.** It was drawn in the palette's foreground whatever
`.foregroundStyle(_:)` said, over a `String` or an `AttributedString`; now it is drawn in that style, as SwiftUI's is
(a gradient gives its one representative colour). In an editor over an `AttributedString` a run's own
`foregroundColor` still wins, as in a `Text` of the value. The selection, the caret and the find bar's matches keep
their own colours, and a disabled editor still draws its text in the palette's tertiary tier.

**`.border()` hugs what it borders: padding is the inset, as in SwiftUI.** A border used to put a blank cell of its
own between the content and the line, on the left and the right, so `Text("Hi").border()` was 6 cells wide and
`.padding(1).border()` could not give one cell of room — it gave two. That cell is gone (the owner, 2026-11-17):
every bordered view loses one cell inside its line on each side, and the padding before the border is the only room
between them, as SwiftUI's `content.padding(n).border(...)` reads. **To keep the old look, add `.padding(.horizontal,
1)` before `.border`** — `Text("Hi").padding(.horizontal, 1).border()` draws exactly what `Text("Hi").border()` did.
Each ring of `width:` is now just its line. The line still goes round the content rather than over its edge, since a
terminal cannot stroke a line over text. TUI's own chrome — menus, popovers, notifications, a `GroupBox`'s box, a
grouped `Form`'s sections, the bordered text field styles — keeps its room and looks as it did.
`.backgroundStopsAtContent()` is gone: it kept the border's blank cell clear of a background, and there is no such
cell left to keep clear. With `.padding(.horizontal, 1)` before `.border()` for the old look, a background written
after the padding reaches the line as the padding's own, and one written before it stops at the content:
`.background(m).padding(.horizontal, 1).border()` is what `.backgroundStopsAtContent()` drew.

**A frame that changes nothing under a fade no longer blends the fade again.** The rows under a translucent layer
that is blended at the screen itself (a `.opacity`, a translucent colour, a `Color.clear` under a `TimelineView`)
were taken apart and blended on every frame the app wrote, changed or not. A game's loop that asks for a frame sixty times a second
over a board that moves once a second spent over a third of each frame there. Each row's result is now kept and used
again while its line and the claims over it are what they were; what is written to the terminal is unchanged. The
same now holds under a sheet or an alert: the page below it is veiled, and its fades blended, only where a row
changed, where every row of it was veiled again on every frame the dialog was up (about a tenth of such a frame).
And the dialog is drawn into the rows below it without taking each of them apart again: where it lands on a row is
worked out once and kept while the row and the width of the dialog's line on it are what they were, whatever the
dialog draws there, which was another tenth of a frame under a sheet.

**Arrows Follow Layout goes through a scroll view's content before leaving it.** With `TUI_ARROW_FOCUS=geometric`,
Up from the top row on screen in a `ScrollView` went to a button above the scroll view instead of the row just above
the viewport, in a `VStack` or a `LazyVStack` alike, and Down at the bottom or Left and Right at the sides did the
same wherever the control outside lay as near: a row out of sight lies, on screen, where the controls around the
scroll view are drawn. An arrow now prefers a control in the same scroll views as the focused one, out of sight or
not, and scrolls it in; it leaves the scroll view only when nothing in its content lies that way. Only along the axes
the scroll view scrolls: Right from a row of a vertical list goes to the button beside it, not to a control far down
the list that lies further right.

**`TextEditor` edits an `AttributedString`.** `TextEditor(text:selection:)` takes a `Binding<AttributedString>` and an
optional `Binding<AttributedTextSelection>`, as SwiftUI's does on macOS 26. The text is drawn in its attributes as a
`Text` of it draws them: colours, bold for semibold and heavier fonts, faint for light and lighter ones, italic,
underline and strikethrough, a link in the accent and underlined. Every edit is made in the value in place, so the
characters around it keep their attributes; typed text takes those of the character before the caret (a paragraph's
first character's at its start, a selection's first character's over it), or the typing attributes the app gave an
insertion point; text moved by a drag keeps its own, as an `NSTextView`'s does; undo brings attributes back with the
characters. A value the app writes, such as one it recoloured,
is taken whole: its characters are read and compared with the editor's, about 0.2 ns a character, and the lines on
screen are styled again.

**A paragraph's `lineHeight` in an `AttributedString` is drawn, in whole rows.** `string.lineHeight =
.multiple(factor: 2)` compiles and draws as SwiftUI's spelling does, crudely: a terminal row is a whole line, so each
line of the paragraph takes its factor's rows, rounded half away from zero (1.5 and 2 take two, 2.5 and 3 three, 1.2
one, at most eight), the rows past the first blank, and nothing follows a text's last line. The presets (`.normal`,
`.tight`, `.loose`, `.variable`), `.leading(increase:)` and `.exact(points:)` take one row: a row's height in points is
the terminal's font's, which TUI does not know. On Apple platforms the attribute and `AttributedString.LineHeight` are
Core Text's own, macOS 26 only as in SwiftUI, and Core Text gives no way to read a factor back, so TUI compares the
value with each multiple of 0.05 from 1.5 to 8.45, and any other factor draws one row there; before macOS 26 a program
cannot set a line height, as in SwiftUI. On Linux, Windows and WebAssembly TUI declares the same names itself and reads
every factor. It belongs to a whole paragraph, as `alignment` does. A `Text` puts the blank rows after each line, on top
of `.lineSpacing(_:)`'s, and measures them; a `TextEditor` puts them after each row of the paragraph, where they belong
to the row above for a click, the Up and Down keys step over them, the caret never stands on one, and the scroll and
its bar count them. The editor reads a paragraph's line height when it first shows it, as it reads its colours, so a
large text costs a screenful: the scroll bar's extent grows by a paragraph's blank rows once it has been shown.

**A paragraph's `alignment` in an `AttributedString` is drawn.** `string.alignment = .center` (or `.left`, `.right`)
compiles and draws as it does in SwiftUI. On Apple platforms it is Core Text's own attribute, so it needs macOS 26,
as SwiftUI's does, and naming `AttributedString.TextAlignment` is never ambiguous; TUI re-exports Core Text there, as
`import SwiftUI` does. On Linux and Windows, which have no Core Text, TUI declares the same names itself, with no
gate. To align a paragraph on macOS 15, set TUI's own `paragraphAlignment` (`.leading`,
`.center`, `.trailing`), which draws on every platform and macOS; where a paragraph states both, `alignment` wins.
Either belongs to a whole paragraph: set on a word, it is set on the word's paragraph, and text typed into the
paragraph takes it. A `Text` aligns each of the paragraph's lines within its own width, as `.multilineTextAlignment`
aligns all of them, and wins over that modifier for its own lines. A `TextEditor` centres or right-aligns each row of
the paragraph within its width (the last cell kept for the caret), or each line narrower than the editor where it
scrolls sideways; the caret, clicks, drags, an Option-drag's block and the Up and Down keys go by the cells as drawn.

**`AttributedTextSelection` and `AttributedString`'s selection members arrive, ahead of the attributed `TextEditor`.**
SwiftUI's selection in attributed text, with its four initializers, `indices(in:)`, `affinity(in:)`,
`typingAttributes(in:)` and `attributes(in:)`, and the `AttributedString` members that keep a selection in step with
the text: `transform(updating:body:)`, `replaceSelection(_:withCharacters:)`, `replaceSelection(_:with:)`,
`transformAttributes(in:body:)` and, on macOS 26 and later as in SwiftUI, `subscript(_:)` with a selection. Typing
takes the attributes macOS's text system gives (the character before the caret's, a paragraph's first character's at
its start, a selection's first character's over it). On macOS 26, Linux and Windows the selection is tracked through
a change by Foundation itself. macOS 15's Foundation cannot track, so there the change is found by comparing the text
before and after: exact for one contiguous change, approximate for several in one `transform`, at about
3 ms for a 3 MB text.

**A debug build warns when a `List`'s selection can name none of its rows.** `List(games, selection: $selection)` with a
`GameID?` selection over rows whose `id` is a `String` selects nothing, as in SwiftUI, and said nothing, as SwiftUI says
nothing. A debug build now says so once, for the rows of a `ForEach`, of an outline (`List(_:children:selection:)`) and
of a section's `ForEach` (a `ForEach` of `Section`s), naming both types, through TUI's runtime warnings (on stderr when
the app gives the terminal back, or in `TUI_DIAGNOSTICS_FILE`). Nothing else changes.

**A test can play a terminal that can do what it says, from the start.** `TestApp.terminalCapabilities` is settable,
and `TerminalCapabilities(supported:unsupported:)` is public, so a test can present a terminal that reports key
releases (the kitty keyboard protocol) before the first frame, as a running app learns its terminal before its first
frame: `.onAppear` reads it. A keyboard feature set this way is also one the terminal is taken to report.

**`TestApp.reportFocus(_:)` reports the terminal's window losing or gaining the focus.** A test could not reach
`\.scenePhase`'s `.inactive`: it read `.active` throughout, so a game that pauses when its window goes to the back
could not be tested. `app.reportFocus(false)` moves `\.scenePhase` to `.inactive` and `\.appearsActive` to `false`,
and `app.reportFocus(true)` back, as a running app moves them on the terminal's focus reports; the pointer leaves with
the focus, as it does there.

**A `Canvas` beside a `TimelineView` is not drawn again on every frame of the timeline.** A game's board drawn
beside the `TimelineView(.animation)` that runs its loop ran its renderer sixty times a second though nothing it read
had changed: the timeline's entry drops what the cache keeps for the views around it, and nothing kept the canvas, so
a board of 162 cells cost about 7 ms of every 16.7 ms frame. SwiftUI re-evaluates only the timeline's content on a
tick. A `Canvas` is now memoized as a view of the app's own is, by its fields and its environment, so it is drawn
again when its parent's `body` runs for a change it depends on, when its size or environment changes, or when
something its renderer read is written, and not for a frame something beside it asked for. A renderer that reads
what nothing tracks (a plain class, a global) keeps what it drew until one of those happens, as a `body` does.

**A `Form`'s rows a `ForEach` over comparable data makes are drawn only when they change.** A form read its content
into rows afresh every frame and drew each one through views nothing could compare, so every toggle of a form ran its
body and was measured a dozen times a frame, whatever the frame changed: a slider step in a form of 50 toggles ran
2,400 bodies. Such a row is now kept by its element, as a `ForEach` row is in a stack, and by what the form read of
its content, so a frame that changes one row, or nothing in the form, draws that row and serves the rest (the same
step: 264 bodies). A row the loop's closure builds from observed data outside its element is drawn again when that data
changes, as before. A form cleared on every frame — under a view that reads a clock — draws its rows as before, without
keeping them.

**A page served whole from a memo no longer pays, every frame, for what is cached below it.** The render cache's
end-of-frame prune asked of every entry kept under the served memo whether it was still in the tree; it now skips that
walk when the frame stored nothing and saw the same views as the last one.

**A `TextField`, `SecureField` or `TextEditor` takes text dropped on it, as SwiftUI's do.** A `String` dragged from a
`.draggable` view goes in where it is let go, as a copy, selected, and as one step to undo, inserted as a paste is,
so a content type and the binding treat it as pasted text. As measured of SwiftUI on macOS 15.8.3, a field takes a
drop only while it holds the focus, and an editor focused or not, leaving the focus where it was. A drag carried from
the keyboard (Ctrl-R) can stop at any of them, and Return drops it at the caret.

**A `.dropDestination` no longer keeps an app's objects alive after its loop ends.** The drop target it registers,
which the drag session holds until the next frame's, held the session and the mouse dispatcher back, and with them
the focus manager and every control's mouse handler.

**A `TextField` or `SecureField` on one line keeps a pasted line break.** Pasting "ab", a newline and "cd" bound
`"abcd"`, joining the words on either side; it now binds `"ab\ncd"`, as SwiftUI's field does (measured on macOS
15.8.3). Each break is bound as one `"\n"`, whatever convention the clipboard used, as a vertical field already bound
it, and U+2028 and U+2029 as themselves. The field draws a line break of any kind as `\u{FFFD}` in one cell, so the
text after it stays in view; U+2028 and U+2029 were handed to the terminal raw, to draw as it pleased. An app that
wants one line strips the breaks itself, as it would in SwiftUI.

**`@SceneStorage` keeps its values in a store of its own, which no `@AppStorage` key can name.** The window opened at
launch kept `@SceneStorage("tab")` under `scene.tab` in the app's own store, so `@AppStorage("scene.tab")` was the same
value and writing either changed the other. Scene state now lives beside the app's store, under its declared keys: in
`settings.scenes.json` next to `settings.json` (`TUI_CONFIG_DIR` moves both), in a `UserDefaults` suite named
`<app>.scene-state` on Apple platforms (`<suite>.scene-state` for a store of a suite), and in memory with a `TestApp`'s
own. **A `StorageBackend` of your own** has a new requirement, `sceneStateStore`: hand back another store of your kind,
made once, which answers itself. **Scene state saved by earlier versions is not read back**, since TUI keeps no
compatibility shims before 1.0: windows open once as they would on a first launch, and the old `scene.` keys stay in
the app's store, unread.

**A menu open while the terminal shrinks keeps its highlighted row in sight.** A pop-up menu, a submenu, a context
menu, a `Picker`'s drop-down and a text field's suggestions kept their rows scrolled where they were when their
window of rows changed size, so the highlighted row could end up out of sight and Return chose a row nobody could
see: 30×14 to 12×4 with Item 9 highlighted showed Items 0 to 2. The window now scrolls to the highlighted row, as
little as it must, whenever it changes size or its rows change in number. In a terminal too short for four rows the
window is no longer taller than the space it is drawn in, which cut its last rows off.

**Tab to a `.draggable` or a `.dropDestination` in a scroll view scrolls it into sight.** The focus stop either
modifier gives a view with none of its own was not revealed, as a `.focusable()` view's is: the focus could go below
the fold and stay there unseen, and Copy or Paste there acted on a view the user could not see.

**An edit in a `TextEditor` that joins the halves of a character leaves one character.** Backspace or Delete joining
a line that starts with a combining mark to the line before it, or taking out a character from between two regional
indicators, left the editor counting the two halves apart while its text held one character: the caret sat between
them, and the next key typed went there, so an accent moved onto the letter typed after it and a letter split a
flag. Each line an edit changes is now laid out as its text's characters.

**A click below the text of a `TextEditor` that scrolls sideways lands at the column clicked.** Under
`.textEditorWrapsLines(false)`, a click in the empty rows below the last line put the caret at the start of that
line wherever the click was. It now goes to the column clicked on the last line, as it does in an editor that wraps.

**`ScrollView { OutlineGroup(…) }` draws its tree.** An outline with nothing to lay out its rows — a scroll view's
whole content, the shape `OutlineGroup`'s own documentation shows, or a view's entire `body` — drew a blank screen,
since it had no drawing of its own; inside a `VStack` it drew fine. It now stacks its rows as a `VStack` does, and in
scroll content past 256 open rows draws them as a `LazyVStack` does, building only the rows on screen: an outline has
no lazy counterpart in SwiftUI, so it windows its rows as `GroupBox` and `DisclosureGroup` do.

**A `.scrollPosition(id:)` binding that starts `nil` stays `nil` as the view appears.** The first frame of a
`ScrollView`, `List` or `Table` wrote the id of its top row into the binding, where SwiftUI writes nothing: an app
that read `nil` as "not scrolled yet" never saw it, and an `onChange` of the binding fired as the view appeared. The
binding now stays `nil` until the user scrolls, and then reads the row at the top, as SwiftUI's does.

**Opening or closing a branch of a big `Table(_:children:)` costs that branch's rows.** A change to the open branches
made the table's kept outline again from its roots, listing every open row and each one's id: with 200,000 rows open,
Right and Left took about 240 ms where Down took 8. The table now puts in or takes out only the rows beneath the
branches that opened or closed, and keeps the rest and its index of them by id, so a toggle, an ⌥Right or ⌥Left on a
branch, and an app's write to its `expansion:` set cost the rows they show or hide, and one copy of the open rows.

**Under `.selectionFollowsCursor()` the first key from an empty selection does what macOS's does.** With nothing
selected the cursor started on the first row, drawn there, so the first Down selected the second row and the first
row's own letter skipped it. Now, with nothing selected and nothing having placed the cursor, no row is drawn as the
cursor's and the focus arriving scrolls nothing; Down selects the first row, Up the last, a typed letter the first
row it names, and the keys that act on the cursor's row (Space, Return, Delete, a tree's Left and Right, the row
menu, the swipe and reorder keys) act on none, where they acted on the first row unseen. A selection the app empties takes the cursor with it, so the next arrow starts again from nothing;
one Space empties keeps it, drawn, as does a row the pointer parked it on while the focus follows the pointer. Home,
End and the page keys still select (on macOS they only scroll; deviation V8). Every `List`, `Table`, tree table,
`OutlineGroup` and sidebar tab view keys through the one handler; pickers are unchanged.

**A list or table starts with its keyboard cursor on the selection it starts with.** A selection the app had at
the first frame left the cursor on the first row, so with the sixth row selected the first Down went to the second
row (and under `.selectionFollowsCursor()` selected it), where macOS goes on to the seventh. The cursor now starts on
the selected row, or a multiple selection's first in the rows' order, with the modifier and without it; a list
whose `.defaultScrollAnchor(.bottom)` opens it on its newest rows keeps the cursor there.

**A hugging `List` keeps its width through a change it did not read.** When a view of an app's own was kept and a
property read anywhere beneath it changed, everything kept below it that could not be re-checked was dropped with it,
though each of those has its own watch on what it read. A sidebar `List` hugging its rows beside a clock that ticks
every frame lost its width that way each time the page was tried for keeping again, about every 64 frames, and read
all of its rows twice running to find it: 40% of the frame for 2,000 projects. Now such a change drops the view's
own result and those that contain it, and leaves the rest to their own watches.

**A `Table` measured more than once in a frame measures its border and header once.** A table sizes its chrome by
measuring it around a stand-in for its rows, at the size the rows come to, so a second measure at another size
asks the same thing; the frame's measure memo answered it only by luck, since the header line it was keyed by was
built afresh each time. It is now keyed by the header's size: a title over a 10,000-row table fixed vertically does
24 fewer measures a frame (78 to 54) and takes about 10% less time.

**`sheet(item:)`, `fullScreenCover(item:)` and `popover(item:)` keep each item's state while they are up.** Switched
from one item to another and back, the presented content is as it was left for that item — its `@State`, scroll
positions, selections and where the focus was — while each other item's content has state of its own; its `onAppear`
and `task` run again on its return, as a tab's do. Switching runs no `onDismiss`, and dismissing (the item `nil`)
drops every item's state, so presented again an item starts fresh. Up to 16 items left behind keep theirs; one shown
longer ago starts fresh. Before, every switch started the content over. SwiftUI's `sheet(item:)` on macOS (the form
measured; macOS has no full-screen cover) keeps one state for every item instead, handing the content the new item;
an app that wants that holds the state in the presenting view, or presents on a flag and reads the item in the content.

**`List(_:children:)` and `OutlineGroup` can take the app's expansion too: `expansion: $openIDs`.** Every form of
`List(_:children:)` (selection none, single, set; a tree of values or a binding to one; with and without `id:`) and
every view form of `OutlineGroup` has `Table(_:children:)`'s defaulted argument after `children:`. Handed one, the list
opens exactly the ids in the set, in a list of the outline alone, in a `Section`, or in a bare outline, and the user's
Right, Left, ⌥Right, ⌥Left and clicks on a triangle write it. The list still keeps its open rows between frames and
builds only the rows it draws. Without the argument a list behaves as before, and every SwiftUI call compiles
unchanged.

**`Table(_:children:)` can take the app's expansion: `expansion: $openIDs`.** Every hierarchical table initializer
has a new, defaulted argument after `children:`, a binding to the set of open branches' ids. Handed one, the table
opens exactly the ids in the set, and the user's Right, Left, ⌥Right, ⌥Left and clicks on a triangle write it, so an
app can start with its root open, or open a Find match's ancestors from code, then select the match and scroll to it.
The table still keeps its outline between frames and builds only the rows it draws, which a tree written as row
content (`DisclosureTableRow`) does not. SwiftUI's `Table(_:children:)` takes no expansion; without the argument TUI's
behaves as before, and every SwiftUI call compiles unchanged.

**`.scrollPosition(id:)` keeps the id the app wrote.** Writing the id scrolled to its row by the least move, which
with no anchor can leave the row at the bottom of the view, and then wrote the row at the top straight back into the
binding: the app's id was lost, and writing it again did nothing, the row being in view already. The binding now
keeps the id the app wrote until the user scrolls, as SwiftUI's does, and reads the row at the top from then on.

**A `List` of `Section`s starts its cursor on the first item, not on the first header.** The cursor started on row 0,
the first section's header, where Space and Return did nothing until Down moved it. It now starts on the first row
the selection can name, as SwiftUI's keyboard never stands on a header.

**A `DatePicker` edit keeps the seconds.** Stepping or typing an hour, minute, day, month or year rebuilt the date
to the minute and dropped its seconds and their fraction; an edit now changes only the field edited, as SwiftUI's
picker does.

**A control's own `.disabled(_:)` reaches its label and its style.** `Button(…).disabled(true)`, and the same on a
`Toggle`, `Picker`, `DatePicker`, `Stepper` or `Slider`, is the control's own method, which returns the control rather
than a view under `View.disabled(_:)`, and it left `\.isEnabled` true: a label or a custom style's body reading
`@Environment(\.isEnabled)` drew an enabled control, a control in the label stayed live, and a disabled button under a
`PrimitiveButtonStyle` whose body is `Button(configuration)` could still be pressed and clicked. Each now draws its
label and its style's body with `\.isEnabled` false, as the view modifier does.

**A hierarchical `Table` whose tree is row content lists its open rows in about half the time.** Flattening a tree
written as `DisclosureTableRow` and `ForEach` row content runs over the app's row type in code that cannot be
specialised for it, and it looked up type metadata, made nodes, and pushed and popped them one row at a time. A
branch whose rows are all plain leaves is now listed whole, a loop of rows walks an array's storage directly, and the
outline's bookkeeping no longer depends on the row type; a `Table(_:children:)` gains about a tenth. A `ForEach` over
`Identifiable` elements or a range, of views, rows or tabs, no longer makes a key path to the elements' ids each time
it is created: it never read it.

**A table column of strings sorts `item2` before `item10` on Windows and Linux, as on a Mac.** Given no comparator,
`TableColumn(_:value:)` and `TableColumn(_:value:content:)` over a `String` property sort as Finder lists names
everywhere, where off Apple platforms they sorted by character codes (`Zebra` before `apple`, `item10` before
`item2`), since Foundation there has no `.localizedStandard`. SwiftUI's initializers are unchanged, and a column given
a comparator sorts with that one. File panels sort their names this way on Linux too, as they already did on Windows.

**On Windows, an animated WebP plays, and in the classic console an `Image` takes its natural size.** Windows's
WebP codec composites the frames, so a WebP plays there as a GIF does, at the file's own timing. The classic
console's cell is measured from its window, at its display's scale, so an image that isn't `.resizable()` is as big
there as SwiftUI would draw it, where before it fitted the space it was offered; only where you're at the machine
the app runs on. Windows Terminal doesn't say how big its cell is, so there it still fits. An APNG still shows its
first image.

**Windows is supported.** An app builds with Swift 6.2, 6.3 and 6.4 from swift.org, on arm64 and x86_64, and runs in
Windows Terminal and in the classic Windows console, with nothing of its own to port. Building needs Developer Mode,
for the symbolic links in a dependency's checkout, and a shipped program needs the Swift runtime's DLLs beside it.
What differs from macOS and Linux, such as the keys Windows Terminal keeps for itself, Control-Break for a hung app,
no suspending and no desktop notifications, is in the new Running on Windows article. CI's Windows jobs for the
console layer and the tests stay advisory until they have passed there.

**On Windows, TUI reads the user's language, region and accessibility settings from Windows.** Foundation there
answers world English (`en-001`) whatever was chosen, so every app spoke English and wrote dates day first; TUI's own
words and an app's dates and numbers now follow Settings → Time & language, as `LANG` does elsewhere. Reduce motion,
reduce transparency and increased contrast follow Windows's Animation effects, Transparency effects and contrast
themes. A file panel's Desktop, Documents and Downloads are where Windows keeps them, OneDrive included, and
Applications is Program Files; it refuses a name Windows would read as something else, such as `notes:old`, which
wrote a hidden stream of `notes`, and lists names as Explorer orders them, each file's Kind in Windows's words. The classic
console, which answers no colour query, has its colours read from the console itself.

**On Windows, an `Image` decodes with Windows's own codecs, and a file panel follows shortcuts.** TIFF, WebP,
HEIC and AVIF, JPEG XL and XR, icons, DDS and camera raw files draw, turned upright by their EXIF orientation, where
only PNG, JPEG, GIF and BMP did; a file panel previews them too. A shortcut (`.lnk`) to a folder opens it, and one to
a file is chosen as that file, as a symbolic link is. In the classic console a picture keeps its shape in a font
narrower than Consolas. Elsewhere off Apple platforms, `Image(_:bundle:)` no longer looks for a `.tiff`, which it
could not draw.

**On Windows, a double-click and the text cursor's blink follow Windows's settings.** Two clicks count as one double-click
as far apart as the Mouse control panel allows (500 ms by default, where TUI's own is 400 ms), and the text cursor
blinks at the Keyboard control panel's rate, or holds still where that is None, whatever a view's `.textCursor(_:)`
asked for. Read only where you're at the machine the app runs on, as TUI's other host settings are.

**In a `TextEditor`, Shift-Option-B and Shift-Option-F select a word at a time,** as they do in a `TextField` and as
Shift-Option-← and → already did. They only moved the caret, losing the selection. They are the word keys where a
terminal keeps Shift-Option-arrows for itself, as Windows Terminal binds them to resizing a pane.

**`keyboardShortcutFallback(_:)` gives a button or a toggle a second key.** Both keys are bound, and a menu row, the
button's label and F1's list of shortcuts name the fallback only where the terminal cannot send the
`keyboardShortcut` as itself, such as `⌃⇧P` in a legacy encoding, which sends `⌃P`, or in Windows Terminal, which
keeps it for its command palette. An alert keeps a button's fallback, and `Scene.keyboardShortcutFallback(_:)` gives
a scene's key one, which Settings… and a `Window`'s item in the Window menu name the same way. TUI-specific: SwiftUI
gives a control one shortcut.

**A menu, F1's list of shortcuts and the file panel's status bar name only keys that work in the terminal.** A chord
the terminal cannot send as itself, such as ⌃⇧S where a legacy encoding sends ⌃S, or one the terminal keeps for a
binding of its own, is no longer shown beside its command, where pressing it would do something else or nothing. It
stays bound. Where the command has another key that does arrive, that one is shown, as undo's and redo's hints
already were. `RowShortcuts.hint(for:on:commandKey:)` chooses a list row's hint the same way.

**In Windows Terminal, undo and redo name ⌃Z and ⌃⇧Z.** Windows Terminal keeps ⌃- for its font size and ⌥⇧- for
splitting a pane, so those two of undo's and redo's keys never reach the app there.

**In Windows Terminal, the file panel's status bar no longer names ⌃⇧P for the preview.** Windows Terminal keeps
⌃⇧P (its command palette), and also ⌃⇧N, ⌃⇧D, ⌃⇧A and ⌃⇧., so the panel's New Folder, Desktop, Applications and
hidden-files chords never reach the app there either. `+`, `/` and `>` still do.

**A typed `=` opens and closes the file panel's preview.** It is the preview's key in every terminal, where ⌃⇧P
arrives only under the kitty keyboard protocol and not at all in Windows Terminal, and the status bar names it
wherever ⌃⇧P does not arrive. A text field, such as a save panel's name field, still types it.

**On Windows, `handOffTerminal(running:arguments:)` runs the program.** It threw `.unsupported` there. It now
starts the program in the app's console and waits for it, and reports how it ended as `.exit` with its exit code:
Windows has no signals, so a program ended by ⌃C exits with `0xC000013A`. A name is looked up as Windows looks one
up, with `.exe` added. There is no shell to split `%EDITOR%`: run `cmd.exe /c` for a command line.

**On Windows, ⌃C or Ctrl-Break in a program the app has handed the console to no longer ends the app.** The console
sends both to every program sharing it. ⌃C shut the app down when the program returned, and Ctrl-Break ended it at
once. While the console is handed over, the app now ignores both, as it ignores `SIGINT` and `SIGQUIT` on macOS and
Linux.

**On Windows, a paste of over a megabyte arrives whole.** TUI dropped everything past the first megabyte it held for
the app. It now leaves the rest with the console until the app has read what it holds.

**On Windows, a logoff or a shutdown quits the app in order.** The console never tells a program that has loaded
`user32.dll` of either, and a TUI app has, so the system ended it without its teardown. A hidden window now hears of
the session's end and shuts the app down, as `SIGTERM` does on macOS and Linux.

**On Windows, Ctrl-Break leaves nothing of a frame on the shell's screen.** The console runs Ctrl-Break's quit on a
thread of its own, which could write its teardown while a frame was still being written, so the rest of the frame
landed after it. The quit now waits for the frame, for up to a quarter of a second.

**On Windows, a thread that drew a frame gives back its stack when it ends.** Each thread that drew a frame kept an
8 MiB stack reserved for it after the thread ended.

**On Windows, an animation's frames come when they are due.** `Task.sleep` there wakes on the clock's 15.6 ms tick,
so a frame came as much as a tick late: one due 16.7 ms after the last drew 31.2 ms after it. The run loop now waits for
its next frame on a high-resolution timer, which wakes within about a millisecond of when it is due.

**On Windows, a file panel can show a drive's root.** Going up from `C:\Users`, typing `D:\` or `D:`, or clicking the
drive in the path bar opened a folder named `C:` inside the working folder, which could not be listed. The path bar now
starts at the drive, written `C:`. A network share (`\\server\share`) is still out of reach: Foundation loses the first
backslash of its path.

**On Windows, a file panel lists system files and old profile folders as what they are.** A file Windows holds open,
such as `pagefile.sys`, and a protected folder link such as `Application Data` in a profile could not be read. Each was
listed as a visible file with no size and no date, which could not be opened. Their hidden attributes, sizes and dates
are now read from the folder itself, which also lists a folder 3 to 8 times faster.

**On Windows, a link with no scheme no longer starts a program.** Windows takes a bare name, such as `calc`, for a
program to run. Opening a URL now hands Windows only one that names a scheme, such as `https:` or `mailto:`.

**On Windows, an `AttributedString` of thousands of characters draws without a pause.** Its text was copied once for
each character, so 80,000 characters took 2 seconds to make into runs. It is now copied once.

**In the classic Windows console, a stepper's and a slider's arrows no longer draw as boxes.** Consolas, its
default font, has no `◀` or `▶`, and the console draws a character its font lacks as a box when it stands alone in a
colour of its own, as those arrows do. Where the console's font lacks them, TUI now sends `◄` and `►` in their
place, which it has, in the same cells, and `○` for `◯`, wherever TUI or the app draws them. In Cascadia Mono, which
has them, nothing changes, and changing the font while the app runs redraws it.

**In the classic Windows console, shapes no longer draw boxes in its default font.** Consolas has none of the
quarter blocks TUI cuts a shape's corners with, so each corner showed as a box. TUI now asks the console which font
it is using, and where that font has none of them, it cuts a shape's and a solid button's corners in whole cells, as
on Apple Terminal, and draws a canvas at `CanvasGrain.automatic` in half blocks. Corners are coarser for it: a
`cornerRadius: 1` comes out square. In Cascadia Mono, or another font that has them, nothing changes, and changing
the font while the app runs redraws it. A canvas asked for in `.quadrants`, or a `.blockWedge` spinner, still draws
quarter blocks.

**On Windows Terminal, Settings… shows F2, not ⌃,.** Windows Terminal 1.25 speaks the kitty keyboard protocol, so
TUI offered ⌃, there, but the terminal keeps ⌃, for its own settings and the app never hears it. The menu bar's
Settings… and F1's list now name F2 there, as they do in the classic console. ⌃, is still bound, for someone who has
rebound the terminal's settings.

**A click on the status bar's `⌃Q quit` quits.** Since quit moved to ⌃Q the item drew as a hint but was no click
target; it is one again, and a click quits as the key does, a prevented quit included.

**A copy too large for Windows Terminal or the Windows console is no longer lost.** Both drop an OSC 52 copy of
more than 24,567 bytes of text and say nothing, so TUI used to report such a copy as made. It now goes to this
machine's clipboard where the user is at it, and otherwise is not sent, the status bar saying "Not copied: too large
for the terminal's clipboard" (`statusbar.notCopiedTooLarge`, in every language TUI ships).

**On Windows a deep page draws whole.** A Windows program's threads get 1 MiB of stack unless it was linked asking
for more, and a deep page drawn in a debug build needs more than that: TUI drew its deepest views empty rather than
crash, so parts of a page went missing. Each frame is now drawn on an 8 MiB stack TUI provides, a fiber on the same
thread, so nothing changes for an app's code and there is nothing for it to set.

**Windows Terminal and the classic Windows console are known hosts.** Windows Terminal is named by `WT_SESSION` or by its Device Attributes, and gets OSC 8 hyperlinks, every underline style, OSC 52 copying, OSC 9;4 progress, and CUF repairs for what it advances short of TUI's widths (bare pictographs, a lone regional indicator, SF Symbols). The console (conhost) is named by its Device Attributes. It gives every code point a cell, so ZWJ sequences go out as their parts and skin tones as base and swatch. A flag goes out as its two letters, a variation selector after a wide glyph is dropped, an accent is composed into its letter, and bare pictographs get a CUF. Combining marks that compose with nothing still take a cell each there. Both are measured in the Terminal compatibility survey.

**A `LazyVStack` in a `ScrollView` that scrolls both ways, over rows the app builds in its body, compares them once a
frame.** The width of its widest row, kept so the horizontal scroll reaches every row's end, was matched to the rows
by comparing the rows it was taken over with the rows the stack was handed, element by element whenever they came in
a new array, which a body that sorts or filters makes every frame — on each of the several asks a frame makes. The
stack now keeps a version of its rows, as a `Table`'s `.fit` columns do: the same while they are equal, and a new one
for any change at all, so a changed collection is still measured again.

**A long `.columns` `Form` in scroll content whose rows the app builds in its body compares them once a frame.** The
widths it keeps for its label column and rows were looked up by comparing the rows it was first handed with the rows
it was handed now, element by element whenever they came in a new array, which a body that sorts or filters makes
every frame — and the rows it kept were never replaced, so every time the form was laid out compared all of them. The
form now keeps a version of its rows, as a `Table`'s `.fit` columns do: the same while they are equal, and a new one
for any change at all, so a changed collection is still read again.

**A hierarchical `Table` lists its open rows with less bookkeeping.** As it flattened its tree, a table noted where
each open row sat in three tables keyed by the row's id; it keeps them in order now, and looks a row up by id only
when something asks. Listing the rows of an open tree is about a sixth faster, for rows written as row content
(`DisclosureTableRow`) and for an open `Table(_:children:)`, and holds less memory.

**A `Table` whose tree is row content flattens it once a frame.** A table whose rows are a tree written as row
content (`DisclosureTableRow`, a `ForEach` of rows beneath one) built the content of every open row each time a frame
laid it out: once for each measure a stack around it made, and again to draw it. In a page's stack, as an editor's
table sits under its toolbar, that was two or three times a frame. The rows are built once a frame now and handed to
every measure and the draw; rows or open branches that change between frames are built again.

**An outline in a `List`'s `Section` builds only the rows it draws.** `List { Section { OutlineGroup(…) } }` made a
row for every open node of its tree on every frame, as `List(_:children:)` did before it was windowed. A list whose
content is one section holding an outline now windows its rows the same way, with the section's header before them
and its footer after: with 5,000 rows open, a frame makes about a screenful of rows, and the same at 50,000. A
section among other rows, or several sections, still extracts its rows at once.

**Left, Right and their Option forms open and close an outline inside a `List`'s `Section`.** A list asked the view
its rows came from to open a row, and for a section that was the `Section`, which opens nothing: in
`List { Section { OutlineGroup(…) } }` the keys did nothing to the tree, and Return on a branch did not disclose it.
Each section now hands its outline to the list, so the keys work as in `List(_:children:)`, in every section of a list
of several.

**An outline in a `List` builds only the rows it draws.** `List(_:children:)` made a row for every open node of its
tree on every frame, so a tree of thousands of open rows cost thousands of rows a frame however few were on screen.
Its rows are now windowed as a `ForEach`'s are, and the open nodes are kept from frame to frame while the tree and
its open branches are the same: with 5,000 rows open, a frame makes 22 rows where it made 5,001, and the same at
50,000. Keys, selection, type select and `scrollTo` reach every row as before.

**A `List` that hugs its rows — a split view's sidebar, `.fixedSize(horizontal: true)` — compares rows the app builds
in its body once a frame, as a `Table`'s `.fit` columns now do.** The kept width of its widest row was looked up by
comparing the rows it was taken over with the rows the list was handed, element by element whenever they came in a new
array, on each of the measure's and the render's asks. The list now keeps a version of its rows, the same while they
are equal and a new one for any change at all, so a changed collection is still measured again.

**A `Table` with `.fit` columns whose rows the app builds in its body compares them once a frame, not once for every
time a column's width is asked.** The kept width of a `.fit` column was looked up by comparing the rows it was taken
over with the rows the table was handed, element by element whenever they came in a new array, which a body that sorts
or filters makes every frame; each `.fit` column is asked by the measure and again by the render, so 4,000 rows were
compared twice a frame for each such column, about 7% of a file browser's frame. The table now keeps a version of its
rows: compared once with the last rows it was handed, the same while they are equal, and a new one for any change at
all — an edit, an insertion, a removal, a reorder — so a changed collection is still measured again.

**A row appended to a `Table` with `.fit` columns costs that row, and a hidden tab's table costs next to nothing to
switch back to.** A `.fit` column's width was kept in the render cache, which the write that brings a row sweeps, and
which a table not drawn while its tab was hidden lost at the end of every frame: each appended row, and each switch to
the tab, read every cell of every `.fit` column again — 2,000 rows of five columns, 10,000 cells, for one row. The
width is now kept with the table's state as well: a collection that only grew reads its new rows; one unchanged reads,
after a write, the row that decided the width and the rows on screen; and one that lost or changed rows is read again,
so removing the widest row still narrows the column. A table its container gives another width reads no row either,
unless its one-line cells reach the width they were laid out at. A change to the terminal's size, the theme or
anything else that clears every cached view still reads every row.

**A `TextEditor` lays its text out once in the frame it first appears, not once for every measure.** Before its
first render had made the handler that keeps the layout, each measure of a new editor split its whole text into lines
afresh, and the render once more: six times over for an editor beside a tree and under a heading, 658 ms of a 786 ms
file open over 3.2 MB of JSON in tuitree. The first measure's layout is now kept for the frame's other measures and
handed to the handler the render makes: an editor of the same 3.2 MB in a pane of that shape now opens in about 315
ms of CPU, against 1,050 ms (release build).

**A wrapping `TextEditor` holds a byte a character for each width it keeps its text wrapped at, where it held eight.**
Each character's width in cells was an `Int`; it is now a byte, and the rare character 255 cells wide or wider (a tab to
a far stop) is kept apart. Over 3.2 MB of text, wrapped at the widths a frame asks for, that is about 45 MB less.

**A key in a large `TextEditor` costs the line it changes, not the document.** Each edit joined every line of the text
into a new string, the editor wrapped the whole document again for the next frame, and an editor with a selection
binding walked the text's characters to the caret on every key and every frame: about 230 ms a key in a release build
over 3.2 MB of JSON. The edit is now spliced into the text's bytes, only the lines it touched are wrapped again, and the
caret is found from where each line starts: about 2.6 ms a key over the same text, and 90 MB less held.

**A `TextEditor`'s typing can be undone after the editor leaves the screen.** Its steps stayed in the app's undo
manager only while it was drawn: a pane hidden in a split view took them with it, though its binding, and the text,
lived on. They now stay, and undo and redo restore the text through the binding, as SwiftUI's editor's steps stay in
the window's undo manager after it leaves the window. They leave when the app replaces the text and the next undo or
redo would find it gone, as an editor's on the screen do. A `TextField`'s still leave with it.

**A document a `DocumentGroup` opens after launch starts with the focus where a new window's content does.** Opened
through `openDocument(at:)` or Open…, its content replaced the last document's, and the focus walked from the last
document's focused control to the first control of the new content: its `.searchable`'s field, so the keys the table
answers typed into Find. It now starts on the content's `.defaultFocus`, else its first control, never a search field
while there is another, as each document's window opens on macOS.

**`TUI_ARROW_FOCUS`, `TUI_TEXT_CURSOR_FOLLOWS_FOCUS` and `TUI_GRAPHICS_PLAYBACK` are supported options, no longer
experiments.** Arrows that go to the nearest control on screen, the terminal's text cursor on the focused control, and
animated pictures the terminal plays by itself keep their defaults and do what they did, but they now fall under the
API stability promise, as the rest of the end-user variables do, rather than being free to change or go in any
release. The held-press widening of a text selection (a drag well past a bordered container's interior widens to the
pane) is accepted as it is.

### Scroll views and lists build only what shows

**A view in a scroll view is its content's height, and only the rows on screen are built, wherever they stand.** A
`List`, `Table`, `TextEditor`, grouped `Form`, a `ScrollView` nested in another, or a split view in a vertical
`ScrollView` with no frame is now as tall as its content, and the outer scroll view scrolls it, building only the rows
in view: a 10,000-row table or list under a title builds a screenful a frame where it built thousands, as a
`LazyVStack`, a long `GroupBox` or a `FlowLayout` already did anywhere in the content (below). What changes for an
app:

- A `Table` in a scroll view was capped at the scroll view's height and scrolled its own rows; it is now its rows'
  height, its header and horizontal scroll bar pinned to the top and bottom of the scroll view while its rows are under
  them, and its arrow keys, Page Up and Page Down, End and type select scroll the page; Page Down on its last row, and
  Page Up on its first, page on to what follows or precedes it, and Home and End bring its first or last row back from
  wherever the page has gone. A `List` was 4,096 lines tall,
  most of them blank under its rows; it is its rows' height, its section headers pinned. Focused at launch, neither
  scrolls the title above it out of sight any more.
- A `Spacer`, `Color`, shape, `GeometryReader` or `.frame(maxHeight: .infinity)` in a vertical scroll view's content
  takes its least height there, as in SwiftUI, rather than stretching the content to the scroll view's height, so short
  content no longer spreads down the screen. Use `.containerRelativeFrame(.vertical)` for a view that should be as
  tall as the scroll view.
- A vertical `ScrollView` inside another draws no scroll bar of its own and scrolls nothing: the outer one scrolls its
  content, and a `ScrollViewReader` in it scrolls the outer one. A `VSplitView` lays each pane out at its own height
  rather than cutting the first.
- `.fixedSize(horizontal: false, vertical: true)` makes a `List`, `TextEditor`, `ScrollView` or split view its
  content's height too, where it kept the height it was offered.
- `ScrollView(.horizontal)` gives its content its own height, so a table, list or text editor in it is that tall and
  scrolls its own rows, however many it has, where a long one was 4,096 lines tall and a short one its rows' height.
  Taller content of other kinds still scrolls down.
- A frame still gives any of these a height, as in SwiftUI, and the view then scrolls its own rows inside it.
- A `LazyVStack` of a header and a long `ForEach` builds only the rows on screen from its first frame, where that frame
  built every row, more than once, and so does one that pins its sections' headers or footers (`pinnedViews:`).
- A `LazyVStack` of a few `Section`s with long loops, `LazyVStack { Section { ForEach(0..<10_000) { … } } }`, builds
  only the rows on screen too, pinning its sections' headers or footers or not, where its first frame built every row
  of every section, more than once. A pinning stack whose only content is a section now pins that section's header.
  So does a `LazyVStack` of a loop of a few hundred sections or fewer, `ForEach(groups) { Section { ForEach(items) {
  … } } }`, whose first frame built every row of every section however many there were: it now builds a sample of
  the sections and the rows on screen.
- Page Up from the end of a `LazyVStack` of long lazy stacks with spacing between their rows, two `VStack { header;
  LazyVStack(spacing: 1) { ForEach … } }` or two long `Section`s, moves up a page, where it went a hundred or more rows
  further, and Home then goes back to the top.

**A `ScrollViewReader` inside a scroll view's content scrolls that scroll view.** `ScrollView { ScrollViewReader {
proxy in … } }`, a shape SwiftUI's own examples take, did nothing on `proxy.scrollTo`: the proxy reached only the scroll
views inside the reader. It now also reaches the nearest scroll view around the reader that scrolls, as in SwiftUI.

**Escape in a search field ends the search.** It empties the field and gives the keyboard back to the content, past
the scopes, with text or without, as Escape (the cancel operation) does in a macOS search field; it did nothing. An
open suggestions menu still closes first. `dismissSearch` likewise no longer leaves the focus in the scope bar.

**A `.searchable`'s field no longer takes the focus from the content as the app starts.** The content's first control
does, as on macOS, where a window opens with its `List` or `Table` focused and its search field in the toolbar
untouched. Before, every key the content answered — the arrows, Return, an app's `onKeyPress` chords — typed into the
field until Tab took the focus out. ⌃F (Find) puts the keys in the field, and `.searchFocused(_:)`,
`.defaultFocus(_:_:)` and `isPresented:` still can. Where the content has nothing to focus, the field still takes the
focus, as there is no pointer to click into it with.

**`TestApp.press` sends a lowercase letter held with Shift as its capital, as a terminal does.**
`press(.character("g"), modifiers: [.control, .shift])` was a ⌃G with a Shift flag no terminal sends, and shortcuts
read Shift from a letter's case, so it fired the `("g")` shortcut rather than the `("g", modifiers: [.command,
.shift])` one. It is now ⇧⌃G.

**A `TestApp` draws a change made outside a key press before a test reads the screen.** An undo made through
`app.undoManager.undo()`, or a write to an `@Observable` model a view read, asked for a frame that no one drew until
the next key, click or `advance(by:)`, so the test read the screen as it was before the change. `screen`, `focusedID`
and `windowTitle` now draw the frames the app has asked for first, as a running app's loop would have by then.

**A text field that leaves the screen takes its typing out of the undo history in the same frame.** A row's edit field
closed by Escape left its typing in the app's undo manager until another frame was drawn, which in an app with
nothing animating, or in a `TestApp`, waited for the next input: the status bar went on offering "undo", and the first
⌃Z undid typing nobody could see rather than the app's last step. The steps of a `TextField` or `TextEditor` the frame
stopped drawing now leave as that frame ends, and the frame after it shows the bar without them.

**`TestApp.windowTitle` reads the title the app has given the terminal's window**, such as a `DocumentGroup`
window's document name with "Edited", so a test can check that an edit marks a document edited and a save clears it.

**`.keyboardShortcutHint(_:)` shows a key beside a menu item without binding it.** For an item whose key something
else binds — a table's `onKeyPress` chord, which leaves a focused text field its own ⌃D where an app-wide
`.keyboardShortcut` would take it — the menu shows the key, and pressing it does what the binding does, not the item.
TUI's own menu bar items used it already; it is now public. SwiftUI has no such modifier.

**An app's own Return item in the status bar keeps its label.** The focused control's verb for Return replaced the
label of every Return item on the bar, the app's own too, so a table with a primary action showed an app's "↩ edit" as
"↩ open". It now names only the bar's own Return item; a page that declares a Return item says what Return does there,
and a page that wants the focused control's verb declares none.

**Type select's pause runs on a `TestApp`'s clock.** The second's pause after which a typed character starts a new
prefix was measured on the machine's clock, which `advance(by:)` does not move, so two type selects in a test ran
together ("t", then "s", was "ts"). It is measured on the clock input arrives on, which in a `TestApp` is the one the
test moves; a running app's is the machine's, as before.

**A `TestApp` has an undo manager, as a running app does.** `@Environment(\.undoManager)` read `nil` in a test, so an
app's undo could not be tested through its keys or its status-bar items. A `TestApp` now makes one as a running app
does: a view reads it, ⌃Z undoes through it, the status bar shows its undo and redo items, and a test reads it as
`app.undoManager`. A test that types into a text field in a `TestApp` of a whole app now sees the bar's "undo" item, as
the app's users do.

**`\.copyToClipboard` puts text on the clipboard from an app's own command.** Read it with
`@Environment(\.copyToClipboard)` and call it, `copyToClipboard(path)`, in a menu item's or a button's action: the text
goes where every copy in the app goes — by OSC 52 to the terminal's clipboard, which is the clipboard of the machine the
user is at, over ssh too, or to this machine's where the terminal is on it — and the status bar says what became of it.
SwiftUI has no such action; its apps write `NSPasteboard` or `UIPasteboard`, which in a terminal app is the wrong
machine's clipboard over ssh and does not exist on Linux. A `TestApp`'s new `clipboard` is the text the app last
copied, for a test to read.

**A selection the app writes moves a list's or table's cursor onto it.** An app that selected a row itself — a
Duplicate selecting the copy, a Find selecting a match — left the cursor where it was, so the next arrow went on from
the old row (and, under `.selectionFollowsCursor()`, selected the row after it). The cursor now moves to the selected
row (for a `Set`, its first selected row, unless the cursor is on a selected row already), with or without the
modifier, as on macOS, where the next arrow goes on from the selection whoever wrote it. The list's own keys and clicks
are unchanged, and the row is not scrolled to: `scrollTo` does that.

**A `Divider` in a table's or list's row menu no longer stretches the menu across the screen, and its `Section`s
draw a rule between them.** The row menus — `contextMenu(forSelectionType:menu:primaryAction:)`, a `TableRow`'s
`.contextMenu`, a table's column menu — drew their items as one view, so a `Divider` among them was measured as wide
as the terminal and drew the menu from its left edge, and the menu never saw the `Section`s. Their items are now handed
to the menu as the views they are, as `.contextMenu`'s and a `Menu`'s are: a divider is as wide as the items make the
menu, and each section is set off by a rule.

**A table's or list's selection menu runs the item chosen when its items have an `if` among them.** Where a view of
the app's own whose body is several views was drawn as one view — behind an `AnyView`, as a `List`'s and a `Table`'s
row menus draw their items — the views inside an `if` (or a `Group`) in its body took the identities of the body's
first views. They shared those views' `@State`, and in a row menu their rows, so choosing the first item ran the first
item inside the `if`. Each view now has an identity of its own.

**Two columns of a `NavigationSplitView` whose views are of one type keep their own state.** A column's identity was
its view's type alone, so a sidebar and a content column of the same type — two `List`s of strings, say — shared their
`@State`, and two lists shared one cursor and selection. Each column now has an identity of its own.

**A `NavigationSplitView` too narrow for its columns collapses into a stack.** Each column is at least 10 cells
wide, so three columns in a 20-cell terminal drew 32 wide: the detail and a divider lay past the screen's edge, and Tab
still focused that divider. A split whose width has no room for its visible columns side by side (three under 32 cells,
two under 21) now draws as it does in a compact size class, the sidebar on top and choosing a row going forward, and
expands again when the room comes back, its `columnVisibility` unchanged. A detail column shown alone never collapses,
and is no longer drawn wider than a split narrower than 10 cells.

**A `DocumentGroup`'s New and Open leave nothing of the last document to undo.** The app's undo manager kept the
replaced document's steps, so an undo after New or Open could write the old document's text into the new one, through
the binding a step was registered against, and mark it edited. Replacing the document now empties the undo manager, as
a new document's window starts with an undo manager of its own in SwiftUI.

**`TestApp` draws in the same colours wherever its tests run.** It drew in the colours its environment said the
terminal had, as a running app does, and `swift test` sets `NO_COLOR` whenever its output isn't a terminal, so a test
of `styledLines` could pass in a terminal and fail down a pipe or on CI; `TERM` and `COLORTERM` differ between
machines too. It now draws in 24-bit colour. To test fewer colours, wrap the test in `ColorDepth.withCurrent(_:)`,
which it follows. Apps are unchanged.

**Type select on a long list of plain `Text` rows is about three times quicker, and on a long table a third.** A typed prefix is matched against
the rows from the cursor on, stopping at the first that starts with it, so a prefix no row starts with asks every row
for its text. A row that is a plain `Text` is now read for it rather than drawn: on a 10,000-row list such a key press
went from about 140 ms to 50 ms (a debug build), and on a table whose first column is a key path or a plain `Text`
from about 33 ms to 23 ms. A row the app built from other views is still drawn to be read.

**`.typeSelectDisabled()` turns type select off, so the app's bare keys work beside a list.** A focused list or
table, an open `Picker` drop-down and an open pop-up menu take every printable character but Space to find a row by
its first characters, so no bare-key shortcut or status-bar item hears one meanwhile; that is still the default, as
the owner ruled, shortcuts being meant to take a modifier. Set on a view, the modifier turns type select off for
every one of them below it: a typed character then moves nothing and goes on to the next handler, a
`.keyboardShortcut` with no modifiers, a status-bar item's action (which the bar shows again), or an open menu
row's bare key equivalent. `.typeSelectDisabled(false)` turns it back on inside, and `\.isTypeSelectEnabled` reads
it.

**`.statusBarKeySpelling(_:)` is now `.keyLetterCase(_:)`, and it reaches every place a key is drawn.** A letter
pressed alone is drawn as a capital by default, as macOS draws it (`K`), or in lower case under `.asTyped` (`k`), in
the status bar, a menu's shortcut column and the F1 list of shortcuts alike. A key that needs Shift is drawn `⇧K` in
both: under `.asTyped` a status-bar item on `"K"` read `K`, which looked like the bare key, and now reads `⇧K`.
`StatusBarKeySpelling` is `KeyLetterCase`, its `.menu` `.capital`, and `\.statusBarKeySpelling` `\.keyLetterCase`.

**`.selectionFollowsCursor()` makes the keys select as they move, as on macOS.** A list's or table's arrows move a
cursor apart from the selection, Space or Return selecting, which is still the default. Set on a view, the modifier
makes every key that moves the cursor of a list, table, tree table, radio group or segmented picker below it select
the row or option it lands on: the arrows, Home and End, the paging keys, type select and a tree's Left onto a
parent. With a `Set` selection that row alone is selected; Shift with an arrow and Space still build a larger one.

**A grouped `Form` no longer draws its sections at their narrowest width for a frame, now and then.** A stack's
children are worked out once a frame, and the record of them was looked up by its content's value, which reads the
addresses that value holds. A form builds its rows once to measure them and again to draw them, and when the second
build was handed the memory the first had just given back, the drawing used the measured rows, laid out at their
ideal width rather than the page's. Which memory came back varied from run to run, so the frame it hit did too. The
record now keeps the content it was made from until the frame ends.

**A view no longer takes the size of a different one measured at the same place earlier in the frame.** Sizes are
also worked out once a frame and looked up by the view's value, and so by the addresses it holds: an object, a
closure, a string's or an array's storage. A view built, measured and let go of within a frame could hand its memory
to the next one built at the same place, which was then given the first one's size: rows asked for at 4 and 12 cells
in turn, each holding its width in an object made afresh, all came out 12 cells wide after the fourth. The record now keeps each view
it holds a size for until the frame ends, as the record of a stack's children does. `RenderCache.storeMeasure` takes
the measured value as `measuring:`.

**A `Form` reads its rows and measures them once for a frame's measure and draw, where it read them for each.** A form
reads its content into rows and measures every one to find its label column and its width before it lays out a
column, and in a scroll view it was asked for that column three times a frame. Laid out again at the same place and
width, under an environment it cannot tell apart, it now takes the rows, the widths and the column it made the first
time: a grouped form of 1,000 rows in a scroll view reads them twice a frame rather than three times, and its frame
costs what it did before sizes were kept with the views they were measured for.

**`TestApp.advance(by:)` plays an animation the test started itself.** A test that changed a model in its own code
under `withAnimation`, rather than through a key or a click, and then advanced the clock, saw the animation begin
where the advance ended: a row that should have arrived was still blank, its transition at its first frame, and a
moved value had not moved. An event draws the frames it causes before it returns; a change made between events now
gets its frame at the instant it was made, when the clock is next advanced, as a running app draws it at once.

**A focused split-view divider no longer leaves the focus on nothing when the split collapses and widens again.**
Narrowed into its stack, a `NavigationSplitView` takes its dividers away, and a focused one handed the focus to the
column on top, if that had a control. Where it had none — columns of text — nothing was focused, and when the split
widened again the dividers came back with nothing focused still: the keyboard stayed with the sidebar's empty column,
and only Tab reached anything. Now, wherever a focus the framework had to drop found nowhere to go, the first section
with something to focus takes the keyboard as soon as there is one, and its first control the focus.

**A long lazy stack, `List` or `Table` no longer holds on to every row's `if` once it has scrolled past it.**
Each `if` keeps a record of what it last held, and a row scrolled out of view kept its records — the picture its
view last drew and the identity of every view down to it — for as long as the container lived: a lazy stack of
100,000 rows with an `if` in each grew by about 1.7 KB a line scrolled, 96 MB after 48,000 lines. A scrolled-away
row's record now goes, unless the view its `if` held has state to drop should the row come back without it; the
same page stays at 23 MB. Rows keep their `@State` as before.

**A `ScrollPosition`'s first value places a scroll view or a `List` as it appears, as SwiftUI's does.** A
scroll view drawn with no layout pass before it clamped the offset against a height of 0 and opened at the top,
and a `List` or `Table` opened where it was asked to but went back to its cursor's row the moment the focus first
reached it. A list placed by `.scrollPosition` or `scrollTo` now stays there when the focus arrives, until the
cursor or the user's scroll moves it.

**A view reading a scroll view's bounds no longer draws the scroll view's content twice when the scroll view
changes size.** A `GeometryReader` or an anchor asking `bounds(of:)` was told the scroll view's size as it was
when the reader was last found, so a column made narrower or wider drew the content a second time to correct
each such reader. It is told the size the scroll view has now; the Stress `geometry` page, which narrows every
fifth frame, went from 0.54 corrections a frame to 0.01, and is 26% faster.

**`listEmptyPlaceholder(_:)`, `tableEmptyPlaceholder(_:)` and `tableColumnSpacing(_:)` are view modifiers.** They
were methods of `List` and `Table`, so they had to come straight after the initializer, before any modifier:
`.tableStyle(.bordered).tableEmptyPlaceholder("…")` did not compile. Now they can come anywhere in a chain and, set on
a container, reach every list or table inside it, the nearest one winning. A call right after the initializer still
compiles; one followed by a method of `List` or `Table` itself (`listFooterSeparator(_:)`, `focusID(_:)`) needs that
method moved ahead of it.

**The F1 list of shortcuts names a status-bar item's key as the bar draws it.** An item on `"x"` read `X Export` in
the bar and `x Export` in the list. The list now writes a one-letter key as the bar does, `X` by default and `x`
under `.keyLetterCase(.asTyped)`.

**A `ScrollPosition` bound with a new value scrolls, as SwiftUI's does.** A scroll view acted on a bound position
only after a `scrollTo`, so `.scrollPosition(.constant(ScrollPosition(y: line)))`, a `Binding(get:set:)` that builds
a position, or `position = ScrollPosition(y: line)` moved the view once and then never again, whatever `line` became.
The bound value is now compared with the one last read: a different one is a request, an equal one handed over again
leaves the user's scroll alone, and a `scrollTo` of the row already asked for still scrolls back to it.

**In a `TestApp`, the wheel chains out of a nested list, table or scroll view on the test's clock.** A scroller
holds wheel ticks at its edge for `.scrollChainingDelay` (two seconds by default) before passing them to the scroll
view around it, and timed that on the real clock, which a `TestApp` does not drive: a test's wheel never left an
inner list for the page around it, and `advance(by:)` did not help. The delay is now timed on the clock events
arrive on, which is the test's in a `TestApp` and the real one in an app.

**A long `GroupBox`, `DisclosureGroup`, `Section` or `FlowLayout` in a scroll view builds only the rows on
screen.** A `GroupBox { ForEach(items) { … } }` of thousands of rows, an expanded `DisclosureGroup` of them, a
`Section` drawn on its own or a `FlowLayout` of thousands of tags built every row on every frame, as eager containers
do: 10,000 rows took seconds a frame in a debug build. Past 256 rows, in scroll content, each is drawn as a
`LazyVStack` is (a flow as a lazy stack of its lines), building a screenful of rows whatever their count, while the
wheel, the keys and End still reach every one. As with a lazy stack, a row's `onAppear` and `.task` run when it
scrolls into view, not when the container appears, and the column is as wide as the space offered rather than its
widest row. A flow still measures every item when its data or width changes, to break its lines as before.
SwiftUI's containers have no lazy counterpart, and these differences are deliberate. Smaller containers, and the
rows of a stack inside one, are built as before.

**A burst of wheel ticks over two lazy stacks lands where the same ticks one at a time land.** Twenty ticks read in
one frame, up from the end of a scroll view holding two long `LazyVStack`s one below the other, put the screen about
two dozen lines away from where twenty single ticks put it, and twenty more snapped back to the last rows: a move of
more than four screens was placed by the rows' average height, which a stack under another view counts from a place
of its own. A move of up to 256 lines is now walked row by row whatever the screen's height.

**A lazy stack under a title is settled on and held as one that is a scroll view's whole content.** In a scroll
view whose `VStack` held a title over a long `LazyVStack` marked `.scrollTargetLayout()`,
`.scrollTargetBehavior(.viewAligned)` stopped a wheel tick or a key inside a row and `.paging` cut rows at a page's
edge, as if the stack were not marked; rows inserted above the ones on screen pushed them down; and a row held with
`.anchorPosition(.row(id))` drifted with the rows around it. Each behaves now as for a lazy stack that is the scroll
view's whole content. A row held in a stack other than the one at the top of the screen is not held yet.

**The search field's ✗ stands one cell past the field, and only the ✗ empties it.** It stood three cells out, and a
click on the two blank cells before it emptied the field too: a plain button kept two cells in front of its label for
a focus bullet even under `.focusable(false)`, where it can never show one. A plain button there is now its label
alone, as SwiftUI's is, so a `Menu`'s caret beside a plain primary action sits against it too. `.hidden()` still
keeps a plain button's cells, so hiding one moves nothing.

**A long lazy stack inside a `Layout` of your own in a scroll view draws only the rows on screen.** A `LazyVStack`
of thousands of rows among the subviews of a layout an app writes (`MyColumns { header; LazyVStack { … }; footer }`)
was drawn whole: a first frame built every row several times over (43,000 row builds for 10,000 rows), and a
`scrollTo` into it built 118,000. It is now drawn from the placements the layout makes, as one in a `VStack` or an
`HStack` is: a frame builds a screenful of rows, whatever their count, and the wheel, End, `scrollTo` and Tab reach
every one, the stack written plainly or in an `if`. A layout that puts two such stacks one below the other still
draws them whole.

**An overlay on a long lazy stack in a scroll view stands where its alignment puts it on the whole stack.**
`.overlay(alignment: .bottom) { badge }` on a `LazyVStack` of thousands of rows drew the badge at the foot of every
screenful as you scrolled: the overlay was laid out against the rows drawn, not the stack. It, and a background that
is a view, are laid out against the whole stack now, as SwiftUI lays them out, and show only where that falls on
screen. A colour or a shape that fills the stack is drawn as before.

**Shift-Tab steps back to the control above a long lazy stack once it is scrolled out of sight.** In a scroll view
whose `VStack` held a long `LazyVStack` under a button, scrolled a line or two down, Shift-Tab from the stack's first
row skipped the button and went on to the control before the scroll view, and Tab from the button, once it had
scrolled back into view, skipped the stack's first row: the controls above the scroll position were filed in the focus
order after the rows below it. They are filed in the order they stand, as with an eager `VStack`.

**`scrollTo` finds a row inside a lazy stack that is not the scroll view's whole content.** `proxy.scrollTo(id)`
and `ScrollPosition.scrollTo(id:)` looked for the id only among the rows of the stack that was the scroll view's
content, so a row of a `LazyVStack` under a title, in the second of two stacks, in a `GroupBox`, beside a gutter
in an `HStack` or in either of two stacks side by side, or a message in each day's stack inside an outer stack of days, was silently not scrolled to. It is
found now at any depth, rows never built included — the rows before it are measured to look, once per call, with
no `onAppear` run and nothing drawn on screen — and lands where the anchor asks: `.top`, `.center`, `.bottom`, or, with none, as little movement as shows it.
An eager `VStack`'s rows are searched the same way, and so is a `.id(_:)` on one of its own children.

**Dragging a scroll view's thumb no longer makes the rows under the pointer jump back and forth.** Where a scroll
view's height is an estimate — a long lazy stack of rows of different heights — the estimate improved as the drag
brought new rows into view, and each move of the pointer was read against the new one. A drag now reads every move
against the height it started with, and the thumb settles to the improved one when you let go.

**A scroll view's first frame no longer draws every row of a long lazy stack in it.** An app's first frame begins
with a walk of the page that measures it, and a scroll view drew its content all the way down on that walk: a
`LazyVStack` of 10,000 rows built every row twice before the first frame showed, and a long `List` drew 4,096 lines.
It now draws only down to the bottom of what is visible: 124 rows for the lazy stack.

**A long `LazyVStack` anywhere in a scroll view's content draws only the rows on screen.** Under a title, beside
another in one `VStack` (in an `if` among its views too), or in each row of an outer `LazyVStack`, a lazy stack of more than 256 rows was measured
over every row and drawn whole, on every frame that changed anything: a feed of forty sections of 300 entries built
27,932 rows a frame. The `VStack` or `LazyVStack` that holds one now places it outward from the scroll position, as
a lazy stack that is the scroll view's whole content always was, so it builds about a screenful. Its height, and so
the scrollbar, "~N more" and `onScrollGeometryChange`'s content size, is now an estimate for rows of varying height,
as it already was for a lazy stack that is the whole content, and `onGeometryChange` on it reports the rows it draws.
So does one inside a `GroupBox`, a `.border()` or another box, an `HStack` or a `ZStack`: the box draws its top
line only while the stack's first row is on screen, and its bottom line and footer only with its last. So does one in
a `TabView`'s tab, under its strip, and on a pushed `NavigationStack` screen, under its bar. A lazy stack in a `Grid`
is still drawn whole, as before.

**A `NavigationSplitView` in a `ScrollView` or under `.fixedSize` is as tall as its tallest column.** Offered no
height, it answered one line: in a scroll view it took the viewport's height, so the sidebar's rows past it could
not be scrolled to, and under `.fixedSize(horizontal: false, vertical: true)` it was a single line. It now answers the
height of its tallest visible column, as `HSplitView` does. Offered a height, it still takes all of it.

**On a screen more than 4,096 columns wide, a press far from an open menu closes it.** The region behind an open
menu that takes a press outside it reached 4,096 cells from the menu, so a press farther away left the menu open and
reached the page under it. It now covers the screen.

**An alert's long message and a text field's long prompt are no longer cut.** An alert read its message off a
canvas 4,096 cells square, so a line past the 4,096th never reached the alert, though it scrolls long messages, and
a paragraph wider than that was broken early; a `TextField` with `axis: .vertical` read its prompt the same way. A
field on one line showed no more than the first 100 cells of its prompt, however wide the field. Each is now read at
its natural size.

**A paragraph wider than 4,096 cells in a horizontal `ScrollView` stays on one line.** Asked how wide it would be
with nothing stopping it, a `Text` answered wrapped at the 4,096 cells the scroll view offered first, so a longer
paragraph broke at the last space before that and was drawn as two lines, its tail under its head, instead of
scrolling on. It now answers with its lines unwrapped, as SwiftUI's does.

**A `Table` in a vertical `ScrollView` is its rows' height.** Tables stacked in a scroll view with no frame were
each dealt an even share of the height their rows added up to, so a short one was drawn with blank rows after its
last and a long one was cut short, scrolling inside the page. Now each is as tall as its rows, its header and border,
and the page scrolls past them, up to the scroll view's own height: a table taller than that is that tall and scrolls
its rows within it, building only the rows on screen. A `.frame(height:)` still gives a table a height to fill, as
before. (SwiftUI draws such a table 0 points tall; this is deviation L19.)

**A `Table` whose columns do not fit scrolls sideways.** The columns were squeezed until their cells were nothing but
`…`, six of them in a narrow table showing only ellipses, and a column with a `.width(min:)` wider than the table hid
the rest with no sign they were there. Now, once the columns' minimum widths exceed the table's width (a column that
states none is never narrower than its header), the table scrolls a whole column at a time, the header with it, and
a horizontal scrollbar under the rows shows where you are (placed `.overContent`, over the rows' last line for the
pointer while the table does not hold the focus). → and ← move it where the rows have no use for them, ⇧→
and ⇧← in any table, as do the sideways wheel, Shift with the wheel and the scrollbar; a column picked with ⌃K or
sorted by with ⌃S scrolls into sight, and a title dragged to the table's edge scrolls it a column and moves on past.
A table whose columns fit is unchanged.

**A grouped `Form` scrolls, as SwiftUI's does.** A form in `.formStyle(.grouped)` taller than its space was cut off, and
Tab could move the focus onto a control below the window, out of sight. It is a scroll view now, as SwiftUI's is on
macOS: the wheel and the Page Up, Page Down, Home and End keys the focused control leaves scroll it, and Tab scrolls
the control it lands on into view. Like SwiftUI's, it fills the space it is offered rather than hugging its sections,
its sections spanning its width, so views below it in a stack move to the bottom, and the scroll modifiers written on it (`.scrollIndicators`,
`.scrollPosition`, `.contentMargins` and the rest) apply to it. A columns form, the default, still does not scroll,
as SwiftUI's does not.

**Under `TUI_PLAIN_TEXT`, a scrollbar's thumb is solid.** Its ends, drawn to an eighth of a cell, were `#`s in the
groove's colour; every cell the thumb touches is now a whole cell of it. And the gradient editor's dashed rule is
`- - -`, where it was solid.

**Under `TUI_PLAIN_TEXT`, a large solid button is a solid block of its colour.** Its rows above and below the label
were its rounded corners in `#` (`##    ##`); the face is now drawn in whole cells there, as on Apple Terminal.

**Under `TUI_PLAIN_TEXT`, a box keeps its lines' weight, and Braille its shape.** Sent as plain text, every line was
`-` or `|` and every corner `+`, so a heavy, a double and a rounded box were all one light box, and every Braille cell
was `.`, a blank one too. A heavy box is now `#=====#`, a double one `+=====+`, a rounded one `.-----.` over
`'-----'`, and a dashed line down `:`; a Braille cell is `'`, `.`, `:` or `#` by where its dots are, and blank where
it has none, so a Braille border, a Braille-dotted button and a Braille picture keep their outlines. The barber-pole
progress style, blank before, is `////`, and a scrollbar's triangle arrows `/\` and `\/`.

**A control named with `.focusID(_:)` answers to its `@FocusState`.** `TextField(…).focusID("email")
.focused($field, equals: .email)` kept its name, but the binding pointed at a name of its own that no control had, so
setting `field = .email` moved the focus nowhere and `field` never read `.email`. The binding now follows the control
to the name it was given.

**A Shift-arrow range in a `List` or a `Table` starts from the row you chose, when the rows change under it.** The
row a range is measured from stayed at its place rather than with its row, so after a row arrived above it, or the
table was sorted, the next Shift-Down or Shift-click selected rows from somewhere else. It now follows its row, as the
cursor does.

**With the focus following the pointer, a segmented picker's and a radio group's cursor follow it.** The segment or
option the pointer moves onto becomes the one the arrow keys, Space and Return act on, as a list's cursor row already
did; the choice stays until you click or press Space or Return. A disabled option and the rule between two segments
move nothing.

**A view inserted again while it is leaving comes back from where it is.** It started its arrival from nothing, so a
view fading out flashed to blank and a `.push` sliding out jumped to the far side to slide in again. It now returns
from wherever its removal has it, the removal running on beneath its return as SwiftUI's does: a fade goes on down a
little and comes back up, and a `.push` or `.slide` slides back in from the side it was leaving by.

**A view removed part-way through its arrival leaves from where it is.** A `.push`, a `.slide` or any `asymmetric`
transition whose removal goes the other way jumped to the far side on the first frame of its removal: 30% in, it went
from 70% off the trailing side to 70% off the leading one. It now crosses its slot from where it was, its arrival
running on beneath the removal as SwiftUI's does; a `.move`, an `.opacity` and an `if`'s default fade keep moving
towards their place for a moment before they turn back, rather than turning at once.

**A lazy stack's row leaving by its own transition no longer hides the row that took its place.** The row was
drawn over the rows where it had been, blank cells and all, so under a row as wide as the stack, as a list's row
with a spacer is, the row that moved up was hidden until the removal ended. Only the cells the leaving row paints
are drawn now; the row beneath shows everywhere else.

**A `Form` too narrow for its labels keeps its checkboxes in the control column.** A field row squeezed its label and
its value between them, but a checkbox or a radio group was indented the whole width of the labels, and its title
wrapped a letter or two to a line at the right edge. The label column now gives way, to what the widest control
leaves or half the width, and every row is laid out to it.

**An inspector hidden and shown again is as wide as you left it.** It came back at its default width, whatever you
had dragged it to. So does a pane of your own in an `HSplitView` or a `VSplitView` that comes and goes.

**A `NavigationSplitView` column keeps the width you gave it when the terminal narrows for a while.** A terminal
too narrow for a column you had widened held it in, and the column stayed that narrow once the terminal was wide
again. It now goes back to your width as soon as there is room.

**An `HSplitView` or a `VSplitView` the terminal narrows and widens again puts its dividers back.** Each resize scaled
the panes from the last resize's rounded sizes, so the dividers crept towards the leading edge, a cell or more each
time. The panes are now scaled from the sizes last set, by a divider or at the start.

**A toolbar item the bar is too narrow to show no longer takes the focus.** A top or bottom bar with more items than
it has room for cuts the last of them, and Tab still went to a button it had cut to nothing, so the focus vanished and
Return pressed a button nobody could see. Such an item now takes no focus and no click, and its keyboard shortcut
still works.

**With the focus following the pointer, a control's label focuses the control.** Moving onto the label of a
`Slider`, `Stepper`, `Picker`, `DatePicker`, `ColorPicker` or `LabeledContent`, beside it or in a form's label
column, focuses the control, as moving onto the control does.

**With the focus following the pointer, a list's cursor row follows it.** Over a `List`, a `Table` or an outline,
the row the pointer moves onto becomes the row the keys act on; the selection stays until you click or press Space
or Return (under `.selectionFollowsCursor()` too, or until an arrow moves the cursor on), and rows the wheel scrolls under a still pointer leave the cursor where it was. A closed menu bar title
still opens nothing under the pointer.

**A circular `Gauge` shows its value without colour.** The lit part of `.accessoryCircular`'s and
`.accessoryCircularCapacity`'s ring was the accent and nothing else, so without colour, or where the terminal's colours
round the accent onto the ring's grey, the ring looked the same at every value, and one without a value label said
nothing. There, and under Differentiate Without Color, the lit cells are now drawn in heavy lines (`#` and `=` under
`TUI_PLAIN_TEXT`).

**Under `TUI_PLAIN_TEXT`, a tiny circular gauge shows how full it is.** `.accessoryCircularTiny`'s dial was blank at a
quarter, a half and three quarters, and `o` both empty and full. It is now `.` `:` `+` `*` `#` from empty to full.

**Under `TUI_PLAIN_TEXT`, a progress bar's, a slider's and a gauge's track reads as a track.** Sent as plain text, a
`.bar` track read `]]]]]]--------`, a `.dot` track had no fill, a `.braille` track was dots from end to end, and the
two rails of a slider's `.knob` were the same. Each now draws its own ASCII: `########--------`, `=======o--------`,
dots then spaces, and `=======o--------`.

**A graphical `DatePicker` shows its selected day without colour.** The day was marked only by an accent fill, which
a terminal without colour (or `NO_COLOR`) doesn't draw, nor one whose colours round the accent onto the page: no day
looked chosen, and the arrows moved the date with nothing on the screen following it. There the day is now drawn in
reverse video.

**A graphical `DatePicker` shows the month its selection moved to.** When something other than the calendar moved
the date into another month, a date field beside it or the app itself, the calendar went on showing the month it had,
with no day selected in it. It now turns to the new month, as SwiftUI's does; a month turned with its ◀ and ▶ stays
while the date stays put.

**A scroll view keeps its layout while the focus moves inside it.** Under `.overContent` placement (the default), a
scroll view's indicators sit beside its content while the focus is anywhere inside it — on the view, on a control in
it, or on a scroll view in it — not only on the view itself. Moving the focus among the controls of a page, by Tab or
with the focus following the pointer, no longer moves a scroll view's bar over its content and back, so the content no
longer jumps, and a nested scroll view no longer slides out from under the pointer. A page under a sheet or an alert
keeps the layout it had. Lists, tables and text editors follow the same rule.

**Every segment of a segmented picker answers the pointer.** The segment under the pointer shows it as a button
does, on a hovered face; before, only its label's ink changed, and on most terminals that showed nothing. With the
focus following the pointer, a move onto any segment, or onto any option of a radio group, focuses the picker; before,
only the one under its cursor did. The Settings panel's tab strip is one.

**The Example keeps its palette and control style.** The palette chosen in View ▸ Palette, on the Theme page or with
⇧F2, and the control style, are the ones the next launch starts in, kept with `@AppStorage` as an app keeps its own
choices. An edit of a single colour lasts the run.

**`TUI_BREATHING=1`, `TUI_KEY_SYMBOLS=1` and `TUI_ARROW_FOCUS=tab` undo a kept setting for one launch.** Each
variable said only one thing, so a still focus, keys spelled out or Arrows Follow Layout kept in the settings panel could
not be undone for one run; now each says the other too, and wins over what is kept, as `TUI_REDUCE_MOTION=0` does.
`TerminalClient.keyNotationRequested` is `nil` where the variable says nothing.



**A `navigationDestination(isPresented:)` on a stack's root, presented while values are pushed, empties the path,
as in SwiftUI.** Its screen went over the values, and Back returned to the last of them; it now goes over the root, the
screen it is written on, and Back returns there. The same for `navigationDestination(item:)`.

**`.aboutPanel(applicationName:…)` is the app's, whichever window is in front.** Written on one scene, the name
titled the app menu only while one of that scene's windows was in front, and a `Window` without it, such as an
inspector, brought the process's name back. It now holds for every window, as an Info.plist does; written on several
scenes with different values, the first scene's wins.

**A disabled radio button's label is drawn disabled.** Its label was drawn as an enabled option's, in every
palette, so only the `◌` beside it said it could not be chosen; it is now in the grey every disabled control's label is,
as a toggle's is, whether the group, the option or an enclosing `.disabled()` disables it. And at no colour a disabled
stepper's, slider's, picker's or date picker's label is faint, as its control is; it was drawn as an enabled one's.

**The Example's Text Styles page has a sliding underline.** Beside *Underline by word*, whose front end runs ahead
to the next word before its back end follows, *Sliding underline* moves both ends together, eased, from one word to the
next.

**F1's list of shortcuts is a bordered dialog, centred, in columns.** Its sections sit side by side, as many as the
window is wide enough for, short ones sharing a column; where the window is too short, a long section carries on
into the next column under its heading again rather than scroll. It scrolls downwards only when the window can't
show it all, and never sideways.

**A playing picture converts its frames ahead, off the main actor, and no longer stutters when a setting changes.**
An animated `Image` drawn as glyphs converted each frame the first time it showed, in the render that showed it, so a
costly setting (`imageShapeAware`, a dither) made every frame of the first loop late, and again after each change.
Its frames are now converted in a background task, in the order they will show: after a change the old frames go on
playing until every new one is ready, and the first time round each is kept as soon as it is converted. A
shape-aware frame of the Example's bouncing ball costs 5 to 8 ms in a release build and 200 to 300 ms in a debug one.
**In mono, an animated picture's frames share one ink threshold.** Measured from each frame, Otsu's split moved
with what moved in the picture, and a part that held still could cross it: the Example's old bouncing ball drew its
ground white in some frames and black in others. The split is now measured once across every frame, for the glyphs
and for real pixels alike, unless `imageInkThreshold(_:)` states one.
**The Example's animated picture shows what real pixels draw.** The bouncing ball is now a shaded, lit, chequered
ball at 320 × 200 over a floor running off to a hazy horizon, with a soft shadow, drawn by
`Tools/ExampleImages/make_bouncing_ball.py`; the old one was 80 × 40 pixel art, which looked the same in glyphs and
in Kitty graphics. It is 102 KB more.

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
each name, a control's half-block ends `[ ]` (a field's, a button's, a picker's, a tab's), and a one-row rounded
shape's `( )`, so a tag on a `Capsule` reads `(Beta)` where it read `#Beta#`, while a half block elsewhere, a Canvas's
or a picture's, is `#`; before, `■` and `□` were both `#`, empty radio buttons and half the spinners were blank, and
a toggle in a menu read `:white_large_square:`. Under `TUI_PLAIN_TEXT=transliterate`, an SF Symbol is spelled by its
name, `:star:`, where it vanished, and `❤` typed without its selector is `<3`. Both remain for testing; nothing
changes without the variable.

**A dialog no longer jumps when a tooltip appears in the status bar.** A sheet, alert or other dialog centred over
the page stays where it is as help shows and goes in the status bar, and moves up only where the tooltip's rows
would cover it. A page laid out in the middle of the window does the same.
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

**`TUI_TEXT_CURSOR_FOLLOWS_FOCUS=1` tries out the terminal's own text cursor on the focused control.** An experiment,
off by default, for judging what screen readers, braille displays and magnifiers make of it: after each frame the
terminal's text cursor (not the mouse pointer, which `TUI_FOCUS_FOLLOWS_POINTER` is about) goes to the focused control's
first cell (a text field's insertion point, as before) and is shown there; `hidden` puts it there and keeps it hidden.
See `Documentation/Input and focus/Text cursor follows focus (proof of concept).md`.

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
- The status bar draws an item's one-letter key as a macOS menu draws it: `Q quit` for `"q"`, `⇧N` for an item on `"N"`, matching `⌃Z undo` beside it. The item's string still binds the key. `.keyLetterCase(.asTyped)` draws a letter pressed alone as typed (`q quit`), Shift still as `⇧N`.
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
