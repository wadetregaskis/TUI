//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationBar.swift
//
//  The bar a pushed screen sits under: the trail of titles that got there (or
//  ‹ Back and the title), the rule beneath, and Escape going back. Drawn by
//  `NavigationStack` over the screen on top of its path, and by a collapsed
//  `NavigationSplitView` over the column on top of its stack.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

/// The navigation bar over a pushed screen, going back through `coordinator`.
@MainActor
struct NavigationBar {
    /// The bar's height: the title row plus the rule under it.
    ///
    /// A constant, deliberately. Chrome whose height depends on the content it
    /// sits above cannot be laid out in one pass — the content's height would
    /// have to be known to size the bar, and the bar's height has to be known
    /// to give the content its space. A long title truncates instead.
    static var height: Int { 2 }

    /// The path the bar goes back along, and whose titles its trail names.
    let coordinator: NavigationCoordinator

    /// The navigation bar, pinned to `ChromeStyle.barHeight(contentRows:)` rows.
    /// `escapeHandlerSlot` is the key dispatcher's handler count from before the
    /// screen rendered: where the bar's Escape handler is filed.
    func render(
        title: String, subtitle: String, hidesBack: Bool, width: Int, escapeHandlerSlot: Int,
        context: RenderContext
    ) -> FrameBuffer {
        let coordinator = coordinator
        // The Back button is a real `Button`: a Tab stop, clickable, and
        // styled by whatever `.buttonStyle` is in effect above the stack.
        let back = "‹ " + LocalizationService.shared.string(for: LocalizationKey.Button.back)
        let barContext = context.withAvailableSize(width: width, height: Self.height)

        // Escape goes back, after the focused control has had its chance at the
        // key (the status-bar claim re-routes ESC through the focus system
        // first, so a list clearing its selection still wins). The claim is the
        // lightweight kind: a pushed screen is not a modal, so the app's other
        // shortcuts keep working.
        // Only when nothing else claimed ESC this frame: the content renders
        // BEFORE the bar (the bar needs the title preference the content
        // publishes), so an open menu, popover or drop-down inside it has
        // already posted its own close label — and this write clobbered it,
        // showing "⎋ go back" under an open menu whose ESC closes the menu.
        //
        // A presented sheet or alert claims ESC the OTHER way: as a dismiss item
        // of its own input-grabbing section, never through the label. The label
        // test alone let this write go-back over it, and the status bar renames
        // every escape item to the claimed label — the dialog read "⎋ go back"
        // while ESC closed the dialog. With dismissal disabled the dialog
        // publishes no item, and go-back was the only escape entry on the bar,
        // for a key that did nothing: the dialog's grab keeps the handler below
        // from running. So a modal section holding the keyboard is a claim too;
        // with none written, the dialog's own item is what the bar shows and
        // what ESC fires. A presenter rendered AFTER the stack marks its section
        // too late for this to see; it withdraws this claim instead, as it
        // takes the keyboard (`StatusBarState.withdrawEscapeClaim`).
        if !context.isMeasuring, barContext.environment.statusBar?.hasEscapeClaimHere != true,
            barContext.environment.focusManager?.activeSectionIsModal != true
        {
            // The claim and the handler are both per-frame: the render loop
            // resets the label and empties the dispatcher before every pass, so a
            // stack served from a value memo left Escape unclaimed and unhandled.
            // Declared, as every other writer to those registries is.
            barContext.environment.volatileReadTracker?.recordRenderSideEffect()
            barContext.environment.statusBar?.escapeLabelOverride =
                LocalizationService.shared.string(for: LocalizationKey.StatusBar.goBack)
            barContext.environment.statusBar?.escapeClaimGrabsInput = false
            // Filed at the slot taken before the screen rendered, not appended.
            // The dispatcher asks the most recent registration first, so an
            // appended pop outranked every handler the screen had just
            // registered: a screen's `.onKeyEvent(keys: [.escape])` never ran,
            // and a screen that must not be left (the remedy
            // `navigationBarBackButtonHidden(_:)` documents) could not say so.
            // Filed ahead of the screen, going back is what ESC does when
            // nothing ON the screen wants it; a handler AROUND the stack (a
            // page returning to its menu on ESC) registered before the slot,
            // and still loses to going back.
            //
            // Only the handler moves. The label claim above stays after the
            // screen, because it has to see whether something inside claimed
            // ESC first; hoisted, it would also lower the grabs-input flag
            // under a drop-down that has yet to post its own claim.
            //
            // In a pane — a live sheet docked under the page — only while the
            // focus is in that pane, as its claim holds only then: with the
            // focus on the page, Escape is the page's (A19, owner Q6).
            let focusManager = barContext.environment.focusManager
            let pane = focusManager?.currentPaneID
            barContext.environment.keyEventDispatcher?.insertHandler(
                at: escapeHandlerSlot,
                sectionID: barContext.environment.activeFocusSectionID
            ) { event in
                guard event.key == .escape, focusManager?.activePaneID == pane else { return false }
                coordinator.pop()
                return true
            }
        }

        // The title takes whatever the button leaves, truncated rather than
        // wrapped: the bar's height is fixed, so it has nowhere to wrap to.
        // Measure the BUTTON, not the bar — the bar ends in a `Spacer`, so
        // measuring it answers "the whole width", which left the title no room
        // at all and silently truncated it to nothing.
        let backWidth =
            hidesBack
            ? 0
            : measureChild(
                backButton(back, coordinator: coordinator),
                proposal: ProposedSize(width: nil, height: nil),
                context: barContext.withChildIdentity(type: NavigationBarID.self)
            ).width
        // Crumbs when they fit, the Back button when they do not. `backWidth`
        // is what a bar with the single button would need, so it doubles as the
        // budget the trail has to beat.
        coordinator.recordTitle(title, atDepth: coordinator.depth)
        // With the button hidden the trail goes too: every crumb in it pops, so
        // keeping it would leave three ways back where the screen asked for
        // none. The title then has the whole bar rather than what the button
        // left it.
        let titled = navigationBar(
            back: back,
            hidesBack: hidesBack,
            title: title.truncatedToWidth(max(0, width - backWidth - 1)),
            subtitle: subtitle,
            crumbs: hidesBack
                ? nil
                : NavigationCrumbs.trail(
                    titles: coordinator.titles(upTo: coordinator.depth), fittingWidth: width),
            coordinator: coordinator)

        let rendered = TUIkitView.renderToBuffer(
            titled, context: barContext.withChildIdentity(type: NavigationBarID.self))
        return Self.padded(rendered, toWidth: width, height: Self.height)
    }

