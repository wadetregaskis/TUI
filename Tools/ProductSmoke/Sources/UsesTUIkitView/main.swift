//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitView re-exports TUIkitCore and TUIkitStyling, whose types its API names (its Exports.swift), so this one
// import gives a file `FrameBuffer` and `Color` too (ChoosingProducts).
import TUIkitView

// A primitive view, made as `View`'s documentation makes one: it draws a `FrameBuffer` (TUIkitCore's).
struct Primitive: View {
    var body: Never { fatalError("Primitive renders via Renderable") }
}

extension Primitive: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(text: "View")
    }
}

// And `Color` (TUIkitStyling's) as a view, a conformance TUIkitView declares.
let colour: some View = Color.red

print("UsesTUIkitView: \(String(reflecting: Primitive.self)), \(String(reflecting: type(of: colour)))")
