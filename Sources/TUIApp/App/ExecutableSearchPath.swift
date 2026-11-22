//  🖥️ TUI — A Terminal UI framework for Swift
//  ExecutableSearchPath.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Where a helper program is looked for: the directories of `PATH`, as a shell
/// looks for a command, for the helpers TUI starts by a path of its own:
/// `notify-send`, the Linux clipboard's `wl-copy`, `wl-paste`, `xclip` and
/// `xsel`, and `xdg-open`.
///
/// Read from the environment it is handed, so a test can pose one. POSIX's
/// `PATH`, its directories separated by `:`: only POSIX helpers are looked up
/// here. An empty entry, which a shell reads as the working directory, is
/// skipped: a helper is never taken from wherever the app was started.
enum ExecutableSearchPath {
    /// `PATH`'s directories in `environment`, in order; none where it is unset.
    static func directories(in environment: [String: String]) -> [Substring] {
        (environment["PATH"] ?? "").split(separator: ":")
    }

    /// The first `name` in `PATH`'s directories that `isExecutable` accepts,
    /// or `nil` where none does.
    static func find(
        _ name: String, in environment: [String: String], isExecutable: (String) -> Bool
    ) -> String? {
        directories(in: environment).lazy.map { "\($0)/\(name)" }.first(where: isExecutable)
    }
}
