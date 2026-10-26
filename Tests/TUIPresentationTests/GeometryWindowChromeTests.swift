//  🖥️ TUI — A Terminal UI framework for Swift
//  GeometryWindowChromeTests.swift
//
//  The scene root's geometry in a window with bars: the frame the root reads
//  is the screen, the bars' rows and the composited layers included, so
//  `.global` is the screen's cells, and a reader in a bar's content or in a
//  presented surface is found and corrected as a reader on the page is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

/// A reader on the page, one in the top bar and one in the bottom bar, each
/// drawing the row it is told it is on.
private struct BarReadersApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text("PAGE")
                GeometryReader { proxy in Text("P\(proxy.frame(in: .global).minY)") }
                    .frame(width: 6, height: 1)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    GeometryReader { proxy in Text("T\(proxy.frame(in: .global).minY)") }
                        .frame(width: 6, height: 1)
                }
                ToolbarItem(placement: .bottomBar) {
                    GeometryReader { proxy in Text("B\(proxy.frame(in: .global).minY)") }
                        .frame(width: 6, height: 1)
                }
            }
        }
    }
}

/// A reader inside a sheet the page presents.
private struct SheetReaderApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .sheet(isPresented: .constant(true)) {
                    VStack(spacing: 0) {
                        Text("SHEET")
                        GeometryReader { proxy in Text("S\(proxy.frame(in: .global).minY)") }
                            .frame(width: 6, height: 1)
                    }
                }
        }
    }
}

@MainActor
@Suite("Geometry in a window with bars", .serialized)
struct GeometryWindowChromeTests {
    @Test("A reader on the page or in either bar draws the screen row it is on, from the first frame")
    func readersAreFoundOnTheScreen() {
        let app = HeadlessApp(BarReadersApp(), width: 40, height: 12)
        for frame in 0..<3 {
            app.frame(atNanos: Int64(frame) * 20_000_000)
            let screen = app.screen.map(\.stripped)
            // Each reader draws its label and the row it was told it is on.
            for label in ["P", "T", "B"] {
                let found = screen.enumerated().filter { $0.element.contains("\(label)\($0.offset)") }
                #expect(found.count == 1, "frame \(frame), \(label): \(screen)")
            }
        }
    }

    @Test("A reader inside a sheet draws the screen row it is on, from the sheet's first frame")
    func sheetReaderIsFoundOnTheScreen() {
        let app = HeadlessApp(SheetReaderApp(), width: 40, height: 12)
        for frame in 0..<2 {
            app.frame(atNanos: Int64(frame) * 20_000_000)
            let screen = app.screen.map(\.stripped)
            let found = screen.enumerated().filter { $0.element.contains("S\($0.offset)") }
            #expect(found.count == 1, "frame \(frame): \(screen)")
        }
    }
}
