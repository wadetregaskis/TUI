//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentationCornerRadius.swift
//
//  `presentationCornerRadius(_:)`: the corners of a sheet's box.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIFoundation
import TUIView

/// A view naming the corner radius of the sheet it is presented in, found
/// through any other presentation trait around it (`presentationTrait(_:of:)`).
@MainActor
protocol PresentationCornerRadiusProviding {
    /// The radius; `nil` for the appearance's corners.
    var cornerRadius: CGFloat? { get }
}

/// The wrapper `.presentationCornerRadius(_:)` produces. Renders and measures
/// as its content; carrying the radius to the presenter is its whole job.
nonisolated struct _PresentationCornerRadiusView<Content: View>: View, PresentationCornerRadiusProviding {
    let content: Content
    let cornerRadius: CGFloat?

    @MainActor var body: Never {
        fatalError("_PresentationCornerRadiusView renders via Renderable")
    }
}

@MainActor extension _PresentationCornerRadiusView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: context)
    }
}

@MainActor extension _PresentationCornerRadiusView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

@MainActor extension _PresentationCornerRadiusView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

extension View {
    /// Requests that the presentation have a specific corner radius — mirrors
    /// SwiftUI's `presentationCornerRadius(_:)`.
    ///
    /// Apply it to the presented content, as with ``View/presentationDetents(_:)``.
    /// A terminal sheet is its content's outermost box (a `Dialog`, a `Panel`, a
    /// `.border()`), and the radius reaches that box's corners as a shape's does
    /// in lines: zero is square, `┌`; any other radius is rounded, `╭`; `nil` is
    /// the appearance's. Only light lines have both corners — under a heavy,
    /// double, dotted or block appearance the box keeps its own. Decisions A24.
    ///
    /// ```swift
    /// .sheet(isPresented: $showSettings) {
    ///     SettingsView()
    ///         .presentationDetents([.medium, .large])
    ///         .presentationCornerRadius(0)
    /// }
    /// ```
    ///
    /// - Parameter cornerRadius: The corner radius, or `nil` to use the system
    ///   default.
    /// - Returns: The content, carrying the radius to its presentation.
    nonisolated public func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View {
        _PresentationCornerRadiusView(content: self, cornerRadius: cornerRadius)
    }
}
