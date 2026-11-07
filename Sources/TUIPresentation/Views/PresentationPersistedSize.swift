//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentationPersistedSize.swift
//
//  `presentationPersistedSize(width:height:onResize:)`: persisted size and resize callback for sheets.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUIView

/// A view specifying persisted dimensions and a resize callback for a presented dialog,
/// found through presentation traits (`presentationTrait(_:of:)`).
@MainActor
package protocol PresentationPersistedSizeProviding {
    var persistedWidth: Int? { get }
    var persistedHeight: Int? { get }
    var onResize: ((Int?, Int?) -> Void)? { get }
}

package struct _PresentationPersistedSizeView<Content: View>: View, PresentationPersistedSizeProviding {
    package let content: Content
    package let persistedWidth: Int?
    package let persistedHeight: Int?
    package let onResize: ((Int?, Int?) -> Void)?

    package init(content: Content, width: Int?, height: Int?, onResize: ((Int?, Int?) -> Void)?) {
        self.content = content
        self.persistedWidth = width
        self.persistedHeight = height
        self.onResize = onResize
    }

    @MainActor package var body: Never {
        fatalError("_PresentationPersistedSizeView renders via Renderable")
    }
}

@MainActor extension _PresentationPersistedSizeView: Renderable {
    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: context)
    }
}

@MainActor extension _PresentationPersistedSizeView: Layoutable {
    package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

@MainActor extension _PresentationPersistedSizeView: PresentationTraitWrapper {
    package var presentationTraitContent: any View { content }
}

@MainActor extension _PresentationPersistedSizeView: SingleContentWrapper {
    package var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    package func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

@MainActor extension _PresentationPersistedSizeView: DrawsContentUnchanged {}

extension View {
    /// Carries initial persisted dimensions and a resize callback to the presenter of a sheet.
    ///
    /// `onResize` hears the size the user left the sheet at, axis by axis: `nil`
    /// for one the user has never set, which is to be left unsaved.
    @MainActor
    package func presentationPersistedSize(
        width: Int?,
        height: Int?,
        onResize: ((Int?, Int?) -> Void)? = nil
    ) -> some View {
        _PresentationPersistedSizeView(content: self, width: width, height: height, onResize: onResize)
    }
}
