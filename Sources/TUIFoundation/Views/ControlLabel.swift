//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlLabel.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Control Labels

/// Shared treatment for a control's own label views.
enum _ControlLabel {
    /// A disabled control dims its label WITH it — the label is part of the
    /// control, not adjacent content. The dim is the same recipe every
    /// built-in control uses for its disabled chrome, applied as the
    /// environment foreground so a label with its own explicit colour still
    /// wins. Enabled controls get the label back untouched.
    ///
    /// - Parameter controlDisabled: The control's OWN `.disabled()` flag —
    ///   the per-control method bypasses the `\.isEnabled` environment, so
    ///   callers pass it explicitly; either source of disablement dims.
    @MainActor
    static func dimmingWhenDisabled<Label: View>(
        _ label: Label, context: RenderContext, controlDisabled: Bool = false
    ) -> AnyView {
        guard controlDisabled || !context.environment.isEnabled else { return AnyView(label) }
        let palette = context.environment.palette
        return AnyView(
            label.foregroundStyle(
                palette.foregroundTertiary.opacity(
                    ViewConstants.disabledForeground, over: palette.background)))
    }

    /// `buffer`, a label drawn through ``dimmingWhenDisabled(_:context:controlDisabled:)``,
    /// drawn faint too where a disabled control says so without colour
    /// (``FrameBuffer/fadedWithoutColor(if:greyDrawsAsEnabled:context:)``), as the
    /// control beside it is. At no colour the grey is gone, and a stepper's,
    /// slider's or picker's label was drawn as an enabled one's while a toggle's,
    /// faded with its control, was faint.
    @MainActor
    static func fadingWhenDisabled(
        _ buffer: FrameBuffer, context: RenderContext, controlDisabled: Bool = false
    ) -> FrameBuffer {
        buffer.fadedWithoutColor(if: controlDisabled || !context.environment.isEnabled, context: context)
    }
}

/// Renders an inline control label followed by one separating space — or
/// nothing when the label is empty/blank/absent, so the control isn't preceded
/// by a stray space.
///
/// This is the shared building block for every control whose label sits to the
/// LEFT of the control on the same line, which is what macOS SwiftUI does for
/// `Stepper`, `Slider` and `Picker`. Measured 2026-07-25 against real SwiftUI
/// (hosted in an `NSHostingView`, drawn controls captured via `cacheDisplay`):
///
/// ```
/// Slider(value: $a) { Text("Volume") }   ->  "Volume  ▬▬▬▬●▬▬▬▬"
/// Slider(value: $b)                      ->  "▬▬▬▬▬▬▬●▬▬▬▬▬▬▬"
/// Picker("Theme", selection: $t) { … }   ->  "Theme  [ Dark ⌄ ]"
/// Picker("", selection: $t) { … }        ->  "[ Dark ⌄ ]"
/// ```
///
/// i.e. the label takes space on the same line and the control shrinks to fit,
/// and an absent label reserves NOTHING — no leading gap. Composing it as an
/// HStack sibling (rather than drawing it inside the control's own core) also
/// keeps the core's internal x-offsets — hit regions, arrow zones, track
/// origin — measured from its own buffer, because the stack shifts them.
nonisolated package struct _CollapsingLabel<Label: View>: View, Renderable, Layoutable {
    let label: Label?

    /// The control's own `.disabled()` flag — it bypasses the environment,
    /// so the label must be told explicitly.
    let controlDisabled: Bool

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUINumericControls' sliders and steppers, TUIPickers'
    /// pickers and date pickers, and TUIForms' labeled content make these.
    package init(label: Label?, controlDisabled: Bool) {
        self.label = label
        self.controlDisabled = controlDisabled
    }

    @MainActor package var body: Never { fatalError("_CollapsingLabel renders via Renderable") }

    /// Size from one render (it drops to nothing for a blank label and adds a
    /// trailing space otherwise — both need the render), flexibility from the label.
    @MainActor package func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        let labelFlexible = label.map {
            measureChild($0, proposal: proposal, context: context).isWidthFlexible
        } ?? false
        return ViewSize(width: size.width, height: size.height, isWidthFlexible: labelFlexible)
    }

    @MainActor package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // `.labelsHidden()` collapses the label the same way an absent one
        // does — including the separating space — because the point of hiding
        // a label is that the layout closes up around it. Answered here rather
        // than at the three call sites so `Picker`, `Slider` and `Stepper`
        // cannot come to disagree about what hidden means.
        guard !context.environment.controlLabelsAreHidden else { return FrameBuffer() }
        guard let label, !(label is EmptyView) else { return FrameBuffer() }
        let buffer = _ControlLabel.fadingWhenDisabled(
            TUIView.renderToBuffer(
                _ControlLabel.dimmingWhenDisabled(
                    label, context: context, controlDisabled: controlDisabled),
                context: context),
            context: context, controlDisabled: controlDisabled)
        guard !buffer.isBlank else { return FrameBuffer() }
        // `replacingLines`, not `FrameBuffer(lines:)`: a label is a full view
        // slot, so its content can carry runs, hit-test regions and overlays,
        // and the bare initializer drops all three. Appending the gap space
        // moves nothing — no row is inserted and no cell shifts left — so they
        // carry through unshifted. A `Slider`'s label holding a Button drew its
        // hover and focus perfectly and could not be clicked; one presenting a
        // sheet grabbed the keyboard and drew no sheet.
        return buffer.replacingLines(buffer.lines.map { $0 + " " })
    }
}

