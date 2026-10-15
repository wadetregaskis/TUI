//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FlexibleFrameSwiftUIRuleTests.swift
//
//  A flexible frame sizes itself as SwiftUI's does: a maximum fills the offer
//  up to it, a minimum raises the content to it, and an ideal is read only
//  when nothing was offered. Every expected width here is what SwiftUI drew
//  for the same frame, `Tools/SwiftUIProbes/Flexible frames/frame.out`, but
//  the one difference `FlexibleFrameAxis` documents.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A flexible frame's size, as SwiftUI's")
struct FlexibleFrameSwiftUIRuleTests {
    private let short = "Short"  // 5
    private let long = "A noticeably longer line of text here"  // 37

    private func context(width: Int = 80, height: Int = 24) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// The frame's width offered `offer` columns, or offered none (`nil`), as
    /// under `.fixedSize()` — and the measure agreeing with the drawing.
    private func width<V: View>(_ view: V, offer: Int?) -> Int {
        let context = context(width: offer ?? 80)
        let buffer =
            offer == nil
            ? renderToBuffer(view.fixedSize(), context: context)
            : renderToBuffer(view, context: context)
        let measured =
            offer == nil
            ? measureChild(view.fixedSize(), proposal: .unspecified, context: context)
            : measureChild(view, proposal: ProposedSize(width: offer, height: nil), context: context)
        #expect(measured.width == buffer.width, "measured \(measured.width), drew \(buffer.width)")
        return buffer.width
    }

    /// The frame's height offered `offer` lines, or offered none (`nil`).
    private func height<V: View>(_ view: V, offer: Int?) -> Int {
        let context = context(height: offer ?? 24)
        let view = view.fixedSize(horizontal: false, vertical: offer == nil)
        return renderToBuffer(view, context: context).height
    }

    @Test("A maximum fills the offer up to it")
    func maximumFillsTheOffer() {
        #expect(width(Text(short).frame(maxWidth: 30), offer: 80) == 30)
        #expect(width(Text(short).frame(maxWidth: 30), offer: 20) == 20)
        #expect(width(Text(short).frame(maxWidth: 30), offer: nil) == 5)
        #expect(width(Text(long).frame(maxWidth: 30), offer: nil) == 30)
        #expect(width(Text(short).frame(maxWidth: 3), offer: 80) == 3)
        #expect(width(Text(short).frame(maxWidth: .infinity), offer: 80) == 80)
        #expect(width(Text(short).frame(maxWidth: .infinity), offer: nil) == 5)
    }

    @Test("A minimum and a maximum fill the offer between them")
    func minimumAndMaximum() {
        #expect(width(Text(short).frame(minWidth: 10, maxWidth: 30), offer: 80) == 30)
        #expect(width(Text(short).frame(minWidth: 10, maxWidth: 30), offer: 20) == 20)
        #expect(width(Text(short).frame(minWidth: 10, maxWidth: 30), offer: nil) == 10)
        #expect(width(Text(short).frame(minWidth: 0, maxWidth: .infinity), offer: 80) == 80)
        #expect(width(Text(short).frame(minWidth: 0, maxWidth: .infinity), offer: nil) == 5)
    }

    @Test("A minimum alone raises the content to it")
    func minimumAlone() {
        #expect(width(Text(short).frame(minWidth: 10), offer: 80) == 10)
        #expect(width(Text(short).frame(minWidth: 10), offer: nil) == 10)
        #expect(width(Text(long).frame(minWidth: 10), offer: 80) == 37)
    }

    @Test("Offered a width, the ideal is not read")
    func idealIgnoredWhenOffered() {
        #expect(width(Text(short).frame(idealWidth: 10), offer: 80) == 5)
        #expect(width(Text(short).frame(idealWidth: 50), offer: 80) == 5)
        // It once capped what the content was offered: the line wrapped at 10.
        #expect(width(Text(long).frame(idealWidth: 10), offer: 80) == 37)
        #expect(width(Text(short).frame(minWidth: 10, idealWidth: 20), offer: 80) == 10)
        #expect(width(Text(short).frame(idealWidth: 20, maxWidth: 30), offer: 80) == 30)
        #expect(width(Text(short).frame(idealWidth: 20, maxWidth: .infinity), offer: 80) == 80)
    }

    @Test("Offered nothing, a frame with a maximum is its ideal")
    func idealWhenOfferedNothing() {
        #expect(width(Text(short).frame(idealWidth: 20, maxWidth: 30), offer: nil) == 20)
        #expect(width(Text(short).frame(idealWidth: 20, maxWidth: .infinity), offer: nil) == 20)
        #expect(width(Text(long).frame(idealWidth: 10), offer: nil) == 10)
    }

    @Test("Offered nothing, a frame with an ideal and no maximum is its content's size")
    func idealWithoutMaximumIsTheContents() {
        // The one difference (`FlexibleFrameAxis`): SwiftUI's frames are 10
        // and 20, the ideal itself.
        #expect(width(Text(short).frame(idealWidth: 10), offer: nil) == 5)
        #expect(width(Text(short).frame(minWidth: 10, idealWidth: 20), offer: nil) == 10)
    }

    @Test("Contradictory constraints are put in order")
    func contradictoryConstraints() {
        #expect(width(Text(short).frame(idealWidth: 40, maxWidth: 30), offer: 80) == 40)
        #expect(width(Text(short).frame(idealWidth: 40, maxWidth: 30), offer: 20) == 20)
        #expect(width(Text(short).frame(idealWidth: 40, maxWidth: 30), offer: nil) == 40)
    }

    @Test("Heights follow the same rule")
    func heights() {
        #expect(height(Text(short).frame(maxHeight: 5), offer: 10) == 5)
        #expect(height(Text(short).frame(maxHeight: 5), offer: 2) == 2)
        #expect(height(Text(short).frame(maxHeight: 5), offer: nil) == 1)
        #expect(height(Text(short).frame(minHeight: 2, maxHeight: 5), offer: 10) == 5)
        #expect(height(Text(short).frame(minHeight: 2, maxHeight: 5), offer: nil) == 2)
        #expect(height(Text(short).frame(idealHeight: 3), offer: 10) == 1)
    }

    @Test("An integer literal is a fixed maximum")
    func integerLiteral() {
        let dimension: FrameDimension = 12
        #expect(dimension == .fixed(12))
    }
}
