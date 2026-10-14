//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HostReduceMotionRefresher.swift
//
//  The host's own Reduce Motion, counted where TUIkit is sure the user is at
//  this machine (refusal review O1): asked off the main actor at launch and
//  again whenever the terminal regains the focus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation
import TUIkitTerminalHost

/// Keeps the host's Reduce Motion current for the app runner, which hands it
/// to its render loop to OR into the root's `accessibilityReduceMotion`
/// (``RenderLoop/hostReducesMotion``).
///
/// Asked at launch, and again each time the terminal regains the focus: the
/// user may have been in System Settings meanwhile. Each reading is blocking
/// (a `gsettings` call on Linux, a tmux one inside tmux), so it runs off the
/// main actor, and readings coalesce as the capability refresher's do: at most
/// one in flight, and a request made while it runs re-reads once when it ends.
/// A reading lands a frame or two after launch, which a launch that animates
/// nothing never shows.
@MainActor
internal final class HostReduceMotionRefresher {
    /// The last reading: `false` until the first lands.
    private(set) var reducesMotion = false

    /// Produces a reading. Blocking (bounded); always run off the main actor.
    private let read: @Sendable () -> Bool

    /// Runs, on the main actor, when a reading differs from the last.
    private let onChange: @MainActor (Bool) -> Void

    private var coalescer = ProbeCoalescer()

    init(
        read: @escaping @Sendable () -> Bool = HostReduceMotionRefresher.readHost,
        onChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.read = read
        self.onChange = onChange
    }

    /// Whether no reading is in flight or queued, for a test to wait on.
    var isIdleForTesting: Bool { coalescer.isIdle }

    /// Reads the host's setting again, off the main actor.
    func refresh() {
        guard coalescer.requestProbe() else { return }
        startReading()
    }

    private func startReading() {
        let read = self.read
        Task.detached(priority: .utility) { [weak self] in
            let reduces = read()
            await self?.apply(reduces)
        }
    }

    private func apply(_ reduces: Bool) {
        if reduces != reducesMotion {
            reducesMotion = reduces
            onChange(reduces)
        }
        if coalescer.probeCompleted() {
            startReading()
        }
    }

    /// The host's Reduce Motion, counted only where the session is provably
    /// local (``SessionLocality/isLocal()``): over ssh it would be the
    /// server's, and say nothing about the person at the keyboard. The host is
    /// asked first, so where it reduces nothing — most machines — the locality
    /// test, a tmux subprocess inside tmux, is not run. A wrong "local" can
    /// only add reduced motion.
    nonisolated static func readHost() -> Bool {
        TerminalClient.hostReducesMotion() == true && SessionLocality.isLocal()
    }
}
