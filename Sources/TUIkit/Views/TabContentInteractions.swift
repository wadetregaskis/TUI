//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabContentInteractions.swift
//
//  What a tab does under the pointer and the keys besides selecting: a
//  context menu, a popover, a drag that carries it, and drops onto it — on a
//  strip's chip and on a sidebar's row alike.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - What a tab carries

/// A popover a tab presents, from `TabContent.popover(isPresented:…)` or
/// `TabContent.popover(item:…)`.
struct _TabPopover {
    let isPresented: Binding<Bool>
    /// The popover's content, or `nil` for the `item:` form with no item.
    let content: AnyView?
    let attachmentAnchor: PopoverAttachmentAnchor
    let arrowEdge: Edge?
    /// The identity key of the item the popover is about, for the `item:` form.
    let itemKey: String?
}

/// Everything a tab does besides being selected: what the tab content
/// modifiers below record on each tab.
struct _TabInteractionTraits {
    /// The context menu's items.
    var contextMenu: AnyView?
    /// The popovers the tab presents, innermost first.
    var popovers: [_TabPopover] = []
    /// What a drag that starts on the tab carries, evaluated when it starts.
    var dragPayload: (() -> Any?)?
    /// The drops the tab takes — the table rows' kind, which is the same thing.
    var drops: [_TableRowDrop] = []

    /// Whether the tab carries nothing of the kind.
    var isEmpty: Bool { contextMenu == nil && popovers.isEmpty && dragPayload == nil && drops.isEmpty }
}

// MARK: - The modifiers

extension TabContent {
    /// Adds a context menu to a tab.
    ///
    /// A right-click — or Ctrl-click, where the terminal keeps the right
    /// button for itself — on the tab opens it at the click, in a strip on the
    /// tab's chip and in a `.sidebarAdaptable` sidebar on its row; Shift+F10
    /// opens the selected tab's under it while the tab bar or the sidebar has
    /// the focus. Compose the menu from `Button`, `Toggle` and `Picker`, with
    /// `Menu` for a submenu and `Section` or `Divider` to group.
    ///
    /// - Parameter menuItems: A closure that produces the menu's contents. You
    ///   can deactivate the context menu by returning nothing from the closure.
    /// - Returns: A tab that can display a context menu.
    public func contextMenu<M: View>(@ViewBuilder menuItems: () -> M) -> some TabContent<TabValue> {
        let menu = AnyView(menuItems())
        // The modifier nearest the tab has already spoken.
        return _TabTraitContent(content: self) { tab in
            if tab.interactions.contextMenu == nil { tab.interactions.contextMenu = menu }
        }
    }

    /// Presents a popover from the tab when a given condition is true.
    ///
    /// The popover hangs from the tab's chip in a strip and from its row in a
    /// `.sidebarAdaptable` sidebar, as `View.popover(isPresented:…)` hangs from
    /// its view; Escape or a click outside it closes it.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the popover.
    ///   - attachmentAnchor: Where on the tab the popover attaches.
    ///   - arrowEdge: Which side of the tab the popover sits on; `nil`, below.
    ///   - content: A closure returning the content of the popover.
    /// - Returns: A tab that can present the popover.
    public func popover<Content: View>(
        isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil, @ViewBuilder content: @escaping () -> Content
    ) -> some TabContent<TabValue> {
        let popover = _TabPopover(
            isPresented: isPresented, content: AnyView(content()), attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge, itemKey: nil)
        return _TabTraitContent(content: self) { $0.interactions.popovers.append(popover) }
    }