/// A control's label drawn apart from the control — in a ``Form``'s label
/// column (``FormFieldControl``) — dimmed with a disabled control as
/// ``_CollapsingLabel`` dims it, and with no separating space: the column
/// supplies the gap.
nonisolated package struct _DetachedControlLabel<Label: View>: View, Renderable, Layoutable {
    let label: Label

    /// The control's own `.disabled()` flag, which bypasses the environment.
    let controlDisabled: Bool

    package init(label: Label, controlDisabled: Bool) {
        self.label = label
        self.controlDisabled = controlDisabled
    }

    @MainActor package var body: Never { fatalError("_DetachedControlLabel renders via Renderable") }

    @MainActor package func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(label, proposal: proposal, context: context)
    }

    @MainActor package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        _ControlLabel.fadingWhenDisabled(
            TUIView.renderToBuffer(
                _ControlLabel.dimmingWhenDisabled(label, context: context, controlDisabled: controlDisabled),
                context: context),
            context: context, controlDisabled: controlDisabled)
    }
}

/// A control and its label, laid out together — the stack of a `Slider`, a
/// `Stepper`, a `Picker`, a `DatePicker` or a `LabeledContent`, or a form's
/// field row — as one place where the focus following the pointer finds the
/// control: a move onto the label offers the control the focus, as a move onto
/// the control does (owner ruling HOVER-FOCUS b). Only the focus: the label
/// moves no value.
///
/// The control is the first focus id the content's regions carry, in the
/// order they were drawn: a `ColorPicker`'s swatch before its channels, a
/// graphical `DatePicker`'s calendar before its time. Content carrying none
/// (a `LabeledContent` of plain text, a disabled control) names nothing. A
/// control in the label itself keeps its own cells, in front of this region.
///
/// The region goes behind the whole content, so the control's regions and
/// any in the label stay in front of it, and is a hover observer that only
/// names the control (`MouseEventDispatcher.filePointerFocusName(_:for:in:)`):
/// it carries no focus id, so the control's own region is still the first
/// with its id, where a reveal and the text cursor go, and it takes no press
/// and no hover from what is behind it. Filed only while the focus follows the
/// pointer.
nonisolated package struct _LabelledControlRow<Content: View>: View, Renderable, Layoutable {
    let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @MainActor package var body: Never { fatalError("_LabelledControlRow renders via Renderable") }

    @MainActor package func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    @MainActor package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIView.renderToBuffer(content, context: context)
        guard !context.isMeasuring, context.environment.focusFollowsPointer == true,
            let dispatcher = context.environment.mouseEventDispatcher,
            buffer.width > 0, buffer.height > 0
        else { return buffer }
        guard let named = buffer.hitTestRegions.lazy.compactMap(\.focusID).first else { return buffer }
        let id = dispatcher.registerHoverObserver(in: context) { _ in false }
        dispatcher.filePointerFocusName(named, for: id, in: context)
        buffer.hitTestRegions.insert(contentsOf: buffer.frameHitRegions(handlerID: id), at: 0)
        return buffer
    }
}

/// Seen through by a container asking for a z-index or an alignment guide, as
/// `_BehindContentTapModifier` is: it draws its content where it is, unchanged,
/// at its own identity.
extension _LabelledControlRow: SingleContentWrapper {
    package var wrappedContent: Content { content }

    package static var _keepsContentGeometry: Bool { true }

    package func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _LabelledControlRow: DrawsContentUnchanged {}
