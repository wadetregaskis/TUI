//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayScene.swift
//
//  The scenes presented over the window in front rather than as windows of
//  their own — a `Settings` scene's sheet, an alert scene — and the view that
//  presents them there.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Overlay Scenes

/// A scene the presenter shows over the window in front rather than as a
/// window of its own: TUIkitScenes' `Settings`, presented as a sheet, and
/// `AlertScene`, as an alert.
///
/// Opaque to this module, which cannot see the presentations they are drawn
/// with: each hands over the view that presents it — an empty view carrying
/// the presentation modifier — which the presenter draws beside the window's
/// content (``_SceneOverlayHost``), as a `.sheet` written on a view in the
/// page presents over the whole page.
package protocol OverlayScene: Scene {
    /// Whether ``EnvironmentValues/openSettings`` presents it: a `Settings`
    /// scene.
    var isSettings: Bool { get }

    /// The view that presents the scene, in `presenter`'s app: an empty view
    /// whose presentation modifier is bound to the presenter's state (the
    /// Settings sheet's) or the scene's own (an alert scene's binding).
    @MainActor
    func overlay(in presenter: ScenePresenter) -> AnyView
}

/// One overlay scene, as the presenter shows it this frame: its view and what
/// its modifiers state, keyed by its place in the body.
package struct SceneOverlay {
    /// The scene's place in the body: what its view's state is kept under.
    let key: String

    /// What the scene's modifiers state, applied to its view alone.
    let configuration: SceneConfiguration

    /// The view that presents it.
    let view: AnyView
}

/// The overlay scenes a window presents this frame, by reference: carried down
/// the scene tree to the window scene that draws them, and taken off there, so
/// no view's environment holds it.
@MainActor
final class SceneOverlayList: Equatable {
    let overlays: [SceneOverlay]

    init(_ overlays: [SceneOverlay]) {
        self.overlays = overlays
    }

    nonisolated static func == (lhs: SceneOverlayList, rhs: SceneOverlayList) -> Bool {
        lhs === rhs
    }
}

private struct SceneOverlaysKey: EnvironmentKey {
    static let defaultValue: SceneOverlayList? = nil
}

extension EnvironmentValues {
    /// The overlay scenes the window being drawn presents — the window in
    /// front's — or `nil`.
    var sceneOverlays: SceneOverlayList? {
        get { self[SceneOverlaysKey.self] }
        set { self[SceneOverlaysKey.self] = newValue }
    }
}

// MARK: - Presenting Them

/// The window's content with the overlay scenes' views drawn beside it: the
/// content at its own identity, as it is drawn with none, and each overlay's
/// view at an identity of its own under it, in the scene's own environment,
/// its presentation layers handed up with the content's for the window to
/// composite over its content area.
///
/// Beside the content rather than around it, so a scene's statements (an alert
/// scene's `.dialogSeverity`) reach its presentation and not the window, and
/// the content keeps its identity whether or not an overlay scene is declared.
/// A presentation that holds the keyboard isolates the content as one written
/// on a view in the page does: its focus section is active and marked modal,
/// it grabs the key dispatcher, and the compositor's dimming drops the page's
/// regions.
struct _SceneOverlayHost<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let overlays: [SceneOverlay]

    var body: Never { fatalError("_SceneOverlayHost renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkitView.renderToBuffer(content, context: context)
        guard !context.isMeasuring else { return buffer }
        for overlay in overlays {
            var overlayContext = context.withChildIdentity(erasedType: SceneOverlayMarker.self, key: overlay.key)
            overlay.configuration.applyRootOverrides(to: &overlayContext.environment)
            let presented = TUIkitView.renderToBuffer(overlay.view, context: overlayContext)
            buffer.overlays.append(contentsOf: presented.overlays)
        }
        return buffer
    }

    /// Transparent: it measures as its content, the overlays being presented
    /// over it.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// The type an overlay scene's view's identity is keyed under.
private enum SceneOverlayMarker {}
