//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DialogModifierTests.swift
//
//  The modifiers written OUTSIDE an alert or confirmation dialog that change
//  how it is drawn: `dialogSeverity(_:)` and `dialogIcon(_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitPresentation
@testable import TUIkitTestSupport

@MainActor
@Suite("Dialog modifiers", .rendersEnglishUI)
struct DialogModifierTests {
    private struct Full: LocalizedError {
        var errorDescription: String? { "The disk is full" }
    }

    /// The composited screen, with its escape codes — colour is what severity
    /// changes, so the stripped text would hide it.
    private func screen(_ view: some View) -> [String] {
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
            .lines
    }

    private func alert(_ severity: DialogSeverity, title: String = "Erase?") -> some View {
        Text("base")
            .alert(title, isPresented: .constant(true)) {
                Button("Erase", role: .destructive) {}
            }
            .dialogSeverity(severity)
    }

    @Test("A critical dialog's title starts with the caution sign, and it takes the warning colour")
    func criticalIsMarkedAndColoured() throws {
        let critical = screen(alert(.critical))
        let marked = screen(alert(.standard, title: "\u{26A0}\u{FE0F} Erase?"))
        #expect(critical.map(\.stripped) == marked.map(\.stripped), "the sign before the title is all the text adds")
        #expect(critical != marked, "a critical dialog takes the warning colour")

        // The sign claims two cells, so the titled top border is as wide as
        // the walls below it.
        let box = critical.map(\.stripped).filter { $0.contains("│") || $0.contains("─") }
        let top = try #require(box.first { $0.contains("Erase?") })
        let wall = try #require(box.first { $0.hasPrefix("│") || $0.contains(" │") })
        #expect(top.strippedLength == wall.strippedLength, "\(box)")
    }

    @Test("The automatic severity is standard, except for an alert that presents an error")
    func automaticSeverity() {
        #expect(screen(alert(.automatic)) == screen(alert(.standard)))

        let errorAlert = { (severity: DialogSeverity) in
            self.screen(
                Text("base")
                    .alert(isPresented: .constant(true), error: Full()) {
                        Button("Erase", role: .destructive) {}
                    }
                    .dialogSeverity(severity))
        }
        #expect(errorAlert(.automatic) == errorAlert(.critical), "an error alert is critical by default")
        #expect(errorAlert(.automatic) != errorAlert(.standard))
    }

    @Test("An alert given colours of its own keeps them under a critical severity")
    func explicitColoursWin() {
        let coloured = { (severity: DialogSeverity, title: String) in
            self.screen(
                Text("base")
                    .alert(
                        title, isPresented: .constant(true),
                        actions: { Button("Erase") {} },
                        borderColor: .blue, titleColor: .green
                    )
                    .dialogSeverity(severity))
        }
        #expect(coloured(.critical, "Erase?") == coloured(.standard, "\u{26A0}\u{FE0F} Erase?"))
    }

    @Test("A dialog icon sits at the leading edge of the message")
    func iconBesideMessage() throws {
        let plain = screen(
            Text("base").confirmationDialog("Erase?", isPresented: .constant(true)) {
                Button("Erase") {}
            } message: {
                Text("Gone for good.")
            }
        ).map(\.stripped)
        let withIcon = screen(
            Text("base").confirmationDialog("Erase?", isPresented: .constant(true)) {
                Button("Erase") {}
            } message: {
                Text("Gone for good.")
            }
            .dialogIcon(Image(.file("/nonexistent/icon.png")))
        ).map(\.stripped)
        let column = { (lines: [String]) -> Int? in
            for line in lines {
                if let range = line.range(of: "Gone for good.") {
                    return line.distance(from: line.startIndex, to: range.lowerBound)
                }
            }
            return nil
        }
        let plainColumn = try #require(column(plain))
        let iconColumn = try #require(column(withIcon))
        #expect(
            plainColumn + _AlertMessage.rasterIconSize.width + 2 == iconColumn,
            "the message moves right by the icon's width and the gap")
        #expect(withIcon.count >= plain.count, "the icon's rows are at least the message's")
    }

    // MARK: - Suppression toggle

    /// The state an alert's page keeps, by reference so the bindings a frame
    /// built still reach it.
    private final class Flags {
        var presented = true
        var suppressed = false
        var erased = 0
    }

    private func suppressible(_ flags: Flags, label: String? = nil) -> some View {
        let presented = Binding(get: { flags.presented }, set: { flags.presented = $0 })
        let suppressed = Binding(get: { flags.suppressed }, set: { flags.suppressed = $0 })
        let alert = Text("base")
            .alert("Erase?", isPresented: presented) {
                Button("Erase") { flags.erased += 1 }
            }
        return Group {
            if let label {
                alert.dialogSuppressionToggle(label, isSuppressed: suppressed)
            } else {
                alert.dialogSuppressionToggle(isSuppressed: suppressed)
            }
        }
    }

    @Test("The suppression toggle draws above the buttons, with the default title")
    func suppressionDraws() throws {
        let lines = screen(suppressible(Flags())).map(\.stripped)
        let toggleRow = try #require(lines.firstIndex { $0.contains("Do not show this message again") })
        let buttonRow = try #require(lines.firstIndex { $0.contains("Erase") && !$0.contains("Erase?") })
        #expect(toggleRow < buttonRow)
        #expect(screen(suppressible(Flags(), label: "Never ask")).contains { $0.stripped.contains("Never ask") })
    }

    @Test("The alert's button keeps the opening focus; the toggle is a Tab away and writes the binding")
    func suppressionFocusAndBinding() {
        let harness = InputChainHarness(width: 60, height: 16)
        let flags = Flags()
        harness.frame(suppressible(flags))
        harness.frame(suppressible(flags))
        harness.press(KeyEvent(key: .tab))  // the button → the toggle
        harness.frame(suppressible(flags))
        harness.press(KeyEvent(key: .space))
        harness.frame(suppressible(flags))
        #expect(flags.suppressed, "Space on the checkbox turned suppression on")
        #expect(flags.presented, "toggling it did not answer the dialog")
        harness.press(KeyEvent(key: .tab))  // back round to the button
        harness.frame(suppressible(flags))
        harness.press(KeyEvent(key: .enter))
        harness.frame(suppressible(flags))
        #expect(flags.erased == 1 && !flags.presented, "the button answered and closed the alert")
    }

    @Test("With a suppression toggle, an alert's first button still takes Return at once")
    func buttonFocusedFirst() {
        let harness = InputChainHarness(width: 60, height: 16)
        let flags = Flags()
        harness.frame(suppressible(flags))
        harness.frame(suppressible(flags))
        harness.press(KeyEvent(key: .enter))
        harness.frame(suppressible(flags))
        #expect(flags.erased == 1, "the button, not the checkbox, held the opening focus")
        #expect(!flags.suppressed)
    }
}
