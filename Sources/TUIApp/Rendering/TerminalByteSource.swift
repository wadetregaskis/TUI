//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalByteSource.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Where ``Terminal`` reads its input bytes from: standard input, or a test's
/// script (``Terminal/readSource``).
///
/// A protocol, held as `any TerminalByteSource`, rather than a stored closure
/// over a buffer pointer: a closure of that type is an unsafe type, and storing
/// one would make the terminal's storage unsafe, and every type holding a
/// terminal after it (strict memory safety). The read is as unsafe as it was,
/// and marked `unsafe` where it is called.
protocol TerminalByteSource {
    /// Reads at most `buffer.count` bytes into `buffer`, and returns how many:
    /// 0 for none, negative for an error, as `read(2)` does.
    func read(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int
}

/// A ``TerminalByteSource`` that is a closure, as ``Terminal/readSource`` is
/// set and read.
@unsafe struct ClosureByteSource: TerminalByteSource {
    let body: (UnsafeMutableBufferPointer<UInt8>) -> Int

    func read(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        unsafe body(buffer)
    }
}
