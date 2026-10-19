//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuPopover.swift
//
//  The floating menu presentation shared by `.contextMenu` and a pop-up `Menu`.
//  Both put the same thing on screen — a bordered column of rows that owns the
//  focus and the keyboard until it is dismissed — and differ only in what opens
//  it and where it is anchored. Every row is a `Button`, including the one a
//  `Toggle` becomes: that is what claims an ordinal from the column. The
//  column itself is planned, measured and drawn in `MenuColumnLayout.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Renders `items` as an open POP-UP menu, through the same drop-down renderer
/// a `Picker` and a combo box use.
///
/// The two engines met here. The rows stay VIEWS — that is what gives `Menu`
/// arbitrary `@ViewBuilder` content, `ButtonRole`, per-row `.disabled()` and key
/// equivalents — and are drawn by `_MenuItemButtonStyle` exactly as before. But
/// they are then handed to ``DropdownMenu`` already drawn, so the menu inherits
/// what only the procedural side had: a scrollbar in its own COLUMN rather than
/// "N more" lines eating two rows of content, hover-follows-cursor, and a
/// highlight that spans the whole interior instead of leaving two gutters the
/// pointer cannot hit.
///
/// Slicing a column of views back into rows is possible because each row already
/// publishes a hit-test region tagged with its ordinal (``menuRowRegionID``), so
/// the exact line range of every row is known without guessing at heights or
/// classifying lines by what they look like. Lines no row claims — a `Divider`,
/// a heading — become unselectable rows: placed as drawn, never highlighted,
/// never clickable.
@MainActor
func renderMenuPopup(
    _ items: some View, context: RenderContext, controller: MenuPopupController,
    dismiss: @escaping () -> Void
) -> FrameBuffer {
    let rowsOnly = VStack(alignment: .leading, spacing: 0) { _MenuSectionedItems(items: items) }
        .buttonStyle(_MenuItemButtonStyle())

    // The channel goes in BEFORE anything is measured, not just before the
    // render. Only a render pass claims an ordinal (`_ButtonCore` guards on
    // `isMeasuring`), so a measure still cannot shift the numbering — but a row
    // that DRAWS differently as a menu row has to be measured that way too, or
    // the hug below is the width of a picture the render never draws. A
    // `Toggle` is exactly that row: a checkbox on the page, a menu item with a
    // state mark here.
    controller.sink.beginPass()
    var rowContext = context
    rowContext.environment.menuRowSink = controller.sink
    rowContext.environment.menuHighlightedOrdinal = controller.highlightedOrdinal

    // Size to the content first, exactly as the inline assembly does and for
    // the same reason: a `Divider` MEASURES as one cell but RENDERS at whatever
    // width it is offered, so laying out against the screen would inflate the
    // menu to the terminal. The chrome here is the drop-down's two border
    // columns plus its one-cell padding on each side.
    let inset = 1
    let widthCap = max(1, context.availableWidth - 2 - 2 * inset)
    let natural = measureChild(
        rowsOnly, proposal: ProposedSize(width: widthCap, height: nil), context: rowContext)
    let rowWidth = max(1, min(natural.width, widthCap)) + 2 * inset

    // Rendered against a canvas as tall as the column actually is, on purpose:
    // the renderer below is what windows the menu, and it can only window rows
    // that exist. Laid out in the space actually available, the column would be
    // clipped to the overlay's height first and the rows past the fold would
    // never be drawn at all — so the scrollbar would have nothing to scroll to.
    //
    // The canvas used to be `max(context.availableHeight * 64, 4096)`, and that
    // is a ceiling wearing a generous canvas's clothes: a menu of 9,000 rows
    // rendered exactly **4,096** of them (measured), so the highlight could
    // walk to ordinal 8,999 while the drop-down had no line to slice for it.
    // `measureNaturalExtent`'s ladder starts at the same generous budget — one
    // measure for every menu anybody will ever build by hand — and, unlike the
    // constant, keeps going when the content is taller.
    var sized = rowContext.withAvailableWidth(rowWidth)
    sized.environment.menuRowInset = inset
    // Set before the extent is measured, not after: a row that hugs is measured
    // against the menu's whole interior and a row that is drawn gets that
    // interior less its hint column, and a label can wrap into the difference —
    // which would make the canvas a row short of what the render then draws.
    sized.environment.menuRowWidth = rowWidth
    // …and having changed what a row measures to, say so, or the extent walk and
    // the render below can be answered from the hug above. The two asks here
    // happen to differ in width today, so this is a guard rather than a fix —
    // but it is the same two-question shape as the inline menu's, where it was
    // not a guard. See ``RenderContext/measureGeneration``.
    sized = sized.invalidatingMeasureMemo()
    sized = sized.withAvailableHeight(
        max(1, measureNaturalExtent(
            rowsOnly, along: .vertical,
            proposal: ProposedSize(width: rowWidth, height: nil), context: sized,
            startingBudget: naturalExtentStartingBudget(forVisible: context.availableHeight)
        ).height))
    let column = TUIkitView.renderToBuffer(rowsOnly, context: sized)
    controller.adoptRenderedRows()

    // Which lines belong to which row, from the regions the rows themselves
    // published. A line no row claimed is chrome the caller drew.
    var ordinalByLine: [Int: Int] = [:]
    for region in column.hitTestRegions {
        guard let focusID = region.focusID, let ordinal = menuRowOrdinal(fromRegionID: focusID)
        else { continue }
        for line in region.offsetY..<(region.offsetY + region.height) {
            ordinalByLine[line] = ordinal
        }
    }
    let selectable = Set(controller.highlight.selectable)
    var rows: [DropdownMenu.Row] = []
    var rowByOrdinal: [Int: Int] = [:]
    for (line, content) in column.lines.enumerated() {
        if let ordinal = ordinalByLine[line] {
            rowByOrdinal[ordinal] = rows.count
        }
        rows.append(
            .rendered(
                content,
                isSelectable: ordinalByLine[line].map(selectable.contains) ?? false))
    }

    // Every line of an item answers for it — the pointer over it, a click on
    // it — not only the line `rowByOrdinal` keeps: an item too long for the
    // menu wraps, and inverting that map left the lines above its last one
    // belonging to nothing, so a click on the first line of "Export Everything
    // As One Long Archive" ran nothing. A row here IS a line, so the lines'
    // own ordinals are the rows'.
    let ordinalByRow = ordinalByLine
    return DropdownMenu.popup(
        DropdownMenu.Configuration(
            rows: rows,
            highlightedRow: controller.highlightedOrdinal.flatMap { rowByOrdinal[$0] },
            innerWidth: rowWidth,
            scroll: controller.scroll,
            followHighlight: controller.highlight.consumeFollowPending(),
            autoRepeatToken: "menu-popup-scrollbar-\(context.identity.path)"),
        context: context,
        // Hover follows the cursor, which a view-composed menu never did: its
        // rows had a hover state of their own but nothing joined it up to the
        // highlight the keyboard was driving.
        onHover: { row in ordinalByRow[row].map(controller.highlight.point(at:)) },
        onActivate: { row in ordinalByRow[row].map(controller.sink.activate(ordinal:)) },
        onDismiss: dismiss)
}

