//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Image

/// Displays an image as colored ASCII art in the terminal.
///
/// `Image` loads a raster image from a file path or URL, converts it to
/// colored ASCII characters, and displays it at the specified size.
/// Loading happens asynchronously; a placeholder is shown while loading.
///
/// ## Usage
///
/// ```swift
/// // From a local file
/// Image(.file("/path/to/logo.png"))
///     .frame(width: 60, height: 30)
///
/// // From a URL (cached per session)
/// Image(.url("https://example.com/photo.png"))
///     .frame(width: 40, height: 20)
///
/// // With rendering options
/// Image(.file("photo.png"))
///     .imageCharacterSet(.braille)
///     .imageColorMode(.trueColor)
///     .imageDithering(.floydSteinberg)
///     .frame(width: 80, height: 40)
/// ```
///
/// ## Sizing
///
/// An image that is not resizable takes its **natural size**, as SwiftUI's
/// does: its size in points — its pixels over its scale, so a pixel a point
/// for a file — in cells of the terminal's size in points, whatever it is
/// offered. A 140 × 70-pixel picture is 20 × 5 cells in a terminal whose cell
/// is 7 × 14 points, and a frame around it does not change it. A frame
/// smaller than that cuts it to the frame, keeping its top-leading part:
/// unlike SwiftUI's, which overflows its frame, a terminal image draws only
/// within the space it is given.
///
/// The cell's size in points is known where TUIkit has measured what the
/// terminal reports: Apple Terminal, iTerm2 and Warp, and Ghostty when the app
/// runs on the Mac it is on (see ``EnvironmentValues/imageCellPoints``).
/// Elsewhere — under tmux, which does not pass the cell's size on, over ssh to
/// Ghostty, on a terminal nobody has measured — an image that is not
/// resizable **fits the space it is offered** instead, keeping its aspect,
/// which is what every image here did before images had a natural size. So
/// does one under ``View/imageFitTarget(_:)`` `.proposedSize` or `.viewport`.
///
/// ``resizable(capInsets:resizingMode:)`` makes it fill its frame instead, as
/// SwiftUI's does, unless a content mode (``View/scaledToFit()``,
/// ``View/aspectRatio(_:contentMode:)``) says to keep the aspect. The common
/// `.resizable().scaledToFit()` is how an image is fitted to a space on every
/// terminal alike.
///
/// ## Placeholder
///
/// While loading, a centered placeholder is displayed. By default this is an
/// animated ``Spinner``, above the placeholder text when there is some. It
/// animates at the speed set for spinners (see
/// ``View/indicatorAnimationSpeed(_:for:)``) and is drawn in this image's
/// `foregroundStyle`, or the palette's accent. Use
/// ``View/imagePlaceholder(_:)-(LocalizedStringKey)`` to set the text,
/// ``View/imagePlaceholderSpinner(style:color:)`` to choose the spinner, and
/// ``View/imagePlaceholderSpinner(_:)`` to leave it out.
///
/// ## SF Symbols
///
/// ``init(systemName:)`` makes the other kind of image SwiftUI has — a system
/// symbol — which in a terminal is one glyph rather than a raster:
///
/// ```swift
/// HStack {
///     Image(systemName: "star.fill")
///     Text("Favourite")
/// }
/// ```
///
/// The rendering modifiers above apply to raster images only; there is nothing
/// for them to do to a character. See ``SFSymbol`` for where symbols draw at
/// all, and ``Label/init(_:systemImage:)-(LocalizedStringKey,_)`` for the icon-with-title shape, which
/// is usually the better one because it can drop its gap as well as its glyph.
public struct Image: View {
    /// What this image *is* — the two unrelated things SwiftUI's `Image` also
    /// covers, kept as one type because that is the API being matched.
    ///
    /// They share nothing but the name: one is decoded, resampled and converted
    /// to coloured cells, the other is a single character looked up in a table.
    package enum Content: Equatable {
        /// A raster image: the picture the bitmap path made (``_ImageRaster``)
        /// from a file, a URL, a bundle or pixels already decoded.
        case raster(any _ImageRaster)
        /// An SF Symbol, by name — resolved to a glyph at render time so
        /// ``View/symbolVariant(_:)`` above it still chooses the cut.
        case symbol(String)

        /// A picture compares through its own ``_ImageRaster/isEqual(to:)``,
        /// which leaves out pixels already decoded. Every pair spelled out,
        /// with no `default`, so a third kind of content has to say how it
        /// compares.
        package static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.raster(let lhs), .raster(let rhs)): lhs.isEqual(to: rhs)
            case (.symbol(let lhs), .symbol(let rhs)): lhs == rhs
            case (.raster, .symbol), (.symbol, .raster): false
            }
        }
    }

    package let content: Content

    /// The interpolation quality ``interpolation(_:)`` set, if any.
    var interpolationQuality: Interpolation?

    /// Whether ``antialiased(_:)`` asked for smoothing, if it was called.
    var isAntialiased: Bool?

    /// How ``renderingMode(_:)`` said to draw the image, if it was called.
    var templateRenderingMode: TemplateRenderingMode?

    /// How ``resizable(capInsets:resizingMode:)`` said to fill the frame, or
    /// `nil` for an image that was not made resizable.
    var resizing: _ImageResizing?

    /// The supersampling factor this image's own modifiers ask for, or `nil`
    /// to take the environment's: an interpolation quality, else `1` for an
    /// image told not to antialias.
    private var samplingFactor: Int? {
        if let interpolationQuality { return interpolationQuality.samplingFactor }
        return isAntialiased == false ? 1 : nil
    }

    /// Creates an image of the picture the bitmap path made: what
    /// ``init(_:)`` from a file or a URL, the bundle and asset-catalogue
    /// initialisers and ``AsyncImage`` make their images with. They live
    /// beside the bitmap path (`Image+Raster.swift`), which `Image` does not
    /// name — see ``_ImageRaster``.
    init(raster: any _ImageRaster) {
        self.content = .raster(raster)
    }

    /// Creates an image showing the named SF Symbol.
    ///
    /// Mirrors SwiftUI's `Image(systemName:)`. The symbol is a terminal glyph,
    /// not artwork: it takes the two cells a wide character takes and follows
    /// the surrounding text's colour, and it cannot be scaled.
    ///
    /// Where the symbol would not really draw — a non-Apple platform, a
    /// terminal without the SF Symbols font, an unknown name — this renders
    /// **nothing**, because there is nothing else it could honestly show (see
    /// ``SFSymbol/canRender(named:)``). That is the one place
    /// ``Label/init(_:systemImage:)-(LocalizedStringKey,_)`` does better: it can close the gap it was
    /// going to leave, and a bare `Image` in an `HStack` cannot, the spacing
    /// being the stack's.
    ///
    /// - Parameter systemName: The SF Symbol name, e.g. `"star.fill"`.
    public init(systemName: String) {
        self.content = .symbol(systemName)
    }

    @ViewBuilder
    public var body: some View {
        switch content {
        case .raster(let raster):
            _ImageRasterHost(
                raster: raster,
                options: _ImageRasterOptions(
                    isTemplate: templateRenderingMode == .template, resizing: resizing,
                    samplingFactor: samplingFactor))
        case .symbol(let name):
            _SymbolIcon(name: name)
        }
    }
}

// MARK: - Equatable

extension Image: @preconcurrency Equatable {
    /// Every stored property, the content through its picture's own equality,
    /// which leaves out pixels already decoded (what the source decodes to):
    /// an image drawn at another quality, or as a template, is a different
    /// image to a memo that compares them.
    public static func == (lhs: Image, rhs: Image) -> Bool {
        guard lhs.content == rhs.content,
            lhs.interpolationQuality == rhs.interpolationQuality,
            lhs.isAntialiased == rhs.isAntialiased,
            lhs.templateRenderingMode == rhs.templateRenderingMode
        else { return false }
        return lhs.resizing == rhs.resizing
    }
}
