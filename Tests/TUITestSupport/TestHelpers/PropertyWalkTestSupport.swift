//  🖥️ TUI — A Terminal UI framework for Swift
//  PropertyWalkTestSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import TUICore
@testable import TUIView

/// Prepares `value`'s properties as the render walk does before evaluating
/// its `body` at `identity`: each `@State` bound to what `storage` keeps,
/// each `@Environment` handed `environment`, each app property's `update()`
/// run and written back. Nothing for a type that holds no property.
@MainActor
func prepareForBody<V>(
    _ value: inout V, identity: ViewIdentity, storage: StateStorage,
    environment: EnvironmentValues = EnvironmentValues()
) {
    guard let plan = propertyPlan(for: V.self) else { return }
    prepareProperties(
        of: &value, plan: plan, identity: identity, storage: storage, environment: environment, isMeasuring: false)
}

#endif
