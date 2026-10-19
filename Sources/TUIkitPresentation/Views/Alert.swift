//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Alert.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

/// A modal alert view that displays a title, message, and optional action buttons.
///
/// `Alert` draws the panel. **Presenting it is a separate job**, and the way to
/// do it is ``View/alert(_:isPresented:actions:message:borderStyle:borderColor:titleColor:)-(LocalizedStringKey,_,_,_,_,_,_)`` or
/// ``View/modal(isPresented:onDismiss:content:)``.
///
/// ## Structure
///
/// - **Header**: Title (rendered in the top border)
/// - **Body**: Message
/// - **Footer**: Action buttons (separated by optional separator line)
///
/// ## Examples
///
/// ```swift
/// // Simple alert
/// Alert(title: "Warning", message: "Are you sure?")
///
/// // Alert with action buttons
/// Alert(title: "Confirm", message: "Delete this item?") {
///     Button("Yes") { }
///     Button("No") { }
/// }
///
/// // Present it. `.alert` builds the panel for you from a title and actions;
/// // `.modal` takes an Alert (or a Dialog) you built yourself.
/// mainContent
///     .alert("Notice", isPresented: $showing) {
///         Button("OK") { showing = false }
///     } message: {
///         Text("Operation complete!")
///     }
///
/// mainContent
///     .modal(isPresented: $showing) {
///         Alert(title: "Notice", message: "Operation complete!") {
///             Button("OK") { showing = false }
///         }
///     }
/// ```
///
/// > Important: Do **not** present an `Alert` with bare `.dimmed().overlay()`.
/// > This documentation taught that pattern, and it does not work: `.dimmed()`
/// > dims and deadens the background in place, and `.overlay` composites the
/// > panel into the page in flow. The panel never captures the keyboard,
/// > Escape does not close it, it is not centred on the screen, and anything
/// > OUTSIDE the dimmed subtree stays live. The
/// > presentation modifiers do all four things — dim the background AND make
/// > it inert, capture focus in a section of their own, publish ESC to
/// > dismiss, and centre the panel on the whole screen no matter where in the
/// > tree the modifier is attached. ``Dialog`` carries the same warning.
///
/// Composing an `Alert` inline — in a `ZStack`, or through `.overlay` — is
/// still legitimate when what you want is an alert-SHAPED panel that is part
/// of the page. It is only "modal" that it cannot give you.
public struct Alert<Actions: View>: View {
    /// The alert title.
    let title: String

    /// The alert message.
    let message: String

    /// The shared visual configuration.
    let config: ContainerConfig

    /// The action views (typically buttons).
    let actions: Actions

    /// Whether the action buttons stack vertically (an action-sheet /
    /// confirmation-dialog column) rather than the default horizontal row.
    let verticalButtons: Bool

