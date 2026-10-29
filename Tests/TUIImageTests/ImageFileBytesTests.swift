//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageFileBytesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIImage

/// `loadImage(from path:)` used to hand the path to stb_image's `stbi_load`,
/// whose narrow `fopen` decodes it under the Windows ANSI codepage rather than
/// UTF-8. Foundation now reads the bytes, so these tests pin the two things
/// that made that a bug: a non-ASCII path resolves, and a read failure still
/// surfaces as `ImageLoadError`.
///
/// In `TUIImageTests` rather than `TUIFoundationTests` deliberately: the Windows
/// lane cannot build the `TUI` umbrella yet (CONTRIBUTING.md), so this is
/// the only target that even COMPILES there — and compiling is all it does.
/// `.github/workflows/ci.yml:463` runs `build --target TUIImageTests`, and
/// the lane's one `test` step (`:484`) has to build the umbrella first, so no
/// test in this package has ever EXECUTED on Windows. These are therefore
/// contract pins for the hosts that never had the bug, not a reproduction:
/// the Windows behaviour is verified by reading stb_image.h, not by CI.
@Suite("Image file bytes")
struct ImageFileBytesTests {

    @Test("Reads a file whose directory and name are both outside ASCII")
    func readsNonASCIIPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-café-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("日本-café.png")
        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try payload.write(to: file)

        #expect(try PlatformImageLoader.fileBytes(atPath: file.path) == payload)
    }

    @Test("An unreadable path throws ImageLoadError, not a Foundation error")
    func unreadablePathThrowsImageLoadError() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-absent-\(UUID().uuidString).png").path

        #expect(throws: ImageLoadError.self) {
            try PlatformImageLoader.fileBytes(atPath: absent)
        }
    }

    #if !os(Windows)
        /// A named pipe reports 0 bytes, so it passed as a small file and was
        /// opened to decode on the frame that drew it, which waits for a
        /// writer: the app froze, signals and all (2026-10-29 review). Before
        /// the fix this test hangs rather than fails.
        @Test("A named pipe is refused, not opened")
        func namedPipeRefused() throws {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("tuikit-fifo-\(UUID().uuidString).png").path
            #expect(mkfifo(path, 0o600) == 0)
            defer { try? FileManager.default.removeItem(atPath: path) }
            #expect(throws: ImageLoadError.self) { try PlatformImageLoader().loadImage(from: path) }
        }
    #endif
}
