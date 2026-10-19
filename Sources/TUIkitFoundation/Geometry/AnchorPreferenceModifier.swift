//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnchorPreferenceModifier.swift
//
//  `anchorPreference(key:value:transform:)` and
//  `transformAnchorPreference(key:value:transform:)`: a preference whose value
//  says where this view is, for a reader elsewhere to resolve.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Sets a value for the specified preference key, the value is a function
    /// of a geometry value tied to the current coordinate space, allowing
    /// readers of the value to convert the geometry to their local
    /// coordinates.
    ///
    /// ```swift
    /// Text("Selected")
    ///     .anchorPreference(key: SelectionKey.self, value: .bounds) { $0 }
    /// ```
    ///
    /// A reader converts the anchor with ``GeometryProxy/subscript(_:)`` — see
    /// ``Anchor`` for how a terminal resolves it.
    ///
    /// - Parameters:
    ///   - key: The preference key type.
    ///   - value: The geometry value in the current coordinate space.
    ///   - transform: The function to produce the preference value.
    /// - Returns: A new version of the view that writes the preference.
    public func anchorPreference<A, K: PreferenceKey>(
        key _: K.Type = K.self, value: Anchor<A>.Source, transform: @escaping (Anchor<A>) -> K.Value
    ) -> some View {
        AnchorPreferenceModifier(content: self, source: value, publish: .value { anchor, preferences in
            preferences.setValue(transform(anchor), forKey: K.self)
        })
    }

    /// Sets a value for the specified preference key, the value is a function
    /// of the key's current value and a geometry value tied to the current
    /// coordinate space, allowing readers of the value to convert the geometry
    /// to their local coordinates.
    ///
    /// As `transformPreference(_:_:)` does, the transform runs on the value
    /// this view's subtree reduced — the key's default when nothing in it set
    /// one — and its result is what the view's ancestors see.
    ///
    /// - Parameters:
    ///   - key: The preference key type.
    ///   - value: The geometry value in the current coordinate space.
    ///   - transform: The function to produce the preference value.
    /// - Returns: A new version of the view that writes the preference.
    public func transformAnchorPreference<A, K: PreferenceKey>(
        key _: K.Type = K.self, value: Anchor<A>.Source, transform: @escaping (inout K.Value, Anchor<A>) -> Void
    ) -> some View {
        AnchorPreferenceModifier(content: self, source: value, publish: .transform { anchor, values in
            var reduced = values[K.self]
            transform(&reduced, anchor)
            values[K.self] = reduced
        })
    }
}

// MARK: - Modifier

/// How an anchor preference reaches the preference storage.
enum AnchorPublish<Value> {
    /// Set before the content renders, as `preference(key:value:)` sets its
    /// value — so a reduction sees this view's value before its children's.
    case value((Anchor<Value>, PreferenceStorage) -> Void)
    /// Applied to what the content's subtree reduced, as
    /// `transformPreference(_:_:)` applies its transform.
    case transform((Anchor<Value>, inout PreferenceValues) -> Void)
}

/// Publishes an anchor to this view, and stamps the marker its readers find
/// it by — see ``View/anchorPreference(key:value:transform:)``.
struct AnchorPreferenceModifier<Content: View, Value>: View {
    let content: Content
    let source: Anchor<Value>.Source
    let publish: AnchorPublish<Value>

    var body: Never {
        fatalError("AnchorPreferenceModifier renders via Renderable")
    }
}

extension AnchorPreferenceModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A measure collects no preferences; and a write is a render-pass side
        // effect a cached buffer cannot reproduce — both as
        // `PreferenceModifier` has it.
        guard !context.isMeasuring, let preferences = context.environment.preferenceStorage else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        // Claimed before the content renders, as every marker slot is. With no
        // coordinator wired there is nothing to resolve against; the anchor
        // still exists, naming no view.
        let site = context.anchorSiteID()
        let anchor = Anchor<Value>(
            site: site ?? HitTestRegion.HandlerID(HitTestRegion.HandlerID.geometryMarkerBit),
            geometry: source.geometry)
        var buffer: FrameBuffer
        switch publish {
        case .value(let set):
            set(anchor, preferences)
            buffer = TUIkitView.renderToBuffer(content, context: context)
        case .transform(let transform):
            preferences.push()
            buffer = TUIkitView.renderToBuffer(content, context: context)
            preferences.pop { transform(anchor, &$0) }
        }
        if let site {
            buffer.hitTestRegions.append(.geometryMarker(site))
            context.geometryCoordinator?.registerAnchorSite(id: site, size: buffer.cellSize)
        }
        return buffer
    }
}

extension AnchorPreferenceModifier: Layoutable {
    /// Publishes a preference and renders `content` unchanged, so it measures
    /// as `content`.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// looks through this wrapper, as it looks through `preference(key:value:)`.
extension AnchorPreferenceModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension AnchorPreferenceModifier: DrawsContentUnchanged {}
/// Measures its content in the context it is given, so an alignment guide
/// inside it is asked through it — see `HandsContentItsContext`.
extension AnchorPreferenceModifier: HandsContentItsContext {}
