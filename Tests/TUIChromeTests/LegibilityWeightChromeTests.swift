//  🖥️ TUI — A Terminal UI framework for Swift
//  LegibilityWeightChromeTests.swift
//
//  Under `\.legibilityWeight == .bold` the text the app's chrome draws itself —
//  a notification's message, a tooltip's help — is a tier heavier too, as all
//  of SwiftUI's text is (decisions B2). Its frame is not text, and is not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Legibility weight in the app's chrome", .serialized)
struct LegibilityWeightChromeTests {
    private func context(under weight: LegibilityWeight?) -> RenderContext {
        var context = RenderContext(
            availableWidth: 40, availableHeight: 24, tuiContext: TUIContext(),
            identity: ViewIdentity(path: "Root")
        ).isolatingRenderCache()
        context.environment.legibilityWeight = weight
        return context
    }

    @Test("A notification's message is drawn bold under .bold, and plain without it")
    func notification() {
        for weight: LegibilityWeight? in [nil, .bold] {
            var context = context(under: weight)
            let service = NotificationService()
            service.post("Alert!")
            context.environment.notificationService = service
            let buffer = renderToBuffer(NotificationHostModifier(content: Text("Base"), width: 40), context: context)
            let screen = buffer.compositingOverlays(maxWidth: 40, maxHeight: 24, palette: context.environment.palette)
            #expect(sgrState(of: "Alert!", in: screen.lines)?.isBold == (weight == .bold), "\(String(describing: weight))")
        }
    }

    @Test("A tooltip's help is drawn bold under .bold, and its frame is not")
    func tooltip() {
        for weight: LegibilityWeight? in [nil, .bold] {
            let panel = TooltipPopover.panel(text: "Saves the file", maxWidth: 40, context: context(under: weight))
            #expect(sgrState(of: "Saves", in: panel.lines)?.isBold == (weight == .bold), "\(String(describing: weight))")
            #expect(panel.lines.first.map { !$0.contains("\u{1B}[1;") && !$0.contains("\u{1B}[1m") } == true, "the frame")
        }
    }
}
