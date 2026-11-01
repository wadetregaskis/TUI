//  🖥️ TUI — A Terminal UI framework for Swift
//  BackgroundBeneathBorderInset.swift
//
//  A border's inset takes the background of the view it borders. SwiftUI's
//  `.border()` is drawn inside the view's frame, over the edge of whatever is
//  there, so a background always reaches the line. TUI's cannot draw over
//  content (it would cover text), so it adds a ring of its own: a blank cell
//  either side of the content, then the line. That inset exists only because
//  of the border, so it belongs to the bordered box, and a background on the
//  content fills it: `.background(m).border()` draws `m` up to the line, as
//  SwiftUI does, and `.border().background(m)` beneath the line as well. The
//  owner's answer to GLASS-BORDER-GAP, option (a), 2026-10-27, where a
//  material stopped a cell short of a dialog's border and the photograph
//  behind showed through the gap.
//
//  `.backgroundStopsAtContent()` keeps the inset clear, for a border that
//  should stand apart from what it surrounds.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A view whose outermost layer paints a background behind the rest: a
/// border around it puts its inset beneath that background, so the background
/// reaches the line (`BackgroundBeneathBorderInset.swift`).
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

// MARK: - Keeping the inset clear

/// A view whose background stops at its content: not a
/// ``BackgroundBeneathBorderInset``, so a border's inset around it stays clear.
nonisolated public struct _BackgroundStopsAtContent<Content: View>: View {
    let content: Content

    @MainActor public var body: some View { content }
}

extension View {
    /// Keeps a border's inset around this view clear of its background.
    ///
    /// A border draws a blank cell either side of what it borders, so text
    /// does not run up against the line, and by default a background on the
    /// bordered view fills that inset too, reaching the line as SwiftUI's
    /// does. Say this between the two for a border that stands apart from
    /// what it surrounds:
    ///
    /// ```swift
    /// Text("Draft")
    ///     .background(.yellow)
    ///     .backgroundStopsAtContent()
    ///     .border()
    /// ```
    ///
    /// TUI-specific: SwiftUI's border is drawn over the view's edge, with no
    /// inset to fill.
    ///
    /// - Returns: A view whose background a border around it does not extend.
    nonisolated public func backgroundStopsAtContent() -> some View {
        _BackgroundStopsAtContent(content: self)
    }
}
