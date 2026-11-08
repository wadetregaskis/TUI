//  🖥️ TUI — A Terminal UI framework for Swift
//  BodyChangeReport.swift
//
//  What `_printChanges()` and `_logChanges()` report, and how: the call in a
//  body leaves a request, and the walk that evaluated the body settles it,
//  comparing what the body was evaluated with against what it was last time.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(os)
import os
#endif
import TUICore

/// Says why a body that called `_printChanges()` or `_logChanges()` was
/// evaluated.
///
/// **The handoff.** The call is a static function with nothing to hand it the
/// view, its place or the storage, so it only leaves a request naming its type
/// (``request(_:logs:)``). The walk that evaluated the body looks for one
/// straight after (``noteBodyEvaluated(_:context:)``) and, finding one, has
/// all three. A body evaluates no other body inside it, so the next look after
/// the call is that body's own. A request made anywhere else — outside a body,
/// or in a body the walk evaluated without looking, as an alignment query does
/// — is dropped at the next look, its type not matching.
///
/// **Why a static.** The request has to cross from the call to the walk with
/// nothing between them to carry it, as `@Environment`'s fallback crosses on a
/// task local. A task local costs a scope per body evaluated, called or not;
/// this costs one load and a branch never taken. It is not state any app or
/// test can see: it is set and emptied inside one synchronous evaluation on
/// the main actor, so no other evaluation, test or app ever finds it set. What
/// the reports compare against is per app, in its `StateStorage`.
///
/// **What it compares.** At the view's identity, under
/// ``StateStorage/StateKey/bodyChangeRecordIndex``, the storage keeps the value
/// the last report saw, each `@State` box's write count then and what each
/// `@Environment` property read (``BodyChangeRecord``). No record: `@self,
/// @identity` and every `@State`. Otherwise:
///
/// - `@self` when the value compares unequal by the render memo's
///   field-by-field comparison (``ValueComparison``);
/// - each `@State` written since, by its name (`_count`);
/// - each `@Environment` property whose value moved, by its name
///   (`_colorScheme`), as a `@State` is named;
/// - `@dependencies` when an `@Observable` property the body read was
///   written: the observation that redraws the body says so to the cache's
///   link (``RenderCache/Link/takeObservedChange(forReportAt:)``). Which
///   property, and of which object, it can't say: Observation's change
///   handler is told neither.
///
/// **Never a false `unchanged.`** What can't be compared — a closure or a
/// `Binding` in the value, which may read changed state; an environment value
/// that is neither `Equatable` nor an object; a `@State` that can't be found;
/// a render with no cache to ask — is named as what "may have changed", and
/// only when nothing certainly did. `unchanged.` is said only when everything
/// was compared and nothing moved.
///
/// **SwiftUI's words.** `@self`, `@identity`, a property's own name and
/// `unchanged.` are SwiftUI's. `@dependencies` is the token SwiftUI is
/// widely reported to print for a body redrawn by an `@Observable` write, and
/// the string is in macOS 15's dyld shared cache (searched 2026-11-08), but in
/// a region not tied to a library there: NOT verified against a SwiftUI run,
/// so if SwiftUI turns out to word it otherwise, follow SwiftUI. "may have
/// changed" is TUI's own: SwiftUI has no words for a cause it could not
/// compare.
@MainActor
package enum BodyChangeReport {
    /// A call waiting for the walk.
    struct Request {
        /// The type whose `_printChanges()` or `_logChanges()` was called.
        let type: Any.Type
        /// Whether it was `_logChanges()`.
        let logs: Bool
    }

    /// The call made since the walk last looked, if any.
    private static var pending: Request?

    /// Notes a call of `type`'s `_printChanges()` (or `_logChanges()`, if
    /// `logs`), for the walk to settle once the body returns.
    static func request(_ type: Any.Type, logs: Bool) {
        pending = Request(type: type, logs: logs)
    }

    /// Settles a request made while `view`'s body was evaluated at `context`,
    /// if there is one. Called by the walk straight after every composite body
    /// it evaluates; one load and a branch when nothing called.
    @inline(__always)
    package static func noteBodyEvaluated<V: View>(_ view: V, context: RenderContext) {
        if _slowPath(pending != nil) { settle(view, context: context) }
    }

    @inline(never)
    private static func settle<V: View>(_ view: V, context: RenderContext) {
        guard let request = pending else { return }
        pending = nil
        if ObjectIdentifier(request.type) == ObjectIdentifier(V.self) {
            let states = propertyPlan(for: V.self).map { ownStates(of: V.self, plan: $0, at: context.identity) } ?? []
            report(on: view, states: states, request: request, context: context)
        } else if let holder = view as? any AppliedModifierHolder,
            ObjectIdentifier(type(of: holder).appliedModifierType) == ObjectIdentifier(request.type)
        {
            holder.reportOnAppliedModifier(request, context: context)
        }
    }

    /// Reports on `subject`, the view or the modifier whose body was evaluated
    /// at `context`, whose `@State` lies under `states` (`nil` where that can't
    /// be told).
    static func report<Subject>(
        on subject: Subject, states: [(name: String, key: StateStorage.StateKey)]?, request: Request,
        context: RenderContext
    ) {
        guard let storage = context.stateStorage else { return }
        let recordKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateStorage.StateKey.bodyChangeRecordIndex)
        let last = storage.values[recordKey] as? BodyChangeRecord
        // A body measured and then drawn in one pass is reported once.
        if let last, last.pass == storage.currentPass { return }
        let counts = (states ?? []).map { (storage.values[$0.key] as? any WriteCountingBox)?.writeCount }
        let environment = environmentReadings(of: subject, in: context.environment)
        // Asked whatever the record says, so the link starts remembering at the
        // first report and forgets what came before each.
        let observed = context.renderCache?.link.takeObservedChange(forReportAt: context.identity)
        var causes = Causes()
        if let last {
            causes.note(selfChange(from: (last.value as? KeptValue<Subject>)?.value, to: subject, context: context), "@self")
            if let states {
                for (index, state) in states.enumerated() where last.counts[state.key] != counts[index] {
                    causes.note(.changed, state.name)
                }
            } else {
                causes.note(.unknown, "a @State property")
            }
            for reading in environment {
                causes.note(change(from: last.readings[reading.name], to: reading.value), reading.name)
            }
            causes.note(observed.map { $0 ? .changed : .same } ?? .unknown, "@dependencies")
        } else {
            causes.certain = ["@self", "@identity"] + (states ?? []).map(\.name)
        }
        var keptCounts: [StateStorage.StateKey: UInt32?] = [:]
        for (index, state) in (states ?? []).enumerated() { keptCounts.updateValue(counts[index], forKey: state.key) }
        storage.values[recordKey] = BodyChangeRecord(
            pass: storage.currentPass, value: KeptValue(subject), counts: keptCounts,
            readings: Dictionary(environment.map { ($0.name, Reading($0.value)) }, uniquingKeysWith: { $1 }))
        emit(line(for: Subject.self, causes: causes.certain, unknown: causes.unknown), logs: request.logs, storage: storage)
    }

    /// What a report found: what certainly changed, and what may have.
    struct Causes {
        /// What compared unequal.
        var certain: [String] = []
        /// What couldn't be compared.
        var unknown: [String] = []

        /// Notes `name` by how it compared.
        mutating func note(_ change: Change, _ name: String) {
            switch change {
            case .changed: certain.append(name)
            case .unknown: unknown.append(name)
            case .same: break
            }
        }
    }

    /// The line reported for `type`: what certainly changed, or, where nothing
    /// did, what may have and couldn't be compared, or else `unchanged.`
    static func line(for type: Any.Type, causes: [String], unknown: [String]) -> String {
        let name = String(describing: type)
        if !causes.isEmpty { return "\(name): \(causes.joined(separator: ", ")) changed." }
        if !unknown.isEmpty { return "\(name): \(unknown.joined(separator: ", ")) may have changed." }
        return "\(name): unchanged."
    }

    /// The `@State` among `type`'s own fields, planned by `plan`, each with
    /// the key its box is kept under at `identity`: as the property walk keys
    /// them (``PropertyWalk``), the view's own counted in declaration order.
    /// `nil` when a field may hold one only some of the time (an optional or
    /// an existential), which moves the count, so that no name can be trusted.
    static func ownStates(
        of type: Any.Type, plan: SlotPlan, at identity: ViewIdentity
    ) -> [(name: String, key: StateStorage.StateKey)]? {
        guard case .fields(let fields) = plan.action else { return nil }
        let names = RuntimeFields.fields(of: type)
        var states: [(name: String, key: StateStorage.StateKey)] = []
        var ownIndex = 0
        for step in fields.steps where step.reference == nil {
            switch step.slot.action {
            case .leaf(let leaf) where leaf.isIndexed:
                defer { ownIndex += 1 }
                guard leaf.state != nil, step.position < names.count else { continue }
                states.append(
                    (names[step.position].name, StateStorage.StateKey(identity: identity, propertyIndex: ownIndex)))
            case .optional, .existential:
                if step.slot.mayInstall { return nil }
            default:
                continue
            }
        }
        return states
    }

    /// The `@State` among the fields of a modifier, planned by `fields`, that a
    /// view at `identity` applies from its field at `position`: keyed in that
    /// field's scope by position, as the walk keys a nested property.
    static func modifierStates(
        _ fields: FieldsPlan, atPosition position: Int, of identity: ViewIdentity
    ) -> [(name: String, key: StateStorage.StateKey)] {
        let scope = NestedScope.container(at: position, ofType: fields.type, in: NestedScope.view)
        let names = RuntimeFields.fields(of: fields.type)
        return fields.steps.compactMap { step in
            guard step.reference == nil, case .leaf(let leaf) = step.slot.action, leaf.state != nil,
                step.position < names.count
            else { return nil }
            return (
                names[step.position].name,
                StateStorage.StateKey(identity: identity, propertyIndex: step.position, scope: scope)
            )
        }
    }

    /// How `new` compares with `old`, field by field as the render memo
    /// compares views: changed where a field compares unequal; unknown where
    /// the type can't be compared, or where the only difference may be a
    /// closure or a `Binding` (equal leniently, unequal strictly), which can
    /// read state that changed; the same otherwise.
    private static func selfChange<Subject>(from old: Subject?, to new: Subject, context: RenderContext) -> Change {
        guard let old, let plans = context.renderCache?.valueHashPlans,
            let comparison = plans.comparison(for: Subject.self)
        else { return .unknown }
        return withUnsafePointer(to: old) { old in
            withUnsafePointer(to: new) { new in
                if unsafe !comparison.equal(old, new, strict: false, plans: plans) { return .changed }
                return unsafe comparison.equal(old, new, strict: true, plans: plans) ? .same : .unknown
            }
        }
    }

    /// Sends `line` where it goes: the storage's sink, if a test set one;
    /// otherwise, for `_logChanges()`, the unified log where there is one, and
    /// for the rest the channel framework diagnostics share (``SoftTrapLog``).
    private static func emit(_ line: String, logs: Bool, storage: StateStorage) {
        if let sink = storage.bodyChangeSink {
            sink(line)
            return
        }
        #if canImport(os)
            if logs {
                Logger(subsystem: "TUI", category: "Changed Body Properties").log("\(line, privacy: .public)")
                return
            }
        #endif
        SoftTrap.log.writeEachTime(line + "\n")
    }
}

/// What `_printChanges()` last reported on at a view's identity
/// (``BodyChangeReport``).
final class BodyChangeRecord {
    /// The render pass it was made in.
    let pass: UInt32
    /// The view's value, or the modifier's, as a ``KeptValue``.
    let value: AnyObject
    /// Each `@State` box's write count, by its key; `nil` for a box not yet made.
    let counts: [StateStorage.StateKey: UInt32?]
    /// What each `@Environment` property read, by its name.
    let readings: [String: BodyChangeReport.Reading]

    init(
        pass: UInt32, value: AnyObject, counts: [StateStorage.StateKey: UInt32?],
        readings: [String: BodyChangeReport.Reading]
    ) {
        self.pass = pass
        self.value = value
        self.counts = counts
        self.readings = readings
    }
}

/// A value kept by reference, so a record can hold one of any type.
final class KeptValue<Value> {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
