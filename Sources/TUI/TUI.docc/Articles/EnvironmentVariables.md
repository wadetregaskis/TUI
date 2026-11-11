# Environment Variables

Change how an app behaves without changing its code, and know which setting wins when several say different things.

## Overview

Whoever runs an app built with TUI can set an environment variable to change something about it for that run, or for every run if it's in their shell's profile:

```
NO_COLOR=1 myapp
TUI_REDUCE_MOTION=1 myapp
TUI_GRAPHICS=0 swift run MyApp
```

Those three are the ones people reach for most: `NO_COLOR=1` turns colour off, `TUI_REDUCE_MOTION=1` asks for less motion, and `TUI_GRAPHICS=0` draws pictures as text characters instead of pixels.

Most people never need one, because TUI works out what each terminal can do. They're there for when it gets that wrong, for what only the person knows they need, and for trying out how an app looks somewhere else.

This page says which setting wins, then lists every variable: <doc:EnvironmentVariables#For-People-Running-an-App>, <doc:EnvironmentVariables#For-Developers-Building-an-App> and <doc:EnvironmentVariables#What-TUI-Works-Out-for-Itself>. To put the list in your own app's man page, see <doc:ShippingAnApp#Documenting-Environment-Variables>.

## Which Setting Wins

**What your code states wins over a variable, and a variable wins over what TUI would otherwise do.** Your code can state a setting in a view modifier, an environment write or an assignment. What TUI would otherwise do includes what it reads from the system: `TUI_REDUCE_MOTION=0` turns off a machine-wide Reduce Motion, and `COLUMNS` and `LINES` win over the size the terminal reports, even if they're out of date.

There's one deliberate exception, and one thing that doesn't count as stating anything:

- **What someone asks for so that they can use the program at all can't be taken away.** ``Scene/reduceMotion(_:)`` can ask for less motion, but `false` doesn't undo `TUI_REDUCE_MOTION=1`. The person knows they need it, and the app doesn't. The same goes for `TUI_KEY_SYMBOLS=0`, the other accessibility variables, and `TUI_OPEN_URLS=0`, where the person is saying "not on this machine".
- **An app can choose a global setting, but its ordinary drawing doesn't count as choosing.** Under `NO_COLOR`, `.foregroundStyle(.red)` draws no colour, or no app would honour `NO_COLOR`. Assigning ``ColorDepth/current`` does override it, as [no-color.org](https://no-color.org) says a program's own flag or config may. It's the same with `TUI_GRAPHICS=0` and `.terminalGraphics(true)`, with `TUI_HYPERLINKS=0` and a `Link`, and with `TUI_POINTER_SHAPES=0` and `.pointerStyle(_:)`. Each asks for something if it's available, and each has a global setting that decides.

Some variables have nothing to state in code, such as `TUI_KEYBOARD_PROTOCOL=0`, the way out if a terminal gets the protocol wrong. So those are the only way to set that.

An empty variable counts as unset, which is how a shell clears one: `NO_COLOR= myapp`. A value that isn't listed is ignored, rather than guessed at.

### Command-line flags

TUI doesn't read your app's command line. A flag you read is your own code, so it wins over a variable when you pass what it says to the same setting, and "a flag beats a variable" is an order you get by doing that:

```swift
@main
struct Viewer: App {
    @MainActor init() {
        let flags = CommandLine.arguments
        if flags.contains("--color=always") { ColorDepth.current = .truecolor }
        if flags.contains("--color=never") { ColorDepth.current = .noColor }
        if flags.contains("--no-pictures") { TerminalClient.graphicsSupport = false }
        if flags.contains("--open-links") { TerminalClient.urlOpeningSupport = true }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .reduceMotion(CommandLine.arguments.contains("--reduce-motion"))
    }
}
```

Set these before the first frame, since some are read once. <doc:EnvironmentVariables#What-code-can-do-about-each-variable> lists what's read when.

A tool that uses ``renderOnce(output:content:)`` also says how its output should be written when a flag decides: `output: .escapeSequences` for `--color=always`, even down a pipe, and `output: .plainText` for `--color=never`.

So the order is your code, then a flag, then a variable, then TUI's default:

1. A value your code states outright leaves no flag to read.
2. A flag wins over a variable when your code passes what it says to the setting.
3. A variable wins when your code states nothing, which includes a flag that wasn't given.
4. TUI's default applies when nothing else says.

Step 3 depends on how you read the flag. Only pass it on if it was given, or a flag's default overrides the variable. With swift-argument-parser (<doc:ScenesAndQuitting#With-swift-argument-parser>), that means an optional value rather than a default:

```swift
struct ViewerCommand: AsyncParsableCommand {
    @Option var color: String?  // nil when not given, and then NO_COLOR still counts

    func run() async {
        if color == "always" { ColorDepth.current = .truecolor }
        if color == "never" { ColorDepth.current = .noColor }
        await Viewer().run()
    }
}
```

