//  🖥️ TUI — A Terminal UI framework for Swift
//  CompileCorpusTUIOnly.swift
//
//  SwiftUI source that must compile against TUI ALONE — type-checked on its
//  own by `compile_corpus.sh`, because `CompileCorpus.swift` imports AppKit for
//  its bridge snippets, and AppKit brings SwiftUICore with it.
//
//  What this file proves is decisions B50: nothing TUI is built from imports
//  AppKit, so an app that imports only TUI sees nothing of SwiftUICore. Its
//  `FormatStyle.offset(to:)` and the rest were visible beside TUI's in every
//  such app, and a plain `FormatStyle` context below was ambiguous — a compile
//  error — until the bridges moved to `TUIAppKit`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

@available(macOS 15, *)
@MainActor
private struct FormatStylesWithoutSwiftUICore: View {
    let deadline: Date

    var body: some View {
        VStack {
            // A `FormatStyle` context outside TUI: Foundation's own
            // `formatted(_:)`. With SwiftUICore loaded it is ambiguous.
            Text(verbatim: String(Date.now.formatted(.offset(to: deadline)).characters))
            Text(verbatim: String(Date.now.formatted(.reference(to: deadline)).characters))
            Text(.currentDate, format: .offset(to: deadline))
            Text(.currentDate, format: .timer(countingDownIn: Date.now..<deadline))
        }
    }
}

/// SwiftUI's named colour and image, bound to TUI's own declarations
/// (decisions A15): with `TUIAppKit` absent they are the only ones.
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

/// Core Graphics' bridges, with TUI alone (decisions B-D3M-4): a `CGColor`
/// and a `CGImage` into SwiftUI's colour and image, and a colour back out.
#if canImport(CoreGraphics)
    @MainActor
    private struct CoreGraphicsBridgesWithoutAppKit: View {
        let picture: CGImage

        var body: some View {
            VStack {
                Image(picture, scale: 2, label: Text("picture"))
                Image(decorative: picture, scale: 1, orientation: .up)
            }
            .foregroundStyle(Color(cgColor: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        }

        var cgColor: CGColor { Color.red.resolve(in: EnvironmentValues()).cgColor }
    }
#endif