    /// Creates an alert with localized text and custom action views.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``. Both of them: an alert's message is prose the
    /// reader has to understand, not data.
    ///
    /// > Note: Both must be literals, or neither is looked up — a computed
    ///   `String` in either slot picks the plain-`String` overload below, which
    ///   displays what it is given. Resolve such a pair yourself.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title.
    ///   - messageKey: The key for the alert message.
    ///   - borderStyle: The border style (default: appearance borderStyle).
    ///   - borderColor: The border color (default: theme border).
    ///   - titleColor: The title color (default: theme accent).
    ///   - showFooterSeparator: Whether to show separator before actions (default: true).
    ///   - verticalButtons: Stack the buttons vertically (default: `false`).
    ///   - actions: The action views to display in the footer.
    public init(
        title titleKey: LocalizedStringKey,
        message messageKey: LocalizedStringKey,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil,
        showFooterSeparator: Bool = true,
        verticalButtons: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            title: titleKey.localized,
            message: messageKey.localized,
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor,
            showFooterSeparator: showFooterSeparator,
            verticalButtons: verticalButtons,
            actions: actions
        )
    }

    /// Creates an alert with custom action views, displayed as written.
    ///
    /// Generic over `StringProtocol` — in **both** slots, the way
    /// `LabeledContent`'s pair is — rather than taking concrete `String`s,
    /// which is what keeps a *literal* binding to the key overload above; see
    /// ``LocalizedStringKey``. `@_disfavoredOverload` alone is not enough once
    /// the initializer takes another required argument, and this one takes
    /// `actions`.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - message: The alert message.
    ///   - borderStyle: The border style (default: appearance borderStyle).
    ///   - borderColor: The border color (default: theme border).
    ///   - titleColor: The title color (default: theme accent).
    ///   - showFooterSeparator: Whether to show separator before actions (default: true).
    ///   - verticalButtons: Stack the buttons vertically (default: `false`).
    ///   - actions: The action views to display in the footer.
    @_disfavoredOverload
    public init<S1: StringProtocol, S2: StringProtocol>(
        title: S1,
        message: S2,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil,
        showFooterSeparator: Bool = true,
        verticalButtons: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = String(title)
        self.message = String(message)
        self.config = ContainerConfig(
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor,
            padding: EdgeInsets(horizontal: 2, vertical: 1),
            showFooterSeparator: showFooterSeparator
        )
        self.actions = actions()
        self.verticalButtons = verticalButtons
    }

    public var body: some View {
        _AlertCore(
            title: title,
            message: message,
            config: config,
            actions: actions,
            verticalButtons: verticalButtons
        )
    }
}

// MARK: - Alert Core Rendering

/// Internal view that handles Alert rendering.
///
/// This separation ensures `Alert.body` returns a real `View`, allowing
/// environment modifiers like `.foregroundStyle()` to propagate correctly.
struct _AlertCore<Actions: View>: View, Renderable, Layoutable {
    let title: String
    let message: String
    let config: ContainerConfig
    let actions: Actions
    var verticalButtons: Bool = false

    var body: Never {
        fatalError("_AlertCore renders via Renderable")
    }

    /// Maximum width for alerts (characters).
    private static var maxWidth: Int { 60 }

    /// Measures via the shared container path, applying the same `maxWidth`
    /// clamp `renderToBuffer` uses — to the proposal as well as the context, so
    /// the container reads the clamped width whether or not a proposal is set.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var alertContext = context
        alertContext.availableWidth = min(context.availableWidth, Self.maxWidth)
        var alertProposal = proposal
        if let width = proposal.width {
            alertProposal = ProposedSize(width: min(width, Self.maxWidth), height: proposal.height)
        }
        let buttons = alertActions(from: actions, in: context)
        let config = resolvedConfig(context)
        let shownTitle = resolvedTitle(context)
        let body = messageBody(context)
        if let suppression = context.environment.dialogSuppression {
            return measureContainer(
                title: shownTitle, config: config, content: body,
                footer: _AlertFooter(
                    buttons: buttons, verticalButtons: verticalButtons, suppression: suppression),
                proposal: alertProposal, context: alertContext)
        }
        if verticalButtons {
            return measureContainer(
                title: shownTitle, config: config, content: body,
                footer: buttons.isEmpty ? nil : AlertButtonColumn(actions: buttons),
                proposal: alertProposal, context: alertContext)
        }
        return measureContainer(
            title: shownTitle, config: config, content: body,
            footer: buttons.isEmpty ? nil : AlertButtonRow(actions: buttons),
            proposal: alertProposal, context: alertContext)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Limit alert width
        var alertContext = context
        alertContext.availableWidth = min(context.availableWidth, Self.maxWidth)

