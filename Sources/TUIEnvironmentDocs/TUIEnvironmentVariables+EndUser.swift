//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIEnvironmentVariables+EndUser.swift
//
//  The variables for the person running an app. Each `effect` is written for them:
//  plain words about the screen, the keys and the mouse, never about TUI's insides,
//  in ASCII, since it ends up in a man page. It says what the variable does, its
//  default where that isn't obvious, and an example where one helps. What a
//  developer does about it goes in `code`, which only developers read.
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftlint:disable line_length

extension TUIEnvironmentVariables {
    /// Everything the person running an app can set, in the order the documentation
    /// lists it.
    static let endUser: [TUIEnvironmentVariable] =
        appearance + motion + keyboardAndMouse + language + output + linksAndNotifications + terminalQuirks
        + files + troubleshooting

    /// The sentence each variable the settings panel and the View menu also
    /// set ends with.
    private static let viewMenu =
        "The program's settings panel (F2) has this too, as does its View menu if it has a menu bar. A choice there wins until the program quits, and is kept for its next runs, where this variable wins over it; the panel's Settings for All Programs... keeps one for every program."

    /// The default of each variable that a setting of the computer's also answers.
    private static let systemSetting =
        "Unset, what you've kept in the settings panel decides, and otherwise your computer's own setting, when you're at the machine the program runs on."

