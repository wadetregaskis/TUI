//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnHoverModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - On Hover Modifier

/// A modifier that fires a callback when the cursor enters or
/// leaves the wrapped view's hit region.
///
/// `OnHoverModifier` participates in TUIkit's hover state
/// machine, which lives in `MouseEventDispatcher`: bare
/// `.moved` events on the dispatcher synthesise `.entered` /
/// `.exited` transitions whenever the cursor crosses a region
/// boundary. The modifier registers a handler that reacts to
/// only those synthetic phases — never raw motion — and
/// surfaces them through a SwiftUI-compatible callback shape.
///
/// The modifier also calls
/// `MouseEventDispatcher.requestFeature(_:)` every frame with
/// `.motion`, so the terminal switches into any-event
/// mouse-tracking mode while the view is on screen. Once the
/// view disappears the request is no longer made and the
/// dispatcher relaxes back to whatever the base scene-level
/// ``MouseSupport`` configuration set.
public struct OnHoverModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// Where the cells the callback is told are measured from: the view's
    /// own top-left (`.local`) or the terminal's (`.global`).
    var coordinateSpace: CoordinateSpace = .local

    /// The hover callback: told when the cursor enters the view's hit region,
    /// moves within it, and leaves it, with where it is. `.onHover` hears the
    /// crossings and not the moves.
    let observe: @MainActor (HoverTransition) -> Void

    public var body: Never {
        fatalError("OnHoverModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension OnHoverModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)

        // SwiftUI parity (verified empirically on macOS 15): a hover callback
        // registered INSIDE a `.disabled(true)` scope never fires, while one
        // attached outside the disabled subtree (`.disabled(true).onHover`)
        // still does. Gating on the environment's `isEnabled` reproduces that
        // scoping exactly — the outer-attachment case renders this modifier
        // with an enabled environment.
        guard !context.isMeasuring,
              context.environment.isEnabled,
              let dispatcher = context.environment.mouseEventDispatcher
        else {
            return buffer
        }

        // Ask the dispatcher to enable motion reporting for this
        // frame — necessary because the terminal only emits
        // `.moved` events when motion tracking is active.
        dispatcher.requestFeature(.motion, in: context)

        let capturedObserve = observe
        // The dispatcher hands a handler cells local to its region; the
        // terminal's are those plus the region's origin, which is known only
        // where the region was composited — so it is looked up when the event
        // comes, by the id the registration returns.
        let globalOrigin = coordinateSpace == .global ? RegionOrigin(dispatcher: dispatcher) : nil
        // An OBSERVER, not an ordinary region. This region goes on after the
        // content's, so on every cell it is the innermost match, and as an
        // ordinary region it took the `.entered` / `.exited` the wrapped
        // control needs for its own hover face — `Button("Save") {}.onHover { … }`
        // never lit up, where SwiftUI keeps both. See
        // `MouseEventDispatcher.registerHoverObserver(in:_:)`.
        let handlerID = dispatcher.registerHoverObserver(in: context) { event in
            let origin = globalOrigin?.offset ?? (x: 0, y: 0)
            let cell = CellPoint(x: event.x + origin.x, y: event.y + origin.y)
            switch event.phase {
            case .entered:
                capturedObserve(.entered(cell))
                return true
            case .exited:
                capturedObserve(.exited)
                return true
            case .moved:
                // Offered while the pointer stays inside; answering `false`
                // asks for no frame of its own — an action that changes state
                // asks for one through that state.
                capturedObserve(.moved(cell))
                return false
            default:
                // Don't claim any non-hover event so other
                // siblings / parents still get a shot at it
                // (especially clicks and wheel scrolling).
                return false
            }
        }
        globalOrigin?.handlerID = handlerID
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: handlerID
            )
        )
        return buffer
    }
}

/// Where a registered region sits on the terminal, looked up when an event
/// arrives: the handler is built before the registration that names it, so the
/// id is filled in afterwards. A memo replaying the registration keeps the id,
/// and so the lookup.
final class RegionOrigin: @unchecked Sendable {
    private weak var dispatcher: MouseEventDispatcher?
    var handlerID: HitTestRegion.HandlerID?

    init(dispatcher: MouseEventDispatcher) {
        self.dispatcher = dispatcher
    }

    /// The region's top-left cell on the terminal, or `(0, 0)` while it has
    /// none.
    var offset: (x: Int, y: Int) {
        handlerID.flatMap { dispatcher?.regionOffset(for: $0) } ?? (x: 0, y: 0)
    }
}

// MARK: - Transitions

