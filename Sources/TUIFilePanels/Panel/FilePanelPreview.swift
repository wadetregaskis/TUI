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
                preview
                    .id(entry.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let excerpt {
                ScrollView {
                    Text(verbatim: excerpt)
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

    /// Legacy alias for ``previewByteCap``.
    nonisolated static var excerptBytes: Int { previewByteCap }

    /// The most lines a preview keeps before truncating.
    nonisolated static let previewLineCap = 250

    /// Legacy alias for ``previewLineCap``.
    nonisolated static var excerptLines: Int { previewLineCap }

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

    /// Decodes `data` as UTF-8 text when it contains no binary control bytes
    /// and is valid UTF-8 (trimming up to three trailing bytes of a split
    /// multi-byte scalar when `truncated` is true); `nil` for binary data.
    nonisolated static func utf8Text(from data: Data, truncated: Bool) -> String? {
        guard !data.isEmpty, !containsBinaryControlBytes(data) else { return nil }
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

    /// The preview text of `entry` if it is a text file, read off the main actor;
    /// `nil` for anything else, or a file that cannot be read.
    ///
    /// Only a regular file (or a link to one) is opened: on Linux a type is
    /// its extension's, so a named pipe called `x.log` is "text", and opening
    /// it waits for a writer — holding a thread of the cooperative pool for
    /// good.
    @concurrent
    static func excerpt(of entry: FileEntry) async -> String? {
        let file = entry.url.resolvingSymlinksInPath()
        guard mayContainText(entry.contentType),
            (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        else { return nil }
        let totalSize = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
            ?? entry.size
        guard let handle = try? FileHandle(forReadingFrom: file),
            let data = try? handle.read(upToCount: previewByteCap),
            !data.isEmpty
        else { return nil }
        try? handle.close()
        let cappedSlice = data.prefix(previewByteCap)
        let total = totalSize ?? Int64(data.count)
        let isTruncatedByBytes = cappedSlice.count < total
        let decoded: String
        if let text = utf8Text(from: cappedSlice, truncated: isTruncatedByBytes) {
            decoded = text
        } else if entry.contentType.conforms(to: .text), !containsBinaryControlBytes(cappedSlice) {
            // Lossy fallback for non-UTF-8 declared text files (e.g. ISO-8859-1,
            // Windows-1252), matching behaviour prior to 426893104 while continuing
            // to reject binary data.
            // swiftlint:disable:next optional_data_string_conversion
            decoded = String(decoding: cappedSlice, as: UTF8.self)
        } else {
            return nil
        }
        let text = decoded.replacingOccurrences(of: "\t", with: "  ")
        var rawLines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
        )
        if rawLines.last?.isEmpty == true, rawLines.count > 1 {
            rawLines.removeLast()
        }
        var lines = rawLines.map(String.init)
        let isTruncatedByLines = lines.count > previewLineCap
        if isTruncatedByLines {
            let shownBytes = Int64((0..<previewLineCap).reduce(0) { total, index in
                let sepEnd = index + 1 < rawLines.count ? rawLines[index + 1].startIndex : text.endIndex
                return total + rawLines[index].utf8.count + text[rawLines[index].endIndex..<sepEnd].utf8.count
            })
            lines = Array(lines.prefix(previewLineCap))
            let remaining = max(0, total - shownBytes)
            if remaining > 0 {
                let formatted = ByteCountFormatStyle(style: .file).format(remaining)
                lines.append("…")
                let format = LocalizationService.shared.string(for: LocalizationKey.FilePanel.previewMore)
                lines.append(String(format: format, formatted))
            }
        } else if isTruncatedByBytes {
            let remaining = max(0, total - Int64(cappedSlice.count))
            if remaining > 0 {
                let formatted = ByteCountFormatStyle(style: .file).format(remaining)
                lines.append("…")
                let format = LocalizationService.shared.string(for: LocalizationKey.FilePanel.previewMore)
                lines.append(String(format: format, formatted))
            }
        }
        return lines.joined(separator: "\n")
    }
}
