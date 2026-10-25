//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileDialogSystemIconsTests.swift
//
//  `fileDialogSystemIcons()`: the file panels' items drawn with NSWorkspace's
//  icons where pictures draw, kept so each is one picture, and the panels' own
//  icons elsewhere.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

#if canImport(AppKit)
    import AppKit
    @testable import TUIkitAppKit
    import UniformTypeIdentifiers
#endif

@testable import TUIkitAppTestSupport
import TUIkitCore
@testable import TUIkitFilePanels
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

#if canImport(AppKit)
    @MainActor
    @Suite("File panels' system icons")
    struct FileDialogSystemIconsTests {
        @Test("Pictures draw only where the terminal takes them and the app has not turned them off")
        func drawsPictures() {
            #expect(FileDialogSystemIcons.drawsPictures(terminalGraphics: true, supported: true))
            #expect(!FileDialogSystemIcons.drawsPictures(terminalGraphics: false, supported: true))
            #expect(!FileDialogSystemIcons.drawsPictures(terminalGraphics: true, supported: false))
        }

        @Test("A file's icon is its type's; a folder's, a package's and a link's their own")
        func keys() {
            let one = URL(fileURLWithPath: "/tmp/a.txt")
            let two = URL(fileURLWithPath: "/tmp/b.txt")
            #expect(
                FileDialogSystemIcons.key(for: one, type: .plainText)
                    == FileDialogSystemIcons.key(for: two, type: .plainText))
            let downloads = URL(fileURLWithPath: "/Users/someone/Downloads", isDirectory: true)
            let other = URL(fileURLWithPath: "/Users/someone/Work", isDirectory: true)
            #expect(
                FileDialogSystemIcons.key(for: downloads, type: .folder)
                    != FileDialogSystemIcons.key(for: other, type: .folder))
            #expect(FileDialogSystemIcons.key(for: downloads, type: .folder).hasSuffix(downloads.path))
            let app = URL(fileURLWithPath: "/Applications/Safari.app", isDirectory: true)
            #expect(FileDialogSystemIcons.key(for: app, type: .applicationBundle).hasSuffix(app.path))
            #expect(FileDialogSystemIcons.key(for: one, type: .symbolicLink).hasSuffix(one.path))
        }

        @Test("Each icon is asked for once and kept, at the size it is drawn out at")
        func kept() {
            let icons = FileDialogSystemIcons()
            let first = icons.nsImage(for: URL(fileURLWithPath: "/tmp/a.txt"), type: .plainText)
            let second = icons.nsImage(for: URL(fileURLWithPath: "/tmp/b.txt"), type: .plainText)
            #expect(first === second)
            let size = Double(FileDialogSystemIcons.pointSize)
            #expect(first.size == NSSize(width: size, height: size))
            let folder = icons.nsImage(for: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true), type: .folder)
            #expect(folder !== first)
        }

        @Test("Where pictures do not draw, the modifier's icons are none, so a panel draws its own")
        func fallsBack() throws {
            // Turned off by the app, which holds whatever the terminal answered
            // (`KittyGraphics.isSupported` is process-wide, and not this test's).
            var provider: FileDialogIconProvider?
            let context = makeRenderContext()
            _ = renderToBuffer(
                ProviderReader { provider = $0 }.fileDialogSystemIcons().terminalGraphics(false), context: context)
            let installed = try #require(provider)
            #expect(installed.box.icon(URL(fileURLWithPath: "/tmp/a.txt"), .plainText) == nil)
        }
    }

    /// Hands `read` the file panels' icon provider when it renders.
    private struct ProviderReader: View {
        let read: (FileDialogIconProvider?) -> Void

        var body: some View {
            _ProviderReaderCore(read: read)
        }
    }

    private struct _ProviderReaderCore: View, Renderable {
        let read: (FileDialogIconProvider?) -> Void
        var body: Never { fatalError("renders via Renderable") }
        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            read(context.environment.fileDialogIcon)
            return FrameBuffer(lines: [" "])
        }
    }
#endif
