//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScenePresenter+WindowMenu.swift
//
//  What the menu bar's Window menu shows of the presenter's windows, and the
//  presenter in the environment, where the menu bar finds it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Window Menu's Reading

extension ScenePresenter {
    /// One open window, as the Window menu lists it.
    package struct ListedWindow {
        /// The window's serial number, which the menu brings it to the front
        /// by.
        package let serial: Int

        /// Its scene's title, or `nil` for a scene with none.
        package let title: String?

        /// Whether it is the window in front.
        package let isFront: Bool
    }

    /// One `Window` scene, as the Window menu offers to open it.
    package struct ListedScene {
        /// The scene's identifier, which the menu opens it by.
        package let id: String

        /// Its title.
        package let title: String?

        /// The key that opens it, if its `.keyboardShortcut` states one.
        package let shortcut: KeyboardShortcut?
    }

    /// Whether the app can have more than one window open: whether it has
    /// windows to list, and the Window menu anything to show. It can where it
    /// declares more than one window scene, or a window group that something
    /// opens another window of — `openWindow` by the group's identifier or by
    /// a value it presents, or the key its `.keyboardShortcut` states. A lone
    /// group with none of those has its one window for the life of the app.
    package var opensSeveralWindows: Bool {
        entries.count > 1 || entries.contains { opensFurtherWindows(of: $0) }
    }

    /// Whether something can open another window of the scene `entry`, one
    /// already open: a group that `openWindow` names, or whose key opens one.
    private func opensFurtherWindows(of entry: SceneCatalog.WindowEntry) -> Bool {
        guard !entry.window.opensOneWindow else { return false }
        return entry.window.sceneID != nil || entry.window.presentedValueType != nil || shortcut(of: entry) != nil
    }

    /// The open windows, back to front.
    package var listedWindows: [ListedWindow] {
        let front = front?.serial
        return windows.map { window in
            ListedWindow(
                serial: window.serial, title: entry(of: window)?.window.windowTitle?.content,
                isFront: window.serial == front)
        }
    }

    /// The `Window` scenes the app declares, in declaration order.
    package var listedScenes: [ListedScene] {
        entries.compactMap { entry in
            guard entry.window.opensOneWindow, let id = entry.window.sceneID else { return nil }
            return ListedScene(id: id, title: entry.window.windowTitle?.content, shortcut: shortcut(of: entry))
        }
    }

    /// Whether the person may close the window in front — the Window menu's
    /// Close Window, a visibility toggle's Hide, as Escape may: not the last
    /// one, whose closing would quit the app (the app menu's Quit does that),
    /// nor one whose content disabled its dismissal, nor one showing a modal
    /// presentation, which an interactive dismissal leaves open (B-O9-4).
    package var canCloseFrontWindow: Bool {
        guard windows.count > 1, let front else { return false }
        return front.closesInteractively && !front.showsModalPresentation
    }

    /// Brings the window `serial` to the front: what choosing it in the
    /// Window menu does.
    package func showWindow(_ serial: Int) {
        bringToFront(serial)
    }

    /// Closes the window in front, where the person may
    /// (``canCloseFrontWindow``): the Window menu's Close Window, which a
    /// person chooses as they would press Escape.
    package func closeFrontWindow() {
        guard canCloseFrontWindow, let front else { return }
        close([front.serial])
    }

    /// Opens the `Window` scene `id`, or brings its window to the front.
    package func openScene(_ id: String) {
        open(WindowTarget(id: id))
    }
}

// MARK: - In the Environment

extension ScenePresenter: Equatable {
    /// Whether the two are the same app's: compared by identity, so the
    /// environment that carries one keeps the memos below it on.
    nonisolated package static func == (lhs: ScenePresenter, rhs: ScenePresenter) -> Bool {
        lhs === rhs
    }
}

extension EnvironmentValues {
    /// The running app's scene presenter, for the menu bar's Window menu;
    /// `nil` outside a running app.
    ///
    /// Held weakly (``WeakScenePresenter``), in the substrate's
    /// `.scenePresenter` slot (``FeatureObjectSlot``), which detaching an
    /// environment clears: the presenter holds the app's scenes, their views
    /// and every window's bars, and through them environments that reach the
    /// app's services, so an environment a view kept — in a key handler's
    /// closure, a focus registration — that held it strongly kept the app's
    /// state, cache and dispatchers alive after its loop.
    package var scenePresenter: ScenePresenter? {
        (self[featureObject: .scenePresenter] as? WeakScenePresenter)?.presenter
    }

    /// Where ``scenePresenter`` is read from: the presenter's
    /// ``ScenePresenter/environmentReference``, which the run loop publishes.
    var scenePresenterReference: WeakScenePresenter? {
        get { self[featureObject: .scenePresenter] as? WeakScenePresenter }
        set { self[featureObject: .scenePresenter] = newValue }
    }
}

/// The presenter, weakly, as the environment carries it
/// (``EnvironmentValues/scenePresenter``): one per presenter
/// (``ScenePresenter/environmentReference``), so the environment holds the
/// same object from frame to frame.
final class WeakScenePresenter {
    weak var presenter: ScenePresenter?

    init(_ presenter: ScenePresenter) {
        self.presenter = presenter
    }
}
