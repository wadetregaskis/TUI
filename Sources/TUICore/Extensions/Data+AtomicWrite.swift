//  🖥️ TUI — A Terminal UI framework for Swift
//  Data+AtomicWrite.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Data {
    /// Writes the data to `url`, replacing what is there: atomically where the
    /// platform can, so that a crash leaves the old file or the new one whole,
    /// and directly where it cannot.
    ///
    /// WASI is where it cannot. Its Foundation has no atomic write: `.atomic` is
    /// unavailable to compile ("temporary files are not supported"),
    /// `atomically: true` fails at run time (NSCocoaError 3328), and a
    /// temporary file of one's own is no way round it, since `rename` over an
    /// existing file answers "Not supported" under WasmKit (measured
    /// 2026-11-10). A write that asked for atomicity there wrote nothing at all;
    /// now it writes, and a host that needs the guarantee provides it.
    ///
    /// Every write of a file TUI keeps or an app saves goes through this, so a
    /// platform that gains atomic writes gains them everywhere at once.
    package func writeAtomicallyWherePossible(to url: URL) throws {
        #if canImport(WASILibc)
            try write(to: url)
        #else
            try write(to: url, options: .atomic)
        #endif
    }
}