    private static let appearance: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "NO_COLOR", .endUser, .appearance,
            values: "Any value, even `0`",
            effect: "Turns colour off, as the no-color.org convention asks. Bold, underline and italics stay, and so do pictures drawn in real pixels. For example: `NO_COLOR=1 myapp`.",
            code: .overrides("Assign `ColorDepth.current`, as a `--color=always` flag would. Ordinary drawing doesn't count as choosing: under `NO_COLOR`, `.foregroundStyle(.red)` draws no colour. `ColorDepth.cap` only lowers, so it can't undo this.")),
        TUIEnvironmentVariable(
            "FORCE_COLOR", .endUser, .appearance,
            values: "A number, or a word such as `true`",
            effect: "Asks for colour, whatever the terminal seems able to show, as the force-color.org convention asks. `1` asks for at least 16 colours, `2` for at least 256, and `3` for millions. `0` or `false` turns colour off instead. Any other value, such as `true`, asks for what the terminal shows, but at least 16 colours. `NO_COLOR` wins over it.",
            code: .overrides("Assign `ColorDepth.current`. `ColorDepth.cap` still holds it down.")),
        TUIEnvironmentVariable(
            "CLICOLOR_FORCE", .endUser, .appearance,
            values: "Any value but `0` or `false`",
            effect: "Asks for colour, whatever the terminal seems able to show: what it shows, but at least 16 colours. `NO_COLOR` and `FORCE_COLOR` win over it.",
            code: .overrides("Assign `ColorDepth.current`. `ColorDepth.cap` still holds it down.")),
        TUIEnvironmentVariable(
            "CLICOLOR", .endUser, .appearance,
            values: "`0` or `false`",
            effect: "Turns colour off. Any other value changes nothing, since the program uses colour anyway. `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR_FORCE` win over it.",
            code: .overrides("Assign `ColorDepth.current`.")),
        TUIEnvironmentVariable(
            "COLORTERM", .endUser, .appearance,
            values: "`truecolor` or `24bit`",
            effect: "Says that the terminal shows millions of colours. Your terminal sets this itself, but ssh doesn't pass it on, so if colours look coarse on another machine, set it there: `COLORTERM=truecolor myapp`.",
            code: .overrides("Assign `ColorDepth.current`.")),
        TUIEnvironmentVariable(
            "TERM", .endUser, .appearance,
            values: "A terminal type, such as `xterm-256color`",
            effect: "The kind of terminal, which says how many colours it shows. Your terminal sets this itself. With `dumb` there's no colour, and a full-screen program takes it that there's no screen to draw on.",
            code: .overrides("Assign `ColorDepth.current` for its colours. Whether there's a terminal to draw on stays as `TERM` says.")),
        TUIEnvironmentVariable(
            "TUI_INCREASE_CONTRAST", .endUser, .appearance,
            values: "`1` or `0`",
            effect: "`1` asks for more contrast, where the program has it. `0` asks for standard contrast, even with Increase Contrast on in your computer's settings. \(systemSetting) \(viewMenu)",
            code: .cannotOverride("`colorSchemeContrast` is read-only, as in SwiftUI. `_colorSchemeContrast` writes it for a preview or a test.")),
        TUIEnvironmentVariable(
            "TUI_DIFFERENTIATE_WITHOUT_COLOR", .endUser, .appearance,
            values: "`1` or `0`",
            effect: "`1` asks for signs that don't rest on colour alone: the control your keys act on is shown in reverse video, one you can't use is faint, and a table's selected rows have a dot. `0` turns these off, even with Differentiate Without Color on in your computer's settings. \(systemSetting) \(viewMenu)",
            code: .cannotOverride("`accessibilityDifferentiateWithoutColor` is read-only, as in SwiftUI. `_accessibilityDifferentiateWithoutColor` writes it for a preview or a test.")),
        TUIEnvironmentVariable(
            "TUI_REDUCE_TRANSPARENCY", .endUser, .appearance,
            values: "`1` or `0`",
            effect: "`1` draws see-through panels and glass solid. `0` keeps them see-through, even with Reduce Transparency on in your computer's settings. \(systemSetting) \(viewMenu)",
            code: .cannotOverride("`accessibilityReduceTransparency` is read-only, as in SwiftUI. `_accessibilityReduceTransparency` writes it for a preview or a test.")),
    ]

    private static let motion: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_REDUCE_MOTION", .endUser, .motion,
            values: "`1` or `0`",
            effect: "`1` turns animations off: things jump to where they're going instead of gliding there, and the program can't undo it. `0` keeps animations, even with Reduce Motion on in your computer's settings. \(systemSetting) \(viewMenu) For example: `TUI_REDUCE_MOTION=1 myapp`.",
            code: .cannotOverride("`Scene.reduceMotion(_:)` can ask for less motion too, even under `0`, but `false` doesn't undo `1`.")),
        TUIEnvironmentVariable(
            "TUI_BREATHING", .endUser, .motion,
            values: "`0`",
            effect: "Stops the highlight on the control your keys act on from slowly pulsing or blinking: it's shown by colour and bold, and a control already in that colour, like a ticked checkbox or a link, shows it with its label in reverse video. The text cursor still blinks. `TUI_REDUCE_MOTION` doesn't do this by itself. \(viewMenu)",
            code: .cannotOverride("`Scene.focusBreathing(false)` holds it still too, but `true` doesn't undo `0`. `.selectionIndicatorStyle(.none)` holds part of a screen still. `focusBreathes` is read-only.")),
    ]

    private static let keyboardAndMouse: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_KEY_SYMBOLS", .endUser, .keyboardAndMouse,
            values: "`0`",
            effect: "Writes keyboard shortcuts out in words, such as `Ctrl-Shift-Z`, instead of in symbols, for a font that has no symbols for the keys. \(viewMenu)",
            code: .cannotOverride("`Scene.keyNotation(.spelledOut)` asks for the names too, but `.symbols` doesn't undo this. `keyNotation` is read-only.")),
        TUIEnvironmentVariable(
            "TUI_ARROW_FOCUS", .endUser, .keyboardAndMouse,
            values: "`geometric`",
            effect: "An experiment. When the control your keys act on doesn't use an arrow key itself, the arrow moves to the nearest control in that direction, scrolling to it if it's out of sight, so Down goes to the button below. At the edge it stays put instead of wrapping around. Tab and Shift-Tab are unchanged. Unset, the arrows go in the same order as Tab. \(viewMenu)"),
        TUIEnvironmentVariable(
            "TUI_FOCUS_FOLLOWS_POINTER", .endUser, .keyboardAndMouse,
            values: "`1` or `0`",
            effect: "`1`: moving the mouse onto a control makes it the one your keys act on, as a click would, without pressing it. A text field you've typed in keeps your keys until you click or press Tab. `0`: only a click or the keyboard does that. Unset, the program decides, and where it doesn't, what you've kept in the settings panel, else it's off. \(viewMenu)",
            code: .overrides("`Scene.focusFollowsPointer(_:)`.")),
        TUIEnvironmentVariable(
            "TUI_CURSOR_FOLLOWS_FOCUS", .endUser, .keyboardAndMouse,
            values: "`1`, `show` or `hidden`",
            effect: "An experiment, for a screen reader, a braille display or a magnifier that follows the terminal's cursor: the cursor moves to the control your keys act on after each change. `1` or `show` shows it there, and `hidden` moves it there but keeps it hidden. Unset, the cursor is hidden except in a text field you're typing in."),
        TUIEnvironmentVariable(
            "TUI_SPRING_LOADING_DELAY", .endUser, .keyboardAndMouse,
            values: "Seconds, such as `0.3` or `1`",
            effect: "How long you hold a dragged item over a control, such as a tab or a folder, before it opens. Unset, your Mac's own setting, when you're at the machine the program runs on, and otherwise half a second.",
            code: .overrides("`.springLoadingDelay(_:)`, or `.environment(\\.springLoadingDelay, _)`, for part of an app.")),
        TUIEnvironmentVariable(
            "TUI_SHIFT_CLICKS", .endUser, .keyboardAndMouse,
            values: "`0`",
            effect: "Leaves Shift-click to the terminal, which usually selects text with it, instead of passing it to the program.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_POINTER_SHAPES", .endUser, .keyboardAndMouse,
            values: "`0`, `1` or `apps`",
            effect: "Whether the mouse pointer changes shape over the program, such as to an I-beam over a text field. `0`: never. `1`: yes, even where the program can't tell that the terminal can. `apps`: only for the shapes the program asks for itself, not those of its ordinary controls. Unset, yes where the terminal is known to do it.",
            code: .overrides("`TerminalClient.pointerShapeSupport`, before the first frame. `.pointerStyle(_:)` in a view doesn't count as choosing: under `0` the pointer stays as it is. Nothing in code undoes `apps`."),
            reading: .eachUse),
    ]

    private static let language: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "LANGUAGE", .endUser, .language,
            values: "A list of languages, such as `pt:es`",
            effect: "The languages for the program's words, most wanted first. It wins over the variables below. A language you pick inside the program wins over it. For example: `LANGUAGE=de myapp`.",
            code: .overrides("`LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\\.locale, _)` at the scene's root for the whole app, or on a view for part of it.")),
        TUIEnvironmentVariable(
            "LC_ALL", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The language, unless `LANGUAGE` says otherwise, the region dates and numbers are written for, and the character set. It wins over the variables below.",
            code: .overrides("`LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\\.locale, _)` for part of an app.")),
        TUIEnvironmentVariable(
            "LC_MESSAGES", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The language, unless `LANGUAGE` or `LC_ALL` says otherwise.",
            code: .overrides("`LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\\.locale, _)` for part of an app.")),
        TUIEnvironmentVariable(
            "LC_TIME", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The region dates and numbers are written for, unless `LC_ALL` says otherwise.",
            code: .overrides("`.environment(\\.locale, _)`.")),
        TUIEnvironmentVariable(
            "LC_NUMERIC", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The region dates and numbers are written for, unless `LC_ALL` or `LC_TIME` says otherwise.",
            code: .overrides("`.environment(\\.locale, _)`.")),
        TUIEnvironmentVariable(
            "LC_CTYPE", .endUser, .language,
            values: "A locale, such as `de_DE.ISO8859-1`",
            effect: "The terminal's character set, unless `LC_ALL` says otherwise. Anything but UTF-8 says the terminal shows nothing beyond plain ASCII, so the program sends ASCII alone."),
        TUIEnvironmentVariable(
            "LANG", .endUser, .language,
            values: "A locale, such as `fr_FR.UTF-8`",
            effect: "The language, the region and the character set, wherever none of the above says. For example: `LANG=fr_FR.UTF-8 myapp`.",
            code: .overrides("`LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\\.locale, _)` for part of an app.")),
    ]

    private static let output: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "COLUMNS", .endUser, .output,
            values: "A whole number above 0",
            effect: "How many columns wide to draw, instead of the window's width. Unset, the window's width, or 80 where there's no window, such as when the output goes down a pipe. While it's set the program doesn't follow the window as you resize it, so if a program draws at the wrong size, look for a leftover export with `echo $COLUMNS` and clear it with `unset COLUMNS`.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "LINES", .endUser, .output,
            values: "A whole number above 0",
            effect: "How many lines tall to draw, instead of the window's height. Unset, the window's height, or 24 where there's no window. While it's set the program doesn't follow the window as you resize it, so if a program draws at the wrong size, look for a leftover export with `echo $LINES` and clear it with `unset LINES`.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_FORCE_ESCAPES", .endUser, .output,
            values: "`0`, or any other value",
            effect: "For a program that prints once and exits, rather than taking over the screen. `0` prints plain text. Anything else prints styled text, even into a file or down a pipe, as in `TUI_FORCE_ESCAPES=1 mytool > out.txt`. `NO_COLOR` still takes the colours out.",
            code: .overrides("`renderOnce(output:content:)`, with `.plainText` or `.escapeSequences`. Only `.automatic`, the default, reads this."),
            reading: .eachUse),
    ]

    private static let linksAndNotifications: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_OPEN_URLS", .endUser, .linksAndNotifications,
            values: "`0` or `1`",
            effect: "Whether the program may open a link in your web browser. Off by default, because the program can't tell whether it's running on the computer in front of you or on one you've reached over ssh. `1` allows it, unless the program says no. `0` never allows it, whatever the program says.",
            code: .cannotOverride("`TerminalClient.urlOpeningSupport` wins over `1` and over no setting, but not over `0`: the person is saying \"not on this machine\", which the program can't know better than they do. An `OpenURLAction` that opens URLs its own way isn't affected."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_HYPERLINKS", .endUser, .linksAndNotifications,
            values: "`0` or `1`",
            effect: "Whether links are sent so that the terminal can open them when you click (OSC 8). `0`: never, and the link's text still shows. `1`: always. Unset, where the terminal is known to handle them.",
            code: .overrides("`TerminalClient.hyperlinkSupport`. A `Link` in a view doesn't count as choosing: under `0` it's still there, without the terminal's link."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_OSC52", .endUser, .linksAndNotifications,
            values: "`0` or `1`",
            effect: "Whether copying puts text on your clipboard through the terminal (OSC 52), which works over ssh too. `0`: never. `1`: always. Unset, where the terminal is known to allow it.",
            code: .overrides("`TerminalClient.clipboardWriteSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_OSC5522", .endUser, .linksAndNotifications,
            values: "`0` or `1`",
            effect: "Whether copy and paste through the terminal can carry more than plain text (OSC 5522). `0`: never. `1`: always. Unset, where the terminal says it can.",
            code: .overrides("`TerminalClient.mimeClipboardSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_NOTIFICATIONS", .endUser, .linksAndNotifications,
            values: "`0` or `1`",
            effect: "Whether the program sends notifications to your desktop at all, and whether they go through the terminal, which shows them as your desktop's own. `0`: none at all, neither through the terminal nor posted by this computer, so a program asking for your attention rings the bell instead. `1`: always through the terminal. Unset, through the terminal where it's known to show them, and elsewhere as `TUI_SYSTEM_NOTIFICATIONS` says.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_SYSTEM_NOTIFICATIONS", .endUser, .linksAndNotifications,
            values: "`0` or `1`",
            effect: "Whether a notification the terminal can't show is posted by this computer itself, with `osascript` on macOS or `notify-send` on Linux. `0`: never. `1`: wherever the program can't tell where you are, such as inside zellij or GNU screen at your own desk. Unset, only where the program can tell you're at this computer, and never over ssh. On macOS these are Script Editor's notifications, so they show only where System Settings > Notifications > Script Editor allows them. A notification never comes twice: a terminal that shows them always gets them instead. `TUI_NOTIFICATIONS=0` turns these off too, whatever this says.",
            reading: .once),
        TUIEnvironmentVariable(
            "TUI_PROGRESS", .endUser, .linksAndNotifications,
            values: "`0` or `1`",
            effect: "Whether the terminal is told how far a long task has got, to show in its tab or its window. `0`: never. `1`: always. Unset, where the terminal is known to show it.",
            reading: .eachUse),
    ]

    private static let terminalQuirks: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_TERM_PROGRAM", .endUser, .terminal,
            values: "`Apple_Terminal`, `iTerm.app`, `ghostty`, `WarpTerminal`, `tmux` or `gnome-terminal`",
            effect: "Says which terminal this is, when the program can't work it out and emoji or borders look out of line, as in `TUI_TERM_PROGRAM=ghostty myapp`. Under tmux, tmux's own answer counts. The program sets it itself when it had to ask the terminal, so a program it starts knows too.",
            code: .overrides("`TerminalClient.simulated`, which draws for another terminal: for diagnosis, not for shipping.")),
        TUIEnvironmentVariable(
            "TUI_GRAPHICS", .endUser, .terminal,
            values: "`0`, `1`, `classic` or `sixel`",
            effect: "How pictures are drawn, without asking the terminal what it can do. `0`: in text characters, which works everywhere. `1`: in real pixels, by the Kitty graphics protocol. `classic`: the same, for a terminal with the protocol's older form alone. `sixel`: in real pixels, by Sixel. Unset, the program asks the terminal. For example: `TUI_GRAPHICS=0 myapp`.",
            code: .overrides("`TerminalClient.graphicsSupport`. `.terminalGraphics(false)` for part of an app; `.terminalGraphics(true)` doesn't turn on what this turned off."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_GRAPHICS_COMPRESSION", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether pictures are compressed on their way to the terminal. Unset, the program asks the terminal. Try `0` if pictures don't appear.",
            code: .overrides("`TerminalClient.graphicsCompressionSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_GRAPHICS_PLAYBACK", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "An experiment. `1` hands an animated picture to the terminal to play by itself after it's been sent once, which saves sending each frame. It works only on a terminal that plays Kitty animations: on any other, the picture stops at its first frame. Off unless it's `1`.",
            code: .overrides("`TerminalClient.graphicsPlaybackSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_HAIRLINES", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether the thin lines between a list's rows are drawn as pictures, finer than any character. `0`: never. `1`: always. Unset, only on Ghostty, where they've been checked.",
            code: .overrides("`TerminalClient.hairlineSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_PICTURES_UNDER_TEXT", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether text over a frosted picture is drawn on top of the picture itself. `0`: never. `1`: always. Unset, only on Ghostty, where it's been checked.",
            code: .overrides("`TerminalClient.pictureUnderTextSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_KEYBOARD_PROTOCOL", .endUser, .terminal,
            values: "`0`",
            effect: "Doesn't turn on the terminal's fuller report of the keys (the Kitty keyboard protocol). Try it if keys or shortcuts do the wrong thing.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_PIXEL_MOUSE", .endUser, .terminal,
            values: "`0`",
            effect: "Doesn't ask the terminal where the mouse is to the pixel, only to the character. Try it if clicks land in the wrong place while you drag or hover.",
            reading: .once),
        TUIEnvironmentVariable(
            "TUI_SYNCHRONIZED_OUTPUT", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "`0`: doesn't ask the terminal to show each change to the screen all at once. Try it if the screen flickers, freezes or tears. `1`: asks under tmux too, which otherwise isn't asked, because tmux then redraws its whole pane each time.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_SCROLL_OUTPUT", .endUser, .terminal,
            values: "`0` or `off`",
            effect: "Doesn't ask the terminal to scroll part of the screen when a list or a page scrolls, and redraws each changed line instead, which sends more. Try it if lines land in the wrong place after scrolling."),
    ]

    private static let files: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_CONFIG_DIR", .endUser, .files,
            values: "A folder",
            effect: "Keeps the program's saved settings in a folder named after it inside this one, on every system, instead of the usual place, and your settings for all programs in its `TUI` folder. A way to try something without touching your real settings: `TUI_CONFIG_DIR=/tmp/try myapp`.",
            code: .overrides("`StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app. `LocalizationService` still keeps the language it saved here."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "XDG_CONFIG_HOME", .endUser, .files,
            values: "A folder",
            effect: "Not on macOS or Windows: where the program's saved settings go, in a folder named after it, and your settings for all programs, in its `tui` folder. Unset, `.config` in your home folder. `TUI_CONFIG_DIR` wins over it.",
            code: .overrides("`StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "APPDATA", .endUser, .files,
            values: "A folder",
            effect: "Windows only, which sets it itself: where the program's saved settings go, in a folder named after it, and your settings for all programs, in its `TUI` folder. Unset, `AppData\\Roaming` in your home folder. `TUI_CONFIG_DIR` wins over it.",
            code: .overrides("`StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app."),
            reading: .eachUse),
    ]

    private static let troubleshooting: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_RUN_BODY_ON_EVERY_FRAME", .endUser, .troubleshooting,
            values: "`1`",
            effect: "Try this if part of the screen stays out of date until you move away and back. The program then works out most of the screen afresh each time it draws, instead of reusing what looks unchanged. It costs more processor time, and if it helps, please tell the program's authors."),
        TUIEnvironmentVariable(
            "TUI_IMAGE_CACHE_SIZE", .endUser, .troubleshooting,
            values: "A size, such as `256M` or `1G`, in bytes or with a `K`, `M` or `G`",
            effect: "How much memory the program may use to keep pictures ready to show again. Unset, 64 MiB. Lower it if the program uses too much memory, and raise it if pictures are slow to come back. `0` keeps nothing beyond the pictures on the screen.",
            code: .overrides("`.urlImageCache(_:)` with a `URLImageCache(byteLimit:)` of the app's own.")),
    ]
}

// swiftlint:enable line_length
