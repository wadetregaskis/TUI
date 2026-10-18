//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PrehashedVerdictsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// `PrehashedVerdicts` must answer what the `[Int: Bool]` it replaced
/// answers, through growth from empty and for the keys its storage treats
/// specially.
@Suite("Prehashed verdicts answer as a dictionary would")
struct PrehashedVerdictsTests {

    @Test("Random keys, stored and overwritten through growth from empty, read back as a dictionary's")
    func matchesDictionary() {
        var generator = SystemRandomNumberGenerator()
        for minimumCount in [0, 1, 37, 1_000] {
            var table = PrehashedVerdicts(minimumCount: minimumCount)
            var reference: [Int: Bool] = [:]
            // Keys from a small range as well as the whole one, so slots
            // collide and keys repeat.
            for step in 0..<3_000 {
                let key = step.isMultiple(of: 2) ? Int.random(in: -500...500, using: &generator) : Int.random(in: .min ... .max, using: &generator)
                // 0 shares 1's slot by design — `zeroKey` covers it.
                guard key != 0 else { continue }
                let verdict = Bool.random(using: &generator)
                table.set(verdict, for: key)
                reference[key] = verdict
            }
            for key in reference.keys { #expect(table[key] == reference[key]) }
            for _ in 0..<1_000 {
                let key = Int.random(in: .min ... .max, using: &generator)
                guard key != 0 else { continue }
                #expect(table[key] == reference[key])
            }
        }
    }

    @Test("An empty table answers nothing for any key, 0 included")
    func empty() {
        let table = PrehashedVerdicts()
        #expect(table[0] == nil)
        #expect(table[42] == nil)
        #expect(table[.min] == nil)
    }

    @Test("A key of 0 is stored, sharing 1's slot as the type says it does")
    func zeroKey() {
        var table = PrehashedVerdicts()
        table.set(true, for: 0)
        #expect(table[0] == true)
        #expect(table[1] == true, "0 is stored as 1")
        table.set(false, for: 1)
        #expect(table[0] == false)
    }
}
