//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BlendModeModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - blendMode

extension View {
    /// Sets how this view's colours combine with the colours behind it. Matches
    /// SwiftUI's `blendMode(_:)`.
    ///
    /// ```swift
    /// ZStack {
    ///     Text(logLine)
    ///     Color.yellow.blendMode(.multiply)   // a highlighter over the line
    /// }
    /// ```
    ///
    /// Composited as ``View/opacity(_:)`` is: this view renders as a layer, and
    /// where the layer is drawn onto what is behind it each cell's ink and field
    /// are combined with what is behind them, by the arithmetic macOS uses (see
    /// ``BlendMode``). With nothing behind, an arithmetic mode leaves the view as
    /// it is, as SwiftUI's does over a clear backdrop.
    ///
    /// > Note: A cell holds one character. Where this view draws no glyph over
    ///   text, the text keeps its character and its colours blend, so a
    ///   ``BlendMode/multiply`` highlight tints the letters; where both draw one,
    ///   this view's is drawn at or above half opacity, as under
    ///   ``View/opacity(_:)``, in the blended colour.
    ///
    /// - Parameter blendMode: How the colours combine.
    /// - Returns: A view composited with that mode over whatever it is drawn on.
    public func blendMode(_ blendMode: BlendMode) -> some View {
        _BlendModeView(content: self, blendMode: blendMode)
    }
}

/// Marks everything `content` draws with a blend mode, for the compositor to
/// resolve against what is behind it, as ``_OpacityView`` marks a fade.
package struct _BlendModeView<Content: View>: View {
    let content: Content
    let blendMode: BlendMode

    package var body: Never {
        fatalError("_BlendModeView renders via Renderable")
    }
}

extension _BlendModeView: Renderable {
    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkitView.renderToBuffer(content, context: context)
        guard blendMode != .normal, !buffer.isEmpty || !buffer.overlays.isEmpty else { return buffer }
        // One claim over the whole of what was drawn, AFTER the claims inside it:
        // the resolution takes each cell's layer from the first claim covering it,
        // and its mode from the first that names one, so a fade inside keeps its
        // alpha and takes this mode, and a mode inside keeps its own.
        buffer.opacityRegions = Self.marking(buffer.opacityRegions, wholeOf: buffer, with: blendMode)
        buffer.overlays = Self.markingOverlays(buffer.overlays, with: blendMode)
        return buffer
    }

    private static func marking(
        _ regions: [OpacityRegion], wholeOf buffer: FrameBuffer, with mode: BlendMode
    ) -> [OpacityRegion] {
        guard !buffer.isEmpty else { return regions }
        return regions + [
            OpacityRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.lines.count, opacity: 1,
                blendMode: mode)
        ]
    }

    /// The layers this view drew, displaced, marked as its lines are; the
    /// screen-level ones it merely hosts (a sheet, an alert) left alone, as
    /// `OpacityFading.fadingOverlays` leaves them.
    private static func markingOverlays(_ overlays: [OverlayLayer], with mode: BlendMode) -> [OverlayLayer] {
        overlays.map { layer in
            guard !layer.isScreenLevel else { return layer }
            var marked = layer
            marked.content.opacityRegions = marking(layer.content.opacityRegions, wholeOf: layer.content, with: mode)
            marked.content.overlays = markingOverlays(layer.content.overlays, with: mode)
            return marked
        }
    }
}

extension _BlendModeView: Layoutable {
    /// Blending rewrites colours in place: same characters, same cells, same size.
    package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper

extension _BlendModeView: ContentRewrapping {
    /// Its content's geometry is its own, as ``_OpacityView``'s is
    /// (``SingleContentWrapper/_keepsContentGeometry``).
    package static var _keepsContentGeometry: Bool { true }

    package var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    package func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }

    package func rewrapping<V: View>(_ view: V) -> any View {
        _BlendModeView<V>(content: view, blendMode: blendMode)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension _BlendModeView: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension _BlendModeView: GridRowProviding where Content: GridRowProviding {}
