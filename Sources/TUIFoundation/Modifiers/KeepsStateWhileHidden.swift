//  🖥️ TUI — A Terminal UI framework for Swift
//  KeepsStateWhileHidden.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIView

extension View {
    /// Keeps the state of the views inside this one while they are not drawn —
    /// the page a `switch` left, the branch an `if` turned away from — for as
    /// long as this view itself is drawn, so that they come back as they were
    /// left: the text typed into a field, a toggle's setting, a list's
    /// selection and scroll.
    ///
    /// ```swift
    /// VStack {
    ///     switch page {
    ///     case .settings: SettingsPage()
    ///     case .notes: NotesPage()
    ///     }
    /// }
    /// .keepsStateWhileHidden()
    /// ```
    ///
    /// It keeps `@State`, `onChange` baselines and which branch a nested
    /// conditional was on, in memory, for the session; it persists nothing,
    /// which is `@AppStorage`'s and `@SceneStorage`'s business. Views still
    /// disappear and appear: their `onDisappear`, `onAppear` and `.task` run
    /// as they leave and come back. Every view ever drawn inside it is kept
    /// while it is drawn, so wrap the part of an app that comes and goes, not
    /// a list of thousands of generated views.
    ///
    /// TUI-specific: SwiftUI gives a view that is inserted again fresh state.
    /// A terminal app is often a set of pages one key away from each other,
    /// where losing what was typed on a page by visiting another is a surprise.
    ///
    /// - Parameter keeps: Whether the state is kept. `false` lets it go as
    ///   usual.
    /// - Returns: A view that keeps its hidden descendants' state.
    nonisolated public func keepsStateWhileHidden(_ keeps: Bool = true) -> some View {
        _HiddenStateKeeper(keeps: keeps, content: self)
    }
}

/// Declares its subtree retained on every frame it renders
/// (`StateStorage.retainSubtree`), as a `DisclosureGroup` does its collapsed
/// content's, so a branch that stops rendering below it is not pruned; and
/// tells the conditionals below not to drop the branch they turn away from
/// (``EnvironmentValues/keepsHiddenState``), which they otherwise do the
/// moment they flip.
nonisolated private struct _HiddenStateKeeper<Content: View>: View, Renderable, Layoutable {
    let keeps: Bool
    let content: Content

    @MainActor var body: Never {
        fatalError("_HiddenStateKeeper renders via Renderable")
    }

    @MainActor func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Render path only: a measure must not write persistent state, and the
        // declaration is per pass — the render that follows makes it. A memo
        // serving this subtree keeps its state as it is served.
        guard keeps else { return TUIView.renderToBuffer(content, context: context) }
        if !context.isMeasuring { context.stateStorage?.retainSubtree(context.identity) }
        // And a conditional below does not drop the branch it turns away
        // from, which it otherwise does the moment it flips.
        var inner = context
        inner.environment.keepsHiddenState = true
        return TUIView.renderToBuffer(content, context: inner)
    }

    /// Transparent: no chrome and no identity step, so it measures exactly as
    /// what it wraps.
    @MainActor func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard keeps else { return measureChild(content, proposal: proposal, context: context) }
        var inner = context
        inner.environment.keepsHiddenState = true
        return measureChild(content, proposal: proposal, context: inner)
    }
}
