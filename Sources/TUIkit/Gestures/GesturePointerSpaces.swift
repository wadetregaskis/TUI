//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GesturePointerSpaces.swift
//
//  Which named coordinate spaces a gesture reports pointer locations in, so
//  the view it is attached to can be found in them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Reporting

/// A gesture that reports pointer locations in a coordinate space of its own
/// choosing — `DragGesture`, `SpatialTapGesture` — or one made of such
/// gestures, which reports what its parts do.
///
/// A location in the view's own space or the global one is arithmetic on the
/// event. One in a NAMED space (`.named(_:)`, `.scrollView`) needs to know
/// where the view is in that space, which only the view that owns the space
/// can say: the attachment stamps a geometry marker for the owner to find
/// (`GeometryCoordinator`), and the location is converted with what the owner
/// found when the frame the event arrives over was drawn.
@MainActor
protocol PointerSpaceReporting {
    /// The spaces this gesture's parts report locations in.
    var pointerSpaces: [CoordinateSpace] { get }
}

/// The named spaces `gesture` reports locations in — what its attachment must
/// be found in. A gesture of the app's own reports what its `body` does.
@MainActor
func namedPointerSpaces<G: Gesture>(of gesture: G) -> [CoordinateSpace] {
    let spaces: [CoordinateSpace]
    if let reporting = gesture as? any PointerSpaceReporting {
        spaces = reporting.pointerSpaces
    } else if G.Body.self == Never.self {
        return []
    } else {
        spaces = namedPointerSpaces(of: gesture.body)
    }
    var named: [CoordinateSpace] = []
    for space in spaces {
        guard case .named = space, !named.contains(space) else { continue }
        named.append(space)
    }
    return named
}

extension DragGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { [coordinateSpace] }
}

extension SpatialTapGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { [coordinateSpace] }
}

extension SimultaneousGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: first) + namedPointerSpaces(of: second) }
}

extension SequenceGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: first) + namedPointerSpaces(of: second) }
}

extension ExclusiveGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: first) + namedPointerSpaces(of: second) }
}

extension _EndedGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: content) }
}

extension _ChangedGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: content) }
}

extension _MapGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: content) }
}

extension _ModifiersGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: content) }
}

extension GestureStateGesture: PointerSpaceReporting {
    var pointerSpaces: [CoordinateSpace] { namedPointerSpaces(of: base) }
}

extension AnyGesture: PointerSpaceReporting {}

extension Optional: PointerSpaceReporting where Wrapped: Gesture {
    var pointerSpaces: [CoordinateSpace] {
        switch self {
        case .some(let wrapped): namedPointerSpaces(of: wrapped)
        case .none: []
        }
    }
}

// MARK: - Converting

/// How a pointer location measured from a view's own top-left becomes one in
/// another space, at the time an event arrives.
///
/// Made each frame by the view handling the pointer — a gesture's attachment,
/// `onContinuousHover`, `onMouseEvent` — for the space it was asked to report
/// in: nothing for `.local`; the region's composited origin for `.global`
/// (`RegionOrigin`); for a named space, where the space's owner found the
/// view's geometry marker (`GeometryAsk`, role `.pointer`). A name nothing
/// declared around the view is answered in the global space, as SwiftUI's is
/// — and so is a name no owner has found the view in, its marker dropped on
/// the way up (the app header's content, a `Table` cell): the global space,
/// for hover and mouse handlers as for a gesture (`GesturePointer`), never the
/// view's own.
final class PointerSpaceOrigin: @unchecked Sendable {
    private let region: RegionOrigin?
    private let ask: GeometryAsk?

    /// - Parameters:
    ///   - spaces: The named spaces to find the view in.
    ///   - global: Whether `.global` is asked too.
    init?(named spaces: [CoordinateSpace], global: Bool, context: RenderContext) {
        guard let dispatcher = context.environment.mouseEventDispatcher, global || !spaces.isEmpty else {
            return nil
        }
        // For `.global`, and for a named space's fallback to it — which a
        // handler that says where its region is (`handlerID`) can answer; a
        // gesture's locations fall back through `GesturePointer` instead.
        region = global || !spaces.isEmpty ? RegionOrigin(dispatcher: dispatcher) : nil
        if !spaces.isEmpty, let ask = context.makeGeometryAsk(role: .pointer) {
            for space in spaces { ask.want(space) }
            self.ask = ask
            // The ask is made afresh each frame, and an event converts with
            // the frame's own: a memo serving this view's subtree would hand
            // the next event a stale one, so nothing above may keep it.
            context.environment.volatileReadTracker?.recordUnkeyedRead()
        } else {
            self.ask = nil
        }
    }

    /// The id of the region whose composited origin is the global answer.
    var handlerID: HitTestRegion.HandlerID? {
        get { region?.handlerID }
        set { region?.handlerID = newValue }
    }

    /// Registers the named spaces' ask and stamps the view's marker, once the
    /// view has rendered into `buffer`.
    func stamp(into buffer: inout FrameBuffer, context: RenderContext) {
        guard let ask else { return }
        ask.finishRecording(size: buffer.cellSize)
        if context.geometryCoordinator?.register(ask) == true {
            buffer.hitTestRegions.append(.geometryMarker(ask.id))
        }
    }

    /// What to add to a point measured from the view's top-left to measure it
    /// in `space` instead — for a named space no owner found the view in, the
    /// global space's, when the handler said which region is the view's —
    /// and `nil` when nothing says.
    func offset(in space: CoordinateSpace) -> CellPoint? {
        switch space {
        case .local:
            return CellPoint(x: 0, y: 0)
        case .global:
            return globalOffset
        case .named:
            return ask?.observation(in: space)?.origin ?? globalOffset
        }
    }

    /// The region's composited origin, once a handler has said which region
    /// is the view's.
    private var globalOffset: CellPoint? {
        guard let region, region.handlerID != nil else { return nil }
        let origin = region.offset
        return CellPoint(x: origin.x, y: origin.y)
    }
}

/// Where `event`, measured from its region's top-left, is in `space`: moved by
/// where `origin` found the region's view there (the global space for a name
/// no owner found it in) — or left where it is when nothing says, a handler
/// with no region to measure from.
func pointerCell(of event: MouseEvent, in space: CoordinateSpace, origin: PointerSpaceOrigin?) -> CellPoint {
    guard space != .local, let offset = origin?.offset(in: space) else {
        return CellPoint(x: event.x, y: event.y)
    }
    return CellPoint(x: event.x + offset.x, y: event.y + offset.y)
}

extension CoordinateSpace {
    /// Whether this is a named space — one a view declared, or a scroll view's.
    var isNamed: Bool {
        if case .named = self { return true }
        return false
    }
}
