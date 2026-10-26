//  🖥️ TUI — A Terminal UI framework for Swift
//  GestureModifier.swift
//
//  Attaching a gesture to a view: `gesture(_:including:)` and its two
//  siblings, and the mask that says which gestures stay live.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - GestureMask

/// Options that control how adding a gesture to a view affects other gestures
/// recognized by the view and its subviews.
@frozen
public struct GestureMask: OptionSet, Sendable {
    /// The corresponding value of the raw type.
    public let rawValue: UInt32

    /// Creates the mask from a raw value.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Disable all gestures in the subview hierarchy, including the added
    /// gesture.
    public static let none: GestureMask = []

    /// Enable the added gesture but disable all gestures in the subview
    /// hierarchy.
    public static let gesture = Self(rawValue: 1 << 0)

    /// Enable all gestures in the subview hierarchy but disable the added
    /// gesture.
    public static let subviews = Self(rawValue: 1 << 1)

    /// Enable both the added gesture as well as all other gestures on the
    /// view and its subviews.
    public static let all: GestureMask = [.gesture, .subviews]
}

extension GestureMask: BitwiseCopyable {}

// MARK: - Attaching

/// How an attached gesture ranks against the gestures of the view it is
/// attached to.
enum GesturePriority: Equatable {
    /// Below them: they go first, and it gets the pointer if they fail.
    case normal

    /// Above them: it goes first, and they get the pointer if it fails.
    case high

    /// Beside them: it sees every event whatever they do, and they whatever
    /// it does.
    case simultaneous
}

extension View {
    /// Attaches a gesture to the view with a lower precedence than gestures
    /// defined by the view.
    ///
    /// ```swift
    /// VStack {
    ///     Text("Tap me").onTapGesture { print("Tap on text.") }
    ///     Text("Or here")
    /// }
    /// .gesture(TapGesture().onEnded { print("Tap on VStack.") })
    /// ```
    ///
    /// A click on the first `Text` runs its own tap; a click anywhere else in
    /// the stack runs the stack's. A control's own press — a `Button`'s, a
    /// `TextField`'s — is one of the view's gestures too, so a gesture attached
    /// this way to a button never takes its click (all as measured on macOS
    /// 15.8).
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - mask: A value that controls how adding this gesture to the view
    ///     affects other gestures recognized by the view and its subviews.
    ///     Defaults to ``GestureMask/all``.
    /// - Returns: The view, with the gesture attached.
    public func gesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        GestureAttachment(content: self, gesture: gesture, mask: mask, priority: .normal)
    }

    /// Attaches a gesture to the view with a lower precedence than gestures
    /// defined by the view, and lets you disable it.
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - isEnabled: Whether the added gesture is enabled.
    /// - Returns: The view, with the gesture attached.
    public func gesture<T: Gesture>(_ gesture: T, isEnabled: Bool) -> some View {
        self.gesture(gesture, including: isEnabled ? .all : .subviews)
    }

    /// Attaches a gesture to the view with a lower precedence than gestures
    /// defined by the view.
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - name: A string that identifies the gesture. iOS uses it to set up
    ///     failure relationships with UIKit gesture recognizers; macOS has
    ///     none to set up, and neither has a terminal, so it changes nothing.
    ///   - isEnabled: Whether the added gesture is enabled.
    /// - Returns: The view, with the gesture attached.
    public func gesture<T: Gesture>(_ gesture: T, name: String, isEnabled: Bool = true) -> some View {
        self.gesture(gesture, isEnabled: isEnabled)
    }

    /// Attaches a gesture to the view with a higher precedence than gestures
    /// defined by the view.
    ///
    /// The gesture goes first, and the view's own gestures — its subviews',
    /// and a control's own press — get the pointer only if it fails. A
    /// high-priority tap on a `Button` takes the click from it; a high-priority
    /// drag lets a click through to it and takes a drag (measured on macOS
    /// 15.8).
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - mask: A value that controls how adding this gesture to the view
    ///     affects other gestures recognized by the view and its subviews.
    ///     Defaults to ``GestureMask/all``.
    /// - Returns: The view, with the gesture attached.
    public func highPriorityGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        GestureAttachment(content: self, gesture: gesture, mask: mask, priority: .high)
    }

    /// Attaches a gesture to the view with a higher precedence than gestures
    /// defined by the view, and lets you disable it.
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - isEnabled: Whether the added gesture is enabled.
    /// - Returns: The view, with the gesture attached.
    public func highPriorityGesture<T: Gesture>(_ gesture: T, isEnabled: Bool) -> some View {
        highPriorityGesture(gesture, including: isEnabled ? .all : .subviews)
    }

    /// Attaches a gesture to the view with a higher precedence than gestures
    /// defined by the view.
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - name: A string that identifies the gesture; as for
    ///     ``gesture(_:name:isEnabled:)``, it changes nothing here.
    ///   - isEnabled: Whether the added gesture is enabled.
    /// - Returns: The view, with the gesture attached.
    public func highPriorityGesture<T: Gesture>(_ gesture: T, name: String, isEnabled: Bool = true) -> some View {
        highPriorityGesture(gesture, isEnabled: isEnabled)
    }

    /// Attaches a gesture to the view to process simultaneously with gestures
    /// defined by the view.
    ///
    /// The gesture sees every event the view's own gestures do, and each side
    /// recognizes as if the other were not there: a simultaneous tap on a
    /// `Button` runs, and so does the button (the gesture first, as measured
    /// on macOS 15.8).
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - mask: A value that controls how adding this gesture to the view
    ///     affects other gestures recognized by the view and its subviews.
    ///     Defaults to ``GestureMask/all``.
    /// - Returns: The view, with the gesture attached.
    public func simultaneousGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        GestureAttachment(content: self, gesture: gesture, mask: mask, priority: .simultaneous)
    }

    /// Attaches a gesture to the view to process simultaneously with gestures
    /// defined by the view, and lets you disable it.
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - isEnabled: Whether the added gesture is enabled.
    /// - Returns: The view, with the gesture attached.
    public func simultaneousGesture<T: Gesture>(_ gesture: T, isEnabled: Bool) -> some View {
        simultaneousGesture(gesture, including: isEnabled ? .all : .subviews)
    }

    /// Attaches a gesture to the view to process simultaneously with gestures
    /// defined by the view.
    ///
    /// - Parameters:
    ///   - gesture: A gesture to attach to the view.
    ///   - name: A string that identifies the gesture; as for
    ///     ``gesture(_:name:isEnabled:)``, it changes nothing here.
    ///   - isEnabled: Whether the added gesture is enabled.
    /// - Returns: The view, with the gesture attached.
    public func simultaneousGesture<T: Gesture>(_ gesture: T, name: String, isEnabled: Bool = true) -> some View {
        simultaneousGesture(gesture, isEnabled: isEnabled)
    }
}

