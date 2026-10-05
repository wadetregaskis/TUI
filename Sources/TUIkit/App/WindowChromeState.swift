//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowChromeState.swift
//
//  The rows the window's bars hold from one frame to the next: last frame's
//  answer, adopted a frame after the walk that changed it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Window Chrome State

/// What the window's chrome holds, frame to frame: how many rows of content
/// each bar keeps, so the chrome host can reserve them BEFORE the content draws.
///
/// The content is what declares the bars, as it draws, so the rows a frame is
/// laid out against cannot be this walk's answer — finding it would take
/// another walk, thrown away, and a walk thrown away runs effects for a tree
/// nobody sees (the effect leak `RenderPassScopeTests` pinned for as long as
/// the run loop re-rendered on a header-height change). So a bar's rows are
/// LAST frame's answer (the A28 design study's policy P2):
///
/// - Each frame is laid out against the reservation and drawn honestly at it.
///   A bar that grew this walk is cut to its reserved rows; one that shrank or
///   went is padded with its own background.
/// - After the walk the chrome host compares what the content declared with
///   what it reserved (``settle(_:wanting:)``). A difference is adopted for the
///   NEXT frame, and that frame is asked for, so a still screen still gets it.
/// - Frame 1 has no last frame: the run loop's first-frame measuring walk
///   ``seed(_:rows:)``s it, so an app that declares its chrome once at the root
///   never sees a frame without it.
///
/// A frame is therefore one walk, always, after the first. The price is that
/// a bar appears or goes a frame (≥ 16.7 ms) late.
///
/// ## Oscillation
///
/// A page whose layout at the smaller height stops declaring a bar — a
/// `ViewThatFits` that picks a variant without one — would flip every frame:
/// reserve, lose the declaration, release, regain it. Two rules hold it still:
///
/// - A bar is never released in the frame after it was reserved. The release
///   waits a frame (which is asked for), so a one-frame bounce costs nothing.
/// - A bar that changes back and forth three times within
///   ``oscillationWindow`` frames is PINNED at the larger of the two, and the
///   flip is reported on the diagnostic channel. It stays pinned while the
///   content keeps declaring either of the two, for ``pinNanos``; then the
///   declaration is adopted again, in case the flipping was a person changing
///   pages faster than the guard can tell from a layout that cannot settle. A
///   declaration of anything else is a real change, and unpins it at once.
final class WindowChromeState: @unchecked Sendable {
    /// Which of the window's bars.
    enum Edge: CaseIterable {
        /// The app header, at the very top.
        case header
        /// The top toolbar, under the header.
        case top
        /// The bottom toolbar, above the status bar.
        case bottom
        /// The status bar, at the very bottom.
        case statusBar
    }

    /// A toolbar item a walk declared, as the bar draws it.
    struct ToolbarEntry {
        /// Where the item goes.
        let placement: ToolbarItemPlacement
        /// What the item draws.
        let view: AnyView
        /// The environment of the view that declared it.
        let environment: EnvironmentValues
        /// The identity it was declared at.
        let identity: ViewIdentity
    }

    /// One bar's reservation and the history its oscillation guard reads.
    struct Bar: Equatable {
        /// Rows of content the bar holds this frame, before its style frames
        /// them. 0 is no bar.
        var rows = 0
        /// The frame number the last adoption was recorded in, or `nil`.
        var lastChange: Int?
        /// Recent adoptions — the frame, and the rows before and after — kept
        /// for ``oscillationWindow`` frames.
        var recent: [Adoption] = []
        /// The two values the bar is flipping between, while it is pinned.
        var pinned: Set<Int>?
        /// When the pin was set, on the frame clock.
        var pinnedAtNanos: Int64 = 0
    }

    /// What settling a bar asks of the run loop.
    enum Settlement: Equatable {
        /// Nothing: the bar is what the content declared, or is held there.
        case settled
        /// The next frame: it draws the adopted reservation, or lets a held
        /// release through.
        case nextFrame
        /// A frame at this instant on the frame clock: when a pin lapses.
        case frame(atNanos: Int64)
    }

    /// A change of reservation, as the oscillation guard remembers it.
    struct Adoption: Equatable {
        let frame: Int
        let from: Int
        let to: Int
    }

    /// How many frames back a flip counts towards pinning.
    static let oscillationWindow = 12

    /// How long a pin holds before the content's declaration is tried again:
    /// one second, sixty frames.
    static let pinNanos: Int64 = 1_000_000_000

    /// The app header's reservation.
    private(set) var header = Bar()

    /// The top toolbar's reservation.
    private(set) var top = Bar()

    /// The bottom toolbar's reservation.
    private(set) var bottom = Bar()

    /// The status bar's reservation.
    private(set) var statusBar = Bar()

    /// The toolbar items this walk has declared, in the order it declared them.
    private(set) var toolbarEntries: [ToolbarEntry] = []

    /// The identities of ``toolbarEntries``, so an item a walk renders twice —
    /// the first frame's measuring walk measures some views by rendering them —
    /// is declared once.
    private var declaredIdentities: Set<ViewIdentity> = []

    /// The window's title: the root `.navigationTitle`, as the last frame's
    /// content published it.
    ///
    /// Scene-level data: the top bar shows it in its title slot, and it is
    /// what a terminal window title (OSC 2) would be set from.
    var title = ""

    /// The window's subtitle: the root `.navigationSubtitle`.
    var subtitle = ""

