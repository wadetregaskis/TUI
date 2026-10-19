//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MatchedGeometryRegistry.swift
//
//  The groups `matchedGeometryEffect` joins views into: who was in each group
//  last frame and where, who has joined this walk, and the check the scene
//  root makes once it has found them all.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Keys and Records

/// The group a matched geometry effect joins: an id within a namespace.
package struct MatchedGeometryKey: Hashable {
    package let namespace: Namespace.ID
    package let id: AnyHashable

    package init(namespace: Namespace.ID, id: AnyHashable) {
        self.namespace = namespace
        self.id = id
    }
}

/// How far each edge of a drawn rectangle stands from where its view is
/// going, in fractional cells: what a matched geometry animation starts from
/// and runs down to nothing.
///
/// Edges rather than an origin and a size, so a rectangle part-way through
/// rounds each edge once: interpolated as an origin and a size rounded apart,
/// the trailing edge of a growing view jittered by a cell between frames.
package struct MatchedEdgeOffsets: Equatable, Sendable {
    package var minX: Double
    package var minY: Double
    package var maxX: Double
    package var maxY: Double

    /// No offset: the drawing is where its view is going.
    package static let zero = Self(minX: 0, minY: 0, maxX: 0, maxY: 0)

    package init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// The offsets that take `target` to `drawn`.
    package init(from drawn: CellRect, to target: CellRect) {
        self.init(
            minX: Double(drawn.minX - target.minX), minY: Double(drawn.minY - target.minY),
            maxX: Double(drawn.maxX - target.maxX), maxY: Double(drawn.maxY - target.maxY))
    }

    package var isZero: Bool { self == .zero }

    /// `target` with `remaining` of these offsets still to cover — `1` where
    /// the animation starts, `0` where it ends — each edge rounded once.
    package func applied(to target: CellRect, remaining: Double) -> CellRect {
        let minX = target.minX + Int((self.minX * remaining).rounded())
        let minY = target.minY + Int((self.minY * remaining).rounded())
        let maxX = target.maxX + Int((self.maxX * remaining).rounded())
        let maxY = target.maxY + Int((self.maxY * remaining).rounded())
        return CellRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}

/// One member of the registry: a view, and the wrapper that joined it to a
/// group.
///
/// A view can be in more than one group — two effects stacked on it, or an
/// effect and a matched transition source — and every one of those wrappers
/// draws at the view's identity, since a modifier does not descend it. So a
/// member is told apart by the wrapper's type as well, as the animation store
/// tells two modifiers on one view apart (`AnimationStore.Key.owner`): two
/// stacked wrappers' types differ, the outer one's naming the inner one.
/// Keyed by the identity alone, the wrappers on one view read each other's
/// state, and which one each read changed with the order a dictionary was
/// walked in.
package struct MatchedMemberID: Hashable {
    package let identity: ViewIdentity
    /// The type of the wrapper that joined the view to its group.
    package let owner: ObjectIdentifier

    package init(identity: ViewIdentity, owner: ObjectIdentifier) {
        self.identity = identity
        self.owner = owner
    }
}

/// What a group's source is, as a member following it reads it.
package struct MatchedSource: Equatable {
    package var identity: ViewIdentity
    /// Its frame in the global space, as laid out.
    package var frame: CellRect
    /// The point of it that is shared (`matchedGeometryEffect`'s `anchor`).
    package var anchor: UnitPoint

    package init(identity: ViewIdentity, frame: CellRect, anchor: UnitPoint) {
        self.identity = identity
        self.frame = frame
        self.anchor = anchor
    }
}

/// What a member carries from frame to frame: the animation it is running,
/// and what it drew, to start the next one from.
package struct MatchedMemberState {
    package var key: MatchedGeometryKey
    /// The source a member that is not one followed, or `nil` — for a source,
    /// and for a member whose group has none.
    package var followed: ViewIdentity?
    /// The slot of the member's running animation in the animation store: a
    /// new one for each change it animates, so that each is a first sight.
    package var epoch: Int
    /// Where the drawing stood from where the member was going when its
    /// animation started; zero at rest.
    package var offsets: MatchedEdgeOffsets
    /// Where it drew itself, in the global space — filled in once the scene
    /// root has found it.
    package var presented: CellRect?
    /// The member of its group that left as it arrived, while this one is
    /// carried from where that one was drawn — so the picture it left is
    /// carried with it (decisions B-O4-1). `nil` at rest.
    package var leaving: MatchedMember?

    package init(
        key: MatchedGeometryKey, followed: ViewIdentity?, epoch: Int, offsets: MatchedEdgeOffsets
    ) {
        self.key = key
        self.followed = followed
        self.epoch = epoch
        self.offsets = offsets
    }
}

/// A member of a group as a walk registered it, once it has drawn.
package struct MatchedRegistration {
    package var identity: ViewIdentity
    /// The type of the wrapper that joined it (``MatchedMemberID``).
    package var owner: ObjectIdentifier
    /// Its geometry marker, which the scene root finds it by.
    package var marker: HitTestRegion.HandlerID
    package var isSource: Bool
    package var anchor: UnitPoint
    /// Its own size, as laid out.
    package var size: CellSize
    /// Where it expects to be found in the global space — its carried origin
    /// and residual (`GeometryAsk.expectedOrigin(in:)`) — for a member drawn
    /// after it in the same walk to follow; `nil` where nothing predicts it.
    package var expectedOrigin: CellPoint?
    /// Where it drew itself, relative to its own top-leading corner, or `nil`
    /// when it drew itself in its own place.
    package var drawn: CellRect?
    /// Whether it follows the group's source (`isSource: false`).
    package var isFollower: Bool
    /// The source it drew from, or `nil` for one that found none.
    package var followed: MatchedSource?
    /// A member of the group last frame that it took to have left, and
    /// animated from.
    package var assumedDeparted: ViewIdentity?
    package var state: MatchedMemberState

    package init(
        identity: ViewIdentity, owner: ObjectIdentifier, marker: HitTestRegion.HandlerID, isSource: Bool,
        anchor: UnitPoint, size: CellSize, state: MatchedMemberState
    ) {
        self.identity = identity
        self.owner = owner
        self.marker = marker
        self.isSource = isSource
        self.anchor = anchor
        self.size = size
        self.isFollower = !isSource
        self.state = state
    }

    /// The member it registers.
    package var member: MatchedMemberID {
        MatchedMemberID(identity: identity, owner: owner)
    }
}

/// A member of a group as the scene root found it.
package struct MatchedMember {
    package var identity: ViewIdentity
    /// Its geometry marker, which finds it in a picture it drew in — the
    /// one it left, when it has gone (`DepartureStore.carrying(_:leftFrom:)`).
    package var marker: HitTestRegion.HandlerID
    package var isSource: Bool
    package var anchor: UnitPoint
    /// Its own frame in the global space.
    package var frame: CellRect
    /// Where it drew itself in the global space.
    package var presented: CellRect
}

// MARK: - Registry

/// The groups `View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`
/// joins views into.
///
/// A member draws before anyone knows where the others are — TUIkit renders
/// bottom-up — so it draws from what is known: what the scene root found last
/// frame, or, in the walk the root makes again to correct a reader, what it
/// found in the walk before; and a source drawn earlier in the same walk says
/// where its owner expects to find it. Each member registers what it drew
/// from, and once the root has found every member
/// (``GeometryCoordinator/resolveRemaining(in:size:)``) it checks them: a
/// follower that drew from a source that is not where it is, or not the
/// group's, or a member that animated from one it took to have left that is
/// still there, asks the root to draw the frame again — the correction
/// `GeometryReader` uses (design study A2, G4). The effect never moves a view
/// in its parent's layout, so the second walk lays out what the first did,
/// and one is enough. Only a member the root found is checked, as only a
/// reader it found is: one it did not was drawn nowhere anyone sees.
///
/// One per geometry coordinator; touched only on the render path and at the
/// end of a frame, both on the main actor.
package final class MatchedGeometryRegistry: @unchecked Sendable {
    /// This walk's members, in the order they drew.
    private var walk: [MatchedGeometryKey: [MatchedRegistration]] = [:]

    /// What the root found in the last walk of this frame, once a walk has
    /// been resolved; `nil` in the frame's first walk.
    private var settled: [MatchedGeometryKey: [MatchedMember]]?

    /// What the root found in the last frame.
    private var lastFrame: [MatchedGeometryKey: [MatchedMember]] = [:]

    /// Each member's state as the last frame left it.
    private var states: [MatchedMemberID: MatchedMemberState] = [:]

    /// Each member's state as the last resolved walk of this frame leaves it.
    private var pendingStates: [MatchedMemberID: MatchedMemberState] = [:]

    /// The members that registered last frame and that the root did not find:
    /// drawn nowhere anyone sees — the root a navigation stack draws
    /// off-screen under a pushed screen. A source among them is not followed
    /// from where its owner expects it, which the root would not confirm.
    private var drawnNowhere: Set<MatchedMemberID> = []

    /// The members registered and not found in the last resolved walk of this
    /// frame.
    private var pendingDrawnNowhere: Set<MatchedMemberID> = []

    init() {}

    /// Whether there is anything at all to keep — the check every frame
    /// without a matched geometry effect pays.
    private var isEmpty: Bool { walk.isEmpty && lastFrame.isEmpty && settled == nil }
}

// MARK: - Asking

extension MatchedGeometryRegistry {
    /// The state `member` was left in last frame, or `nil` for a member that
    /// is new.
    package func state(of member: MatchedMemberID) -> MatchedMemberState? {
        states[member]
    }

    /// Whether `identity` was a member of `key`'s group last frame.
    package func wasMember(_ identity: ViewIdentity, of key: MatchedGeometryKey) -> Bool {
        lastFrame[key]?.contains { $0.identity == identity } ?? false
    }

    /// The group's source as best known now, for a member other than it to
    /// follow: the last source the root found in this frame's last walk; else
    /// the last one registered so far in this walk, where its owner expects
    /// it, unless the root did not find it last frame either; else last
    /// frame's. `nil` when the group has none.
    ///
    /// A source registered and not found last frame was drawn nowhere anyone
    /// sees, and is not followed: followed, a follower on a screen pushed over
    /// a navigation stack's root drew at a source on the covered root, and the
    /// root drew every frame twice to correct it.
    ///
    /// The last, where SwiftUI calls more than one source undefined: a
    /// follower takes the later one's frame, as SwiftUI was measured doing
    /// (`Tools/SwiftUIProbes/Matched geometry/mg1.out`, S10).
    package func source(of key: MatchedGeometryKey, excluding identity: ViewIdentity) -> MatchedSource? {
        if let settled {
            return settled[key]?.last { $0.isSource && $0.identity != identity }.map {
                MatchedSource(identity: $0.identity, frame: $0.frame, anchor: $0.anchor)
            }
        }
        if let registered = walk[key]?.last(where: {
            $0.isSource && $0.identity != identity && !drawnNowhere.contains($0.member)
        }) {
            if let origin = registered.expectedOrigin {
                return MatchedSource(
                    identity: registered.identity,
                    frame: CellRect(
                        x: origin.x, y: origin.y, width: registered.size.width, height: registered.size.height),
                    anchor: registered.anchor)
            }
            // Drawn already, with nothing to say where: where it was last
            // frame, or nothing for one that is new — either way the root
            // checks.
            return lastFrame[key]?.first { $0.identity == registered.identity }.map {
                MatchedSource(identity: $0.identity, frame: $0.frame, anchor: registered.anchor)
            }
        }
        return lastFrame[key]?.last { $0.isSource && $0.identity != identity }.map {
            MatchedSource(identity: $0.identity, frame: $0.frame, anchor: $0.anchor)
        }
    }

    /// Whether `key`'s group has a member that follows its source — last
    /// frame, in this frame's last resolved walk, or registered so far in this
    /// one — so a source must say where it expects to be found.
    package func hasFollowers(of key: MatchedGeometryKey) -> Bool {
        if lastFrame[key]?.contains(where: { !$0.isSource }) == true { return true }
        if settled?[key]?.contains(where: { !$0.isSource }) == true { return true }
        return walk[key]?.contains(where: \.isFollower) == true
    }

    /// The member of `key`'s group that left as `identity` arrived — what an
    /// arriving member animates from, SwiftUI's "a view inserted in the same
    /// transaction that another view with the same key is removed" — or `nil`
    /// when `identity` was there last frame, or nothing left.
    ///
    /// In a frame's first walk a member that has not drawn yet is taken to
    /// have left; the root checks, and draws the frame again if it had not.
    /// A source is preferred over a follower, and the last over the first.
    package func departed(from key: MatchedGeometryKey, arriving identity: ViewIdentity) -> MatchedMember? {
        guard let before = lastFrame[key], !before.contains(where: { $0.identity == identity }) else { return nil }
        let present: [ViewIdentity] =
            settled.map { ($0[key] ?? []).map(\.identity) } ?? (walk[key] ?? []).map(\.identity)
        let gone = before.filter { !present.contains($0.identity) }
        return gone.last(where: \.isSource) ?? gone.last
    }
}

// MARK: - Registering

extension MatchedGeometryRegistry {
    /// Adds a member to `key`'s group for this walk, once it has drawn. A
    /// member drawn again in the same walk replaces what it registered the
    /// first time.
    package func register(_ registration: MatchedRegistration, in key: MatchedGeometryKey) {
        var members = walk[key] ?? []
        if let index = members.firstIndex(where: { $0.member == registration.member }) {
            members[index] = registration
        } else {
            members.append(registration)
        }
        walk[key] = members
    }
}

// MARK: - The Walk and the Frame

extension MatchedGeometryRegistry {
    /// Forgets what the last walk registered: the root is drawing the scene
    /// again, or a new frame.
    func beginWalk() {
        if !walk.isEmpty { walk.removeAll(keepingCapacity: true) }
    }

    /// Finds this walk's members where the root found their markers, keeps
    /// what was found for the frame's next walk and the next frame, and
    /// answers whether any of them drew from something that was not so — a
    /// source moved or replaced, or one taken to have left still there — so
    /// the root draws the frame again.
    ///
    /// A member the root did not find is not checked: its drawing was thrown
    /// away — the root a navigation stack draws off-screen under a pushed
    /// screen — so nothing it drew from can have been seen to be wrong, as
    /// for a reader no owner found (``GeometryCoordinator/resolveRemaining(in:size:)``).
    /// Checked, a follower there drew from a source that was not found
    /// either on every frame, and every frame was drawn twice.
    ///
    /// - Parameter origin: Where the root found the marker with an id, in the
    ///   global space, or `nil` where it found none (a container that drops
    ///   its content's regions).
    /// - Returns: Whether a member must be drawn again.
    func resolveWalk(origin: (HitTestRegion.HandlerID) -> CellPoint?) -> Bool {
        guard !isEmpty else { return false }
        var found: [MatchedGeometryKey: [MatchedMember]] = [:]
        var resolvedStates: [MatchedMemberID: MatchedMemberState] = [:]
        var unfound: Set<MatchedMemberID> = []
        for (key, registrations) in walk {
            for registration in registrations {
                guard let at = origin(registration.marker) else {
                    unfound.insert(registration.member)
                    continue
                }
                let frame = CellRect(
                    x: at.x, y: at.y, width: registration.size.width, height: registration.size.height)
                let presented =
                    registration.drawn.map {
                        CellRect(x: at.x + $0.x, y: at.y + $0.y, width: $0.width, height: $0.height)
                    } ?? frame
                found[key, default: []].append(
                    MatchedMember(
                        identity: registration.identity, marker: registration.marker, isSource: registration.isSource,
                        anchor: registration.anchor, frame: frame, presented: presented))
                var state = registration.state
                state.presented = presented
                resolvedStates[registration.member] = state
            }
        }
        var misled = false
        for (key, registrations) in walk {
            let members = found[key] ?? []
            for registration in registrations
            where !unfound.contains(registration.member) && Self.wasMisled(registration, by: members) {
                misled = true
            }
        }
        settled = found
        pendingStates = resolvedStates
        pendingDrawnNowhere = unfound
        return misled
    }

    /// Whether `registration` drew from something `members` — its group as
    /// the root found it — says was not so.
    private static func wasMisled(_ registration: MatchedRegistration, by members: [MatchedMember]) -> Bool {
        if let departed = registration.assumedDeparted, members.contains(where: { $0.identity == departed }) {
            return true
        }
        guard registration.isFollower else { return false }
        let source = members.last { $0.isSource && $0.identity != registration.identity }
        return source?.identity != registration.followed?.identity
            || source?.frame != registration.followed?.frame
    }

    /// Keeps what the frame's last walk found for the next frame.
    func endFrame() {
        guard !isEmpty || !states.isEmpty || !drawnNowhere.isEmpty else { return }
        lastFrame = settled ?? [:]
        states = settled == nil ? [:] : pendingStates
        drawnNowhere = settled == nil ? [] : pendingDrawnNowhere
        settled = nil
        pendingStates = [:]
        pendingDrawnNowhere = []
        walk.removeAll(keepingCapacity: true)
    }
}
