//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelNameField.swift
//
//  A save panel's name field, and the rule that turns what is typed in it
//  into the name a file is saved under.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation
import TUIkitTextInput

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// The row a save panel names its file in: the label (Save As:, or the
/// `fileExporterFilenameLabel(_:)`) and the field.
struct FilePanelNameField: View {
    let label: String
    let name: Binding<String>

    var body: some View {
        HStack(spacing: 1) {
            Text(label).foregroundStyle(.palette.foregroundSecondary)
            TextField(label, text: name)
        }
    }
}

/// The name a save panel saves under, from what was typed.
enum SaveName {
    /// `typed` as a file's name: trimmed, and given the first content type's
    /// extension when it has none of the types' own (as a macOS save panel
    /// adds the extension of the type it saves) — `notes` saved as plain text
    /// is `notes.txt`, `notes.md` stays as it is, since Markdown is plain text.
    /// `nil` for a name no file can have: empty, `.` or `..`, or one with a `/`.
    static func resolve(_ typed: String, contentTypes: [UTType]) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
        guard let preferred = contentTypes.first?.preferredFilenameExtension else { return name }
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, let typedType = UTType(filenameExtension: ext),
            contentTypes.contains(where: { typedType.conforms(to: $0) })
        {
            return name
        }
        return name + "." + preferred
    }

    /// The content type to save as, of `types`: the one the name's extension
    /// names or conforms to, else the first; `nil` when there are none.
    static func type(for name: String, among types: [UTType]) -> UTType? {
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, let named = UTType(filenameExtension: ext),
            let match = types.first(where: { named.conforms(to: $0) })
        {
            return match
        }
        return types.first
    }
}
