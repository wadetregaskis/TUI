//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentStampTests.swift
//
//  An environment's stamp: what a render below it would read, kept so a later
//  environment can be compared with it key by key (Option C, C2a).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Fixtures

private struct NumberKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct NameKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct OptionalServiceKey: EnvironmentKey {
    static let defaultValue: Service? = nil
}

private struct ServiceKey: EnvironmentKey {
    static let defaultValue = Service(name: "default")
}

private struct ActionKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

private struct UnhashedKey: EnvironmentKey {
    static let defaultValue = Unhashed(value: 0)
}

private struct ListKey: EnvironmentKey {
    static let defaultValue: [Unhashed] = []
}

private struct ChannelKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue = 0
}

/// A class whose `==` says two instances are equal: compared by identity all
/// the same, since what a render below reads from a class is the object.
private final class Service: Equatable, @unchecked Sendable {
    let name: String
    init(name: String) { self.name = name }
    static func == (lhs: Service, rhs: Service) -> Bool { lhs.name == rhs.name }
}

/// Equatable and neither hashable nor a collection: its stamps share a
/// shallow hash whatever its value.
private struct Unhashed: Equatable {
    var value: Int
}

@MainActor
@Suite("Environment stamps")
struct EnvironmentStampTests {

    private func environment(_ build: (inout EnvironmentValues) -> Void) -> EnvironmentValues {
        var environment = EnvironmentValues()
        build(&environment)
        return environment
    }

    @Test("Equal values in two environments stamp equivalent; a different one does not")
    func equalValues() throws {
        let stamps = EnvironmentStamps()
        let first = try #require(stamps.build(environment { $0[NumberKey.self] = 3; $0[NameKey.self] = "a" }))
        let same = try #require(stamps.build(environment { $0[NameKey.self] = "a"; $0[NumberKey.self] = 3 }))
        let other = try #require(stamps.build(environment { $0[NumberKey.self] = 4; $0[NameKey.self] = "a" }))
        #expect(first.isEquivalent(to: same))
        #expect(first.shallowHash == same.shallowHash, "the order keys were set in reaches the hash")
        #expect(!first.isEquivalent(to: other))
        #expect(first.firstDifference(from: other) == ObjectIdentifier(NumberKey.self))
    }

    @Test("A class is compared by identity, before its ==")
    func classBeforeEquatable() throws {
        let stamps = EnvironmentStamps()
        let one = Service(name: "s")
        let twin = Service(name: "s")
        #expect(one == twin)
        let first = try #require(stamps.build(environment { $0[ServiceKey.self] = one }))
        let again = try #require(stamps.build(environment { $0[ServiceKey.self] = one }))
        let other = try #require(stamps.build(environment { $0[ServiceKey.self] = twin }))
        #expect(first.isEquivalent(to: again))
        #expect(!first.isEquivalent(to: other), "two equal instances are two objects")
    }