// MARK: - The modifier

/// Where ``GestureAttachment`` keeps its recognizers between frames. A
/// namespace of its own because a generic type cannot hold static stored
/// properties.
private enum GestureAttachmentStateIndex {
    // Negative: the attachment renders its content at its own identity, and
    // 0... belongs to a composite content view's own @State. See
    // `StateStorage.StateKey`'s reserved-range table.
    static let participants = -120
}

/// The gestures attached at one identity, one per attaching modifier: chained
/// `.gesture(_:)`s each wrap the last, so each has a type of its own to be
/// found by.
final class GestureParticipants {
    private var byOwner: [ObjectIdentifier: GestureParticipant] = [:]

    @MainActor
    func participant(for owner: ObjectIdentifier) -> GestureParticipant {
        if let existing = byOwner[owner] { return existing }
        let made = GestureParticipant()
        byOwner[owner] = made
        return made
    }

    /// The participant `owner` made in an earlier frame, if it made one:
    /// a disabled view's attachment looks, and never makes one.
    func existingParticipant(for owner: ObjectIdentifier) -> GestureParticipant? {
        byOwner[owner]
    }
}

/// The modifier behind ``View/gesture(_:including:)``,
/// ``View/highPriorityGesture(_:including:)`` and
/// ``View/simultaneousGesture(_:including:)``.
///
/// Each frame it hands the gesture value to the gesture's recognizers — they
/// keep their state across frames, the closures and parameters are the
/// frame's, built when the arena next looks (``GestureParticipant``) — and
/// files the gesture with the mouse dispatcher under a region
/// the size of the view. The region goes BEHIND the content's regions, so a
/// gesture inside the view comes first, which is what makes an attached
/// gesture rank below the view's own; the dispatcher's ``GestureArena`` does
/// the rest.
struct GestureAttachment<Content: View, G: Gesture>: View {
    // The four-byte mask before the one-byte priority, and both last: the
    // per-pass memos key a view by the bytes its fields define, and the
    // priority first left three bytes of padding before the mask, so every
    // attachment was hashed run by run where a `Text`'s tap — 85 bytes with
    // no gap now — hashes as one dense run (`FlexibleFrameView` explains the
    // padding). Content and gesture keep their places: what follows either
    // is word-aligned for the common views and gestures, which end on a word.
    let content: Content
    let gesture: G
    let mask: GestureMask
    let priority: GesturePriority

    var body: Never {
        fatalError("GestureAttachment renders via Renderable")
    }
}

