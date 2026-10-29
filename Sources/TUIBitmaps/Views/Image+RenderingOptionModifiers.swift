//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+RenderingOptionModifiers.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation
import TUIImage

// MARK: - View Modifiers

extension View {
    /// Sets the glyph charset for image rendering — the fundamental
    /// repertoire (``ASCIICharacterSet/ascii(glyphs:)`` /
    /// ``ASCIICharacterSet/unicode(glyphs:)`` /
    /// ``ASCIICharacterSet/blocks(_:)`` /
    /// ``ASCIICharacterSet/customRamp(_:)``) and its size. Combine with
    /// ``imageShapeAware(_:)`` to choose the rendering algorithm.
    ///
    /// - Parameter characterSet: The charset to use.
    /// - Returns: A modified view.
    public func imageCharacterSet(_ characterSet: ASCIICharacterSet) -> some View {
        environment(\.imageCharacterSet, characterSet)
    }

    /// Sets whether image glyphs are SHAPE-matched — each glyph chosen for
    /// how its measured in-cell ink distribution fits the cell (a corner of
    /// darkness picks a corner-heavy glyph; curved edges follow) — rather
    /// than mapped from the cell's overall luminance alone.
    ///
    /// Applies to the `.ascii`, `.unicode`, and `.blocks` charsets (blocks
    /// shape-match over quadrants / halves / shades / corner triangles
    /// `◢◣◤◥`); a `.customRamp` is always luminance-mapped.
    ///
    /// One of three independent questions an image conversion answers — see
    /// ``imageEdgeContrast(_:)``, which lists all three.
    public func imageShapeAware(_ shapeAware: Bool = true) -> some View {
        environment(\.imageShapeAware, shapeAware)
    }

    /// Sets the color mode for ASCII art image rendering.
    ///
    /// ## Mono draws in the view's colours
    ///
    /// ``ASCIIColorMode/mono`` draws the picture in two colours. Its ink is the
    /// view's foreground style and its paper the view's background style (see
    /// ``View/foregroundStyle(_:)-(S)`` and ``View/backgroundStyle(_:)-(S)``),
    /// each falling back to the palette's foreground or background where nothing
    /// is stated. It is TUI's analogue of a SwiftUI template image, which
    /// `foregroundStyle` tints. TUI has no `renderingMode(_:)`, and taking
    /// the paper from `backgroundStyle` is TUI-specific.
    ///
    /// ```swift
    /// Image(.file("logo.png"))
    ///     .imageColorMode(.mono)
    ///     .foregroundStyle(.rgb(255, 255, 255))
    ///     .backgroundStyle(.rgb(0, 0, 0))
    /// ```
    ///
    /// - A gradient style inks the picture in its representative colour, and the
    ///   text style cascade is not consulted: an image is not text.
    /// - A faded colour fades the glyphs. Where the terminal draws the picture as
    ///   pixels it is drawn at full strength, since those carry no alpha.
    /// - A cell nothing of the picture reaches is left unpainted, so a
    ///   transparent surround shows what the image sits on.
    ///
    /// Because it is inked the way `Text` is, it is re-inked wherever `Text`
    /// would be. A Button's label colour, a menu row's highlight, a disabled
    /// control's dim, and a Toggle's or RadioButton's hover or disabled colour
    /// all reach a mono image in their label. Where the terminal draws pictures
    /// as pixels, each new ink re-sends the picture: once per state change, and
    /// once per frame of a `withAnimation` fade. A focus breath is the
    /// exception. In a focused link's label the glyphs breathe, but a picture
    /// keeps the label's resting colour, the bright end of the breath, so it is
    /// sent once rather than once per frame.
    ///
    /// - Parameter colorMode: The color mode to use.
    /// - Returns: A modified view.
    public func imageColorMode(_ colorMode: ASCIIColorMode) -> some View {
        environment(\.imageColorMode, colorMode)
    }

    /// Recolours the image, by saying what its tones BECOME.
    ///
    /// ```swift
    /// Image("photo.jpg").imageToneCurve(.inverted)
    /// ```
    ///
    /// The pairs are a transfer curve, not a palette: `{black → white, white →
    /// black}` is a continuous negative in which mid-grey stays mid-grey, not a
    /// two-colour image. Applied before everything — before the monochrome
    /// threshold, before dithering, before any ``ASCIIPalette`` mapping —
    /// because an inversion moves where those land. See ``ASCIIToneCurve``.
    ///
    /// - Parameter toneCurve: The recolouring, or `nil` for none.
    /// - Returns: A modified view.
    public func imageToneCurve(_ toneCurve: ASCIIToneCurve?) -> some View {
        environment(\.imageToneCurve, toneCurve)
    }