    /// Presents a popover from the tab using the given item as a data source
    /// for the popover's content.
    ///
    /// As ``TabContent/popover(isPresented:attachmentAnchor:arrowEdge:content:)``,
    /// presented while `item` holds a value; closing it sets `item` to `nil`. A
    /// popover reopened for a different item starts with fresh state.
    ///
    /// - Parameters:
    ///   - item: A binding to an optional source of truth for the popover.
    ///   - attachmentAnchor: Where on the tab the popover attaches.
    ///   - arrowEdge: Which side of the tab the popover sits on; `nil`, below.
    ///   - content: A closure returning the content of the popover.
    /// - Returns: A tab that can present the popover.
    public func popover<Item: Identifiable, Content: View>(
        item: Binding<Item?>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some TabContent<TabValue> {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in if !presented { item.wrappedValue = nil } })
        let current = item.wrappedValue
        let popover = _TabPopover(
            isPresented: isPresented, content: current.map { AnyView(content($0)) },
            attachmentAnchor: attachmentAnchor, arrowEdge: arrowEdge, itemKey: current.map { identityKey($0.id) })
        return _TabTraitContent(content: self) { $0.interactions.popovers.append(popover) }
    }

    /// Activates this tab as the source of a drag and drop operation.
    ///
    /// Press the tab — its chip in a strip, its row in a `.sidebarAdaptable`
    /// sidebar — and move to begin the drag: the tab's title follows the
    /// pointer, and releasing over a destination that takes the payload
    /// delivers it. A press released without moving is a click, which selects
    /// the tab as ever. SwiftUI drags a tab only from a sidebar; a terminal tab
    /// strip is the same row of tabs drawn across rather than down.
    ///
    /// As for every TUIkit drag, the payload needs no `Transferable`
    /// conformance — the drag never leaves the app.
    ///
    /// - Parameter payload: The value the drag carries, evaluated when the drag
    ///   begins.
    /// - Returns: A tab that can be dragged.
    public func draggable<T>(_ payload: @autoclosure @escaping () -> T) -> some TabContent<TabValue> {
        // `Any?`, so a payload that is an optional holding nothing starts no
        // drag.
        let carried: () -> Any? = { payload() as Any? }
        return _TabTraitContent(content: self) { tab in
            if tab.interactions.dragPayload == nil { tab.interactions.dragPayload = carried }
        }
    }

    /// Defines the tab as the destination of a drag and drop operation that
    /// handles the dropped content with a closure that you specify.
    ///
    /// The tab's chip or sidebar row is the target: while a drag carrying a
    /// payload of `payloadType` is over it, its label lifts as under the
    /// pointer, and releasing there hands `action` the dropped values. A drag
    /// held still over the tab also selects it (see
    /// ``TabContent/springLoadingBehavior(_:)``), so the drop can reach the
    /// tab's content instead.
    ///
    /// - Parameters:
    ///   - payloadType: The type of objects you want the tab to receive.
    ///   - action: A closure that takes the dropped content.
    /// - Returns: A tab that takes drops.
    public func dropDestination<T>(
        for payloadType: T.Type = T.self, action: @escaping ([T]) -> Void
    ) -> some TabContent<TabValue> {
        let drop = _TableRowDrop(accepts: { $0 is T }, perform: { action($0.compactMap { $0 as? T }) })
        return _TabTraitContent(content: self) { $0.interactions.drops.append(drop) }
    }
}

// MARK: - The host

/// The filing of a tab's menu opener, shared by the live render and by a memo
/// replaying it — see `EffectJournal`.
@MainActor
private enum TabMenuOpenerRegistrar {
    /// The journal kind of the filing.
    static let kind = EffectJournal.Kind("tabMenu.opener")

    /// Files, in `openers`, what opens the menu kept in `stateBox` from the
    /// keyboard, under the tab's `value`.
    static func file(
        stateBox: StateBox<ContextMenuState>, onOpen: MenuOpenAction?, value: AnyHashable,
        into openers: _TabMenuOpeners?
    ) {
        openers?.file({ ContextMenuPresentation.openFromKeyboard(stateBox, onOpen: onOpen) }, for: value)
    }
}