extension GestureAttachment: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A measure pass registers nothing and starts no clock.
        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher,
            let storage = context.stateStorage
        else {
            return TUIView.renderToBuffer(content, context: context)
        }
        let key = StateStorage.StateKey(
            identity: context.identity, propertyIndex: GestureAttachmentStateIndex.participants)
        // A disabled view takes no gesture, as a disabled control takes no
        // click. One it took before is filed as disabled, so that an arena
        // still holding it gives it up at the disable, as macOS does
        // (decisions B-F2-2); looked up, never made.
        guard context.environment.isEnabled else {
            let existing: StateBox<GestureParticipants>? = storage.existingStorage(for: key)
            if let participant = existing?.value.existingParticipant(for: ObjectIdentifier(Self.self)) {
                dispatcher.fileDisabledGesture(participant, in: context)
            }
            return TUIView.renderToBuffer(content, context: context)
        }
        storage.markActive(context.identity)
        let box: StateBox<GestureParticipants> = storage.storage(for: key, default: GestureParticipants())
        let participant = box.value.participant(for: ObjectIdentifier(Self.self))

        // A gesture reporting locations in a named space asks to be found in
        // it; claimed before the content renders, as every marker slot is.
        let pointerSpaces = PointerSpaceOrigin(
            named: namedPointerSpaces(of: gesture), global: false, context: context)
        var buffer = TUIView.renderToBuffer(content, context: context)
        pointerSpaces?.stamp(into: &buffer, context: context)
        participant.pointerSpaces = pointerSpaces

        let isLive = mask.contains(.gesture)
        if isLive { participant.update(gesture) }
        // Nothing to arbitrate: the gesture is off and its subviews' are not.
        guard isLive || !mask.contains(.subviews) else { return buffer }

        let subtree: Set<HitTestRegion.HandlerID> =
            priority == .high || !mask.contains(.subviews)
            ? Set(buffer.hitTestRegions.map(\.handlerID)) : []
        let role = GestureRole(
            participant: isLive ? participant : nil, priority: priority,
            disablesSubviews: !mask.contains(.subviews), subtree: subtree)
        // One filing — the region's handler, the role, and the click and drag
        // reporting the gesture hears through — made again by a memo that
        // serves this subtree: the recognizers live in the participant, not in
        // the frame, so a served frame's gesture is the same gesture. Its clock
        // needs nothing from the render either — the run loop ticks the arena
        // and asks for the wake (`advanceGestures`, `gestureDeadline`).
        let id = dispatcher.registerGesture(in: context, role)
        buffer.hitTestRegions.insert(contentsOf: buffer.frameHitRegions(handlerID: id), at: 0)
        return buffer
    }
}

extension GestureAttachment: Layoutable {
    /// Behaviour-only decorator — it renders `content` unchanged, so it
    /// measures as its content does.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension GestureAttachment: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// A gesture written on a form row is the gesture of the row the form lays
/// out, which keeps its place, as SwiftUI's form keeps it (measured,
/// `Tools/SwiftUIProbes/Form rows`).
extension GestureAttachment: FormRowRewrapping {
    func rewrappingFormRow<V: View>(_ row: V) -> any View {
        GestureAttachment<V, G>(content: row, gesture: gesture, mask: mask, priority: priority)
    }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension GestureAttachment: DrawsContentUnchanged {}

// MARK: - Participant

/// One attached gesture, as the dispatcher's arena sees it: its recognizers,
/// kept across frames, and the root it reports through.
///
/// The recognizers are built from the gesture value of the last frame that
/// rendered the attachment — its closures and parameters — but not in that
/// frame. A frame only hands its value over (``update(_:)``); the build waits
/// until the arena next reads ``root``, which is when a press lands on the
/// view, and each frame-start tick and event while one is under way. Building
/// every frame instead cost every gesture on screen a walk of its gesture tree
/// — a recognizer looked up per node, with the generic metadata of each node
/// type fetched at run time — on every frame, for the rare frame a press
/// lands on. Nothing reads the recognizers between the render and the arena's
/// next look, so what the arena sees is the build it would have seen.
///
/// The one thing deferring can change is which recognizer a place in the tree
/// keeps. A gesture whose shape changed and changed back across frames no
/// press touched — `isOn ? tap : nil`, flipped twice — comes back to the
/// recognizer it had, where a build per frame would have dropped it and made a
/// new one. That recognizer is at rest: one under way is in the arena, which
/// reads every build while it lasts. And a recognizer at rest taking the next
/// press is what every gesture whose shape holds still does anyway — it keeps
/// its recognizers for as long as its view is on screen.
@MainActor
final class GestureParticipant {
    private let cache = GestureNodeCache()

    /// Where the attachment's view is in the named spaces its gesture reports
    /// locations in, as of the last frame that drew it — `nil` when it reports
    /// in none. Read by the arena as it hands each event to the recognizers.
    var pointerSpaces: PointerSpaceOrigin?

    /// The gesture value of the last frame that rendered the attachment, until
    /// ``root`` builds it. An existential: a tap's value fits its inline
    /// buffer, so handing one over allocates nothing.
    private var pending: (any Gesture)?

    /// The recognizer as of the last build.
    private var built: GestureNodeBase?

    /// Takes this frame's gesture value, to be built when the arena next looks.
    func update(_ gesture: some Gesture) {
        pending = gesture
    }

    /// The recognizer for the gesture as of the last frame that rendered it,
    /// built from that frame's value if it has not been yet.
    var root: GestureNodeBase? {
        if let gesture = pending.take() {
            built = Self.build(gesture, into: cache)
            cache.commit()
        }
        return built
    }

    /// Builds `gesture`'s recognizers against `cache`, opening the existential
    /// ``update(_:)`` stored it in.
    private static func build<G: Gesture>(_ gesture: G, into cache: GestureNodeCache) -> GestureNodeBase {
        G._makeGesture(gesture: gesture, inputs: _GestureInputs(cache: cache)).node
    }

    /// When the gesture next has to hear the clock.
    var deadline: Int64? { root?.deadline }
}
