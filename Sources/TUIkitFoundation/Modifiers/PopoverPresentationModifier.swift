//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PopoverPresentationModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - PopoverAttachmentAnchor

/// Where a popover attaches to the view presenting it — SwiftUI's type of the
/// same name.
public enum PopoverAttachmentAnchor: Sendable, Equatable {
    /// Attach to a rectangle of the presenting view: `.rect(.bounds)`, the
    /// default, is the view's own frame, and `.rect(.rect(_:))` a rectangle in
    /// its cells. The popover is centred along the rectangle's edge that
    /// `arrowEdge` names, and flips around the rectangle when there is no room.
    case rect(Anchor<CellRect>.Source)

    /// Attach at a point within the presenting view's frame.
    case point(UnitPoint)

    /// Two anchors attach a popover to the same place. Written out because
    /// `Anchor.Source` is not `Equatable` — SwiftUI's is not.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.rect(let left), .rect(let right)): left.geometry == right.geometry
        case (.point(let left), .point(let right)): left == right
        default: false
        }
    }
}

// MARK: - popover(…)

// `View.popover(isPresented:…)` and `popover(item:…)` are declared in
// TUIkitPresentation (`View+Popover.swift`), beside the sheet and the cover a
// popover adapts to in a compact size class (decisions A21).

// MARK: - Modifier

/// Presents `popover` as a bordered panel anchored to `content`.
package struct PopoverPresentationModifier<Content: View, Popover: View>: View {
    let content: Content
    let isPresented: Binding<Bool>
    let popover: Popover
    let attachmentAnchor: PopoverAttachmentAnchor
    let arrowEdge: Edge

    /// The identity key of the item this popover is ABOUT, or `nil` for the
    /// `isPresented:` form. See ``ModalPresentationModifier/itemKey``: the two
    /// presenters key their presented content on exactly the same terms.
    var itemKey: String?

    /// Whether `isPresented` is state the presenter owns: a `@State` of the
    /// view whose body this popover is, so that every change to it reaches
    /// every memo holding the popover — they are that view's ancestors.
    ///
    /// Then a closed frame declares a render side effect only when it has a
    /// section to tear down — the first after the popover was up — as
    /// `.contextMenu`'s does, and the closed popover costs a memo above it
    /// nothing. `View.popover` leaves this off: an app's binding may be state
    /// anywhere, and a row memo keyed by its element cannot see such state
    /// change (a ForEach row capturing it), so a closed frame stored and
    /// served there would never show the popover. Every closed frame of such
    /// a popover declares, which keeps it out of every memo.
    var ownsPresentation = false

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitTabs makes these, for a tab's popovers, and
    /// TUIkitPickers, for a date picker's calendar.
    package init(
        content: Content,
        isPresented: Binding<Bool>,
        popover: Popover,
        attachmentAnchor: PopoverAttachmentAnchor,
        arrowEdge: Edge,
        itemKey: String? = nil,
        ownsPresentation: Bool = false
    ) {
        self.content = content
        self.isPresented = isPresented
        self.popover = popover
        self.attachmentAnchor = attachmentAnchor
        self.arrowEdge = arrowEdge
        self.itemKey = itemKey
        self.ownsPresentation = ownsPresentation
    }

    package var body: Never {
        fatalError("PopoverPresentationModifier renders via Renderable")
    }
}

extension PopoverPresentationModifier: Renderable {
    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let contentContext = context.withChildIdentity(type: Content.self, index: 0)

        guard isPresented.wrappedValue else {
            if !context.isMeasuring { tearDownIfPresented(context: context) }
            return TUIkitView.renderToBuffer(content, context: contentContext)
        }
        let sectionID = Self.sectionID(context)

        var baseBuffer = TUIkitView.renderToBuffer(content, context: contentContext)
        guard !context.isMeasuring, context.environment.mouseEventDispatcher != nil else {
            return baseBuffer
        }

        // Presentation is a per-frame render side effect: a memoized replay
        // would skip the section registration and leave a popover that no
        // longer holds the keyboard.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let isPresented = self.isPresented
        // Content that forbade interactive dismissal keeps Escape and the
        // outside click from closing it — the presenter's two gestures, and
        // SwiftUI's swipe-down in terminal form. A `Done` button inside, or
        // `@Environment(\.dismiss)`, still works; that is the point.
        let dismissIsDisabled =
            presentationTrait(InteractiveDismissDisabling.self, of: popover)?
            .interactiveDismissIsDisabled ?? false
        // Through the gate, so content with a `dismissalConfirmationDialog` can
        // ask first — see `presentationDismissalGate(context:propertyIndex:)`.
        let gate = presentationDismissalGate(context: context, propertyIndex: StateIndex.dismissalGate)
        // A manual box at this identity, which nothing else hydrates: marked
        // so the end of the pass does not prune it and hand the content a new
        // gate — a new environment value — every frame.
        context.stateStorage?.markActive(context.identity)
        if ownsPresentation, let storage = context.stateStorage {
            storage.storage(for: Self.teardownKey(context), default: PopoverTeardown()).value.isPending = true
        }
        let dismiss = {
            guard !dismissIsDisabled else { return }
            gate.dismiss { isPresented.wrappedValue = false }
        }