        let buttons = alertActions(from: actions, in: context)
        let config = resolvedConfig(context)
        let shownTitle = resolvedTitle(context)
        let body = messageBody(context)
        // A suppression toggle needs the footer that draws it above the
        // buttons; without one the buttons are the footer, as they always were.
        if let suppression = context.environment.dialogSuppression {
            return renderContainer(
                title: shownTitle, config: config, content: body,
                footer: _AlertFooter(
                    buttons: buttons, verticalButtons: verticalButtons, suppression: suppression),
                context: alertContext)
        }
        if verticalButtons {
            return renderContainer(
                title: shownTitle, config: config, content: body,
                footer: buttons.isEmpty ? nil : AlertButtonColumn(actions: buttons),
                context: alertContext)
        }
        return renderContainer(
            title: shownTitle, config: config, content: body,
            footer: buttons.isEmpty ? nil : AlertButtonRow(actions: buttons),
            context: alertContext)
    }

    /// The caution sign a critical dialog's title starts with: U+26A0 WARNING
    /// SIGN with U+FE0F, the emoji presentation — two cells, coloured by the
    /// font rather than the palette.
    ///
    /// Spelt with the selector, not bare: bare, U+26A0 is a text-presentation
    /// character that terminals draw one cell wide or two, while the selector
    /// form is a VS-16 pictograph, a measured row of the advance table in
    /// `Terminal compatibility survey.md` — claimed two cells, and compensated where a
    /// host advances it one (Terminal.app, iTerm2) by the writer, as every
    /// VS-16 pictograph in an app's own text is.
    static var criticalMark: String { "\u{26A0}\u{FE0F}" }

    /// The title as the environment's dialog severity leaves it: a critical
    /// dialog's starts with ``criticalMark``, where macOS draws its large
    /// caution symbol.
    private func resolvedTitle(_ context: RenderContext) -> String {
        guard context.environment.dialogIsCritical else { return title }
        return title.isEmpty ? Self.criticalMark : Self.criticalMark + " " + title
    }

    /// The configuration as the environment's dialog severity leaves it: a
    /// critical dialog takes the palette's warning colour for its border and
    /// title, where the alert was not given colours of its own — beside the
    /// caution sign its title starts with (``resolvedTitle(_:)``).
    private func resolvedConfig(_ context: RenderContext) -> ContainerConfig {
        guard context.environment.dialogIsCritical else { return config }
        var critical = config
        critical.borderColor = critical.borderColor ?? .palette.warning
        critical.titleColor = critical.titleColor ?? .palette.warning
        return critical
    }

    /// The message, with the environment's dialog icon beside it.
    private func messageBody(_ context: RenderContext) -> _AlertMessage {
        _AlertMessage(message: message, icon: context.environment.dialogIcon)
    }
}

// MARK: - Alert Button Row

/// Internal view that renders buttons horizontally for alerts.
struct AlertButtonRow: View, Renderable {
    let actions: [AlertAction]

