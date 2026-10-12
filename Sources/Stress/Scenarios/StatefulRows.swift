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
        }
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
            ExistentialRow(seed: config.seed, index: index, tick: tick, stamp: RowStamp())
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

private struct ExistentialRow: View {
    let seed: UInt64
    let index: Int
    let tick: Int
    @State private var taps = 0
    @Environment(\.statefulRowsAccent) private var accent
    var stamp: any DynamicProperty

    var body: some View {
        rowText(seed, index, tick, taps + accent + ((stamp as? RowStamp)?.value ?? 0))
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
