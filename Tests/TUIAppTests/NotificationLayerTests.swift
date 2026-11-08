//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationLayerTests.swift
//
//  Toasts and what is presented over the window: one above presentations is
//  drawn over a sheet and reachable with F6 while it is up; one below them is
//  drawn beneath it, out of reach, its timer stopped until the sheet closes;
//  and which a post gets by default follows whose it is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUIPresentation
@testable import TUITestSupport

/// A clock the tests step by hand, for the service and the frames alike.
private final class LayerClock: Sendable {
    let nanos = Mutex<UInt64>(5_000_000_000)
    var now: UInt64 { nanos.withLock { $0 } }
    func advance(seconds: Double) { nanos.withLock { $0 += UInt64(seconds * 1_000_000_000) } }
}

/// Whether the sheet is up, which its binding reads and Escape writes.
@MainActor
private final class SheetFlag {
    var isPresented = true
    var binding: Binding<Bool> { Binding(get: { self.isPresented }, set: { self.isPresented = $0 }) }
}

/// Where the sheet's content puts the service its environment hands it.
@MainActor
private final class Captured {
    var service: NotificationService?
}

/// A view inside the sheet that keeps the service its environment hands it.
private struct Capturing: View {
    let captured: Captured
    @Environment(\.notificationService) private var notifications

    var body: some View {
        captured.service = notifications
        return Button("Sheet") {}.focusID("sheet")
    }
}

@MainActor
@Suite("Notifications and presentations")
struct NotificationLayerTests {
    private let clock = LayerClock()

    /// A service on the test's clock.
    private func service() -> NotificationService {
        let clock = clock
        return NotificationService(nowNanos: { clock.now })
    }

    /// A window with a button, presenting a sheet with a button while `flag` says.
    private func page(_ flag: SheetFlag, captured: Captured = Captured()) -> some View {
        _WindowChromeHost(
            content: Button("Page") {}.focusID("page")
                .sheet(isPresented: flag.binding) { Capturing(captured: captured) })
    }

    /// A harness whose views get `service`.
    private func harness(_ service: NotificationService) -> InputChainHarness {
        InputChainHarness(width: 70, height: 20) { $0.notificationService = service }
    }

    /// A frame at the clock's instant.
    @discardableResult
    private func frame(_ harness: InputChainHarness, _ flag: SheetFlag, captured: Captured = Captured()) -> FrameBuffer {
        harness.now = Int64(clock.now)
        return harness.frame(page(flag, captured: captured))
    }

    private func entry(_ id: NotificationID, in service: NotificationService) -> NotificationEntry? {
        service.activeEntries().first { $0.id == id }
    }

    @Test("A post belonging to no window goes above presentations; one through a window's service, below")
    func defaultLayerFollowsTheOwner() throws {
        let service = service()
        let unowned = service.post("Saved")
        let windows = service.owned(byWindow: 1).post("Saved")
        let sheets = service.owned(byWindow: 1).owned(byPresentation: "sheet").post("Saved")
        let explicit = service.owned(byWindow: 1).post("Saved", layer: .abovePresentations)
        #expect(try #require(entry(unowned, in: service)).layer == .abovePresentations)
        #expect(try #require(entry(windows, in: service)).layer == .belowPresentations)
        let sheet = try #require(entry(sheets, in: service))
        #expect(sheet.layer == .belowPresentations)
        #expect(sheet.owner == NotificationOwner(window: 1, presentation: "sheet"))
        #expect(try #require(entry(explicit, in: service)).layer == .abovePresentations)
        service.clear()
    }

    @Test("Over a sheet, F6 reaches a toast's button; Escape dismisses the toast, then the sheet")
    func aboveIsReachableOverASheet() throws {
        let service = service()
        defer { service.clear() }
        let flag = SheetFlag()
        let id = service.post("Saved", duration: 30, actions: [NotificationAction("Open") {}])
        let harness = harness(service)
        frame(harness, flag)
        frame(harness, flag)
        #expect(harness.focusManager.currentFocusedID == "sheet")
        harness.press(KeyEvent(key: .f6))
        frame(harness, flag)
        #expect(harness.focusManager.currentFocusedID == NotificationKeyboard.focusID(id, button: 0))
        #expect(harness.focusManager.activeSectionIsModal, "the bars stay inert while the toast has the focus")
        // Escape with the toast focused is the toast's: the sheet stays.
        harness.press(KeyEvent(key: .escape))
        frame(harness, flag)
        #expect(try #require(entry(id, in: service)).isDismissed)
        #expect(flag.isPresented)
        #expect(harness.focusManager.currentFocusedID == "sheet")
        // Without the toast focused, Escape closes the sheet as before.
        harness.press(KeyEvent(key: .escape))
        frame(harness, flag)
        #expect(!flag.isPresented)
    }

    @Test("Escape over a sheet closes the sheet while the toast over it does not have the focus")
    func escapeIsTheSheetsFirst() throws {
        let service = service()
        defer { service.clear() }
        let flag = SheetFlag()
        let id = service.post("Saved", duration: 30, actions: [NotificationAction("Open") {}])
        let harness = harness(service)
        frame(harness, flag)
        frame(harness, flag)
        harness.press(KeyEvent(key: .escape))
        frame(harness, flag)
        #expect(!flag.isPresented)
        #expect(try #require(entry(id, in: service)).isDismissed == false)
    }

