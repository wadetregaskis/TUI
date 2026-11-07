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
        #expect(excerpt == content)
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
        #expect(excerpt.contains("Line 1"))
        #expect(excerpt.contains("…"))
        #expect(excerpt.contains("(plus"))
        #expect(excerpt.contains("more)"))
        #expect(!excerpt.contains("Line 299"))
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
        #expect(excerpt.contains("…"))
        #expect(excerpt.contains("(plus"))
        #expect(excerpt.contains("more)"))
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
        #expect(crExcerpt.contains("Line 1"))
        #expect(crExcerpt.contains("…"))
        #expect(crExcerpt.contains("(plus"))
        #expect(!crExcerpt.contains("Line 299"))

        // CRLF
        let crlfUrl = fixture.url("crlf.txt")
        let crlfContent = crLines.joined(separator: "\r\n")
        try Data(crlfContent.utf8).write(to: crlfUrl)
        let crlfEntry = entry(for: crlfUrl, size: Int64(crlfContent.utf8.count))
        let crlfExcerpt = try #require(await FilePanelPreview.excerpt(of: crlfEntry))
        #expect(crlfExcerpt.contains("Line 1"))
        #expect(crlfExcerpt.contains("…"))
        #expect(crlfExcerpt.contains("(plus"))
        #expect(!crlfExcerpt.contains("Line 299"))
    }
}
