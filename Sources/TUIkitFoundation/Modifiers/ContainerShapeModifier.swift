//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerShapeModifier.swift
//
//  `containerShape(_:)`: the shape a container gives the
//  `ContainerRelativeShape`s inside it, and where the container is.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUIkitCore
import TUIkitView

// MARK: - What a container publishes

/// The shape a container gives the container-relative shapes inside it, and
/// the frame it gives it in: where the container is, in the frame of
/// reference its content's carried origins are counted in, and its size.
struct ContainerShapeContext: Equatable, Sendable {
    /// The container's shape.
    let shape: ErasedInsettableShape
    /// The container's carried origin, against which a view inside reads its
    /// offset (`RenderContext.geometryOriginX`).
    let originX: Int
    let originY: Int
    /// The container's size, in cells.
    let columns: Int
    let rows: Int
}

/// An `InsettableShape`, erased: drawn, inset, asked for its box corners, and
/// compared.
///
/// Compared by type and by its path in a fixed square: shapes are not
/// `Equatable`, and an environment value that cannot be compared turns the
/// render memo off below it. Two values that draw the same path there are the
/// same container shape for every purpose a container-relative shape has.
struct ErasedInsettableShape: Equatable, Sendable {
    /// The shape.
    let base: any InsettableShape
    /// Its path in the comparison square.
    private let fingerprint: Path
    /// Its type.
    private let type: ObjectIdentifier

    init<S: InsettableShape>(_ shape: S) {
        base = shape
        fingerprint = shape.path(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        type = ObjectIdentifier(S.self)
    }

    /// The shape inset by `amount`.
    func inset(by amount: CGFloat) -> any Shape {
        base.inset(by: amount)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && lhs.fingerprint == rhs.fingerprint
    }
}

private struct ContainerShapeContextKey: EnvironmentKey {
    static let defaultValue: ContainerShapeContext? = nil
}

extension EnvironmentValues {
    /// The nearest `containerShape(_:)` above, or `nil` outside every one.
    var containerShapeContext: ContainerShapeContext? {
        get { self[ContainerShapeContextKey.self] }
        set { self[ContainerShapeContextKey.self] = newValue }
    }
}

// MARK: - The modifier

extension View {
    /// Sets the container shape to use for any container relative shape
    /// within this view.
    ///
    /// A ``ContainerRelativeShape`` inside is drawn as `shape`, inset by how
    /// far its frame lies inside this view's — so a rounded card's inner
    /// panels round concentrically, and one inset as far as the card's radius
    /// is square:
    ///
    /// ```swift
    /// VStack {
    ///     Text("Inner").padding(1).background(.blue, in: ContainerRelativeShape())
    /// }
    /// .padding(1)
    /// .background(.gray, in: RoundedRectangle(cornerRadius: 3))
    /// .containerShape(RoundedRectangle(cornerRadius: 3))
    /// ```
    ///
    /// - Parameter shape: The shape of this container.
    /// - Returns: The view, a container of that shape.
    public func containerShape<T: InsettableShape>(_ shape: T) -> some View {
        _ContainerShapeView(content: self, shape: ErasedInsettableShape(shape))
    }
}

/// ``View/containerShape(_:)``'s view: its content, told the container's
/// shape, origin and size.
struct _ContainerShapeView<Content: View>: View {
    let content: Content
    let shape: ErasedInsettableShape

    var body: Never { fatalError("_ContainerShapeView renders via Renderable") }
}

extension _ContainerShapeView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Its content's views are told where they sit relative to here: a
        // carried origin, started here unless one is already in force.
        let carried = context.carryingGeometryOrigin()
        let origin = carried.geometryOrigin ?? (x: 0, y: 0)
        // The container's own size, before its content renders: measured as
        // a frame offered this much, a flexible axis taking all of it.
        let size = measureChild(
            content, proposal: ProposedSize(width: context.availableWidth, height: context.availableHeight),
            context: carried)
        let columns = size.isWidthFlexible ? max(size.width, context.availableWidth) : size.width
        let rows = size.isHeightFlexible ? max(size.height, context.availableHeight) : size.height
        let published = carried.publishingContainerShape(
            ContainerShapeContext(
                shape: shape, originX: origin.x, originY: origin.y, columns: columns, rows: rows))
        return TUIkitView.renderToBuffer(content, context: published)
    }
}

