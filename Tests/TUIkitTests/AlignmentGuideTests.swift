//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuideTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A custom guide one third of the way across, to prove the model is genuinely
/// extensible rather than three built-ins in a trench coat.
private enum OneThird: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double {
        Double(context.width) / 3
    }
}

extension HorizontalAlignment {
    fileprivate static let oneThird = Self(OneThird.self)
}

/// A guide whose rule produces a value that is not a coordinate. Nobody writes
/// `.infinity` on purpose; dividing by a dimension that is legitimately zero —
/// `childOffset` measures on ONE axis, so the other is always zero — is how an
/// app arrives at one by accident.
private enum ZeroDivideID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double {
        Double(context.width) / Double(context.height)
    }
}

extension HorizontalAlignment {
    fileprivate static let zeroDivide = Self(ZeroDivideID.self)
}

/// What a guide that is a logic error reported (`AlignmentGuideRun.guideErrorReporter`):
/// each distinct message once, in order, as `SoftTrap`'s log keeps them.
///
/// `@unchecked Sendable` because the reporter closure must be `@Sendable`, but
/// only the main-actor test that binds it ever touches it.
private final class GuideErrorReports: @unchecked Sendable {
    private(set) var messages: [String] = []

    func append(_ message: String) {
        if !messages.contains(message) { messages.append(message) }
    }
}

/// `body`'s result, and what a guide that is a logic error reported while it
/// ran — through the task-local seam, so a debug build does not stop at the
/// assertion.
@MainActor
func collectingGuideErrors<T>(_ body: () -> T) -> (T, [String]) {
    let reports = GuideErrorReports()
    let result = AlignmentGuideRun.$guideErrorReporter.withValue({ reports.append($0) }, operation: body)
    return (result, reports.messages)
}

extension VerticalAlignment {
    fileprivate static let zeroDivide = Self(ZeroDivideID.self)
}

/// `HorizontalAlignment` and `VerticalAlignment` are SwiftUI-shaped structs over
/// ``AlignmentID`` rather than closed enums, so apps can define their own
/// guides.
///
/// The property that made this safe to do at all: a guide value is **fractional
/// even though every size and position is a whole cell**. Guides are only ever
/// subtracted from one another and floored, and flooring does not distribute
/// over subtraction — whole-cell guides would have silently moved 190 of 820
/// centring cases by a cell.
@Suite("Alignment guides")
struct AlignmentGuideTests {

