//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StateStorage+Objects.swift
//
//  What the state storage keeps for the class properties views hold: which
//  view each object's contents belong to, and the object's `@State` boxes,
//  kept under that view's key.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension StateStorage {
    /// Whether the walk of the view at `claimant`, under `environment`,
    /// walks what `object`, a class instance the view holds in a property
    /// field, holds: its `@State` bound to the view's key, its `@Environment`
    /// resolved to `environment` (``PropertyWalk``).
    ///
    /// An object's contents belong to one view at a time, its claimant: in
    /// each render pass, the first view drawn whose walk reaches it. The
    /// claimant walks them on every walk of its own — the last of a pass that
    /// walks the tree twice decides — and every other holder leaves them as
    /// the claimant left them. A measure never takes them from another view,
    /// and its own claim, made while the object has none, is only
    /// provisional: a view only measured may never be drawn (a
    /// `ViewThatFits` candidate). A view drawn takes them from a claimant
    /// not yet drawn in the pass — one that has left (a `ViewThatFits`
    /// switch, a row removed), or is only measured or served from the memo
    /// this pass. The object's `@State` is the object's: its claimant's walk
    /// keeps each box the object holds under the claimant's key
    /// (``keep(_:for:)``), so one object has one state whichever view draws
    /// it. A claim lasts while its claimant's state does: it is dropped at
    /// the end of a pass in which its claimant was neither drawn nor retained
    /// (by a memo hit or a windowing container), and the next holder to
    /// reach the object then claims it, the object's state with it.
    ///
    /// A measure that finds the object another view's, not yet walked by it
    /// in this pass, would leave its body reading what that view's last walk
    /// left, and nothing has resolved a property set on the object since:
    /// an `@Environment(Model.self)` there traps when read. Such a measure
    /// hands each `@Environment` in the object that has none the
    /// environment of the claimant's last walk, kept with the claim, and
    /// changes nothing else (``ObjectContentsClaim/fillEnvironment(_:)``).
    func claimObjectContents(
        _ object: AnyObject, for claimant: ViewIdentity, environment: EnvironmentValues, isMeasuring: Bool
    ) -> ObjectContentsClaim {
        let id = ObjectIdentifier(object)
        guard let index = objectClaims.index(forKey: id), objectClaims.values[index].object === object else {
            objectClaims[id] = ObjectClaim(
                object: object, claimant: claimant, environment: environment, walkedPass: renderPass,
                drawnPass: isMeasuring ? nil : renderPass)
            return .walk
        }
        // Changed in place: a new record would form a new weak reference to
        // the object.
        return objectClaims.values[index].contents(
            for: claimant, environment: environment, in: renderPass, isMeasuring: isMeasuring)
    }

    /// Keeps `box`, a `@State` box an object holds, under `key`, its
    /// claimant's (``claimObjectContents(_:for:environment:isMeasuring:)``):
    /// the object's state is its own, and goes with it from view to view. A
    /// box the storage dropped — its claimant's place pruned, its key given
    /// to another object's box — is kept again, with its value: the object
    /// held it all along. One kept under another key, the claimant's before,
    /// is moved. Whatever was kept under `key` until now is dropped; another
    /// object holding it keeps it again when its claimant next walks it.
    func keep<Value>(_ box: StateBox<Value>, for key: StateKey) {
        box.identity = key.identity
        box.invalidationSink = renderCacheLink
        if values[key] === box { return }
        if box.wasDropped {
            box.markKept()
        } else {
            // Kept under the key of the claimant before: a claim changes hands
            // rarely, so the key is found by a scan rather than kept in every
            // box. A loop, not `first(where:)`: a closure handed to the
            // standard library from here is checked, in a release build, to
            // run on the main actor.
            var previous: StateKey?
            for (kept, value) in values where value === box {
                previous = kept
                break
            }
            if let previous { values.removeValue(forKey: previous) }
        }
        (values.updateValue(box, forKey: key) as? any DroppableBox)?.markDropped()
    }
}

/// The view a class property's contents belong to
/// (``StateStorage/claimObjectContents(_:for:environment:isMeasuring:)``).
struct ObjectClaim {
    /// The object, held weakly.
    weak var object: AnyObject?
    /// The view whose walk walks what the object holds.
    private(set) var claimant: ViewIdentity
    /// The environment of the claimant's last walk of the object: what a
    /// measure that reaches the object before the claimant in a pass hands
    /// an `@Environment` in it that has none.
    private(set) var environment: EnvironmentValues
    /// The render pass the claimant last walked the object in, measured or
    /// drawn.
    private(set) var walkedPass: Int
    /// The render pass the claimant was last drawn in holding it, or `nil`
    /// while it has only been measured.
    private(set) var drawnPass: Int?

    init(object: AnyObject, claimant: ViewIdentity, environment: EnvironmentValues, walkedPass: Int, drawnPass: Int?) {
        self.object = object
        self.claimant = claimant
        self.environment = environment
        self.walkedPass = walkedPass
        self.drawnPass = drawnPass
    }

    /// What a walk by `claimant`, under `environment`, in render pass `pass`,
    /// does with the object's contents
    /// (``StateStorage/claimObjectContents(_:for:environment:isMeasuring:)``),
    /// the claim brought up to date with it.
    mutating func contents(
        for claimant: ViewIdentity, environment: EnvironmentValues, in pass: Int, isMeasuring: Bool
    ) -> ObjectContentsClaim {
        if claimant != self.claimant {
            // Taken only by a view drawn, from a claimant not drawn in this
            // pass.
            guard !isMeasuring, drawnPass != pass else {
                return walkedPass == pass ? .skip : .fillEnvironment(self.environment)
            }
            self.claimant = claimant
            drawnPass = pass
        } else if !isMeasuring, drawnPass != pass {
            // Stamped with this pass's identity too, so the next compare
            // stops at the first node the two share rather than walk the
            // chain of the frame the claim was made in.
            self.claimant = claimant
            drawnPass = pass
        }
        walkedPass = pass
        self.environment = environment
        return .walk
    }
}

/// What a walk does with what an object holds
/// (``StateStorage/claimObjectContents(_:for:environment:isMeasuring:)``).
enum ObjectContentsClaim {
    /// Leaves it as its claimant left it in this pass: the walk's view is
    /// not the claimant.
    case skip
    /// Leaves it as its claimant last left it, but for each `@Environment`
    /// in it never handed an environment, which is handed this one, the
    /// claimant's last: the walk is a measure, and the claimant has not
    /// walked the object in this pass. Nothing is bound, no claim or state
    /// moves, and no property in it is updated.
    case fillEnvironment(EnvironmentValues)
    /// Walks it: the walk's view is its claimant, under whose key each
    /// `@State` box it holds is kept (``StateStorage/keep(_:for:)``).
    case walk
}
