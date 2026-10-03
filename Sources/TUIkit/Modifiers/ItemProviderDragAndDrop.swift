//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemProviderDragAndDrop.swift
//
//  SwiftUI's item-provider drag and drop: onDrag, onDrop and DropDelegate.
//  The payloads are NSItemProviders and the types UTTypes, which exist only
//  where UniformTypeIdentifiers does, so on Linux these are absent rather
//  than half there.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(UniformTypeIdentifiers)
    import Foundation
    import UniformTypeIdentifiers

    // MARK: - Item providers of a payload

    /// The item providers a drag's payload amounts to: an `onDrag` provider as
    /// it is, and the values TUIkit's own `draggable(_:)` carries that have a
    /// standard representation — a string, a URL — wrapped as SwiftUI wraps
    /// a `Transferable`, so an `onDrop` hears them too.
    enum ItemProviders {
        static func of(_ payload: Any?) -> [NSItemProvider] {
            switch payload {
            case let provider as NSItemProvider: return [provider]
            case let providers as [NSItemProvider]: return providers
            case let string as String: return [NSItemProvider(object: string as NSString)]
            case let url as URL: return [NSItemProvider(object: url as NSURL)]
            default: return []
            }
        }

        /// The providers of `payload` with an item conforming to one of `types`.
        static func of(_ payload: Any?, conformingTo types: [UTType]) -> [NSItemProvider] {
            of(payload).filter { provider in
                types.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
            }
        }
    }

    extension DropInfo {
        /// Whether at least one item the drag carries conforms to one of
        /// `contentTypes` — SwiftUI's `hasItemsConforming(to:)`.
        public func hasItemsConforming(to contentTypes: [UTType]) -> Bool {
            !ItemProviders.of(payload?.value, conformingTo: contentTypes).isEmpty
        }

        /// The item providers the drag carries that conform to one of
        /// `contentTypes` — SwiftUI's `itemProviders(for:)`.
        public func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] {
            ItemProviders.of(payload?.value, conformingTo: contentTypes)
        }
    }

    // MARK: - Drop delegate

    // Not class-only, as the rule would have a delegate protocol be: SwiftUI's
    // is not, and its delegates are routinely structs holding bindings. The
    // view holds the delegate for a frame, so there is no cycle to break with
    // a weak reference. Block form, so the doc comment stays on the protocol.
    // swiftlint:disable class_delegate_protocol
    /// The full interface to a drop on a view — SwiftUI's `DropDelegate`, for
    /// ``View/onDrop(of:delegate:)``.
    ///
    /// Called as SwiftUI calls it: ``validateDrop(info:)`` once a drag of a
    /// supported type comes over the view, then — if it said yes —
    /// ``dropEntered(info:)``, ``dropUpdated(info:)`` on every move, and
    /// ``dropExited(info:)`` or ``performDrop(info:)``. A proposal of
    /// ``DropOperation/cancel`` or ``DropOperation/forbidden`` refuses the drop
    /// (it never reaches ``performDrop(info:)``, and the drag goes home); any
    /// other operation accepts it, and what it means to the data is the
    /// delegate's to carry out — a TUIkit drag never leaves the app, and
    /// nothing at the pointer shows the operation.
    @MainActor
    public protocol DropDelegate {
        /// Whether the view will take this drop. Asked once, as the drag comes
        /// over it. Defaults to `true`.
        func validateDrop(info: DropInfo) -> Bool
        /// A validated drag came over the view. Does nothing by default.
        func dropEntered(info: DropInfo)
        /// A validated drag moved within the view. Return the operation a drop
        /// here would perform, or `nil` to keep the last (``DropOperation/copy``
        /// to begin with), which is the default.
        func dropUpdated(info: DropInfo) -> DropProposal?
        /// A validated drag left the view without dropping. Does nothing by
        /// default.
        func dropExited(info: DropInfo)
        /// Performs the drop; answers whether it succeeded.
        func performDrop(info: DropInfo) -> Bool
    }
    // swiftlint:enable class_delegate_protocol

    extension DropDelegate {
        /// Takes every drop of a supported type.
        public func validateDrop(info: DropInfo) -> Bool { true }
        /// Does nothing.
        public func dropEntered(info: DropInfo) {}
        /// Keeps the last proposal.
        public func dropUpdated(info: DropInfo) -> DropProposal? { nil }
        /// Does nothing.
        public func dropExited(info: DropInfo) {}
    }

    // MARK: - View modifiers

    extension View {
        /// Makes this view the source of a drag carrying the item provider
        /// `data` returns — SwiftUI's `onDrag(_:)`. The view's own picture
        /// follows the pointer.
        ///
        /// The drag is within the app, as every TUIkit drag is: an
        /// ``onDrop(of:isTargeted:perform:)`` whose types the provider
        /// conforms to takes it.
        ///
        /// - Parameter data: Returns the provider, when the drag begins.
        /// - Returns: A view that can be dragged.
        public func onDrag(_ data: @escaping () -> NSItemProvider) -> some View {
            DraggableModifier(content: self, payload: data, preview: nil)
        }

        /// Makes this view the source of a drag carrying the item provider
        /// `data` returns, with `preview` following the pointer — SwiftUI's
        /// `onDrag(_:preview:)`.
        ///
        /// - Parameters:
        ///   - data: Returns the provider, when the drag begins.
        ///   - preview: The picture that follows the pointer.
        /// - Returns: A view that can be dragged.
        public func onDrag<V: View>(
            _ data: @escaping () -> NSItemProvider, @ViewBuilder preview: () -> V
        ) -> some View {
            DraggableModifier(content: self, payload: data, preview: AnyView(preview()))
        }

        /// Makes this view a destination for drags carrying items of
        /// `supportedContentTypes` — SwiftUI's `onDrop(of:isTargeted:perform:)`.
        ///
        /// A drag from ``onDrag(_:)`` carries its provider; one from TUIkit's
        /// `draggable(_:)` with a string or a URL carries it as a provider of
        /// text or a URL.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the view takes.
        ///   - isTargeted: Set while a drag it would take is over the view.
        ///   - action: Performs the drop, given the conforming providers;
        ///     answers whether it took them.
        /// - Returns: A view that can receive drops.
        public func onDrop(
            of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
            perform action: @escaping ([NSItemProvider]) -> Bool
        ) -> some View {
            onDrop(of: supportedContentTypes, isTargeted: isTargeted) { providers, _ in action(providers) }
        }

        /// Makes this view a destination for drags carrying items of
        /// `supportedContentTypes`, telling the action where the drop landed —
        /// SwiftUI's `onDrop(of:isTargeted:perform:)` with a location, a
        /// ``CellPoint`` in the view's own cells where SwiftUI's is a `CGPoint`.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the view takes.
        ///   - isTargeted: Set while a drag it would take is over the view.
        ///   - action: Performs the drop, given the conforming providers and
        ///     the cell; answers whether it took them.
        /// - Returns: A view that can receive drops.
        public func onDrop(
            of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
            perform action: @escaping ([NSItemProvider], CellPoint) -> Bool
        ) -> some View {
            ItemProviderDropModifier(content: self) { context, buffer in
                DropZone.install(
                    on: &buffer, context: context,
                    accepts: { !ItemProviders.of($0, conformingTo: supportedContentTypes).isEmpty },
                    perform: { payload, info in
                        action(ItemProviders.of(payload, conformingTo: supportedContentTypes), info.location)
                    },
                    setTargeted: { isTargeted?.wrappedValue = $0 })
            }
        }

        /// Makes this view a destination for drags carrying items of
        /// `supportedContentTypes`, handled by `delegate` — SwiftUI's
        /// `onDrop(of:delegate:)`. See ``DropDelegate`` for the order of calls.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the view takes.
        ///   - delegate: Validates, follows and performs the drop.
        /// - Returns: A view that can receive drops.
        public func onDrop(of supportedContentTypes: [UTType], delegate: any DropDelegate) -> some View {
            ItemProviderDropModifier(content: self) { context, buffer in
                guard let storage = context.stateStorage else { return }
                storage.markActive(context.identity)
                let state: StateBox<DropDelegateState> = storage.storage(
                    for: StateStorage.StateKey(
                        identity: context.identity, propertyIndex: ItemProviderDropStateIndex.delegate),
                    default: DropDelegateState())
                let session = DropDelegateSession(state: state.value, delegate: delegate)
                DropZone.install(
                    on: &buffer, context: context,
                    accepts: { !ItemProviders.of($0, conformingTo: supportedContentTypes).isEmpty },
                    perform: session.perform,
                    setTargeted: session.setTargeted,
                    hoveringInfo: session.hovering)
            }
        }
    }

    // MARK: - Delegate state

    /// Where ``View/onDrop(of:delegate:)`` keeps a drag's progress between
    /// frames. A namespace of its own because a generic type cannot hold
    /// static stored properties.
    private enum ItemProviderDropStateIndex {
        // Negative: the modifier renders its content at its own identity, and
        // 0... belongs to a composite content view's own @State. See
        // `StateStorage.StateKey`'s reserved-range table.
        static let delegate = -100
    }

    /// One drag's progress over a delegate's view: kept across frames, since
    /// a drag outlives the frame its zone was registered in.
    final class DropDelegateState: @unchecked Sendable {
        /// What `validateDrop` answered for the drag now over the view, or
        /// `nil` before it has been asked.
        var validated: Bool?
        /// The operation last proposed.
        var operation = DropOperation.copy
        /// Where the drag last was over the view, for `dropExited`.
        var lastInfo: DropInfo?
        /// Whether the drag dropped here, so leaving afterwards is no exit.
        var dropped = false

        func reset() {
            validated = nil
            operation = .copy
            lastInfo = nil
            dropped = false
        }
    }

    /// The drop zone's callbacks for a delegate, in SwiftUI's order.
    @MainActor
    private struct DropDelegateSession {
        let state: DropDelegateState
        let delegate: any DropDelegate

        func setTargeted(_ targeted: Bool) {
            if !targeted, state.validated == true, !state.dropped, let info = state.lastInfo {
                delegate.dropExited(info: info)
            }
            state.reset()
        }

        func hovering(_ info: DropInfo) {
            state.lastInfo = info
            if state.validated == nil {
                let valid = delegate.validateDrop(info: info)
                state.validated = valid
                if valid { delegate.dropEntered(info: info) }
            }
            guard state.validated == true else { return }
            if let proposal = delegate.dropUpdated(info: info) { state.operation = proposal.operation }
        }

        func perform(_ payload: Any, _ info: DropInfo) -> Bool {
            if state.validated == nil { hovering(info) }
            guard state.validated == true, state.operation != .cancel, state.operation != .forbidden else {
                return false
            }
            state.dropped = true
            return delegate.performDrop(info: info)
        }
    }

    // MARK: - Modifier

    /// The view wrapper behind SwiftUI's `onDrop` forms: renders its content
    /// and registers its rectangle as a drop zone, as `install` says.
    struct ItemProviderDropModifier<Content: View>: View {
        let content: Content
        let install: @MainActor (RenderContext, inout FrameBuffer) -> Void

        var body: Never {
            fatalError("ItemProviderDropModifier renders via Renderable")
        }
    }

    extension ItemProviderDropModifier: Renderable, Layoutable {
        func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
            measureChild(content, proposal: proposal, context: context)
        }

        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            var buffer = TUIkit.renderToBuffer(content, context: context)
            guard !context.isMeasuring else { return buffer }
            install(context, &buffer)
            return buffer
        }
    }

    extension ItemProviderDropModifier: SingleContentWrapper {
        var wrappedContent: Content { content }
    }

    extension ItemProviderDropModifier: DrawsContentUnchanged {}
#endif
