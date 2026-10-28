//  🖥️ TUI — A Terminal UI framework for Swift
//  StackGlide.swift
//
//  An eager stack's children while a change of layout animates: each drawn
//  where its glide has got to, and a view that has left drawn where it was
//  while its removal plays — SwiftUI's insertion and removal model, measured
//  (owner ruling FB16 (a′), 2026-10-18;
//  `Tools/SwiftUIProbes/Insertion and removal (FB16)/samples.txt`).
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Which children a stack lays out

/// A stack's children: the ones it lays out, and the slots of views that have
/// left and are still playing their removal.
struct StackChildren {
    /// The children the stack lays out, in declaration order.
    var laidOut: [ChildView]
    /// The slots of views still leaving (``ChildView/isDeparting``), in
    /// declaration order: laid out nowhere, drawn where each view last was.
    var departing: [ChildView]
}

/// `content`'s children as an eager stack treats them: a view that has left
/// takes no room, as in SwiftUI, unless the environment holds its room while
/// it leaves (``View/transitionSpace(_:)``).
///
/// One check where nothing is leaving anywhere — every frame of every app but
/// the few a removal plays on — and a scan of the children where something
/// is.
@MainActor
func stackChildren<Content: View>(of content: Content, context: RenderContext) -> StackChildren {
    let children = resolveChildViews(from: content, context: context)
    guard context.leavingTakesNoRoom(among: children)
    else { return StackChildren(laidOut: children, departing: []) }
    return StackChildren(
        laidOut: children.filter { !$0.isDeparting }, departing: children.filter(\.isDeparting))
}

extension RenderContext {
    /// Whether `children` hold the slot of a view still leaving that a
    /// container lays out nowhere: something is leaving here, and the
    /// environment does not hold its room while it does
    /// (``View/transitionSpace(_:)``). One check where nothing is leaving
    /// anywhere, and a scan of the children where something is.
    @MainActor
    func leavingTakesNoRoom(among children: [ChildView]) -> Bool {
        guard let storage = stateStorage, !storage.departures.isEmpty else { return false }
        return environment.transitionSpace == .released && children.contains(where: \.isDeparting)
    }
}

// MARK: - Drawing the children where they are

extension RenderContext {
    /// A stack's children drawn where they are on this frame, or `nil` where
    /// every one of them is at its target and nothing is leaving: the stack
    /// then draws as it always does.
    ///
    /// The canvas is the stack's in-flow size; a child that lies past it —
    /// one gliding in from outside a stack that just shrank, a removed view
    /// whose room has gone — is drawn past it at its place in the stacking
    /// order (``FrameBuffer/layered(_:width:height:splitsOverhang:wakeToken:context:)``).
    /// Children overlap while they move, so they are drawn as a `ZStack` draws
    /// its layers: in ascending z-index, and in declaration order within one.
    /// A view leaving goes beneath the present views of its z-index, which is
    /// where SwiftUI draws it (measured, `Tools/SwiftUIProbes/Insertion and removal (FB16)/samples.txt`: the removed
    /// view's layer is first in its column, under both siblings, whatever its
    /// transition) — and why a `.zIndex` lifts it.
    ///
    /// - Parameters:
    ///   - children: The children laid out.
    ///   - buffers: What each drew, `nil` for a spacer.
    ///   - targets: Where the layout put each of them.
    ///   - departing: The slots of views leaving.
    ///   - width: The stack's in-flow width.
    ///   - height: The stack's in-flow height.
    @MainActor
    package func glidingStackBuffer(
        _ children: [ChildView], buffers: [FrameBuffer?], at targets: [ChildPlacement],
        departing: [ChildView], width: Int, height: Int
    ) -> FrameBuffer? {
        guard let placements = glidingPlacements(of: children, drawing: buffers, at: targets, departing: departing)
        else {
            return nil
        }
        // (z-index, beneath its present siblings, declaration order)
        var layers: [(buffer: FrameBuffer, x: Int, y: Int, order: (Double, Int, Int))] = []
        layers.reserveCapacity(children.count + departing.count + placements.leaving.count)
        for (index, departed) in departing.enumerated() {
            guard let (placement, zIndex) = placements.departing[index] else { continue }
            // At the size the view had, whatever room this stack has now:
            // the room it took is gone, and a stack that held only it was
            // offered none.
            let size = departed.measure(proposal: .unspecified, context: self)
            let picture = departed.render(width: size.width, height: size.height, context: self)
            layers.append((picture, placement.x, placement.y, (zIndex, 0, index)))
        }
        // A branch, a case or a row that has gone, playing its own removal
        // where it was (`ChildFade`): beneath, as a slot is.
        for (index, leaver) in placements.leaving.enumerated() {
            layers.append(
                (leaver.picture, leaver.placement.x, leaver.placement.y, (leaver.zIndex, 0, departing.count + index)))
        }
        for index in children.indices {
            guard var buffer = buffers[index] else { continue }
            // Fading in where it lands, if the change put it here.
            if let presence = placements.presence { buffer = DefaultTransition.faded(buffer, by: presence[index]) }
            let placement = placements.presented[index]
            layers.append((buffer, placement.x, placement.y, (children[index].zIndex, 1, index)))
        }
        layers.sort { $0.order < $1.order }
        return FrameBuffer.layered(
            layers.map { ($0.buffer, $0.x, $0.y) }, width: width, height: height, splitsOverhang: true,
            wakeToken: "stack-base-run-\(identity.path)", context: self)
    }
}

