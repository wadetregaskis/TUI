//  🖥️ TUI — A Terminal UI framework for Swift
//  TextFieldBorderStyleTests.swift
//
//  SwiftUI's `.roundedBorder` and `.squareBorder` text field styles: the field
//  framed in box-drawing characters, rounded or square, which a terminal draws
//  as distinctly as it draws anything.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
import TUITextInput

@MainActor
@Suite("Bordered text field styles")
struct TextFieldBorderStyleTests {

    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 20, height: 5))
            .lines.map(\.stripped)
    }

    @Test("A rounded border frames the field in rounded corners")
    func rounded() {
        let drawn = lines(TextField("Name", text: .constant("Ada")).textFieldStyle(.roundedBorder))
        #expect(drawn.first?.hasPrefix("╭") == true && drawn.dropFirst(2).first?.hasPrefix("╰") == true,
                "\(drawn)")
        #expect(drawn.dropFirst().first?.contains("Ada") == true)
    }

    @Test("A square border frames the field in square corners")
    func square() {
        let drawn = lines(SecureField("Password", text: .constant("x")).textFieldStyle(.squareBorder))
        #expect(drawn.first?.hasPrefix("┌") == true && drawn.dropFirst(2).first?.hasPrefix("└") == true,
                "\(drawn)")
    }

    @Test("The default and plain styles draw no frame")
    func noFrame() {
        #expect(lines(TextField("Name", text: .constant("Ada"))).filter { !$0.isEmpty }.count == 1)
        #expect(lines(TextField("Name", text: .constant("Ada")).textFieldStyle(.plain))
            .filter { !$0.isEmpty }.count == 1)
    }

    @Test("A typed character lands inside the frame")
    func typingInsideTheFrame() throws {
        var value = ""
        let binding = Binding(get: { value }, set: { value = $0 })
        let context = makeRenderContext(width: 20, height: 5)
        _ = renderToBuffer(TextField("Name", text: binding).textFieldStyle(.roundedBorder), context: context)
        let focus = try #require(context.environment.focusManager)
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .character("a"))))
        #expect(value == "a")
    }
}
