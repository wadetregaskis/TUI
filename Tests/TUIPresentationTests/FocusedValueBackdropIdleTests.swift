//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusedValueBackdropIdleTests.swift
//
//  A view's own `@FocusedValue` drawn as a backdrop — the page beneath a
//  sheet, a `.dimmed()` card — reads what a live reader reads, the values for
//  wherever the focus is, so the end-of-pass check that repeats the reading
//  agrees with it and an app with nothing changing asks for no more frames.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

private struct BackdropNoteKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    fileprivate var backdropNote: String? {
        get { self[BackdropNoteKey.self] }
        set { self[BackdropNoteKey.self] = newValue }
    }
}

/// Draws the focused note, read through the view's own `@FocusedValue`.
private struct BackdropNoteLine: View {
    @FocusedValue(\.backdropNote) private var note

    var body: some View {
        Text("note: \(note ?? "none")")
    }
}

/// A page whose reader is drawn beneath a modal sheet, while the sheet's
/// focused control publishes a focused value — not a scene value, which a
/// reader with no focus of its own would see too.
private struct SheetOverReaderApp: App {
    var body: some Scene {
        WindowGroup {
            // The reader on the top row, clear of the sheet drawn in the middle.
            VStack {
                BackdropNoteLine()
                Spacer()
                Button("page") {}
            }
            .sheet(isPresented: .constant(true)) {
                Button("in the sheet") {}.focusedValue(\.backdropNote, "sheet")
            }
        }
    }
}

/// The same reader inside a `.dimmed()` card, beside the focused control
/// that publishes.
private struct DimmedReaderApp: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                BackdropNoteLine().dimmed()
                Button("live") {}.focusedValue(\.backdropNote, "live")
            }
        }
    }
}

@MainActor
@Suite("A @FocusedValue drawn as a backdrop", .rendersEnglishUI)
struct FocusedValueBackdropIdleTests {
    private static let frameNanos: Int64 = 16_666_667

    /// Draws `count` frames from `now`, one frame interval apart.
    private func frames(_ app: HeadlessApp<some App>, _ count: Int, from now: inout Int64) {
        for _ in 0..<count {
            app.frame(atNanos: now)
            now += Self.frameNanos
        }
    }

    @Test("A reader beneath a sheet reads the sheet's focused value and asks for no frames once settled")
    func readerBeneathASheetIdles() {
        let app = HeadlessApp(SheetOverReaderApp(), width: 40, height: 12)
        var now: Int64 = 0
        frames(app, 3, from: &now)
        let settled = app.framesAsked
        frames(app, 4, from: &now)
        #expect(app.framesAsked == settled, "frames asked for over four frames that change nothing")
        #expect(
            app.screen.map(\.stripped).contains { $0.contains("note: sheet") },
            "the page beneath reads what the focus publishes: \(app.screen.map(\.stripped))")
    }

    @Test("A reader in a dimmed card reads the focused value and asks for no frames once settled")
    func readerInADimmedCardIdles() {
        let app = HeadlessApp(DimmedReaderApp(), width: 40, height: 12)
        var now: Int64 = 0
        frames(app, 3, from: &now)
        let settled = app.framesAsked
        frames(app, 4, from: &now)
        #expect(app.framesAsked == settled, "frames asked for over four frames that change nothing")
        #expect(
            app.screen.map(\.stripped).contains { $0.contains("note: live") },
            "the dimmed card reads what the focus publishes: \(app.screen.map(\.stripped))")
    }
}
