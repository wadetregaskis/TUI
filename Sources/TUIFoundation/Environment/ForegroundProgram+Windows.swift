//  🖥️ TUI — A Terminal UI framework for Swift
//  ForegroundProgram+Windows.swift
//
//  Starting a program for a hand-off with `CreateProcessW`, and waiting for
//  it: the Windows arm of ForegroundProgram.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import WinSDK

extension HandOffTerminalAction {
    /// A program run for a hand-off on Windows: started in the app's console,
    /// which it shares as a POSIX program shares the app's process group, and
    /// waited for.
    enum ForegroundProgram {
        /// Starts `executable` with `arguments` and waits for it to end.
        static func run(_ executable: Executable, arguments: [String]) throws(LaunchError) -> Termination {
            let process = unsafe HANDLE(bitPattern: try start(executable, arguments: arguments))
            defer { _ = unsafe CloseHandle(process) }
            guard unsafe WaitForSingleObject(process, INFINITE) == WAIT_OBJECT_0 else {
                throw .couldNotWait(errno: errno(for: GetLastError()))
            }
            var code = DWORD(0)
            guard unsafe GetExitCodeProcess(process, &code) else {
                throw .couldNotWait(errno: errno(for: GetLastError()))
            }
            return .exit(Int32(bitPattern: code))
        }

        /// Starts it, and answers its process's handle.
        ///
        /// No application name: the program is the command line's first word,
        /// which `CreateProcessW` looks for as a name, with `.exe` added where
        /// it has no extension, in the app's folder, the working directory,
        /// the system's folders and then `PATH`. A path is used as given. No
        /// handles inherited: a console program finds the console it shares
        /// without them, and the app's own files stay its own.
        /// As the handle's bits, as a raw pointer is kept everywhere it is
        /// handed on in TUI.
        private static func start(_ executable: Executable, arguments: [String]) throws(LaunchError) -> UInt {
            var line = Array(commandLine([executable.spelling] + arguments).utf16) + [0]
            var startup = unsafe STARTUPINFOW()
            unsafe startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
            var information = unsafe PROCESS_INFORMATION()
            let started = unsafe CreateProcessW(
                nil, &line, nil, nil, false, DWORD(CREATE_UNICODE_ENVIRONMENT), nil, nil, &startup, &information)
            guard started else { throw .couldNotStart(errno: errno(for: GetLastError())) }
            _ = unsafe CloseHandle(information.hThread)
            return unsafe UInt(bitPattern: information.hProcess)
        }

        /// `words` as one command line, each quoted so that the C runtime's
        /// parsing (`CommandLineToArgvW`'s rules) gives it back whole: a word
        /// with a space, a tab or a quote in it is put in quotes, a quote in it
        /// escaped, and the backslashes before a quote or the closing one
        /// doubled.
        static func commandLine(_ words: [String]) -> String {
            words.map(quoted).joined(separator: " ")
        }

        private static func quoted(_ word: String) -> String {
            guard word.isEmpty || word.contains(where: { $0 == " " || $0 == "\t" || $0 == "\"" }) else {
                return word
            }
            var result = "\""
            var backslashes = 0
            for character in word {
                switch character {
                case "\\":
                    backslashes += 1
                case "\"":
                    result += String(repeating: "\\", count: 2 * backslashes + 1) + "\""
                    backslashes = 0
                default:
                    result += String(repeating: "\\", count: backslashes) + String(character)
                    backslashes = 0
                }
            }
            return result + String(repeating: "\\", count: 2 * backslashes) + "\""
        }

        /// The `errno` code ``LaunchError`` reports for a Windows error: a
        /// program not found `ENOENT`, one that may not be run `EACCES`, one
        /// that is not a program `ENOEXEC`, and `EINVAL` for the rest.
        static func errno(for error: DWORD) -> Int32 {
            switch Int32(error) {
            case ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, ERROR_INVALID_NAME, ERROR_DIRECTORY: ENOENT
            case ERROR_ACCESS_DENIED: EACCES
            case ERROR_BAD_EXE_FORMAT, ERROR_EXE_MACHINE_TYPE_MISMATCH: ENOEXEC
            default: EINVAL
            }
        }
    }
}

#endif
