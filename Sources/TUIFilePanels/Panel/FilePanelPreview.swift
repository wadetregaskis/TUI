//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelPreview.swift
//
//  The column view's preview column: the file selected in the last column,
//  as Finder's column view previews it beside the folder it is in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// The file selected in a column view's last column, previewed in a column of
/// its own after it, as Finder's is: the app's preview of it
/// (`fileDialogPreview(_:)`), else the opening lines of a text file, and
/// beneath, its name, kind, size and date.
struct FilePanelPreview: View {
    let entry: FileEntry

    /// The app's previews, where it supplies them.
    @Environment(\.fileDialogPreview) private var appPreviews

    /// The opening lines of a text file, once read; `nil` for anything else.
    @State private var excerpt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let preview = appPreviews?.view(for: entry) {
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let excerpt {
                Text(verbatim: excerpt)
                    .foregroundStyle(.palette.foregroundSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: entry.name).bold().lineLimit(2)
                Text(verbatim: entry.kind).foregroundStyle(.palette.foregroundSecondary)
                if entry.size != nil { Text(verbatim: entry.sizeText).foregroundStyle(.palette.foregroundSecondary) }
                if entry.modified != nil {
                    Text(verbatim: entry.modifiedText).foregroundStyle(.palette.foregroundSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: entry.url) {
            // The last file's excerpt is not this one's: gone while this one
            // is read. And a read the selection has moved on from is dropped,
            // or a slow one of the last file showed its text under this one.
            excerpt = nil
            let read = await Self.excerpt(of: entry)
            guard !Task.isCancelled else { return }
            excerpt = read
        }
    }

    /// The most of a file read for its excerpt, in bytes.
    nonisolated static let excerptBytes = 2_048

    /// The most lines an excerpt keeps.
    nonisolated static let excerptLines = 12

    /// The opening lines of `entry` if it is a text file, read off the main
    /// actor; `nil` for anything else, or a file that cannot be read.
    ///
    /// Only a regular file (or a link to one) is opened: on Linux a type is
    /// its extension's, so a named pipe called `x.log` is "text", and opening
    /// it waits for a writer — holding a thread of the cooperative pool for
    /// good.
    @concurrent
    static func excerpt(of entry: FileEntry) async -> String? {
        let file = entry.url.resolvingSymlinksInPath()
        guard entry.contentType.conforms(to: .text),
            (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
            let handle = try? FileHandle(forReadingFrom: file)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: excerptBytes) else { return nil }
        // Lossy, so a read that ends inside a character keeps the lines
        // before it, where the failable initialiser the rule prefers drops
        // them all; tabs as a terminal would draw them in a narrow column.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\t", with: "  ")
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(excerptLines).joined(separator: "\n")
    }
}
