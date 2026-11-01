# Environment Variables

Change how an app behaves without changing its code, and know which setting wins when several say different things.

## Overview

Whoever runs an app built with TUI can set an environment variable to change something about it for that run, or for every run if it's in their shell's profile:

```
NO_COLOR=1 myapp
TUI_REDUCE_MOTION=1 myapp
TUI_GRAPHICS=0 swift run MyApp
```

Most people never need one, because TUI works out what each terminal can do. They're there for when it gets that wrong, for what only the person knows they need, and for trying out how an app looks somewhere else.

This page says which setting wins, then lists every variable: <doc:EnvironmentVariables#For-People-Running-an-App>, <doc:EnvironmentVariables#For-Developers-Building-an-App> and <doc:EnvironmentVariables#What-TUI-Works-Out-for-Itself>. To put the list in your own app's man page, see <doc:ShippingAnApp#Documenting-Environment-Variables>.

## Which Setting Wins

**What your code states wins over a variable, and a variable wins over what TUI would otherwise do.** Your code can state a setting in a view modifier, an environment write or an assignment.

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

### Setting a variable from code

Don't write a variable to state a setting. Many are read once, and `setenv` isn't safe while another thread reads the environment. Use the setting <doc:EnvironmentVariables#What-code-can-do-about-each-variable> gives. Where it gives none, the variable is for the person running the program.

## For People Running an App

<!-- tui-environment-docs: end-user -->
### Colour

| Variable | Values | Effect |
|---|---|---|
| `NO_COLOR` | Any value, even `0` | No colour. Bold, underline, italics and the other text attributes stay. A picture the terminal draws in real pixels keeps its colours. |
| `FORCE_COLOR` | A number, or a word such as `true` | `0` or `false`: no colour. `1`: at least 16 colours. `2`: at least 256. `3` or more: millions. Any other value, such as `true`: what the terminal has, but at least 16. `NO_COLOR` beats it. |
| `CLICOLOR_FORCE` | Any value but `0` or `false` | What the terminal has, but at least 16 colours. `NO_COLOR` and `FORCE_COLOR` beat it. |
| `CLICOLOR` | `0` or `false` | No colour. Any other value changes nothing. `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR_FORCE` beat it. |
| `COLORTERM` | `truecolor` or `24bit` | The terminal can show millions of colours. Terminals set this themselves, and ssh doesn't pass it on, so set it on the remote machine if colours look coarse there. |
| `TERM` | A terminal type, such as `xterm-256color` | The kind of terminal, which says how many colours it has. Terminals set this themselves. With `dumb` there's no colour, and a full-screen program takes it that there's no terminal to draw on. |

### Accessibility

| Variable | Values | Effect |
|---|---|---|
| `TUI_REDUCE_MOTION` | `1` | Less motion: things jump to where they're going rather than glide. Reduce Motion in your system's settings does the same, if you're at the machine the program runs on. |
| `TUI_REDUCE_TRANSPARENCY` | `1` | Less transparency: materials and glass are drawn opaque. Reduce Transparency in your system's settings does the same, if you're at the machine the program runs on. |
| `TUI_DIFFERENTIATE_WITHOUT_COLOR` | `1` | Asks the program for cues that don't rest on colour alone, where it has them. The setting of that name in your system's settings does the same, if you're at the machine the program runs on. |
| `TUI_INCREASE_CONTRAST` | `1` | Asks the program for more contrast, where it has it. Increase Contrast in your system's settings does the same, if you're at the machine the program runs on. |
| `TUI_KEY_SYMBOLS` | `0` | Writes keys by name, such as `Ctrl-Shift-Z`, rather than in symbols, for a font that has no glyphs for the symbols. |

### Language and region

| Variable | Values | Effect |
|---|---|---|
| `LANGUAGE` | A list of languages, such as `pt:es` | The languages to use, most preferred first. It comes before the variables below. A language you chose inside the program comes before it. |
| `LC_ALL` | A locale, such as `de_DE.UTF-8` | The language, unless `LANGUAGE` says otherwise, and the region that dates and numbers are written for. |
| `LC_MESSAGES` | A locale, such as `de_DE.UTF-8` | The language, unless `LANGUAGE` or `LC_ALL` says otherwise. |
| `LC_TIME` | A locale, such as `de_DE.UTF-8` | The region that dates and numbers are written for, unless `LC_ALL` says otherwise. |
| `LC_NUMERIC` | A locale, such as `de_DE.UTF-8` | The region that dates and numbers are written for, unless `LC_ALL` or `LC_TIME` says otherwise. |
| `LANG` | A locale, such as `de_DE.UTF-8` | The language and region, where none of the above says. |

