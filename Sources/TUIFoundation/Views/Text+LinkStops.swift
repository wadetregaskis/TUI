//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+LinkStops.swift
//
//  A link inside a `Text` as a control (the owner's ruling B85-KEYBOARD,
//  2026-10-23, "full control"): each link is a focus stop that Tab reaches,
//  breathes while it holds the focus as a `Link` does, and does what a `Link`
//  does on Return, Space or a click — opens or copies its destination and
//  shows it in a popover — with `Link`'s menu on Shift+F10, the Menu key or a
//  right-click.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

// MARK: - Where the links were drawn

/// The cells each link run of a text was drawn in, noted as the text draws
/// (`Text.rendered(context:linkSpans:routesLinks:)`).
///
/// A link is a run of the text, and the text wraps, so a link is one span
/// per row it reaches: a span is a row and the columns of one fragment of
/// that row.
final class TextLinkSpans {
    /// One row's piece of a link.
    struct Span: Equatable {
        var row: Int
        let column: Int
        let width: Int

        /// The span as a rectangle of cells.
        var rect: CellRect { CellRect(x: column, y: row, width: width, height: 1) }
    }

    /// Each link run's spans, by the run's index, top row first.
    private(set) var byRun: [Int: [Span]] = [:]

    /// Notes where each link run's fragments are in `lines`, the text's laid
    /// out lines, attributed to `runs` as the drawing attributes them
    /// (`TextRunAttribution`, from `runTexts`, the runs' words as drawn): by
    /// line, with the columns the fragments before it take, as the alpha
    /// claims count them.
    ///
    /// The attribution is made again here rather than handed over from the
    /// drawing, which keeps the drawing's signature as it was; only a text
    /// whose links are stops pays it, once a frame.
    func note(_ lines: [String], runTexts: [String], runs: [Text.Run]) {
        byRun.removeAll(keepingCapacity: true)
        var cursor = (run: 0, offset: 0)
        let attributed = lines.map { TextRunAttribution.fragments(of: $0, runTexts: runTexts, cursor: &cursor) }
        for (row, line) in attributed.enumerated() {
            var column = 0
            for fragment in line {
                let width = fragment.text.strippedLength
                defer { column += width }
                guard width > 0, runs.indices.contains(fragment.run), runs[fragment.run].link != nil else { continue }
                byRun[fragment.run, default: []].append(Span(row: row, column: column, width: width))
            }
        }
    }

    /// Moves each span from its line to its row, `spacing` blank rows
    /// standing between lines (`LineSpacingRows`).
    func space(by spacing: Int) {
        guard spacing > 0 else { return }
        for run in byRun.keys {
            byRun[run] = byRun[run]?.map { span in
                var spaced = span
                spaced.row *= spacing + 1
                return spaced
            }
        }
    }
}

// MARK: - Drawing a text

extension Text {
    /// The text drawn.
    ///
    /// - Parameters:
    ///   - linkSpans: Where to note the cells each link run is drawn in, for
    ///     the link stops (`TextLinkStops`); `nil` to note nothing.
    ///   - routesLinks: Whether a text whose links are focus stops here is
    ///     drawn by them: `false` when they are what is drawing it.
    func rendered(context: RenderContext, linkSpans: TextLinkSpans?, routesLinks: Bool) -> FrameBuffer {
        // A text whose links are focus stops is drawn by them, which draw it
        // through here again with `routesLinks` off (decisions B85). Only a
        // text with runs can have a link: every other pays a nil check.
        if routesLinks, let runs, let routed = TextLinkStops.render(self, runs: runs, context: context) {
            return routed
        }
        var shadowing: Paint?
        let buffer = drawn(context: context, shadowing: &shadowing, linkSpans: linkSpans, routesLinks: routesLinks)
        guard let shadowing else { return buffer }
        // A shadowed foreground style's shadows, cast from the letters drawn
        // in it (``ShapeStyle/shadow(_:)``).
        return buffer.castingShadows(of: shadowing, context: context, owner: Text.self)
    }
}

// MARK: - The route