    /// Sets the area-sampling factor for every non-shape renderer: each
    /// sample — a ramp cell's tone, a solid or half-block pixel, a braille
    /// dot — is averaged from a factor×factor block of source pixels
    /// instead of the bilinear scaler's 2×2 point read, which aliases fine
    /// textures on heavy downscales. Clamped to 1...4. Pass `nil` to
    /// restore the default (2 for luminance ramps longer than 12 levels,
    /// else 1). Ignored when ``imageShapeAware(_:)`` is on — the shape
    /// matcher already reads 96 staggered samples per cell.
    public func imageSupersampling(_ factor: Int?) -> some View {
        environment(\.imageSupersampling, factor)
    }

    /// Sets the minimum Sobel gradient magnitude for a shape-aware cell
    /// (see ``imageShapeAware(_:)``) to be drawn as a directional line
    /// glyph (`- | / \` for the ASCII charset, `─ │ ╱ ╲` for Unicode)
    /// instead of its nearest coverage match. Lower values trace more
    /// edges; the default `0.9` (in 0…1 region-darkness units, practical
    /// range roughly 0.3…2) triggers on a clean light/dark boundary across
    /// a cell. Pass `nil` to disable line glyphs entirely (pure coverage
    /// matching). The shape-aware block repertoire carries its own
    /// directional glyphs, so it does not trace edges.
    /// One of three independent questions an image conversion answers — see
    /// ``imageEdgeContrast(_:)``, which lists all three.
    public func imageEdgeThreshold(_ threshold: Double?) -> some View {
        environment(\.imageEdgeThreshold, threshold)
    }

    /// Raises the image's LOCAL contrast before any character is chosen for it
    /// — an unsharp mask over the render's own pixel grid.
    ///
    /// The third of three independent things that can be asked of an image, and
    /// the only one about the picture rather than about the characters:
    /// ``imageEdgeThreshold(_:)`` decides *where the picture has an edge* and
    /// draws those cells as line glyphs, ``imageShapeAware(_:)`` decides *how a
    /// cell's ink is chosen*, and this decides *how much separation there is to
    /// see at all*. Any combination of the three is meaningful, this one
    /// included on its own — a plain luminance ramp gains contrast at the glyph
    /// boundaries too.
    ///
    /// Not a ``imageToneCurve(_:)``, which is the global version of the same
    /// wish: a curve moves every pixel of a given tone wherever it sits, so
    /// steepening it clips the ends to buy separation in the middle. This moves
    /// a pixel only by how far it differs from its neighbours, so flat regions
    /// stay exactly as they were.
    ///
    /// - Parameter amount: `0` (the default) leaves the picture alone; around
    ///   `0.6` is a visible lift, `2` heavy-handed. Negative values are treated
    ///   as zero.
    public func imageEdgeContrast(_ amount: Double) -> some View {
        environment(\.imageEdgeContrast, amount)
    }

    /// Sets the luminance at or above which a pixel is ink, where the
    /// drawing is ink or none: braille's dots, and every cell in the
    /// monochrome modes. TUI-specific.
    ///
    /// By default (`nil`) it is measured from each picture: the split between
    /// its two most different tones (Otsu's method), which lands where a
    /// person would draw it for a subject against a background. Where the two
    /// most different tones are two parts of the subject — the two halves of
    /// a two-tone face — the split loses one of them, and a stated threshold
    /// is the black level that keeps it. In colour, braille draws what falls
    /// below it as each cell's background, so nothing vanishes; the threshold
    /// still decides which pixels are dots.
    ///
    /// - Parameter threshold: `0...1`, from black to white, or `nil` to
    ///   measure it.
    public func imageInkThreshold(_ threshold: Double?) -> some View {
        environment(\.imageInkThreshold, threshold)
    }

    /// Sets the dithering mode for ASCII art image rendering.
    ///
    /// - Parameter dithering: The dithering algorithm.
    /// - Returns: A modified view.
    public func imageDithering(_ dithering: DitheringMode) -> some View {
        environment(\.imageDithering, dithering)
    }

    /// Sets the localized placeholder text shown while an image is loading.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The text is not optional in this overload:
    /// `nil` has no key to look up, and would otherwise be ambiguous.
    ///
    /// - Parameter textKey: The key for the placeholder text.
    /// - Returns: A modified view.
    public func imagePlaceholder(_ textKey: LocalizedStringKey) -> some View {
        environment(\.imagePlaceholderText, textKey.localized)
    }

