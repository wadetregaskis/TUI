//  🖥️ TUI — A Terminal UI framework for Swift
//  EntryMacroTests.swift
//
//  `@Entry`, used as an app uses it: the entries below are expanded by the
//  compiler plugin, and the tests read and write what it wrote, in each of
//  the four types an entry can extend.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUI
import TUIMacros

// `ContainerValues()` and `FocusedValues()` are the framework's to make; the
// tests make them to read an entry without drawing a view.
@testable import TUIFoundation

/// A reference type, so a test can tell one default from the next.
final class EntryBox {}

extension EnvironmentValues {
    @Entry var entryGreeting: String = "Hello"
    @Entry var entryInferred = 42
    @Entry var entryOptional: Int?
    @Entry var entryBox = EntryBox()
    /// A public entry: its accessors take the property's access, its key
    /// stays private.
    @Entry public var entryPublic: Double = 1.5
}

extension Transaction {
    @Entry var entryIsUndo: Bool = false
}

extension ContainerValues {
    @Entry var entryRank: Int = 7
}

extension FocusedValues {
    @Entry var entryTitle: String?
}

@MainActor
@Suite("@Entry")
struct EntryMacroTests {
    @Test("An environment entry reads its default until set, and what was set after")
    func environment() {
        var environment = EnvironmentValues()
        #expect(environment.entryGreeting == "Hello")
        #expect(environment.entryInferred == 42)
        #expect(environment.entryOptional == nil)
        #expect(environment.entryPublic == 1.5)
        environment.entryGreeting = "Hi"
        environment.entryInferred = 7
        environment.entryOptional = 3
        #expect(environment.entryGreeting == "Hi")
        #expect(environment.entryInferred == 7)
        #expect(environment.entryOptional == 3)
        #expect(EnvironmentValues().entryGreeting == "Hello", "a fresh table still reads the default")
    }

    @Test("The default is made at each read, as SwiftUI's is")
    func defaultMadeAtEachRead() {
        let environment = EnvironmentValues()
        let first = environment.entryBox
        let second = environment.entryBox
        #expect(first !== second)
    }

    @Test("A transaction entry reads its default until set")
    func transaction() {
        var transaction = Transaction()
        #expect(!transaction.entryIsUndo)
        transaction.entryIsUndo = true
        #expect(transaction.entryIsUndo)
    }

    @Test("A container entry reads its default until set")
    func container() {
        var values = ContainerValues()
        #expect(values.entryRank == 7)
        values.entryRank = 1
        #expect(values.entryRank == 1)
    }

    @Test("A focused entry is nil until published, and its key names the type without the ?")
    func focused() {
        var values = FocusedValues()
        #expect(values.entryTitle == nil)
        values.entryTitle = "Draft"
        #expect(values.entryTitle == "Draft")
        values.entryTitle = nil
        #expect(values.entryTitle == nil)
    }
}
