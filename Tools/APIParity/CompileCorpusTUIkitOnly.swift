//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompileCorpusTUIkitOnly.swift
//
//  SwiftUI source that must compile against TUIkit ALONE — type-checked on its
//  own by `compile_corpus.sh`, because `CompileCorpus.swift` imports AppKit for
//  its bridge snippets, and AppKit brings SwiftUICore with it.
//
//  What this file proves is decisions B50: nothing TUIkit is built from imports
//  AppKit, so an app that imports only TUIkit sees nothing of SwiftUICore. Its
//  `FormatStyle.offset(to:)` and the rest were visible beside TUIkit's in every
//  such app, and a plain `FormatStyle` context below was ambiguous — a compile
//  error — until the bridges moved to `TUIkitAppKit`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

@available(macOS 15, *)
@MainActor
private struct FormatStylesWithoutSwiftUICore: View {
    let deadline: Date

    var body: some View {
        VStack {
            // A `FormatStyle` context outside TUIkit: Foundation's own
            // `formatted(_:)`. With SwiftUICore loaded it is ambiguous.
            Text(verbatim: String(Date.now.formatted(.offset(to: deadline)).characters))
            Text(verbatim: String(Date.now.formatted(.reference(to: deadline)).characters))
            Text(.currentDate, format: .offset(to: deadline))
            Text(.currentDate, format: .timer(countingDownIn: Date.now..<deadline))
        }
    }
}

/// SwiftUI's named colour and image, bound to TUIkit's own declarations
/// (decisions A15): with `TUIkitAppKit` absent they are the only ones.
@MainActor
private struct AssetCatalogShapesWithoutAppKit: View {
    var body: some View {
        VStack {
            Text("asset.title").foregroundStyle(Color("Brand"))
            Image("Logo", bundle: .main)
            Image(decorative: "Logo")
        }
        .background(Color("Background", bundle: .main))
    }
}
