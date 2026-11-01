//  🖥️ TUI — A Terminal UI framework for Swift
//  URLImageHTTPFailureTests.swift
//
//  A response that says the request failed is a failed download, whatever its
//  body is. Nothing read the status, so a 404's HTML page went to the decoder,
//  and the person was told "Image decoding failed" about a picture that was
//  never there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIImage
@testable import TUITestSupport

// The server is a BSD socket (see `LocalHTTPServer`).
#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

@Suite("URL image: HTTP failures")
struct URLImageHTTPFailureTests {
    /// How a load of `status` with `body` fails, or `nil` if it succeeds.
    private func failure(status: String, body: Data) async throws -> ImageLoadError? {
        let server = try LocalHTTPServer(status: status, body: body)
        defer { server.stop() }
        do {
            _ = try await PlatformImageLoader().loadImage(fromURL: server.url())
            return nil
        } catch let error as ImageLoadError {
            return error
        }
    }

    @Test("A 404 is reported as an HTTP failure, not as a picture that would not decode")
    func notFound() async throws {
        let error = try await failure(status: "404 Not Found", body: Data("<html>not here</html>".utf8))
        guard case .downloadFailed(let reason)? = error else {
            Issue.record("expected a download failure, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("HTTP 404"), "\(reason)")
    }

    @Test("A failure status fails even when its body is a picture")
    func failureWithAPictureInIt() async throws {
        let fixture = try BitmapFixture(width: 2, height: 2)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: fixture.path))
        let error = try await failure(status: "500 Internal Server Error", body: bytes)
        guard case .downloadFailed(let reason)? = error else {
            Issue.record("expected a download failure, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("HTTP 500"), "\(reason)")
    }

    @Test("A success status still loads the picture")
    func success() async throws {
        let fixture = try BitmapFixture(width: 2, height: 2)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: fixture.path))
        let error = try await failure(status: "200 OK", body: bytes)
        #expect(error == nil, "\(String(describing: error))")
    }
}
#endif
