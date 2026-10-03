//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DirectionsTests.swift
//
//  The one-axis edge and direction types, and `Axis`. Every number here was
//  read off a SwiftUI build (macOS 15.8, 2026-10-03): raw values, set bits and
//  the JSON a `Codable` value encodes to. They are pinned because a value
//  persisted under one framework has to read back under the other.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@Suite("Edges, directions and axes")
struct DirectionsTests {

    private func json<T: Encodable>(_ value: T) throws -> String? {
        String(bytes: try JSONEncoder().encode(value), encoding: .utf8)
    }

    @Test("Raw values are SwiftUI's")
    func rawValues() {
        #expect(HorizontalEdge.allCases.map(\.rawValue) == [0, 1])
        #expect(HorizontalDirection.allCases.map(\.rawValue) == [0, 1])
        #expect(VerticalDirection.allCases.map(\.rawValue) == [0, 1])
        #expect(VerticalEdge.allCases.map(\.rawValue) == [0, 1])
        #expect(Axis.allCases.map(\.rawValue) == [0, 1])
        #expect(Edge.trailing.rawValue == 3)
    }

    @Test("Each set holds one bit per member, and all is every member")
    func setBits() {
        #expect(HorizontalEdge.Set.leading.rawValue == 1)
        #expect(HorizontalEdge.Set.trailing.rawValue == 2)
        #expect(HorizontalDirection.Set.all.rawValue == 3)
        #expect(VerticalDirection.Set.up.rawValue == 1)
        #expect(VerticalDirection.Set.down.rawValue == 2)
        #expect(VerticalEdge.Set.all.rawValue == 3)
        #expect(Axis.Set.vertical.rawValue == 2)
    }

    @Test("A set made from one member is that member's static")
    func setFromMember() {
        #expect(HorizontalEdge.Set(.trailing) == .trailing)
        #expect(HorizontalDirection.Set(.leading) == .leading)
        #expect(VerticalDirection.Set(.down) == .down)
        #expect(VerticalEdge.Set(.bottom) == .bottom)
    }

    @Test("A value encodes as its raw value, and decodes back")
    func codable() throws {
        #expect(try json(HorizontalEdge.trailing) == "1")
        #expect(try json(VerticalDirection.down) == "1")
        #expect(try json(VerticalEdge.top) == "0")
        let decoded = try JSONDecoder().decode(HorizontalDirection.self, from: Data("1".utf8))
        #expect(decoded == .trailing)
    }

    @Test("An axis describes itself by name")
    func axisDescription() {
        #expect(String(describing: Axis.horizontal) == "horizontal")
        #expect(Axis.vertical.description == "vertical")
    }
}
