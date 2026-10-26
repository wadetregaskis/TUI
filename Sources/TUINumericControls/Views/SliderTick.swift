//  🖥️ TUI — A Terminal UI framework for Swift
//  SliderTick.swift
//
//  SwiftUI's slider ticks: marks at values along a slider's track, each with
//  an optional label, built with `@SliderTickBuilder`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - SliderTick

/// A representation of a tick in a slider, with associated value and optional
/// label — mirrors SwiftUI's `SliderTick`.
///
/// ```swift
/// Slider(value: $percentage) {
///     Text("Percentage")
/// } ticks: {
///     SliderTickContentForEach(stride(from: 0.0, through: 1.0, by: 0.25).map { $0 }, id: \.self) {
///         SliderTick($0)
///     }
/// }
/// ```
///
/// A tick is drawn as a mark on the row under the track, and its label, if it
/// has one, on the row under that.
public struct SliderTick<V: BinaryFloatingPoint>: Identifiable {
    /// The value the tick marks.
    let value: V

    /// What is drawn under the mark, if anything.
    let label: AnyView?

    /// The type of value a tick marks.
    public typealias Value = V

    /// A tick is identified by its value.
    public typealias ID = V

    /// The tick's identity: its value.
    public var id: V { value }

    /// Creates an unlabelled slider tick at a specific value.
    ///
    /// - Parameter value: The value to mark.
    public init(_ value: V) {
        self.value = value
        self.label = nil
    }

    /// Creates a labelled slider tick at a specific value.
    ///
    /// - Parameters:
    ///   - value: The value to mark.
    ///   - label: The view drawn under the mark.
    @MainActor
    public init(_ value: V, @ViewBuilder label: () -> some View) {
        self.value = value
        self.label = AnyView(label())
    }

    /// Creates a slider tick with a label from a localized string key.
    ///
    /// - Parameters:
    ///   - titleKey: The key of the label's text.
    ///   - value: The value to mark.
    @MainActor
    public init(_ titleKey: LocalizedStringKey, _ value: V) {
        self.value = value
        self.label = AnyView(Text(titleKey))
    }

    /// Creates a slider tick with a label from a string.
    ///
    /// - Parameters:
    ///   - title: The label's text.
    ///   - value: The value to mark.
    @MainActor @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, _ value: V) {
        self.value = value
        self.label = AnyView(Text(title))
    }
}

/// Ticks compare and order by the values they mark, as SwiftUI's do.
extension SliderTick: Comparable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

// MARK: - Content

/// A type that provides content for a `SliderTickBuilder` — mirrors SwiftUI's
/// `SliderTickContent`.
public protocol SliderTickContent<Value> {
    /// The type of value the ticks mark.
    associatedtype Value: BinaryFloatingPoint

    /// The collection of ticks this content is.
    associatedtype Body: RandomAccessCollection where Body.Element == SliderTick<Value>

    /// The value of this type's content: its ticks.
    var body: Body { get }
}

extension SliderTick: SliderTickContent {
    public typealias Body = [SliderTick<V>]

    /// A tick is content of one tick: itself.
    public var body: [SliderTick<V>] { [self] }
}

/// Several tick contents in a row: what `SliderTickBuilder` makes of a block
/// of them — mirrors SwiftUI's `TupleSliderTickContent`.
@frozen
public struct TupleSliderTickContent<V: BinaryFloatingPoint, T>: SliderTickContent {
    public typealias Value = V
    public typealias Body = [SliderTick<V>]
    public typealias TicksCollection = [SliderTick<V>]

    /// The contents, as a tuple.
    public var value: T

    /// The ticks, in order.
    public let body: [SliderTick<V>]
}

extension Optional: SliderTickContent where Wrapped: SliderTickContent {
    public typealias Value = Wrapped.Value
    public typealias Body = [SliderTick<Wrapped.Value>]
    public typealias TicksCollection = [SliderTick<Wrapped.Value>]

    /// The wrapped content's ticks, or none.
    public var body: [SliderTick<Wrapped.Value>] { map { Array($0.body) } ?? [] }
}

/// One of two contents, chosen by a builder's `if`/`else` — the counterpart of
/// SwiftUI's `_ConditionalContent` for slider ticks.
public enum _ConditionalSliderTickContent<TrueContent: SliderTickContent, FalseContent: SliderTickContent>:
    SliderTickContent
where TrueContent.Value == FalseContent.Value {
    case trueContent(TrueContent)
    case falseContent(FalseContent)

    public typealias Value = TrueContent.Value
    public typealias Body = [SliderTick<TrueContent.Value>]

    public var body: [SliderTick<TrueContent.Value>] {
        switch self {
        case .trueContent(let content): Array(content.body)
        case .falseContent(let content): Array(content.body)
        }
    }
}

