//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+Bundle.swift
//
//  SwiftUI's named colours, read from the asset catalogue a bundle carries.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Color {
    /// Creates a color from a color set that you indicate by name — mirrors
    /// SwiftUI's `init(_:bundle:)`.
    ///
    /// The colour set is read from the asset catalogue the bundle carries
    /// uncompiled: `swift build` copies an `Assets.xcassets` folder in a
    /// target's resources into its resource bundle as it is, and TUIkit reads
    /// `Name.colorset/Contents.json` there, on every platform. A catalogue
    /// Xcode compiled (`Assets.car`) is read too, on macOS, where the file
    /// imports `TUIkitAppKit`, which reads it through AppKit.
    ///
    /// ```swift
    /// // Package.swift: resources: [.process("Resources")], with
    /// // Resources/Assets.xcassets/Brand.colorset inside.
    /// Text("Hello").foregroundStyle(Color("Brand", bundle: .module))
    /// ```
    ///
    /// A colour that is not found is `Color.clear`, as SwiftUI's is (measured:
    /// it resolves to `#00000000`).
    ///
    /// > Important: **A set's light and dark colours are chosen when the
    /// > colour is made, not where it is drawn.** SwiftUI keeps both and draws
    /// > the one for the `\.colorScheme` where the colour is used. A TUIkit
    /// > `Color` is five bytes, with no room for two colours or a reference to
    /// > the set, so the choice is made at once, by the colour scheme a view
    /// > reads where nothing has set a palette — the default palette's, which
    /// > is what `NSColor(_:)` resolves a palette role against too. A subtree
    /// > under a `.palette(_:)` of the other scheme, or under a
    /// > `.environment(\.colorScheme, …)` pin, still gets that colour. See
    /// > `Documentation/SwiftUI-API-completion-decisions-D6M.md` (B-D6M-1).
    ///
    /// - Parameters:
    ///   - name: The name of the color resource to look for.
    ///   - bundle: The bundle in which to search for the color resource. If
    ///     you don't indicate a bundle, the initializer looks in your app's
    ///     main bundle by default.
    @_disfavoredOverload
    public init(_ name: String, bundle: Bundle? = nil) {
        // `@_disfavoredOverload` is NOT a hint about which spelling to prefer
        // inside TUIkit: it is what lets `TUIkitAppKit`'s declaration of this
        // same initializer, which also reads compiled catalogues, win wherever
        // a file imports that module. Two modules declaring one member is
        // otherwise ambiguous at the call (measured on Swift 6.2.4); a
        // disfavoured one loses to the other, and is the only one where
        // `TUIkitAppKit` is not imported.
        self = Self.catalogColor(named: name, in: bundle) ?? .clear
    }

    /// The colour `name` in the uncompiled catalogues of `bundle` (the main
    /// bundle for `nil`), in ``catalogColorScheme``, or `nil` where none has
    /// it. `TUIkitAppKit` asks this before it asks AppKit.
    package static func catalogColor(named name: String, in bundle: Bundle?) -> Color? {
        AssetCatalog.colorSet(named: name, in: bundle ?? .main)?.color(for: catalogColorScheme)
    }

    /// The colour scheme a named colour's or image's light and dark variants
    /// are chosen by: the one a view reads where nothing has set a palette.
    package static var catalogColorScheme: ColorScheme {
        EnvironmentValues().colorScheme
    }
}
