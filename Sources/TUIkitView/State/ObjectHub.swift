//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObjectHub.swift
//
//  What the state storage keeps for one object that views hold in a property
//  field: the views drawn holding it, which a write to its state redraws, and
//  the path its ids are made from.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The views drawn holding one class property's object, in one
/// ``StateStorage``: the sink of every `@State` box the object holds, so a
/// write to the object's state redraws each of them.
///
/// Made by the first render walk that reaches the object, never by a
/// measure, and only for an object whose class holds a `@State`,
/// `@Environment`, `@FocusState` or `@Namespace` (``PropertyWalk``). Each view
/// is registered by a ``HolderToken`` kept among the storage's values at its
/// identity, so it stays registered exactly while its own `@State` would be
/// kept: drawn, served from the memo, or retained by a container that windows
/// its rows. Nothing is done for it on a memo hit.
///
/// `@unchecked Sendable`: ``holders`` is behind its lock, and a write reads
/// nothing else. The rest is the main actor's, as the walk is.
final class ObjectHub: RenderInvalidationSink, @unchecked Sendable {
    /// The object, held weakly: an object made at a freed one's address is
    /// never taken for it (``StateStorage/objectHub(of:)``).
    private(set) weak var object: AnyObject?

    /// The render cache the holders' invalidations go to.
    private let link: RenderCache.Link?

    /// The views drawn holding the object, each counted by the fields it holds
    /// it in, and the last to stop holding it. Behind a lock: a write reads it
    /// from whatever thread it is made on.
    private let holders = Lock(initialState: Holders())

    /// What the ids of the `@FocusState` and `@Namespace` inside the object
    /// are made from: `obj` and a count of the storage's, so an object keeps
    /// its ids whichever view draws it, and two objects never share theirs —
    /// unless the object is one of a chain made with the values of one view
    /// at one field, which share their first's (``StateStorage/registerHolder(_:of:at:kind:)``).
    /// Main actor only.
    private(set) var idPath: String

    /// Whether ``idPath`` is a chain's, taken from the object the holder
    /// showed before: given up for one of the object's own once a walk finds
    /// the object was made before the pass that walks it
    /// (``StateStorage/giveOwnIDs(to:)``). Main actor only.
    private(set) var takesChainIDs: Bool

    /// Whether ``primary``'s last render walk to reach a property of the
    /// object that keeps what it takes from the environment in a store every
    /// copy shares — a `@FocusState`'s focus manager, `@FocusedValue` — drew
    /// it as a backdrop, the page beneath a modal: another holder's live walk
    /// hands them its environment then (``PropertyWalk/ObjectWalk/sharedStores``).
    /// Main actor only.
    var primaryDrawsBackdrop = false

    /// The view the object reads its environment as at rest: the first
    /// holder drawn on a hub with none, for as long as it holds the object.
    /// Its render walk leaves the object its environment, where every other
    /// walk's is put back after its view's content
    /// (``StateStorage/notePrimaryEnvironment(_:_:)``). Main actor only.
    var primary: ViewIdentity?

    /// What the object's `@State` held in each place's box that the object
    /// made next at that place took over while this one was alive, by the
    /// box: what a `@State` of the object still bound there takes back when a
    /// walk finds the object again, so it outlived its pass — made on demand
    /// in a body and kept, not with a view value
    /// (``StateStorage/placeBox(_:at:adopting:from:)``). Each is kept with no
    /// sink until taken: one would be this hub, and the hub and the box would
    /// keep each other after the object had gone. Main actor only.
    private var handedOver: [ObjectIdentifier: AnyObject] = [:]

    init(object: AnyObject, link: RenderCache.Link?, idPath: String, takesChainIDs: Bool) {
        self.object = object
        self.link = link
        self.idPath = idPath
        self.takesChainIDs = takesChainIDs
    }

    /// Makes the object's ids from `idPath`, its own.
    func takeOwnIDs(_ idPath: String) {
        self.idPath = idPath
        takesChainIDs = false
    }

    /// Keeps `state`, a box holding what the object's `@State` bound to `box`
    /// held when the object made next at `box`'s place took `box` over, and
    /// with no sink (``handedOver``).
    func keep(_ state: AnyObject, handedOverWith box: AnyObject) {
        handedOver[ObjectIdentifier(box)] = state
    }

