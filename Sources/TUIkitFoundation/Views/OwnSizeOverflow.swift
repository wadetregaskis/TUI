//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OwnSizeOverflow.swift
//
//  Content drawn at its own size whatever it is offered — `.fixedSize()`, an
//  image at its natural size — larger than the frame, overlay or background
//  placing it, is drawn whole, placed by the region's alignment, the part
//  past the region drawn past it, as SwiftUI draws it (decisions B-GUIDE3-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// A view drawn at its own size whatever it is offered: `.fixedSize()`, and an
/// image at its natural size, which report a size larger than their offer and
/// mean it.
///
/// A `.frame`, an `.overlay` or a `.background` that places one larger than
/// its region offers it that size, so it comes back whole, places it by the
/// region's alignment, and draws what lies past the region past it, at the
/// view's place in the stacking order, as SwiftUI does (measured,
/// `Tools/SwiftUIProbes/Alignment guides/` GUIDE2 `g2c`: a 40-wide view in a
/// 20-wide `.frame(alignment: .center)` draws 10 past each side). Other
/// content larger than its region — a `Text` taller than a one-row frame,
/// which SwiftUI truncates — is cut to it, as before.
@MainActor
package protocol DrawsAtItsOwnSize {}

extension _FixedSizeView: DrawsAtItsOwnSize {}

extension Image: DrawsAtItsOwnSize {}

/// Whether views of `type` are drawn at their own size: they say so
/// (``DrawsAtItsOwnSize``), or the view a single-content wrapper of theirs
/// wraps is, or — a view of the app's own — its body is. A question of the
/// type, kept per type (`BodyWitnessMemo`), so a frame asks it for one table
/// read.
@MainActor
func drawsAtItsOwnSize<V: View>(_ type: V.Type) -> Bool {
    BodyWitnessMemo.answer(in: BodyWitnessMemo.ownSize, for: type) {
        if type is any DrawsAtItsOwnSize.Type { return true }
        if let wrapper = type as? any SingleContentWrapper.Type { return wrappedDrawsAtItsOwnSize(wrapper) }
        guard V.Body.self != Never.self, !(type is any Renderable.Type) else { return false }
        return drawsAtItsOwnSize(V.Body.self)
    }
}

/// ``drawsAtItsOwnSize(_:)`` of a wrapper's content, the existential opened.
@MainActor
private func wrappedDrawsAtItsOwnSize<W: SingleContentWrapper>(_: W.Type) -> Bool {
    drawsAtItsOwnSize(W.WrappedContent.self)
}

/// The size `content` draws at offered `width` × `height`, where it is drawn
/// at its own size (``DrawsAtItsOwnSize``) and that is larger on an axis — and
/// `nil` otherwise, the usual case, at the cost of a table read. On a render
/// only: a measure places nothing past a region.
@MainActor
func ownSizePastOffer<V: View>(
    of content: V, width: Int, height: Int, context: RenderContext
) -> (width: Int, height: Int)? {
    guard !context.isMeasuring, drawsAtItsOwnSize(V.self) else { return nil }
    let size = measureChild(content, proposal: ProposedSize(width: width, height: height), context: context)
    guard size.width > width || size.height > height else { return nil }
    return (width: max(width, size.width), height: max(height, size.height))
}

extension HorizontalAlignment {
    /// The leading offset at which a `childWidth`-wide view sits in a
    /// `totalWidth`-wide region so that its guide meets the region's, held to
    /// nothing: negative, or past the far edge, where the view is larger than
    /// the region — what a region that draws its content past it places it at.
    func offsetDrawingPast(childWidth: Int, in totalWidth: Int) -> Int {
        let region = ViewDimensions(width: totalWidth, height: 0)
        let child = ViewDimensions(width: childWidth, height: 0)
        return Int(clamping: (self[dimensions: region] - self[dimensions: child]).rounded(.down))
    }
}

extension VerticalAlignment {
    /// The vertical twin of ``HorizontalAlignment/offsetDrawingPast(childWidth:in:)``.
    func offsetDrawingPast(childHeight: Int, in totalHeight: Int) -> Int {
        let region = ViewDimensions(width: 0, height: totalHeight)
        let child = ViewDimensions(width: 0, height: childHeight)
        return Int(clamping: (self[dimensions: region] - self[dimensions: child]).rounded(.down))
    }
}
