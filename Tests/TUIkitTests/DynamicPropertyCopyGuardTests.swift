//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyCopyGuardTests.swift
//
//  What `update()` changes is written back into the view value about to run
//  `body`, and into nothing else: not the value the caller holds, nor any
//  copy of it. Two kinds of property keep their value in a box their copies
//  share — an existential too big for its inline buffer, and an indirect
//  enum — so a write into one in place would reach every copy. They guard
//  the property walk's existential and enum write-back (session notes
//  DYNV/notes.md).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// Bigger than an existential's three-word inline buffer, so an existential
/// holding it keeps it in a heap box that copies share.
private struct BigCounting: DynamicProperty {
    var updates = 0
    var padding: (Int, Int, Int, Int) = (0, 0, 0, 0)

    mutating func update() {
        updates += 1
    }
}

private struct BigExistentialView: View {
    let p: any DynamicProperty

    var body: some View {
        Text(verbatim: "updates \((p as? BigCounting)?.updates ?? -1)")
    }
}

private struct BigAnyView: View {
    let p: Any

    var body: some View {
        Text(verbatim: "updates \((p as? BigCounting)?.updates ?? -1)")
    }
}

/// An app property that is an indirect enum: its payload lives in a box the
/// enum's copies share.
private indirect enum IndirectCounting: DynamicProperty {
    case on(BigCounting)

    var updates: Int {
        switch self {
        case .on(let counting): counting.updates
        }
    }
}

private struct IndirectView: View {
    let p: IndirectCounting

    var body: some View {
        Text(verbatim: "updates \(p.updates)")
    }
}

@MainActor
@Suite("DynamicProperty write-back into shared boxes")
struct DynamicPropertyCopyGuardTests {

    private func lines<V: View>(_ view: V, context: RenderContext) -> [String] {
        renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    /// The write-back copies an existential's value out, updates it and
    /// assigns it back, and the language copies a shared box before the
    /// write. A fix that wrote into the box in place would change the value
    /// the caller holds, and every copy of it. Holds whether TUIkit keeps
    /// updating existentials or drops them.
    @Test("update() on a property in a boxed existential changes neither the view value drawn nor its copies")
    func boxedExistentialIsNotWrittenInPlace() {
        let context = makeRenderContext(width: 20, height: 1)
        let view = BigExistentialView(p: BigCounting())
        let copy = view
        let first = lines(view, context: context)
        #expect(lines(view, context: context) == first, "each frame starts from the value given")
        #expect((view.p as? BigCounting)?.updates == 0)
        #expect((copy.p as? BigCounting)?.updates == 0)

        let anyView = BigAnyView(p: BigCounting())
        let anyCopy = anyView
        let anyFirst = lines(anyView, context: context)
        #expect(lines(anyView, context: context) == anyFirst, "each frame starts from the value given")
        #expect((anyView.p as? BigCounting)?.updates == 0)
        #expect((anyCopy.p as? BigCounting)?.updates == 0)
    }

    /// An enum's payload is written back in place, through its value
    /// witnesses (decisions-DYNP B-DYNP-1;
    /// `DynamicPropertyDiscoveryTests.enumPropertyPayloadWrittenBack`), but
    /// never into an indirect case's box, which every copy of the enum
    /// shares: that payload is updated on a copy (decisions-DYNVFIX
    /// B-DYNVFIX-2).
    @Test("update() on an indirect enum property changes no value another copy shares")
    func indirectEnumIsNotWrittenInPlace() {
        let context = makeRenderContext(width: 20, height: 1)
        let view = IndirectView(p: .on(BigCounting()))
        let copy = view
        let first = lines(view, context: context)
        #expect(lines(view, context: context) == first, "each frame starts from the value given")
        #expect(view.p.updates == 0)
        #expect(copy.p.updates == 0)
    }
}