The exception at the top of this page still holds: `.reduceMotion(false)` doesn't undo `TUI_REDUCE_MOTION=1`, whether or not a flag asked for it.

### Setting a variable from code

Don't write a variable to state a setting. Many are read once, and `setenv` isn't safe while another thread reads the environment. Use the setting <doc:EnvironmentVariables#What-code-can-do-about-each-variable> gives. Where it gives none, the variable is for the person running the program.

## For People Running an App

These change what you see and how the keys and the mouse behave. Set one for a single run by writing it before the command, or for every run by exporting it from your shell's profile:

```
TUI_REDUCE_MOTION=1 myapp
export NO_COLOR=1
```

An empty value counts as unset, and a value a table doesn't list is ignored. Those marked as an experiment may change or go. The standard variables other programs read, such as `NO_COLOR`, `TERM`, `LANG` and `COLUMNS`, mean here what they mean everywhere else. What your terminal, tmux or ssh sets for you is under <doc:EnvironmentVariables#What-TUI-Works-Out-for-Itself>.

These tables are generated from the same text an app's man page gets, so the page and the man page say the same.

<!-- tui-environment-docs: end-user -->
### Colour and appearance

| Variable | Values | Effect |
|---|---|---|
| `NO_COLOR` | Any value, even `0` | Turns colour off, as the no-color.org convention asks. Bold, underline and italics stay, and so do pictures drawn in real pixels. For example: `NO_COLOR=1 myapp`. |
| `FORCE_COLOR` | A number, or a word such as `true` | Asks for colour, whatever the terminal seems able to show, as the force-color.org convention asks. `1` asks for at least 16 colours, `2` for at least 256, and `3` for millions. `0` or `false` turns colour off instead. Any other value, such as `true`, asks for what the terminal shows, but at least 16 colours. `NO_COLOR` wins over it. |
| `CLICOLOR_FORCE` | Any value but `0` or `false` | Asks for colour, whatever the terminal seems able to show: what it shows, but at least 16 colours. `NO_COLOR` and `FORCE_COLOR` win over it. |
| `CLICOLOR` | `0` or `false` | Turns colour off. Any other value changes nothing, since the program uses colour anyway. `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR_FORCE` win over it. |
| `COLORTERM` | `truecolor` or `24bit` | Says that the terminal shows millions of colours. Your terminal sets this itself, but ssh doesn't pass it on, so if colours look coarse on another machine, set it there: `COLORTERM=truecolor myapp`. |
| `TERM` | A terminal type, such as `xterm-256color` | The kind of terminal, which says how many colours it shows. Your terminal sets this itself. With `dumb` there's no colour, and a full-screen program takes it that there's no screen to draw on. |
| `TUI_INCREASE_CONTRAST` | `1` or `0` | `1` asks for more contrast, where the program has it. `0` asks for standard contrast, even with Increase Contrast on in your computer's settings. Unset, what you've kept in the settings panel decides, and otherwise your computer's own setting, when you're at the machine the program runs on. The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program. |
| `TUI_DIFFERENTIATE_WITHOUT_COLOR` | `1` or `0` | `1` asks for signs that don't rest on colour alone: the control your keys act on is shown in reverse video, one you can't use is faint, and a table's selected rows have a dot. `0` turns these off, even with Differentiate Without Color on in your computer's settings. Unset, what you've kept in the settings panel decides, and otherwise your computer's own setting, when you're at the machine the program runs on. The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program. |
| `TUI_REDUCE_TRANSPARENCY` | `1` or `0` | `1` draws see-through panels and glass solid. `0` keeps them see-through, even with Reduce Transparency on in your computer's settings. Unset, what you've kept in the settings panel decides, and otherwise your computer's own setting, when you're at the machine the program runs on. The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program. |

### Motion

| Variable | Values | Effect |
|---|---|---|
| `TUI_REDUCE_MOTION` | `1` or `0` | `1` turns animations off: things jump to where they're going instead of gliding there, and the program can't undo it. `0` keeps animations, even with Reduce Motion on in your computer's settings. Unset, what you've kept in the settings panel decides, and otherwise your computer's own setting, when you're at the machine the program runs on. The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program. For example: `TUI_REDUCE_MOTION=1 myapp`. |
| `TUI_BREATHING` | `0` or `1` | `0` stops the highlight on the control your keys act on from slowly pulsing or blinking: it's shown by colour and bold, and a control already in that colour, like a ticked checkbox or a link, shows it with its label in reverse video. The text cursor still blinks. `TUI_REDUCE_MOTION` doesn't do this by itself. `1` lets it pulse, even where you've kept it still in the settings panel. Unset, what you've kept there decides, else it pulses. The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program. |

### Keyboard and mouse

