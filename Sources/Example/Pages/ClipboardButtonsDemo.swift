//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipboardButtonsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The system buttons that do one thing to text: `PasteButton`, which reads
/// the clipboard as the type it is asked for, and `RenameButton`, which runs
/// whatever `.renameAction` the views above it set — here, focusing the field
/// that holds the name.
struct ClipboardButtonsDemo: View {
    @State private var pasted = ""
    @State private var name = "Untitled.txt"
    @FocusState private var nameFocused: Bool

    var body: some View {
        DemoSection("page.textInput.buttonsSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.textInput.buttonsExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 2) {
                    PasteButton(payloadType: String.self) { strings in
                        pasted = strings.joined(separator: " ")
                    }
                    Text(pasted.isEmpty ? L("page.textInput.pastedNothing") : pasted)
                        .foregroundStyle(pasted.isEmpty ? .palette.foregroundTertiary : .palette.accent)
                        .lineLimit(1)
                }
                HStack(spacing: 2) {
                    RenameButton()
                    TextField("page.textInput.fileName", text: $name)
                        .focused($nameFocused)
                        .frame(width: 24)
                }
                .renameAction($nameFocused)
            }
        }
    }
}