/// `StateStorage` property indices for ``_TabInteractionsHost``. Lifted out of
/// the generic struct because Swift does not allow static stored properties in
/// generic types. From 0: the host renders its content at child identities.
private enum TabInteractionsStateIndex {
    static let menu = 0
}

/// One tab's interactions, over `content` — its sidebar row's label, or a
/// strip chip's footprint (``_TabChipFootprint``), whose regions and overlays
/// the strip moves onto the chip.
///
/// A context menu opens and draws as `.contextMenu`'s does
/// (``ContextMenuPresentation``) but registers no focus stop of its own: the
/// tab is reached by the strip's or the sidebar's, whose Shift+F10 opens it
/// through ``_TabMenuOpeners``. Its popovers are `View.popover`'s, around the
/// content. A drag handle and a drop zone cover the whole content.
struct _TabInteractionsHost<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let traits: _TabInteractionTraits
    /// The tab's value, which the openers file its menu under.
    let value: AnyHashable
    /// The tab's title, which a drag carries as its picture.
    let title: String
    /// Where the menu's opener is filed: the strip's, or `nil` for the
    /// sidebar's, which ``_TabSidebarMenuKeys`` puts in the environment.
    var openers: _TabMenuOpeners?
    /// Told whether a drop the tab takes is over it.
    var setTargeted: (Bool) -> Void = { _ in }

    private typealias StateIndex = TabInteractionsStateIndex

    var body: Never { fatalError("_TabInteractionsHost renders via Renderable") }

    /// The content with the tab's popovers around it, innermost first.
    private var presented: AnyView {
        traits.popovers.reduce(AnyView(content)) { view, popover in
            AnyView(
                PopoverPresentationModifier(
                    content: view, isPresented: popover.isPresented, popover: popover.content ?? AnyView(EmptyView()),
                    attachmentAnchor: popover.attachmentAnchor, arrowEdge: popover.arrowEdge ?? .bottom,
                    itemKey: popover.itemKey))
        }
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context.withChildIdentity(type: Content.self, index: 0))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let contentContext = context.withChildIdentity(type: Content.self, index: 0)
        guard !context.isMeasuring, context.environment.isEnabled, let storage = context.stateStorage else {
            return TUIkit.renderToBuffer(presented, context: contentContext)
        }
        // Nothing declared here: what the host registers a memo makes again
        // (the regions and drop target, its journals; the menu's opener, the
        // entry `attachMenu` records), and the one thing it cannot — tearing
        // down the section a closed menu left — declares itself on the one
        // frame it happens, as `.contextMenu`'s does (740df15af). So a row
        // carrying a tab's menu, drag or drops can be served from its memo.
        var buffer = TUIkit.renderToBuffer(presented, context: contentContext)
        // The drag handle first: it takes the regions already there as the
        // content's own, forwarding an unmoved click to them — and a click
        // nothing in the content wants falls through to the tab behind. The
        // menu's trigger, added after, is the tab's, not the content's, and
        // goes behind the handle.
        attachDrag(to: &buffer, context: context)
        if let menu = traits.contextMenu {
            attachMenu(menu, to: &buffer, storage: storage, context: context)
        }
        attachDrop(to: &buffer, context: context)
        return buffer
    }

    /// The tab's context menu over `buffer`: its trigger while closed, the menu
    /// while open.
    private func attachMenu(
        _ menu: AnyView, to buffer: inout FrameBuffer, storage: StateStorage, context: RenderContext
    ) {
        storage.markActive(context.identity)
        let stateBox: StateBox<ContextMenuState> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.menu),
            default: ContextMenuState())
        let state = stateBox.value
        fileOpener(for: stateBox, context: context)

        guard state.isOpen else {
            // The one effect no memo makes again, so declared — on the one
            // frame there is a section to tear down.
            if state.needsSectionTeardown {
                context.environment.volatileReadTracker?.recordRenderSideEffect()
                context.environment.focusManager?.deactivateSection(id: "tabmenu-\(context.identity.path)")
                state.needsSectionTeardown = false
            }
            ContextMenuPresentation.attachTrigger(to: &buffer, stateBox: stateBox, focusID: nil, context: context)
            return
        }
        state.needsSectionTeardown = true
        ContextMenuPresentation.present(
            menu, over: &buffer, stateBox: stateBox, sectionID: "tabmenu-\(context.identity.path)",
            context: context)
    }

    /// Files the menu's opener where the strip's or the sidebar's Shift+F10
    /// finds it — and, while a memo records, the entry that files it again
    /// when the memo is served. The openers are emptied on every render of
    /// whoever owns them (``_TabMenuOpeners``), so a served row that did not
    /// file its opener again would have a menu Shift+F10 could not open.
    ///
    /// A row whose value is the same as the last frame's is served, and the
    /// entry is then the one thing that files its opener:
    /// `TabInteractionsMemoTests.keyboardOnAServedRow` serves every row of
    /// the sidebar's parts composed over such rows, and Shift+F10 opened
    /// nothing without it. A tab view's own sidebar rows are not served
    /// across frames today (decisions D2C, found on the way: each is drawn at
    /// two sizes a frame, and each tab's menu is a new value every time the
    /// body that makes the tab view runs), so there it is belt and braces.
    private func fileOpener(for stateBox: StateBox<ContextMenuState>, context: RenderContext) {
        let onOpen = context.environment.menuOpenAction
        let value = self.value
        TabMenuOpenerRegistrar.file(
            stateBox: stateBox, onOpen: onOpen, value: value, into: openers ?? context.environment.tabMenuOpeners)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        // Looked up in the context the entry runs against, not captured: the
        // sidebar's openers, for a row served inside its list. A memo above a
        // tab view is served with the tab view, whose openers it did not
        // empty, so finding none there leaves what they hold.
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: TabMenuOpenerRegistrar.kind, channelToken: token) { replay in
                TabMenuOpenerRegistrar.file(
                    stateBox: stateBox, onOpen: onOpen, value: value, into: replay.environment.tabMenuOpeners)
            })
    }

    /// A drag handle over the content, carrying the tab's payload with its
    /// title as the picture. A press released without moving passes through
    /// as the click that selects the tab.
    private func attachDrag(to buffer: inout FrameBuffer, context: RenderContext) {
        guard let payload = traits.dragPayload, let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return }
        let preview = FrameBuffer(lines: [" \(title) "])
        let anchor = context.environment.dragPreviewAnchor
        _DragHandle.install(
            on: &buffer, context: context, dispatcher: dispatcher,
            onDragBegin: { _, grab in
                guard let value = payload() else { return }
                session.begin(payload: value, preview: preview, grabX: grab.x, grabY: grab.y, anchor: anchor)
            },
            onDragMove: { _ in session.dragMoved() },
            onDragEnd: { _ in _ = session.performDrop() })
    }

    /// A drop zone behind the content, handing the tab the drops it takes.
    private func attachDrop(to buffer: inout FrameBuffer, context: RenderContext) {
        let drops = traits.drops
        guard !drops.isEmpty else { return }
        DropZone.install(
            on: &buffer, context: context,
            accepts: { payload in drops.contains { $0.accepts(payload) } },
            perform: { payload, _ in
                for drop in drops where drop.accepts(payload) { drop.perform([payload]) }
                return true
            },
            setTargeted: setTargeted)
    }
}