    /// Frames begun, counted by ``beginFrame()``.
    private(set) var frame = 0

    /// Whether the run loop's first-frame walk has seeded the reservations.
    private(set) var isSeeded = false

    /// The flips reported so far, oldest first — what a test reads instead of
    /// the diagnostic channel.
    private(set) var oscillationReports: [Edge] = []

    /// Rows of content `edge` holds this frame.
    func rows(_ edge: Edge) -> Int {
        self[edge].rows
    }

    /// Counts a frame. Called by the run loop before the scene is walked.
    func beginFrame() {
        frame += 1
    }

    /// Forgets the toolbar items the last walk declared. Called by the run loop
    /// before every walk of the scene: what a walk declares is that walk's.
    func beginWalk() {
        toolbarEntries.removeAll(keepingCapacity: true)
        declaredIdentities.removeAll(keepingCapacity: true)
    }

    /// Records a toolbar item the walk declared — once per identity.
    func declare(_ entry: ToolbarEntry) {
        guard declaredIdentities.insert(entry.identity).inserted else { return }
        toolbarEntries.append(entry)
    }

    /// The items this walk declared for the toolbar at `edge`.
    func toolbarEntries(for edge: Edge) -> [ToolbarEntry] {
        toolbarEntries.filter { $0.placement.bar == edge }
    }

    /// Takes `rows` as `edge`'s reservation outright: what the first frame's
    /// measuring walk found the content declaring.
    func seed(_ edge: Edge, rows: Int) {
        self[edge].rows = rows
        isSeeded = true
    }

    /// Compares what the content declared for `edge` this walk with what the
    /// frame reserved, and adopts a difference for the next frame.
    ///
    /// - Parameters:
    ///   - edge: The bar.
    ///   - wanted: The rows of content the walk declared for it.
    ///   - nowNanos: This frame's instant on the frame clock, for a pin's lapse.
    /// - Returns: What the run loop owes the bar.
    func settle(_ edge: Edge, wanting wanted: Int, nowNanos: Int64) -> Settlement {
        var bar = self[edge]
        defer { self[edge] = bar }
        bar.recent.removeAll { frame - $0.frame > Self.oscillationWindow }
        guard wanted != bar.rows else { return .settled }

        if let pinned = bar.pinned {
            if pinned.contains(wanted) {
                // Still flipping between the same two: hold the larger until
                // the pin lapses, then try the declaration again.
                let lapse = bar.pinnedAtNanos &+ Self.pinNanos
                guard nowNanos >= lapse else { return .frame(atNanos: lapse) }
                bar.recent = []
            }
            bar.pinned = nil
        }

        // Never release in the frame after reserving: wait one frame, and ask
        // for it, so a bounce that settles costs nothing and a real release
        // still happens on a still screen.
        if wanted < bar.rows, bar.lastChange == frame - 1 { return .nextFrame }

        // Back to a value two recent changes have both touched, one of them by
        // leaving it: the third flip. Hold the larger of the two.
        let flips = bar.recent.filter { $0.from == wanted || $0.to == wanted }
        if flips.count >= 2, flips.contains(where: { $0.from == wanted }) {
            let other = bar.rows
            bar.pinned = [wanted, other]
            bar.pinnedAtNanos = nowNanos
            bar.lastChange = frame
            report(edge, between: wanted, and: other)
            guard wanted > other else { return .frame(atNanos: nowNanos &+ Self.pinNanos) }
            bar.rows = wanted
            return .nextFrame
        }

        bar.recent.append(Adoption(frame: frame, from: bar.rows, to: wanted))
        bar.rows = wanted
        bar.lastChange = frame
        return .nextFrame
    }

    /// The bar's state for `edge`.
    private subscript(edge: Edge) -> Bar {
        get {
            switch edge {
            case .header: header
            case .top: top
            case .bottom: bottom
            case .statusBar: statusBar
            }
        }
        set {
            switch edge {
            case .header: header = newValue
            case .top: top = newValue
            case .bottom: bottom = newValue
            case .statusBar: statusBar = newValue
            }
        }
    }

    /// Says on the diagnostic channel that `edge` is flipping and has been
    /// pinned.
    private func report(_ edge: Edge, between first: Int, and second: Int) {
        oscillationReports.append(edge)
        DiagnosticChannel.emit(
            """
            [TUIkit] the window's \(edge) bar keeps changing between \(first) and \(second) rows \
            (frame \(frame)): the page declares it at one height and not at the other. Holding \
            the larger.

            """)
    }
}

// MARK: - Environment Key

/// Environment key for the window's chrome state.
private struct WindowChromeKey: EnvironmentKey {
    static let defaultValue: WindowChromeState? = nil
}

/// Environment key for the first frame's seeding walk.
private struct SeedsWindowChromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this walk is the first frame's measuring walk, which seeds the
    /// window's chrome: a `.toolbar` declares its items there although the walk
    /// measures, and nowhere else that measures. Read by `.toolbar` alone.
    var seedsWindowChrome: Bool {
        get { self[SeedsWindowChromeKey.self] }
        set { self[SeedsWindowChromeKey.self] = newValue }
    }

    /// The window's chrome state: the rows each bar holds this frame.
    ///
    /// `nil` outside a running application, as every runtime service is — a
    /// headless render of a scene reserves no chrome and draws every bar it is
    /// handed at its own height.
    var windowChrome: WindowChromeState? {
        get { self[WindowChromeKey.self] }
        set { self[WindowChromeKey.self] = newValue }
    }
}