| Variable | Values | Effect |
|---|---|---|
| `TUI_KEY_SYMBOLS` | `0` or `1` | `0` writes keyboard shortcuts out in words, such as `Ctrl-Shift-Z`, instead of in symbols, for a font that has no symbols for the keys. `1` writes them in symbols, even where you've kept the words in the settings panel. Unset, what you've kept there decides, else symbols. The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program. |
| `TUI_ARROW_FOCUS` | `geometric` or `tab` | An experiment. `geometric`: when the control your keys act on doesn't use an arrow key itself, the arrow moves to the nearest control in that direction, scrolling to it if it's out of sight, so Down goes to the button below. At the edge it stays put instead of wrapping around. Tab and Shift-Tab are unchanged. `tab`: the arrows go in the same order as Tab, even where you've kept Arrows Follow Layout on in the settings panel. Unset, what you've kept there decides, else the order of Tab. The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program. |
| `TUI_FOCUS_FOLLOWS_POINTER` | `1` or `0` | `1`: moving the mouse onto a control makes it the one your keys act on, as a click would, without pressing it. A text field you've typed in keeps your keys until you click or press Tab. `0`: only a click or the keyboard does that. Unset, the program decides, and where it doesn't, what you've kept in the settings panel, else it's off. The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program. |
| `TUI_TEXT_CURSOR_FOLLOWS_FOCUS` | `1`, `show` or `hidden` | An experiment, for a screen reader, a braille display or a magnifier that follows the terminal's text cursor: the text cursor (not the mouse pointer, which `TUI_FOCUS_FOLLOWS_POINTER` is about) moves to the control your keys act on after each change. `1` or `show` shows it there, and `hidden` moves it there but keeps it hidden. Unset, the cursor is hidden except in a text field you're typing in. |
| `TUI_SPRING_LOADING_DELAY` | Seconds, such as `0.3` or `1` | How long you hold a dragged item over a control, such as a tab or a folder, before it opens. Unset, your Mac's own setting, when you're at the machine the program runs on, and otherwise half a second. |
| `TUI_SHIFT_CLICKS` | `0` | Leaves Shift-click to the terminal, which usually selects text with it, instead of passing it to the program. |
| `TUI_POINTER_SHAPES` | `0`, `1` or `apps` | Whether the mouse pointer changes shape over the program, such as to an I-beam over a text field. `0`: never. `1`: yes, even where the program can't tell that the terminal can. `apps`: only for the shapes the program asks for itself, not those of its ordinary controls. Unset, yes where the terminal is known to do it. |

### Text and language

| Variable | Values | Effect |
|---|---|---|
| `LANGUAGE` | A list of languages, such as `pt:es` | The languages for the program's words, most wanted first. It wins over the variables below. A language you pick inside the program wins over it. For example: `LANGUAGE=de myapp`. |
| `LC_ALL` | A locale, such as `de_DE.UTF-8` | The language, unless `LANGUAGE` says otherwise, the region dates and numbers are written for, and the character set. It wins over the variables below. |
| `LC_MESSAGES` | A locale, such as `de_DE.UTF-8` | The language, unless `LANGUAGE` or `LC_ALL` says otherwise. |
| `LC_TIME` | A locale, such as `de_DE.UTF-8` | The region dates and numbers are written for, unless `LC_ALL` says otherwise. |
| `LC_NUMERIC` | A locale, such as `de_DE.UTF-8` | The region dates and numbers are written for, unless `LC_ALL` or `LC_TIME` says otherwise. |
| `LC_CTYPE` | A locale, such as `de_DE.ISO8859-1` | The terminal's character set, unless `LC_ALL` says otherwise. Anything but UTF-8 says the terminal shows nothing beyond plain ASCII, so the program sends ASCII alone. |
| `LANG` | A locale, such as `fr_FR.UTF-8` | The language, the region and the character set, wherever none of the above says. For example: `LANG=fr_FR.UTF-8 myapp`. |

### Screen size and printed output

| Variable | Values | Effect |
|---|---|---|
| `COLUMNS` | A whole number above 0 | How many columns wide to draw, instead of the window's width. Unset, the window's width, or 80 where there's no window, such as when the output goes down a pipe. While it's set the program doesn't follow the window as you resize it, so if a program draws at the wrong size, look for a leftover export with `echo $COLUMNS` and clear it with `unset COLUMNS`. |
| `LINES` | A whole number above 0 | How many lines tall to draw, instead of the window's height. Unset, the window's height, or 24 where there's no window. While it's set the program doesn't follow the window as you resize it, so if a program draws at the wrong size, look for a leftover export with `echo $LINES` and clear it with `unset LINES`. |
| `TUI_FORCE_ESCAPES` | `0`, or any other value | For a program that prints once and exits, rather than taking over the screen. `0` prints plain text. Anything else prints styled text, even into a file or down a pipe, as in `TUI_FORCE_ESCAPES=1 mytool > out.txt`. `NO_COLOR` still takes the colours out. |