### The terminal

| Variable | Values | Effect |
|---|---|---|
| `TUI_TERM_PROGRAM` | `Apple_Terminal`, `iTerm.app`, `ghostty`, `WarpTerminal`, `tmux` or `gnome-terminal` | Says which terminal this is, when the program can't work it out and emoji or borders look out of line. Under tmux, tmux decides. |
| `TUI_GRAPHICS` | `0` or `1` | Pictures in text characters, or in real pixels, without asking the terminal. |
| `TUI_GRAPHICS_COMPRESSION` | `0` or `1` | Whether pictures sent to the terminal are compressed, without asking the terminal. |
| `TUI_HAIRLINES` | `0` or `1` | Whether the thin lines between a list's rows are drawn as pictures, off or on, whatever the terminal. |
| `TUI_PICTURES_UNDER_TEXT` | `0` or `1` | Whether text over a frosted picture stands on the picture itself, off or on, whatever the terminal. |
| `TUI_KEYBOARD_PROTOCOL` | `0` | Doesn't ask for the Kitty keyboard protocol: the way out if a terminal says it has it, and then keys go wrong. |
| `TUI_SHIFT_CLICKS` | `0` | Leaves Shift-clicks to the terminal, which usually selects text with them, rather than asking for them to reach the program. |
| `TUI_SYNCHRONIZED_OUTPUT` | `0` | Doesn't ask the terminal to hold each frame until it's complete: the way out if a terminal gets that wrong. |
| `TUI_HYPERLINKS` | `0` or `1` | Whether links are sent as links the terminal can follow (OSC 8), off or on, whatever the terminal. |
| `TUI_OSC52` | `0` or `1` | Whether a copy goes through the terminal to your clipboard (OSC 52), off or on, whatever the terminal. |
| `TUI_OSC5522` | `0` or `1` | Whether a copy or a paste carries more than text through the terminal (OSC 5522), off or on, whatever the terminal says. |
| `TUI_NOTIFICATIONS` | `0` or `1` | Whether notifications go to the terminal, off or on, whatever the terminal. With `0`, each one is only a bell. |
| `TUI_PROGRESS` | `0` or `1` | Whether the terminal is told about progress, to show in its own window or tab, off or on, whatever the terminal. |
| `TUI_POINTER_SHAPES` | `0`, `1` or `apps` | Whether the pointer changes shape over the program, off or on, whatever the terminal. `apps` is on, but only for the shapes the program itself asks for, not those of its controls, such as the I-beam over a text field. |

### Behaviour

| Variable | Values | Effect |
|---|---|---|
| `TUI_OPEN_URLS` | `0` or `1` | Whether the program may start your browser for a link. It's off by default, because the program can't tell that it's on the machine in front of you. `1` turns it on, unless the program says no. `0` keeps it off, whatever the program says. |
| `TUI_SPRING_LOADING_DELAY` | Seconds, such as `0.3` or `1` | How long a drag has to rest on a control before the control opens. It overrides the setting on your machine. |
| `TUI_IMAGE_CACHE_SIZE` | A size, such as `256M` or `1 GiB`, in bytes or with a `K`, `M` or `G`. `0` keeps nothing | How much memory the program may use to keep pictures it has decoded. 64 MiB by default. |

### Files

| Variable | Values | Effect |
|---|---|---|
| `TUI_CONFIG_DIR` | A directory | Keeps the program's settings in files under this directory, in a folder named after the program, on every platform. A way to keep a test run away from your real settings. |
| `XDG_CONFIG_HOME` | A directory | Not on macOS: where the program's settings go, in a folder named after it. `~/.config` by default. `TUI_CONFIG_DIR` beats it. |
| `XDG_DATA_HOME` | A directory | Not on Apple platforms: where a program that uses it keeps saved data, in a folder named after the program. `~/.local/share` by default. |

### One-off output

