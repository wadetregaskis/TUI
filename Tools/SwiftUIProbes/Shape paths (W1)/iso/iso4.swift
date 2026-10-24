@MainActor public protocol View { associatedtype Body: View; var body: Body { get } }
extension Never: View { public var body: Never { fatalError() } }
@MainActor public protocol Animatable { var data: Double { get set } }
@MainActor public protocol Renderable { func render() -> Int }
@MainActor func mainOnly() -> Int { 1 }
public nonisolated protocol Shape: Sendable, Animatable, View {
    func path(in rect: Double) -> [Double]
}
extension Shape {
    @MainActor public var body: FillView<Self> { FillView(shape: self) }
    public func fill() -> FillView<Self> { FillView(shape: self) }
}
public nonisolated struct FillView<S: Shape>: View {
    public let shape: S
    public init(shape: S) { self.shape = shape }
    @MainActor public var body: Core<S> { Core(shape: shape) }
}
public struct Core<S: Shape>: View, Renderable {
    let shape: S
    public var body: Never { fatalError() }
    public func render() -> Int { mainOnly() + shape.path(in: 1).count }
}
public struct Rect: Shape {
    public init() {}
    public func path(in rect: Double) -> [Double] { [rect] }
    public var data: Double { get { 0 } set {} }
}
struct Key { static let value = Rect() ; static let filled = Rect().fill() }
func nonisolatedUse() -> [Double] { Rect().path(in: 2) }
struct Custom: Shape {
    var data: Double = 0
    func path(in rect: Double) -> [Double] { [rect * 2] }
}
nonisolated func useCustom() -> Int { Custom().fill().shape.path(in: 1).count }
@MainActor func render<S: Shape>(_ s: S) -> Int { s.body.body.render() }
