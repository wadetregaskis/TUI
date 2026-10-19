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
    }

    /// Whether the app declares more than one window scene: whether it has
    /// windows to list, and the Window menu anything to show.
    package var opensSeveralWindows: Bool { entries.count > 1 }

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
            return ListedScene(id: id, title: entry.window.windowTitle?.content)
        }
    }

    /// Whether the window in front can be closed from the menu: not the last
    /// one, whose closing would quit the app (the app menu's Quit does that).
    package var canCloseFrontWindow: Bool { windows.count > 1 }

    /// Brings the window `serial` to the front: what choosing it in the
    /// Window menu does.
    package func showWindow(_ serial: Int) {
        bringToFront(serial)
    }

    /// Closes the window in front, if it is not the last: the Window menu's
    /// Close Window, which a person chooses as they would press Escape.
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

private struct ScenePresenterKey: EnvironmentKey {
    static let defaultValue: ScenePresenter? = nil
}

extension EnvironmentValues {
    /// The running app's scene presenter, for the menu bar's Window menu;
    /// `nil` outside a running app.
    package var scenePresenter: ScenePresenter? {
        get { self[ScenePresenterKey.self] }
        set { self[ScenePresenterKey.self] = newValue }
    }
}