/// What a hover observer is told about the pointer, in its coordinate space.
enum HoverTransition {
    /// It came into the region, at this cell.
    case entered(CellPoint)
    /// It moved to this cell without leaving.
    case moved(CellPoint)
    /// It left.
    case exited
}

// MARK: - Hover Phase

/// Where the pointer is over a view — SwiftUI's `HoverPhase`, as
/// ``View/onContinuousHover(coordinateSpace:perform:)-(CoordinateSpace,_)`` hands it to its action.
///
/// The location is a ``CellPoint`` where SwiftUI's is a `CGPoint`: a terminal
/// reports the pointer's cell and nothing finer (§2.2 of
/// `Documentation/SwiftUI-compatibility.md`).
public enum HoverPhase: Equatable, Sendable {
    /// The pointer is over the view, at this cell.
    case active(CellPoint)
    /// The pointer has left the view.
    case ended
}

// MARK: - Layoutable

extension OnHoverModifier: Layoutable {
    /// Forwards measurement straight to the content — the
    /// hover modifier doesn't change layout.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - View Extension

extension View {
    /// Adds an action to perform when the cursor enters or
    /// leaves the view's hit region.
    ///
    /// SwiftUI-compatible signature. The closure receives
    /// `true` on enter, `false` on leave — driven by the
    /// dispatcher's hover state machine, not by raw motion, so
    /// transitions are de-duplicated and only fire on actual
    /// region crossings.
    ///
    /// > Note: Hover requires the terminal's any-event motion
    ///   reporting mode. This modifier requests it
    ///   automatically per-frame; the AppRunner unions the
    ///   request with the base ``MouseSupport`` configuration
    ///   each frame.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Hover me")
    ///     .onHover { isHovered in
    ///         print(isHovered ? "in" : "out")
    ///     }
    /// ```
    ///
    /// - Parameter action: A closure invoked with `true` when
    ///   the cursor enters and `false` when it leaves.
    /// - Returns: A view that reports cursor enter / exit
    ///   transitions to `action`.
    public func onHover(perform action: @escaping @MainActor (Bool) -> Void) -> some View {
        OnHoverModifier(content: self) { transition in
            switch transition {
            case .entered: action(true)
            case .exited: action(false)
            case .moved: break
            }
        }
    }

    /// Adds an action to perform when the pointer enters the view, moves
    /// within it, and leaves it — SwiftUI's `onContinuousHover`.
    ///
    /// ```swift
    /// @State private var hoverCell: CellPoint?
    ///
    /// Grid { … }
    ///     .onContinuousHover { phase in
    ///         switch phase {
    ///         case .active(let cell): hoverCell = cell
    ///         case .ended: hoverCell = nil
    ///         }
    ///     }
    /// ```
    ///
    /// The action runs with ``HoverPhase/active(_:)`` when the pointer comes
    /// in and each time the terminal reports it moving within, and with
    /// ``HoverPhase/ended`` when it leaves. A terminal reports the pointer's
    /// cell, so a move is the pointer reaching another cell.
    /// Like ``onHover(perform:)`` it needs the terminal's any-event mouse
    /// reporting, which it asks for while the view is on screen, and a view
    /// inside `.disabled(true)` hears nothing.
    ///
    /// - Parameters:
    ///   - coordinateSpace: Where the location is measured from: the view's
    ///     own top-left cell (`.local`, the default) or the terminal's
    ///     (`.global`).
    ///   - action: The action, given the phase.
    /// - Returns: A view that reports the pointer over it to `action`.
    public func onContinuousHover(
        coordinateSpace: CoordinateSpace = .local, perform action: @escaping @MainActor (HoverPhase) -> Void
    ) -> some View {
        OnHoverModifier(content: self, coordinateSpace: coordinateSpace) { transition in
            switch transition {
            case .entered(let cell), .moved(let cell): action(.active(cell))
            case .exited: action(.ended)
            }
        }
    }

    /// Adds an action to perform when the pointer moves onto, within, or off
    /// this view, with the space named through ``CoordinateSpaceProtocol`` —
    /// the spelling SwiftUI moved this modifier to, answering as the
    /// ``CoordinateSpace`` form does.
    ///
    /// - Parameters:
    ///   - coordinateSpace: `.local`, the default, or `.global`.
    ///   - action: The action, given the phase.
    /// - Returns: A view that reports the pointer over it to `action`.
    public func onContinuousHover(
        coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping @MainActor (HoverPhase) -> Void
    ) -> some View {
        onContinuousHover(coordinateSpace: coordinateSpace.coordinateSpace, perform: action)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension OnHoverModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension OnHoverModifier: DrawsContentUnchanged {}
