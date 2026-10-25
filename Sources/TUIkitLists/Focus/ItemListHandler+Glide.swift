//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+Glide.swift
//
//  A `List`'s or a `Table`'s animated programmatic scroll (decisions
//  B27-ANIMATING, piece 6): a `scrollTo` or a bound `.scrollPosition` request
//  made inside `withAnimation` glides there a row at a time, as a
//  `ScrollView`'s glides a line at a time, and the list reports its scroll
//  phases to `onScrollPhaseChange`, as SwiftUI's list — a scroll view there —
//  does. The stepping is `ScrollGlide.swift`'s, shared by every scrollable.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

extension ItemListHandler: ScrollPhaseReporting {
    /// A scrollbar held, a drag's auto-scroll, or a key's glide
    /// (``ScrollPhaseReporting``): the user's scroll goes on though no step
    /// has come.
    package var holdsUserScroll: Bool {
        scrollbarDragGrab != nil || scrollbarRepeat != nil || isAutoScrolling || glide?.isKeyboard == true
    }
}

// MARK: - Requests

extension ItemListHandler {
    /// Places this frame's programmatic requests, before the offset settles,
    /// in order: a glide in flight steps to this frame's row and lands when it
    /// is done; then a parked `scrollTo`; then what a bound `.scrollPosition`
    /// asks for (``applyScrollPosition(rowIndex:context:)``). Each glides when
    /// it was made inside an animation and jumps otherwise. `rowIndex` finds
    /// a row by the key a request names it by. Render passes only.
    ///
    /// The focus and the selection do not move, gliding or not, as
    /// ``scroll(toRow:anchor:)`` promises.
    @MainActor
    package func resolveScrollRequests(rowIndex: (String) -> Int?, context: RenderContext) {
        guard !context.isMeasuring else { return }
        if glide != nil { settleGlide(rowIndex: rowIndex, context: context) }
        if let request = pendingScrollTo {
            pendingScrollTo = nil
            if let index = rowIndex(request.key) {
                placeProgrammatically(landing: .seek(request), context: context) {
                    scroll(toRow: index, anchor: request.anchor)
                }
            }
        }
        applyScrollPosition(rowIndex: rowIndex, context: context)
    }

    /// Runs `place`, a programmatic placement, as a glide when this frame's
    /// transaction animates — the offset put back where the list is drawn,
    /// and the rows between gliding by — and as the jump it is otherwise,
    /// which stops any glide in flight. A second request mid-glide glides on
    /// from the row the first is drawn on, at rest.
    ///
    /// A list glides a row at a time, where its wheel steps a line: a row's
    /// height is known only by building it, and a glide past rows it never
    /// draws must not build them to count their lines. The landing puts the
    /// list exactly where the request does (`landing`), the lines of a tall
    /// row scrolled off its top included. A placement that moves the list
    /// within its top row alone jumps.
    @MainActor
    func placeProgrammatically(landing: ScrollGlide.Landing, context: RenderContext, _ place: () -> Void) {
        let start = (row: scrollOffset, subRowLines: scrollTopClipLines)
        place()
        let target = scrollOffset
        guard let animation = context.scrollGlideAnimation, target != start.row else {
            stopGlide()
            return
        }
        (scrollOffset, scrollTopClipLines) = (start.row, start.subRowLines)
        let began = beginGlide(
            to: target, animation: animation, landing: landing, viewport: glideViewport(context),
            context: context)
        if began { phase = .animating }
    }

    /// Steps a glide in flight to this frame's row, and lands it when its
    /// animation is done — or at once, when the list has changed size under
    /// it — applying its request once more, unanimated: the row sought again,
    /// which corrects rows that arrived between the viewport and it, or the
    /// edge, the line or the place. A `scrollTo` made since the last frame
    /// supersedes a re-seek. Landed, the list is idle again, or — a key's
    /// glide — quiet from here.
    @MainActor
    private func settleGlide(rowIndex: (String) -> Int?, context: RenderContext) {
        let keyboard = glide?.isKeyboard == true
        // Held only for the call: no cycle to break.
        let stepRows: (Int) -> Int = { delta in
            let before = self.scrollOffset
            self.scrollTopClipLines = 0
            self.scroll(by: delta)
            return self.scrollOffset - before
        }
        guard let landing = advanceGlide(viewport: glideViewport(context), context: context, step: stepRows)
        else { return }
        if phase == .animating { phase = .idle }
        if keyboard { lastUserScrollNanos = phaseNow() }
        switch landing {
        case .seek(let request):
            guard pendingScrollTo == nil, let index = rowIndex(request.key) else { return }
            scroll(toRow: index, anchor: request.anchor)
        case .offset(let line):
            scroll(toLine: line)
        case .top:
            scroll(toRow: 0, anchor: .top)
        case .bottom:
            scroll(toRow: itemCount - 1, anchor: .bottom)
        case .rowPosition(let row, let subRowLines):
            (scrollOffset, scrollTopClipLines) = (row, subRowLines)
            clampScrollOffset()
            clampTopClip()
        case .distance:
            break
        }
    }

    /// The area a glide starts in: the width the list is offered and the
    /// lines its rows have. A change of either lands the glide at once.
    @MainActor
    private func glideViewport(_ context: RenderContext) -> CellSize {
        CellSize(width: context.availableWidth, height: rowLineBudget)
    }

    /// Stops a glide in flight where it stands, and returns the list to
    /// `.idle` from `.animating`: the cursor moved, and showing it is what
    /// the user now asks for.
    func stopGlide() {
        guard glide != nil else { return }
        glide = nil
        if phase == .animating { phase = .idle }
    }
}

// MARK: - The frame's end

extension ItemListHandler {
    /// What a render does once the list's offset has settled: asks for the
    /// frame a glide in flight next needs, and reports the phase to the
    /// `onScrollPhaseChange` observers the list claims — nothing without one.
    @MainActor
    func finishScrollFrame(context: RenderContext) {
        if glide != nil { requestGlideFrame(context: context) }
        context.reportScrollPhase(of: self) { phaseGeometry(context) }
    }

    /// The geometry a phase change is reported with: the rows' lines as the
    /// container, at the width the list is offered, and the content as the
    /// lines the rows measure. A list reports no `onScrollGeometryChange` of
    /// its own, and its offset here counts the rows above the top one a line
    /// each — exact for rows of one line — rather than build them to measure
    /// them.
    @MainActor
    private func phaseGeometry(_ context: RenderContext) -> ScrollGeometry {
        let width = max(0, context.availableWidth)
        return ScrollGeometry(
            contentOffset: CellPoint(x: 0, y: scrollOffset + scrollTopClipLines),
            contentSize: CellSize(width: width, height: contentHeight ?? itemCount),
            contentInsets: EdgeInsets(),
            containerSize: CellSize(width: width, height: rowLineBudget))
    }
}
