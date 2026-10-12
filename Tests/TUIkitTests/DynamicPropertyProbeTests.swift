//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyProbeTests.swift
//
//  A view whose fields the property walk acts on only if their values say so
//  — an existential, or an optional of one — is probed where it lies before
//  any copy of it is made: if no field holds anything the walk acts on, its
//  body is evaluated on the view as it is, as a view holding no property's
//  is. Such a field's dynamic type is read where it lies, never by copying
//  the value out into an `Any`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// An object whose retain count the bodies record: one more while a copy of
/// the view holding it lives.
private final class Token {}

/// What each body recorded.
@MainActor
private final class Counts {
    var retains: [String: UInt] = [:]
}

/// A protocol a view's existential field is declared as.
private protocol Shape {}

/// A shape that is no property, too big for an existential's inline
/// buffer.
private struct Square: Shape {
    var side = 1
    var corners = (0, 0, 0, 0)
}

/// Holds the token and nothing the walk acts on.
private struct PlainHolder: View {
    let token: Token
    let counts: Counts

    var body: some View {
        counts.retains["plain"] = _getRetainCount(token)
        return Text(verbatim: "plain")
    }
}

/// Holds the token and an existential that holds no property.
private struct ShapeHolder: View {
    let token: Token
    let shape: any Shape
    let counts: Counts

    var body: some View {
        counts.retains["shape"] = _getRetainCount(token)
        return Text(verbatim: "shape")
    }
}

@MainActor
@Suite("DynamicProperty probes")
struct DynamicPropertyProbeTests {

    /// Every body of a view holding an existential field copied the view
    /// before walking it, and copied the field's value out into an `Any` to
    /// read its type, where the walks it replaced had skipped the type after
    /// a first body that found nothing (decisions-DYNP B-DYNP-2's bug: what
    /// the field held later was never looked at). The field's type is now
    /// read where it lies, and one found holding nothing is noted, so a later
    /// body holding it again evaluates the view as it is: the token is
    /// retained no more often than a view holding no existential retains it.
    @Test("A view whose existential holds no property is evaluated as it is, with no copy of the view")
    func existentialHoldingNothingIsNotCopied() {
        let context = makeRenderContext(width: 20, height: 1)
        let token = Token()
        let counts = Counts()
        _ = renderToBuffer(PlainHolder(token: token, counts: counts), context: context)
        // The first body of the type finds `Square` unknown and walks it.
        _ = renderToBuffer(ShapeHolder(token: token, shape: Square(), counts: counts), context: context)
        _ = renderToBuffer(ShapeHolder(token: token, shape: Square(), counts: counts), context: context)
        #expect(counts.retains["shape"] == counts.retains["plain"])
    }
}
