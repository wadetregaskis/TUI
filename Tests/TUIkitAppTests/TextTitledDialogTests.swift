//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextTitledDialogTests.swift
//
//  An alert or confirmation dialog titled with a `Text`, as SwiftUI's can be
//  (the semantic audit's item 121): `.alert(Text("Delete?"), isPresented:)`
//  compiles and draws its title.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Dialogs titled with a Text")
struct TextTitledDialogTests {
    private func render(_ view: some View) -> String {
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
            .lines.joined(separator: "\n").stripped
    }

    @Test("An alert takes a Text title, with or without a message, presented or with data")
    func alerts() {
        let plain = render(Text("base").alert(Text("Delete the draft?"), isPresented: .constant(true)) { Button("Delete") {} })
        #expect(plain.contains("Delete the draft?") && plain.contains("Delete"), "\(plain)")
        let messaged = render(
            Text("base").alert(Text("Saved"), isPresented: .constant(true)) {} message: { Text("All done.") })
        #expect(messaged.contains("Saved") && messaged.contains("All done."), "\(messaged)")
        let presenting = render(
            Text("base").alert(Text("Rename"), isPresented: .constant(true), presenting: "notes.txt") { name in
                Button("Rename \(name)") {}
            })
        #expect(presenting.contains("Rename") && presenting.contains("notes.txt"), "\(presenting)")
    }

    @Test("A confirmation dialog takes a Text title, shown when asked")
    func confirmationDialogs() {
        let dialog = render(
            Text("base").confirmationDialog(Text("Empty the trash?"), isPresented: .constant(true), titleVisibility: .visible) {
                Button("Empty Trash", role: .destructive) {}
            })
        #expect(dialog.contains("Empty the trash?") && dialog.contains("Empty Trash"), "\(dialog)")
        let presenting = render(
            Text("base").confirmationDialog(
                Text("Remove"), isPresented: .constant(true), titleVisibility: .visible, presenting: 3
            ) { count in
                Button("Remove \(count) items", role: .destructive) {}
            })
        #expect(presenting.contains("Remove") && presenting.contains("3 items"), "\(presenting)")
    }
}
