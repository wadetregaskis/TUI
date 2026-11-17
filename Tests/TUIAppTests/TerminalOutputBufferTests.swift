//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalOutputBufferTests.swift
//
//  Created by LAYERED.work
//  License: MIT

// Every test reads stdout back through pipe(2), which wasip1 does not have.
#if !canImport(WASILibc)

import Foundation
import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

// MARK: - Output Capture Helper

/// Captures all bytes written to `STDOUT_FILENO` during a closure.
///
/// Redirects stdout to a pipe, runs the closure, restores stdout,
/// and returns the captured bytes as a UTF-8 string.
@MainActor
private func captureStdout(_ body: () -> Void) -> String {
    #if os(Windows)
        // The C library's names for the same calls. Its `_dup2` onto descriptor 1
        // points the standard output handle, which the terminal writes through
        // (`StandardHandle`), at the pipe too. The pipe is large enough for every
        // test here, as nothing reads it until the body is done.
        var pipeFDs: [Int32] = [0, 0]
        _ = _pipe(&pipeFDs, 1 << 20, _O_BINARY)
        let savedStdout = _dup(1)
        _ = _dup2(pipeFDs[1], 1)
        body()
        _ = _close(pipeFDs[1])
        _ = _dup2(savedStdout, 1)
        _ = _close(savedStdout)
        var data = Data()
        var readBuffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = _read(pipeFDs[0], &readBuffer, UInt32(readBuffer.count))
            if bytesRead <= 0 { break }
            data.append(contentsOf: readBuffer.prefix(Int(bytesRead)))
        }
        _ = _close(pipeFDs[0])
        return String(data: data, encoding: .utf8) ?? ""
    #else
    var pipeFDs: [Int32] = [0, 0]
    unsafe pipe(&pipeFDs)

    let savedStdout = dup(STDOUT_FILENO)
    dup2(pipeFDs[1], STDOUT_FILENO)

    body()

    // Flush and close write end so read doesn't block
    close(pipeFDs[1])
    dup2(savedStdout, STDOUT_FILENO)
    close(savedStdout)

    // Read captured output
    var data = Data()
    var readBuffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let bytesRead = unsafe read(pipeFDs[0], &readBuffer, readBuffer.count)
        if bytesRead <= 0 { break }
        data.append(contentsOf: readBuffer.prefix(bytesRead))
    }
    close(pipeFDs[0])

    return String(data: data, encoding: .utf8) ?? ""
    #endif
}

// MARK: - Frame Buffer Tests

@Suite("Terminal Output Buffer Tests", .serialized)
@MainActor
struct TerminalOutputBufferTests {

    @Test("Buffered writes produce same output as unbuffered writes")
    func bufferedMatchesUnbuffered() {
        let unbuffered = captureStdout {
            let terminal = Terminal()
            terminal.write("Hello")
            terminal.write(" World")
        }

        let buffered = captureStdout {
            let terminal = Terminal()
            terminal.beginFrame()
            terminal.write("Hello")
            terminal.write(" World")
            terminal.endFrame()
        }

        #expect(unbuffered == "Hello World")
        #expect(buffered == "Hello World")
    }

    @Test("endFrame without beginFrame is a no-op")
    func endFrameWithoutBeginIsNoop() {
        let output = captureStdout {
            let terminal = Terminal()
            terminal.endFrame()
            terminal.write("After")
        }

        #expect(output == "After")
    }

    @Test("Double beginFrame is a no-op — buffer is not reset")
    func doubleBeginFrameIsNoop() {
        let output = captureStdout {
            let terminal = Terminal()
            terminal.beginFrame()
            terminal.write("First")
            terminal.beginFrame()  // should not reset buffer
            terminal.write("Second")
            terminal.endFrame()
        }

        #expect(output == "FirstSecond")
    }

    @Test("Sequential frames on same terminal flush independently")
    func sequentialFramesFlushIndependently() {
        let output = captureStdout {
            let terminal = Terminal()
            terminal.beginFrame()
            terminal.write("Frame1")
            terminal.endFrame()
            terminal.beginFrame()
            terminal.write("Frame2")
            terminal.endFrame()
        }

        #expect(output == "Frame1Frame2")
    }

    @Test("Empty frame produces no output")
    func emptyFrameProducesNoOutput() {
        let output = captureStdout {
            let terminal = Terminal()
            terminal.beginFrame()
            terminal.endFrame()
        }

        #expect(output.isEmpty)
    }

    @Test("Buffered frame handles ANSI escape sequences correctly")
    func bufferedFrameHandlesANSI() {
        let cursorMove = ANSIRenderer.moveCursor(toRow: 5, column: 1)
        var style = TextStyle()
        style.isBold = true
        let styled = ANSIRenderer.render("Bold", with: style)

        let output = captureStdout {
            let terminal = Terminal()
            terminal.beginFrame()
            terminal.write(cursorMove)
            terminal.write(styled)
            terminal.endFrame()
        }

        #expect(output.contains("\u{1B}[5;1H"))
        #expect(output.contains("\u{1B}[1m"))
        #expect(output.contains("Bold"))
    }
}

#endif