    /// The box ``keep(_:handedOverWith:)`` kept for `box`, which it gives up.
    func takeState(handedOverWith box: AnyObject) -> AnyObject? {
        handedOver.isEmpty ? nil : handedOver.removeValue(forKey: ObjectIdentifier(box))
    }

    /// Notes that `holder` holds the object in one more field.
    func addHolder(_ holder: ViewIdentity) {
        holders.withLock { $0.counts[holder, default: 0] += 1 }
    }

    /// Notes that `holder` holds the object in one field fewer: none left, it
    /// is no longer the object's holder, nor its primary.
    func removeHolder(_ holder: ViewIdentity) {
        let gone = holders.withLock { holders -> Bool in
            guard let count = holders.counts[holder] else { return false }
            if count > 1 {
                holders.counts[holder] = count - 1
                return false
            }
            holders.counts.removeValue(forKey: holder)
            holders.departed = holder
            return true
        }
        if gone, primary == holder { primary = nil }
    }

    /// Whether `holder` holds the object.
    func isHeld(by holder: ViewIdentity) -> Bool {
        holders.withLock { $0.counts[holder] != nil }
    }

    /// Redraws every view drawn holding the object: what a write to a
    /// `@State` box the object holds does. `identity`, the box's, is not
    /// asked: the object's state is every holder's. Once no view holds the
    /// object, it redraws what was above the last to leave, which may show
    /// the object without holding it — through a store, or a closure — as the
    /// view a box was kept for is redrawn by the box's writes after it left.
    func invalidateRender(for _: ViewIdentity?) {
        let holders = self.holders.withLock { holders -> [ViewIdentity] in
            guard holders.counts.isEmpty else { return Array(holders.counts.keys) }
            return holders.departed.map { [$0] } ?? []
        }
        for holder in holders {
            link?.invalidateRender(for: holder)
        }
    }
}

/// The views drawn holding an object (``ObjectHub``).
private struct Holders {
    /// Each view holding it, counted by the fields it holds it in.
    var counts: [ViewIdentity: Int] = [:]
    /// The last view to stop holding it, if none does now: what a write
    /// redraws above. Of several that stop in one pass, whichever the prune
    /// drops last, in no set order.
    var departed: ViewIdentity?
}

/// That a view drawn holds an object (``ObjectHub``) in one field: kept among
/// the storage's values at the view's identity, at
/// ``StateStorage/StateKey/objectHolderIndex`` and the field's scope, so it is
/// pruned, retained by a memo hit or a window, and dropped with the view's
/// own state, and the hub forgets the view with it.
final class HolderToken: DroppableBox {
    /// The view.
    let holder: ViewIdentity

    /// The hub of the object the view held in the field when it was last
    /// drawn.
    private(set) var hub: ObjectHub

    /// What the walk found that object to be, the last time the view was
    /// drawn: what tells whether an object made with this frame's value of
    /// the view may take the state an earlier one left at its place.
    var lastObject = ObjectKind.unknown

    /// Whether the storage has dropped the token.
    private var isDropped = false

    init(holder: ViewIdentity, hub: ObjectHub) {
        self.holder = holder
        self.hub = hub
        hub.addHolder(holder)
    }

    /// The view holds another object in the field now.
    func move(to hub: ObjectHub) {
        self.hub.removeHolder(holder)
        hub.addHolder(holder)
        self.hub = hub
    }

    func markDropped() {
        guard !isDropped else { return }
        isDropped = true
        hub.removeHolder(holder)
    }
}

/// What the walk of an object found it to be, from when its `@State` was made
/// (``StateBacking/createdIn``).
enum ObjectKind: UInt8 {
    /// It holds no `@State` the walk reached, which would say.
    case unknown
    /// Made in the render pass that walked it, with a value of the view
    /// holding it (session notes `DYNV2/notes.md` §4.11): its `@State` is the
    /// place's, as a view value's is.
    case perValue
    /// Made before the pass, or kept from one: its `@State` is its own.
    case longLived
}
