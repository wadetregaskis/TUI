//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Preferences.swift
//
//  Preferences system for bottom-up data flow (child → parent).
//  Similar to SwiftUI's PreferenceKey system.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Preference Modifier

/// A modifier that sets a preference value.
struct PreferenceModifier<Content: View, K: PreferenceKey>: View {
    /// The content view.
    let content: Content

    /// The preference value to set.
    let value: K.Value

    var body: Never {
        fatalError("PreferenceModifier renders via Renderable")
    }
}

extension PreferenceModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The write is a render-pass side effect, twice over:
        // - never during a measure pass (a measure-render of this subtree —
        //   e.g. under a render-to-measure ancestor — would apply an
        //   accumulating `reduce` a second time within the same frame);
        // - always declared to any value-memoizing ancestor: the preference
        //   stack is rebuilt every render pass, so a cached buffer would
        //   silently drop this value from the frame's collection.
        if !context.isMeasuring {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            context.environment.preferenceStorage!.setValue(value, forKey: K.self)
            if let line = Self.windowTitleLine { offerToWindowChrome(line, context: context) }
        } else if let line = Self.windowTitleLine, context.environment.seedsWindowChrome {
            // Except what the window's chrome reads, on the first frame's
            // seeding walk — a measurement whose one job is to find the chrome
            // (`EnvironmentValues.seedsWindowChrome`): the top bar's rows
            // depend on whether there is a title, and a subtitle under it.
            offerToWindowChrome(line, context: context)
        }

        // Render content
        return TUIkitView.renderToBuffer(content, context: context)
    }
}

extension PreferenceModifier {
    /// The line of the window's title slot `K` fills, if any: the
    /// navigation title or subtitle, which the window's chrome takes from the
    /// views that declare them.
    ///
    /// Decided by `K` alone, before anything is read from the environment:
    /// every `.preference(key:value:)` and every view that publishes one
    /// renders through here, every frame, and the window's chrome wants two
    /// keys of them. Asked in the other order, every one of them paid two
    /// environment lookups (each a dictionary probe and a cast from `Any`)
    /// and a dynamic cast of `K` to a protocol before finding out; now it is
    /// two comparisons of a metatype.
    private static var windowTitleLine: WindowChromeState.TitleLine? {
        if K.self == NavigationTitleKey.self { return .title }
        if K.self == NavigationSubtitleKey.self { return .subtitle }
        return nil
    }

    /// Offers a title or subtitle to the window's chrome, which shows the
    /// outermost one drawn (``WindowChromeState/offer(_:as:at:)``) —
    /// unless this is presented content: a sheet's title is the sheet's, and
    /// one in a sheet's content was the window's while the sheet was up.
    ///
    /// The window reads it here, as it is declared, rather than from the
    /// published preference, which keeps the LAST value and so the deepest
    /// view's. On the drawn walk and on the first frame's seeding walk, which
    /// measures: the top bar's rows are seeded from that walk, and they depend
    /// on whether there is a title, and a subtitle under it.
    private func offerToWindowChrome(_ line: WindowChromeState.TitleLine, context: RenderContext) {
        guard let chrome = context.environment.windowChrome,
            !context.environment.presentationHostsToolbar,
            let text = value as? String
        else { return }
        chrome.offer(text, as: line, at: context.identity)
    }
}

extension PreferenceModifier: Layoutable {
    /// Publishes a preference and renders `content` unchanged, so it measures as
    /// `content` (and the preference write stays a render-pass side-effect).
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - OnPreferenceChange Modifier

/// A modifier that reacts to preference changes.
struct OnPreferenceChangeModifier<Content: View, K: PreferenceKey>: View
where K.Value: Equatable {
    /// The content view.
    let content: Content

    /// The action to perform when the preference changes.
    let action: (K.Value) -> Void

    var body: Never {
        fatalError("OnPreferenceChangeModifier renders via Renderable")
    }
}

extension OnPreferenceChangeModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Pure passthrough during a measure pass: registering the callback and
        // invoking the action are render side effects (the action would fire
        // with a partial mid-measure collection).
        guard !context.isMeasuring else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        let prefs = context.environment.preferenceStorage!