/// Where a presented menu hangs, and off what.
package struct MenuAnchor {
    /// The menu's top-left column, in the presenter's own coordinate space.
    let x: Int

    /// The menu's top row, likewise.
    let y: Int

    /// The width to centre the menu within, starting at ``x``, or `nil` to put
    /// its left edge at ``x``.
    ///
    /// A pointer-opened menu is anchored at the cell that was clicked, because
    /// the pointer is about to pick from it and wants the rows in a predictable
    /// place under itself. A KEYBOARD-opened one has no pointer to be
    /// predictable for, so it centres on the view it belongs to and reads as
    /// that view's menu rather than as something that landed in the corner.
    var centredWithin: Int?

    /// How many rows the control immediately above ``y`` occupies.
    ///
    /// `1` for a pop-up ``Menu``, whose trigger is the row above it; `0` for a
    /// `.contextMenu`, which hangs off the cell that was clicked and has
    /// nothing above it to clear. The number does two jobs — the flip when
    /// there is no room below, and an enclosing `ScrollView`'s overlay culling
    /// — and both go wrong when it is understated. See
    /// ``OverlayLayer/anchorHeight``.
    let controlHeight: Int

    package init(x: Int, y: Int, controlHeight: Int, centredWithin: Int? = nil) {
        self.x = x
        self.y = y
        self.controlHeight = controlHeight
        self.centredWithin = centredWithin
    }
}