/// Whether a text's links are focus stops here, and the drawing of one whose
/// links are.
@MainActor
enum TextLinkStops {
    /// The text drawn with its links as focus stops, or `nil` where they are
    /// none: the text has no link, or this is a measure, or the links are not
    /// controls here.
    ///
    /// Not controls:
    ///
    /// - where the destination is written on the row
    ///   (``LinkDisplay/urlInParentheses``, ``LinkDisplay/urlOnly``), as a
    ///   ``Link`` is not one there;
    /// - in a disabled subtree, or one whose focus is suppressed
    ///   (`.focusable(false)`, `.allowsHitTesting(false)`);
    /// - in a list's or table's row, where the list is the stop and the row
    ///   reports to it (as a context menu in a row does);
    /// - outside a running app, with no focus system to be stops in.
    static func render(_ text: Text, runs: [Text.Run], context: RenderContext) -> FrameBuffer? {
        guard !context.isMeasuring, runs.contains(where: { $0.link != nil }) else { return nil }
        let environment = context.environment
        guard environment.linkDisplay == .popover, environment.isEnabled, !environment.isFocusSuppressed,
            environment.focusManager != nil, environment.mouseEventDispatcher != nil, context.stateStorage != nil,
            environment.listRowEditRestrictions?.currentRowIndex == nil
        else { return nil }
        // A child identity for the links' state: the text is a leaf, and
        // whatever renders it may keep `@State` at the text's own identity.
        return TUIView.renderToBuffer(
            _TextLinks(text: text), context: context.withChildIdentity(type: _TextLinks.self, index: 0))
    }

    /// The id of the focus stop of the link at `run` of the text drawn at
    /// `identity`: `text-link-<identity path>#<run>`.
    static func focusID(identity: ViewIdentity, run: Int) -> String {
        "text-link-\(identity.path)#\(run)"
    }
}

// MARK: - State across frames

/// What a text's link stops keep from one frame to the next.
///
/// A reference, held in `@State`, so the closures made in one frame read
/// what the next frame drew: where the links are, for the popover's anchor,
/// and which holds the focus, for the menu, which opens on the focused link.
@MainActor
final class TextLinkStopState {
    /// Each link's spans as last drawn on the live page, by run.
    var spans: [Int: [TextLinkSpans.Span]] = [:]

    /// The link that held the focus when the page last drew, by run.
    var focused: Int?

    /// Each link's gate against a held Return's repeats, by run
    /// (``LinkActivationGate``).
    private var gates: [Int: LinkActivationGate] = [:]

    /// The gate of the link at `run`.
    func gate(_ run: Int) -> LinkActivationGate {
        if let gate = gates[run] { return gate }
        let gate = LinkActivationGate()
        gates[run] = gate
        return gate
    }

    /// Where the popover of the link at `run` attaches: its first span, or
    /// the text's origin before it has drawn.
    func anchor(of run: Int?) -> CellRect {
        guard let run, let first = spans[run]?.first else { return CellRect(x: 0, y: 0, width: 1, height: 1) }
        return first.rect
    }
}

// MARK: - The links' presentations

/// A text whose links are controls: the text and its stops
/// (``_TextLinksCore``), the menu a link opens, and the popover that shows a
/// link's destination — `Link`'s two presentations, for the link that holds
/// the focus.
private struct _TextLinks: View {
    let text: Text

    /// The run whose destination the popover shows, if it is up.
    @State private var shown: Int?

    @State private var stops = TextLinkStopState()

    @Environment(\.openURL) private var openURL
    @Environment(\.clipboardAccess) private var clipboard
    @Environment(\.linkActivation) private var activation

