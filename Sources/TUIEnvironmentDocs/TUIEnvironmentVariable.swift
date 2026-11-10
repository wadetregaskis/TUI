//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIEnvironmentVariable.swift
//
//  One environment variable TUI reads, as a row of the table the documentation
//  is generated from.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One environment variable that TUI reads: what it's called, who it's for, what
/// it does, and what an app's own code can do about it.
///
/// ``TUIEnvironmentVariables/all`` holds one of these for each variable. A TUI-specific
/// type, with no SwiftUI counterpart.
public struct TUIEnvironmentVariable: Sendable, Hashable, Identifiable {
    /// Who a variable is for.
    public enum Audience: String, Sendable, Hashable, CaseIterable {
        /// The person running an app. These belong in an app's man page.
        case endUser

        /// Someone building an app with TUI, while they test and debug it.
        case developer

        /// Nobody, as a rule: a terminal, a multiplexer or ssh sets these, and TUI
        /// reads them to work out where it's running. An app's man page lists them
        /// after the ``endUser`` variables, so the person running it knows what
        /// their terminal is telling it.
        case detected
    }

    /// What a variable is about, which is how the documentation groups them. The
    /// documentation lists the topics in the order they're declared here.
    public enum Topic: String, Sendable, Hashable, CaseIterable {
        /// Colour, contrast and transparency.
        case appearance

        /// Animations, and anything else on the screen that moves by itself.
        case motion

        /// What the keys and the mouse do, and how they're shown.
        case keyboardAndMouse

        /// The language, the character set, and the region dates and numbers are
        /// written for.
        case language

        /// How big the screen is, and what a program writes when it prints once and
        /// exits.
        case output

        /// Opening links, posting notifications, and copying to the clipboard.
        case linksAndNotifications

        /// What the terminal is asked to do, and what it's assumed to be able to: the
        /// way out when a terminal gets something wrong.
        case terminal

        /// Where the program keeps what it saves.
        case files

        /// What to try when the program misbehaves.
        case troubleshooting

        /// Checking a program's screen in its tests.
        case testing

        /// Finding out what a program is doing as it draws.
        case diagnostics

        /// A limit that's there to catch a mistake.
        case limits

        /// Which terminal this is, and what's between it and the program.
        case identity

        /// Whether the person is at this machine, and what it offers.
        case session

        /// The heading this topic has in the documentation.
        public var title: String {
            switch self {
            case .appearance: "Colour and appearance"
            case .motion: "Motion"
            case .keyboardAndMouse: "Keyboard and mouse"
            case .language: "Text and language"
            case .output: "Screen size and printed output"
            case .linksAndNotifications: "Links, notifications and the clipboard"
            case .terminal: "Terminal quirks"
            case .files: "Saved settings"
            case .troubleshooting: "Troubleshooting"
            case .testing: "Testing"
            case .diagnostics: "Diagnostics"
            case .limits: "Limits"
            case .identity: "Set by your terminal"
            case .session: "Set by ssh and your desktop"
            }
        }
    }

    /// What an app's own code can do about a variable. A flag the app reads is the
    /// app's code, so this is also what such a flag can do.
    public enum CodeSetting: Sendable, Hashable {
        /// The app's setting wins, and this says how to state it.
        case overrides(String)

        /// The app can't take away what the person asked for, and this says what it
        /// can do. It's what someone asks for so that they can use the program at
        /// all, and they're the one who knows that they need it.
        case cannotOverride(String)

        /// There's nothing to state in code: the variable is the only way to set this.
        case none

        /// How the app says it, or `nil` for ``none``.
        public var explanation: String? {
            switch self {
            case .overrides(let text), .cannotOverride(let text): text
            case .none: nil
            }
        }
    }

    /// When TUI reads a variable. A program can only see a variable it was started
    /// with, unless it writes its own, so this matters only to code that does that.
    public enum Reading: String, Sendable, Hashable, CaseIterable {
        /// The first time it's needed. What it said then stays for the whole run.
        case once

        /// Each time the answer is needed.
        case eachUse
    }

    /// The variable's name, such as `NO_COLOR`.
    public let name: String

    /// Who it's for.
    public let audience: Audience

    /// What it's about.
    public let topic: Topic

    /// The values it takes, in Markdown. An empty variable counts as unset, and
    /// any other value it doesn't list is ignored.
    public let values: String

    /// What it does, in Markdown, written for ``audience``.
    public let effect: String

    /// What an app's own code can do about it, in Markdown.
    public let codeSetting: CodeSetting

    /// When TUI reads it.
    public let reading: Reading

    /// ``name``, which is unique in the table.
    public var id: String { name }

    init(
        _ name: String, _ audience: Audience, _ topic: Topic, values: String, effect: String,
        code: CodeSetting = .none, reading: Reading = .once
    ) {
        self.name = name
        self.audience = audience
        self.topic = topic
        self.values = values
        self.effect = effect
        self.codeSetting = code
        self.reading = reading
    }
}