    @Test("An object is held weakly: a stamp keeps nothing alive, and a dead one compares unequal")
    func deadReferenceIsUnequal() throws {
        let stamps = EnvironmentStamps()
        weak var watched: Service?
        let (first, second) = try { () throws -> (EnvironmentStamp, EnvironmentStamp) in
            let service = Service(name: "s")
            watched = service
            let stamped = environment { $0[ServiceKey.self] = service }
            return (try #require(stamps.build(stamped)), try #require(stamps.build(stamped)))
        }()
        #expect(watched == nil, "the stamps kept the object alive")
        #expect(!first.isEquivalent(to: second), "two dead references compared equal")
    }

    #if canImport(ObjectiveC)
        @Test("An Objective-C object is held strongly: some refuse weak references")
        func objectiveCHeldStrongly() throws {
            let stamps = EnvironmentStamps()
            weak var watched: NSObject?
            let stamp = try { () throws -> EnvironmentStamp in
                let object = NSObject()
                watched = object
                return try #require(stamps.build(environment { $0[ObjectKey.self] = object }))
            }()
            #expect(watched != nil)
            #expect(stamp.isEquivalent(to: stamp))
        }
    #endif

    @Test("An Optional is unwrapped; an explicit nil is not a key never set")
    func optionals() throws {
        let stamps = EnvironmentStamps()
        let service = Service(name: "s")
        let set = try #require(stamps.build(environment { $0[OptionalServiceKey.self] = service }))
        let setAgain = try #require(stamps.build(environment { $0[OptionalServiceKey.self] = service }))
        let explicitNil = try #require(stamps.build(environment { $0[OptionalServiceKey.self] = nil }))
        let explicitNilAgain = try #require(stamps.build(environment { $0[OptionalServiceKey.self] = nil }))
        let unset = try #require(stamps.build(EnvironmentValues()))
        #expect(set.isEquivalent(to: setAgain))
        #expect(explicitNil.isEquivalent(to: explicitNilAgain))
        #expect(!set.isEquivalent(to: explicitNil))
        #expect(!explicitNil.isEquivalent(to: unset), "a key set on one side only must be unequal")
    }

    @Test("A value that is not Equatable makes the environment uncomparable, and its key is named")
    func closureIsUncomparable() {
        let stamps = EnvironmentStamps()
        #expect(stamps.build(environment { $0[ActionKey.self] = {} }) == nil)
        #expect(stamps.counts.uncomparable == 1)
        #expect(stamps.uncomparableKeys[ObjectIdentifier(ActionKey.self)] == 1)
        #expect(EnvironmentStamps.debugName(of: ObjectIdentifier(ActionKey.self)).hasSuffix("ActionKey"))
    }

    @Test("A neutral key is skipped")
    func neutralKeySkipped() throws {
        let stamps = EnvironmentStamps()
        let first = try #require(stamps.build(environment { $0[NumberKey.self] = 1; $0[ChannelKey.self] = 1 }))
        let second = try #require(stamps.build(environment { $0[NumberKey.self] = 1; $0[ChannelKey.self] = 2 }))
        #expect(first.isEquivalent(to: second))
        #expect(first.entries.count == 1)
    }

    @Test("Interned, an environment rebuilt in a later pass with a new volatile-read tracker is the same stamp")
    func internedAcrossPasses() throws {
        let stamps = EnvironmentStamps()
        func pass() -> EnvironmentStamp? {
            stamps.beginPass()
            return stamps.stamp(of: environment {
                $0[NumberKey.self] = 7
                $0.volatileReadTracker = VolatileReadTracker()
            })
        }
        let first = try #require(pass())
        let second = try #require(pass())
        #expect(first === second)
        #expect(stamps.counts.internHits == 1)
    }

    @Test("Within a pass an environment is stamped once, by its storage")
    func memoisedWithinAPass() {
        let stamps = EnvironmentStamps()
        stamps.beginPass()
        let shared = environment { $0[NumberKey.self] = 1 }
        let first = stamps.stamp(of: shared)
        let second = stamps.stamp(of: shared)
        #expect(first === second)
        #expect(stamps.counts.built == 1)
        #expect(stamps.counts.memoHits == 1)
    }

    @Test("Stamps never hold one another: a thousand passes keep as many alive as there are environments")
    func liveStampsBounded() {
        let stamps = EnvironmentStamps()
        var held: [EnvironmentStamp] = []
        for frame in 0..<1_000 {
            stamps.beginPass()
            let made = stamps.stamp(of: environment {
                $0[NumberKey.self] = frame % 3
                $0.volatileReadTracker = VolatileReadTracker()
            })
            if let made { held.append(made) }
            if held.count > 3 { held.removeFirst() }
        }
        stamps.beginPass()
        #expect(stamps.liveStampCount <= 3, "\(stamps.liveStampCount) stamps alive")
    }

    @Test("A collection's count separates stamps of values that hash nothing else")
    func collectionDiscriminator() throws {
        let stamps = EnvironmentStamps()
        let short = try #require(stamps.build(environment { $0[ListKey.self] = [Unhashed(value: 1)] }))
        let long = try #require(stamps.build(environment { $0[ListKey.self] = [Unhashed(value: 1), Unhashed(value: 2)] }))
        #expect(short.shallowHash != long.shallowHash)
    }

    @Test("A bucket keeps 32 live stamps, most recently used first, and counts what it pushes out")
    func bucketCapacity() {
        let stamps = EnvironmentStamps()
        var held: [EnvironmentStamp] = []
        for value in 0..<40 {
            if let made = stamps.stamp(of: environment { $0[UnhashedKey.self] = Unhashed(value: value) }) {
                held.append(made)
            }
        }
        #expect(held.count == 40)
        #expect(stamps.counts.overflows == 40 - EnvironmentStamps.bucketCapacity)
        // The first is the least recently used and was pushed out; a stamp of
        // the same environment is now a new object.
        stamps.beginPass()
        let again = stamps.stamp(of: environment { $0[UnhashedKey.self] = Unhashed(value: 0) })
        #expect(again !== held[0])
        #expect(again?.isEquivalent(to: held[0]) == true)
    }

    @Test("An environment's storage is one word, on every platform")
    func storageIsOneWord() {
        #expect(MemoryLayout<[ObjectIdentifier: Any]>.size == MemoryLayout<UInt>.size)
        let environment = environment { $0[NumberKey.self] = 1 }
        let copy = environment
        #expect(environment.storageWord == copy.storageWord)
    }

    /// Every key declared neutral, and why a row's pixels cannot depend on it.
    /// A key added to the list without a reason here fails; the behavioural
    /// proofs (a row stored under one value served under another) come with
    /// the re-check that serves rows (C4c).
    private static let neutralKeys: [String: String] = [
        "VolatileReadTrackerKey": "a mailbox: a reader records its read and is never stored",
        "PulsePhaseKey": "a reader records a volatile read, so nothing that read it is stored",
        "CursorTimerKey": "a reader records a volatile read, so nothing that read it is stored",
        "PreferenceStorageKey": "a mailbox views post into and never draw from",
        "RowEditRestrictionsKey": "a mailbox views post into and never draw from",
        "KeyEventDispatcherKey": "a per-walk channel: registrations are journalled and replayed into the one in force",
        "MouseEventDispatcherKey": "a per-walk channel: registrations are journalled and replayed into the one in force",
        "KeyChannelTokenKey": "a per-walk channel: registrations are journalled and replayed into the one in force",
        "FocusManagerKey": "a per-walk channel; a focused control is never stored",
        "StateStorageKey": "a service mirrored onto the render context",
        "RenderCacheKey": "a service mirrored onto the render context",
        "LifecycleKey": "a service: registrations are journalled and replayed",
        "AnimationSchedulerKey": "a service: wakes are asked for, nothing drawn from it",
        "DrawsBackdropKey": "carried by the key: the buffer's effect scope includes it",
        "StatusBarKey": "a per-walk channel: items are registered into the one in force, nothing drawn from it",
        "KeyboardShortcutRegistryKey": "a per-walk channel: shortcuts are registered into the one in force",
        "SynthesizeKeyEventKey": "an app service called at event time, installed once from the TUIContext",
        "ClipboardAccessKey": "an app service called at event time, installed once from the TUIContext",
    ]

    @Test("Every key declared neutral is listed with why")
    func neutralRegistry() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var declared: Set<String> = []
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let pattern = /struct (\w+): EnvironmentKey, _RenderNeutralEnvironmentKey/
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: pattern) { declared.insert(String(match.1)) }
        }
        #expect(declared == Set(Self.neutralKeys.keys), "declared but not listed: \(declared.subtracting(Self.neutralKeys.keys))")
    }
}

#if canImport(ObjectiveC)
    private struct ObjectKey: EnvironmentKey {
        nonisolated(unsafe) static let defaultValue = NSObject()
    }
#endif
