//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextVariantPreferenceTests.swift
//
//  `Text.textVariant(.fixed)`: SwiftUI's default preference, the widest
//  variant, which is what every text draws already.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Text.textVariant(_:)")
struct TextVariantPreferenceTests {
    @Test("The fixed preference draws the widest variant, as a text does without it")
    func fixedIsTheDefault() {
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let context = makeRenderContext(width: 8, height: 1) { environment, _ in
            environment.locale = Locale(identifier: "en_US")
            environment.calendar = Calendar(identifier: .gregorian)
            environment.timeZone = TimeZone(identifier: "UTC")!
        }
        context.renderCache?.frameDate = base
        let text = Text(base.addingTimeInterval(-3_725.5), style: .relative).lineLimit(1)
        let fixed = renderToBuffer(text.textVariant(.fixed), context: context).lines
        let plain = renderToBuffer(text, context: context).lines
        #expect(fixed == plain)
        // Eight cells cannot hold "1 hr, 2 min": the fixed preference
        // truncates the widest variant rather than choose "1h 2m".
        #expect(fixed.map(\.stripped) == ["1 hr, 2…"])
    }
}
