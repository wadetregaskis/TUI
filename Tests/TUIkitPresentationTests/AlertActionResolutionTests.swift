//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlertActionResolutionTests.swift
//
//  A dialog finds its buttons wherever the actions builder wrote them
//  (deviations sweep, likely bug 14; semantic audit 38). SwiftUI keeps "a
//  Button … wherever in the builder it was written"; TUIkit's walk knew three
//  view types, so a modified button, an `if`/`else`, a `Group` or a `ForEach`
//  drew no button at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
import TUIkitPresentation
@testable import TUIkitTestSupport

@MainActor
@Suite("A dialog finds its buttons wherever they are written")
struct AlertActionResolutionTests {
    private func render(_ view: some View) -> String {
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
            .lines.joined(separator: "\n").stripped
    }

    /// Buttons of the app's own, in a view of its own.
    private struct Choices: View {
        var body: some View {
            Button("Mine") {}
            Button("Yours") {}
        }
    }

    @Test("A modified button, an if/else, a Group and a ForEach are all buttons")
    func everyShape() {
        let modified = render(
            Text("base").alert("Warning", isPresented: .constant(true)) {
                Button("Defaulted") {}.keyboardShortcut(.defaultAction)
                Button("Cancelled", role: .cancel) {}
            })
        #expect(modified.contains("Defaulted") && modified.contains("Cancelled"), "\(modified)")
        let flag = true
        let branched = render(
            Text("base").alert("Warning", isPresented: .constant(true)) {
                if flag { Button("Yes") {} } else { Button("No") {} }
            })
        #expect(branched.contains("Yes") && !branched.contains("No"), "\(branched)")
        let grouped = render(
            Text("base").alert("Warning", isPresented: .constant(true)) {
                Group { Button("Grouped") {} }
            })
        #expect(grouped.contains("Grouped"), "\(grouped)")
        let looped = render(
            Text("base").confirmationDialog("Pick", isPresented: .constant(true)) {
                ForEach(["Aaa", "Bbb"], id: \.self) { Button($0) {} }
            })
        #expect(looped.contains("Aaa") && looped.contains("Bbb"), "\(looped)")
        let own = render(Text("base").alert("Warning", isPresented: .constant(true)) { Choices() })
        #expect(own.contains("Mine") && own.contains("Yours"), "\(own)")
    }

    @Test("An action that is not a button is left out, and found buttons keep their order")
    func nonButtonsLeftOut() {
        let quiet = DroppedMemberReports()
        let mixed = DroppedMember.$reporter.withValue(quiet.record) {
            render(
                Text("base").alert("Warning", isPresented: .constant(true)) {
                    Button("First") {}
                    Text("not a button")
                    Button("Second") {}
                })
        }
        #expect(!mixed.contains("not a button"), "\(mixed)")
        #expect(quiet.messages.isEmpty, "a Text is left out quietly, as SwiftUI leaves it out: \(quiet.messages)")
        let first = mixed.range(of: "First")
        let second = mixed.range(of: "Second")
        #expect(first != nil && second != nil && first!.lowerBound < second!.lowerBound, "\(mixed)")
    }

    @Test("A toggle among the actions, which SwiftUI's alert shows, is reported as left out")
    func toggleReported() {
        let reports = DroppedMemberReports()
        let drawn = DroppedMember.$reporter.withValue(reports.record) {
            render(
                Text("base").alert("Warning", isPresented: .constant(true)) {
                    Toggle("Remember", isOn: .constant(true))
                    Button("OK") {}
                })
        }
        #expect(drawn.contains("OK") && !drawn.contains("Remember"), "\(drawn)")
        #expect(
            !reports.messages.isEmpty && reports.messages.allSatisfy { $0.contains("leaves out a Toggle") },
            "\(reports.messages)")
    }
}
