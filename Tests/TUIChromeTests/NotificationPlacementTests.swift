//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationPlacementTests.swift
//
//  Where toasts are drawn: six placements, each a channel stacking its own
//  toasts, the newest nearest its edge.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Notification placements")
struct NotificationPlacementTests {
    private static let width = 70
    private static let height = 20

    /// A service on a clock the test steps, a second past each post when drawn.
    private func service() -> (NotificationService, StepClock) {
        let clock = StepClock()
        return (NotificationService(nowNanos: { clock.nanos.withLock { $0 } }), clock)
    }

    /// The screen `service`'s toasts are drawn on, a second after their posts.
    private func screen(_ service: NotificationService, clock: StepClock, height: Int = Self.height) -> [String] {
        clock.nanos.withLock { $0 += 1_000_000_000 }
        var context = RenderContext(
            availableWidth: Self.width, availableHeight: height, tuiContext: TUIContext(),
            identity: ViewIdentity(path: "Root")
        ).isolatingRenderCache()
        context.environment.notificationService = service
        let buffer = renderToBuffer(Text("Base").notificationHost(), context: context)
        // Long past their ends, so the animation task the render started stops.
        defer { clock.nanos.withLock { $0 += 3_600_000_000_000 } }
        return buffer.compositingOverlays(
            maxWidth: Self.width, maxHeight: height, palette: context.environment.palette
        ).lines.map(\.stripped)
    }

    /// The row and column `text` starts at on `screen`.
    private func position(of text: String, in screen: [String]) -> (row: Int, column: Int)? {
        for (row, line) in screen.enumerated() {
            if let range = line.range(of: text) { return (row, line.distance(from: line.startIndex, to: range.lowerBound)) }
        }
        return nil
    }

    @Test(
        "Each placement starts its stack a cell in from its side and a row in from its edge",
        arguments: [
            (NotificationPlacement.topLeading, 1, 1), (.top, 15, 1), (.topTrailing, 29, 1),
            (.bottomLeading, 1, 14), (.bottom, 15, 14), (.bottomTrailing, 29, 14),
        ])
    func origin(placement: NotificationPlacement, x: Int, y: Int) {
        let origin = placement.origin(width: 40, height: 5, areaWidth: 70, areaHeight: 20)
        #expect(origin.x == x)
        #expect(origin.y == y)
    }

    @Test("Two placements draw two stacks at once, each at its own edge")
    func twoChannels() throws {
        let (service, clock) = service()
        service.post("Top left", placement: .topLeading)
        service.post("Bottom right", placement: .bottomTrailing)
        let lines = screen(service, clock: clock)
        let left = try #require(position(of: "Top left", in: lines))
        let right = try #require(position(of: "Bottom right", in: lines))
        #expect(left.row < Self.height / 2 && left.column < Self.width / 2)
        #expect(right.row > Self.height / 2 && right.column > left.column + 20)
    }

    @Test("The newest toast is nearest its placement's edge", arguments: [NotificationPlacement.top, .bottom])
    func newestNearestTheEdge(placement: NotificationPlacement) throws {
        let (service, clock) = service()
        service.post("Older", placement: placement)
        service.post("Newer", placement: placement)
        let lines = screen(service, clock: clock)
        let older = try #require(position(of: "Older", in: lines)).row
        let newer = try #require(position(of: "Newer", in: lines)).row
        #expect(placement.isTop ? newer < older : newer > older)
    }

    @Test("defaultPlacement places the posts that name none, from the post on")
    func defaultPlacement() throws {
        let (service, clock) = service()
        service.post("Before")
        service.defaultPlacement = .bottomLeading
        service.post("After")
        #expect(service.activeEntries().map(\.placement) == [.topTrailing, .bottomLeading])
        let lines = screen(service, clock: clock)
        #expect(try #require(position(of: "After", in: lines)).column < Self.width / 2)
    }

    @Test("dismissAll(at:) fades out one channel and leaves the rest")
    func dismissOneChannel() {
        let (service, clock) = service()
        service.post("Stays", placement: .top)
        service.post("Goes", placement: .bottom)
        service.dismissAll(at: .bottom)
        clock.nanos.withLock { $0 += 2_000_000_000 }
        #expect(service.activeEntries().map(\.message) == ["Stays"])
    }

    @Test("A stack taller than the area keeps the newest toasts that fit, and drops none it shows by half")
    func overflow() {
        let (service, clock) = service()
        for index in 1...8 { service.post("Toast \(index)", placement: .topTrailing) }
        let lines = screen(service, clock: clock, height: 12)
        let shown = (1...8).filter { index in lines.contains { $0.contains("Toast \(index)") } }
        #expect(shown.contains(8), "the newest is always shown")
        #expect(!shown.contains(1), "the oldest waits for room")
        #expect(shown == Array(shown.first!...8), "the newest run that fits: \(shown)")
    }

    @Test("width sets how wide a toast is, and never below 8")
    func width() {
        let service = NotificationService()
        service.width = 30
        #expect(service.width == 30)
        service.width = 2
        #expect(service.width == 8)
    }
}