        // The comparison and possible action below are per-frame side
        // effects a cached buffer cannot reproduce — decline the memos.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        // The baseline's slot, claimed BEFORE the content renders: the index is
        // positional, so one claimed afterwards counts the claimants the
        // CONTENT contributed at this same identity, and an `if` without `else`
        // (or an `AnyView`) changes that between frames — both render at the
        // parent identity. This observer would then land on a vanished
        // sibling's slot and read its value as its own previous preference.
        let storage = context.stateStorage!
        let index = storage.nextOnChangeIndex(for: context.identity)
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: index)

        // Push a new preference context
        prefs.push()

        // Render content
        let buffer = TUIkitView.renderToBuffer(content, context: context)

        // Pop and get collected preferences
        let preferences = prefs.pop()
        let value = preferences[K.self]

        // Fire only when the subtree's REDUCED value actually changed —
        // SwiftUI's contract (that is what the `Equatable` constraint is
        // for), and what keeps the render loop settled: the canonical action
        // writes `@State`, and firing unconditionally re-rendered every
        // frame forever. The baseline persists by view identity through the
        // same silent tracked-value store `onChange` uses (its claim counter
        // too, so chained observers at one identity keep distinct slots).
        // This also replaced a per-publisher storage callback that delivered
        // RAW un-reduced values — the action now only ever sees the final
        // reduction, once, like SwiftUI.
        let previous: K.Value? = storage.trackedValue(for: key)
        storage.setTrackedValue(value, for: key)
        storage.markActive(context.identity)
        if previous != value {
            action(value)
        }

        return buffer
    }
}

extension OnPreferenceChangeModifier: Layoutable {
    /// Renders `content` unchanged (it only collects/observes preferences), so it
    /// measures as `content`. Forwarding also keeps the push/pop and the change
    /// callback to the render pass — a measure must not fire preference actions.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Transform Preference Modifier

/// A modifier that rewrites the value of a preference its subtree reduced,
/// before its ancestors see it.
struct TransformPreferenceModifier<Content: View, K: PreferenceKey>: View {
    /// The content view.
    let content: Content

    /// Rewrites the subtree's value in place.
    let transform: (inout K.Value) -> Void

    var body: Never {
        fatalError("TransformPreferenceModifier renders via Renderable")
    }
}

extension TransformPreferenceModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A measure collects no preferences, so there is nothing to transform;
        // and the write below is a render-pass side effect that a cached
        // buffer cannot reproduce — both as `PreferenceModifier` has it.
        guard !context.isMeasuring else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let prefs = context.environment.preferenceStorage!

        prefs.push()
        let buffer = TUIkitView.renderToBuffer(content, context: context)
        // Measured in SwiftUI: the transform runs on the subtree's REDUCED
        // value — on the default when no child set one, whose result is then
        // set — and the result is what the parent receives.
        prefs.pop { values in
            var value = values[K.self]
            transform(&value)
            values[K.self] = value
        }
        return buffer
    }
}

extension TransformPreferenceModifier: Layoutable {
    /// Renders `content` unchanged, so it measures as `content`.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Common Preference Keys

/// A preference key for the navigation title.
public struct NavigationTitleKey: PreferenceKey {
    /// The default navigation title (empty string).
    public static let defaultValue: String = ""
}

/// A preference key for the navigation subtitle: what
/// `navigationSubtitle(_:)` publishes, read by a `NavigationStack` with the
/// title.
package struct NavigationSubtitleKey: PreferenceKey {
    package static let defaultValue: String = ""
}

/// A preference key for whether a pushed screen hides its Back control.
///
/// A preference rather than a static conformance — unlike a sheet's detent,
/// which decides the height it renders into, this is read AFTER the screen has
/// rendered, which is exactly when the navigation bar is built.
public struct NavigationBackButtonHiddenKey: PreferenceKey {
    /// Screens show their Back control unless they say otherwise.
    public static let defaultValue: Bool = false
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension PreferenceModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension PreferenceModifier: DrawsContentUnchanged {}