### Links, notifications and the clipboard

| Variable | Values | Effect |
|---|---|---|
| `TUI_OPEN_URLS` | `0` or `1` | Whether the program may open a link in your web browser. Off by default, because the program can't tell whether it's running on the computer in front of you or on one you've reached over ssh. `1` allows it, unless the program says no. `0` never allows it, whatever the program says. |
| `TUI_HYPERLINKS` | `0` or `1` | Whether links are sent so that the terminal can open them when you click (OSC 8). `0`: never, and the link's text still shows. `1`: always. Unset, where the terminal is known to handle them. |
| `TUI_OSC52` | `0` or `1` | Whether copying puts text on your clipboard through the terminal (OSC 52), which works over ssh too. `0`: never. `1`: always. Unset, where the terminal is known to allow it. |
| `TUI_OSC5522` | `0` or `1` | Whether copy and paste through the terminal can carry more than plain text (OSC 5522). `0`: never. `1`: always. Unset, where the terminal says it can. |
| `TUI_NOTIFICATIONS` | `0` or `1` | Whether the program sends notifications to your desktop at all, and whether they go through the terminal, which shows them as your desktop's own. `0`: none at all, neither through the terminal nor posted by this computer, so a program asking for your attention rings the bell instead. `1`: always through the terminal. Unset, through the terminal where it's known to show them, and elsewhere as `TUI_SYSTEM_NOTIFICATIONS` says. |
| `TUI_SYSTEM_NOTIFICATIONS` | `0` or `1` | Whether a notification the terminal can't show is posted by this computer itself, with `osascript` on macOS or `notify-send` on Linux. `0`: never. `1`: wherever the program can't tell where you are, such as inside zellij or GNU screen at your own desk. Unset, only where the program can tell you're at this computer, and never over ssh. On macOS these are Script Editor's notifications, so they show only where System Settings > Notifications > Script Editor allows them. A notification never comes twice: a terminal that shows them always gets them instead. `TUI_NOTIFICATIONS=0` turns these off too, whatever this says. |
| `TUI_PROGRESS` | `0` or `1` | Whether the terminal is told how far a long task has got, to show in its tab or its window. `0`: never. `1`: always. Unset, where the terminal is known to show it. |

### Terminal quirks

| Variable | Values | Effect |
|---|---|---|
| `TUI_TERM_PROGRAM` | `Apple_Terminal`, `iTerm.app`, `ghostty`, `WarpTerminal`, `tmux` or `gnome-terminal` | Says which terminal this is, when the program can't work it out and emoji or borders look out of line, as in `TUI_TERM_PROGRAM=ghostty myapp`. Under tmux, tmux's own answer counts. The program sets it itself when it had to ask the terminal, so a program it starts knows too. |
| `TUI_GRAPHICS` | `0`, `1`, `classic` or `sixel` | How pictures are drawn, without asking the terminal what it can do. `0`: in text characters, which works everywhere. `1`: in real pixels, by the Kitty graphics protocol. `classic`: the same, for a terminal with the protocol's older form alone. `sixel`: in real pixels, by Sixel. Unset, the program asks the terminal. For example: `TUI_GRAPHICS=0 myapp`. |
| `TUI_GRAPHICS_COMPRESSION` | `0` or `1` | Whether pictures are compressed on their way to the terminal. Unset, the program asks the terminal. Try `0` if pictures don't appear. |
| `TUI_GRAPHICS_PLAYBACK` | `0` or `1` | An experiment. `1` hands an animated picture to the terminal to play by itself after it's been sent once, which saves sending each frame. It works only on a terminal that plays Kitty animations: on any other, the picture stops at its first frame. Off unless it's `1`. |
| `TUI_HAIRLINES` | `0` or `1` | Whether the thin lines between a list's rows are drawn as pictures, finer than any character. `0`: never. `1`: always. Unset, only on Ghostty, where they've been checked. |
| `TUI_PICTURES_UNDER_TEXT` | `0` or `1` | Whether text over a frosted picture is drawn on top of the picture itself. `0`: never. `1`: always. Unset, only on Ghostty, where it's been checked. |
| `TUI_KEYBOARD_PROTOCOL` | `0` | Doesn't turn on the terminal's fuller report of the keys (the Kitty keyboard protocol). Try it if keys or shortcuts do the wrong thing. |
| `TUI_PIXEL_MOUSE` | `0` | Doesn't ask the terminal where the mouse is to the pixel, only to the character. Try it if clicks land in the wrong place while you drag or hover. |
| `TUI_SYNCHRONIZED_OUTPUT` | `0` or `1` | `0`: doesn't ask the terminal to show each change to the screen all at once. Try it if the screen flickers, freezes or tears. `1`: asks under tmux too, which otherwise isn't asked, because tmux then redraws its whole pane each time. |
| `TUI_SCROLL_OUTPUT` | `0` or `off` | Doesn't ask the terminal to scroll part of the screen when a list or a page scrolls, and redraws each changed line instead, which sends more. Try it if lines land in the wrong place after scrolling. |

