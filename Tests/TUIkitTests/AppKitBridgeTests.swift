//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppKitBridgeTests.swift
//
//  The bridges to Apple's colour types, which live in TUIkitAppKit so that
//  nothing TUIkit is built from imports AppKit — and the guard that keeps it
//  that way.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

#if canImport(AppKit)
    import AppKit
    import TUIkitAppKit
#endif

@testable import TUIkit

@MainActor
@Suite("Bridges to AppKit")
struct AppKitBridgeTests {
    #if canImport(AppKit)
        @Test("A colour goes to NSColor and CGColor and comes back the same")
        func colourRoundTrips() {
            let colour = Color(red: 1, green: 0.5, blue: 0)
            let resolved = colour.resolve(in: EnvironmentValues())
            let fromNS = Color(nsColor: NSColor(colour)).resolve(in: EnvironmentValues())
            let fromCG = Color(cgColor: resolved.cgColor).resolve(in: EnvironmentValues())
            for back in [fromNS, fromCG] {
                #expect(abs(back.red - resolved.red) < 0.01)
                #expect(abs(back.green - resolved.green) < 0.01)
                #expect(abs(back.blue - resolved.blue) < 0.01)
            }
        }
    #endif

    /// The rule the module split exists for: no source of a module TUIkit is
    /// built from imports AppKit. A module that did would load SwiftUICore
    /// into every app that imports TUIkit, `internal import` or not, and put
    /// SwiftUI's own `FormatStyle.offset(to:)` and the rest beside TUIkit's.
    @Test("No module TUIkit is built from imports AppKit")
    func noAppKitBelowTheBridges() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var offenders: [String] = []
        for module in ["TUIkit", "TUIkitCore", "TUIkitStyling", "TUIkitView", "TUIkitImage"] {
            let directory = sources.appendingPathComponent(module)
            let walker = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let file as URL in walker where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for line in text.split(separator: "\n") {
                    let words = line.split(separator: " ")
                    if words.contains("import"), words.contains("AppKit") || words.contains("Cocoa")
                        || words.contains("SwiftUI")
                    {
                        offenders.append("\(module)/\(file.lastPathComponent): \(line)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