// MARK: - Where a column and a row put their children

/// Where a stack's assembly puts each child, and the size it comes to before
/// the stack's final clamp.
struct StackPlacements {
    var targets: [ChildPlacement]
    var width: Int
    var height: Int
}

extension _VStackCore {
    /// Where `renderClip`'s PASS 3 puts each child: down the column by the
    /// rows each one draws (`buffers`, or a spacer's height), a gap charged
    /// only between two children that draw rows, as `appendVertically` charges
    /// one; across it by the guide run, or by the alignment within
    /// `alignmentWidth`, as `horizontallyAligned(toWidth:alignment:)` places a
    /// narrower child.
    func columnPlacements(
        buffers: [FrameBuffer?], heights: [Int], alignmentWidth: Int, guideRun: AlignmentGuideRun?,
        availableWidth: Int
    ) -> StackPlacements {
        var targets: [ChildPlacement] = []
        targets.reserveCapacity(buffers.count)
        var height = 0
        for index in buffers.indices {
            let rows = buffers[index]?.lines.count ?? heights[index]
            let width = buffers[index]?.width ?? 0
            let x =
                guideRun?.offsets[index]
                ?? (width < alignmentWidth ? alignment.childOffset(childWidth: width, in: alignmentWidth) : 0)
            let y = rows > 0 && height > 0 ? height + spacing : height
            targets.append(ChildPlacement(x: x, y: y))
            if rows > 0 { height = y + rows }
        }
        let width = guideRun.map { min($0.extent, max(0, availableWidth)) } ?? alignmentWidth
        return StackPlacements(targets: targets, width: width, height: height)
    }
}

extension _HStackCore {
    /// Where `renderClip`'s assembly puts each child: along the row by the
    /// columns each one draws (`buffers`, or a spacer's width), a gap charged
    /// only between two children that draw columns, as `appendHorizontally`
    /// charges one; down it by the guide run, or by the alignment within
    /// `rowHeight`, as `verticallyAligned(toHeight:alignment:)` places a
    /// shorter child.
    func rowPlacements(
        buffers: [FrameBuffer?], widths: [Int], gaps: StackGaps, rowHeight: Int, guideRun: AlignmentGuideRun?
    ) -> StackPlacements {
        var targets: [ChildPlacement] = []
        targets.reserveCapacity(buffers.count)
        var width = 0
        var walk = StackGapWalk(gaps)
        var placedIndex = 0
        for index in buffers.indices {
            let columns = buffers[index]?.width ?? widths[index]
            let gap = walk.gap(before: index, extent: columns)
            walk.place(index, extent: columns)
            var y = 0
            if let buffer = buffers[index] {
                y =
                    guideRun?.offsets[placedIndex]
                    ?? (buffer.height < rowHeight
                        ? alignment.childOffset(childHeight: buffer.height, in: rowHeight) : 0)
                placedIndex += 1
            }
            let x = width > 0 && columns > 0 ? width + gap : width
            targets.append(ChildPlacement(x: x, y: y))
            width = x + columns
        }
        return StackPlacements(targets: targets, width: width, height: rowHeight)
    }
}