    @Test("Guide subtraction reproduces the previous centring rule exactly")
    func centringIsUnchanged() {
        // The rule TUIkit used before guides existed, checked exhaustively
        // rather than at a few sample points — this is the whole reason guide
        // values are fractional.
        for total in 0...40 {
            for child in 0...total {
                #expect(
                    HorizontalAlignment.center.childOffset(childWidth: child, in: total)
                        == (total - child) / 2)
                #expect(
                    VerticalAlignment.center.childOffset(childHeight: child, in: total)
                        == (total - child) / 2)
            }
        }
    }

    @Test("Whole-cell guides would NOT have reproduced it")
    func wholeCellGuidesWouldDiverge() {
        // Pins the reason rather than the result: if someone later "simplifies"
        // the guide type to Int, this is the case that catches it.
        let total = 10, child = 3
        #expect(total / 2 - child / 2 != (total - child) / 2)
        #expect(HorizontalAlignment.center.childOffset(childWidth: child, in: total) == 3)
    }

    @Test("Leading and trailing place flush, and clamp on an oversized child")
    func edgesAndClamping() {
        #expect(HorizontalAlignment.leading.childOffset(childWidth: 3, in: 10) == 0)
        #expect(HorizontalAlignment.trailing.childOffset(childWidth: 3, in: 10) == 7)
        // A child wider than its region cannot be pushed off the leading edge.
        #expect(HorizontalAlignment.trailing.childOffset(childWidth: 20, in: 10) == 0)
        #expect(VerticalAlignment.bottom.childOffset(childHeight: 20, in: 10) == 0)
    }

    @Test("A custom AlignmentID places children by its own rule")
    func customGuidePlaces() {
        // Region guide 12/3 = 4, child guide 3/3 = 1 → offset 3.
        #expect(HorizontalAlignment.oneThird.childOffset(childWidth: 3, in: 12) == 3)
        // And it is a distinct guide, not equal to any built-in.
        #expect(HorizontalAlignment.oneThird != .center)
        #expect(HorizontalAlignment.oneThird != .leading)
    }

    @Test("Alignments compare by their defining AlignmentID")
    func equalityIsByIdentity() {
        // Two separately constructed values over the same AlignmentID must be
        // equal — the property a closed enum gave for free and a struct does not.
        #expect(HorizontalAlignment(OneThird.self) == HorizontalAlignment.oneThird)
        let rebuilt = VerticalAlignment(OneThird.self)
        #expect(rebuilt == VerticalAlignment(OneThird.self))
        #expect(VerticalAlignment.top != VerticalAlignment.bottom)
    }

    @Test("ViewDimensions reports guide positions")
    func viewDimensionsSubscripts() {
        let dimensions = ViewDimensions(width: 10, height: 5)
        #expect(dimensions.width == 10)
        #expect(dimensions.height == 5)
        #expect(dimensions[HorizontalAlignment.leading] == 0)
        #expect(dimensions[HorizontalAlignment.center] == 5)
        #expect(dimensions[HorizontalAlignment.trailing] == 10)
        #expect(dimensions[VerticalAlignment.top] == 0)
        #expect(dimensions[VerticalAlignment.bottom] == 5)

        // Fractional where the cell count is odd — the value that never
        // survives to a coordinate.
        #expect(ViewDimensions(width: 3, height: 0)[HorizontalAlignment.center] == 1.5)
    }

    @Test("Text baselines are the first and last rows")
    func textBaselines() {
        // A terminal cell has no interior baseline, so a line's baseline is the
        // line. `.lastTextBaseline` on an empty view must not go negative.
        let threeLines = ViewDimensions(width: 0, height: 3)
        #expect(threeLines[VerticalAlignment.firstTextBaseline] == 0)
        #expect(threeLines[VerticalAlignment.lastTextBaseline] == 2)
        #expect(ViewDimensions(width: 0, height: 0)[VerticalAlignment.lastTextBaseline] == 0)
    }

    /// The six `Alignment` presets that pair an edge with a baseline. They are
    /// pure combinations, so what is worth pinning is that each pairs the two
    /// alignments its NAME claims — a transposed pair would compile, and would
    /// then quietly align a label to the wrong end of the paragraph.
    @Test("Baseline Alignment presets pair the alignments they are named for")
    func baselineAlignmentPresets() {
        let cases: [(Alignment, HorizontalAlignment, VerticalAlignment)] = [
            (.leadingFirstTextBaseline, .leading, .firstTextBaseline),
            (.centerFirstTextBaseline, .center, .firstTextBaseline),
            (.trailingFirstTextBaseline, .trailing, .firstTextBaseline),
            (.leadingLastTextBaseline, .leading, .lastTextBaseline),
            (.centerLastTextBaseline, .center, .lastTextBaseline),
            (.trailingLastTextBaseline, .trailing, .lastTextBaseline),
        ]
        for (alignment, horizontal, vertical) in cases {
            #expect(alignment.horizontal == horizontal)
            #expect(alignment.vertical == vertical)
        }
        // And that they are genuinely distinct from the box-edge presets they
        // sit beside: `.leading` centres vertically, this one does not.
        #expect(Alignment.leadingFirstTextBaseline != Alignment.leading)
    }

    @Test("No guide set explicitly reads back as nil")
    func explicitGuidesAbsentByDefault() {
        let dimensions = ViewDimensions(width: 10, height: 5)
        #expect(dimensions[explicit: HorizontalAlignment.center] == nil)
        #expect(dimensions[explicit: VerticalAlignment.top] == nil)
    }

    // MARK: - Values that are not coordinates

    /// A guide is caller arithmetic, so it can be anything a `Double` holds.
    /// Resolving one used to reach `Int(_: Double)`, which traps on NaN, on
    /// either infinity and on any magnitude past `Int`'s range — and it fired
    /// on the child that SET the guide, whose own base is `merged - guide`,
    /// i.e. `∞ - ∞`.
    @Test(
        "A guide that is not a coordinate resolves instead of trapping",
        arguments: [
            [Double.infinity, 0], [-.infinity, 0], [0, .infinity], [.nan, 0], [0, .nan],
            [1e300, 0], [-1e300, 0],
        ])
    func nonCoordinateGuideResolves(resolved: [Double]) {
        var reports: [String] = []
        let run = AlignmentGuideRun.resolve(
            resolved: resolved, sizes: [3, 3], fixedExtent: nil, minimumExtent: 0,
            report: { reports.append($0) }, regionGuide: { Double($0) / 2 })
        #expect(run.offsets.count == 2)
        // A finite guide is used as given, as SwiftUI's is, so what bounds the
        // run is how far one guide falling short of another pushes a child —
        // `maximumPush` cells. Past it, the runaway guide is taken as its
        // view's own origin, as a non-finite one is, so nothing is pushed at
        // all: the run is its views' width, not a buffer `Int.max` (or a
        // million) cells wide.
        #expect(run.extent == 3, "extent \(run.extent)")
        #expect(run.offsets == [0, 0], "offsets \(run.offsets)")
        // `resolve` reports only the push; a non-finite guide is reported
        // where its view's size is known (`checkedGuide`).
        #expect(reports.count == (resolved.allSatisfy(\.isFinite) ? 1 : 0), "reports \(reports)")
    }

    @Test("The single-child placement path places one too")
    func nonCoordinateGuidePlacement() {
        // `.frame(alignment:)` / `.overlay(alignment:)`: one guide in a region
        // whose extent is already decided, the view at the region's guide
        // less its own. A guide that is not a number, or one a runaway
        // distance off, is the view's own origin: the view sits on the
        // region's guide, and the runaway is reported.
        for guide in [Double.infinity, -.infinity, .nan, 1e300, -1e300] {
            var reports: [String] = []
            let offset = AlignmentGuideRun.place(
                guide: guide, regionGuide: 5, extent: 10, report: { reports.append($0) })
            #expect(offset == 5, "guide \(guide) -> \(offset)")
            #expect(reports.count == (guide.isFinite ? 1 : 0), "guide \(guide) -> \(reports)")
        }
        // Inside or out, a finite guide is used as given (SwiftUI's rule).
        #expect(AlignmentGuideRun.place(guide: 25, regionGuide: 0, extent: 20, report: nil) == -25)
        #expect(AlignmentGuideRun.place(guide: 0, regionGuide: 20, extent: 20, report: nil) == 20)
        #expect(AlignmentGuideRun.place(guide: 2.5, regionGuide: 10, extent: 20, report: nil) == 7)
        // A runaway region guide (a custom `AlignmentID`) is held to the bound.
        #expect(
            AlignmentGuideRun.place(guide: 0, regionGuide: 1e300, extent: 20, report: nil)
                == AlignmentGuideRun.maximumPush)
    }

    @Test("The push bound is 2^20 cells, and TUIKIT_MAX_ALIGNMENT_PUSH overrides it")
    func maximumPushAndItsOverride() {
        #expect(AlignmentGuideRun.defaultMaximumPush == 1_048_576)
        #expect(AlignmentGuideRun.maximumPush(environment: [:]) == 1_048_576)
        #expect(AlignmentGuideRun.maximumPush(environment: ["TUIKIT_MAX_ALIGNMENT_PUSH": "5000000"]) == 5_000_000)
        #expect(AlignmentGuideRun.maximumPush(environment: ["TUIKIT_MAX_ALIGNMENT_PUSH": " 12 "]) == 12)
        // Held to 2^30, so a pushed run's extent still fits a 32-bit `Int`.
        #expect(
            AlignmentGuideRun.maximumPush(environment: ["TUIKIT_MAX_ALIGNMENT_PUSH": "\(Int.max)"]) == 1 << 30)
        for unusable in ["0", "-5", "lots", "", "1e9"] {
            #expect(
                AlignmentGuideRun.maximumPush(environment: ["TUIKIT_MAX_ALIGNMENT_PUSH": unusable]) == 1_048_576,
                "\(unusable)")
        }
    }

    @Test("A push under the bound is honoured however far past the screen it goes")
    @MainActor
    func pushUnderTheBound() {
        // The canvas the old 4,096-cell bound hid (decisions B-GUIDE-2): items
        // placed down a `ZStack` by guide, for a vertical `ScrollView`.
        // SwiftUI puts the item at row 10,000 and the canvas is 10,001 rows
        // (measured, `Tools/SwiftUIProbes/Alignment guides`, GUIDE2 `g2b`).
        let canvas = ZStack(alignment: .topLeading) {
            Text("a")
            Text("b").alignmentGuide(.top) { _ in -10_000 }
        }
        let context = makeBareRenderContext(width: 10, height: 4)
        let tall = measureNaturalExtent(
            canvas, along: .vertical, proposal: ProposedSize(width: 10, height: nil),
            context: context, startingBudget: naturalExtentStartingBudget(forVisible: 4))
        #expect(tall.height == 10_001)

        var roomy = context
        roomy.availableHeight = 10_001
        let buffer = renderToBuffer(canvas, context: roomy)
        #expect(buffer.height == 10_001)
        #expect(buffer.lines.first?.stripped.hasPrefix("a") == true)
        #expect(buffer.lines.last?.stripped.hasPrefix("b") == true)

        // And sideways: a leading guide of a million (under 2^20) indents the
        // sibling a million cells, which the ideal width reports.
        let column = VStack(alignment: .leading, spacing: 0) {
            Text("g").alignmentGuide(.leading) { _ in 1e6 }
            Text("ssssss")
        }
        let ideal = measureNaturalExtent(
            column, along: .horizontal, proposal: ProposedSize(width: nil, height: nil),
            context: makeBareRenderContext(width: 30, height: 4),
            startingBudget: naturalExtentStartingBudget(forVisible: 30))
        #expect(ideal.width == 1_000_006)
    }

    @Test("A push past the bound is reported, and its guide taken as its view's origin")
    @MainActor
    func guidePastThePushBound() {
        // `1e300` is a runaway expression, not a position. It is reported, and
        // its view placed as if it had no guide: the column draws both views
        // at its leading edge, and asked its ideal width it answers the views'
        // own, rather than a million cells (or `Int.max`, which trapped).
        for guide in [1e300, -1e300, Double(AlignmentGuideRun.maximumPush) + 1] {
            let column = VStack(alignment: .leading, spacing: 0) {
                Text("g").alignmentGuide(.leading) { _ in guide }
                Text("ssssss")
            }
            let context = makeBareRenderContext(width: 30, height: 4)
            let (buffer, reports) = collectingGuideErrors { renderToBuffer(column, context: context) }
            #expect(reports == [AlignmentGuideRun.pushPastTheBoundMessage(bound: AlignmentGuideRun.maximumPush)])
            #expect(buffer.lines.map(\.stripped) == ["g     ", "ssssss"], "guide \(guide)")

            let (ideal, measureReports) = collectingGuideErrors {
                measureNaturalExtent(
                    column, along: .horizontal, proposal: ProposedSize(width: nil, height: nil),
                    context: context, startingBudget: naturalExtentStartingBudget(forVisible: 30))
            }
            #expect(ideal.width == 6, "guide \(guide) -> ideal \(ideal.width)")
            #expect(measureReports.isEmpty, "a measure pass reports nothing: \(measureReports)")
        }

        // The runaway is the guide furthest from its own origin, not whichever
        // falls short: a legitimate canvas row keeps its place beside it.
        let canvas = ZStack(alignment: .topLeading) {
            Text("a")
            Text("b").alignmentGuide(.top) { _ in -3 }
            Text("c").alignmentGuide(.top) { _ in -1e300 }
        }
        let (rows, reports) = collectingGuideErrors {
            renderToBuffer(canvas, context: makeBareRenderContext(width: 10, height: 10))
        }
        #expect(reports.count == 1)
        #expect(rows.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } == ["c", "", "", "b"])
    }

    @Test("A run with many runaways takes each as its origin in one pass, and reports the run once")
    func manyRunawaysInOnePass() {
        // A canvas whose rows are a thousand cells apart (a unit mix-up):
        // rows up to 1,048 fit the bound beside row 0, and every row past
        // them is a runaway. Taken one at a time with a rescan each, the
        // 951 of them were reported 951 times and cost a pass over the run
        // each; a canvas of 20,000 such rows cost about 10^9 comparisons a
        // resolve.
        let rows = 2_000
        var reports = 0
        let run = AlignmentGuideRun.resolve(
            resolved: (0..<rows).map { -Double($0) * 1_000 }, sizes: Array(repeating: 1, count: rows),
            fixedExtent: nil, minimumExtent: 1, report: { _ in reports += 1 }, regionGuide: { _ in 0 })
        let kept = AlignmentGuideRun.maximumPush / 1_000
        #expect(reports == 1)
        #expect(Array(run.offsets.prefix(kept + 1)) == (0...kept).map { $0 * 1_000 })
        #expect(run.offsets.dropFirst(kept + 1).allSatisfy { $0 == 0 })
        #expect(run.extent == kept * 1_000 + 1)
    }

    @Test("A guide that is not a number is reported on a view with a width and a height, and only there")
    @MainActor
    func nonFiniteGuideReports() {
        for guide in [Double.nan, .infinity, -.infinity] {
            let column = VStack(alignment: .leading, spacing: 0) {
                Text("g").alignmentGuide(.leading) { _ in guide }
                Text("ssssss")
            }
            let context = makeBareRenderContext(width: 30, height: 4)
            let (buffer, reports) = collectingGuideErrors { renderToBuffer(column, context: context) }
            #expect(reports == [AlignmentGuideRun.nonFiniteGuideMessage(guide)], "guide \(guide)")
            #expect(buffer.lines.map(\.stripped) == ["g     ", "ssssss"], "guide \(guide)")

            let (_, measureReports) = collectingGuideErrors {
                measureChild(column, proposal: ProposedSize(width: 30, height: 4), context: context)
            }
            #expect(measureReports.isEmpty, "a measure pass reports nothing: \(measureReports)")
        }

        // `d.width / d.height` on a view a small terminal squeezed to no
        // height is legitimately infinite: placed at its origin, silently.
        let squeezed = HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: 2, height: 0).alignmentGuide(.top) { d in Double(d.width) / Double(d.height) }
            Text("b")
        }
        let (_, reports) = collectingGuideErrors {
            renderToBuffer(squeezed, context: makeBareRenderContext(width: 10, height: 2))
        }
        #expect(reports.isEmpty, "\(reports)")
    }

    @Test("A custom AlignmentID that answers with NaN or infinity still places")
    func nonCoordinateCustomAlignmentID() {
        // No `.alignmentGuide` involved: `childOffset` subtracts two
        // caller-supplied defaults and converted the difference the same way.
        #expect((0...7).contains(HorizontalAlignment.zeroDivide.childOffset(childWidth: 3, in: 10)))
        #expect((0...10).contains(HorizontalAlignment.zeroDivide.childOffset(childWidth: 0, in: 10)))
        #expect((0...7).contains(VerticalAlignment.zeroDivide.childOffset(childHeight: 3, in: 10)))
    }

    @Test("An explicit guide overrides the default")
    func explicitGuideOverrides() {
        let dimensions = ViewDimensions(
            width: 10, height: 5,
            explicitGuides: [HorizontalAlignment.center.key: 2])
        #expect(dimensions[HorizontalAlignment.center] == 2)
        #expect(dimensions[explicit: HorizontalAlignment.center] == 2)
        // Untouched guides still answer their default.
        #expect(dimensions[HorizontalAlignment.leading] == 0)
    }

    @Test("Explicit values combine by their mean, ignoring views that give none")
    func combineExplicitMean() {
        #expect(HorizontalAlignment.center.combineExplicit([2.0, nil, 6.0]) == 4)
        #expect(VerticalAlignment.top.combineExplicit([1.0, 3.0]) == 2)
        #expect(HorizontalAlignment.leading.combineExplicit([Double?.none, nil]) == nil)
        #expect(HorizontalAlignment.leading.combineExplicit([Double?]()) == nil)
    }

    @Test("A text baseline keeps the line it names: first is the topmost, last the lowest")
    func combineExplicitBaselines() {
        #expect(VerticalAlignment.firstTextBaseline.combineExplicit([3.0, nil, 1.0, 2.0]) == 1)
        #expect(VerticalAlignment.lastTextBaseline.combineExplicit([3.0, nil, 1.0, 2.0]) == 3)
    }
}
