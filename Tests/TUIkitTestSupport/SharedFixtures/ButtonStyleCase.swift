//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonStyleCase.swift
//
//  Cut from ButtonMeasureParityTests.swift: ProbeMeasureMemoTests iterates it too.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import TUIkitFoundation

/// The built-in styles, as a value a test can iterate.
enum ButtonStyleCase: CustomStringConvertible {
    case `default`, primary, success, destructive, plain

    var description: String {
        switch self {
        case .default: "default"
        case .primary: "primary"
        case .success: "success"
        case .destructive: "destructive"
        case .plain: "plain"
        }
    }

    @MainActor
    func apply(to button: Button) -> AnyView {
        switch self {
        case .default: AnyView(button.buttonStyle(.automatic))
        case .primary: AnyView(button.buttonStyle(.borderedProminent))
        case .success: AnyView(button.buttonStyle(.success))
        case .destructive: AnyView(button.buttonStyle(.destructive))
        case .plain: AnyView(button.buttonStyle(.plain))
        }
    }
}

#endif
