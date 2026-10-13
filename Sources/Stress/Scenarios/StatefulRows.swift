//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatefulRows.swift
//
//  Composite rows that each hold property wrappers, redrawn every frame, so
//  every row's body runs and pays the property walk (one lookup of the type's
//  plan, then, for a type holding a property, a copy of the row and one step
//  per planned field, `PropertyPlans`) and, for an app property, its
//  `update()` and write-back. The variants differ only in what each row
//  holds, so an A/B of two TUIkit builds on one variant prices that kind of
//  field (session notes DYNV/notes.md).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUIkit

enum StatefulRowsScenario {
    @MainActor
    static let descriptor = Scenario(
        // A literal: StressLocalizationParityTests reads the id from the source.
        id: "stateful",
        title: "Stateful Rows",
        blurb: "Composite rows that each hold property wrappers, redrawn every frame, so every row's body runs.",
        stresses: "per-body property walks (Mirror, casts, binding, environment resolution) · app DynamicProperty write-back · per-type negative caches",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(StatefulRowsView(config: config, kind: .stateAndEnvironment))
        },
        drive: { config in ScenarioVariants.resolve(config, in: scenarioID)?.drive?(config) }
    )

    /// The registry's key: the descriptor's own id, so the two cannot drift.
    @MainActor
    static var scenarioID: String { descriptor.id }

    private static func variant(
        _ id: String, _ summary: String, _ kind: StatefulRowKind
    ) -> ScenarioVariant {
        ScenarioVariant(id: id, summary: summary, axis: "row fields", make: { config in
            AnyView(StatefulRowsView(config: config, kind: kind))
        })
    }

    @MainActor
    static let variants: [ScenarioVariant] = [
        variant("state-env", "each row holds one @State and one @Environment", .stateAndEnvironment),
        variant("plain", "each row holds no property wrapper: its type is planned as holding nothing", .plain),
        variant("app-property", "each row also holds an app DynamicProperty struct with a @State: copy and write-back per body", .appProperty),
        variant("optional-property", "each row holds an optional app property, present on even rows: a nil check every body", .optionalProperty),
        variant("existential", "each row holds its app property as `any DynamicProperty`: its dynamic type read every body", .existential),
        variant("enum-rows", "each row is an enum view with no property anywhere: its case read every body (B-DYNP-2)", .enumRow),
        ScenarioVariant(
            id: "shared-objects",
            summary: "memoised rows of 50 long-lived class properties, each holding a @State and an @Environment, beside a "
                + "detail view of the selected one under another environment; a write lands in the selected item and in "
                + "one row's each frame, and the selection moves every 8 ticks",
            axis: "class properties", make: { SharedObjectsView.driven(config: $0).view },
            drive: { SharedObjectsView.driven(config: $0) }),
        ScenarioVariant(
            id: "identity-churn", summary: "500 rows whose identities are new every frame (`RowModel(id: UUID())`), each "
                + "showing a long-lived class property holding a @State: a new holder of each object, per row, per frame",
            axis: "class properties", make: { AnyView(IdentityChurnView(config: $0)) }),
    ]
}

/// What each row of a variant holds.
enum StatefulRowKind: Sendable {
    case plain, stateAndEnvironment, appProperty, optionalProperty, existential, enumRow
}

private struct StatefulRowsAccent: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    fileprivate var statefulRowsAccent: Int {
        get { self[StatefulRowsAccent.self] }
        set { self[StatefulRowsAccent.self] = newValue }
    }
}

