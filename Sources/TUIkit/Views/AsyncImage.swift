//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AsyncImage.swift
//
//  SwiftUI's `AsyncImage`: an image loaded from a URL, with the loading,
//  success and failure phases handed to the app's own content.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitImage
import TUIkitView

// MARK: - Phase

/// The current phase of the asynchronous image loading operation — mirrors
/// SwiftUI's `AsyncImagePhase`.
public enum AsyncImagePhase: Sendable {
    /// No image is loaded.
    case empty

    /// An image succesfully loaded.
    case success(Image)

    /// An image failed to load with an error.
    case failure(any Error)

    /// The loaded image, if any.
    public var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }

    /// The error that occurred when attempting to load an image, if any.
    public var error: (any Error)? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

/// Pixels already decoded, carried by an ``Image`` so it draws them rather
/// than loading its source again. A reference, so an `Image` carrying one
/// stays cheap to copy.
///
/// Main-actor state in practice — views are built and drawn there — which is
/// what the unchecked `Sendable` rests on, the drawn-out pixels being cached
/// on first use.
final class _DecodedImage: @unchecked Sendable {
    /// What the pixels are drawn out of — a `CGImage` or an `NSImage` — or
    /// `nil` for pixels handed over as they are.
    ///
    /// Its address names the picture in the image's source, and a freed
    /// address can come straight back for a different picture. So the view
    /// keeps the owner it last drew for as long as it keeps that source, and
    /// no other picture can take the address while it does.
    let owner: AnyObject?

    private var drawn: RGBAImage?
    private let draw: () -> RGBAImage

    /// Pixels already decoded.
    init(_ pixels: RGBAImage) {
        self.owner = nil
        self.drawn = pixels
        self.draw = { pixels }
    }

    /// Pixels drawn out of `owner` by `draw`, the first time they are wanted.
    init(owner: AnyObject, draw: @escaping () -> RGBAImage) {
        self.owner = owner
        self.draw = draw
    }

    /// The pixels.
    var pixels: RGBAImage {
        if let drawn { return drawn }
        let pixels = draw()
        drawn = pixels
        return pixels
    }
}

/// Why an ``AsyncImage`` could not load its image.
struct AsyncImageLoadError: Error, CustomStringConvertible {
    let description: String
}

// MARK: - AsyncImage

/// A view that asynchronously loads and displays an image — mirrors SwiftUI's
/// `AsyncImage`.
///
/// ```swift
/// AsyncImage(url: URL(string: "https://example.com/icon.png")) { image in
///     image.resizable()
/// } placeholder: {
///     ProgressView()
/// }
/// .frame(width: 20, height: 10)
/// ```
///
/// The image loads through the same loader and per-session cache as
/// `Image(.url(_:))`, and draws the same way: as cells, fitted to its frame.
/// `scale` is accepted and changes nothing — a TUIkit image is sized by its
/// frame, never by its pixel count, so there is no natural size for a scale to
/// divide.
public struct AsyncImage<Content: View>: View {
    let url: URL?
    let transaction: Transaction
    let content: (AsyncImagePhase) -> Content

    /// Loads and displays an image from the specified URL, drawing nothing
    /// until it loads, and nothing if it fails.
    ///
    /// - Parameters:
    ///   - url: The URL of the image to display, or `nil` for none.
    ///   - scale: The scale the image was made for. Accepted; see the type's
    ///     notes.
    public init(url: URL?, scale: CGFloat = 1) where Content == _AsyncImageDefaultContent {
        self.url = url
        self.transaction = Transaction()
        self.content = { _AsyncImageDefaultContent(phase: $0) }
    }

    /// Loads and displays a modifiable image from the specified URL using a
    /// custom placeholder until the image loads.
    ///
    /// - Parameters:
    ///   - url: The URL of the image to display, or `nil` for none.
    ///   - scale: The scale the image was made for. Accepted; see the type's
    ///     notes.
    ///   - content: A closure that takes the loaded image and returns the view
    ///     to show.
    ///   - placeholder: A closure that returns the view to show until the load
    ///     succeeds — and after it fails.
    public init<I: View, P: View>(
        url: URL?, scale: CGFloat = 1, @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == ConditionalView<I, P> {
        self.url = url
        self.transaction = Transaction()
        self.content = { phase in
            if let image = phase.image { return .trueContent(content(image)) }
            return .falseContent(placeholder())
        }
    }

    /// Loads and displays a modifiable image from the specified URL in phases.
    ///
    /// - Parameters:
    ///   - url: The URL of the image to display, or `nil` for none.
    ///   - scale: The scale the image was made for. Accepted; see the type's
    ///     notes.
    ///   - transaction: The transaction to use when the phase changes.
    ///   - content: A closure that takes the load phase and returns the view to
    ///     show for it.
    public init(
        url: URL?, scale: CGFloat = 1, transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.transaction = transaction
        self.content = content
    }

    public var body: some View {
        _AsyncImageCore(url: url, transaction: transaction, content: content)
    }
}

/// What a plain `AsyncImage(url:)` draws: the image once it loads, and
/// nothing before or after a failure.
public struct _AsyncImageDefaultContent: View {
    let phase: AsyncImagePhase

