//  🖥️ TUI — A Terminal UI framework for Swift
//  ForegroundProgram.swift
//
//  Starting an interactive program for a hand-off with `posix_spawn`, and
//  waiting for it: POSIX only, kept to this file, which is empty on Windows
//  and WebAssembly (`HandOffTerminalAction+Running.swift` throws there).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

    import Foundation

    #if canImport(Darwin)
        import Darwin
    #elseif canImport(Glibc)
        import Glibc
    #elseif canImport(Musl)
        import Musl
    #endif

    /// Starts a program in this process's group, which is the terminal's
    /// foreground group, with every signal at its default action and none
    /// blocked, and waits for it to end: what
    /// ``HandOffTerminalAction/callAsFunction(running:arguments:)`` runs while
    /// the terminal is handed over.
    ///
    /// In this group, not one of its own as Foundation's `Process` makes: the
    /// terminal stops a background group that reads it (`SIGTTIN`). With the
    /// defaults, because a program inherits what its parent ignores: the app
    /// ignores `SIGPIPE` always, and `SIGINT` and `SIGQUIT` while it hands the
    /// terminal over, so a program spawned without them would ignore ⌃C.
    enum ForegroundProgram {
        typealias Termination = HandOffTerminalAction.Termination
        typealias LaunchError = HandOffTerminalAction.LaunchError

        /// Starts `executable` with `arguments`, this process's environment and
        /// working directory, and waits for it to end.
        static func run(
            _ executable: HandOffTerminalAction.Executable,
            arguments: [String]
        ) throws(LaunchError) -> Termination {
            let child = try spawn(executable, arguments: arguments)
            return try wait(for: child)
        }

        private static func spawn(
            _ executable: HandOffTerminalAction.Executable,
            arguments: [String]
        ) throws(LaunchError) -> pid_t {
            let words = [executable.spelling] + arguments
            let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
            let argv: [UnsafeMutablePointer<CChar>?] = unsafe words.map { unsafe strdup($0) } + [nil]
            let envp: [UnsafeMutablePointer<CChar>?] = unsafe environment.map { unsafe strdup($0) } + [nil]
            defer {
                unsafe argv.forEach { unsafe free($0) }
                unsafe envp.forEach { unsafe free($0) }
            }
            #if canImport(Darwin)
                var attributes: posix_spawnattr_t?
            #elseif canImport(Musl)
                // A struct of pointers in Musl, so its zeroed value is made
                // unsafely; `posix_spawnattr_init` fills it in.
                var attributes = unsafe posix_spawnattr_t()
            #else
                var attributes = posix_spawnattr_t()
            #endif
            unsafe posix_spawnattr_init(&attributes)
            defer { unsafe posix_spawnattr_destroy(&attributes) }
            // Every signal that can be caught or ignored, at its default.
            var defaults = sigset_t()
            unsafe sigfillset(&defaults)
            unsafe sigdelset(&defaults, SIGKILL)
            unsafe sigdelset(&defaults, SIGSTOP)
            unsafe posix_spawnattr_setsigdefault(&attributes, &defaults)
            var none = sigset_t()
            unsafe sigemptyset(&none)
            unsafe posix_spawnattr_setsigmask(&attributes, &none)
            // No POSIX_SPAWN_SETPGROUP: the child stays in this process group.
            unsafe posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

            var child: pid_t = 0
            // `posix_spawnp` looks a name up in `PATH`, and takes a name with a
            // slash in it as a path, as `execvp` does.
            let failure =
                executable.searchesPath
                ? unsafe posix_spawnp(&child, executable.spelling, nil, &attributes, argv, envp)
                : unsafe posix_spawn(&child, executable.spelling, nil, &attributes, argv, envp)
            guard failure == 0 else { throw .couldNotStart(errno: failure) }
            return child
        }

        /// Waits for `child` to end, and says how it did.
        ///
        /// A child that stops alone — one that stops itself, as a program that
        /// reads ⌃Z as a key may — stops this process too, as ⌃Z stops the two
        /// together, so that the shell sees the job stopped and takes the
        /// terminal back: otherwise this process would wait on, in the
        /// foreground, and the terminal look hung. `fg` continues both.
        private static func wait(for child: pid_t) throws(LaunchError) -> Termination {
            var status: Int32 = 0
            while true {
                guard unsafe waitpid(child, &status, WUNTRACED) >= 0 else {
                    guard errno == EINTR else { throw .couldNotWait(errno: errno) }
                    continue
                }
                if let ended = WaitStatus(status).termination { return ended }
                guard WaitStatus(status).isStopped else { continue }
                // Stopped. A ⌃Z stopped this process too, before it saw the
                // report, and it sees it only once `fg` has continued both: a
                // stop to make again only if the child has not been continued
                // since. (`WCONTINUED` reports one continuing, `WNOHANG` returns
                // 0 while there is nothing new to report.)
                let again = unsafe waitpid(child, &status, WNOHANG | WCONTINUED)
                if again < 0 {
                    guard errno == EINTR else { throw .couldNotWait(errno: errno) }
                    continue
                }
                if again == child, let ended = WaitStatus(status).termination { return ended }
                if again == 0 {
                    // The stop the line discipline sends for ⌃Z: this process
                    // has it at its default action while the terminal is handed
                    // over (`SignalManager.beginHandOff()`).
                    raise(SIGTSTP)
                }
            }
        }
    }

    /// A status `waitpid` gives, read as its `WIFEXITED` and other macros read
    /// it: Swift imports none of them. The encodings are the same in Darwin,
    /// Glibc and Musl, but for a continuing (`WIFCONTINUED`): `0xFFFF` in
    /// Glibc and Musl, a stop by `SIGCONT` in Darwin.
    private struct WaitStatus {
        let raw: Int32

        init(_ raw: Int32) { self.raw = raw }

        /// The low seven bits: 0 for an exit, 0x7F for a stop or a continuing,
        /// and otherwise the signal that ended the process.
        private var low: Int32 { raw & 0x7F }
        /// The next eight: an exit's status, or a stop's signal.
        private var high: Int32 { (raw >> 8) & 0xFF }

        /// How the process ended, where it has.
        var termination: HandOffTerminalAction.Termination? {
            switch low {
            case 0: .exit(high)
            case 0x7F: nil
            default: .uncaughtSignal(low)
            }
        }

        /// Whether the process stopped (and did not continue).
        var isStopped: Bool {
            low == 0x7F && raw != 0xFFFF && high != SIGCONT
        }
    }

#endif