/// A strip chip's footprint: nothing drawn, the chip's size. What a chip's
/// ``_TabInteractionsHost`` covers, so its regions and the popovers it hangs
/// land where the chip is once the strip moves them there.
struct _TabChipFootprint: View, Renderable, Layoutable {
    let width: Int
    let height: Int

    var body: Never { fatalError("_TabChipFootprint renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize.fixed(width, height)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(emptyWithWidth: width, height: height)
    }
}

// MARK: - On a strip's chips

extension _TabViewCore {
    /// Gives each chip whose tab carries interactions its own: the host over
    /// the chip's footprint, drawn at an identity of its own per tab, its
    /// regions and overlays moved onto the chip — in front of the chip's own
    /// click region, which a right-click and a click released unmoved fall
    /// through to. Their menus go where the strip's Shift+F10 finds them, on
    /// its handler.
    ///
    /// The pointer's hover goes to the front-most region alone, and none of
    /// the host's answers it, so in front of them all goes a region of the
    /// chip's own that answers hover and nothing else, lifting the chip as its
    /// click region does when nothing covers it. Without it a tab with a menu,
    /// a drag or a drop never lifted under the pointer. Every other event it
    /// declines, and a declined event goes on to the regions behind it — the
    /// host's, then the click region.
    ///
    /// An ordinary region, on the lane of the control under the pointer, as
    /// the click region is — NOT a hover observer
    /// (``MouseEventDispatcher/registerHoverObserver(in:_:)``): one observer
    /// is heard per point, the outermost, so an observer here went unheard
    /// wherever `.onHover` or `help(_:)` sat on the tab view or around it,
    /// and the chip did not lift while a plain tab beside it did.
    @MainActor
    func attachTabInteractions(
        to buffer: inout FrameBuffer,
        regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)],
        context: RenderContext
    ) {
        let handlerKey = StateStorage.StateKey(identity: context.identity, propertyIndex: TabViewStateIndex.handler)
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher,
            let handler = (context.stateStorage?.existingStorage(for: handlerKey) as StateBox<TabStripHandler>?)?.value
        else { return }
        let openers = handler.menuOpeners
        openers.beginFrame()
        let hoverBox = hoveredTabBox(context: context)
        for region in regions {
            let tab = tabs[region.index]
            guard !tab.interactions.isEmpty else { continue }
            let index = region.index
            let host = _TabInteractionsHost(
                content: _TabChipFootprint(width: region.width, height: region.height), traits: tab.interactions,
                value: tab.value, title: tab.title, openers: openers,
                setTargeted: { targeted in
                    if targeted {
                        hoverBox.value = index
                    } else if hoverBox.value == index {
                        hoverBox.value = nil
                    }
                })
            let hostContext = context.withChildIdentity(erasedType: _RawTab.self, key: "\(tab.value)")
            let hosted = TUIkit.renderToBuffer(host, context: hostContext)
            buffer.hitTestRegions += hosted.shiftedHitTestRegions(byX: region.x, y: region.y)
            buffer.overlays += hosted.shiftedOverlays(byX: region.x, y: region.y)
            let lift = dispatcher.register(in: hostContext) { event in
                Self.hover(event, overTab: index, hoverBox: hoverBox) ?? false
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: region.x, offsetY: region.y, width: region.width, height: region.height,
                    handlerID: lift, focusID: nil))
        }
    }

    /// What the pointer's motion over the chip of tab `index` does: lifts it on
    /// arriving, lets it down on leaving. `nil` for an event that is not
    /// motion, which is the caller's to handle.
    ///
    /// Shared by the chip's own region (`attachTabClicks`) and, for a chip
    /// whose tab carries interactions, the region in front of them that
    /// answers hover alone (``attachTabInteractions(to:regions:context:)``).
    static func hover(_ event: MouseEvent, overTab index: Int, hoverBox: StateBox<Int?>) -> Bool? {
        switch event.phase {
        case .entered, .moved:
            // Only a CHANGE means something: consuming every .moved
            // re-rendered the whole app once per motion drain for a
            // cursor travelling inside a tab it already lit.
            guard hoverBox.value != index else { return false }
            hoverBox.value = index
            return true
        case .exited:
            if hoverBox.value == index { hoverBox.value = nil }
            return true
        default:
            return nil
        }
    }
}