private struct StatefulRowsView: View {
    let config: StressConfig
    let kind: StatefulRowKind
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(50)
        // Passed to every row, so every row's value differs every frame and
        // no row is served from a memo: each body runs.
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.stateful.heading", String(describing: kind), count)).bold()
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    row(index: index, tick: tick)
                }
            }
            .environment(\.statefulRowsAccent, tick % 7)
        }
    }

    @ViewBuilder
    private func row(index: Int, tick: Int) -> some View {
        switch kind {
        case .plain:
            PlainRow(seed: config.seed, index: index, tick: tick)
        case .stateAndEnvironment:
            StateEnvironmentRow(seed: config.seed, index: index, tick: tick)
        case .appProperty:
            AppPropertyRow(seed: config.seed, index: index, tick: tick)
        case .optionalProperty:
            OptionalPropertyRow(
                seed: config.seed, index: index, tick: tick,
                stamp: index.isMultiple(of: 2) ? RowStamp() : nil)
        case .existential:
            ExistentialRow(seed: config.seed, index: index, tick: tick, stamp: WideRowStamp())
        case .enumRow:
            if index.isMultiple(of: 2) {
                EnumRow.even(seed: config.seed, index: index, tick: tick)
            } else {
                EnumRow.odd(seed: config.seed, index: index, tick: tick)
            }
        }
    }
}

/// What every row draws: its index, a word, and the tick.
@MainActor
private func rowText(_ seed: UInt64, _ index: Int, _ tick: Int, _ extra: Int) -> some View {
    HStack {
        Text(verbatim: "#\(index)").foregroundStyle(.secondary)
        Text(verbatim: Synth.slug(mix(seed, index)))
        Spacer()
        Text(verbatim: "\(tick) \(extra)")
    }
}

private struct PlainRow: View {
    let seed: UInt64
    let index: Int
    let tick: Int

    var body: some View {
        rowText(seed, index, tick, 0)
    }
}

private struct StateEnvironmentRow: View {
    let seed: UInt64
    let index: Int
    let tick: Int
    @State private var taps = 0
    @Environment(\.statefulRowsAccent) private var accent

    var body: some View {
        rowText(seed, index, tick, taps + accent)
    }
}

/// An app property: a `@State` of its own, and an `update()` that changes a
/// stored value, so the holding row is copied and written back every body.
private struct RowStamp: DynamicProperty {
    @State private var seen = 0
    var updates = 0

    mutating func update() {
        updates &+= 1
    }

    var value: Int { seen &+ updates }
}

private struct AppPropertyRow: View {
    let seed: UInt64
    let index: Int
    let tick: Int
    @State private var taps = 0
    @Environment(\.statefulRowsAccent) private var accent
    var stamp = RowStamp()

    var body: some View {
        rowText(seed, index, tick, taps + accent + stamp.value)
    }
}

private struct OptionalPropertyRow: View {
    let seed: UInt64
    let index: Int
    let tick: Int
    @State private var taps = 0
    @Environment(\.statefulRowsAccent) private var accent
    var stamp: RowStamp?

    var body: some View {
        rowText(seed, index, tick, taps + accent + (stamp?.value ?? 0))
    }
}

/// `RowStamp` with room beside it: too big for an existential's three-word
/// inline buffer, so the existential row prices the boxed path — the value
/// copied out of its box each body and, since `update()` changes it, put in a
/// box anew.
private struct WideRowStamp: DynamicProperty {
    var stamp = RowStamp()
    var padding = (0, 0)
}

private struct ExistentialRow: View {
    let seed: UInt64
    let index: Int
    let tick: Int
    @State private var taps = 0
    @Environment(\.statefulRowsAccent) private var accent
    var stamp: any DynamicProperty

    var body: some View {
        rowText(seed, index, tick, taps + accent + ((stamp as? WideRowStamp)?.stamp.value ?? 0))
    }
}

/// An enum view with no property anywhere.
private enum EnumRow: View {
    case even(seed: UInt64, index: Int, tick: Int)
    case odd(seed: UInt64, index: Int, tick: Int)

    var body: some View {
        switch self {
        case .even(let seed, let index, let tick): rowText(seed, index, tick, 0)
        case .odd(let seed, let index, let tick): rowText(seed, index, tick, 1)
        }
    }
}

