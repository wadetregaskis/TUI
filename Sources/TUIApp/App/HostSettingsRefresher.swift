//  🖥️ TUI — A Terminal UI framework for Swift
//  HostSettingsRefresher.swift
//
//  The host's own settings — its accessibility settings, Reduce Motion among
//  them — counted where TUI is sure the user is at this machine (refusal
//  review O1): asked off the main actor at launch and again whenever the
//  terminal regains the focus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUITerminalHost

/// What TUI reads from the machine the app runs on, where the user is
/// provably at it (``HostSettingsRefresher``).
struct HostSettings: Equatable, Sendable {
    /// The host's accessibility settings: Reduce Motion and its three siblings.
    var accessibility: AccessibilityPreferences = []

    /// The host's spring-loading delay, where it states one (owner ruling B82).
    var springLoadingDelay: Duration?

    /// Whether this reading asks for anything a host left at its defaults
    /// does not: what decides whether the session's locality is worth asking.
    var asksForAnything: Bool {
        !accessibility.isEmpty || (springLoadingDelay.map { $0 != EnvironmentValues().springLoadingDelay } ?? false)
    }
}

/// Keeps the host's settings current for the app runner, which hands them to
/// its render loop to add to the user's at the root
/// (``RenderLoop/hostAccessibility``, ``RenderLoop/hostSpringLoadingDelay``).
///
/// Asked at launch, and again each time the terminal regains the focus: the
/// user may have been in System Settings meanwhile. Each reading is blocking
/// (a `gsettings` call on Linux, a tmux one inside tmux), so it runs off the
/// main actor, and readings coalesce as the capability refresher's do: at most
/// one in flight, and a request made while it runs re-reads once when it ends.
/// A reading lands a frame or two after launch, which a launch that animates
/// nothing never shows.
@MainActor
internal final class HostSettingsRefresher {
    /// The last reading: nothing until the first lands.
    private(set) var settings = HostSettings()

    /// Produces a reading. Blocking (bounded); always run off the main actor.
    private let read: @Sendable () -> HostSettings

    /// Runs, on the main actor, when a reading differs from the last.
    private let onChange: @MainActor (HostSettings) -> Void

    private var coalescer = ProbeCoalescer()

    init(
        read: @escaping @Sendable () -> HostSettings = HostSettingsRefresher.readHost,
        onChange: @escaping @MainActor (HostSettings) -> Void
    ) {
        self.read = read
        self.onChange = onChange
    }

    /// Whether no reading is in flight or queued, for a test to wait on.
    var isIdleForTesting: Bool { coalescer.isIdle }

    /// Reads the host's settings again, off the main actor.
    func refresh() {
        guard coalescer.requestProbe() else { return }
        startReading()
    }

    private func startReading() {
        let read = self.read
        Task.detached(priority: .utility) { [weak self] in
            let settings = read()
            await self?.apply(settings)
        }
    }

    private func apply(_ read: HostSettings) {
        if read != settings {
            settings = read
            onChange(read)
        }
        if coalescer.probeCompleted() {
            startReading()
        }
    }

    /// The host's settings, counted only where the session is provably local
    /// (``SessionLocality/isLocal()``): over ssh they would be the server's,
    /// and say nothing about the person at the keyboard. The host is asked
    /// first, so where it asks for nothing — most machines — the locality test,
    /// a tmux subprocess inside tmux, is not run. A wrong "local" can only add
    /// a preference.
    nonisolated static func readHost() -> HostSettings {
        let host = HostSettings(
            accessibility: TerminalClient.hostAccessibility() ?? [],
            springLoadingDelay: TerminalClient.hostSpringLoadingDelay())
        guard host.asksForAnything, SessionLocality.isLocal() else { return HostSettings() }
        return host
    }
}
