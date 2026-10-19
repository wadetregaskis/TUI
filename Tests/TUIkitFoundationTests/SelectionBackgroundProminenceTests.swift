//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectionBackgroundProminenceTests.swift
//
//  A `.selection` background raises `\.backgroundProminence` for the content
//  drawn over it — SwiftUI's documentation of the environment value says its
//  standard styles do — and no other background does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A view that says which prominence its content was drawn under. Equatable by
/// its name alone, so `.equatable()` memoizes it whatever the prominence.
private struct ProminenceProbe: View, Equatable {
    let name: String
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text("\(name):\(prominence == .increased ? "raised" : "plain")")
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
}

@MainActor
@Suite("A selection background raises its content's prominence")
struct SelectionBackgroundProminenceTests {
    /// What the probe in `view` said, rendered once.
    private func said(_ view: some View) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 3)).lines.map(\.stripped).joined()
    }

    @Test("The selection behind a view raises it, in each spelling of the background")
    func selectionRaises() {
        #expect(said(ProminenceProbe(name: "a").background(.selection)).contains("a:raised"))
        #expect(said(ProminenceProbe(name: "a").background(AnyShapeStyle(.selection))).contains("a:raised"))
        #expect(said(ProminenceProbe(name: "a").background(AnyShapeStyle(AnyShapeStyle(.selection)))).contains("a:raised"))
        #expect(said(ProminenceProbe(name: "a").background(.selection, in: Capsule())).contains("a:raised"))
        #expect(said(VStack { ProminenceProbe(name: "a") }.padding(1).background(.selection)).contains("a:raised"))
    }

    @Test("Any other background leaves the prominence as it was")
    func otherBackgroundsDoNotRaise() {
        #expect(said(ProminenceProbe(name: "a")).contains("a:plain"))
        #expect(said(ProminenceProbe(name: "a").background(.red)).contains("a:plain"))
        #expect(said(ProminenceProbe(name: "a").background(.tint)).contains("a:plain"))
        #expect(said(ProminenceProbe(name: "a").background(AnyShapeStyle(.red))).contains("a:plain"))
        #expect(said(ProminenceProbe(name: "a").background(.red, in: Capsule())).contains("a:plain"))
        // The prominence is the background's alone: a selection fill drawn as
        // a view behind the probe, or in front of it, is not one.
        #expect(said(ProminenceProbe(name: "a").foregroundStyle(.selection)).contains("a:plain"))
    }

    @Test("A raise from an erased style comes and goes with it, through a memo below")
    func erasedSelectionFlipsThroughAMemo() {
        let context = makeRenderContext(width: 30, height: 3)
        let cache = context.renderCache!
        func frame(selected: Bool) -> String {
            cache.beginRenderPass()
            defer { cache.removeInactive() }
            let style = selected ? AnyShapeStyle(.selection) : AnyShapeStyle(.red)
            let view = ProminenceProbe(name: "a").equatable().background(style)
            return renderToBuffer(view, context: context).lines.map(\.stripped).joined()
        }
        #expect(frame(selected: true).contains("a:raised"))
        #expect(frame(selected: false).contains("a:plain"), "served the raised picture after the raise went")
        #expect(frame(selected: true).contains("a:raised"), "served the plain picture after the raise came back")
    }
}
