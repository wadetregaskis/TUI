//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScenePresenter+Render.swift
//
//  Drawing the open windows as the presenter's policy places them: the one in
//  front as the frame, each behind it off-screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension ScenePresenter {
    /// Draws the open windows of `scene` as the policy places them, and returns
    /// the frame: the window in front's buffer, the size of `context`.
    ///
    /// A window held behind another is drawn first, off-screen, isolated from
    /// the focus, the keys, the status bar and the clock as a navigation
    /// stack's covered root is, its buffer dropped: what that keeps is its
    /// `@State`, which the end of the pass would otherwise collect, its
    /// lifecycle — a window behind another has not disappeared — and its tasks.
    /// Drawn with its own scene's statements (`environment`), not the front
    /// window's. Not on a measuring walk, which keeps nothing.
    ///
    /// - Parameters:
    ///   - scene: The app's scene.
    ///   - context: The frame's context, at the scene's identity.
    ///   - environment: The environment a held window draws with, for its
    ///     scene's configuration: kept by the run loop on every frame that
    ///     holds a window (``holdsWindows``), and so never `nil` here.
    func render(
        _ scene: some Scene, context: RenderContext,
        environment: (SceneConfiguration) -> EnvironmentValues?
    ) -> FrameBuffer {
        guard let front else { return FrameBuffer() }
        if !context.isMeasuring {
            for (window, placement) in zip(windows, placements) where placement == .covered {
                renderHeld(window, scene: scene, context: context, environment: environment)
            }
            handFocus(to: front, focusManager: context.environment.focusManager)
        }
        return renderFront(front, scene: scene, context: context)
    }

    /// `context` for drawing `window`: at its identity, aimed at its scene,
    /// with its own dismissals and its focus section.
    private func context(
        for window: OpenWindow, entry: SceneCatalog.WindowEntry, from context: RenderContext
    ) -> RenderContext {
        var context = context
        context.identity = window.rootIdentity(under: context.identity)
        context.environment.sceneRenderTarget = SceneRenderTarget(path: entry.path)
        // At its root, dismissing means closing the window, as SwiftUI's
        // documentation says of a window's root view on macOS. The app quits
        // when the last one closes.
        context.environment.dismiss = DismissAction(box: window.dismissBox)
        context.environment.dismissWindow = DismissWindowAction(handler: actions, window: window.serial)
        context.environment.presentedWindow = window.presented
        context.environment.sceneStorageNamespace = window.storageNamespace
        if !window.isLaunchWindow { context.environment.activeFocusSectionID = window.focusSection }
        return context
    }

    /// Draws `window`, held behind the one in front, into nothing.
    private func renderHeld(
        _ window: OpenWindow, scene: some Scene, context: RenderContext,
        environment: (SceneConfiguration) -> EnvironmentValues?
    ) {
        guard let entry = entry(of: window) else { return }
        var held = context
        // The frame's own, with the front window's statements, only were the
        // windows to change between the loop's keeping its base and this
        // walk, which no code runs in: drawn all the same, so it keeps its
        // state.
        held.environment = environment(entry.configuration) ?? context.environment
        let backdrop = self.context(for: window, entry: entry, from: held).isolatedForBackground()
        _ = backdrop.withThrowawayFrameDemand { hidden in scene.renderSceneTree(context: hidden) }
        // Its presenters held the backdrop's focus manager as a presentation
        // holds the live one: a modal one is still up behind the window in front.
        window.showsModalPresentation = backdrop.environment.focusManager?.activeSectionIsModal == true
    }

    /// Draws `window`, in front, over the whole surface.
    ///
    /// With another window open behind it, Escape closes it when nothing in it
    /// takes the key, as a pushed navigation screen's Escape goes back: a
    /// lightweight claim, named "close window" on the status bar, made after
    /// the window has drawn and only if nothing in it claimed the key, and a
    /// handler filed ahead of everything the window registers, so the
    /// window's own handlers are asked first. A window's content has no other
    /// way out a terminal can always reach: macOS gives every window a close
    /// button and ⌘W.
    private func renderFront(_ window: OpenWindow, scene: some Scene, context: RenderContext) -> FrameBuffer {
        guard let entry = entry(of: window) else { return FrameBuffer() }
        var context = self.context(for: window, entry: entry, from: context)
        // The `Settings` sheet and the alert scenes are presented over the
        // window in front.
        context.environment.sceneOverlays = overlays()
        if !context.isMeasuring, !window.isLaunchWindow {
            context.environment.focusManager?.registerSection(id: window.focusSection)
        }
        let escapeHandlerSlot = context.environment.keyEventDispatcher?.handlerCount ?? 0
        // Named before the window draws, for its status bar, which draws
        // before the claim below can be made; anything in the window that
        // claims Escape names it instead.
        if !context.isMeasuring, windows.count > 1, window.closesInteractively {
            context.environment.statusBar?.escapeFallbackLabel = Self.closeWindowLabel
        }
        let buffer = scene.renderSceneTree(context: context)
        // A window's first frame's seeding walk declares its dismiss behavior
        // as it declares its toolbar, so a window that cannot be closed never
        // offers Escape, even on the frame it opens.
        if !context.isMeasuring || context.environment.seedsWindowChrome {
            window.closesInteractively = window.chrome.dismissBehavior != .disabled
        }
        guard !context.isMeasuring else { return buffer }
        window.showsModalPresentation = context.environment.focusManager?.activeSectionIsModal == true
        // After the window: its content's own shortcut on a scene's key keeps it.
        if let registry = context.environment.keyboardShortcutRegistry {
            registerSceneShortcuts(in: registry, commandKey: context.environment.commandKey)
        }
        if windows.count > 1, window.closesInteractively {
            claimEscape(closing: window, at: escapeHandlerSlot, context: context)
        }
        return buffer
    }

    /// What the status bar calls Escape that closes a window.
    private static var closeWindowLabel: String {
        LocalizationService.shared.string(for: LocalizationKey.StatusBar.closeWindow)
    }

    /// Makes Escape close `window`, where nothing in it claimed the key and no
    /// presentation in it holds the keyboard.
    private func claimEscape(closing window: OpenWindow, at slot: Int, context: RenderContext) {
        let statusBar = context.environment.statusBar
        let focusManager = context.environment.focusManager
        guard statusBar?.hasEscapeClaimHere != true, focusManager?.activeSectionIsModal != true else { return }
        statusBar?.escapeLabelOverride = Self.closeWindowLabel
        statusBar?.escapeClaimGrabsInput = false
        let serial = window.serial
        context.environment.keyEventDispatcher?.insertHandler(
            at: slot, sectionID: context.environment.activeFocusSectionID
        ) { [weak self, weak focusManager] event in
            guard event.key == .escape, focusManager?.activePaneID == nil else { return false }
            self?.close([serial])
            return true
        }
    }
}
