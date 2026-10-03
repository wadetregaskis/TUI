//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationPathCodableTests.swift
//
//  Saving and restoring a navigation path: `codable`, its representation's
//  `Codable` conformance, and `init(_:)` back from it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Internal, not private: a value is restored by its type's name, and a
/// private type's name carries a per-file discriminator the lookup cannot
/// resolve (see `NavigationPath.CodableRepresentation`).
struct PathCodableRecipe: Codable, Hashable {
    let name: String
}

enum PathCodableIngredient: String, Codable, Hashable {
    case flour, water
}

/// Hashable but not Codable: a path holding one cannot be saved.
private struct Ephemeral: Hashable {
    let id: Int
}

@Suite("NavigationPath saving and restoring")
struct NavigationPathCodableTests {

    private func roundTrip(_ path: NavigationPath) throws -> NavigationPath {
        let codable = try #require(path.codable)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(NavigationPath.CodableRepresentation.self, from: data)
        return NavigationPath(decoded)
    }

    @Test("A path of Codable values of several types restores to itself")
    func mixedTypesRoundTrip() throws {
        var path = NavigationPath()
        path.append(PathCodableRecipe(name: "bread"))
        path.append(PathCodableIngredient.flour)
        path.append(42)
        let restored = try roundTrip(path)
        #expect(restored == path)
        #expect(restored.elements.map { $0.base is PathCodableRecipe } == [true, false, false])
    }

    @Test("An empty path restores to an empty path")
    func emptyRoundTrip() throws {
        #expect(try roundTrip(NavigationPath()).isEmpty)
    }

    @Test("A path holding a value that is not Codable has no representation")
    func nonCodableHasNone() {
        var path = NavigationPath([PathCodableRecipe(name: "bread")])
        #expect(path.codable != nil)
        path.append(Ephemeral(id: 1))
        #expect(path.codable == nil)
    }

    @Test("Equal paths have equal representations")
    func representationsCompare() {
        let first = NavigationPath([PathCodableRecipe(name: "a"), PathCodableRecipe(name: "b")])
        let second = NavigationPath([PathCodableRecipe(name: "a"), PathCodableRecipe(name: "b")])
        let other = NavigationPath([PathCodableRecipe(name: "a")])
        #expect(first.codable == second.codable)
        #expect(first.codable != other.codable)
    }

    @Test("A type name this process does not know fails to decode, rather than dropping a screen")
    func unknownTypeThrows() throws {
        let data = Data(#"["NoSuchModule.NoSuchType", "{}"]"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NavigationPath.CodableRepresentation.self, from: data)
        }
    }
}
