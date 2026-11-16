//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPositionIDHoldTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// What a `.scrollPosition(id:)` binding reads after the APP writes it.
///
/// SwiftUI seeks the row by the least move (with no anchor, a row below the
/// viewport lands at the bottom) and the binding keeps the id the app wrote:
/// it reads the row at the top again only once the user scrolls. Measured,
/// `Tools/SwiftUIProbes/Bug-hunt parity items (1116B)/scrollid.swift`. TUI
/// used to write the top row straight back, so the app's id was lost and
/// writing it again did nothing.
@MainActor
@Suite("scrollPosition(id:) keeps the id the app wrote")
struct ScrollPositionIDHoldTests {
    private static let viewport = 6

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
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

    @Test("The app's id survives the seek, and writing it again after the user scrolls seeks again")
    func appWrittenIDIsKept() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollPosition(id: binding)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        // The least move: row 18 at the bottom. The binding still reads 18.
        visible = 18
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let landed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(landed.last?.hasPrefix("row 18") == true, "\(landed)")
        #expect(visible == 18, "the app's id was replaced by the top row: \(String(describing: visible))")

        // The user scrolls to the top: now the binding reads the top row.
        let handler = focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        handler?.userScrollToTop()
        let top = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(top.first?.hasPrefix("row 0") == true, "\(top)")
        #expect(visible == 0, "\(String(describing: visible))")

        // Writing 18 again seeks again.
        visible = 18
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let again = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(again.contains { $0.hasPrefix("row 18") }, "\(again)")
        #expect(visible == 18, "\(String(describing: visible))")
    }

    @Test("From below, the least move puts the row at the top")
    func fromBelowLandsAtTop() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollPosition(id: binding)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let handler = focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        handler?.userScrollToBottom()
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        visible = 18
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let landed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(landed.first?.hasPrefix("row 18") == true, "\(landed)")
        #expect(visible == 18, "\(String(describing: visible))")
    }

    /// SwiftUI leaves a `nil` id `nil` as the view appears: the binding is
    /// written when the app's seek lands or the user scrolls, not before
    /// (step 1 of the probe). TUI reports the top row at once.
    @Test("An id that starts nil stays nil until the user scrolls")
    func nilStaysNilAtAppear() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollPosition(id: binding)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        withKnownIssue("TUI writes the top row's id as the view appears; SwiftUI writes nothing") {
            #expect(visible == nil, "\(String(describing: visible))")
        }
    }
}