    var body: Never {
        fatalError("AlertButtonRow renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !actions.isEmpty else {
            return FrameBuffer(lines: [])
        }

        // Sort buttons: cancel on left, others on right
        let sortedButtons = actions.sorted { lhs, rhs in
            let lhsIsCancel = lhs.role == .cancel
            let rhsIsCancel = rhs.role == .cancel
            if lhsIsCancel != rhsIsCancel {
                return lhsIsCancel  // Cancel comes first (left)
            }
            return false  // Keep original order otherwise
        }

        // Render each button under its OWN child identity — see the note in
        // `AlertButtonColumn`, which had the identical defect.
        var buttonBuffers: [FrameBuffer] = []
        for (index, action) in sortedButtons.enumerated() {
            let childContext = context.withChildIdentity(type: Button.self, index: index)
            let buffer = TUIkitView.renderToBuffer(action.view, context: childContext)
            buttonBuffers.append(buffer)
        }

        // Find the maximum height
        let maxHeight = buttonBuffers.map { $0.height }.max() ?? 0

        // Calculate total width needed (buttons + spacing)
        let spacing = 1
        let totalButtonWidth = buttonBuffers.reduce(0) { $0 + $1.width }
        let totalSpacingWidth = max(0, buttonBuffers.count - 1) * spacing
        let totalNeededWidth = totalButtonWidth + totalSpacingWidth

        // Available width from context
        let availableWidth = context.availableWidth

        // Right-align: calculate left padding
        let leftPadding = max(0, availableWidth - totalNeededWidth)

        // Combine horizontally (right-aligned). Each child Button
        // already carries its own hit-test region; we lift those into
        // the composed buffer by tracking the running x-offset so that
        // clicks on dialog buttons reach the right handler.
        var resultLines: [String] = Array(repeating: "", count: maxHeight)
        var resultRegions: [HitTestRegion] = []
        var resultRuns: [AnimatedCellRun] = []
        var resultFaded: [OpacityRegion] = []
        // The buttons' layers, gathered as `Section` gathers its parts' (see
        // `AlertButtonColumn`).
        var layers = FrameBuffer()
        let spacer = String.spaces(spacing)
        var xCursor = leftPadding

        for lineIndex in 0..<maxHeight {
            resultLines[lineIndex] = String.spaces(leftPadding)
        }

        for (index, buffer) in buttonBuffers.enumerated() {
            if index > 0 {
                for lineIndex in 0..<maxHeight {
                    resultLines[lineIndex] += spacer
                }
                xCursor += spacing
            }
            for lineIndex in 0..<maxHeight {
                if lineIndex < buffer.height {
                    resultLines[lineIndex] += buffer.lines[lineIndex]
                } else {
                    resultLines[lineIndex] += String.spaces(buffer.width)
                }
            }
            resultRegions.append(
                contentsOf: buffer.shiftedHitTestRegions(byX: xCursor, y: 0))
            // …and its animated runs, so the focused button's caps keep
            // breathing once the dialog composes the row. See
            // `FrameBuffer.replacingLines`, which states the rule and names
            // `AnimatedRunPropagationTests`: a dropped run freezes an animation
            // rather than removing it, so it reads as a win in a diff.
            resultRuns.append(contentsOf: buffer.shiftedAnimatedCells(byX: xCursor, y: 0))
            layers.coverOverflow(under: buffer, at: (x: xCursor, y: 0))
            layers.appendOverlays(of: buffer, shiftedByX: xCursor, y: 0)
            resultFaded.append(contentsOf: buffer.shiftedOpacityRegions(byX: xCursor, y: 0))
            xCursor += buffer.width
        }

        var result = FrameBuffer(lines: resultLines)
        result.hitTestRegions = resultRegions
        result.animatedCells = resultRuns
        result.opacityRegions = resultFaded
        result.overlays = layers.overlays
        return result
    }
}

// MARK: - Alert Button Column

/// Internal view that renders buttons stacked vertically for confirmation
/// dialogs (action sheets). A cancel-role button is sorted to the bottom, and
/// each button is centred within the dialog width.
struct AlertButtonColumn: View, Renderable {
    let actions: [AlertAction]

