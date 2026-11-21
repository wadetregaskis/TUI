//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumnIdentityTests.swift
//
//  What a table keeps from one frame to the next must name the column it is
//  for, not its position: the row memo's frame key the columns' key paths, a
//  view cell's identity and a `.fit` record the column's place in the column
//  closure. Keyed by position, a reorder or a swapped key path left every kept
//  row drawing the old cells under the new headers, and a condition before a
//  column handed its cells' `@State` and its `.fit` record to its neighbour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUITables
import TUITesting
@testable import TUITestSupport

@Observable
@MainActor
private final class Model {
    var customization = TableColumnCustomization<Person>()
    /// Whether the first column shows the given name or the family name.
    var givenFirst = true
    /// Whether the conditional column before the others is built.
    var showLead = true
}

private struct Person: Identifiable, Equatable {
    let id: Int
    var given: String { "g\(id)" }
    var family: String { "f\(id)" }
    var lead: String { "k" }
    /// Short, but one row's is long: off screen in a table nine lines high.
    var name: String { id == 150 ? "nnnnnnnnnnnnnnnnnnnnnnnnnn" : "n\(id)" }
    var tail: String { "t" }
}

/// Mints a number for each new `@State`, so a cell shows which one it holds.
@MainActor
private final class Minter {
    private var next = 0

    func mint() -> Int {
        next += 1
        return next
    }
}

/// A view cell with state of its own: the number it was given when it was made.
private struct Stamp: View {
    let label: String
    @State private var number: Int

    init(label: String, minter: Minter) {
        self.label = label
        _number = State(initialValue: minter.mint())
    }

    var body: some View { Text(verbatim: "\(label)\(number)") }
}

private enum Page {
    case reorder, swappedKeyPath, fit, viewCells
}

private struct PeopleApp: App {
    let model: Model?
    let page: Page
    let minter: Minter

    init() {
        model = nil
        page = .reorder
        minter = Minter()
    }

    init(_ model: Model, page: Page, minter: Minter) {
        self.model = model
        self.page = page
        self.minter = minter
    }

    var body: some Scene {
        WindowGroup {
            Group { if let model { PeoplePage(model: model, page: page, minter: minter) } }
        }
    }
}

private struct PeoplePage: View {
    let model: Model
    let page: Page
    let minter: Minter
    private let few = (1...5).map(Person.init)
    private let many = (1...300).map(Person.init)

    /// The key paths the two columns of the swapped page show, by the model.
    private var firstKey: KeyPath<Person, String> { model.givenFirst ? \.given : \.family }
    private var secondKey: KeyPath<Person, String> { model.givenFirst ? \.family : \.given }

    var body: some View {
        switch page {
        case .reorder:
            Table(few, columnCustomization: Bindable(model).customization) {
                TableColumn("Given", value: \.given).customizationID("given")
                TableColumn("Family", value: \.family).customizationID("family")
            }
            .frame(height: 9)
        case .swappedKeyPath:
            Table(few) {
                TableColumn("Name", value: firstKey)
                TableColumn("Other", value: secondKey)
            }
            .frame(height: 9)
        case .fit:
            Table(many) {
                if model.showLead {
                    TableColumn("L", value: \.lead).width(.fit)
                }
                TableColumn("Name", value: \.name).width(.fit)
                TableColumn("Tail", value: \.tail)
            }
            .frame(height: 9)
        case .viewCells:
            Table(few) {
                if model.showLead {
                    TableColumn("A") { (_: Person) in Stamp(label: "a", minter: minter) }
                }
                TableColumn("B") { (_: Person) in Stamp(label: "b", minter: minter) }
            }
            .frame(height: 9)
        }
    }
}

@MainActor
private final class Harness {
    let model = Model()
    let app: TestApp
    private var now: Int64 = 0

    init(_ page: Page) {
        app = TestApp(PeopleApp(model, page: page, minter: Minter()), width: 60, height: 14)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var lines: [String] { app.screen.lines }

    var screen: String { lines.joined(separator: "\n") }

    /// Where `text` starts on the line that holds `marker`, as a whole word.
    func column(of text: String, onLineWith marker: String) -> Int? {
        guard let line = lines.first(where: { $0.contains(marker) }), let range = line.range(of: text) else {
            return nil
        }
        return line.distance(from: line.startIndex, to: range.lowerBound)
    }

    /// The numbers the drawn ``Stamp``s labelled `label` show.
    func stamps(labelled label: String) -> Set<String> {
        let words = lines.flatMap { $0.split { !$0.isLetter && !$0.isNumber } }
        return Set(words.filter { $0.hasPrefix(label) && $0.dropFirst().allSatisfy(\.isNumber) && $0.count > 1 }
            .map(String.init))
    }
}

@MainActor
@Suite("A table keeps what it keeps by column, not by position")
struct TableColumnIdentityTests {
    @Test("Columns moved in the customization move every kept row's cells with their headers")
    func reorderedColumnsRedrawEveryRow() throws {
        let harness = Harness(.reorder)
        for id in 1...5 {
            let given = try #require(harness.column(of: "g\(id)", onLineWith: "g\(id)"), "\(harness.screen)")
            let family = try #require(harness.column(of: "f\(id)", onLineWith: "g\(id)"), "\(harness.screen)")
            #expect(given < family, "\(harness.screen)")
        }
        harness.model.customization.move("family", toPlaceOf: "given", declared: ["given", "family"])
        harness.frame()
        harness.frame()
        let header = try #require(harness.lines.first { $0.contains("Given") && $0.contains("Family") })
        #expect(header.range(of: "Family")!.lowerBound < header.range(of: "Given")!.lowerBound, "\(harness.screen)")
        for id in 1...5 {
            let given = try #require(harness.column(of: "g\(id)", onLineWith: "g\(id)"), "\(harness.screen)")
            let family = try #require(harness.column(of: "f\(id)", onLineWith: "g\(id)"), "\(harness.screen)")
            #expect(family < given, "row \(id) kept the old order:\n\(harness.screen)")
        }
    }

    @Test("A key path chosen by a condition redraws every kept row when the condition flips")
    func swappedKeyPathRedrawsEveryRow() throws {
        let harness = Harness(.swappedKeyPath)
        harness.model.givenFirst = false
        harness.frame()
        harness.frame()
        for id in 1...5 {
            let given = try #require(harness.column(of: "g\(id)", onLineWith: "f\(id)"), "\(harness.screen)")
            let family = try #require(harness.column(of: "f\(id)", onLineWith: "f\(id)"), "\(harness.screen)")
            #expect(family < given, "row \(id) kept the old key paths:\n\(harness.screen)")
        }
    }
}
