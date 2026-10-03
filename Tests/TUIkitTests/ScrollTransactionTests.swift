//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTransactionTests.swift
//
//  `Transaction.scrollTargetAnchor`, `.scrollContentOffsetAdjustmentBehavior`
//  and `.scrollPositionUpdatePreservesVelocity`: what a change made under a
//  transaction asks of the scroll views it moves. The run loop publishes the
//  transaction a change was made under for the frame that renders it; these
//  tests publish it the same way.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("Scroll transactions")
struct ScrollTransactionTests {

    @MainActor
    private struct Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        @discardableResult
        func render<V: View>(_ view: V, transaction: Transaction = Transaction(), height: Int = 6) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.transaction = transaction
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 20, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        }
    }

    private func anchoredBottom(_ anchor: UnitPoint) -> Transaction {
        var transaction = Transaction()
        transaction.scrollTargetAnchor = anchor
        return transaction
    }

    @Test("The members read back, with SwiftUI's defaults")
    func values() {
        var transaction = Transaction()
        #expect(transaction.scrollTargetAnchor == nil)
        #expect(transaction.scrollContentOffsetAdjustmentBehavior == .automatic)
        #expect(!transaction.scrollPositionUpdatePreservesVelocity)
        transaction.scrollTargetAnchor = .bottom
        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
        transaction.scrollPositionUpdatePreservesVelocity = true
        #expect(transaction.scrollTargetAnchor == .bottom)
        #expect(transaction.scrollContentOffsetAdjustmentBehavior == .disabled)
        #expect(transaction.scrollPositionUpdatePreservesVelocity)
        #expect(transaction != Transaction())
    }

    @Test("The members share bytes without touching each other, and the anchor keeps hundredths")
    func packedStorage() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        #expect(transaction.scrollContentOffsetAdjustmentBehavior == .automatic)
        #expect(!transaction.scrollPositionUpdatePreservesVelocity)
        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
        transaction.disablesAnimations = false
        #expect(transaction.scrollContentOffsetAdjustmentBehavior == .disabled)
        #expect(!transaction.disablesAnimations)

        transaction.scrollTargetAnchor = UnitPoint(x: 0.333, y: 0.7)
        #expect(transaction.scrollTargetAnchor == UnitPoint(x: 0.33, y: 0.7))
        transaction.scrollTargetAnchor = .zero
        #expect(transaction.scrollTargetAnchor == .zero, "zero is a point, not none")
        transaction.scrollTargetAnchor = nil
        #expect(transaction.scrollTargetAnchor == nil)
        // A Binding carries a transaction inline; the anchor costs two bytes.
        #expect(MemoryLayout<Transaction>.size == 76)
        #expect(interiorPadding(of: Transaction.self).isEmpty)
    }

    @Test("A transaction's anchor places the row an id binding asks for")
    func anchorForIDBinding() {
        let frames = Frames()
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
        }
        .scrollPosition(id: binding)
        frames.render(view)
        visible = 20
        let landed = frames.render(view, transaction: anchoredBottom(.bottom))
        #expect(landed.last == "row 20", "\(landed)")
    }

    @Test("A request's own anchor wins over the transaction's; without one, the transaction's applies")
    func anchorForPositionRequest() {
        let frames = Frames()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
        }
        .scrollPosition(binding)
        frames.render(view)
        position.scrollTo(id: 20)
        let unanchored = frames.render(view, transaction: anchoredBottom(.bottom))
        #expect(unanchored.last == "row 20", "\(unanchored)")
        position.scrollTo(id: 30, anchor: .top)
        let anchored = frames.render(view, transaction: anchoredBottom(.bottom))
        #expect(anchored.first == "row 30", "\(anchored)")
    }

    @Test("A disabled adjustment leaves a following ScrollView where it is, and releases the follow")
    func disabledAdjustmentReleasesScrollViewFollow() {
        let frames = Frames()
        var count = 10
        func view() -> some View {
            ScrollView {
                VStack(spacing: 0) { ForEach(0..<count, id: \.self) { Text("row \($0)") } }
            }
            .defaultScrollAnchor(.bottom)
        }
        let opened = frames.render(view())
        #expect(opened.last == "row 9", "precondition: following the tail \(opened)")

        var disabled = Transaction()
        disabled.scrollContentOffsetAdjustmentBehavior = .disabled
        count = 13
        let held = frames.render(view(), transaction: disabled)
        #expect(held.last == "row 9", "not followed: \(held)")
        count = 14
        let after = frames.render(view())
        #expect(after.last == "row 9", "released, as a user scroll releases it: \(after)")

        // Control: without the transaction it follows.
        let control = Frames()
        count = 10
        control.render(view())
        count = 13
        #expect(control.render(view()).last == "row 12")
    }

    @Test("A disabled adjustment leaves a following List where it is, and releases the follow")
    func disabledAdjustmentReleasesListFollow() {
        let frames = Frames()
        var count = 10
        func view() -> some View {
            List(0..<count, id: \.self) { Text("row \($0)") }
                .defaultScrollAnchor(.bottom)
        }
        frames.render(view(), height: 8)
        let opened = frames.render(view(), height: 8)
        #expect(opened.contains { $0.contains("row 9 ") }, "precondition: \(opened)")
        var disabled = Transaction()
        disabled.scrollContentOffsetAdjustmentBehavior = .disabled
        count = 13
        let held = frames.render(view(), transaction: disabled, height: 8)
        #expect(!held.contains { $0.contains("row 12 ") }, "not followed: \(held)")
        count = 14
        let after = frames.render(view(), height: 8)
        #expect(!after.contains { $0.contains("row 13 ") }, "released: \(after)")

        let control = Frames()
        count = 10
        control.render(view(), height: 8)
        count = 13
        #expect(control.render(view(), height: 8).contains { $0.contains("row 12 ") })
    }
}