/// Presents `items` as a floating menu over `base`, anchored at
/// (`anchor.x`, `anchor.y`) in `base`'s own coordinate space.
///
/// Takes the focus section, the keyboard, and the screen-covering dismiss
/// backdrop; renders the items as menu rows sized to hug their widest; and
/// appends the result to `base` as a `.popover` overlay. A no-op on a measure
/// pass — presentation is a render-pass side effect, and an ancestor measuring
/// by rendering must not register a phantom section.
///
/// - Parameters:
///   - items: The menu's content: `Button`s, `Toggle`s and `Divider`s.
///   - base: The buffer to float the menu over; the overlay is appended to it.
///   - controller: The menu's highlight, persisted by the caller across frames.
///     The caller tells it how the menu was opened (``MenuPopupController/opened(withSelection:)``)
///     at the moment it opens, when only the caller knows which device did it.
///   - sectionID: The focus section this menu owns while it is up.
///   - itemsIndex: The child-identity index for `items` under `context`, so its
///     `@State` and focus slots stay distinct from the presenter's own.
///   - anchor: Where the menu's top-left goes, and how tall the control above
///     it is — see ``MenuAnchor``.
///   - dismiss: Closes the menu — run by Escape, by an outside click, and by
///     any item that fires.
///   - context: The presenter's render context.
@MainActor
package func presentMenuPopover<Items: View>(
    items: Items,
    over base: inout FrameBuffer,
    controller: MenuPopupController,
    sectionID: String,
    itemsIndex: Int,
    anchor: MenuAnchor,
    dismiss: @escaping () -> Void,
    context: RenderContext
) {
    // A mouse dispatcher is what makes a presentation possible at all — the
    // dismiss backdrop and every row's click region go through it.
    guard !context.isMeasuring, context.environment.mouseEventDispatcher != nil else { return }

    context.environment.volatileReadTracker?.recordRenderSideEffect()
    let focusManager = context.environment.focusManager
    focusManager?.registerSection(id: sectionID)
    // As a PRESENTED section, the same rule every presenter follows: never
    // taken back from a surface stacked on this one. See
    // `FocusManager.activatePresentedSection(id:)`.
    focusManager?.activatePresentedSection(id: sectionID)
    // Input-grabbing so global chrome hotkeys don't fire behind the menu.
    focusManager?.markSectionModal(id: sectionID)
    // A menu takes the keyboard, not the focus: its items and the page go on
    // reading the focused values of what was focused where it was opened
    // (`FocusManager.focusedValuesIdentity`).
    focusManager?.markSectionMenu(id: sectionID)
    // Closed if a frame goes by without it: see `FocusManager.notePresentation`.
    focusManager?.notePresentation(id: sectionID, dismiss: dismiss)
    // The section deliberately holds NO focus: a pop-up's rows report to the
    // controller, not to the focus ring. Something may still register in here
    // (a tall menu's own ScrollView does), and without this the end of the
    // render pass would hand it the focus for want of anything better.
    focusManager?.markSectionFocusOptional(id: sectionID)
    // Take the keyboard for this section. Isolating the presenter's own subtree
    // silences what is BENEATH the menu, but a menu hangs off one view — its
    // siblings are elsewhere in the tree and render into the live dispatcher
    // every frame, keeping their handlers.
    context.environment.keyEventDispatcher!.grabInput(sectionID: sectionID)
    // Escape closes the MENU, not the page. Claiming the label is what makes
    // that true as well as discoverable: `InputHandler` routes ESC to the focus
    // system before the status bar when an override is posted, and without it
    // the status bar's own "⎋ back" won — so Escape in an open Menu dismissed
    // the whole page behind it. The Picker drop-down has always claimed it;
    // this is the same claim, from the presentation both share.
    context.environment.statusBar?.escapeLabelOverride = MenuPresentationLabels.popUp.close
    attachMenuKeys(controller: controller, sectionID: sectionID, dismiss: dismiss, context: context)

    var menuContext = context
        .withChildIdentity(erasedType: Items.self, index: itemsIndex)
        .withAvailableWidth(context.environment.terminalWidth)
        .withAvailableHeight(context.environment.overlayContentHeight)
    menuContext.environment.activeFocusSectionID = sectionID
    // A menu opened from inside this one is no menu bar's.
    menuContext.environment.menuBarStep = nil
    menuContext.leaveScrollCanvas()
    menuContext.environment.leaveUnstatedTextAlignment()
    menuContext.environment.dismissMenu = DismissMenuAction(action: dismiss)
    // Explicitly NOT the top-border ●: that mark reads as "this titled
    // container has the focus", and a menu has no title, so a lone dot floating
    // in an otherwise dead frame reads as debris. Left nil, which is also what
    // stops an enclosing section's indicator leaking in. (The FRAME still
    // breathes — the drop-down renderer draws its own border on the shared
    // `SelectionEmphasis` clock, so two menus on one screen agree.)
    menuContext.environment.focusIndicator = nil

    var menuBuffer = renderMenuPopup(
        items, context: menuContext, controller: controller, dismiss: dismiss)
    guard !menuBuffer.isEmpty else { return }

    // The same screen-covering dismiss backdrop the drop-down menus use.
    DropdownMenu.attachDismissBackdrop(to: &menuBuffer, context: context, onDismiss: dismiss)

    // `.popover` level, declaring the control above it. That number does two
    // jobs, and getting it wrong broke both: an enclosing `ScrollView` culls an
    // overlay by `offsetY - anchorHeight`, so a menu whose trigger is the last
    // visible row starts exactly AT the viewport's bottom edge and was thrown
    // away before the compositor saw it (the `Picker` drop-down's version of
    // this is why `anchorHeight` exists); and with no room below, the flip puts
    // the menu's bottom flush with the anchor's TOP, which without a height is
    // flush with the trigger itself — landing the menu on the control that
    // opened it.
    // Centring can only happen here: the menu's width is not known until it has
    // been laid out to its own content.
    var offsetX = anchor.x
    if let span = anchor.centredWithin {
        offsetX = anchor.x + max(0, (span - menuBuffer.width) / 2)
    }
    base.overlays.append(
        OverlayLayer(
            offsetX: offsetX, offsetY: anchor.y, content: menuBuffer,
            level: .popover, anchorHeight: anchor.controlHeight, holdsInput: true))
}

