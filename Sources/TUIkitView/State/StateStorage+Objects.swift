//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StateStorage+Objects.swift
//
//  What the state storage keeps for the class properties views hold: each
//  object's hub, the views drawn holding it, and the places that keep the
//  state of an object made with a view value.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension StateStorage {
    /// The hub of `object`, if a render walk has made one
    /// (``registerHolder(_:of:at:kind:)``). A hub whose object has gone is not
    /// `object`'s, though `object` was made at its address.
    func objectHub(of object: AnyObject) -> ObjectHub? {
        guard let hub = objectHubs[ObjectIdentifier(object)], hub.object === object else { return nil }
        return hub
    }

    /// The record that `holder` held an object in the field whose scope is
    /// `scope`, if it has been drawn holding one there and its state is kept.
    func holderToken(_ holder: ViewIdentity, at scope: UInt64) -> HolderToken? {
        values[StateKey(identity: holder, propertyIndex: StateKey.objectHolderIndex, scope: scope)] as? HolderToken
    }

    /// Registers `holder`, drawn, as holding `object` in the field whose
    /// scope is `scope`: the object's hub made if it has none, the view's
    /// ``HolderToken`` for the field made or moved to the hub, and the view
    /// made the hub's primary if it has none. A render walk's, never a
    /// measure's.
    ///
    /// A new hub's ids are the object's own — unless the object the view held
    /// in the field when last drawn was made with that frame's value of the
    /// view, or held no `@State` to say, and this one was made in this pass
    /// too, or holds no `@State` at a fixed offset to say (`kind`): then it
    /// is one of a chain of objects made with the view's values, which share
    /// their first's ids, as a view value's `@FocusState` keeps its id from
    /// frame to frame. A hub with a chain's ids takes its own once its object
    /// is found made before the pass that walks it (``giveOwnIDs(to:)``): it
    /// was made on demand in a body, and kept.
    ///
    /// - Returns: The hub; the view's token for the field, in which the walk
    ///   notes what it finds the object to be; what the token said of the
    ///   object the view held there last, before this walk; and, when that
    ///   was another object made with a view value, its hub: the object an
    ///   object made with this frame's value takes the place's state from
    ///   (``placeBox(_:at:adopting:from:)``).
    func registerHolder(
        _ holder: ViewIdentity, of object: AnyObject, at scope: UInt64, kind: () -> ObjectKind
    ) -> (hub: ObjectHub, token: HolderToken, previous: ObjectKind, predecessor: ObjectHub?) {
        let key = StateKey(identity: holder, propertyIndex: StateKey.objectHolderIndex, scope: scope)
        let token = values[key] as? HolderToken
        let hub: ObjectHub
        if let found = objectHub(of: object) {
            hub = found
            if hub.takesChainIDs, kind() == .longLived { giveOwnIDs(to: hub) }
        } else {
            if let token, token.lastObject != .longLived, kind() != .longLived {
                hub = ObjectHub(object: object, link: renderCacheLink, idPath: token.hub.idPath, takesChainIDs: true)
            } else {
                hub = ObjectHub(object: object, link: renderCacheLink, idPath: newObjectIDPath(), takesChainIDs: false)
            }
            objectHubs[ObjectIdentifier(object)] = hub
        }
        if hub.primary == nil { hub.primary = holder }
        if let token {
            guard token.hub !== hub else { return (hub, token, token.lastObject, nil) }
            let predecessor = token.lastObject == .perValue ? token.hub : nil
            token.move(to: hub)
            return (hub, token, token.lastObject, predecessor)
        }
        let made = HolderToken(holder: holder, hub: hub)
        values[key] = made
        return (hub, made, .unknown, nil)
    }

    /// Gives `hub`, whose ids are a chain's, ids of its object's own: its
    /// object was made before the pass that walks it.
    func giveOwnIDs(to hub: ObjectHub) {
        hub.takeOwnIDs(newObjectIDPath())
    }

    /// A path for an object's ids no other object's hub has been given.
    private func newObjectIDPath() -> String {
        // Wrapping: a view whose identity changes every frame, holding an
        // object made with each of its values, starts a chain a frame, and
        // `Int` is 32 bits on WebAssembly — 500 such rows at sixty frames a
        // second would trap within a day.
        objectIDs &+= 1
        return "obj\(objectIDs)"
    }

    /// The box kept under `key` for an object made with a view value in the
    /// pass that walks it: the one the place keeps already when `adopting` —
    /// the state an object made with the view's last value left — and
    /// otherwise `own`, the object's backing's box, which holds what was
    /// written to it before the walk, kept in place of whatever was there.
    ///
    /// The object the place's state is taken from, `predecessor`'s, is left
    /// what it held, if it is alive: it may have been made on demand in a
    /// body and kept rather than with a view value — the two look alike in
    /// the pass that first walks them — and a walk that finds it again takes
    /// that back (``ObjectHub/takeState(handedOverWith:)``), rather than the
    /// state the new object goes on to write into the box they share.
    func placeBox<Value>(
        _ own: StateBox<Value>, at key: StateKey, adopting: Bool, from predecessor: ObjectHub?
    ) -> StateBox<Value> {
        if adopting, let kept = values[key] as? StateBox<Value> {
            kept.identity = key.identity
            if let predecessor, predecessor.object != nil {
                let left = StateBox(kept.value)
                left.invalidationSink = predecessor
                predecessor.keep(left, handedOverWith: kept)
            }
            return kept
        }
        own.identity = key.identity
        if let replaced = values.updateValue(own, forKey: key), replaced !== own {
            (replaced as? any DroppableBox)?.markDropped()
        }
        return own
    }

    // MARK: Environments put back

    /// How many `@Environment`s inside objects are waiting to be put back:
    /// what a composite view notes before its body is evaluated, and puts
    /// back to after the body's content (``restoreEnvironments(to:)``).
    var environmentRestoreDepth: Int {
        @inline(__always) get { restoreDepth.pointee }
    }

    /// Notes that a walk other than `hub`'s object's primary holder's is
    /// about to hand `box`, an `@Environment`'s inside the object, its view's
    /// environment, `box` holding `previous` until then.
    func pushEnvironmentRestore(_ box: EnvironmentBox, previous: EnvironmentValues?, hub: ObjectHub?) {
        environmentRestores.append(
            EnvironmentRestore(box: box, previous: previous, hub: hub, primaryWalks: hub?.primaryWalks ?? 0))
        restoreDepth.pointee = environmentRestores.count
    }

    /// Puts back, last first, what the walks noted since the count was
    /// `depth` handed the `@Environment`s inside objects: each box gets what
    /// it held before — or, if its object's primary holder walked since, the
    /// primary's environment — and none is set back to `nil`. Called after a
    /// composite body's content is drawn or measured, at the pass's end, and
    /// nowhere else: a load and a compare when nothing is waiting.
    @inline(__always)
    func restoreEnvironments(to depth: Int) {
        if restoreDepth.pointee > depth { popEnvironmentRestores(to: depth) }
    }

    @inline(never)
    private func popEnvironmentRestores(to depth: Int) {
        while environmentRestores.count > depth {
            let restore = environmentRestores.removeLast()
            if let hub = restore.hub, hub.primaryWalks != restore.primaryWalks, let rest = hub.rest {
                restore.box.environment = rest
            } else if let previous = restore.previous {
                restore.box.environment = previous
            }
        }
        restoreDepth.pointee = environmentRestores.count
    }
}

/// An `@Environment`'s box inside a class property's object that a walk other
/// than the object's primary holder's resolved, and what to put back
/// (``StateStorage/restoreEnvironments(to:)``).
struct EnvironmentRestore {
    let box: EnvironmentBox
    /// What the box held before the walk.
    let previous: EnvironmentValues?
    /// The object's hub, if a render walk made one.
    let hub: ObjectHub?
    /// The hub's ``ObjectHub/primaryWalks`` when the walk resolved the box.
    let primaryWalks: Int
}