    var body: some View {
        // Resolved now, in the render, and captured: a closure that ran later
        // and read `@Environment` would read it outside a render pass.
        let open = openURL
        let clipboard = self.clipboard
        let activation = self.activation
        let stops = self.stops
        let showing = $shown
        // As `Link`'s activation: opens or copies, as `.linkActivation(_:)`
        // says, and either way raises the popover, which shows where the link
        // goes on a machine that may not be the user's.
        let activate: (Int, URL) -> Void = { run, destination in
            guard stops.gate(run).allows(nowNanos: MonotonicClock.nowNanoseconds) else { return }
            switch activation {
            case .open: open(destination)
            case .copy: _ = clipboard.write(destination.absoluteString, announcingSuccess: true)
            }
            showing.wrappedValue = run
        }
        let destination = shown.flatMap { run in text.runs?.indices.contains(run) == true ? text.runs?[run].link : nil }
        let copyLink = LocalizationService.shared.string(for: LocalizationKey.Menu.copyLink)
        return PopoverPresentationModifier(
            content: ContextMenuModifier(
                content: _TextLinksCore(text: text, stops: stops, activate: activate),
                menuItems: _TextLinkMenu(
                    text: text, stops: stops, clipboard: clipboard,
                    show: { if let run = stops.focused { showing.wrappedValue = run } }),
                keyboardRoute: .contentStopRegions),
            isPresented: Binding(get: { showing.wrappedValue != nil }, set: { if !$0 { showing.wrappedValue = nil } }),
            // `verbatim`: a URL is content, not a lookup key. A right-click on
            // it offers Copy Link, as on a `Link`'s.
            popover: ContextMenuModifier(
                content: Text(verbatim: destination?.absoluteString ?? ""),
                menuItems: Button(copyLink) { [clipboard] in
                    if let destination { _ = clipboard.write(destination.absoluteString, announcingSuccess: true) }
                },
                keyboardRoute: .contentStops),
            attachmentAnchor: .rect(.rect(stops.anchor(of: shown))),
            arrowEdge: .bottom,
            ownsPresentation: true)
    }
}

extension _TextLinks: ResolvesOwnEnvironment {
    func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _openURL.resolveEnvironment(environment)
        _clipboard.resolveEnvironment(environment)
        _activation.resolveEnvironment(environment)
    }
}

/// The menu of the link that holds the focus: `Link`'s, with Show Link and
/// the copies. A right-click on a link gives it the focus before the menu
/// opens (``_TextLinksCore``), so the focused link is the one asked about.
private struct _TextLinkMenu: View {
    let text: Text
    let stops: TextLinkStopState
    let clipboard: ClipboardAccess
    let show: () -> Void

    var body: some View {
        if let run = stops.focused, let runs = text.runs, runs.indices.contains(run), let destination = runs[run].link {
            LinkContextMenu(
                destination: destination, label: Self.label(runs[run].text), clipboard: clipboard, show: show)
        }
    }

    /// The link's words, for Copy Label and Copy as Markdown.
    private static func label(_ words: String) -> LinkLabelText {
        let label = LinkLabelText()
        label.text = words.trimmingCharacters(in: .whitespaces)
        return label
    }
}

// MARK: - The stops

/// The text, and a focus stop for each of its links: registered with the
/// focus system, breathing while it holds the focus, and answering the
/// pointer over each row's piece of it.
private struct _TextLinksCore: View, Renderable {
    let text: Text
    let stops: TextLinkStopState
    let activate: (Int, URL) -> Void