    /// Sets the placeholder text shown while an image is loading, as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``. Non-optional, because a generic parameter cannot
    /// be inferred from `nil`; clearing the text stays on the overload below.
    ///
    /// - Parameter text: The placeholder text.
    /// - Returns: A modified view.
    @_disfavoredOverload
    public func imagePlaceholder<S: StringProtocol>(_ text: S) -> some View {
        environment(\.imagePlaceholderText, String(text))
    }

    /// Sets — or clears — the placeholder text shown while an image is loading.
    ///
    /// Stays concrete because the generic overload above cannot be inferred
    /// from `nil`, and `nil` ("no text at all") is the spelling that turns the
    /// placeholder text off. Unlike a concrete *non-optional* `String`, it
    /// cannot take a literal away from the key overload: binding one here costs
    /// an optional injection, which ranks below both siblings.
    ///
    /// - Parameter text: The placeholder text, or `nil` for no text.
    /// - Returns: A modified view.
    @_disfavoredOverload
    public func imagePlaceholder(_ text: String?) -> some View {
        environment(\.imagePlaceholderText, text)
    }

    /// Controls whether a spinner is shown while an image is loading.
    ///
    /// On by default. The spinner is a real ``Spinner``, `.dots` unless
    /// ``View/imagePlaceholderSpinner(style:color:)`` chose another: it animates
    /// for as long as the image is loading, at the speed set for spinners with
    /// ``View/indicatorAnimationSpeed(_:for:)``, so a loading image keeps the
    /// animation clock running until its picture arrives. It is drawn in the
    /// colour that modifier gave it, or else in this view's `foregroundStyle`, or
    /// else in the palette's accent. The placeholder text keeps the secondary
    /// foreground either way.
    ///
    /// Pass `false` for a placeholder that does not move: the text alone, or
    /// "Loading..." when there is no text. This sets only whether the spinner is
    /// shown, so a style chosen further out is kept for when it is shown again.
    ///
    /// - Parameter showSpinner: Whether to show a spinner.
    /// - Returns: A modified view.
    public func imagePlaceholderSpinner(_ showSpinner: Bool) -> some View {
        // `transformEnvironment`, not `environment`: this says only WHETHER there is
        // a spinner, so a style or colour chosen further out has to survive it.
        transformEnvironment(\.imagePlaceholderSpinner) { $0.isShown = showSpinner }
    }

    /// Shows a spinner while an image is loading, and chooses which, for every
    /// `Image` in this subtree.
    ///
    /// TUI-specific, like ``View/refreshIndicator(style:color:)``: a spinner here is
    /// a handful of glyphs whose legibility depends on the terminal's font. `.dots`
    /// (Braille) is the default, and `.line` is pure ASCII for a font without
    /// Braille.
    ///
    /// Choosing a style asks for a spinner, so this shows one even inside an outer
    /// `.imagePlaceholderSpinner(false)`. An `.imagePlaceholderSpinner(false)`
    /// inside this one hides it again.
    ///
    /// ```swift
    /// Image(.url(address))
    ///     .imagePlaceholderSpinner(style: .line)   // ASCII, for fonts without Braille
    /// ```
    ///
    /// - Parameters:
    ///   - style: The spinner animation style (default: `.dots`).
    ///   - color: The colour to draw it in, or `nil` for this view's
    ///     `foregroundStyle`, and failing that the palette's accent.
    /// - Returns: A view whose loading images show that spinner.
    public func imagePlaceholderSpinner(style: SpinnerStyle = .dots, color: Color? = nil) -> some View {
        environment(
            \.imagePlaceholderSpinner, ImagePlaceholderSpinner(isShown: true, style: style, color: color))
    }

    /// Sets the reference box this image scales to fit.
    ///
    /// `.fit`/`.fill` (via ``aspectRatio(_:contentMode:)``) decides *how* an image
    /// scales; this decides *which box* it scales to. By default an image that is
    /// not resizable takes its natural size where the terminal's cell size in
    /// points is known (``ImageFitTarget/naturalSize``), and otherwise fits the
    /// size the layout proposes (``ImageFitTarget/proposedSize``) — which inside a
    /// `ScrollView` is unbounded on the scroll axis, so the image renders at full
    /// size and scrolls (inside one that scrolls horizontally, where nothing
    /// bounds it, it fits the viewport). Pass ``ImageFitTarget/proposedSize`` to
    /// fit what is proposed on every terminal. Pass ``ImageFitTarget/viewport`` to fit the enclosing
    /// `ScrollView`'s *visible* area instead: the image fills the viewport at
    /// ``imageZoom(_:)`` `1` and overflows (showing scrollbars) only when zoomed in,
    /// so one fixed view tree goes from "fits exactly" to "scroll around" purely by
    /// changing the zoom.
    ///
    /// - Parameter target: The box to fit within.
    /// - Returns: A modified view.
    public func imageFitTarget(_ target: ImageFitTarget) -> some View {
        environment(\.imageFitTarget, target)
    }

