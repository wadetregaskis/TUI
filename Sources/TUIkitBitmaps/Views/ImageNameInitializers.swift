//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageNameInitializers.swift
//
//  `Label("Settings", image: "gear")` and the same shorthand on
//  `ContentUnavailableView`: an icon from an image resource named by a string.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

/// A raster image drawn as a label's icon: in the two cells a symbol takes.
///
/// - Important: Framework infrastructure, public only because it appears in
///   ``Label``'s generic signature, as `_SymbolIcon` does.
public struct _ImageIcon: View {
    let image: Image

    public var body: some View {
        // The picture at a glyph's size: an icon beside a title, not a photograph
        // fitted to the row. Stretched to the two cells, as SwiftUI's resizable
        // icon fills its frame.
        image.resizable().frame(width: 2, height: 1)
    }
}

extension Label where Title == Text, Icon == _ImageIcon {
    /// Creates a label with a localized title and an icon from an image
    /// resource — mirrors SwiftUI's `Label(_:image:)` with a resource name.
    ///
    /// The image is found as ``Image/init(_:bundle:)`` finds it, a plain image
    /// file among the main bundle's resources, and drawn in the two cells a
    /// symbol takes. The `ImageResource` spelling stays declined: it names a
    /// build product only Xcode's asset catalogue makes.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the title — a literal is looked up, see
    ///     ``LocalizedStringKey``.
    ///   - name: The name of the image resource.
    public init(_ titleKey: LocalizedStringKey, image name: String) {
        self.init(title: Text(titleKey), icon: _ImageIcon(image: Image(name)), iconIsVisible: true)
    }

    /// Creates a label with a title shown as written and an icon from an image
    /// resource — see ``init(_:image:)-(LocalizedStringKey,_)``.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - name: The name of the image resource.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image name: String) {
        self.init(title: Text(String(title)), icon: _ImageIcon(image: Image(name)), iconIsVisible: true)
    }
}

extension ContentUnavailableView
where Label == TUIkitFoundation.Label<Text, _ImageIcon>, Description == Text?, Actions == EmptyView {
    /// Creates an empty-state view with an image resource beside a localized
    /// title — mirrors SwiftUI's `init(_:image:description:)` with a resource
    /// name.
    ///
    /// - Parameters:
    ///   - title: The key for the title text.
    ///   - name: The name of the image resource, found as
    ///     ``Image/init(_:bundle:)`` finds it.
    ///   - description: An optional sentence below the title.
    public init(_ title: LocalizedStringKey, image name: String, description: Text? = nil) {
        self.init(
            label: { TUIkitFoundation.Label(title, image: name) },
            description: { description },
            actions: { EmptyView() })
    }

    /// Creates an empty-state view with an image resource beside a title shown
    /// as written.
    ///
    /// - Parameters:
    ///   - title: The title text.
    ///   - name: The name of the image resource.
    ///   - description: An optional sentence below the title.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image name: String, description: Text? = nil) {
        self.init(
            label: { TUIkitFoundation.Label(title, image: name) },
            description: { description },
            actions: { EmptyView() })
    }
}