| Variable | Values | Effect |
|---|---|---|
| `TUI_FORCE_ESCAPES` | `0`, or any other value | What a program writes when it prints a view once, rather than taking over the screen. `0`: plain text. Anything else: styled text, even down a pipe. `NO_COLOR` still takes out the colour. |
| `COLUMNS` | A whole number above 0 | How wide the terminal is, where the system can't say, such as when the output goes down a pipe. 80 by default. It doesn't change what a terminal reports for itself. |
| `LINES` | A whole number above 0 | How tall the terminal is, where the system can't say, such as when the output goes down a pipe. 24 by default. It doesn't change what a terminal reports for itself. |
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
| `TUI_VERIFY_RENDER_MEMO` | Any value, even `0`, or a path with a `/` in it to log to | Renders again every picture the render cache serves, draws the fresh one, and reports any that differ. For finding a view that doesn't update. |
| `TUI_VERIFY_MEASURE_MEMO` | Any value, even `0`, or a path with a `/` in it to log to | Measures again every size the render cache serves, uses the fresh one, and reports any that differ. |
| `TUI_DEBUG_RENDER` | `1` | Writes the render cache's statistics to stderr each frame. Redirect stderr, or it lands on the screen. |
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
| `TUI_REDUCE_MOTION` | Can't undo it | `Scene.reduceMotion(_:)` can ask for less motion too, but `false` doesn't undo this. | Once |
| `TUI_REDUCE_TRANSPARENCY` | Can't undo it | `accessibilityReduceTransparency` is read-only, as in SwiftUI. `_accessibilityReduceTransparency` writes it for a preview or a test. | Once |
| `TUI_DIFFERENTIATE_WITHOUT_COLOR` | Can't undo it | `accessibilityDifferentiateWithoutColor` is read-only, as in SwiftUI. `_accessibilityDifferentiateWithoutColor` writes it for a preview or a test. | Once |
| `TUI_INCREASE_CONTRAST` | Can't undo it | `colorSchemeContrast` is read-only, as in SwiftUI. `_colorSchemeContrast` writes it for a preview or a test. | Once |
| `TUI_KEY_SYMBOLS` | Can't undo it | `Scene.keyNotation(.spelledOut)` asks for the names too, but `.symbols` doesn't undo this. `keyNotation` is read-only. | Once |
| `LANGUAGE` | Wins | `LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\.locale, _)` for part of an app. | Once |
| `LC_ALL` | Wins | `LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\.locale, _)` for part of an app. | Once |
| `LC_MESSAGES` | Wins | `LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\.locale, _)` for part of an app. | Once |
| `LC_TIME` | Wins | `.environment(\.locale, _)`. | Once |
| `LC_NUMERIC` | Wins | `.environment(\.locale, _)`. | Once |
| `LANG` | Wins | `LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\.locale, _)` for part of an app. | Once |
| `TUI_TERM_PROGRAM` | Wins | `TerminalClient.simulated`, which draws for another terminal: for diagnosis, not for shipping. | Once |
| `TUI_GRAPHICS` | Wins | `TerminalClient.graphicsSupport`. `.terminalGraphics(false)` for part of an app; `.terminalGraphics(true)` doesn't turn on what this turned off. | Each use |
| `TUI_GRAPHICS_COMPRESSION` | Wins | `TerminalClient.graphicsCompressionSupport`. | Each use |
| `TUI_HAIRLINES` | Wins | `TerminalClient.hairlineSupport`. | Each use |
| `TUI_PICTURES_UNDER_TEXT` | Wins | `TerminalClient.pictureUnderTextSupport`. | Each use |
| `TUI_KEYBOARD_PROTOCOL` | No setting | The variable is the only way. | Each use |
| `TUI_SHIFT_CLICKS` | No setting | The variable is the only way. | Each use |
| `TUI_SYNCHRONIZED_OUTPUT` | No setting | The variable is the only way. | Each use |
| `TUI_HYPERLINKS` | Wins | `TerminalClient.hyperlinkSupport`. A `Link` in a view doesn't count as choosing: under `0` it's still there, without the terminal's link. | Each use |
| `TUI_OSC52` | Wins | `TerminalClient.clipboardWriteSupport`. | Each use |
| `TUI_OSC5522` | Wins | `TerminalClient.mimeClipboardSupport`. | Each use |
| `TUI_NOTIFICATIONS` | No setting | The variable is the only way. | Each use |
| `TUI_PROGRESS` | No setting | The variable is the only way. | Each use |
| `TUI_POINTER_SHAPES` | Wins | `TerminalClient.pointerShapeSupport`, before the first frame. `.pointerStyle(_:)` in a view doesn't count as choosing: under `0` the pointer stays as it is. Nothing in code undoes `apps`. | Each use |
| `TUI_OPEN_URLS` | Can't undo it | `TerminalClient.urlOpeningSupport` wins over `1` and over no setting, but not over `0`: the person is saying "not on this machine", which the program can't know better than they do. An `OpenURLAction` that opens URLs its own way isn't affected. | Each use |
| `TUI_SPRING_LOADING_DELAY` | Wins | `.springLoadingDelay(_:)`, or `.environment(\.springLoadingDelay, _)`, for part of an app. | Once |
| `TUI_IMAGE_CACHE_SIZE` | Wins | `.urlImageCache(_:)` with a `URLImageCache(byteLimit:)` of the app's own. | Once |
| `TUI_CONFIG_DIR` | Wins | `StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app. `LocalizationService` still keeps the language it saved here. | Each use |
| `XDG_CONFIG_HOME` | Wins | `StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app. | Each use |
| `XDG_DATA_HOME` | Wins | `StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app. | Each use |
| `TUI_FORCE_ESCAPES` | Wins | `renderOnce(output:content:)`, with `.plainText` or `.escapeSequences`. Only `.automatic`, the default, reads this. | Each use |
| `COLUMNS` | No setting | The variable is the only way. | Each use |
| `LINES` | No setting | The variable is the only way. | Each use |
| `TUI_RECORD_SNAPSHOTS` | No setting | The variable is the only way. | Each use |
| `TUI_VERIFY_RENDER_MEMO` | Wins | Assign `RenderCache.verifiesRenderMemo`. | Once |
| `TUI_VERIFY_MEASURE_MEMO` | Wins | Assign `RenderCache.verifiesMeasureMemo`. | Once |
| `TUI_DEBUG_RENDER` | No setting | The variable is the only way. | Once |
| `TUI_DIAGNOSE_BODY_MUTATION` | No setting | The variable is the only way. | Once |
| `TUI_DIAGNOSTICS_FILE` | No setting | The variable is the only way. | Once |
| `TUI_DEBUG_FRAME_DUMP` | No setting | The variable is the only way. | Once |
| `TUI_MAX_ALIGNMENT_PUSH` | No setting | The variable is the only way. | Once |
<!-- /tui-environment-docs -->

## What TUI Works Out for Itself

A terminal, a multiplexer or ssh sets these, and TUI reads them to work out where it's running. You'd rarely set one yourself: to say which terminal this is, use `TUI_TERM_PROGRAM`, which beats them. TUI sets that one itself when it had to ask the terminal, and a program your app starts inherits it. ``TerminalClient/current`` says what TUI concluded, and how.

<!-- tui-environment-docs: detected -->
### Which terminal this is

| Variable | What it says |
|---|---|
| `TERM_PROGRAM` | The terminal's name, set by many terminals. ssh doesn't pass it on. `TUI_TERM_PROGRAM` beats it. |
| `TERM_PROGRAM_VERSION` | The terminal's version, which says whether it can set the pointer's shape. |
| `LC_TERMINAL` | The terminal's name, as iTerm2 sets it. It's what ssh does pass on, by default, being named like a locale variable. |
| `LC_TERMINAL_VERSION` | The version that goes with `LC_TERMINAL`. |
| `GNOME_TERMINAL_SCREEN` | This is GNOME Terminal. |
| `GNOME_TERMINAL_SERVICE` | This is GNOME Terminal. |
| `VTE_VERSION` | This terminal is built on VTE, as GNOME Terminal is. |
| `KITTY_WINDOW_ID` | This is kitty, which takes clipboard writes and pointer shapes. |
| `XTERM_VERSION` | This is xterm, and which version, which says whether it can set the pointer's shape. |
| `COLORFGBG` | The terminal's foreground and background, which say whether it's dark, when the terminal doesn't answer and there's no multiplexer. |
| `TMUX` | The program is in a tmux pane. |
| `TMUX_PANE` | Which tmux pane, to ask tmux about it. |
| `STY` | The program is in a GNU screen session. |
| `ZELLIJ` | The program is in a zellij session. |
| `ZELLIJ_SESSION_NAME` | The program is in a zellij session. |
| `ABDUCO_SESSION` | The program is in an abduco session. |
| `SHPOOL_SESSION_NAME` | The program is in a shpool session. |

### Where the person is

| Variable | What it says |
|---|---|
| `SSH_CONNECTION` | The program is running over ssh, so the person isn't at this machine. |
| `SSH_CLIENT` | The program is running over ssh, so the person isn't at this machine. |
| `SSH_TTY` | The program is running over ssh, so the person isn't at this machine. |
| `DISPLAY` | On Linux, an X11 clipboard helper may be usable. |
| `WAYLAND_DISPLAY` | On Linux, a Wayland clipboard helper may be usable. |
<!-- /tui-environment-docs -->

## See Also

- <doc:TerminalSupport>
- <doc:Troubleshooting>
- <doc:ShippingAnApp>
- ``TUIEnvironmentVariables``