### Saved settings

| Variable | Values | Effect |
|---|---|---|
| `TUI_CONFIG_DIR` | A folder | Keeps the program's saved settings in a folder named after it inside this one, on every system, instead of the usual place, and your settings for all programs in its `TUI` folder. A way to try something without touching your real settings: `TUI_CONFIG_DIR=/tmp/try myapp`. |
| `XDG_CONFIG_HOME` | A folder | Not on macOS or Windows: where the program's saved settings go, in a folder named after it, and your settings for all programs, in its `tui` folder. Unset, `.config` in your home folder. `TUI_CONFIG_DIR` wins over it. |
| `APPDATA` | A folder | Windows only, which sets it itself: where the program's saved settings go, in a folder named after it, and your settings for all programs, in its `TUI` folder. Unset, `AppData\Roaming` in your home folder. `TUI_CONFIG_DIR` wins over it. |

### Troubleshooting

| Variable | Values | Effect |
|---|---|---|
| `TUI_RUN_BODY_ON_EVERY_FRAME` | `1` | Try this if part of the screen stays out of date until you move away and back. The program then works out most of the screen afresh each time it draws, instead of reusing what looks unchanged. It costs more processor time, and if it helps, please tell the program's authors. |
| `TUI_IMAGE_CACHE_SIZE` | A size, such as `256M` or `1G`, in bytes or with a `K`, `M` or `G` | How much memory the program may use to keep pictures ready to show again. Unset, 64 MiB. Lower it if the program uses too much memory, and raise it if pictures are slow to come back. `0` keeps nothing beyond the pictures on the screen. |
<!-- /tui-environment-docs -->

### How the colour variables agree

They're the variables other command-line tools read, so an app honours what's already in your shell profile, and each is checked only if none above it decided. `COLORTERM` and `TERM` also say what "what the terminal has" means.

