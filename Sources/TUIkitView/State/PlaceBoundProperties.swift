//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PlaceBoundProperties.swift
//
//  One view value drawn at two places — `HStack { tally; tally }`, one value
//  handed to two children — holds one copy of each property per place, and
//  every copy shares what the property keeps behind a reference. The walk
//  binds each place in turn, so a reference every copy shares ends bound to
//  the second place, and a closure made in the first place's body reads the
//  second's. `@State` and `@Environment` give a copy at a second place a
//  reference of its own (DYNV bug 1). These are the same for the properties
//  bound to their place's identity and those that read through a reader.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A property bound to an id from its view's render identity, whose copies
/// share a reference — `@Namespace`, `@FocusState` — bound per place.
///
/// SwiftUI gives each place its own (measured:
/// `Tools/SwiftUIProbes/Dynamic property discovery/twoplaces.out`, a
/// namespace for each place one value is drawn at; decisions DYNVFIX,
/// B-DYNVFIX-5).
///
/// The rule, as `@State`'s and `@Environment`'s: a reference bound at another
/// place in this pass is this copy's second place, which takes a reference of
/// its own; one bound at another place in an earlier pass — a value kept
/// across frames and moved — is rebound where it lies, so a moved value takes
/// no new reference on every body.
package protocol PlaceBoundIdentity: RenderIdentityBindable {
    /// Binds the property at `address`, in the copy of a view drawn where
    /// `path` names, to its id there, in pass `pass`.
    ///
    /// - Returns: Whether the property at `address` was changed — given a
    ///   reference of its own — rather than its shared one bound.
    @MainActor
    static func bindRenderIdentity(
        at address: UnsafeMutableRawPointer, path: String, propertyIndex: Int, pass: UInt32
    ) -> Bool
}

/// A property handed its view's environment through a reader its copies
/// share — `@FocusedValue`, `@FocusedBinding` — resolved per place, by
/// ``PlaceBoundIdentity``'s rule.
package protocol PlaceResolvedReader: EnvironmentResolvable {
    /// Hands the property at `address`, in the copy of a view drawn at
    /// `place`, `environment`, in pass `pass`.
    ///
    /// - Returns: Whether the property at `address` was changed — given a
    ///   reader of its own — rather than its shared one resolved.
    @MainActor
    static func resolveEnvironment(
        at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues, place: ViewIdentity, pass: UInt32
    ) -> Bool
}

/// Where a reference its copies share was last bound: the place, and the
/// pass. What ``PlaceBoundIdentity`` and ``PlaceResolvedReader`` decide by.
package struct PlaceStamp<Place: Equatable> {
    package var place: Place?
    package var pass: UInt32 = 0

    package init() {}

    /// Whether a copy bound at `place` in `pass` is at a second place in the
    /// pass the stamp was made in: it was bound elsewhere in this same pass.
    package func isSecondPlace(_ place: Place, in pass: UInt32) -> Bool {
        guard let bound = self.place else { return false }
        return self.pass == pass && bound != place
    }

    /// Stamps the reference as bound at `place` in `pass`.
    package mutating func stamp(_ place: Place, in pass: UInt32) {
        self.place = place
        self.pass = pass
    }
}
