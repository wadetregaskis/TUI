//  🖥️ TUI — A Terminal UI framework for Swift
//  AppCommand.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if ArgumentParser
    /// A command that parses its command line and then runs an app made from it.
    ///
    /// ```swift
    /// import TUI
    /// import TUIArgumentParser
    ///
    /// @main
    /// struct ViewerCommand: AppCommand {
    ///     @Option(help: "The folder to show.")
    ///     var path = "."
    ///
    ///     var app: some App { Viewer(path: path) }
    /// }
    ///
    /// struct Viewer: App {
    ///     var path = "."
    ///
    ///     var body: some Scene {
    ///         WindowGroup { FileList(path: path) }
    ///     }
    /// }
    /// ```
    ///
    /// The parsing is swift-argument-parser's and comes first, with the terminal
    /// untouched: `--help` and `--version` print to standard output, a mistake
    /// prints to standard error, and each exits with the usual status, even down
    /// a pipe. Only a command line that parses reaches ``app``.
    ///
    /// It's `Sendable` because the command is parsed off the main actor and the
    /// app is made on it. `@Option` and `@Flag` properties are, if their values
    /// are.
    ///
    /// A command with subcommands can make some of them `AppCommand`s and others
    /// plain commands that print a report and exit.
    public protocol AppCommand: AsyncParsableCommand, Sendable {
        /// The type of the app the command runs.
        associatedtype Application: App

        /// The app to run, made from the values parsed.
        @MainActor var app: Application { get }
    }

    extension AppCommand {
        /// Runs ``app`` until it quits.
        public func run() async throws {
            await runApp()
        }

        /// A function of its own so that the app stays on the main actor from
        /// being made to being run: an `App` need not be `Sendable`.
        @MainActor
        private func runApp() async {
            await app.run()
        }
    }
#else
    /// Empty without the trait, so that a client who forgets it is told what to do.
    @available(
        *, unavailable,
        message: "Turn on TUI's trait: .package(url: ..., traits: [.defaults, \"ArgumentParser\"])"
    )
    public protocol AppCommand {}
#endif
