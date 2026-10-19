//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScenePresenter.swift
//
//  The one place an app's scenes are presented from: which windows are open,
//  in what order, and how they share the one surface a terminal app has.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Policy

/// How the app's open windows share the surface: where each is drawn.
///
/// A terminal app has one surface, the terminal it runs in. Refusal review O9
/// was ruled (b) on 2026-10-12: secondary scenes are full-surface covers stacked
/// over the main one — and room is to be left for a real windowing model. So the
/// presenter asks a policy where the windows go, rather than deciding it, and a
/// tiling or overlapping manager is a policy that answers otherwise, with the
/// presenter, the actions and every scene's API unchanged.
@MainActor
protocol ScenePresentationPolicy {
    /// Where each of `windows`, back to front, is drawn: one placement each.
    func placements(of windows: [ScenePresenter.OpenWindow]) -> [ScenePresenter.Placement]
}

/// The first policy: every window covers the whole surface, the front one is
/// drawn, and each behind it is held — drawn off-screen, so its state, its
/// lifecycle and its tasks carry on — until the windows in front of it close.
struct StackedCoversPolicy: ScenePresentationPolicy {
    func placements(of windows: [ScenePresenter.OpenWindow]) -> [ScenePresenter.Placement] {
        windows.indices.map { $0 == windows.count - 1 ? .wholeSurface : .covered }
    }
}

// MARK: - The Presenter

