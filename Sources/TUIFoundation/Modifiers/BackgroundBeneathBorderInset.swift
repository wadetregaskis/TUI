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
//  it clear.
//
//  `.backgroundStopsAtContent()` kept that inset clear when `.border()` had
//  one; it now reaches nothing an app can put inside chrome, and is kept only
//  until the owner rules on removing it (API baselines change at a release).
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

// MARK: - Keeping the inset clear

/// A view whose background stops at its content: not a
/// ``BackgroundBeneathBorderInset``, so a bordered box's inset around it stays
/// clear.
nonisolated struct _BackgroundStopsAtContent<Content: View>: View {
    let content: Content

    @MainActor var body: some View { content }
}

extension View {
    /// Keeps a border's inset around this view clear of its background.
    ///
    /// Until 2026-11-17 `.border()` drew a blank cell either side of what it
    /// bordered, and a background on the bordered view filled it; this kept
    /// it clear. `.border()` has no inset now — padding is the inset, as in
    /// SwiftUI — so this changes nothing: put the padding where the
    /// background should stop instead.
    ///
    /// ```swift
    /// Text("Draft")
    ///     .background(.yellow)
    ///     .padding(.horizontal, 1)   // clear: the background stops at the text
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