Where the conventions disagree, TUI goes with the one that does what the person meant. `NO_COLOR` beats `FORCE_COLOR`, as it does in Python and the [CLICOLORS](https://bixense.com/clicolors/) text, though Node has it the other way. `FORCE_COLOR=0` means off, as it does in Node and chalk, though [force-color.org](https://force-color.org) would count any value as on. An empty `FORCE_COLOR` means unset, as force-color.org and Python have it, though Node and chalk would turn colour on.

These choose the colours, not whether there's a terminal to draw on. An app still needs one, so `FORCE_COLOR=1 myapp | less` and `TERM=dumb FORCE_COLOR=1 myapp` go to its `runWithoutTerminal` as usual (see <doc:ScenesAndQuitting>). ``renderOnce(output:content:)`` has no such need: `FORCE_COLOR` or `CLICOLOR_FORCE` keeps its escape sequences down a pipe, unless `NO_COLOR` is set too, which leaves plain text there.

<doc:TerminalSupport#Without-colour> says what a control looks like without colour.

## For Developers Building an App

These help you test and debug your app. They're no use to the person running it, so they stay out of a man page.

<!-- tui-environment-docs: developer -->
### Testing

| Variable | Values | Effect |
|---|---|---|
| `TUI_RECORD_SNAPSHOTS` | `1` | `compareToSnapshot(_:filePath:)` writes each snapshot rather than comparing with it. Run this way when a change to the screen is what you meant. |

### Diagnostics

| Variable | Values | Effect |
|---|---|---|
| `TUI_VERIFY_RENDER_MEMO` | Any value, even `0` or an empty one, or a path with a `/` in it to log to | Renders again every picture the render cache serves, draws the fresh one, and reports any that differ. For finding a view that doesn't update. |
| `TUI_VERIFY_MEASURE_MEMO` | Any value, even `0` or an empty one, or a path with a `/` in it to log to | Measures again every size the render cache serves, uses the fresh one, and reports any that differ. |
| `TUI_DEBUG_RENDER` | `1` | Writes the render cache's statistics to stderr each frame. Redirect stderr, or it lands on the screen. |
| `TUI_FRAME_TRACE` | A file | Writes one tab-separated line per frame to that file: its number, when it began and how long it took in milliseconds, the bytes it sent, its render cache hits and misses, and what caused it. |
| `TUI_DIAGNOSE_BODY_MUTATION` | `1` | Reports a view whose `body` changes state as it draws, naming where it is in the tree. |
| `TUI_DIAGNOSTICS_FILE` | A file | Appends TUI's diagnostics to this file, rather than writing them to stderr, where they'd land on the screen. |
| `TUI_DEBUG_FRAME_DUMP` | `1` | Arms the backtick key, which writes the raw bytes of the last frame to a file in the working directory. |

### Limits

| Variable | Values | Effect |
|---|---|---|
| `TUI_MAX_ALIGNMENT_PUSH` | A whole number of cells above 0, held to 1073741824 | How far one alignment guide may push a view: 1048576 cells by default. A guide past that is taken for a mistake. Raise it for a canvas that really is larger. |
<!-- /tui-environment-docs -->

Two of the variables above are worth knowing for tests too. `TUI_CONFIG_DIR` keeps a run's `@AppStorage` away from your real settings, which on a Mac would otherwise be in the preferences of the program's name, whatever `HOME` says. And ``TestApp`` draws as if the accessibility variables were unset, so a test doesn't depend on who runs it: see <doc:TestingYourApp>.

### What code can do about each variable

**Wins** means that the setting named here beats the variable. **Can't undo it** is the exception above. **No setting** means that there's nothing to state in code. **Read** says whether a variable is read the first time it's needed and kept, or each time. What's read once is settled by the first frame.

<!-- tui-environment-docs: code -->
| Variable | Code | What code can do | Read |
|---|---|---|---|
| `NO_COLOR` | Wins | Assign `ColorDepth.current`, as a `--color=always` flag would. Ordinary drawing doesn't count as choosing: under `NO_COLOR`, `.foregroundStyle(.red)` draws no colour. `ColorDepth.cap` only lowers, so it can't undo this. | Once |
| `FORCE_COLOR` | Wins | Assign `ColorDepth.current`. `ColorDepth.cap` still holds it down. | Once |
| `CLICOLOR_FORCE` | Wins | Assign `ColorDepth.current`. `ColorDepth.cap` still holds it down. | Once |
| `CLICOLOR` | Wins | Assign `ColorDepth.current`. | Once |
| `COLORTERM` | Wins | Assign `ColorDepth.current`. | Once |
| `TERM` | Wins | Assign `ColorDepth.current` for its colours. Whether there's a terminal to draw on stays as `TERM` says. | Once |
| `TUI_INCREASE_CONTRAST` | Can't undo it | `colorSchemeContrast` is read-only, as in SwiftUI. `_colorSchemeContrast` writes it for a preview or a test. | Once |
| `TUI_DIFFERENTIATE_WITHOUT_COLOR` | Can't undo it | `accessibilityDifferentiateWithoutColor` is read-only, as in SwiftUI. `_accessibilityDifferentiateWithoutColor` writes it for a preview or a test. | Once |
| `TUI_REDUCE_TRANSPARENCY` | Can't undo it | `accessibilityReduceTransparency` is read-only, as in SwiftUI. `_accessibilityReduceTransparency` writes it for a preview or a test. | Once |
| `TUI_REDUCE_MOTION` | Can't undo it | `Scene.reduceMotion(_:)` can ask for less motion too, even under `0`, but `false` doesn't undo `1`. | Once |
| `TUI_BREATHING` | Can't undo it | `Scene.focusBreathing(false)` holds it still too, but `true` doesn't undo `0`. `.selectionIndicatorStyle(.none)` holds part of a screen still. `focusBreathes` is read-only. | Once |
| `TUI_KEY_SYMBOLS` | Can't undo it | `Scene.keyNotation(.spelledOut)` asks for the names too, but `.symbols` doesn't undo this. `keyNotation` is read-only. | Once |
| `TUI_ARROW_FOCUS` | No setting | The variable is the only way. | Once |
| `TUI_FOCUS_FOLLOWS_POINTER` | Wins | `Scene.focusFollowsPointer(_:)`. | Once |
| `TUI_TEXT_CURSOR_FOLLOWS_FOCUS` | No setting | The variable is the only way. | Once |
| `TUI_SPRING_LOADING_DELAY` | Wins | `.springLoadingDelay(_:)`, or `.environment(\.springLoadingDelay, _)`, for part of an app. | Once |
| `TUI_SHIFT_CLICKS` | No setting | The variable is the only way. | Each use |
| `TUI_POINTER_SHAPES` | Wins | `TerminalClient.pointerShapeSupport`, before the first frame. `.pointerStyle(_:)` in a view doesn't count as choosing: under `0` the pointer stays as it is. Nothing in code undoes `apps`. | Each use |
| `LANGUAGE` | Wins | `LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\.locale, _)` at the scene's root for the whole app, or on a view for part of it. | Once |
| `LC_ALL` | Wins | `LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\.locale, _)` for part of an app. | Once |
| `LC_MESSAGES` | Wins | `LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\.locale, _)` for part of an app. | Once |
| `LC_TIME` | Wins | `.environment(\.locale, _)`. | Once |
| `LC_NUMERIC` | Wins | `.environment(\.locale, _)`. | Once |
| `LC_CTYPE` | No setting | The variable is the only way. | Once |
| `LANG` | Wins | `LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\.locale, _)` for part of an app. | Once |
| `COLUMNS` | No setting | The variable is the only way. | Each use |
| `LINES` | No setting | The variable is the only way. | Each use |
| `TUI_FORCE_ESCAPES` | Wins | `renderOnce(output:content:)`, with `.plainText` or `.escapeSequences`. Only `.automatic`, the default, reads this. | Each use |
| `TUI_OPEN_URLS` | Can't undo it | `TerminalClient.urlOpeningSupport` wins over `1` and over no setting, but not over `0`: the person is saying "not on this machine", which the program can't know better than they do. An `OpenURLAction` that opens URLs its own way isn't affected. | Each use |
| `TUI_HYPERLINKS` | Wins | `TerminalClient.hyperlinkSupport`. A `Link` in a view doesn't count as choosing: under `0` it's still there, without the terminal's link. | Each use |
| `TUI_OSC52` | Wins | `TerminalClient.clipboardWriteSupport`. | Each use |
| `TUI_OSC5522` | Wins | `TerminalClient.mimeClipboardSupport`. | Each use |
| `TUI_NOTIFICATIONS` | No setting | The variable is the only way. | Each use |
| `TUI_SYSTEM_NOTIFICATIONS` | No setting | The variable is the only way. | Once |
| `TUI_PROGRESS` | No setting | The variable is the only way. | Each use |
| `TUI_TERM_PROGRAM` | Wins | `TerminalClient.simulated`, which draws for another terminal: for diagnosis, not for shipping. | Once |
| `TUI_GRAPHICS` | Wins | `TerminalClient.graphicsSupport`. `.terminalGraphics(false)` for part of an app; `.terminalGraphics(true)` doesn't turn on what this turned off. | Each use |
| `TUI_GRAPHICS_COMPRESSION` | Wins | `TerminalClient.graphicsCompressionSupport`. | Each use |
| `TUI_GRAPHICS_PLAYBACK` | Wins | `TerminalClient.graphicsPlaybackSupport`. | Each use |
| `TUI_HAIRLINES` | Wins | `TerminalClient.hairlineSupport`. | Each use |
| `TUI_PICTURES_UNDER_TEXT` | Wins | `TerminalClient.pictureUnderTextSupport`. | Each use |
| `TUI_KEYBOARD_PROTOCOL` | No setting | The variable is the only way. | Each use |
| `TUI_PIXEL_MOUSE` | No setting | The variable is the only way. | Once |
| `TUI_SYNCHRONIZED_OUTPUT` | No setting | The variable is the only way. | Each use |
| `TUI_SCROLL_OUTPUT` | No setting | The variable is the only way. | Once |
| `TUI_CONFIG_DIR` | Wins | `StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app. `LocalizationService` still keeps the language it saved here. | Each use |
| `XDG_CONFIG_HOME` | Wins | `StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app. | Each use |
| `APPDATA` | Wins | `StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app. | Each use |
| `TUI_RUN_BODY_ON_EVERY_FRAME` | No setting | The variable is the only way. | Once |
| `TUI_IMAGE_CACHE_SIZE` | Wins | `.urlImageCache(_:)` with a `URLImageCache(byteLimit:)` of the app's own. | Once |
| `TUI_RECORD_SNAPSHOTS` | No setting | The variable is the only way. | Each use |
| `TUI_VERIFY_RENDER_MEMO` | Wins | Assign `RenderCache.verifiesRenderMemo`. | Once |
| `TUI_VERIFY_MEASURE_MEMO` | Wins | Assign `RenderCache.verifiesMeasureMemo`. | Once |
| `TUI_DEBUG_RENDER` | No setting | The variable is the only way. | Once |
| `TUI_FRAME_TRACE` | No setting | The variable is the only way. | Once |
| `TUI_DIAGNOSE_BODY_MUTATION` | No setting | The variable is the only way. | Once |
| `TUI_DIAGNOSTICS_FILE` | No setting | The variable is the only way. | Once |
| `TUI_DEBUG_FRAME_DUMP` | No setting | The variable is the only way. | Once |
| `TUI_MAX_ALIGNMENT_PUSH` | No setting | The variable is the only way. | Once |
<!-- /tui-environment-docs -->

## What TUI Works Out for Itself

A terminal, a multiplexer or ssh sets these, and TUI reads them to work out where it's running. You'd rarely set one yourself: to say which terminal this is, use `TUI_TERM_PROGRAM`, which beats them. TUI sets that one itself when it had to ask the terminal, and a program your app starts inherits it. ``TerminalClient/current`` says what TUI concluded, and how.

<!-- tui-environment-docs: detected -->
### Set by your terminal

| Variable | What it says |
|---|---|
| `TERM_PROGRAM` | Your terminal's name, which many terminals set. ssh doesn't pass it on. `TUI_TERM_PROGRAM` wins over it. |
| `TERM_PROGRAM_VERSION` | Your terminal's version, which says whether it can change the mouse pointer's shape. |
| `LC_TERMINAL` | Your terminal's name, as iTerm2 sets it. ssh does pass this one on, since its name looks like a language setting's. |
| `LC_TERMINAL_VERSION` | The version that goes with `LC_TERMINAL`. |
| `GNOME_TERMINAL_SCREEN` | This is GNOME Terminal, and which tab, so the program can remember its state for each tab. |
| `GNOME_TERMINAL_SERVICE` | This is GNOME Terminal. |
| `VTE_VERSION` | This terminal is built on VTE, as GNOME Terminal is. |
| `WT_SESSION` | This is Windows Terminal, which draws Sixel pictures on a cell of 10 by 20 pixels, and which tab, so the program can remember its state for each tab. |
| `KITTY_WINDOW_ID` | This is kitty, which accepts clipboard writes and pointer shapes, and which window, so the program can remember its state for each window. |
| `KITTY_PID` | Which kitty this is, since each one numbers its windows from 1 again. |
| `TERM_SESSION_ID` | Which Terminal window or iTerm2 session this is, where `TERM_PROGRAM` names one of them, so the program can remember its state for each. |
| `ITERM_SESSION_ID` | Which iTerm2 session this is, where `TERM_PROGRAM` names iTerm2, so the program can remember its state for each. |
| `WEZTERM_PANE` | Which WezTerm pane this is, where `TERM_PROGRAM` names WezTerm, so the program can remember its state for each. |
| `WEZTERM_UNIX_SOCKET` | Which WezTerm this is, which goes with `WEZTERM_PANE`. |
| `WARP_TERMINAL_SESSION_UUID` | Which Warp session this is, where `TERM_PROGRAM` names Warp, so the program can remember its state for each. |
| `KONSOLE_DBUS_SESSION` | Which Konsole session this is, so the program can remember its state for each. |
| `KONSOLE_DBUS_SERVICE` | Which Konsole this is, which goes with `KONSOLE_DBUS_SESSION`. |
| `ALACRITTY_WINDOW_ID` | Which Alacritty window this is, so the program can remember its state for each. |
| `ALACRITTY_SOCKET` | Which Alacritty this is, which goes with `ALACRITTY_WINDOW_ID`. |
| `XTERM_VERSION` | This is xterm, and its version, which says whether it can change the pointer's shape. |
| `COLORFGBG` | The terminal's text and background colours, which say whether it's dark, when the terminal doesn't answer the program's question and there's no tmux or GNU screen in between. |
| `TMUX` | The program is running inside tmux, which changes what it asks of the terminal. |
| `TMUX_PANE` | Which tmux pane, so the program can ask tmux about it and remember its state for each pane. |
| `STY` | The program is running inside GNU screen, so it can't be sure you're at this computer. |
| `WINDOW` | Which GNU screen window, where `STY` is set, so the program can remember its state for each. |
| `ZELLIJ` | The program is running inside zellij, so it can't be sure you're at this computer. |
| `ZELLIJ_SESSION_NAME` | The program is running inside zellij, so it can't be sure you're at this computer. |
| `ABDUCO_SESSION` | The program is running inside abduco, so it can't be sure you're at this computer. |
| `SHPOOL_SESSION_NAME` | The program is running inside shpool, so it can't be sure you're at this computer. |

### Set by ssh and your desktop

| Variable | What it says |
|---|---|
| `SSH_CONNECTION` | The program is running over ssh, so you aren't at this computer: it doesn't follow this computer's own settings, such as Reduce Motion, and doesn't copy or post notifications through it. |
| `SSH_CLIENT` | The program is running over ssh, as `SSH_CONNECTION` says. |
| `SSH_TTY` | The program is running over ssh, as `SSH_CONNECTION` says. |
| `DISPLAY` | On Linux, there's an X11 desktop, so the program can copy with `xclip` or `xsel`, and post a notification the terminal can't show with `notify-send`. |
| `WAYLAND_DISPLAY` | On Linux, there's a Wayland desktop, so the program can copy with `wl-copy`, and post a notification the terminal can't show with `notify-send`. |
| `DBUS_SESSION_BUS_ADDRESS` | On Linux, there's a desktop session for `notify-send` to post notifications to. |
| `XDG_RUNTIME_DIR` | On Linux, where to look for that desktop session, when `DBUS_SESSION_BUS_ADDRESS` doesn't say. |
| `PATH` | Where to look for `notify-send`. |
<!-- /tui-environment-docs -->

## See Also

- <doc:TerminalSupport>
- <doc:Troubleshooting>
- <doc:ShippingAnApp>
- ``TUIEnvironmentVariables``