    /// Scales an image by a zoom multiplier on top of its fitted size.
    ///
    /// `1` (the default) renders at the fitted size; `2` doubles it; and so on.
    /// Combine with ``imageFitTarget(_:)`` `.viewport` inside a `ScrollView` to zoom
    /// an image in and out, scrollbars appearing automatically once it exceeds the
    /// viewport. The ASCII conversion re-runs at the zoomed size, so zooming in adds
    /// detail rather than just enlarging cells.
    ///
    /// - Parameter factor: The zoom multiplier. Any positive finite factor is
    ///   honoured up to `64` (the rendered size is floored at one cell, so
    ///   arbitrarily small factors shrink to a single cell); NaN, infinities
    ///   and non-positive values mean `1`.
    /// - Returns: A modified view.
    public func imageZoom(_ factor: Double) -> some View {
        environment(\.imageZoom, factor)
    }

    /// Sets the maximum allowed pixel count for image loading.
    ///
    /// Images with more total pixels than this limit will fail to load
    /// with `ImageLoadError.imageTooLarge`. Use this to prevent excessive
    /// memory usage from very large images.
    ///
    /// ```swift
    /// Image(.url("https://example.com/photo.png"))
    ///     .imageMaxPixelCount(4_000_000)  // ~4 megapixels
    /// ```
    ///
    /// - Parameter maxPixels: The maximum total pixel count, or `nil` for no limit.
    /// - Returns: A modified view.
    public func imageMaxPixelCount(_ maxPixels: Int?) -> some View {
        environment(\.imageMaxPixelCount, maxPixels)
    }

    /// Sets the timeout for URL image downloads.
    ///
    /// If the download does not complete within the specified interval,
    /// it fails with `ImageLoadError.downloadFailed`.
    ///
    /// ```swift
    /// Image(.url("https://example.com/photo.png"))
    ///     .imageURLTimeout(10)  // 10 seconds
    /// ```
    ///
    /// - Parameter seconds: The timeout in seconds (default: 30).
    /// - Returns: A modified view.
    public func imageURLTimeout(_ seconds: TimeInterval) -> some View {
        environment(\.imageURLTimeout, seconds)
    }

    /// Sets the largest image file, in bytes, that is decoded on the frame that
    /// first draws it, so that the picture is there on that frame rather than
    /// a placeholder. A larger file loads in a task, off the frame, and draws
    /// when it has loaded. A TUI-specific modifier: SwiftUI's `Image` of a
    /// local picture draws at once, and has nothing to configure.
    ///
    /// The default, 256 KB, decodes an icon or a small picture in a few
    /// milliseconds, within a frame, so it does not flash in after a
    /// placeholder. 0 keeps every load off the frame: every picture from a file
    /// draws its placeholder first.
    ///
    /// ```swift
    /// PhotoGrid(photos)
    ///     .imageSynchronousDecodeLimit(0)  // never decode on a frame
    /// ```
    ///
    /// A picture the cache already holds draws on its first frame whatever
    /// this says: that is a lookup, not a decode.
    ///
    /// - Parameter bytes: The largest file decoded on the frame; 0 or less
    ///   for none.
    /// - Returns: A modified view.
    public func imageSynchronousDecodeLimit(_ bytes: Int) -> some View {
        environment(\.imageSynchronousDecodeLimit, max(0, bytes))
    }

    /// Sets the cache the images in this view load URLs and files through — in
    /// place of the app's own, which every app has, bounded at
    /// ``URLImageCache/defaultByteLimit``. A file is kept under its path, size
    /// and modification time, so an edited file is read again; a picture the
    /// cache holds draws on a new view's first frame.
    ///
    /// A test that wants a cache nothing else sees, or an app that wants a
    /// different bound for one part of itself, hands its views its own:
    ///
    /// ```swift
    /// Gallery()
    ///     .urlImageCache(URLImageCache(byteLimit: 256 << 20))
    /// ```
    ///
    /// `URLImageCache(byteLimit: 0)` keeps nothing. TUI-specific: SwiftUI's
    /// `AsyncImage` goes through the URL loading system's own cache.
    ///
    /// - Parameter cache: The cache, or `nil` for the app's own.
    /// - Returns: A modified view.
    public func urlImageCache(_ cache: URLImageCache?) -> some View {
        environment(\.urlImageCache, cache)
    }
}