    /// The bar's view: the crumb trail (or the Back button and title when the
    /// trail will not fit), and the rule beneath.
    private func navigationBar(
        back: String, hidesBack: Bool, title: String, subtitle: String,
        crumbs: [NavigationCrumbs.Crumb]?, coordinator: NavigationCoordinator
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if let crumbs {
                    // One closure parameter, NOT `{ _, crumb in`. The closure is
                    // not the bug: `{ _, crumb in` is converted to a function of
                    // one tuple parameter, and swift.org's Swift 6.2.4 (an
                    // assertions build) aborts in SILGen ("no generic
                    // environment provided for type with type parameters") on a
                    // function conversion that needs a reabstraction thunk, in
                    // a generic context (`_NavigationStackCore<Root>`, where
                    // this bar was drawn until it moved here), of a function
                    // whose opaque result does not use that context's
                    // parameters (`crumbView`). One parameter needs no conversion. Xcode's
                    // 6.2.4 compiles either spelling. See
                    // Tools/CompilerBugs/README.md, section 4.
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { pair in
                        crumbView(pair.element, coordinator: coordinator)
                    }
                } else if hidesBack {
                    Text(title).bold()
                } else {
                    backButton(back, coordinator: coordinator)
                    Text(" ")
                    Text(title).bold()
                }
                // After the title, in what the title and the trail leave: the
                // lowest priority in the row and one line, so it truncates
                // first and the bar keeps its height.
                //
                // No `Spacer` after it: one would be of a HIGHER priority than
                // the subtitle, and a stack offers its higher priorities space
                // first, so the spacer would take the whole slack and leave
                // the subtitle its `…` — as SwiftUI's would. The bar is padded
                // to the full width below instead.
                if !subtitle.isEmpty {
                    // The gap on its own, so truncating the subtitle cannot
                    // eat it.
                    Text(verbatim: "  ")
                    Text(verbatim: subtitle)
                        .foregroundStyle(Color.palette.foregroundSecondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            Divider()
        }
    }

    /// A crumb: a `Button` when it goes somewhere, plain text when it is the
    /// separator or the screen you are already on.
    ///
    /// Only the clickable ones are Buttons, so only they are Tab stops — the
    /// separators would otherwise put dead entries in the focus ring, and the
    /// current screen is not somewhere to navigate to.
    ///
    /// Three weights, loudest last: the punctuation recedes, a screen you can
    /// go back to is quiet until the focus or the pointer lifts it
    /// (``_NavigationCrumbButtonStyle``), and the screen you are on is bold.
    @ViewBuilder
    private func crumbView(_ crumb: NavigationCrumbs.Crumb, coordinator: NavigationCoordinator) -> some View {
        if let depth = crumb.popsTo {
            // The lead rides in the label: this style reserves no cells of its
            // own, so nothing else would space the trail.
            Button(NavigationCrumbs.lead + crumb.label) { coordinator.pop(coordinator.depth - depth) }
                .buttonStyle(_NavigationCrumbButtonStyle())
        } else if crumb.isChrome {
            Text(NavigationCrumbs.lead + crumb.label)
                .foregroundStyle(Color.palette.foregroundTertiary)
        } else {
            Text(NavigationCrumbs.lead + crumb.label).bold()
        }
    }

    /// The **‹ Back** control — a real `Button`, so it is a Tab stop, it takes
    /// a click, and `.buttonStyle(_:)` above the stack restyles it.
    private func backButton(_ label: String, coordinator: NavigationCoordinator) -> some View {
        Button(label) { coordinator.pop() }
            .buttonStyle(.borderless)
    }

    /// Pads (or clips) a buffer to exactly `width` × `height`, keeping its
    /// overlays and hit-test regions — `replacingLines` is what preserves them.
    static func padded(_ buffer: FrameBuffer, toWidth width: Int, height: Int) -> FrameBuffer {
        var lines = buffer.lines.prefix(height).map { line -> String in
            let visible = line.strippedLength
            return visible < width ? line + String(repeating: " ", count: width - visible) : line
        }
        let blank = String(repeating: " ", count: width)
        while lines.count < height { lines.append(blank) }
        return buffer.replacingLines(Array(lines))
    }
}

/// Identity tag for the navigation bar, keeping the Back button's focus
/// registration in one stable place across pushes.
private enum NavigationBarID {}