    public var body: some View {
        if let image = phase.image {
            image
        }
    }
}

// MARK: - Core

/// The async image core's state slots, out of the generic type, which cannot
/// hold static stored properties.
private enum AsyncImageStateIndex {
    static let phase = 0
    static let lastURL = 1
}

/// The load: the phase kept at the view's identity, a load started when the
/// view first appears (and again when its URL changes), and the app's content
/// for the current phase drawn as its child.
private struct _AsyncImageCore<Content: View>: View, Renderable, Layoutable {
    let url: URL?
    let transaction: Transaction
    let content: (AsyncImagePhase) -> Content

    private typealias StateIndex = AsyncImageStateIndex

    /// The phase as stored: pixels rather than an `Image`, so a later frame
    /// makes the image afresh from what was loaded.
    enum Stored: Sendable {
        case empty
        case loaded(_DecodedImage, String)
        case failed(String)
    }

    var body: Never { fatalError("_AsyncImageCore renders via Renderable") }

    private func phase(_ stored: Stored) -> AsyncImagePhase {
        switch stored {
        case .empty:
            return .empty
        case .loaded(let pixels, let address):
            var image = Image(.url(address))
            image.decoded = pixels
            return .success(image)
        case .failed(let message):
            return .failure(AsyncImageLoadError(description: message))
        }
    }

    private func stored(_ context: RenderContext) -> StateBox<Stored>? {
        context.stateStorage?.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.phase),
            default: Stored.empty)
    }

    private func childContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(type: Content.self, index: 0)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let current = stored(context)?.value ?? .empty
        return measureChild(content(phase(current)), proposal: proposal, context: childContext(context))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let box = stored(context) else {
            return TUIkitView.renderToBuffer(content(.empty), context: childContext(context))
        }
        // Kept from frame to frame, as any view's state is while it is drawn:
        // without this the pass drops the boxes, the next frame reads a new URL,
        // and the load is cancelled and started again for ever.
        context.stateStorage?.markActive(context.identity)
        if !context.isMeasuring, let lifecycle = context.environment.lifecycle {
            // A render-pass side effect, declared as `Image`'s own load is.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            manageLoad(box: box, lifecycle: lifecycle, context: context)
        }
        return TUIkitView.renderToBuffer(content(phase(box.value)), context: childContext(context))
    }

    /// Starts the load on first appearance or a new URL, publishes its result
    /// under the transaction, and cancels it when the view disappears.
    private func manageLoad(box: StateBox<Stored>, lifecycle: LifecycleManager, context: RenderContext) {
        let token = "async-image-\(context.identity.path)"
        let lastURLBox: StateBox<URL?> = context.stateStorage!.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.lastURL),
            default: nil)
        if lastURLBox.value != url {
            lifecycle.cancelTask(token: token)
            lifecycle.resetAppearance(token: token)
            if case .empty = box.value {} else { box.value = .empty }
            lastURLBox.value = url
        }
        guard !lifecycle.hasAppeared(token: token) else {
            _ = lifecycle.recordAppear(token: token) {}
            return
        }
        _ = lifecycle.recordAppear(token: token) {}
        lifecycle.registerDisappear(token: token) { [lifecycle] in lifecycle.cancelTask(token: token) }
        guard let url else { return }
        let address = url.absoluteString
        let timeout = context.environment.imageURLTimeout
        let maxPixels = context.environment.imageMaxPixelCount
        let transaction = self.transaction
        lifecycle.startTask(token: token, priority: .userInitiated) {
            guard let loaded = await _ImageCore.loadPhase(
                source: .url(address), maxPixelCount: maxPixels, urlTimeout: timeout)
            else { return }
            await MainActor.run {
                // As `Image`'s load: a cancellation that arrives during the hop
                // is honoured here, last, before the write.
                guard !Task.isCancelled else { return }
                let next: Stored
                switch loaded {
                case .success(let pixels): next = .loaded(_DecodedImage(pixels), address)
                case .failure(let message): next = .failed(message)
                case .loading: return
                }
                withTransaction(transaction) { box.value = next }
            }
        }
    }
}
