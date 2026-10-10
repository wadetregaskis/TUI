//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DeviceEnvironmentTests.swift
//
//  The device and display-setting environment values. Every expected default
//  is what SwiftUI reported on macOS 15.8 (2026-10-03), read off a SwiftUI
//  build: a scale of 1, regular size classes, a large type size, standard
//  contrast, left to right, no legibility weight.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Draws one environment value, so a test can read what a subtree sees.
private struct Reads<Value>: View {
    let keyPath: KeyPath<EnvironmentValues, Value>
    @Environment(\.self) private var environment

    var body: some View {
        Text(verbatim: String(describing: environment[keyPath: keyPath]))
    }
}

@MainActor
@Suite("Device and display environment values")
struct DeviceEnvironmentTests {

    private func shown<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 80, height: 1))
            .lines.first?.stripped.trimmingCharacters(in: .whitespaces) ?? ""
    }

    @Test("The defaults are macOS's")
    func defaults() {
        let environment = EnvironmentValues()
        #expect(environment.colorSchemeContrast == .standard)
        #expect(environment.displayScale == 1)
        #expect(environment.pixelLength == 1)
        #expect(environment.dynamicTypeSize == .large)
        #expect(environment.horizontalSizeClass == .regular)
        #expect(environment.verticalSizeClass == .regular)
        #expect(environment.isLuminanceReduced == false)
        #expect(environment.isUserAuthenticationEnabled == false)
        #expect(environment.layoutDirection == .leftToRight)
        #expect(environment.legibilityWeight == nil)
        #expect(environment.supportsRemoteScenes == false)
        #expect(environment.autocorrectionDisabled == false)
        #expect(environment.isFocusEffectEnabled)
        #expect(environment.textCase == nil)
    }

    @Test("A Dynamic Type size set on a subtree is what it reads")
    func dynamicTypeSizeSets() {
        #expect(shown(Reads(keyPath: \.dynamicTypeSize).dynamicTypeSize(.accessibility3))
            == "accessibility3")
    }

    @Test("A range clamps the size into it, as SwiftUI's does")
    func dynamicTypeSizeClamps() {
        #expect(shown(Reads(keyPath: \.dynamicTypeSize).dynamicTypeSize(...DynamicTypeSize.small))
            == "small")
        #expect(shown(Reads(keyPath: \.dynamicTypeSize).dynamicTypeSize(DynamicTypeSize.xxLarge...))
            == "xxLarge")
        #expect(shown(Reads(keyPath: \.dynamicTypeSize).dynamicTypeSize(.medium ... .xLarge))
            == "large", "a size already inside the range is left alone")
    }

    @Test("Type sizes order smallest first, and the last five are accessibility sizes")
    func dynamicTypeSizeOrder() {
        #expect(DynamicTypeSize.xSmall < .large && DynamicTypeSize.xxxLarge < .accessibility1)
        #expect(DynamicTypeSize.allCases.filter(\.isAccessibilitySize).count == 5)
        #expect(!DynamicTypeSize.xxxLarge.isAccessibilitySize)
    }

    @Test("Size classes, the display scale and reduced luminance are channels a subtree can set")
    func settableChannels() {
        // The value's description names the module that declares its type,
        // which the module split moves (TUIkitFoundation now, not TUIkit).
        #expect(shown(Reads(keyPath: \.horizontalSizeClass).environment(\.horizontalSizeClass, .compact))
            == String(describing: UserInterfaceSizeClass?.some(.compact)))
        #expect(shown(Reads(keyPath: \.displayScale).environment(\.displayScale, 2)) == "2.0")
        #expect(shown(Reads(keyPath: \.isLuminanceReduced).environment(\.isLuminanceReduced, true))
            == "true")
    }

    @Test("autocorrectionDisabled records the request in the environment")
    func autocorrectionRecorded() {
        #expect(shown(Reads(keyPath: \.autocorrectionDisabled).autocorrectionDisabled()) == "true")
        #expect(shown(Reads(keyPath: \.autocorrectionDisabled).autocorrectionDisabled(false)) == "false")
    }

    @Test("focusEffectDisabled turns isFocusEffectEnabled off, and an inner false does not restore it")
    func focusEffectEnvironment() {
        #expect(shown(Reads(keyPath: \.isFocusEffectEnabled).focusEffectDisabled()) == "false")
        #expect(shown(Reads(keyPath: \.isFocusEffectEnabled)
            .focusEffectDisabled(false).focusEffectDisabled()) == "false")
    }

    @Test("The textCase environment value is the transform, both to read and to write")
    func textCaseEnvironment() {
        // The reading is itself a Text under the transform, so it shouts too.
        // (Its description names the module declaring `Text.Case`, as above.)
        #expect(shown(Reads(keyPath: \.textCase).textCase(.uppercase))
            == String(describing: Text.Case?.some(.uppercase)).uppercased())
        #expect(shown(Text("shout").environment(\.textCase, .uppercase)) == "SHOUT")
        #expect(shown(Text("quiet").environment(\.textCase, nil).textCase(.uppercase)) == "quiet",
                "a nil written inside clears the transform set outside")
    }

    @Test("An environment describes the values set in it")
    func describes() {
        var environment = EnvironmentValues()
        #expect(environment.description == "[]")
        environment.dynamicTypeSize = .xLarge
        #expect(environment.description.contains("xLarge"))
    }
}