/// A type of slider content that creates content by iterating over a
/// collection — mirrors SwiftUI's `SliderTickContentForEach`.
public struct SliderTickContentForEach<Data: RandomAccessCollection, ID: Hashable, Content: SliderTickContent>:
    SliderTickContent
{
    public typealias Value = Content.Value
    public typealias Body = [SliderTick<Content.Value>]

    /// The ticks, computed from the data when the content is made.
    public let body: [SliderTick<Content.Value>]

    /// Creates ticks over identifiable data.
    ///
    /// - Parameters:
    ///   - data: The identified data the ticks are made from.
    ///   - content: The builder that creates ticks for each element.
    public init<V>(_ data: Data, @SliderTickBuilder<V> content: @escaping (Data.Element) -> Content)
    where ID == V.ID, V: Identifiable, V == Data.Element, Data.Element == Content.Value {
        self.body = data.flatMap { Array(content($0).body) }
    }

    /// Creates ticks over a constant range.
    ///
    /// - Parameters:
    ///   - data: A constant range.
    ///   - content: The builder that creates ticks for each index.
    public init<V>(_ data: Range<Int>, @SliderTickBuilder<V> content: @escaping (Range<Int>.Element) -> Content)
    where Data == Range<Int>, ID == Int, V == Content.Value {
        self.body = data.flatMap { Array(content($0).body) }
    }

    /// Creates ticks over data identified by a key path.
    ///
    /// - Parameters:
    ///   - data: The data the ticks are made from.
    ///   - id: The key path to each element's identity.
    ///   - content: The builder that creates ticks for each element.
    public init<V>(
        _ data: Data, id: KeyPath<Data.Element, ID>,
        @SliderTickBuilder<V> content: @escaping (Data.Element) -> Content
    ) where V == Data.Element, Data.Element == Content.Value {
        self.body = data.flatMap { Array(content($0).body) }
    }
}

// MARK: - Builder

/// A result builder for a slider's ticks — mirrors SwiftUI's
/// `SliderTickBuilder`.
@resultBuilder
public struct SliderTickBuilder<V: BinaryFloatingPoint> {
    /// No ticks.
    public static func buildBlock() -> TupleSliderTickContent<V, ()> {
        TupleSliderTickContent(value: (), body: [])
    }

    /// One content's ticks.
    public static func buildBlock<C0: SliderTickContent>(_ c0: C0) -> TupleSliderTickContent<V, C0>
    where C0.Value == V {
        TupleSliderTickContent(value: c0, body: Array(c0.body))
    }

    // SwiftUI's arities, two to ten. Spelled out rather than a parameter pack:
    // a pack cannot yet say "every element's `Value` is `V`" (Swift 6.2: "same-
    // element requirements are not yet supported").
    // swiftlint:disable large_tuple function_parameter_count

