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

@testable import TUIkit

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

    private func alert(_ severity: DialogSeverity) -> some View {
        Text("base")
            .alert("Erase?", isPresented: .constant(true)) {
                Button("Erase", role: .destructive) {}
            }
            .dialogSeverity(severity)
    }

    @Test("A critical dialog is drawn differently from a standard one, in the same words")
    func criticalIsColoured() {
        let critical = screen(alert(.critical))
        let standard = screen(alert(.standard))
        #expect(critical.map(\.stripped) == standard.map(\.stripped), "severity changes no text")
        #expect(critical != standard, "a critical dialog takes the warning colour")
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
        let coloured = { (severity: DialogSeverity) in
            self.screen(
                Text("base")
                    .alert(
                        "Erase?", isPresented: .constant(true),
                        actions: { Button("Erase") {} },
                        borderColor: .blue, titleColor: .green
                    )
                    .dialogSeverity(severity))
        }
        #expect(coloured(.critical) == coloured(.standard))
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
}