        let focusManager = context.environment.focusManager
        focusManager?.registerSection(id: sectionID)
        // As a PRESENTED section: a sheet or menu opened from a control in the
        // popover holds the active section on top of it, and plain activation
        // took it back from that surface on every frame — see
        // `FocusManager.activatePresentedSection(id:)`.
        focusManager?.activatePresentedSection(id: sectionID)
        // Input-grabbing, so the app's chrome hotkeys don't fire behind it.
        focusManager?.markSectionModal(id: sectionID)
        // A popover holds arbitrary content, which may be entirely
        // non-focusable (a paragraph of text). Without this the end of the
        // render pass would hand the focus to whatever it could find — outside
        // the popover.
        focusManager?.markSectionFocusOptional(id: sectionID)
        context.environment.keyEventDispatcher!.grabInput(sectionID: sectionID)
        if presentationPreventsTermination(of: popover) {
            context.environment.statusBar?.preventQuit()
        }
        // The popover's name for its Escape, until the content has drawn
        // (below): a claim, whose token names it as the popover's own.
        var escapeClaim: Int?
        if !dismissIsDisabled {
            escapeClaim = context.environment.statusBar?.claimEscape(gate.escapeLabel(dismissal: .closePopover))
            context.environment.keyEventDispatcher!.addHandler(sectionID: sectionID) { event in
                guard event.key == .escape else { return false }
                // The content's cancel button where it drew one, as on macOS
                // (`DismissalGate.escape`); an outside click still dismisses.
                gate.escape(isRepeat: event.phase == .repeat) { isPresented.wrappedValue = false }
                return true
            }
        }

        // Keyed by the item, for the `item:` form — so a popover reopened for a
        // different row is a different view, with its own `@State`. See
        // ``ModalPresentationModifier``'s own keying for the whole reasoning.
        var popoverContext =
            (itemKey.map { context.withChildIdentity(erasedType: Popover.self, key: $0) }
            ?? context.withChildIdentity(type: Popover.self, index: 1))
            .withAvailableWidth(context.environment.terminalWidth)
            .withAvailableHeight(context.environment.overlayContentHeight)
        popoverContext.environment.activeFocusSectionID = sectionID
        // Its `.toolbar`s draw their items themselves, in the popover: the
        // window's bars are inert while it is up.
        popoverContext.environment.presentationHostsToolbar = true
        // It holds the keyboard, so a sheet presented from it is a modal
        // (`LiveSheet.dock`).
        popoverContext.environment.isInModalPresentation = true
        popoverContext.leaveScrollCanvas()
        popoverContext.environment.leaveUnstatedTextAlignment()
        // `@Environment(\.dismiss)` inside the popover closes the POPOVER — the
        // same act as its Escape handler above. Left unset it would mean the
        // top-level dismissal, which is to quit the application.
        popoverContext.environment.isPresented = true
        popoverContext.environment.dismiss = DismissAction {
            isPresented.wrappedValue = false
        }
        popoverContext.environment.dismissalGate = gate

        var panel = gate.drawingContent(context: context) {
            renderPresentedDialog(
                panelView(context: context), context: popoverContext,
                capHeight: context.environment.overlayContentHeight)
        }
        // Named for what Escape does, now the content has drawn: "cancel"
        // where it presses the content's cancel button, which may keep the
        // popover up. Unless the content claimed Escape for itself, whose
        // name stands — told by the claim's token, not its label: a popover
        // presented inside this one claims with the same "close popover".
        if let escapeClaim, gate.escapePressesCancelButton {
            context.environment.statusBar?.renameEscapeClaim(
                escapeClaim, to: gate.escapeLabel(dismissal: .closePopover))
        }
        guard !panel.isEmpty else { return baseBuffer }

        // The same screen-covering backdrop every menu presentation uses: a
        // click outside closes it, and the wheel still reaches the page. With
        // dismissal disabled the backdrop is still attached and `dismiss` is
        // the no-op above — so the click is SWALLOWED rather than passed
        // through. Letting it reach the page would be the opposite of what was
        // asked: the popover stays up and something behind it acts on a click
        // aimed at closing it.
        DropdownMenu.attachDismissBackdrop(to: &panel, context: context, onDismiss: dismiss)

