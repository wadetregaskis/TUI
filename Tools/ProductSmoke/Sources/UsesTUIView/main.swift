//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIView re-exports TUICore and TUIStyling, whose types its API names (its Exports.swift), so this one
// import gives a file `FrameBuffer` and `Color` too (ChoosingProducts).
import TUIView

// A primitive view, made as `View`'s documentation makes one: it draws a `FrameBuffer` (TUICore's).
struct Primitive: View {
    var body: Never { fatalError("Primitive renders via Renderable") }
}

extension Primitive: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(text: "View")
    }
}

// And `Color` (TUIStyling's) as a view, a conformance TUIView declares.
let colour: some View = Color.red

print("UsesTUIView: \(String(reflecting: Primitive.self)), \(String(reflecting: type(of: colour)))")