    /// The ticks of 2 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent
    >(
        _ c0: C0, _ c1: C1
    ) -> TupleSliderTickContent<V, (C0, C1)>
    where
        C0.Value == V, C1.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        return TupleSliderTickContent(value: (c0, c1), body: ticks)
    }

    /// The ticks of 3 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent, C2: SliderTickContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> TupleSliderTickContent<V, (C0, C1, C2)>
    where
        C0.Value == V, C1.Value == V, C2.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        ticks.append(contentsOf: c2.body)
        return TupleSliderTickContent(value: (c0, c1, c2), body: ticks)
    }

    /// The ticks of 4 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent, C2: SliderTickContent, C3: SliderTickContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> TupleSliderTickContent<V, (C0, C1, C2, C3)>
    where
        C0.Value == V, C1.Value == V, C2.Value == V, C3.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        ticks.append(contentsOf: c2.body)
        ticks.append(contentsOf: c3.body)
        return TupleSliderTickContent(value: (c0, c1, c2, c3), body: ticks)
    }

    /// The ticks of 5 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent, C2: SliderTickContent, C3: SliderTickContent,
        C4: SliderTickContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> TupleSliderTickContent<V, (C0, C1, C2, C3, C4)>
    where
        C0.Value == V, C1.Value == V, C2.Value == V, C3.Value == V, C4.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        ticks.append(contentsOf: c2.body)
        ticks.append(contentsOf: c3.body)
        ticks.append(contentsOf: c4.body)
        return TupleSliderTickContent(value: (c0, c1, c2, c3, c4), body: ticks)
    }

    /// The ticks of 6 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent, C2: SliderTickContent, C3: SliderTickContent,
        C4: SliderTickContent, C5: SliderTickContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
    ) -> TupleSliderTickContent<V, (C0, C1, C2, C3, C4, C5)>
    where
        C0.Value == V, C1.Value == V, C2.Value == V, C3.Value == V, C4.Value == V, C5.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        ticks.append(contentsOf: c2.body)
        ticks.append(contentsOf: c3.body)
        ticks.append(contentsOf: c4.body)
        ticks.append(contentsOf: c5.body)
        return TupleSliderTickContent(value: (c0, c1, c2, c3, c4, c5), body: ticks)
    }

    /// The ticks of 7 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent, C2: SliderTickContent, C3: SliderTickContent,
        C4: SliderTickContent, C5: SliderTickContent, C6: SliderTickContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6
    ) -> TupleSliderTickContent<V, (C0, C1, C2, C3, C4, C5, C6)>
    where
        C0.Value == V, C1.Value == V, C2.Value == V, C3.Value == V, C4.Value == V, C5.Value == V,
        C6.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        ticks.append(contentsOf: c2.body)
        ticks.append(contentsOf: c3.body)
        ticks.append(contentsOf: c4.body)
        ticks.append(contentsOf: c5.body)
        ticks.append(contentsOf: c6.body)
        return TupleSliderTickContent(value: (c0, c1, c2, c3, c4, c5, c6), body: ticks)
    }

    /// The ticks of 8 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent, C2: SliderTickContent, C3: SliderTickContent,
        C4: SliderTickContent, C5: SliderTickContent, C6: SliderTickContent, C7: SliderTickContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7
    ) -> TupleSliderTickContent<V, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where
        C0.Value == V, C1.Value == V, C2.Value == V, C3.Value == V, C4.Value == V, C5.Value == V,
        C6.Value == V, C7.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        ticks.append(contentsOf: c2.body)
        ticks.append(contentsOf: c3.body)
        ticks.append(contentsOf: c4.body)
        ticks.append(contentsOf: c5.body)
        ticks.append(contentsOf: c6.body)
        ticks.append(contentsOf: c7.body)
        return TupleSliderTickContent(value: (c0, c1, c2, c3, c4, c5, c6, c7), body: ticks)
    }

    /// The ticks of 9 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent, C2: SliderTickContent, C3: SliderTickContent,
        C4: SliderTickContent, C5: SliderTickContent, C6: SliderTickContent, C7: SliderTickContent,
        C8: SliderTickContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> TupleSliderTickContent<V, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where
        C0.Value == V, C1.Value == V, C2.Value == V, C3.Value == V, C4.Value == V, C5.Value == V,
        C6.Value == V, C7.Value == V, C8.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        ticks.append(contentsOf: c2.body)
        ticks.append(contentsOf: c3.body)
        ticks.append(contentsOf: c4.body)
        ticks.append(contentsOf: c5.body)
        ticks.append(contentsOf: c6.body)
        ticks.append(contentsOf: c7.body)
        ticks.append(contentsOf: c8.body)
        return TupleSliderTickContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8), body: ticks)
    }

    /// The ticks of 10 contents, in order.
    public static func buildBlock<
        C0: SliderTickContent, C1: SliderTickContent, C2: SliderTickContent, C3: SliderTickContent,
        C4: SliderTickContent, C5: SliderTickContent, C6: SliderTickContent, C7: SliderTickContent,
        C8: SliderTickContent, C9: SliderTickContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9
    ) -> TupleSliderTickContent<V, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where
        C0.Value == V, C1.Value == V, C2.Value == V, C3.Value == V, C4.Value == V, C5.Value == V,
        C6.Value == V, C7.Value == V, C8.Value == V, C9.Value == V
    {
        var ticks: [SliderTick<V>] = []
        ticks.append(contentsOf: c0.body)
        ticks.append(contentsOf: c1.body)
        ticks.append(contentsOf: c2.body)
        ticks.append(contentsOf: c3.body)
        ticks.append(contentsOf: c4.body)
        ticks.append(contentsOf: c5.body)
        ticks.append(contentsOf: c6.body)
        ticks.append(contentsOf: c7.body)
        ticks.append(contentsOf: c8.body)
        ticks.append(contentsOf: c9.body)
        return TupleSliderTickContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9), body: ticks)
    }

    // swiftlint:enable large_tuple function_parameter_count

    /// One content, as written.
    public static func buildExpression<C: SliderTickContent>(_ content: C) -> C where C.Value == V {
        content
    }

    /// An `if` with no `else`: its content, or none.
    public static func buildIf<C: SliderTickContent>(_ content: C?) -> C? where C.Value == V {
        content
    }

    /// The `if` branch of an `if`/`else`.
    public static func buildEither<T: SliderTickContent, F: SliderTickContent>(
        first: T
    ) -> _ConditionalSliderTickContent<T, F> where T.Value == V, F.Value == V {
        .trueContent(first)
    }

    /// The `else` branch of an `if`/`else`.
    public static func buildEither<T: SliderTickContent, F: SliderTickContent>(
        second: F
    ) -> _ConditionalSliderTickContent<T, F> where T.Value == V, F.Value == V {
        .falseContent(second)
    }
}

// MARK: - Resolved

/// A tick as the slider draws it: its position along the bounds, and its
/// label.
struct _SliderTickMark {
    let value: Double
    let label: AnyView?

    init<V: BinaryFloatingPoint>(_ tick: SliderTick<V>) {
        self.value = Double(tick.value)
        self.label = tick.label
    }
}
