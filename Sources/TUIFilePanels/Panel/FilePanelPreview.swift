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
    @State private var excerpt: Excerpt?

    /// The locale the panel writes its sizes in.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let preview = appPreviews?.view(for: entry) {
                preview
                    .id(entry.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let excerpt {
                ScrollView {
                    Text(verbatim: excerpt.shown(locale: locale))
                        .foregroundStyle(.palette.foregroundSecondary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// The most of a file read for its preview, in bytes (64 KiB).
    nonisolated static let previewByteCap = 64 * 1024

    /// The most lines a preview keeps before truncating.
    nonisolated static let previewLineCap = 250

    /// A text file's opening lines, as read for its preview.
    struct Excerpt: Equatable, Sendable {
        /// The lines shown, joined by newlines, tabs as two spaces.
        var text: String

        /// Whether the file goes on past them.
        var isTruncated = false

        /// How many bytes it goes on for, where the file's size says: `nil`
        /// where it doesn't, as a Linux `/proc` file's size of 0 doesn't.
        var omittedBytes: Int64?

        /// The text, and after it where the file goes on, an ellipsis, and
        /// "(plus 12 KB more)" in the language and `locale` it is drawn in:
        /// built as it is drawn, so a change of either shows at once.
        func shown(locale: Locale) -> String {
            guard isTruncated else { return text }
            var shown = text + "\n…"
            if let omittedBytes, omittedBytes > 0 {
                let size = ByteCountFormatStyle(style: .file, locale: locale).format(omittedBytes)
                let format = LocalizationService.shared.string(for: LocalizationKey.FilePanel.previewMore)
                shown += "\n" + String(format: format, size)
            }
            return shown
        }
    }

    /// Whether `type` is a declared text type or an untyped/dynamic file whose
    /// opening bytes may be UTF-8 text (`Package.resolved`, `.gitattributes`,
    /// `.swift-format`, logs, scripts without extensions). Known non-text
    /// formats (`.pdf`, images, archives, bundles) are excluded without
    /// reading the file.
    nonisolated static func mayContainText(_ type: UTType) -> Bool {
        if type.conforms(to: .text) || type.isDynamic { return true }
        return type == .data || type == .item || type == .content
            || type == .log || type == .unixExecutable || type == .propertyList
    }

    /// Whether `data` contains ASCII control characters that indicate binary data
    /// (excluding standard text whitespace: tab, LF, FF, CR).
    nonisolated static func containsBinaryControlBytes(_ data: Data) -> Bool {
        data.contains { ($0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0C && $0 != 0x0D) || $0 == 0x7F }
    }

    /// `data` decoded as UTF-8, up to three trailing bytes of a scalar split
    /// by the cap trimmed when `truncated`; `nil` where it is not UTF-8.
    nonisolated static func utf8Text(from data: Data, truncated: Bool) -> String? {
        guard !data.isEmpty else { return nil }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if truncated {
            guard data.count > 1 else { return nil }
            for trim in 1...min(3, data.count - 1) {
                if let text = String(data: data.dropLast(trim), encoding: .utf8) {
                    return text
                }
            }
        }
        return nil
    }

    /// `data` as the preview's text, or `nil` for what is not text.
    ///
    /// A file of a declared text type is refused only for a NUL, which no
    /// text holds: a log's colour escapes, a DOS file's closing ⌃Z or saved
    /// `man` output's backspaces are text, and the renderer draws such bytes
    /// safely. One in another encoding is shown, its stray bytes as U+FFFD.
    /// An untyped file has to look like text: UTF-8 with no control bytes
    /// past tab, line breaks and form feed.
    nonisolated static func previewText(of data: Data, declaredText: Bool, truncated: Bool) -> String? {
        if declaredText {
            guard !data.contains(0) else { return nil }
        } else {
            guard !containsBinaryControlBytes(data) else { return nil }
        }
        if let text = utf8Text(from: data, truncated: truncated) { return text }
        guard declaredText else { return nil }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }

    /// The byte offset just past `data`'s `count`th line ending (a CR LF one
    /// ending, as it is one line break), or `nil` where it has fewer. Counted
    /// in the bytes, not in the text: tabs drawn as two spaces and stray bytes
    /// drawn as U+FFFD take more bytes there than they did in the file.
    nonisolated static func offset(afterLines count: Int, in data: Data) -> Int? {
        var seen = 0
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            index = data.index(after: index)
            guard byte == 0x0A || byte == 0x0D else { continue }
            if byte == 0x0D, index < data.endIndex, data[index] == 0x0A { index = data.index(after: index) }
            seen += 1
            if seen == count { return data.distance(from: data.startIndex, to: index) }
        }
        return nil
    }

    /// The preview of `entry` if it is a text file, read off the main actor;
    /// `nil` for anything else, or a file that cannot be read.
    ///
    /// Only a regular file (or a link to one) is opened: on Linux a type is
    /// its extension's, so a named pipe called `x.log` is "text", and opening
    /// it waits for a writer — holding a thread of the cooperative pool for
    /// good.
    ///
    /// It reads one byte past ``previewByteCap``, which says whether the file
    /// goes on whatever its size claims: a `/proc` file's is 0, and a file can
    /// grow between its size being read and the read.
    @concurrent
    static func excerpt(of entry: FileEntry) async -> Excerpt? {
        let file = entry.url.resolvingSymlinksInPath()
        guard mayContainText(entry.contentType),
            (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
            let handle = try? FileHandle(forReadingFrom: file)
        else { return nil }
        defer { try? handle.close() }
        guard let read = try? handle.read(upToCount: previewByteCap + 1), !read.isEmpty else { return nil }
        let cutByBytes = read.count > previewByteCap
        let data = read.prefix(previewByteCap)
        // The lines past the cap go, where there are any past it.
        var shown = data
        var isTruncated = cutByBytes
        if let end = offset(afterLines: previewLineCap, in: data), end < data.count || cutByBytes {
            shown = data.prefix(end)
            isTruncated = true
        }
        // Only a cut by bytes can split a scalar: a cut by lines falls after a line break.
        let splitsScalar = cutByBytes && shown.count == data.count
        guard
            let decoded = previewText(
                of: shown, declaredText: entry.contentType.conforms(to: .text), truncated: splitsScalar)
        else { return nil }
        var lines = decoded.replacingOccurrences(of: "\t", with: "  ")
            .split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
        // The break that ends the last line starts no line of its own.
        if lines.last?.isEmpty == true, lines.count > 1 { lines.removeLast() }
        var excerpt = Excerpt(text: lines.joined(separator: "\n"), isTruncated: isTruncated)
        if isTruncated {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? entry.size
            if let size, size > Int64(shown.count) { excerpt.omittedBytes = size - Int64(shown.count) }
        }
        return excerpt
    }
}
