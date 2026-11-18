//  🖥️ TUI — A Terminal UI framework for Swift
//  BackgroundBeneathBorderInset.swift
//
//  A bordered box's inset takes the background of the view it borders. SwiftUI's
//  `.border()` is drawn inside the view's frame, over the edge of whatever is
//  there, so a background always reaches the line. TUI's cannot draw over
//  content (it would cover text), so its line goes round the content instead.
//  The framework's own bordered chrome (`Box`, a menu, a popover, a toast)
//  adds a blank cell either side of the content inside the line as well. That
//  inset exists only because of the box, so it belongs to the box, and a
//  background the content ends in fills it: a popover's surface reaches its
//  line, as SwiftUI's background does. The
//  owner's answer to GLASS-BORDER-GAP, option (a), 2026-10-27, where a
//  material stopped a cell short of a dialog's border and the photograph
//  behind showed through the gap.
//
//  An app's `.border()` has had no inset since 2026-11-17 (the owner: padding
//  is the inset, as in SwiftUI), so a background reaches its line already, and
//  the app says where its padding goes: `.padding(.horizontal, 1).background(m)`
//  before the border fills it, `.background(m).padding(.horizontal, 1)` leaves
//  it clear. (`.backgroundStopsAtContent()`, which kept `.border()`'s old
//  inset clear, went with that inset.)
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A view whose outermost layer paints a background behind the rest: the
/// framework's bordered chrome around it puts its inset beneath that
/// background, so the background reaches the line
/// (`BackgroundBeneathBorderInset.swift`).
protocol BackgroundBeneathBorderInset {
    /// This view with `insets` of padding between its content and its
    /// background.
    func paddingBeneathBackground(_ insets: EdgeInsets) -> AnyView
}

/// A buffer modifier that paints a background behind its content.
protocol PaintsBackground: BufferModifier {}

@MainActor extension BackgroundModifier: PaintsBackground {}

extension ModifiedView: BackgroundBeneathBorderInset where Modifier: PaintsBackground {
    func paddingBeneathBackground(_ insets: EdgeInsets) -> AnyView {
        AnyView(content.padding(insets).modifier(modifier))
    }
}

extension BackgroundLayerModifier: BackgroundBeneathBorderInset {
    func paddingBeneathBackground(_ insets: EdgeInsets) -> AnyView {
        func rewrapping<V: View>(_ padded: V) -> AnyView {
            AnyView(BackgroundLayerModifier<V, Background>(base: padded, background: background, alignment: alignment))
        }
        return rewrapping(base.padding(insets))
    }
}
