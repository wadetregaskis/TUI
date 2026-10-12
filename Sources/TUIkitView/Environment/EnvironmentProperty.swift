//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentProperty.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation
import TUIkitCore

// MARK: - Environment Property Wrapper

/// A property wrapper that reads a value from the environment.
///
/// Use `@Environment` to access environment values in your views.
/// The value is read dynamically during `body` evaluation, so it
/// always reflects the current environment (including any modifications
/// from parent views).
///
/// # KeyPath-Based Access
///
/// ```swift
/// struct MyView: View {
///     @Environment(\.palette) var palette
///     @Environment(\.isDisabled) var isDisabled
///
///     var body: some View {
///         Text("Hello")
///             .foregroundColor(palette.accent)
///     }
/// }
/// ```
///
/// # Type-Based Access (Observable Objects)
///
/// ```swift
/// @Observable
/// class AppModel {
///     var count = 0
///     init() {}
/// }
///
/// struct ContentView: View {
///     @Environment(AppModel.self) var model
///
///     var body: some View {
///         Text("Count: \(model.count)")
///     }
/// }
/// ```
///
/// # How It Works
///
/// The rendering pipeline resolves each view's environment *at render time*
/// (after any `.environment()` modifiers applied by parents) and stores it in a
/// reference box held by this wrapper — see the property walk (`PropertyWalk`),
/// which the renderer runs before evaluating a view's `body`. Because the box
/// is a reference shared with any closure that captures the view (a `Button`
/// action, an `.onKeyEvent` handler, a `Binding`'s `set:`), `@Environment`
/// resolves correctly **inside those closures too** — not only during `body` —
/// matching SwiftUI. (Reading the active environment lazily at access time, the
/// old behaviour, returned defaults in deferred closures.)
///
/// As a fallback, when no box has been populated (a view rendered before the
/// resolve pass, or read outside the render tree as in tests), it reads the
/// active render environment, and finally the framework defaults.
@propertyWrapper
public struct Environment<Value> {
    // How the value is looked up: by key path, or — for an observable object —
    // by its type, through ``EnvironmentValues/storedObject(ofType:)``. Exactly
    // one is set.
    //
    // Each is one pointer wide, deliberately. The observable lookup used to be a
    // `(EnvironmentValues) -> Value?` closure, which is two words and took the
    // whole wrapper to 32 bytes — past the 24-byte inline buffer of an
    // existential, which every view holding one paid a heap allocation for
    // when the property walk reflected it. Two optionals and the box are 24
    // bytes.
    //
    // Two optionals rather than an enum of the two, which is what this was:
    // the enum is generic (it is `Value`'s), so the per-pass memos' value hash
    // could not read it — a generic enum's inactive payload is not reliably
    // written — and every view holding an `@Environment` bypassed both memos.
    // An optional of one pointer (a key path's reference, a metatype) spells
    // `nil` in that pointer's spare values and writes it whole, so the hash
    // reads these, and the wrapper, as plain words.

    /// The key path to read, or `nil` for an observable lookup.
    private let keyPath: KeyPath<EnvironmentValues, Value>?

    /// The observable type to look up, or `nil` for a key-path lookup.
    private let observableType: Any.Type?

    /// Reference box holding the environment captured at the owning view's
    /// render. Shared with closures that capture the view, so they see the same
    /// resolved environment. Populated by the property walk (`PropertyWalk`).
    /// A `var` because a value drawn at a second place has its box replaced,
    /// in that place's copy, by one of its own.
    private var box = EnvironmentBox()

    /// Creates an environment property wrapper for the given key path.
    ///
    /// - Parameter keyPath: The key path to the environment value to read.
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
        self.observableType = nil
    }

    /// Creates an environment property wrapper that reads an observable
    /// object by its type.
    ///
    /// The object must have been injected via `.environment(model)`.
    ///
    /// ```swift
    /// @Environment(AppModel.self) var model
    /// ```
    ///
    /// - Parameter type: The observable type to look up.
    public init(_ type: Value.Type) where Value: Observable {
        self.keyPath = nil
        self.observableType = type
    }

    /// The current environment value.
    ///
    /// Prefers the environment captured into `box` at the owning view's render
    /// (valid inside closures); falls back to the active render environment, then
    /// the framework defaults.
    public var wrappedValue: Value {
        let env = box.environment ?? StateRegistration.activeEnvironment ?? EnvironmentValues()
        if let keyPath { return env[keyPath: keyPath] }
        guard let type = observableType, let object = env.storedObject(ofType: type) as? Value else {
            fatalError(
                "@Environment(\(Value.self).self): "
                    + "No object of type \(Value.self) found in the environment. "
                    + "Did you forget to call .environment(model)?"
            )
        }
        return object
    }
}

// MARK: - Render-time resolution

