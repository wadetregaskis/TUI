//  🖥️ TUI — A Terminal UI framework for Swift
//  EnvironmentStampDerivedTests.swift
//
//  A stamp made from what an environment changes against the pass's first:
//  each must say what a stamp built flat from the same environment says.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIView

private struct NumberKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct TextKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct OtherKey: EnvironmentKey {
    static let defaultValue = 0
}

private final class Service {}

private struct ServiceKey: EnvironmentKey {
    static var defaultValue: Service? { nil }
}

private struct NeutralKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue = 0
}

private struct ClosureKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

private func environment(_ fill: (inout EnvironmentValues) -> Void) -> EnvironmentValues {
    var values = EnvironmentValues()
    fill(&values)
    return values
}

@MainActor
@Suite("A stamp derived from the pass's first")
struct EnvironmentStampDerivedTests {
    /// Stamps `environments` in order in one pass, the first as the anchor.
    private func pass(_ stamps: EnvironmentStamps, _ environments: [EnvironmentValues]) -> [EnvironmentStamp?] {
        stamps.beginPass()
        let made = environments.map { stamps.stamp(of: $0) }
        stamps.endPass()
        return made
    }

    private let root = environment {
        $0[NumberKey.self] = 1
        $0[TextKey.self] = "root"
    }

    @Test("The same environment two ways round is one stamp, in a pass and across passes")
    func canonical() {
        let stamps = EnvironmentStamps()
        let oneThenTwo = environment {
            $0[NumberKey.self] = 5
            $0[TextKey.self] = "root"
            $0[OtherKey.self] = 2
        }
        let twoThenOne = environment {
            $0[OtherKey.self] = 2
            $0[TextKey.self] = "root"
            $0[NumberKey.self] = 5
        }
        let first = pass(stamps, [root, oneThenTwo, twoThenOne])
        #expect(first[1] === first[2])
        #expect(stamps.counts.derived == 2)
        let second = pass(stamps, [root, twoThenOne])
        #expect(second[0] === first[0])
        #expect(second[1] === first[1])
    }

    @Test("A key set to what the anchor holds is no change, nor is a neutral key")
    func noChange() {
        let stamps = EnvironmentStamps()
        let same = environment {
            $0[NumberKey.self] = 1
            $0[TextKey.self] = String("ro") + "ot"
            $0[NeutralKey.self] = 9
        }
        let made = pass(stamps, [root, same])
        #expect(made[0] === made[1])
    }

    @Test("Each kind of difference, as a flat stamp of the same environment says it")
    func agreesWithFlat() throws {
        let stamps = EnvironmentStamps()
        let service = Service()
        let cases = [
            environment {
                $0[NumberKey.self] = 2
                $0[TextKey.self] = "root"
            },
            environment { $0[NumberKey.self] = 1 },
            environment {
                $0[NumberKey.self] = 1
                $0[TextKey.self] = "root"
                $0[ServiceKey.self] = service
            },
            environment {
                $0[NumberKey.self] = 1
                $0[TextKey.self] = "root"
                $0[ServiceKey.self] = nil
            },
        ]
        let made = pass(stamps, [root] + cases).dropFirst()
        for (index, stamp) in made.enumerated() {
            let derived = try #require(stamp)
            let flat = try #require(stamps.build(cases[index]))
            #expect(derived.base != nil)
            #expect(derived.isEquivalent(to: flat))
            #expect(flat.isEquivalent(to: derived))
            #expect(derived.firstDifference(from: flat) == nil)
            #expect(derived.entries.map(\.key) == flat.entries.map(\.key))
        }
        // And none of them is any other.
        let all = Array(made)
        for left in all.indices {
            for right in all.indices where left != right {
                #expect(all[left]?.isEquivalent(to: all[right]!) == false)
            }
        }
    }

    @Test("An object's identity is a difference, and one that has died equals nothing")
    func objects() throws {
        let stamps = EnvironmentStamps()
        let one = Service()
        let holding = environment { $0[ServiceKey.self] = one }
        let other = environment { $0[ServiceKey.self] = Service() }
        let made = pass(stamps, [environment { $0[NumberKey.self] = 1 }, holding, other, holding])
        #expect(made[1] === made[3])
        #expect(made[1] !== made[2])
    }

    @Test("What cannot be compared has no stamp, on an anchor as flat")
    func uncomparable() {
        let stamps = EnvironmentStamps()
        let withClosure = environment {
            $0[NumberKey.self] = 1
            $0[TextKey.self] = "root"
            $0[ClosureKey.self] = {}
        }
        let made = pass(stamps, [root, withClosure])
        #expect(made[0] != nil)
        #expect(made[1] == nil)
        #expect(stamps.counts.uncomparable == 1)
    }

    @Test("Stamps on different anchors still compare by what they hold")
    func differentAnchors() throws {
        let stamps = EnvironmentStamps()
        let target = environment {
            $0[NumberKey.self] = 7
            $0[TextKey.self] = "root"
        }
        let first = try #require(pass(stamps, [root, target])[1])
        let otherRoot = environment { $0[OtherKey.self] = 3 }
        let second = try #require(pass(stamps, [otherRoot, target])[1])
        #expect(first !== second)
        #expect(first.isEquivalent(to: second))
        #expect(second.isEquivalent(to: first))
    }

    @Test("A bucket of stamps on one anchor keeps 32, and goes on answering")
    func derivedBucket() {
        let stamps = EnvironmentStamps()
        var held: [EnvironmentStamp?] = []
        stamps.beginPass()
        _ = stamps.stamp(of: root)
        // Unhashed values have a hash of the key alone, so they share a bucket.
        for value in 0..<40 {
            held.append(
                stamps.stamp(
                    of: environment {
                        $0[NumberKey.self] = 1
                        $0[TextKey.self] = "root"
                        $0[UnhashedKey.self] = Unhashed(value: value)
                    }))
        }
        #expect(stamps.counts.overflows == 40 - EnvironmentStamps.bucketCapacity)
        #expect(Set(held.compactMap { $0.map(ObjectIdentifier.init) }).count == 40)
        stamps.endPass()
    }

    private struct Unhashed: Equatable, Sendable {
        let value: Int
    }

    private struct UnhashedKey: EnvironmentKey {
        static let defaultValue = Unhashed(value: 0)
    }
}