// MARK: - Class properties held by several views

/// A long-lived item that rows and a detail view both show: one object, held
/// in a property field by every view that shows it, holding a `@State` and an
/// `@Environment` — what the property walk installs inside a class property,
/// which SwiftUI does not (decisions-DYNVFIX B-DYNVFIX-3).
private final class SharedItem: DynamicProperty {
    @State var hits = 0
    @Environment(\.statefulRowsAccent) var accent
}

/// Which item the detail view shows: written between frames.
@Observable
@MainActor
private final class SharedSelection {
    var index = 0
}

/// Rows of long-lived items, memoised while their item is not written, beside
/// a detail view of the selected one under another environment: what the
/// views holding one object cost when its `@State` is written — every holder
/// redrawn, a memo-served row included — and when the detail view moves to
/// another object.
private struct SharedObjectsView: View {
    let items: [SharedItem]
    let selection: SharedSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.stateful.heading", "shared-objects", items.count)).bold()
            Divider()
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<items.count, id: \.self) { index in
                        SharedItemRow(index: index, item: items[index])
                    }
                }
                .environment(\.statefulRowsAccent, 1)
                SharedItemDetail(item: items[selection.index])
                    .environment(\.statefulRowsAccent, 2)
            }
        }
    }

    /// `config.sized(50)` items, and the advance that writes the selected
    /// item's state and one row's each frame and moves the selection every 8
    /// ticks.
    static func driven(config: StressConfig) -> DrivenScenario {
        let items = (0..<config.sized(50)).map { _ in SharedItem() }
        let selection = SharedSelection()
        return DrivenScenario(view: AnyView(Self(items: items, selection: selection))) { tick in
            if tick.isMultiple(of: 8) { selection.index = (selection.index + 1) % items.count }
            items[selection.index].hits &+= 1
            items[Int(mix(config.seed, tick) % UInt64(items.count))].hits &+= 1
        }
    }
}

/// A row showing an item: equal while it shows the same item, so it is served
/// from the memo until the item's state is written.
private struct SharedItemRow: View, Equatable {
    let index: Int
    let item: SharedItem
    /// The item's identity, what the row is compared by: the item itself is
    /// not `Sendable`, so a comparison off the main actor cannot read it.
    private let itemID: ObjectIdentifier

    init(index: Int, item: SharedItem) {
        self.index = index
        self.item = item
        itemID = ObjectIdentifier(item)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.itemID == rhs.itemID
    }

    var body: some View {
        HStack {
            Text(verbatim: "#\(index)").foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: "\(item.hits) \(item.accent)")
        }
    }
}

/// The selected item, drawn every time its view is.
private struct SharedItemDetail: View {
    let item: SharedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "hits \(item.hits)").bold()
            Text(verbatim: "accent \(item.accent)")
        }
    }
}

/// A row's model, made anew every frame with a new identity.
private struct ChurnedRowModel: Identifiable {
    let id: UUID
    let item: SharedItem
}

/// Rows whose identities are new every frame, each showing a long-lived item
/// holding a `@State`: every row is a new holder of its object in every
/// pass, and the old one leaves.
private struct IdentityChurnView: View {
    let items: [SharedItem]
    @Environment(StressClock.self) private var clock

    init(config: StressConfig) {
        items = (0..<config.sized(500)).map { _ in SharedItem() }
    }

    var body: some View {
        // Read, so a tick draws the rows again, each under a new identity.
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.stateful.heading", "identity-churn", items.count)).bold()
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items.map { ChurnedRowModel(id: UUID(), item: $0) }) { model in
                    ChurnedRow(tick: tick, item: model.item)
                }
            }
        }
    }
}

/// A row holding its item in a property field.
private struct ChurnedRow: View {
    let tick: Int
    let item: SharedItem

    var body: some View {
        Text(verbatim: "\(tick) \(item.hits)")
    }
}
