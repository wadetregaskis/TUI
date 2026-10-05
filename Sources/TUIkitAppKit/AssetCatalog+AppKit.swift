//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AssetCatalog+AppKit.swift
//
//  SwiftUI's named colours and images from an asset catalogue Xcode compiled
//  (`Assets.car`), which only AppKit reads. Here, in `TUIkitAppKit`, rather
//  than in `TUIkit`: see `Exports.swift` in this module for why.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(AppKit)
    import AppKit
    import TUIkit

    // Each initializer here is TUIkit's of the same name with one more place
    // to look. TUIkit declares its own `@_disfavoredOverload`, so these win in
    // a file that imports this module, and TUIkit's is the only one elsewhere.
    // Each asks TUIkit's first — the uncompiled catalogue and plain resource
    // files a SwiftPM build has — and AppKit only for what that does not find,
    // so importing this module never changes what an app already drew.

    extension Color {
        /// Creates a color from a color set that you indicate by name —
        /// mirrors SwiftUI's `init(_:bundle:)`.
        ///
        /// As TUIkit's own `init(_:bundle:)`, which reads the uncompiled
        /// catalogue `swift build` copies into a resource bundle, and then, for
        /// a name that has none, the compiled catalogue (`Assets.car`) an
        /// Xcode build makes, through `NSColor(named:bundle:)`. Its light or
        /// dark colour is chosen as TUIkit's is: by the colour scheme a view
        /// reads where nothing has set a palette, when the colour is made.
        ///
        /// - Parameters:
        ///   - name: The name of the color resource to look for.
        ///   - bundle: The bundle in which to search for the color resource.
        ///     If you don't indicate a bundle, the initializer looks in your
        ///     app's main bundle by default.
        public init(_ name: String, bundle: Bundle? = nil) {
            if let color = Self.catalogColor(named: name, in: bundle) {
                self = color
            } else if let named = NSColor(named: name, bundle: bundle) {
                var color = Self.clear
                CompiledCatalog.appearance.performAsCurrentDrawingAppearance { color = Color(nsColor: named) }
                self = color
            } else {
                self = .clear
            }
        }
    }

    extension Image {
        /// Creates a labeled image that you can use as content for controls —
        /// mirrors SwiftUI's `init(_:bundle:)`.
        ///
        /// As TUIkit's own `init(_:bundle:)` — an uncompiled catalogue, then a
        /// plain resource file — and then, for a name that has neither, the
        /// compiled catalogue (`Assets.car`) an Xcode build makes, through
        /// `Bundle.image(forResource:)`. Its natural size is the catalogue
        /// image's size in points, as SwiftUI's is.
        ///
        /// - Parameters:
        ///   - name: The name of the image resource.
        ///   - bundle: The bundle to search, or `nil` for the main bundle.
        public init(_ name: String, bundle: Bundle? = nil) {
            self = Image(compiledCatalogNamed: name, bundle: bundle)
        }

        /// Creates a labeled image that you can use as content for controls,
        /// with the specified label — mirrors SwiftUI's
        /// `init(_:bundle:label:)`.
        ///
        /// Found as `init(_:bundle:)` finds it. `label` is accepted for the
        /// accessibility a terminal does not have.
        ///
        /// - Parameters:
        ///   - name: The name of the image resource.
        ///   - bundle: The bundle to search, or `nil` for the main bundle.
        ///   - label: The label associated with the image.
        public init(_ name: String, bundle: Bundle? = nil, label: Text) {
            self = Image(compiledCatalogNamed: name, bundle: bundle)
        }

        /// Creates an unlabeled, decorative image — mirrors SwiftUI's
        /// `init(decorative:bundle:)`.
        ///
        /// Found as `init(_:bundle:)` finds it.
        ///
        /// - Parameters:
        ///   - name: The name of the image resource.
        ///   - bundle: The bundle to search, or `nil` for the main bundle.
        public init(decorative name: String, bundle: Bundle? = nil) {
            self = Image(compiledCatalogNamed: name, bundle: bundle)
        }

        /// TUIkit's lookup, then the compiled catalogue, then the missing
        /// file TUIkit draws for a name it cannot find.
        private init(compiledCatalogNamed name: String, bundle: Bundle?) {
            if let image = Self.bundleResource(named: name, in: bundle) {
                self = image
            } else if let picture = CompiledCatalog.picture(named: name, in: bundle ?? .main) {
                self.init(decorative: picture.image, scale: picture.scale)
            } else {
                self = Image(.file(name))
            }
        }
    }

    /// The pictures read out of compiled catalogues, kept for the process.
    ///
    /// `Bundle.image(forResource:)` makes a new `NSImage` at every call
    /// (measured), and an image the app hands over is named by its object's
    /// address and drawn out once (decisions B43). A body that names a
    /// catalogue image runs every frame, so without this every frame would be
    /// a new picture, drawn out again. Each is rendered once, under the
    /// appearance TUIkit chooses variants by, to a `CGImage` that is kept.
    private enum CompiledCatalog {
        struct Picture {
            let image: CGImage
            let scale: CGFloat
        }

        private struct Key: Hashable {
            let bundlePath: String
            let name: String
            let isDark: Bool
        }

        private static let lock = NSLock()
        nonisolated(unsafe) private static var pictures: [Key: Picture?] = [:]

        /// The appearance a catalogue's light and dark variants are chosen
        /// by — TUIkit's `Color.catalogColorScheme`, in AppKit's terms.
        static var appearance: NSAppearance {
            NSAppearance(named: Color.catalogColorScheme == .dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        }

        static func picture(named name: String, in bundle: Bundle) -> Picture? {
            let isDark = Color.catalogColorScheme == .dark
            let key = Key(bundlePath: bundle.bundlePath, name: name, isDark: isDark)
            if let known = lock.withLock({ pictures[key] }) { return known }
            var picture: Picture?
            // The largest representation, as TUIkit's own reader takes an image
            // set's largest file: a catalogue keeps one per scale.
            if let image = bundle.image(forResource: name), image.size.width > 0,
                let largest = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide })
            {
                appearance.performAsCurrentDrawingAppearance {
                    var rect = CGRect(origin: .zero, size: image.size)
                    if let cgImage = largest.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                        picture = Picture(image: cgImage, scale: CGFloat(cgImage.width) / image.size.width)
                    }
                }
            }
            lock.withLock { pictures[key] = .some(picture) }
            return picture
        }
    }
#endif