        let placement = placement(
            panel: (width: panel.width, height: panel.height),
            over: (width: baseBuffer.width, height: baseBuffer.height))
        baseBuffer.overlays.append(
            OverlayLayer(
                offsetX: placement.x, offsetY: placement.y, content: panel,
                level: .popover, anchorHeight: placement.anchorHeight, holdsInput: true))
        return baseBuffer
    }

    /// The section a presented popover's content is in. Distinct per
    /// instance, like every other presented surface's section (`modal-`,
    /// `alert-`, `contextmenu-`), so two popovers in one frame cannot share a
    /// section and steal each other's focus.
    private static func sectionID(_ context: RenderContext) -> String {
        "popover-\(context.identity.path)"
    }

    /// Where an ``ownsPresentation`` popover notes it has a section to tear
    /// down.
    private static func teardownKey(_ context: RenderContext) -> StateStorage.StateKey {
        StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.teardown)
    }

    /// On a closed frame, tears down the section the popover left if it was
    /// just up — reverting the focus to the page's section and restoring its
    /// remembered focus — and declares that, a render side effect.
    ///
    /// A popover whose presentation is the app's binding cannot tell it was
    /// just up, so it does both on every closed frame (the deactivation is a
    /// no-op once the section is gone); one that owns its presentation knows,
    /// and does them once (``ownsPresentation``).
    private func tearDownIfPresented(context: RenderContext) {
        if ownsPresentation {
            guard
                let teardown = (context.stateStorage?.existingStorage(for: Self.teardownKey(context))
                    as StateBox<PopoverTeardown>?)?.value,
                teardown.isPending
            else { return }
            teardown.isPending = false
        }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        context.environment.focusManager?.deactivateSection(id: Self.sectionID(context))
    }

    /// The popover's content in its panel: a border and a cell of breathing
    /// room, over the app background so the page cannot show through the gaps
    /// between what the content draws — the same opaque fill the drop-down
    /// menus rely on.
    ///
    /// A `presentationBackground` the content named takes the place of the
    /// page's background, filling the same panel.
    @ViewBuilder
    private func panelView(context: RenderContext) -> some View {
        let padded = popover.padding(EdgeInsets(horizontal: 1, vertical: 0))
        if let background = withPresentationBackground(padded, from: popover) {
            background.border(context.environment.palette.border)
        } else {
            padded
                .background(context.environment.palette.background)
                .border(context.environment.palette.border)
        }
    }

    /// Where the panel goes in the presenting view's own coordinate space.
    ///
    /// `anchorHeight` is what the compositor flips around when there is no room
    /// below, and what an enclosing `ScrollView` culls against — understating it
    /// lands the popover on the control that opened it, or throws it away
    /// entirely. See ``OverlayLayer/anchorHeight``.
    private func placement(
        panel: (width: Int, height: Int), over base: (width: Int, height: Int)
    ) -> (x: Int, y: Int, anchorHeight: Int) {
        // The rectangle the popover attaches to, in the presenting view's
        // cells, and the point on it the popover lines up with. A unit point
        // resolves against the presenting view once, floored once: the
        // layout-parity rule, since a fraction of an extent is the one place a
        // fractional value belongs.
        let area: CellRect
        let point: (x: Int, y: Int)
        switch attachmentAnchor {
        case .rect(let source):
            area = source.value(origin: CellPoint(x: 0, y: 0), size: CellSize(width: base.width, height: base.height))
            // Centre on the rectangle, as a keyboard-opened menu centres on its
            // control — the popover reads as belonging to it rather than as
            // something that landed in the corner.
            point = (max(0, area.x + (area.width - panel.width) / 2), area.y)
        case .point(let unit):
            area = CellRect(x: 0, y: 0, width: base.width, height: base.height)
            point = (
                Int((unit.x * Double(base.width)).rounded(.down)),
                Int((unit.y * Double(base.height)).rounded(.down))
            )
        }

        switch arrowEdge {
        case .bottom:
            return (point.x, area.maxY, area.height)
        case .top:
            return (point.x, area.y - panel.height, 0)
        case .leading:
            return (area.x - panel.width, point.y, 0)
        case .trailing:
            return (area.maxX, point.y, 0)
        }
    }
}

extension PopoverPresentationModifier: Layoutable {
    /// The popover floats over the page, so the layout footprint is the
    /// presenting content — presented or not. Forwarding also keeps the
    /// section registration on the render pass.
    package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            content, proposal: proposal,
            context: context.withChildIdentity(type: Content.self, index: 0))
    }
}

/// StateStorage property indices for ``PopoverPresentationModifier``, which
/// draws its content and its popover at child identities of its own. A free
/// enum because the modifier is generic.
private enum StateIndex {
    static let dismissalGate = 0
    /// Whether an ``PopoverPresentationModifier/ownsPresentation`` popover was
    /// presented since it last drew closed.
    static let teardown = 1
}

/// Whether a popover that owns its presentation has a section to tear down: a
/// class, so the closed frame that tears it down changes it in place rather
/// than writing state while it draws.
@MainActor
private final class PopoverTeardown {
    var isPending = false
}
