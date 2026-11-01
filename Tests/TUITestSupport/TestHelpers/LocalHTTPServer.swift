//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalHTTPServer.swift
//
//  A small HTTP server on the loopback address, for the tests of a real URL
//  load: what the status line does to it, and two loads of one URL at once.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

// A BSD socket, so it needs a POSIX libc, as the tarpit in URLImageDownloadTests
// does. WebAssembly has none, and Windows spells it differently.
#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Serves one response to any request on `127.0.0.1`, each on a connection of
/// its own, closed after it.
///
/// `holdUntil` keeps every response back until that many requests have
/// arrived, so that two loads of one URL are both in flight, and both land
/// about together: what a page loading one picture twice does on a fast
/// network, without waiting on one.
final class LocalHTTPServer: @unchecked Sendable {
    let port: UInt16

    private let listener: Int32
    private let status: String
    private let body: Data
    private let holdUntil: Int
    private let lock = NSCondition()
    private var requests = 0

    /// The requests that have arrived so far.
    var requestCount: Int { lock.withLock { requests } }

    /// One server's URL: any path answers the same.
    func url(_ path: String = "/picture") -> String { "http://127.0.0.1:\(port)\(path)" }

    /// SIGPIPE's default action kills the process, and a client that hung up
    /// makes the server's next write raise it. An app gets this from
    /// `SignalManager.install`; a test bundle installs nothing.
    private static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    /// - Parameters:
    ///   - status: The status line after the protocol, such as `200 OK`.
    ///   - body: What every request is answered with.
    ///   - holdUntil: How many requests must arrive before any is answered.
    init(status: String = "200 OK", body: Data, holdUntil: Int = 0) throws {
        _ = Self.ignoreSIGPIPE
        self.status = status
        self.body = body
        self.holdUntil = holdUntil

        #if canImport(Darwin)
            let streamType = SOCK_STREAM
        #else
            let streamType = Int32(SOCK_STREAM.rawValue)
        #endif
        let fd = socket(AF_INET, streamType, 0)
        guard fd >= 0 else { throw SetupError.failed("socket") }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0  // any free port
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian  // 127.0.0.1
        #if canImport(Darwin)
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw SetupError.failed("bind/listen")
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            close(fd)
            throw SetupError.failed("getsockname")
        }

        listener = fd
        port = UInt16(bigEndian: assigned.sin_port)
        let thread = Thread { [self] in acceptConnections() }
        thread.start()
    }

    enum SetupError: Error { case failed(String) }

    /// Stops listening. The accept loop ends when its `accept` fails.
    func stop() {
        // `shutdown` wakes an `accept` blocked on another thread, which a
        // `close` alone does not on Linux.
        #if canImport(Darwin)
            shutdown(listener, SHUT_RDWR)
        #else
            shutdown(listener, Int32(SHUT_RDWR))
        #endif
        close(listener)
    }

    private func acceptConnections() {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }
            Thread { [self] in serve(connection) }.start()
        }
    }

    private func serve(_ connection: Int32) {
        defer { close(connection) }
        // The request itself does not matter, only that all of it has arrived,
        // so that closing does not reset the connection under it.
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !received.contains(Data("\r\n\r\n".utf8)) {
            let count = read(connection, &buffer, buffer.count)
            guard count > 0 else { return }
            received.append(contentsOf: buffer[0..<count])
        }
        lock.withLock {
            requests += 1
            lock.broadcast()
            while requests < holdUntil { lock.wait() }
        }
        var response = Data(
            "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        response.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let count = write(connection, bytes.baseAddress! + sent, bytes.count - sent)
                guard count > 0 else { return }
                sent += count
            }
        }
    }
}

#endif

#endif
