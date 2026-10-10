//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListHugHeightTests.swift
//
//  A list told `.fixedSize(horizontal: true, vertical: false)` hugs its rows'
//  width and keeps filling the height it is given — flexibly, so a view stacked
//  below it is still laid out. Reported as a FIXED height, the list demanded
//  the whole column and pushed the view below off the bottom.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("List hug height")
struct ListHugHeightTests {
    @Test("A view below a horizontally hugging list is still drawn")
    func viewBelowAHuggingListIsDrawn() {
        let view = VStack(alignment: .leading, spacing: 0) {
            List {
                Text("alpha")
                Text("beta")
            }
            .fixedSize(horizontal: true, vertical: false)
            Text("FOOTER")
        }
        let lines = renderToBuffer(view, context: makeRenderContext(width: 30, height: 8)).lines.map(\.stripped)
        #expect(lines.count <= 8, "\(lines)")
        #expect(lines.contains { $0.contains("FOOTER") }, "\(lines)")
        #expect(lines.contains { $0.contains("alpha") }, "\(lines)")
    }

    @Test("A hugging list reports its width fixed and its height flexible")
    func hugSize() {
        var context = makeRenderContext(width: 30, height: 8)
        context.environment.fixedSizeWidth = true
        let size = measureChild(
            List {
                Text("alpha")
            }, proposal: ProposedSize(width: nil, height: 8), context: context)
        #expect(!size.isWidthFlexible && size.isHeightFlexible, "\(size)")
        #expect(size.width < 30, "\(size)")
    }
}
