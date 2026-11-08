//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelTextPreviewTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

@MainActor
@Suite("File panel text preview", .serialized)
struct FilePanelTextPreviewTests {
    private func entry(for url: URL, size: Int64? = nil) -> FileEntry {
        FileEntry(
            url: url, name: url.lastPathComponent, isFolder: false, isHidden: false, isSymbolicLink: false,
            contentType: .plainText, size: size, modified: nil, sizeText: "", modifiedText: "",
            kind: "Plain Text", isChoosable: true)
    }

    @Test("Small text file excerpt shows full contents without truncation indicator")
    func smallFilePreview() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("small.txt")
        let content = "Hello world\nSecond line\nThird line"
        try Data(content.utf8).write(to: url)

        let entry = entry(for: url, size: Int64(content.utf8.count))
        let excerpt = await FilePanelPreview.excerpt(of: entry)
        #expect(excerpt == FilePanelPreview.Excerpt(text: content))
    }

    @Test("Large text file exceeding line cap is truncated with an indicator")
    func lineCapTruncation() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("manylines.txt")
        let lines = (1...300).map { "Line \($0)" }
        let content = lines.joined(separator: "\n")
        try Data(content.utf8).write(to: url)

        let entry = entry(for: url, size: Int64(content.utf8.count))
        let excerpt = try #require(await FilePanelPreview.excerpt(of: entry))
        #expect(excerpt.text.hasPrefix("Line 1\n"))
        #expect(excerpt.text.hasSuffix("\nLine 250"))
        #expect(excerpt.isTruncated)
        let shownBytes = (1...250).map { "Line \($0)\n" }.joined().utf8.count
        #expect(excerpt.omittedBytes == Int64(content.utf8.count - shownBytes))
        #expect(excerpt.shown(locale: Locale(identifier: "en_US")).contains("\n…\n"))
    }

    @Test("Large text file exceeding byte cap is truncated with an indicator")
    func byteCapTruncation() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("bigfile.txt")
        let singleLine = String(repeating: "A", count: 10_000)
        let lines = (1...10).map { "\($0): \(singleLine)" }
        let content = lines.joined(separator: "\n")
        try Data(content.utf8).write(to: url)

        let entry = entry(for: url, size: Int64(content.utf8.count))
        let excerpt = try #require(await FilePanelPreview.excerpt(of: entry))
        #expect(excerpt.isTruncated)
        #expect(excerpt.text.utf8.count == FilePanelPreview.previewByteCap)
        #expect(excerpt.omittedBytes == Int64(content.utf8.count - FilePanelPreview.previewByteCap))
    }

    @Test("Truncated single-byte incomplete UTF-8 sequence does not trap")
    func truncatedSingleByteDoesNotTrap() {
        let data = Data([0xC3])
        #expect(FilePanelPreview.utf8Text(from: data, truncated: true) == nil)
    }

    @Test("CR-only and CRLF files respect the line cap")
    func lineCapWithDifferentLineEndings() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }

        // CR-only
        let crUrl = fixture.url("cronly.txt")
        let crLines = (1...300).map { "Line \($0)" }
        let crContent = crLines.joined(separator: "\r")
        try Data(crContent.utf8).write(to: crUrl)
        let crEntry = entry(for: crUrl, size: Int64(crContent.utf8.count))
        let crExcerpt = try #require(await FilePanelPreview.excerpt(of: crEntry))
        #expect(crExcerpt.text.hasSuffix("\nLine 250"))
        #expect(crExcerpt.isTruncated)
        #expect(
            crExcerpt.omittedBytes
                == Int64(crContent.utf8.count - (1...250).map { "Line \($0)\r" }.joined().utf8.count))

        // CRLF
        let crlfUrl = fixture.url("crlf.txt")
        let crlfContent = crLines.joined(separator: "\r\n")
        try Data(crlfContent.utf8).write(to: crlfUrl)
        let crlfEntry = entry(for: crlfUrl, size: Int64(crlfContent.utf8.count))
        let crlfExcerpt = try #require(await FilePanelPreview.excerpt(of: crlfEntry))
        #expect(crlfExcerpt.text.hasSuffix("\nLine 250"))
        #expect(crlfExcerpt.isTruncated)
        #expect(
            crlfExcerpt.omittedBytes
                == Int64(crlfContent.utf8.count - (1...250).map { "Line \($0)\r\n" }.joined().utf8.count))
    }

    @Test("Exactly 250 lines ending in a newline has no truncation indicator")
    func exactly250LinesEndingInNewline() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("exact250.txt")
        let lines = (1...250).map { "Line \($0)" }
        let content = lines.joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: url)

        let entry = entry(for: url, size: Int64(content.utf8.count))
        let excerpt = try #require(await FilePanelPreview.excerpt(of: entry))
        #expect(excerpt == FilePanelPreview.Excerpt(text: lines.joined(separator: "\n")))
    }

    @Test("Truncation indicator uses localized text")
    func localizedTruncationIndicator() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("trunc.txt")
        let lines = (1...300).map { "Line \($0)" }
        let content = lines.joined(separator: "\n")
        try Data(content.utf8).write(to: url)

        let entry = entry(for: url, size: Int64(content.utf8.count))
        let excerpt = try #require(await FilePanelPreview.excerpt(of: entry))
        let template = LocalizationService.shared.string(for: LocalizationKey.FilePanel.previewMore)
        #expect(template.contains("%@"))
        // In the language the app is in, and the size in the panel's locale.
        let german = Locale(identifier: "de_DE")
        let size = ByteCountFormatStyle(style: .file, locale: german).format(try #require(excerpt.omittedBytes))
        #expect(excerpt.shown(locale: german).hasSuffix("\n…\n" + String(unsafeFormat: template, size)))

        // Check translation in an isolated service without mutating the shared service
        let configDir = NSTemporaryDirectory() + "tuikit-loc-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: configDir) }
        let service = LocalizationService(configDirectoryPath: configDir)
        service.setLanguageWithoutRendering(.german)
        let germanText = service.string(for: LocalizationKey.FilePanel.previewMore)
        #expect(germanText.contains("mehr"))
    }

    @Test("Non-UTF-8 declared text file (e.g. ISO-8859-1) previews with lossy decoding")
    func nonUtf8TextFilePreview() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("latin1.txt")
        // "Café\nCrème\n" encoded in ISO-8859-1 (where 'é' is 0xE9, 'è' is 0xE8; invalid UTF-8)
        let latin1Bytes: [UInt8] = [0x43, 0x61, 0x66, 0xE9, 0x0A, 0x43, 0x72, 0xE8, 0x6D, 0x65, 0x0A]
        try Data(latin1Bytes).write(to: url)

        let entry = entry(for: url, size: Int64(latin1Bytes.count))
        let excerpt = try #require(await FilePanelPreview.excerpt(of: entry))
        #expect(excerpt.text == "Caf\u{FFFD}\nCr\u{FFFD}me")
    }

    @Test("Declared text file containing binary control bytes is rejected")
    func declaredTextWithBinaryBytesRejected() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("binary.txt")
        let binaryBytes: [UInt8] = [0x00, 0x01, 0x02, 0x41, 0x42]
        try Data(binaryBytes).write(to: url)

        let entry = entry(for: url, size: Int64(binaryBytes.count))
        let excerpt = await FilePanelPreview.excerpt(of: entry)
        #expect(excerpt == nil)
    }

    @Test("Tab-indented lines past the cap are counted in the file's bytes, and the cut still says so")
    func tabIndentedLineCap() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("indented.txt")
        // Each tab is drawn as two spaces: counted in the drawn text, 250 of
        // these lines came to more than the whole file, and the cut went unsaid.
        let content = (1...300).map { _ in "\t\t\treturn x\n" }.joined()
        try Data(content.utf8).write(to: url)

        let excerpt = try #require(await FilePanelPreview.excerpt(of: entry(for: url)))
        #expect(excerpt.isTruncated)
        #expect(excerpt.omittedBytes == Int64(50 * "\t\t\treturn x\n".utf8.count))
    }

    @Test("A cut is known from the read, not the size: a size of nothing still says the file goes on")
    func cutKnownFromTheRead() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("big.txt")
        let content = String(repeating: "x", count: FilePanelPreview.previewByteCap + 10)
        try Data(content.utf8).write(to: url)
        let excerpt = try #require(await FilePanelPreview.excerpt(of: entry(for: url)))
        #expect(excerpt.isTruncated)
        #expect(excerpt.text.utf8.count == FilePanelPreview.previewByteCap)
    }

    @Test("A declared text file with escapes, a closing ⌃Z or backspaces previews")
    func declaredTextWithControlBytes() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let url = fixture.url("build.log")
        try Data("\u{1B}[31mred\u{1B}[0m\nend\u{1A}".utf8).write(to: url)
        let excerpt = try #require(await FilePanelPreview.excerpt(of: entry(for: url)))
        #expect(excerpt.text.contains("red"))
    }
}
