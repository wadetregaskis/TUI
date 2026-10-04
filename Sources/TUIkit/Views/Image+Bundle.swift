//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+Bundle.swift
//
//  SwiftUI's named images, found as plain image files among a bundle's
//  resources.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Image {
    /// Creates a labeled image that you can use as content for controls —
    /// mirrors SwiftUI's `init(_:bundle:)`.
    ///
    /// SwiftUI looks the name up in an asset catalogue, which only Xcode
    /// compiles; a SwiftPM executable, which a terminal app is, has none. So
    /// TUIkit looks for a plain image file of that name among the bundle's
    /// resources: the name as given if it has an extension, else the name with
    /// the first of `png`, `jpg`, `jpeg`, `gif`, `bmp` and `tiff` that is
    /// there. An image that is not found draws the load error every raster
    /// image draws for a missing file.
    ///
    /// ```swift
    /// // Package.swift: resources: [.process("Resources")]
    /// Image("logo", bundle: .module)
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the image resource.
    ///   - bundle: The bundle to search, or `nil` for the main bundle.
    public init(_ name: String, bundle: Bundle? = nil) {
        self.init(.file(Self.resourcePath(named: name, in: bundle)))
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
    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        self.init(name, bundle: bundle)
    }

    /// Creates an unlabeled, decorative image — mirrors SwiftUI's
    /// `init(decorative:bundle:)`.
    ///
    /// Found as ``init(_:bundle:)`` finds it.
    ///
    /// - Parameters:
    ///   - name: The name of the image resource.
    ///   - bundle: The bundle to search, or `nil` for the main bundle.
    public init(decorative name: String, bundle: Bundle? = nil) {
        self.init(name, bundle: bundle)
    }

    /// The extensions a named image is looked for with, in order.
    static let resourceExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff"]

    /// The path of the image resource `name` in `bundle` (the main bundle for
    /// `nil`) — or `name` itself when there is none, which then fails to load
    /// as a missing file does.
    static func resourcePath(named name: String, in bundle: Bundle?) -> String {
        let bundle = bundle ?? .main
        if !(name as NSString).pathExtension.isEmpty,
            let url = bundle.url(forResource: name, withExtension: nil)
        {
            return url.path
        }
        for pathExtension in resourceExtensions {
            if let url = bundle.url(forResource: name, withExtension: pathExtension) { return url.path }
        }
        return name
    }
}
