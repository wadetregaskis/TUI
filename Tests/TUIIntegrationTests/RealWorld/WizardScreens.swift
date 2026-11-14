//  🖥️ TUI — A Terminal UI framework for Swift
//  WizardScreens.swift
//
//  Real-world screens: wizards built on NavigationStack. A setup wizard
//  whose Next button pushes the following step, and a list of links that
//  push a detail page. Each pushed page must have the focus, every step must
//  be drawn whole, and going back must land on the page that pushed it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

/// Step `number` of four: a field, and a Next button that pushes the next.
private struct WizardStep: View {
    let number: Int
    @Binding var path: [Int]
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Step \(number) of 4").bold()
            TextField("Answer \(number)", text: $answer).focusID("answer-\(number)")
            HStack {
                Button(number == 4 ? "Finish" : "Next") {
                    if number < 4 { path.append(number + 1) } else { path.removeAll() }
                }
                .focusID("next-\(number)")
            }
        }
        .navigationTitle("Setup")
    }
}

private struct WizardPage: View {
    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            WizardStep(number: 1, path: $path)
                .navigationDestination(for: Int.self) { WizardStep(number: $0, path: $path) }
        }
    }
}

/// A list of 15 links, each pushing a page about its topic.
private struct TopicsPage: View {
    var body: some View {
        NavigationStack {
            List(1...15, id: \.self) { topic in
                NavigationLink("Topic \(topic)", value: topic)
            }
            .focusID("topics")
            .navigationTitle("Help")
            .navigationDestination(for: Int.self) { topic in
                VStack(alignment: .leading) {
                    Text("About topic \(topic)")
                    Button("Thanks") {}.focusID("thanks")
                }
                .navigationTitle("Topic \(topic)")
            }
        }
    }
}

@MainActor
@Suite("Real world: wizards on NavigationStack")
struct WizardScreens {
    @Test("Next through four steps: each one drawn whole and reachable by Tab, Finish back to the first",
          arguments: TerminalSize.all)
    func setupWizard(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { WizardPage() }
        LayoutSanity.check(app, "launch")
        for step in 1...4 {
            for _ in 0..<6 where app.focusedID != "next-\(step)" { app.press(.tab) }
            #expect(app.focusedID == "next-\(step)", "step \(step)'s button never took the focus:\n\(app.screen)")
            LayoutSanity.check(app, "step \(step)")
            if size.height >= 12 {
                #expect(app.screen.contains("Step \(step) of 4"), "step \(step) is not shown:\n\(app.screen)")
            }
            app.press(.enter)
            app.advance(by: .seconds(1))
            LayoutSanity.check(app, "after step \(step)")
        }
        if size.height >= 12 {
            #expect(app.screen.contains("Step 1 of 4"), "Finish did not go back to the first:\n\(app.screen)")
        }
    }

    @Test("A list of links: pushing the 12th topic and going back keeps it chosen", arguments: TerminalSize.all)
    func topics(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { TopicsPage() }
        LayoutSanity.check(app, "launch")
        for _ in 0..<4 where app.focusedID != "topics" { app.press(.tab) }
        #expect(app.focusedID == "topics")
        for step in 1...11 {
            app.press(.down)
            LayoutSanity.check(app, "Down ×\(step)")
        }
        #expect(app.screen.contains("Topic 12"), "the 12th topic is not in sight:\n\(app.screen)")
        app.press(.enter)
        app.advance(by: .seconds(1))
        LayoutSanity.check(app, "pushed")
        #expect(app.screen.contains("About topic 12"), "topic 12 was not pushed:\n\(app.screen)")
        app.press(.escape)
        app.advance(by: .seconds(1))
        LayoutSanity.check(app, "back")
        #expect(app.focusedID == "topics", "the focus did not go back to the list: \(app.focusedID ?? "none")")
    }
}
