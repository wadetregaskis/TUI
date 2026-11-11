//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffTerminalAction+Running.swift
//
//  Handing the terminal to one program, started as an interactive program
//  must be: `handOffTerminal(running: .name("less"), arguments: [path])`.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Running a Program

extension HandOffTerminalAction {
    /// Hands the terminal to a program for as long as it runs, and takes it
    /// back once it ends.
    ///
    /// Starts the program inside the closure form, so everything said of that
    /// holds, and starts it as an interactive program must be: in the app's
    /// process group, the terminal's foreground group, with every signal at
    /// its default action and none blocked. Then it waits for the program to
    /// end:
    ///
    /// ```swift
    /// @Environment(\.handOffTerminal) private var handOffTerminal
    ///
    /// Button("Edit in $EDITOR") {
    ///     // `$1` keeps the path out of the command's words; the shell runs the
    ///     // person's editor with its own arguments (`code --wait`), as git does.
    ///     let ended = try? handOffTerminal(
    ///         running: .path("/bin/sh"),
    ///         arguments: ["-c", "${VISUAL:-${EDITOR:-vi}} \"$1\"", "sh", file.path]
    ///     )
    ///     if ended == .exit(0) { reload(file) }
    /// }
    /// ```
    ///
    /// The program gets the app's environment and its working directory, as
    /// `system(3)` gives them. To give it others, run it through a shell
    /// (`cd "$1" && exec less "$2"`) or `/usr/bin/env` (`env PAGER=cat git log`).
    ///
    /// ⌃Z stops the app and the program together, as for the closure form.
    /// And because the app started the program, it sees it stop when it stops
    /// itself alone, as a program reading ⌃Z as a key may (`raise(SIGTSTP)`):
    /// the app stops too, so the shell gets the job back rather than a
    /// terminal that looks hung, and `fg` continues both.
    ///
    /// Not Foundation's `Process`, which starts a program in a process group
    /// of its own: the terminal treats that as a background job, and stops an
    /// editor that reads the keyboard (`SIGTTIN`).
    ///
    /// - Parameters:
    ///   - executable: The program: a path, or a name looked up in `PATH`.
    ///   - arguments: Its arguments, after its name, which it is given first.
    /// - Returns: How the program ended. A non-zero exit status is an ending,
    ///   not an error.
    /// - Throws: ``LaunchError`` where the program could not be started or
    ///   waited for, the terminal taken back first; and
    ///   ``LaunchError/unsupported`` where no program can be started.
    @MainActor
    @discardableResult
    public func callAsFunction(
        running executable: Executable,
        arguments: [String] = []
    ) throws(LaunchError) -> Termination {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            try self { () throws(LaunchError) -> Termination in
                try ForegroundProgram.run(executable, arguments: arguments)
            }
        #else
            // WebAssembly (WASI) has no processes to start; Windows starts them
            // with `CreateProcess`, which a Windows port of the run loop would
            // bring with the console it hands over.
            throw .unsupported
        #endif
    }

    /// A program to start: a path, or a name looked up in `PATH`.
    ///
    /// Named as swift-subprocess's `Executable` is, which spells the same two
    /// ways to name a program.
    public struct Executable: Hashable, Sendable {
        /// The name or the path, as given.
        let spelling: String
        /// Whether `spelling` is looked up in `PATH`.
        let searchesPath: Bool

        /// The program called `name`, found in `PATH` as a shell finds it:
        /// the first directory listed that holds it. A name with a slash in it
        /// is a path, as for a shell.
        ///
        /// For a program named by a setting, as `$PAGER` is. One named by
        /// `$EDITOR` or `$VISUAL` is a command, arguments and all
        /// (`code --wait`), which a shell must split: run `/bin/sh -c` with it.
        public static func name(_ name: String) -> Self {
            Self(spelling: name, searchesPath: true)
        }

        /// The program at `path`: absolute, or relative to the working
        /// directory.
        public static func path(_ path: String) -> Self {
            Self(spelling: path, searchesPath: false)
        }
    }

    /// How a program ended: named as Foundation's
    /// `Process.TerminationReason` names the two ways.
    public enum Termination: Hashable, Sendable {
        /// It exited with this status: 0 for success, by convention.
        case exit(Int32)
        /// A signal it did not catch ended it: `SIGINT` (2) for ⌃C, say.
        case uncaughtSignal(Int32)
    }

    /// Why a program could not be run.
    public enum LaunchError: Error, Hashable, Sendable {
        /// It could not be started: the `errno` code says why, `ENOENT` for
        /// a program not found, `EACCES` for one that may not be run.
        case couldNotStart(errno: Int32)
        /// It started, and could not be waited for: the `errno` code says
        /// why, `ECHILD` where the app has set `SIGCHLD` to be ignored, which
        /// makes the system reap its programs as they end.
        case couldNotWait(errno: Int32)
        /// No program can be started here: on WebAssembly, which has no
        /// processes, and on Windows, which has no port of the run loop yet.
        case unsupported
    }
}