/// Gives the open menu the whole keyboard: the arrows, the jump gestures every
/// other list-like control in TUIkit answers (Home, End, PageUp, PageDown,
/// Shift+arrow), Enter/Space to choose a row, and Escape to close.
///
/// One handler, because the menu owns an ordinal rather than a focus id — there
/// is no ring underneath to implement half of this. The gestures themselves come
/// from ``OptionListNavigation``, the same helper the `Picker` drop-down, the
/// combo box and `RadioButtonGroup` use, so a menu and a drop-down move
/// identically for the same keystroke.
///
/// Left and Right do nothing in a menu of its own. In a menu bar's menu they
/// step to the menu beside it (``EnvironmentValues/menuBarStep``), as a menu
/// bar's arrows do on every desktop.
///
/// Only what the menu acts on is swallowed — exactly what the focus ring
/// swallowed for it before. A key equivalent typed with the menu open must still
/// reach the shortcut registry (`InputHandler` layer 3.5, below this one), which
/// is how a menu row's accelerator fires while its own menu is showing.
@MainActor
private func attachMenuKeys(
    controller: MenuPopupController, sectionID: String, dismiss: @escaping () -> Void,
    context: RenderContext
) {
    guard let dispatcher = context.environment.keyEventDispatcher else { return }
    let multiplier = context.environment.shiftStepMultiplier
    // A page is the menu's visible rows; the cap is what the column was given.
    let pageSize = max(1, context.environment.overlayContentHeight - 2)
    let barStep = context.environment.menuBarStep

    dispatcher.addHandler(sectionID: sectionID) { event in
        switch event.key {
        case .escape:
            dismiss()
            return true
        case .enter, .space:
            return controller.activateHighlighted()
        case .left, .right:
            // On the focus ring these act as Up/Down (`dispatchKeyEvent` treats
            // the axes alike), which in a vertical menu is simply wrong. The
            // Picker drop-down has always eaten them. A menu bar's menu steps
            // to its neighbour.
            barStep?.step(event.key == .left ? -1 : 1)
            return true
        default:
            return controller.highlight.handle(
                event, multiplier: multiplier, pageSize: pageSize)
        }
    }
}

// MARK: - A Menu Bar's Menu

/// What Left and Right do in an open menu that is one of a menu bar's: step to
/// the menu beside it, `-1` the one before and `1` the one after.
package struct MenuBarStep {
    /// Steps by the offset given.
    package let step: (Int) -> Void

    package init(step: @escaping (Int) -> Void) {
        self.step = step
    }
}

private struct MenuBarStepKey: EnvironmentKey {
    // Computed: the step is a closure, not `Sendable`, so it cannot be a stored
    // global, and no menu is a menu bar's by default anyway.
    static var defaultValue: MenuBarStep? { nil }
}

extension EnvironmentValues {
    /// Where an open menu's Left and Right go: the menu bar presenting it
    /// (TUIkitCommands) sets it; `nil` for any other menu, whose arrows across
    /// do nothing.
    package var menuBarStep: MenuBarStep? {
        get { self[MenuBarStepKey.self] }
        set { self[MenuBarStepKey.self] = newValue }
    }
}
