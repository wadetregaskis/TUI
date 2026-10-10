//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UsableFromInlineSendabilityTests.swift
//
//  The value types that module split step A3 made `@usableFromInline` are still
//  `Sendable`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

/// The compiler infers `Sendable` only for a type that is not usable from inline
/// code. Making a type `@usableFromInline` therefore drops the conformance without
/// a word. So does the conformance of every type that stores one (a
/// ``ScrollIndicatorLine`` stores a ``ClaimingRow``). Nothing failed at the time,
/// because nothing asked. The first `static let` of one, or the first `Sendable`
/// capture, would have failed to compile with no hint of why.
///
/// Each type below states `Sendable` now. This suite checks that at compile time:
/// remove one of the conformances and the test target stops building. Caseless
/// namespaces (`FocusRegistration`, `ANSIRenderer`) and the environment keys have
/// no values anyone holds, so they are not listed.
@Suite("Value types usable from inline code stay Sendable")
struct UsableFromInlineSendabilityTests {
    private func requireSendable<T: Sendable>(_: T.Type) {}

    @Test("Each value type step A3 made @usableFromInline is still Sendable")
    func valueTypesStaySendable() {
        requireSendable(ClaimingRow.self)
        requireSendable(ScrollIndicatorLine.self)
        requireSendable(ScrollAnchorMode.self)
        requireSendable(MouseHandlerLane.self)
        requireSendable(HandlerDrawing.self)
        requireSendable(ResolvedScrollIndicators.self)
        requireSendable(SelectionContextMenuReference.self)
    }

    /// Module split step C2 made ``ScrollRowWindow`` `@usableFromInline`, for a
    /// `Table` in TUIkitTables to inline its resolver, and stated `Sendable` with
    /// it.
    @Test("The scroll row window step C2 made @usableFromInline is still Sendable")
    func scrollRowWindowStaysSendable() {
        requireSendable(ScrollRowWindow.self)
    }
}