extension _ContainerShapeView: Layoutable {
    /// The content's size: a container shape changes nothing about layout.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension RenderContext {
    /// This context with ``EnvironmentValues/containerShapeContext`` set to
    /// `container`, noted with the render cache as an applied environment
    /// value, as ``publishingContainerSize(_:noting:)`` notes a container's
    /// size: a container's size and place change between frames, and a
    /// memoized subtree below that read the old ones has to be dropped.
    func publishingContainerShape(_ container: ContainerShapeContext) -> Self {
        var copy = self
        copy.environment.containerShapeContext = container
        copy.environmentApplicationDepth += 1
        if !isMeasuring, let cache = renderCache,
            case .changed = cache.noteAppliedEnvironment(
                container, identity: identity, keyPath: \EnvironmentValues.containerShapeContext,
                depth: copy.environmentApplicationDepth)
        {
            cache.clearAffected(by: identity)
        }
        return copy
    }
}

// MARK: - The shape a container-relative shape stands for

extension ErasedInsettableShape {
    /// The shape's corner radii in a frame of `size` square units: a rounded
    /// rectangular shape's corners, or the box-drawing tier's; `nil` for a shape
    /// with neither, a circle drawn by the rasterizer.
    func cornerRadii(in size: CGSize) -> RectangleCornerRadii? {
        if let rounded = base as? any RoundedRectangularShape, let corners = rounded.corners(in: size) {
            return corners.radii(container: nil, inset: 0)
        }
        return (base as? any BoxDrawnShape)?.boxCorners(in: CGRect(origin: .zero, size: size))
    }
}

/// A container's shape, as a view inside it draws it: inset by how far the
/// view lies inside the container — the nearest of its four sides — and drawn
/// in a frame grown by the same amount, so the outline sits on the view's frame
/// with every radius shrunk by that distance. Concentric, as SwiftUI's is.
struct ContainerInsetShape: InsettableShape {
    let container: ErasedInsettableShape
    /// How far inside the container the view lies, in square units.
    let distance: CGFloat
    /// How much further this shape is inset, by ``inset(by:)``.
    var extra: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        container.inset(by: distance + extra).path(in: rect.insetBy(dx: -distance, dy: -distance))
    }

    func inset(by amount: CGFloat) -> Self {
        var inset = self
        inset.extra += amount
        return inset
    }
}

extension ContainerInsetShape: BoxDrawnShape {
    /// The container's corners, each shrunk by the distance — square where the
    /// distance has used the radius up.
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        guard extra == 0, container.base is any BoxDrawnShape,
            let radii = container.cornerRadii(in: rect.insetBy(dx: -distance, dy: -distance).size)
        else { return nil }
        let shrink = { (radius: CGFloat) in max(0, radius - distance) }
        return RectangleCornerRadii(
            topLeading: shrink(radii.topLeading), bottomLeading: shrink(radii.bottomLeading),
            bottomTrailing: shrink(radii.bottomTrailing), topTrailing: shrink(radii.topTrailing))
    }
}

extension ContainerShapeContext {
    /// How far inside the container a view `columns` × `rows` at the carried
    /// origin `origin` lies, in square units, rows `aspect` units tall: the
    /// nearest side's distance; none with no carried origin or outside it.
    func distance(ofViewAt origin: (x: Int, y: Int)?, columns viewColumns: Int, rows viewRows: Int, aspect: Double) -> CGFloat {
        guard let origin else { return 0 }
        let left = CGFloat(origin.x - originX)
        let top = CGFloat(origin.y - originY) * CGFloat(aspect)
        let right = CGFloat(originX + columns - origin.x - viewColumns)
        let bottom = CGFloat(originY + rows - origin.y - viewRows) * CGFloat(aspect)
        return max(0, min(left, top, right, bottom))
    }
}

extension ContainerRelativeShape: EnvironmentResolvedShape {
    /// The container's shape, inset concentrically by how far inside it this
    /// view lies; with no container, a rectangle.
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        guard let container = context.environment.containerShapeContext else { return self }
        let distance = container.distance(
            ofViewAt: context.geometryOrigin, columns: columns, rows: rows, aspect: context.environment.imageCellAspect)
        return ContainerInsetShape(container: container.shape, distance: distance, extra: insetAmount)
    }
}
