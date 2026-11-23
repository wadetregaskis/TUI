//  🖥️ TUI — A Terminal UI framework for Swift
//  JSONFileStorageTableTests.swift
//
//  The table every `UserDefaultsStorage` over one suite's file shares its
//  backing through, on Linux, WebAssembly and Windows. That arm is not
//  compiled on Apple platforms, so these test the table itself, on a table of
//  their own: it is the whole of what the arm adds (bug hunt FENV-2, H-41).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation

@Suite("One backing for each file, shared while a store over it lives")
struct JSONFileStorageTableTests {

    /// A folder of the test's own, removed afterwards.
    private static func withDirectory(_ body: (URL) throws -> Void) rethrows {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit.tests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test("Two stores over one file see each other's writes at once")
    func oneFileOneBacking() {
        Self.withDirectory { directory in
            let table = JSONFileStorageTable()
            let file = directory.appendingPathComponent("UserDefaults-prefs.json")
            let first = table.store(at: file)
            // Another spelling of the same path is the same file.
            let second = table.store(at: directory.appendingPathComponent("./x/../UserDefaults-prefs.json"))
            defer { first.synchronize() }

            #expect(first === second, "two stores over one file had a backing each")
            first.setValue("dark", forKey: "theme")
            #expect(second.value(forKey: "theme") == Optional("dark"), "a write was not read through the other store")
            #expect(
                first.entry(forKey: "theme", as: String.self).key
                    === second.entry(forKey: "theme", as: String.self).key,
                "the two stores' readers wait on different keys, so one's write would not redraw the other's")
        }
    }

    @Test("A backing goes with the last store over it, and the next one reads what it saved")
    func freedWithItsLastStore() {
        Self.withDirectory { directory in
            let table = JSONFileStorageTable()
            let file = directory.appendingPathComponent("UserDefaults-prefs.json")
            weak var backing: JSONFileStorage?
            // In a function of its own, so both stores are let go at its end
            // rather than at their last use.
            func useAndLetGo() {
                let first = table.store(at: file)
                let second = table.store(at: file)
                backing = first
                second.setValue(3, forKey: "count")
                #expect(first.value(forKey: "count") == Optional(3))
                // Past the queued save, which holds the backing while it runs.
                first.synchronize()
            }
            useAndLetGo()
            #expect(backing == nil, "the table kept the backing alive after its last store went")

            let next = table.store(at: file)
            defer { next.synchronize() }
            #expect(next.value(forKey: "count") == Optional(3), "the freed backing's write was lost")
        }
    }

    @Test("Two files keep a backing each, even of one name")
    func twoFilesStaySeparate() {
        Self.withDirectory { directory in
            let table = JSONFileStorageTable()
            let elsewhere = directory.appendingPathComponent("elsewhere", isDirectory: true)
            try? FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            let here = table.store(at: directory.appendingPathComponent("UserDefaults.json"))
            let there = table.store(at: elsewhere.appendingPathComponent("UserDefaults.json"))
            let other = table.store(at: directory.appendingPathComponent("UserDefaults-other.json"))
            defer { [here, there, other].forEach { $0.synchronize() } }

            #expect(here !== there, "two folders' files of one name shared a backing")
            #expect(here !== other, "two suites' files shared a backing")
            here.setValue(1, forKey: "count")
            #expect(there.value(forKey: "count") == Int?.none)
            #expect(other.value(forKey: "count") == Int?.none)
        }
    }

    @Test("An entry whose backing has gone is dropped when another is added")
    func goneEntriesAreDropped() {
        Self.withDirectory { directory in
            let table = JSONFileStorageTable()
            func useAndLetGo(_ name: String) {
                _ = table.store(at: directory.appendingPathComponent(name))
            }
            useAndLetGo("UserDefaults-a.json")
            useAndLetGo("UserDefaults-b.json")
            useAndLetGo("UserDefaults-c.json")
            let kept = table.store(at: directory.appendingPathComponent("UserDefaults-d.json"))
            withExtendedLifetime(kept) {
                #expect(table.entryCount == 1, "entries for files no store is over were kept")
            }
        }
    }
}
