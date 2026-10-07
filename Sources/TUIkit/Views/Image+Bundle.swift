//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+Bundle.swift
//
//  SwiftUI's named images, found in the asset catalogue a bundle carries, or
//  as plain image files among its resources.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Image {
    /// Creates a labeled image that you can use as content for controls —
    /// mirrors SwiftUI's `init(_:bundle:)`.
    ///
    /// SwiftUI looks the name up in an asset catalogue. Xcode compiles one;
    /// `swift build`, which builds a terminal app, copies the `.xcassets`
    /// folder into the target's resource bundle as it is. So TUIkit reads
    /// `Name.imageset` in that folder, on every platform: the largest of its
    /// pictures it can decode (`png`, `jpg`, `jpeg`, `gif`, `bmp` or `tiff`),
    /// drawn at the scale it was made for, so a `@2x` picture has the natural
    /// size of its `1x` sibling, as in SwiftUI. Where the file imports
    /// `TUIkitAppKit`, a catalogue Xcode compiled (`Assets.car`) is read too,
    /// on macOS, through AppKit.
    ///
    /// Failing a catalogue, it looks for a plain image file of that name among
    /// the bundle's resources: the name as given if it has an extension, else
    /// the name with the first of those extensions that is there. An image
    /// that is not found draws the load error every raster image draws for a
    /// missing file.
    ///
    /// ```swift
    /// // Package.swift: resources: [.process("Resources")]
    /// Image("logo", bundle: .module)
    /// ```
    ///
    /// An image set with a dark variant is chosen between when the image is
    /// made, as ``Color/init(_:bundle:)`` chooses a colour set's.
    ///
    /// - Parameters:
    ///   - name: The name of the image resource.
    ///   - bundle: The bundle to search, or `nil` for the main bundle.
    @_disfavoredOverload
    public init(_ name: String, bundle: Bundle? = nil) {
        // Disfavoured so `TUIkitAppKit`'s declaration, which also reads a
        // compiled catalogue, wins where it is imported — see
        // `Color.init(_:bundle:)` for why that takes this attribute.
        self = Self.bundleResource(named: name, in: bundle) ?? Image(.file(name))
    }

    /// Creates a labeled image that you can use as content for controls,
    /// with the specified label — mirrors SwiftUI's `init(_:bundle:label:)`.
    ///
    /// Found as ``init(_:bundle:)`` finds it. `label` is accepted for the
    /// accessibility a terminal does not have.
    ///
    /// - Parameters:
    ///   - name: The name of the image resource.
    ///   - bundle: The bundle to search, or `nil` for the main bundle.
    ///   - label: The label associated with the image.
    @_disfavoredOverload
    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        self = Self.bundleResource(named: name, in: bundle) ?? Image(.file(name))
    }

    /// Creates an unlabeled, decorative image — mirrors SwiftUI's
    /// `init(decorative:bundle:)`.
    ///
    /// Found as ``init(_:bundle:)`` finds it.
    ///
    /// - Parameters:
    ///   - name: The name of the image resource.
    ///   - bundle: The bundle to search, or `nil` for the main bundle.
    @_disfavoredOverload
    public init(decorative name: String, bundle: Bundle? = nil) {
        self = Self.bundleResource(named: name, in: bundle) ?? Image(.file(name))
    }

    /// The extensions a named image is looked for with, in order.
    nonisolated static let resourceExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff"]

    /// The image `name` in `bundle` (the main bundle for `nil`): from an
    /// uncompiled asset catalogue, else a plain resource file — or `nil`
    /// where there is neither. `TUIkitAppKit` asks this before it asks AppKit.
    package static func bundleResource(named name: String, in bundle: Bundle?) -> Image? {
        let bundle = bundle ?? .main
        if let file = AssetCatalog.imageFile(named: name, in: bundle, for: Color.catalogColorScheme) {
            return Image(.file(file.path), decoded: file.scale != 1 ? AssetCatalog.decodedImage(for: file) : nil)
        }
        return plainResourcePath(named: name, in: bundle).map { Image(.file($0)) }
    }

    /// The path of the image resource `name` in `bundle` (the main bundle for
    /// `nil`) — or `name` itself when there is none, which then fails to load
    /// as a missing file does.
    static func resourcePath(named name: String, in bundle: Bundle?) -> String {
        plainResourcePath(named: name, in: bundle ?? .main) ?? name
    }

    /// The path of a plain image file `name` among `bundle`'s resources.
    private static func plainResourcePath(named name: String, in bundle: Bundle) -> String? {
        if !(name as NSString).pathExtension.isEmpty,
            let url = bundle.url(forResource: name, withExtension: nil)
        {
            return url.path
        }
        for pathExtension in resourceExtensions {
            if let url = bundle.url(forResource: name, withExtension: pathExtension) { return url.path }
        }
        return nil
    }
}

extension AssetCatalog {
    private static let decodedLock = NSLock()
    nonisolated(unsafe) private static var decoded: [String: _DecodedImage] = [:]

    /// The pixels of an image set's picture drawn at another scale than 1,
    /// decoded the first time they are drawn and kept for the process, so
    /// the same object — and the same name, to a memo — comes back every
    /// frame.
    static func decodedImage(for file: ImageFile) -> _DecodedImage {
        let key = "\(file.scale)@\(file.path)"
        return decodedLock.withLock {
            if let known = decoded[key] { return known }
            let path = file.path
            let made = _DecodedImage(owner: key as NSString, pointSizing: .scale(file.scale)) {
                (try? PlatformImageLoader().loadImage(from: path)) ?? RGBAImage(width: 0, height: 0, pixels: [])
            }
            decoded[key] = made
            return made
        }
    }
}
