//  🖥️ TUI — A Terminal UI framework for Swift
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
    /// it is, and the values TUI's own `draggable(_:)` carries that have a
    /// standard representation — a string, a URL — wrapped as SwiftUI wraps
    /// a `Transferable`, so an `onDrop` hears them too.
    package enum ItemProviders {
        static func of(_ payload: Any?) -> [NSItemProvider] {
            // A selection's values: each one's providers, in order.
            if let selection = payload as? DragItems { return selection.items.flatMap { of($0) } }
            switch payload {
            case let provider as NSItemProvider: return [provider]
            case let providers as [NSItemProvider]: return providers
            case let string as String: return [NSItemProvider(object: string as NSString)]
            case let url as URL: return [NSItemProvider(object: url as NSURL)]
            default: return []
            }
        }

        /// The providers of `payload` with an item conforming to one of `types`.
        package static func of(_ payload: Any?, conformingTo types: [UTType]) -> [NSItemProvider] {
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
    /// delegate's to carry out — a TUI drag never leaves the app. The drag's
    /// preview wears a badge naming the operation proposed now (see
    /// ``DropOperation``).
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
        /// The drag is within the app, as every TUI drag is: an
        /// ``onDrop(of:isTargeted:perform:)-(_,_,([NSItemProvider])->Bool)`` whose types the provider
        /// conforms to takes it.
        ///
        /// - Parameter data: Returns the provider, when the drag begins.
        /// - Returns: A view that can be dragged.
        nonisolated public func onDrag(_ data: @escaping () -> NSItemProvider) -> some View {
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
        nonisolated public func onDrag<V: View>(
            _ data: @escaping () -> NSItemProvider, @ViewBuilder preview: () -> V
        ) -> some View {
            DraggableModifier(content: self, payload: data, preview: AnyView(preview()))
        }

        /// Vends the item provider a drag of this view carries — SwiftUI's
        /// `itemProvider(_:)`, by which a row of a list says what dragging it
        /// takes along.
        ///
        /// The drag is within the app, as ``onDrag(_:)``'s is. A `nil` action,
        /// or one that vends `nil`, starts no drag.
        ///
        /// - Parameter action: Vends the provider when a drag begins.
        /// - Returns: A view whose drag carries the provider.
        nonisolated public func itemProvider(_ action: (() -> NSItemProvider?)?) -> some View {
            DraggableModifier(content: self, payload: { action?() }, preview: nil)
        }

        /// Makes this view a destination for drags carrying items of
        /// `supportedContentTypes` — SwiftUI's `onDrop(of:isTargeted:perform:)`.
        ///
        /// A drag from ``onDrag(_:)`` carries its provider; one from TUI's
        /// `draggable(_:)` with a string or a URL carries it as a provider of
        /// text or a URL. The view proposes ``DropOperation/copy``, so a drag
        /// over it wears the copy badge, `+`.
        ///
        /// From the keyboard, the view is a focus stop, as a
        /// `dropDestination` is: a drag carried there drops on Return, and
        /// Paste drops what was copied, as the providers a drag of it would
        /// carry, at the view's first cell.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the view takes.
        ///   - isTargeted: Set while a drag it would take is over the view.
        ///   - action: Performs the drop, given the conforming providers;
        ///     answers whether it took them.
        /// - Returns: A view that can receive drops.
        nonisolated public func onDrop(
            of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
            perform action: @escaping ([NSItemProvider]) -> Bool
        ) -> some View {
            onDrop(of: supportedContentTypes, isTargeted: isTargeted) { providers, _ in action(providers) }
        }

        /// Makes this view a destination for drags carrying items of
        /// `supportedContentTypes`, telling the action where the drop landed —
        /// SwiftUI's `onDrop(of:isTargeted:perform:)` with a location, a
        /// `CGPoint` as SwiftUI's is, measured in the view's own cells.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the view takes.
        ///   - isTargeted: Set while a drag it would take is over the view.
        ///   - action: Performs the drop, given the conforming providers and
        ///     the cell; answers whether it took them.
        /// - Returns: A view that can receive drops.
        nonisolated public func onDrop(
            of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
            perform action: @escaping ([NSItemProvider], CGPoint) -> Bool
        ) -> some View {
            ItemProviderDropModifier(
                content: self, supportedContentTypes: supportedContentTypes,
                handler: .perform(action, isTargeted: isTargeted))
        }

        /// Makes this view a destination for drags carrying items of
        /// `supportedContentTypes`, handled by `delegate` — SwiftUI's
        /// `onDrop(of:delegate:)`. See ``DropDelegate`` for the order of calls.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the view takes.
        ///   - delegate: Validates, follows and performs the drop.
        /// - Returns: A view that can receive drops.
        nonisolated public func onDrop(of supportedContentTypes: [UTType], delegate: any DropDelegate) -> some View {
            ItemProviderDropModifier(
                content: self, supportedContentTypes: supportedContentTypes, handler: .delegate(delegate))
        }
    }

    // MARK: - Delegate state

    /// `ItemProviderDropModifier`'s `StateStorage` slots, by name. A
    /// namespace of its own because a generic type cannot hold static stored
    /// properties.
    private enum ItemProviderDropStateIndex {
        // Negative: the modifier renders its content at its own identity, and
        // 0... belongs to a composite content view's own @State. Range -100 in
        // `StateStorage.StateKey`'s reserved-range table.
        /// Where ``View/onDrop(of:delegate:)`` keeps a drag's progress
        /// between frames.
        static let delegate = -100
        /// The focus id of its own stop, for a carry and Paste
        /// (`TransferKeys.ownStop`).
        static let ownStop = -101
    }

    /// One drag's progress over a delegate's view: kept across frames, since
    /// a drag outlives the frame its zone was registered in.
    final class DropDelegateState {
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

    /// What a drop does: kept as the caller gave it, and installed where the
    /// view draws, on the main actor.
    enum ItemProviderDropHandler {
        case perform(([NSItemProvider], CGPoint) -> Bool, isTargeted: Binding<Bool>?)
        case delegate(any DropDelegate)
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

        /// The operation the delegate proposes now, for the preview's badge:
        /// `nil` until it has validated the drag, and when it refused it.
        /// The delegate's proposal: `nil` while it proposes nothing (the
        /// session's own rule, a copy or a move, then decides), and a cancel
        /// where it refused the drag — a drop there is no drop, and wears no
        /// badge.
        func proposedOperation() -> DropOperation? {
            switch state.validated {
            case true?: state.operation
            case false?: .cancel
            case nil: nil
            }
        }

        func perform(_ payload: Any, _ info: DropInfo) -> Bool {
            if state.validated == nil { hovering(info) }
            guard state.validated == true, state.operation != .cancel, state.operation != .forbidden else {
                return false
            }
            state.dropped = true
            return delegate.performDrop(info: info)
        }

        /// A drop from Paste, which no drag came over first: the whole of a
        /// drop's calls in one go — validate, enter, update, perform — with
        /// nothing kept for the next.
        func pasted(_ payload: Any, _ info: DropInfo) -> Bool {
            state.reset()
            defer { state.reset() }
            return perform(payload, info)
        }
    }

    // MARK: - Modifier

    /// The view wrapper behind SwiftUI's `onDrop` forms: renders its content
    /// and registers its rectangle as a drop zone, as `install` says.
    nonisolated struct ItemProviderDropModifier<Content: View>: View {
        let content: Content
        let supportedContentTypes: [UTType]
        let handler: ItemProviderDropHandler

        @MainActor var body: Never {
            fatalError("ItemProviderDropModifier renders via Renderable")
        }
    }

    @MainActor extension ItemProviderDropModifier: Renderable, Layoutable {
        func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
            measureChild(content, proposal: proposal, context: context)
        }

        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            // The keyboard's way to drop here, as a `dropDestination`'s
            // (`TransferKeys`): a stop of the content's or one of its own,
            // where a carried drag can stop and Paste drops what was copied.
            let keys = TransferKeys.applies(in: context)
            let own =
                keys
                ? TransferKeys.ownStop(
                    prefix: "ondrop", propertyIndex: ItemProviderDropStateIndex.ownStop, context: context)
                : nil
            var contentContext = context
            if let own { FocusRegistration.publishIsFocused(own.isFocused, context: context, into: &contentContext) }
            var buffer = TUIView.renderToBuffer(content, context: contentContext)
            guard !context.isMeasuring else { return buffer }
            let stops = own.map { TransferKeys.stops(of: buffer, ownID: $0.id, context: context) } ?? []
            install(
                context, &buffer, focusIDs: stops, ownFocusID: own.flatMap { stops == [$0.id] ? $0.id : nil },
                unfocusableStop: TransferKeys.unfocusableStop(own: own?.id, stops: stops, context: context))
            return buffer
        }

        private func install(
            _ context: RenderContext, _ buffer: inout FrameBuffer, focusIDs stops: [String], ownFocusID: String?,
            unfocusableStop: String?
        ) {
            let supportedContentTypes = self.supportedContentTypes
            let accepts = { (payload: Any) in !ItemProviders.of(payload, conformingTo: supportedContentTypes).isEmpty }
            switch handler {
            case .perform(let action, let isTargeted):
                let perform = { (payload: Any, info: DropInfo) in
                    action(ItemProviders.of(payload, conformingTo: supportedContentTypes), info.location)
                }
                registerPaste(on: stops, context: context, accepts: accepts, perform: perform)
                DropZone.install(
                    on: &buffer, context: context, accepts: accepts, perform: perform,
                    setTargeted: { isTargeted?.wrappedValue = $0 },
                    // What SwiftUI's view without a delegate proposes.
                    proposedOperation: { .copy }, focusIDs: stops, ownFocusID: ownFocusID,
                    unfocusableStop: unfocusableStop)
            case .delegate(let delegate):
                guard let storage = context.stateStorage else { return }
                storage.markActive(context.identity)
                let state: StateBox<DropDelegateState> = storage.storage(
                    for: StateStorage.StateKey(
                        identity: context.identity, propertyIndex: ItemProviderDropStateIndex.delegate),
                    default: DropDelegateState())
                let session = DropDelegateSession(state: state.value, delegate: delegate)
                registerPaste(on: stops, context: context, accepts: accepts, perform: session.pasted)
                DropZone.install(
                    on: &buffer, context: context, accepts: accepts,
                    perform: session.perform,
                    setTargeted: session.setTargeted,
                    hoveringInfo: session.hovering,
                    proposedOperation: session.proposedOperation, focusIDs: stops, ownFocusID: ownFocusID,
                    unfocusableStop: unfocusableStop)
            }
        }

        /// Paste on one of `stops` drops what was copied, as it does on a
        /// `dropDestination`: the values this app copied, where the clipboard
        /// still holds their text, or else the text itself, each as the item
        /// provider a drag of it would carry, and only where one conforms to
        /// the view's types.
        private func registerPaste(
            on stops: [String], context: RenderContext, accepts: @escaping (Any) -> Bool,
            perform: @escaping (Any, DropInfo) -> Bool
        ) {
            guard !stops.isEmpty else { return }
            TransferKeys.register("v", focusIDs: stops, context: context) { event, clipboard in
                let text: String?
                if case .paste(let pasted) = event.key { text = pasted } else { text = clipboard.read() }
                guard let text, !text.isEmpty, let values = clipboard.paste(text, as: Any.self) else { return false }
                // Shaped as a drag of them is (`DragAndDropSession`'s
                // selection): one value as it is, several together.
                let payload: Any = values.count == 1 ? values[0] : DragItems(items: values)
                guard accepts(payload) else { return false }
                // Dropped from the keyboard, so at the view's first cell, with
                // no modifiers held and no preview.
                let info = DropInfo(
                    x: 0, y: 0, shift: false, ctrl: false, meta: false, previewX: 0, previewY: 0,
                    previewWidth: 0, previewHeight: 0, payload: DropPayload(payload))
                return perform(payload, info)
            }
        }
    }

    @MainActor extension ItemProviderDropModifier: SingleContentWrapper {
        var wrappedContent: Content { content }

        /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
        func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
    }

    @MainActor extension ItemProviderDropModifier: DrawsContentUnchanged {}
#endif
