//  🖥️ TUI — A Terminal UI framework for Swift
//  StackFocusAddress.swift
//
//  The row of a windowed stack a focus ID or a seek addresses, found by key
//  or by path without building a row where it can be (split out of
//  `StackFocusReach.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

@MainActor extension _VStackCore {
    /// The row of this stack's a seek names: by its key, or — a focus reveal
    /// (``ScrollToRequest/focusID``) — the row the focused control lies in,
    /// by its route (``targetOrdinal(for:children:state:context:)``).
    func seekOrdinal(
        _ seek: ScrollToRequest, children: ChildViewCollection, state: StackWindowState, context: RenderContext
    ) -> Int? {
        guard let focusID = seek.focusID else {
            return resolveOrdinal(forKey: seek.key, children: children, state: state)
        }
        return targetOrdinal(for: focusID, children: children, state: state, context: context)
    }

    /// The ordinal of the row a focus ID addresses below this stack: memo
    /// hit, else one key scan (never builds a row view). Shared by the
    /// uniform and anchored paths (targets, seeks, and ring continuation).
    /// An explicit ID is found by where its control registered
    /// (``focusAddress(_:belowStackPath:context:)``).
    func targetOrdinal(
        for focusID: String?, children: ChildViewCollection,
        state: StackWindowState, context: RenderContext
    ) -> Int? {
        guard let focusID else { return nil }
        let stackPath = context.identity.path
        let address = Self.focusAddress(focusID, belowStackPath: stackPath, context: context)
        guard let key = Self.rowKey(inFocusID: address, belowStackPath: stackPath),
            let ordinal = resolveOrdinal(forKey: key, children: children, state: state)
        else { return nil }
        return Self.memberOrdinal(near: ordinal, key: key, addressedBy: address, children: children)
    }

    /// What finds the control `focusID` names below the stack at `stackPath`:
    /// the id itself when it embeds the stack's path, as a default id does
    /// (`"button-<path>"`), else the identity path the control last
    /// registered at (``FocusManager/identityPath(of:)``).
    ///
    /// An explicit `.focusID(_:)` embeds no path, and found by the id alone a
    /// row whose control had one was never found: neither the focused row's
    /// neighbours nor the rows past a run with nothing to focus were drawn for
    /// it, so the arrows and Tab left the stack early for the control outside
    /// it (found by the geometric arrows' lane, 2026-11-17). Its registration
    /// knows where it is.
    static func focusAddress(_ focusID: String, belowStackPath stackPath: String, context: RenderContext) -> String {
        guard !focusID.contains(stackPath), let focusManager = context.environment.focusManager else { return focusID }
        return focusManager.identityPath(of: focusID)
    }

    /// The ordinal, among the children keyed `key` around `ordinal`, of the
    /// one `focusID` addresses.
    ///
    /// A key names one child for a row of one view, and this is `ordinal`
    /// after two key reads. The views of a `ForEach` row of several (decisions
    /// B15) share their row's key, each at an identity of its own below the
    /// row's, so the run of them is walked and the one whose identity the ID
    /// names is taken: the key alone named the run's first, or whichever the
    /// ordinal memo last saw, and the focused view itself went unrendered —
    /// so it registered nothing, and the focus moved to a row in the band.
    static func memberOrdinal(
        near ordinal: Int, key: String, addressedBy focusID: String, children: ChildViewCollection
    ) -> Int {
        let sharesBefore = ordinal > 0 && children.key(at: ordinal - 1) == key
        let sharesAfter = ordinal + 1 < children.count && children.key(at: ordinal + 1) == key
        guard sharesBefore || sharesAfter else { return ordinal }
        var start = ordinal
        while start > 0, children.key(at: start - 1) == key { start -= 1 }
        var member = start
        while member < children.count, children.key(at: member) == key {
            if let identity = children[member].pinnedIdentity,
                FocusManager.focusID(focusID, addressesSubtreeAt: identity.path)
            {
                return member
            }
            member += 1
        }
        return ordinal
    }
}

// MARK: - The row a focus ID addresses

@MainActor extension _VStackCore {
    /// The slot index of the row whose subtree a focus ID addresses, when the
    /// addressed control lives under one of this stack's rows: by the path a
    /// default (identity-path-derived) ID embeds, or the one an explicit ID's
    /// control registered at (``focusAddress(_:belowStackPath:context:)``).
    ///
    /// Cheap rejection first: unless that path is below this stack's own,
    /// no row can match and no per-row path is materialised. When it does,
    /// the scan renders each row's identity path — O(rows) string work, only
    /// on frames where focus (or a pending target) is inside this stack.
    func rowIndex(
        addressedBy focusID: String?, slots: [RowSlot], context: RenderContext
    ) -> Int? {
        guard let focusID else { return nil }
        let stackPath = context.identity.path
        let address = Self.focusAddress(focusID, belowStackPath: stackPath, context: context)
        guard address.contains(stackPath) else { return nil }
        return slots.firstIndex { slot in
            FocusManager.focusID(address, addressesSubtreeAt: slot.child.identity(under: context).path)
        }
    }
}