    var body: Never {
        fatalError("AlertButtonColumn renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !actions.isEmpty else {
            return FrameBuffer(lines: [])
        }

        // Cancel goes last (bottom), matching action-sheet convention.
        let sortedButtons = actions.sorted { lhs, rhs in
            let lhsIsCancel = lhs.role == .cancel
            let rhsIsCancel = rhs.role == .cancel
            if lhsIsCancel != rhsIsCancel {
                return !lhsIsCancel  // non-cancel first, cancel last
            }
            return false
        }

        let width = context.availableWidth
        var lines: [String] = []
        var regions: [HitTestRegion] = []
        var runs: [AnimatedCellRun] = []
        var faded: [OpacityRegion] = []
        // The buttons' layers, gathered as a stack gathers its children's, and
        // `Section` its parts': what a button's label draws past its region
        // (an alignment guide's placement, `OverlayLayer.isOverflow`) is cut
        // where a later button paints, so it is drawn over the buttons before
        // it and under the buttons after it. Lifted uncut, a label pushed past
        // its button drew over the next one. A buffer of no lines: it only
        // carries the layers, so that the stack's own two steps
        // (`coverOverflow(under:at:)`, `appendOverlays(of:shiftedByX:y:)`) do
        // the work and keep the hint that none is overflow.
        var layers = FrameBuffer()

        // Each button renders under its OWN child identity. A `Button`'s
        // default focus ID is derived from `context.identity.path`, so rendering
        // them all from the SAME context gives every button in the dialog one
        // identity: the focus system then sees a single control — they all pulse
        // together, Tab cannot move between them, and Return runs whichever
        // action that one id resolves to, whatever the pointer or the arrows
        // said. (Clicking still works, because a click routes by hit region to a
        // handler id, which is per-button.) `ButtonRow` has always done this;
        // the alert's two containers had not.
        //
        // Indexed by SORTED position, which is both the drawn order and the
        // order the focus ring walks, so Tab runs top to bottom.
        for (index, action) in sortedButtons.enumerated() {
            let childContext = context.withChildIdentity(type: Button.self, index: index)
            let buffer = TUIkitView.renderToBuffer(action.view, context: childContext)
            let leftPadding = max(0, (width - buffer.width) / 2)
            let pad = String.spaces(leftPadding)
            let startY = lines.count
            for line in buffer.lines {
                lines.append(pad + line)
            }
            // Lift each button's hit-test regions — and its animated runs — to
            // its position in the column. See `FrameBuffer.replacingLines` on
            // why the runs are not optional: dropping one freezes the caps
            // rather than merely failing to animate them.
            regions.append(
                contentsOf: buffer.shiftedHitTestRegions(byX: leftPadding, y: startY))
            runs.append(contentsOf: buffer.shiftedAnimatedCells(byX: leftPadding, y: startY))
            layers.coverOverflow(under: buffer, at: (x: leftPadding, y: startY))
            layers.appendOverlays(of: buffer, shiftedByX: leftPadding, y: startY)
            faded.append(contentsOf: buffer.shiftedOpacityRegions(byX: leftPadding, y: startY))
        }

        var result = FrameBuffer(lines: lines)
        result.hitTestRegions = regions
        result.animatedCells = runs
        result.opacityRegions = faded
        result.overlays = layers.overlays
        return result
    }
}

// MARK: - Convenience Initializer (no actions)

extension Alert where Actions == EmptyView {
    /// Creates an actionless alert with localized text.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``, and the note on
    /// ``Alert/init(title:message:borderStyle:borderColor:titleColor:showFooterSeparator:verticalButtons:actions:)-(LocalizedStringKey,_,_,_,_,_,_,_)``
    /// about mixing a literal with a computed `String`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title.
    ///   - messageKey: The key for the alert message.
    ///   - borderStyle: The border style (default: appearance default).
    ///   - borderColor: The border color (default: nil).
    ///   - titleColor: The title color (default: theme accent).
    public init(
        title titleKey: LocalizedStringKey,
        message messageKey: LocalizedStringKey,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) {
        self.init(
            title: titleKey.localized,
            message: messageKey.localized,
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor
        )
    }

    /// Creates an alert without action buttons, displayed as written.
    ///
    /// Generic over `StringProtocol` in both slots for the same reason as the
    /// form with actions — see ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - message: The alert message.
    ///   - borderStyle: The border style (default: appearance default).
    ///   - borderColor: The border color (default: nil).
    ///   - titleColor: The title color (default: theme accent).
    @_disfavoredOverload
    public init<S1: StringProtocol, S2: StringProtocol>(
        title: S1,
        message: S2,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) {
        self.title = String(title)
        self.message = String(message)
        self.config = ContainerConfig(
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor,
            padding: EdgeInsets(horizontal: 2, vertical: 1),
            showFooterSeparator: false
        )
        self.actions = EmptyView()
        self.verticalButtons = false
    }
}