/// Opens, orders and closes the app's windows, and draws them on the surface as
/// its policy places them. Every scene presentation goes through it: the window
/// opened at launch, and `openWindow` and `dismissWindow`
/// (``SceneActionHandler``).
///
/// One per running app, owned by its render loop: no singleton.
@MainActor
package final class ScenePresenter {
    /// Where the policy puts a window.
    enum Placement: Equatable {
        /// Drawn over the whole surface: the window in front.
        case wholeSurface

        /// Not drawn, held behind the window in front of it: drawn off-screen,
        /// into nothing, so that it keeps its state.
        case covered
    }

    /// One open window: an instance of a window scene.
    package final class OpenWindow {
        /// Which window this is, unique for the life of the app: what a
        /// window's own `dismissWindow` names it by.
        package let serial: Int

        /// Which window scene it is an instance of: the scene's identity, as
        /// the catalogue reckons it.
        let sceneKey: ViewIdentity

        /// Whether it is the window opened at launch, which draws at the
        /// scene's identity and in the page's focus section, as an app of one
        /// window always has.
        let isLaunchWindow: Bool

        /// Its bars: their rows, their items, the menu bar's place — kept while
        /// another window is in front, so it comes back as it was left.
        let chrome = WindowChromeState()

        /// What `dismiss()` at its root does: close it.
        let dismissBox = DismissAction.Box()

        /// Where the focus rested in it when another window came in front of
        /// it, or `nil` while it has never lost the focus.
        var focus: FocusManager.Place?

        /// Whether its bars have yet to be found by a measuring walk, which a
        /// window's first frame takes so its bars are there from the start.
        var needsSeeding = true

        /// The value it presents, for a window of a group that presents data
        /// (`WindowGroup(for:)`); `nil` for any other.
        let presented: PresentedWindowSlot?

        /// Whether it showed a modal presentation — a sheet, a cover, an
        /// alert, holding its keyboard — when last drawn: what an interactive
        /// dismissal leaves open.
        var showsModalPresentation = false

        /// Where its `@SceneStorage` keeps its values, after `scene.`
        /// (``EnvironmentValues/sceneStorageNamespace``).
        let storageNamespace: String

        init(
            serial: Int, sceneKey: ViewIdentity, isLaunchWindow: Bool, presented: PresentedWindowSlot?,
            storageNamespace: String
        ) {
            self.serial = serial
            self.sceneKey = sceneKey
            self.isLaunchWindow = isLaunchWindow
            self.presented = presented
            self.storageNamespace = storageNamespace
        }

        /// The focus section its content registers in: the page's for the
        /// launch window, one of its own for each other.
        var focusSection: String {
            isLaunchWindow ? FocusManager.defaultSectionID : "window-\(serial)"
        }

        /// The identity its scene tree is walked from, under the scene's
        /// identity `root`: that identity for the launch window, as an app of
        /// one window always had, and a child of it of its own for each other,
        /// so two windows of one group keep apart everything they hold.
        func rootIdentity(under root: ViewIdentity) -> ViewIdentity {
            isLaunchWindow ? root : root.child(erasedType: OpenWindow.self, key: "window-\(serial)")
        }
    }

    /// The open windows, back to front.
    package private(set) var windows: [OpenWindow] = []

    /// The window scenes the app declared, as last catalogued.
    private(set) var entries: [SceneCatalog.WindowEntry] = []

    /// The scenes the app declared that are shown over the window in front,
    /// as last catalogued.
    private(set) var overlayEntries: [SceneCatalog.OverlayEntry] = []

    /// Whether the `Settings` scene is presented, over the window in front.
    package var isPresentingSettings = false {
        didSet { if isPresentingSettings != oldValue { requestFrame() } }
    }

    /// The serial number the next window opened takes.
    private var nextSerial = 0

    /// How many windows of each scene have been opened this session: what a
    /// window's scene storage is told apart from its group's others by.
    private var openedCounts: [ViewIdentity: Int] = [:]

    /// Whether the launch window has been opened.
    private var hasLaunched = false

    /// Whether the presenter has asked the app to quit, every window closed.
    package private(set) var hasRequestedExit = false

    /// The serial number of the window drawn in front last frame, which the
    /// focus was in.
    private var lastFront: Int?

    /// What the window actions a view calls reach: this presenter.
    let actions = SceneActionHandler()

    /// Where the windows go.
    var policy: any ScenePresentationPolicy = StackedCoversPolicy()

    /// Asks the app to quit — with every window closed, a terminal app has
    /// nothing to show.
    var requestExit: () -> Void = { AppState.shared.requestExit() }

    /// Asks for a frame, after a window opened or closed between frames.
    var requestFrame: () -> Void = { AppState.shared.setNeedsRender() }

    /// The bars drawn while no window is open.
    private let closedChrome = WindowChromeState()

    init() {
        actions.openWindow = { [weak self] target in self?.open(target) ?? false }
        actions.openSettings = { [weak self] in self?.presentSettings() }
        actions.hasSettings = { [weak self] in self?.hasSettings ?? false }
        actions.dismissWindow = { [weak self] dismissal, behavior in self?.dismiss(dismissal, behavior: behavior) }
    }

    // MARK: Each Frame

    /// Adopts this frame's catalogue: opens the launch window on the first, and
    /// closes a window whose scene the app no longer declares.
    func sync(with catalog: SceneCatalog) {
        entries = catalog.windows
        overlayEntries = catalog.overlays
        if !hasSettings { isPresentingSettings = false }
        windows.removeAll { window in !entries.contains { $0.identity == window.sceneKey } }
        if !hasLaunched {
            hasLaunched = true
            if let launch = entries.first {
                windows.append(makeWindow(of: launch, isLaunchWindow: true))
            }
        }
        if windows.isEmpty { quit() }
    }

    /// Where the policy places each open window, back to front.
    var placements: [Placement] { policy.placements(of: windows) }

    /// The window drawn over the whole surface, if one is.
    var front: OpenWindow? {
        let placements = placements
        return windows.indices.last { placements[$0] == .wholeSurface }.map { windows[$0] }
    }

    /// The window scene `window` is an instance of.
    func entry(of window: OpenWindow) -> SceneCatalog.WindowEntry? {
        entries.first { $0.identity == window.sceneKey }
    }

    /// The bars of the window drawn in front, or of none while no window is
    /// open: what the run loop's chrome is this frame.
    var frontChrome: WindowChromeState { front?.chrome ?? closedChrome }

    // MARK: Settings and Other Overlays

    /// Whether the app declares a `Settings` scene.
    var hasSettings: Bool {
        overlayEntries.contains { $0.scene.isSettings }
    }

    /// Presents the `Settings` scene over the window in front, if the app
    /// declares one; where it is up already, it stays.
    func presentSettings() {
        guard hasSettings else { return }
        isPresentingSettings = true
    }

    /// The overlay scenes, as the window in front presents them this frame.
    func overlays() -> SceneOverlayList? {
        guard !overlayEntries.isEmpty else { return nil }
        return SceneOverlayList(
            overlayEntries.map { entry in
                SceneOverlay(
                    key: entry.identity.path, configuration: entry.configuration, view: entry.scene.overlay(in: self))
            })
    }

    // MARK: Opening and Closing

    /// Opens the window `target` names: brings a `Window`'s open window, or a
    /// window presenting an equal value, to the front; otherwise opens a new
    /// window of the scene, presenting the target's value.
    ///
    /// - Returns: Whether a scene answers to `target`: a target none does
    ///   opens nothing.
    @discardableResult
    func open(_ target: WindowTarget) -> Bool {
        guard let entry = entries.first(where: { $0.answers(to: target) }) else { return false }
        let ofScene = windows.filter { $0.sceneKey == entry.identity }
        if let value = target.value, let showing = ofScene.first(where: { $0.presented?.value == value }) {
            bringToFront(showing.serial)
        } else if entry.window.opensOneWindow, let open = ofScene.first {
            bringToFront(open.serial)
        } else {
            windows.append(makeWindow(of: entry, isLaunchWindow: false, value: target.value))
            requestFrame()
        }
        return true
    }

    /// Brings the window `serial` to the front of the others.
    func bringToFront(_ serial: Int) {
        guard let index = windows.firstIndex(where: { $0.serial == serial }), index != windows.count - 1 else { return }
        windows.append(windows.remove(at: index))
        requestFrame()
    }

    /// Closes the windows `dismissal` names — under an interactive `behavior`,
    /// those not showing a modal presentation.
    func dismiss(_ dismissal: WindowDismissal, behavior: DismissBehavior = .interactive) {
        let closable = { (window: OpenWindow) in behavior == .destructive || !window.showsModalPresentation }
        switch dismissal {
        case .current(let serial):
            close(windows.filter { $0.serial == serial && closable($0) }.map(\.serial))
        case .target(let target):
            let keys = entries.filter { $0.answers(to: target) }.map(\.identity)
            let named = windows.filter { window in
                keys.contains(window.sceneKey) && (target.value == nil || window.presented?.value == target.value)
                    && closable(window)
            }
            close(named.map(\.serial))
        }
    }

    /// Closes the windows `serials`; the window behind comes to the front, and
    /// with none left the app quits.
    func close(_ serials: [Int]) {
        guard !serials.isEmpty else { return }
        let before = windows.count
        windows.removeAll { serials.contains($0.serial) }
        guard windows.count != before else { return }
        requestFrame()
        if windows.isEmpty { quit() }
    }

    /// A new window of `entry`, presenting `value` if its scene presents data.
    private func makeWindow(
        of entry: SceneCatalog.WindowEntry, isLaunchWindow: Bool, value: AnyHashable? = nil
    ) -> OpenWindow {
        let presented = entry.window.presentedValueType.map { _ in PresentedWindowSlot(openedValue: value) }
        let window = OpenWindow(
            serial: nextSerial, sceneKey: entry.identity, isLaunchWindow: isLaunchWindow, presented: presented,
            storageNamespace: storageNamespace(of: entry, isLaunchWindow: isLaunchWindow))
        nextSerial += 1
        let serial = window.serial
        window.dismissBox.action = { [weak self] in self?.close([serial]) }
        return window
    }

    /// Where a new window of `entry` keeps its `@SceneStorage`: nothing more
    /// than `scene.` for the launch window, as an app of one window always
    /// had; the scene's identifier (or its place among the window scenes, for
    /// one with none) for a `Window`'s and the first of a group's; and that
    /// with the how-manyth of its group it is for each after.
    private func storageNamespace(of entry: SceneCatalog.WindowEntry, isLaunchWindow: Bool) -> String {
        let ordinal = openedCounts[entry.identity, default: 0] + 1
        openedCounts[entry.identity] = ordinal
        guard !isLaunchWindow else { return "" }
        let index = entries.firstIndex { $0.identity == entry.identity } ?? 0
        let scene = entry.window.sceneID ?? "scene-\(index)"
        return ordinal > 1 && !entry.window.opensOneWindow ? "\(scene)#\(ordinal)." : "\(scene)."
    }

    /// Asks the app to quit, once.
    private func quit() {
        guard !hasRequestedExit else { return }
        hasRequestedExit = true
        requestExit()
    }

    // MARK: The Focus

    /// Moves the focus into the window in front, if it is not the one the focus
    /// was in last frame: to where it rested there, or into its section. Where
    /// it rested in the window it leaves is kept for when that one comes back.
    func handFocus(to front: OpenWindow, focusManager: FocusManager?) {
        guard lastFront != front.serial else { return }
        defer { lastFront = front.serial }
        // The launch window's first frame: the focus is already the page's.
        guard let lastFront, let focusManager else { return }
        windows.first { $0.serial == lastFront }?.focus = focusManager.place
        focusManager.move(to: front.focus, enteringSection: front.focusSection)
    }
}

// MARK: - Which Scene a Target Names

@MainActor
extension SceneCatalog.WindowEntry {
    /// Whether `openWindow` or `dismissWindow` with `target` names this scene:
    /// its identifier, where the target names one, and for a target with a
    /// value, a group presenting values of its type.
    func answers(to target: WindowTarget) -> Bool {
        if let valueType = target.valueType {
            guard let presented = window.presentedValueType, ObjectIdentifier(presented) == ObjectIdentifier(valueType)
            else { return false }
            return target.id.map { window.sceneID == $0 } ?? true
        }
        guard let id = target.id else { return false }
        return window.sceneID == id
    }
}
