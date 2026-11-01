//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIEnvironmentVariables+EndUser.swift
//
//  The variables for the person running an app. Each `effect` is written for them,
//  in plain ASCII, since it ends up in a man page. What a developer does about it
//  goes in `code`.
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftlint:disable line_length

extension TUIEnvironmentVariables {
    /// Everything the person running an app can set.
    static let endUser: [TUIEnvironmentVariable] =
        colour + accessibility + language + terminal + behaviour + files + output

    private static let colour: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "NO_COLOR", .endUser, .colour,
            values: "Any value, even `0`",
            effect: "No colour. Bold, underline, italics and the other text attributes stay. A picture the terminal draws in real pixels keeps its colours.",
            code: .overrides("Assign `ColorDepth.current`, as a `--color=always` flag would. Ordinary drawing doesn't count as choosing: under `NO_COLOR`, `.foregroundStyle(.red)` draws no colour. `ColorDepth.cap` only lowers, so it can't undo this.")),
        TUIEnvironmentVariable(
            "FORCE_COLOR", .endUser, .colour,
            values: "A number, or a word such as `true`",
            effect: "`0` or `false`: no colour. `1`: 16 colours. `2`: 256. `3` or more: millions. Any other value, such as `true`: what the terminal has, but at least 16. `NO_COLOR` beats it.",
            code: .overrides("Assign `ColorDepth.current`. `ColorDepth.cap` still holds it down.")),
        TUIEnvironmentVariable(
            "CLICOLOR_FORCE", .endUser, .colour,
            values: "Any value but `0` or `false`",
            effect: "What the terminal has, but at least 16 colours. `NO_COLOR` and `FORCE_COLOR` beat it.",
            code: .overrides("Assign `ColorDepth.current`. `ColorDepth.cap` still holds it down.")),
        TUIEnvironmentVariable(
            "CLICOLOR", .endUser, .colour,
            values: "`0` or `false`",
            effect: "No colour. Any other value changes nothing. `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR_FORCE` beat it.",
            code: .overrides("Assign `ColorDepth.current`.")),
        TUIEnvironmentVariable(
            "COLORTERM", .endUser, .colour,
            values: "`truecolor` or `24bit`",
            effect: "The terminal can show millions of colours. Terminals set this themselves, and ssh doesn't pass it on, so set it on the remote machine if colours look coarse there.",
            code: .overrides("Assign `ColorDepth.current`.")),
        TUIEnvironmentVariable(
            "TERM", .endUser, .colour,
            values: "A terminal type, such as `xterm-256color`",
            effect: "The kind of terminal, which says how many colours it has. Terminals set this themselves. With `dumb` there's no colour, and a full-screen program takes it that there's no terminal to draw on.",
            code: .overrides("Assign `ColorDepth.current` for its colours. Whether there's a terminal to draw on stays as `TERM` says.")),
    ]

    private static let accessibility: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_REDUCE_MOTION", .endUser, .accessibility,
            values: "`1`",
            effect: "Less motion: things jump to where they're going rather than glide. Reduce Motion in your system's settings does the same, if you're at the machine the program runs on.",
            code: .cannotOverride("`Scene.reduceMotion(_:)` can ask for less motion too, but `false` doesn't undo this.")),
        TUIEnvironmentVariable(
            "TUI_REDUCE_TRANSPARENCY", .endUser, .accessibility,
            values: "`1`",
            effect: "Less transparency: materials and glass are drawn opaque. Reduce Transparency in your system's settings does the same, if you're at the machine the program runs on.",
            code: .cannotOverride("`accessibilityReduceTransparency` is read-only, as in SwiftUI. `_accessibilityReduceTransparency` writes it for a preview or a test.")),
        TUIEnvironmentVariable(
            "TUI_DIFFERENTIATE_WITHOUT_COLOR", .endUser, .accessibility,
            values: "`1`",
            effect: "Asks the program for cues that don't rest on colour alone, where it has them. The setting of that name in your system's settings does the same, if you're at the machine the program runs on.",
            code: .cannotOverride("`accessibilityDifferentiateWithoutColor` is read-only, as in SwiftUI. `_accessibilityDifferentiateWithoutColor` writes it for a preview or a test.")),
        TUIEnvironmentVariable(
            "TUI_INCREASE_CONTRAST", .endUser, .accessibility,
            values: "`1`",
            effect: "Asks the program for more contrast, where it has it. Increase Contrast in your system's settings does the same, if you're at the machine the program runs on.",
            code: .cannotOverride("`colorSchemeContrast` is read-only, as in SwiftUI. `_colorSchemeContrast` writes it for a preview or a test.")),
        TUIEnvironmentVariable(
            "TUI_KEY_SYMBOLS", .endUser, .accessibility,
            values: "`0`",
            effect: "Writes keys by name, such as `Ctrl-Shift-Z`, rather than in symbols, for a font that has no glyphs for the symbols.",
            code: .cannotOverride("`Scene.keyNotation(.spelledOut)` asks for the names too, but `.symbols` doesn't undo this. `keyNotation` is read-only.")),
    ]

    private static let language: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "LANGUAGE", .endUser, .language,
            values: "A list of languages, such as `pt:es`",
            effect: "The languages to use, most preferred first. It comes before the variables below. A language you chose inside the program comes before it.",
            code: .overrides("`LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\\.locale, _)` for part of an app.")),
        TUIEnvironmentVariable(
            "LC_ALL", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The language, unless `LANGUAGE` says otherwise, and the region that dates and numbers are written for.",
            code: .overrides("`LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\\.locale, _)` for part of an app.")),
        TUIEnvironmentVariable(
            "LC_MESSAGES", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The language, unless `LANGUAGE` or `LC_ALL` says otherwise.",
            code: .overrides("`LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\\.locale, _)` for part of an app.")),
        TUIEnvironmentVariable(
            "LC_TIME", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The region that dates and numbers are written for, unless `LC_ALL` says otherwise.",
            code: .overrides("`.environment(\\.locale, _)`.")),
        TUIEnvironmentVariable(
            "LC_NUMERIC", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The region that dates and numbers are written for, unless `LC_ALL` or `LC_TIME` says otherwise.",
            code: .overrides("`.environment(\\.locale, _)`.")),
        TUIEnvironmentVariable(
            "LANG", .endUser, .language,
            values: "A locale, such as `de_DE.UTF-8`",
            effect: "The language and region, where none of the above says.",
            code: .overrides("`LocalizationService.shared.setLanguage(_:)`, which is saved and wins from then on. `.environment(\\.locale, _)` for part of an app.")),
    ]

    private static let terminal: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_TERM_PROGRAM", .endUser, .terminal,
            values: "`Apple_Terminal`, `iTerm.app`, `ghostty`, `WarpTerminal`, `tmux` or `gnome-terminal`",
            effect: "Says which terminal this is, when the program can't work it out and emoji or borders look out of line. Under tmux, tmux decides.",
            code: .overrides("`TerminalClient.simulated`, which draws for another terminal: for diagnosis, not for shipping.")),
        TUIEnvironmentVariable(
            "TUI_GRAPHICS", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Pictures in text characters, or in real pixels, without asking the terminal.",
            code: .overrides("`TerminalClient.graphicsSupport`. `.terminalGraphics(false)` for part of an app; `.terminalGraphics(true)` doesn't turn on what this turned off."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_GRAPHICS_COMPRESSION", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether pictures sent to the terminal are compressed, without asking the terminal.",
            code: .overrides("`TerminalClient.graphicsCompressionSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_HAIRLINES", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether the thin lines between a list's rows are drawn as pictures, off or on, whatever the terminal.",
            code: .overrides("`TerminalClient.hairlineSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_PICTURES_UNDER_TEXT", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether text over a frosted picture stands on the picture itself, off or on, whatever the terminal.",
            code: .overrides("`TerminalClient.pictureUnderTextSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_KEYBOARD_PROTOCOL", .endUser, .terminal,
            values: "`0`",
            effect: "Doesn't ask for the Kitty keyboard protocol: the way out if a terminal says it has it, and then keys go wrong.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_SHIFT_CLICKS", .endUser, .terminal,
            values: "`0`",
            effect: "Leaves Shift-clicks to the terminal, which usually selects text with them, rather than asking for them to reach the program.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_SYNCHRONIZED_OUTPUT", .endUser, .terminal,
            values: "`0`",
            effect: "Doesn't ask the terminal to hold each frame until it's complete: the way out if a terminal gets that wrong.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_HYPERLINKS", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether links are sent as links the terminal can follow (OSC 8), off or on, whatever the terminal.",
            code: .overrides("`TerminalClient.hyperlinkSupport`. A `Link` in a view doesn't count as choosing: under `0` it's still there, without the terminal's link."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_OSC52", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether a copy goes through the terminal to your clipboard (OSC 52), off or on, whatever the terminal.",
            code: .overrides("`TerminalClient.clipboardWriteSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_OSC5522", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether a copy or a paste carries more than text through the terminal (OSC 5522), off or on, whatever the terminal says.",
            code: .overrides("`TerminalClient.mimeClipboardSupport`."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_NOTIFICATIONS", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether notifications go to the terminal, off or on, whatever the terminal. With `0`, each one is only a bell.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_PROGRESS", .endUser, .terminal,
            values: "`0` or `1`",
            effect: "Whether the terminal is told about progress, to show in its own window or tab, off or on, whatever the terminal.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_POINTER_SHAPES", .endUser, .terminal,
            values: "`0`, `1` or `apps`",
            effect: "Whether the pointer changes shape over the program, off or on, whatever the terminal. `apps` is on, but only for the shapes the program itself asks for, not those of its controls, such as the I-beam over a text field.",
            code: .overrides("`TerminalClient.pointerShapeSupport`, before the first frame. `.pointerStyle(_:)` in a view doesn't count as choosing: under `0` the pointer stays as it is. Nothing in code undoes `apps`."),
            reading: .eachUse),
    ]

    private static let behaviour: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_OPEN_URLS", .endUser, .behaviour,
            values: "`0` or `1`",
            effect: "Whether the program may start your browser for a link. It's off by default, because the program can't tell that it's on the machine in front of you. `1` turns it on, unless the program says no. `0` keeps it off, whatever the program says.",
            code: .cannotOverride("`TerminalClient.urlOpeningSupport` wins over `1` and over no setting, but not over `0`: the person is saying \"not on this machine\", which the program can't know better than they do. An `OpenURLAction` that opens URLs its own way isn't affected."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "TUI_SPRING_LOADING_DELAY", .endUser, .behaviour,
            values: "Seconds, such as `0.3` or `1`",
            effect: "How long a drag has to rest on a control before the control opens. It overrides the setting on your machine.",
            code: .overrides("`.springLoadingDelay(_:)`, or `.environment(\\.springLoadingDelay, _)`, for part of an app.")),
        TUIEnvironmentVariable(
            "TUI_IMAGE_CACHE_SIZE", .endUser, .behaviour,
            values: "A size, such as `256M` or `1 GiB`, in bytes or with a `K`, `M` or `G`. `0` keeps nothing",
            effect: "How much memory the program may use to keep pictures it has decoded. 64 MiB by default.",
            code: .overrides("`.urlImageCache(_:)` with a `URLImageCache(byteLimit:)` of the app's own.")),
    ]

    private static let files: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_CONFIG_DIR", .endUser, .files,
            values: "A directory",
            effect: "Keeps the program's settings in files under this directory, in a folder named after the program, on every platform. A way to keep a test run away from your real settings.",
            code: .overrides("`StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app. `LocalizationService` still keeps the language it saved here."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "XDG_CONFIG_HOME", .endUser, .files,
            values: "A directory",
            effect: "Not on macOS: where the program's settings go, in a folder named after it. `~/.config` by default. `TUI_CONFIG_DIR` beats it.",
            code: .overrides("`StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "XDG_DATA_HOME", .endUser, .files,
            values: "A directory",
            effect: "Not on Apple platforms: where a program that uses it keeps saved data, in a folder named after the program. `~/.local/share` by default.",
            code: .overrides("`StorageDefaults.backend`, or `.defaultAppStorage(_:)` for part of an app."),
            reading: .eachUse),
    ]

    private static let output: [TUIEnvironmentVariable] = [
        TUIEnvironmentVariable(
            "TUI_FORCE_ESCAPES", .endUser, .output,
            values: "`0`, or any other value",
            effect: "What a program writes when it prints a view once, rather than taking over the screen. `0`: plain text. Anything else: styled text, even down a pipe. `NO_COLOR` still takes out the colour.",
            code: .overrides("`renderOnce(output:content:)`, with `.plainText` or `.escapeSequences`. Only `.automatic`, the default, reads this."),
            reading: .eachUse),
        TUIEnvironmentVariable(
            "COLUMNS", .endUser, .output,
            values: "A whole number above 0",
            effect: "How wide the terminal is, where the system can't say, such as when the output goes down a pipe. 80 by default. It doesn't change what a terminal reports for itself.",
            reading: .eachUse),
        TUIEnvironmentVariable(
            "LINES", .endUser, .output,
            values: "A whole number above 0",
            effect: "How tall the terminal is, where the system can't say, such as when the output goes down a pipe. 24 by default. It doesn't change what a terminal reports for itself.",
            reading: .eachUse),
    ]
}

// swiftlint:enable line_length