    var body: Never {
        fatalError("_TextLinksCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let spans = TextLinkSpans()
        let drawn = text.rendered(context: context, linkSpans: spans, routesLinks: false)
        // Noted by line; a line is a row apart from the spacing between them,
        // which is the environment's, as `Text` reads it.
        spans.space(by: context.environment.lineSpacing)
        guard !context.isMeasuring, let runs = text.runs else { return drawn }
        // The page beneath an open menu is a picture drawn unfocused into a
        // throwaway focus system: what it says is not where the focus is.
        let live = context.environment.focusManager?.isBackdrop != true
        var focused: Int?
        var regions: [HitTestRegion] = []
        for run in spans.byRun.keys.sorted() {
            guard let destination = runs[run].link, let runSpans = spans.byRun[run], !runSpans.isEmpty else { continue }
            let focusID = TextLinkStops.focusID(identity: context.identity, run: run)
            let activate = self.activate
            FocusRegistration.register(
                context: context,
                handler: ActionHandler(focusID: focusID, action: { activate(run, destination) }),
                focusID: focusID)
            if FocusRegistration.isFocused(context: context, focusID: focusID) { focused = run }
            let stops = self.stops
            regions += Self.pointerRegions(
                runSpans, focusID: focusID, activate: { activate(run, destination) },
                pointedAt: { stops.focused = run }, context: context)
        }
        if live {
            stops.spans = spans.byRun
            stops.focused = focused
        }
        var buffer = drawn
        if let focused, let focusedSpans = spans.byRun[focused] {
            buffer = breathing(
                focused, rows: Set(focusedSpans.map(\.row)), ownRuns: drawn.animatedCells.count, runs: runs,
                context: context)
        }
        buffer.hitTestRegions += regions
        return buffer
    }

    /// The text with the link at `run` breathing, as a focused `Link`'s words
    /// do: drawn once for each colour of the breath, its rows that the link
    /// reaches replayed from those drawings (``BreathingLabel``). The other
    /// rows stand still.
    ///
    /// - Parameter ownRuns: How many animated runs the text draws of its own
    ///   (a live date in it, say), which the breath's follow.
    private func breathing(
        _ run: Int, rows: Set<Int>, ownRuns: Int, runs: [Text.Run], context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let resting = (runs[run].styleStatingLink(in: context.environment).foregroundColor ?? .palette.accent)
            .resolve(with: palette)
        let ends = BorderRenderer.breathEnds(from: resting, on: context.environment.enclosingSurface)
        let cycle = context.environment.selectionEmphasis.cycle(true)
        var buffer = BreathingLabel.draw(ends: ends, cycle: cycle, indicating: true, isMeasuring: false) { colour in
            text.recolouringRun(run, to: colour).rendered(context: context, linkSpans: nil, routesLinks: false)
        }
        // The breath's runs come after the text's own; only the link's rows
        // need one.
        let own = buffer.animatedCells.prefix(ownRuns)
        let breath = buffer.animatedCells.dropFirst(ownRuns).filter { rows.contains($0.offsetY) }
        buffer.animatedCells = Array(own) + breath
        return buffer
    }

    /// One region per span of a link, each answering the pointer over it: a
    /// press gives the link the focus, and the release over it activates it,
    /// as a button's click does; a secondary press gives it the focus and
    /// passes on, so the menu beneath opens on it (`ContextMenuModifier`'s
    /// `.contentStopRegions`).
    ///
    /// - Parameter pointedAt: Notes the link as the one the menu is about at
    ///   once, as the press arrives: the page beneath the open menu is drawn
    ///   into a throwaway focus system, so the frame that draws the menu
    ///   cannot say which link took the focus.
    private static func pointerRegions(
        _ spans: [TextLinkSpans.Span], focusID: String, activate: @escaping () -> Void,
        pointedAt: @escaping () -> Void, context: RenderContext
    ) -> [HitTestRegion] {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return [] }
        let focusManager = context.environment.focusManager
        return spans.map { span in
            let width = span.width
            // Weak: the dispatcher holds this handler, and the focus manager
            // must not live on in it after its loop.
            let handlerID = dispatcher.register(in: context) { [weak focusManager] event in
                let secondary = event.button == .right || (event.button == .left && event.ctrl)
                switch event.phase {
                case .pressed where secondary:
                    focusManager?.focus(id: focusID)
                    pointedAt()
                    return false
                case .pressed where event.button == .left:
                    focusManager?.focus(id: focusID)
                    return true
                case .released where event.button == .left && !event.ctrl:
                    // Over the piece pressed, as a button's click must end
                    // over the button.
                    if event.y == 0, (0..<width).contains(event.x) { activate() }
                    return true
                default:
                    return false
                }
            }
            // A click (decisions B89): what ranks it against a gesture around
            // the text. Its own test above stays — a release over another
            // piece of the same link is no click on this one.
            dispatcher.fileClickRecognizer(.plain, for: handlerID, in: context)
            return HitTestRegion(
                offsetX: span.column, offsetY: span.row, width: width, height: 1, handlerID: handlerID,
                focusID: focusID)
        }
    }
}

// MARK: - Recolouring a link

extension Text {
    /// This text with the run at `index` drawn in `colour`: a link's words at
    /// one moment of its breath.
    fileprivate func recolouringRun(_ index: Int, to colour: Color) -> Text {
        guard var runs, runs.indices.contains(index) else { return self }
        let run = runs[index]
        var style = run.style
        style.foregroundColor = colour
        runs[index] = Run(text: run.text, style: style, live: run.live, link: run.link, attributes: run.attributes)
        var recoloured = self
        recoloured.runs = runs
        return recoloured
    }
}
