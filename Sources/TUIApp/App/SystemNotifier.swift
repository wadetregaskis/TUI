//  🖥️ TUI — A Terminal UI framework for Swift
//  SystemNotifier.swift
//
//  A toast posted to the desktop, through the operating system itself rather
//  than the terminal: `osascript` on macOS, `notify-send` on Linux, and only
//  where the person is at this machine.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// This machine's own notifications — AppleScript's `display notification`
/// through `osascript` on macOS, `notify-send` (D-Bus) on a Linux desktop —
/// behind the substrate's ``SystemNotificationBackend``: what the app's run
/// loop installs into the ``TUIContext`` it creates. Nothing else does, so no
/// other context, a test's above all, posts a real notification.
///
/// The route for a toast posted to the desktop (`NotificationDesktopDelivery`)
/// that the terminal cannot carry: the run loop sends one through the terminal
/// (`OSC 9`) where the terminal posts notifications, and through this only
/// where it does not, so no notification is ever delivered twice. The terminal
/// goes first because its notification is the terminal's own — its icon, and a
/// click that brings its window forward — where `osascript`'s is attributed to
/// Script Editor, and a click opens that.
///
/// Only where the person is at this machine (``SessionLocality/isLocal()``,
/// positive evidence, so any doubt — an ssh session, a tmux attached from
/// elsewhere, a session keeper — answers no): a notification posted on a
/// machine the person is not at is one nobody sees, and on a shared machine,
/// someone else's screen. `TUI_SYSTEM_NOTIFICATIONS=0` turns it off; `1` posts
/// even where TUI cannot tell, for a session TUI cannot see into (zellij, GNU
/// screen) at the person's own desk.
///
/// Neither blocks the frame: the locality test (which may ask tmux for its
/// clients) and the launch run on a background queue, and nothing waits for the
/// helper. The message reaches the helper as an argument, never inside a
/// script or a shell line: AppleScript reads it from `argv`, so no quoting in
/// it can end a string, and `--` ends the options of both helpers, so a message
/// that starts with `-` is not one. The helper's input and output are the null
/// device, not the terminal the app is drawing on.
struct SystemNotifier: SystemNotificationBackend {
    /// When it posts: `TUI_SYSTEM_NOTIFICATIONS`.
    enum Setting: Equatable, Sendable {
        /// Never (`0`).
        case off
        /// Where the person is at this machine (unset, or any other value).
        case whenLocal
        /// Whether or not TUI can tell (`1`).
        case always

        /// The setting `environment` asks for.
        init(environment: [String: String]) {
            switch environment["TUI_SYSTEM_NOTIFICATIONS"] {
            case "0": self = .off
            case "1": self = .always
            default: self = .whenLocal
            }
        }
    }

    /// A program that posts a notification, at its path.
    enum Helper: Equatable, Sendable {
        /// macOS's `osascript`, running `display notification`.
        case osascript(String)
        /// A Linux desktop's `notify-send`, which asks its notification
        /// server over D-Bus.
        case notifySend(String)

        /// Where the program is.
        var path: String {
            switch self {
            case .osascript(let path), .notifySend(let path): path
            }
        }

        /// What it is run with to post `message` titled `title`: both as
        /// arguments of their own, after `--`.
        func arguments(title: String, message: String) -> [String] {
            switch self {
            case .osascript:
                // The script names its arguments and never contains them, so
                // nothing in either needs AppleScript's quoting.
                [
                    "-e", "on run argv",
                    "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
                    "-e", "end run",
                    "--", title, message,
                ]
            case .notifySend:
                // The body is markup to a server that reads it (the
                // Desktop Notifications Specification's `body-markup`), so its
                // `&`, `<` and `>` are escaped; the summary is plain text.
                ["--app-name=\(title)", "--", title, Self.escapingMarkup(message)]
            }
        }