/// A reference box holding the environment a view's ``Environment`` wrapper was
/// resolved against. Reference semantics are the whole point: a `@Environment`
/// wrapper copied into a closure shares this box, so the closure reads the value
/// captured at render even though it runs later.
final class EnvironmentBox {
    var environment: EnvironmentValues?
    /// The identity of the view the box was resolved for, by the property
    /// walk; `nil` until then.
    var place: ViewIdentity?
}

/// An `@Environment` the property walk resolves for the place its view is
/// drawn at: one value drawn at two places gets a box for each, so a closure
/// made in the first place's body reads the first place's environment, as
/// SwiftUI resolves each place's copy (the `@State` twin of this is DYNV bug
/// 1; ``State/bindState(at:to:key:)``).
///
/// A box resolved for a place that is not drawn in the pass that finds it at
/// another — a value kept across frames, moved — is unplaced at the pass's
/// end (``StateStorage/noteDisplacedEnvironment(_:from:)``), so the next body
/// resolves it where it lies, rather than in a box of its own every body.
protocol PlaceResolvedEnvironment {
    /// Hands the wrapper at `address`, in the copy of a view drawn at
    /// `place`, `environment`; a box resolved for another place is told to
    /// `storage`.
    ///
    /// - Returns: Whether the wrapper at `address` was changed — given a box
    ///   of its own — rather than its shared box resolved.
    static func resolveEnvironment(
        at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues, place: ViewIdentity,
        storage: StateStorage?) -> Bool
}

extension Environment: PlaceResolvedEnvironment {
    static func resolveEnvironment(
        at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues, place: ViewIdentity,
        storage: StateStorage?
    ) -> Bool {
        let wrapper = address.assumingMemoryBound(to: Self.self)
        let box = wrapper.pointee.box
        // An identity compare: it stops at the first node the two identities
        // share, so it walks the whole chain only for a kept value's, whose
        // nodes are another frame's.
        if let resolved = box.place, resolved != place {
            // Resolved for another place in this or an earlier pass: this
            // place's copy gets a box of its own, and if that place is not
            // drawn in this pass, the box is unplaced at its end.
            let own = EnvironmentBox()
            own.environment = environment
            own.place = place
            wrapper.pointee.box = own
            storage?.noteDisplacedEnvironment(box, from: resolved)
            return true
        }
        box.environment = environment
        box.place = place
        return false
    }
}

/// A `@Environment` wrapper that can be handed its resolved environment.
///
/// Existential over the wrapper's `Value` so the renderer can populate every
/// `@Environment` on a view without knowing each one's type.
public protocol EnvironmentResolvable {
    /// Hands this property wrapper the environment to read from.
    ///
    /// Called by the renderer on every `@Environment` it finds on a view,
    /// immediately before the view's `body` runs, so a wrapper answers from
    /// the values in force at *its* position in the tree. Outside a render
    /// pass a wrapper has no environment and reads its default — which is why
    /// an event closure must capture what it needs at render time rather than
    /// reaching for `@Environment` when the event arrives.
    ///
    /// - Parameter environment: The values in force where the view sits.
    func resolveEnvironment(_ environment: EnvironmentValues)
}

extension Environment: EnvironmentResolvable {
    public func resolveEnvironment(_ environment: EnvironmentValues) {
        box.environment = environment
    }
}

/// A framework view that hands its own `@Environment` properties their
/// environment, which the property walk then leaves to it.
///
/// The walk reflected the view with `Mirror` on every `body` when this was
/// written — boxing each stored property into `Any`, a copy of the content a
/// style host wraps among them — and cast each one. A style host around a
/// common control (a `ProgressView`'s, a `Label`'s) paid that on every
/// measure and render: on a dashboard of progress bars, measured cold, the
/// walk was 12% of the frame. The walk now plans each type's fields once
/// (`PropertyPlans`), so listing them saves little.
///
/// A debug build checks each conforming type the first time it renders: every
/// `@Environment` of the view's own must have been resolved, so a property
/// added without being listed fails the first test that draws it.
@MainActor
package protocol ResolvesOwnEnvironment {
    /// Resolves every `@Environment` property of this view against
    /// `environment` — `_name.resolveEnvironment(environment)` for each.
    func resolveOwnEnvironment(_ environment: EnvironmentValues)
}

extension Environment {
    /// Whether this wrapper has been handed an environment: what a debug build
    /// checks of a ``ResolvesOwnEnvironment`` view.
    var isResolved: Bool { box.environment != nil }
}

/// Reads ``Environment/isResolved`` of the wrapper at an address, for a debug
/// build's check of a ``ResolvesOwnEnvironment`` view.
protocol ResolutionInspectable {
    var isResolved: Bool { get }
}

extension Environment: ResolutionInspectable {}