    @Test("Under a sheet a toast is out of reach, and its timer waits until the sheet closes")
    func belowIsCoveredAndWaits() throws {
        let service = service()
        defer { service.clear() }
        let window = service.owned(byWindow: 1)
        let flag = SheetFlag()
        let id = window.post("Saved", duration: 3, actions: [NotificationAction("Open") {}])
        let harness = harness(window)
        clock.advance(seconds: 1)
        frame(harness, flag)
        frame(harness, flag)
        #expect(try #require(entry(id, in: service)).isCovered)
        harness.press(KeyEvent(key: .f6))
        frame(harness, flag)
        #expect(harness.focusManager.currentFocusedID == "sheet", "F6 does not reach a covered toast")
        // Twenty seconds under the sheet: long past its three, and still there, a second old.
        clock.advance(seconds: 20)
        frame(harness, flag)
        let waiting = try #require(entry(id, in: service))
        #expect(abs(waiting.age(atNanos: clock.now) - 1) < 0.01)
        // The sheet closes: the clock runs again from where it stopped.
        flag.isPresented = false
        frame(harness, flag)
        #expect(try #require(entry(id, in: service)).isCovered == false)
        clock.advance(seconds: 2)
        frame(harness, flag)
        #expect(entry(id, in: service) != nil, "three seconds visible, and only two more have passed")
        clock.advance(seconds: 2)
        frame(harness, flag)
        #expect(entry(id, in: service) == nil, "gone once its own three and a half seconds have run")
    }

    @Test("A toast posted from inside a sheet is on top of that sheet, and reachable")
    func postedFromTheSheetIsOverIt() throws {
        let service = service()
        defer { service.clear() }
        let window = service.owned(byWindow: 1)
        let flag = SheetFlag()
        let captured = Captured()
        let harness = harness(window)
        frame(harness, flag, captured: captured)
        frame(harness, flag, captured: captured)
        let sheets = try #require(captured.service)
        #expect(sheets.owner?.presentation != nil)
        #expect(sheets.owner?.window == 1)
        let id = sheets.post("Exported", duration: 30, actions: [NotificationAction("Show") {}])
        frame(harness, flag, captured: captured)
        #expect(try #require(entry(id, in: service)).isCovered == false)
        harness.press(KeyEvent(key: .f6))
        frame(harness, flag, captured: captured)
        #expect(harness.focusManager.currentFocusedID == NotificationKeyboard.focusID(id, button: 0))
    }

    @Test("A toast posted for another window waits, undrawn, while that window is behind")
    func anotherWindowsToastWaits() throws {
        let service = service()
        defer { service.clear() }
        let id = service.owned(byWindow: 2).post("Done", duration: 3)
        let harness = harness(service.owned(byWindow: 1))
        let flag = SheetFlag()
        flag.isPresented = false
        clock.advance(seconds: 1)
        let screen = frame(harness, flag)
        #expect(!screen.lines.contains { $0.stripped.contains("Done") })
        #expect(try #require(entry(id, in: service)).isCovered)
    }

    @Test("A covered toast's layer is beneath every presented surface; an uncovered one's on top")
    func levels() throws {
        let service = service()
        defer { service.clear() }
        service.post("Over", duration: 30)
        service.owned(byWindow: 1).post("Under", duration: 30, placement: .bottom)
        let focusManager = FocusManager()
        var context = RenderContext(
            availableWidth: 60, availableHeight: 16, tuiContext: TUIContext(), identity: ViewIdentity(path: "Root")
        ).isolatingRenderCache()
        context.environment.focusManager = focusManager
        context.environment.notificationService = service.owned(byWindow: 1)
        focusManager.registerSection(id: "sheet")
        focusManager.activateSection(id: "sheet")
        focusManager.markSectionModal(id: "sheet")
        let layers = NotificationOverlay.layers(context: context, areaWidth: 60, areaHeight: 16)
        let levels = layers.map { layer in
            (layer.content.lines.contains { $0.stripped.contains("Over") }, layer.level, layer.zIndex)
        }
        #expect(levels.contains { $0.0 && $0.1 == .notification })
        #expect(levels.contains { !$0.0 && $0.1 == .popover && $0.2 == NotificationOverlay.coveredZIndex })
    }

    @Test("A covered entry's clock stops, runs on from there, and a dismissal starts it again")
    func entryClock() {
        let entry = NotificationEntry(message: "m", duration: 3, postedAtNanos: 1_000_000_000)
        let covered = entry.covered(atNanos: 2_000_000_000)
        #expect(covered.age(atNanos: 9_000_000_000) == 1)
        #expect(covered.expiresAtNanos == .max)
        let uncovered = covered.uncovered(atNanos: 9_000_000_000)
        #expect(uncovered.age(atNanos: 10_000_000_000) == 2)
        #expect(uncovered.expiresAtNanos == entry.expiresAtNanos + 7_000_000_000)
        let dismissed = covered.dismissed(atNanos: 9_000_000_000)
        #expect(!dismissed.isCovered)
        #expect(dismissed.covered(atNanos: 9_500_000_000).isCovered == false, "a dismissed toast is never covered")
    }
}