        /// `text` with the three characters notification-body markup reads
        /// escaped.
        static func escapingMarkup(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        /// The helper this machine has, if any: `osascript` where it is
        /// installed; else `notify-send` on the `PATH` where there is a desktop
        /// session to show it — a session bus (`DBUS_SESSION_BUS_ADDRESS`, or
        /// the socket under `XDG_RUNTIME_DIR`) and a display (`WAYLAND_DISPLAY`
        /// or `DISPLAY`). What is installed decides, not the platform's name.
        static func find(
            environment: [String: String], isExecutable: (String) -> Bool, exists: (String) -> Bool
        ) -> Self? {
            let osascript = "/usr/bin/osascript"
            if isExecutable(osascript) { return .osascript(osascript) }
            let hasBus =
                environment["DBUS_SESSION_BUS_ADDRESS"]?.isEmpty == false
                || environment["XDG_RUNTIME_DIR"].map { !$0.isEmpty && exists($0 + "/bus") } == true
            let hasDisplay =
                environment["WAYLAND_DISPLAY"]?.isEmpty == false || environment["DISPLAY"]?.isEmpty == false
            guard hasBus, hasDisplay, let path = environment["PATH"] else { return nil }
            return path.split(separator: ":").lazy.map { "\($0)/notify-send" }.first(where: isExecutable)
                .map(Self.notifySend)
        }
    }

    /// When it posts.
    let setting: Setting

    /// The program it posts with, or `nil` where this machine has none.
    let helper: Helper?

    /// The notification's title: the app's name.
    let title: String

    /// Whether the person is at this machine, asked at each post, off the main
    /// thread.
    let isLocal: @Sendable () -> Bool

    /// Starts `executable` with `arguments`, without waiting for it.
    let launch: @Sendable (_ executable: String, _ arguments: [String]) -> Void

    /// Runs the post's work: on a background queue, so the frame never waits
    /// on it.
    let perform: @Sendable (@escaping @Sendable () -> Void) -> Void

    /// This process's notifier: its environment's setting, the helper this
    /// machine has, the process's name as the title, the locality test, and
    /// `Process` on a utility queue.
    init() {
        let environment = ProcessInfo.processInfo.environment
        self.init(
            setting: Setting(environment: environment),
            helper: Helper.find(
                environment: environment, isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                exists: { FileManager.default.fileExists(atPath: $0) }),
            title: ProcessInfo.processInfo.processName,
            isLocal: { SessionLocality.isLocal() },
            launch: Self.launchProcess,
            perform: Self.performInBackground)
    }

    /// A notifier with every part given: a test's, which launches nothing.
    init(
        setting: Setting, helper: Helper?, title: String, isLocal: @escaping @Sendable () -> Bool,
        launch: @escaping @Sendable (_ executable: String, _ arguments: [String]) -> Void,
        perform: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void
    ) {
        self.setting = setting
        self.helper = helper
        self.title = title
        self.isLocal = isLocal
        self.launch = launch
        self.perform = perform
    }

    /// Posts `message` where the setting, the helper and the locality test
    /// allow, with its control characters dropped (a line break is a space);
    /// nothing for a message with nothing left to say.
    func post(_ message: String) {
        guard setting != .off, let helper else { return }
        let text = TerminalHostState.sanitizedText(message)
        guard text.contains(where: { !$0.isWhitespace }) else { return }
        let (setting, title, isLocal, launch) = (setting, title, isLocal, launch)
        perform {
            guard setting == .always || isLocal() else { return }
            launch(helper.path, helper.arguments(title: title, message: text))
        }
    }

    /// Runs `work` on a utility queue, so the frame never waits on it; inline
    /// where there is no Dispatch (wasip1, which starts no processes anyway,
    /// so the work there is only the locality test).
    private static func performInBackground(_ work: @escaping @Sendable () -> Void) {
        #if canImport(Dispatch)
        DispatchQueue.global(qos: .utility).async(execute: work)
        #else
        work()
        #endif
    }

    /// Starts `executable` with `arguments` and returns: its input and output
    /// the null device, so nothing it says lands in the frame and it reads
    /// none of the person's keys. Nothing on wasip1, which makes no processes.
    private static func launchProcess(_ executable: String, _ arguments: [String]) {
        #if !canImport(WASILibc)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        #endif
    }
}
