//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollFitBaselineTable.swift
//
//  What every content-sized view and space-filler got on 2026-11-11, at
//  60 × 24, before the SCROLL-FIT ruling changes it: the table
//  `ScrollFitBaselineTests` checks. The lanes that build SCROLL-FIT update
//  the rows they change, on purpose, row by row; the report
//  `Documentation/Working notes/plan/SCROLL-FIT-baseline.md` reads them.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One row of the baseline: a view, where it is, how many rows it has, and
/// what it got.
struct ScrollFitBaselineRow: Sendable, CustomStringConvertible {
    let subject: ScrollFitSubject
    let situation: ScrollFitSituation
    let rows: Int
    /// The size the view came out at, `WIDTHxHEIGHT`; the second copy's in
    /// `.twoStacked`, `-` elsewhere.
    let sizeA: String
    let sizeB: String
    /// Whether its last row came on screen as the wheel turned over the
    /// screen's middle, five ticks (fifteen lines) a frame: `Y` or `n`, a
    /// second letter for the second copy.
    let reached: String
    /// Whether the first frame showed a scroll indicator (▲ ▼) left of the
    /// screen's last column: a bar of the view's own, not the page's.
    let ownBar: Bool

    var description: String { "\(subject.rawValue) \(situation.rawValue) \(rows)" }
}

enum ScrollFitBaseline {
    /// subject, situation, rows, size, second copy's size, reached, own bar.
    /// Views with no rows of their own (pictures and fillers) are listed at 3.
    static let table = """
        table                alone       3   60x6     -        Y   n
        table                underTitle  3   60x6     -        Y   n
        table                twoStacked  3   60x6     60x6     YY  n
        table                fixedSize   3   60x6     -        Y   n
        table                horizontal  3   60x24    -        Y   n
        table                alone       60  60x24    -        Y   Y
        table                underTitle  60  59x24    -        Y   Y
        table                twoStacked  60  59x24    59x24    YY  Y
        table                fixedSize   60  60x63    -        n   n
        table                horizontal  60  59x63    -        Y   n
        listPlain            alone       3   59x4096  -        Y   n
        listPlain            underTitle  3   59x4095  -        Y   n
        listPlain            twoStacked  3   59x2048  59x2048  YY  n
        listPlain            fixedSize   3   60x23    -        Y   n
        listPlain            horizontal  3   59x4096  -        Y   n
        listPlain            alone       60  59x4096  -        Y   n
        listPlain            underTitle  60  59x4095  -        Y   n
        listPlain            twoStacked  60  59x2048  59x2048  YY  n
        listPlain            fixedSize   60  60x23    -        Y   Y
        listPlain            horizontal  60  59x4096  -        Y   n
        listSectioned        alone       3   59x4096  -        Y   n
        listSectioned        underTitle  3   59x4095  -        Y   n
        listSectioned        twoStacked  3   59x2048  59x2048  YY  n
        listSectioned        fixedSize   3   60x23    -        Y   n
        listSectioned        horizontal  3   59x4096  -        Y   n
        listSectioned        alone       60  59x4096  -        Y   n
        listSectioned        underTitle  60  59x4095  -        Y   n
        listSectioned        twoStacked  60  59x2048  59x2048  YY  n
        listSectioned        fixedSize   60  60x23    -        Y   Y
        listSectioned        horizontal  60  59x4096  -        Y   n
        listOutline          alone       3   59x4096  -        Y   n
        listOutline          underTitle  3   59x4095  -        Y   n
        listOutline          twoStacked  3   59x2048  59x2048  YY  n
        listOutline          fixedSize   3   60x23    -        Y   n
        listOutline          horizontal  3   59x4096  -        Y   n
        listOutline          alone       60  59x4096  -        Y   n
        listOutline          underTitle  60  59x4095  -        Y   n
        listOutline          twoStacked  60  59x2048  59x2048  YY  n
        listOutline          fixedSize   60  60x23    -        Y   Y
        listOutline          horizontal  60  59x4096  -        Y   n
        formGrouped          alone       3   60x24    -        Y   n
        formGrouped          underTitle  3   60x23    -        Y   n
        formGrouped          twoStacked  3   60x12    60x12    YY  n
        formGrouped          fixedSize   3   60x5     -        Y   n
        formGrouped          horizontal  3   60x24    -        Y   n
        formGrouped          alone       60  59x119   -        Y   n
        formGrouped          underTitle  60  59x119   -        Y   n
        formGrouped          twoStacked  60  59x119   59x119   YY  n
        formGrouped          fixedSize   60  60x119   -        n   n
        formGrouped          horizontal  60  59x119   -        Y   n
        formColumns          alone       3   5x3      -        Y   n
        formColumns          underTitle  3   5x3      -        Y   n
        formColumns          twoStacked  3   5x3      5x3      YY  n
        formColumns          fixedSize   3   5x3      -        Y   n
        formColumns          horizontal  3   5x3      -        Y   n
        formColumns          alone       60  6x60     -        Y   n
        formColumns          underTitle  60  6x60     -        Y   n
        formColumns          twoStacked  60  6x60     6x60     YY  n
        formColumns          fixedSize   60  6x60     -        n   n
        formColumns          horizontal  60  6x60     -        Y   n
        textEditor           alone       3   60x24    -        Y   n
        textEditor           underTitle  3   60x23    -        Y   n
        textEditor           twoStacked  3   60x12    60x12    YY  n
        textEditor           fixedSize   3   60x3     -        Y   n
        textEditor           horizontal  3   60x24    -        Y   n
        textEditor           alone       60  59x60    -        Y   n
        textEditor           underTitle  60  59x60    -        Y   n
        textEditor           twoStacked  60  59x60    59x60    YY  n
        textEditor           fixedSize   60  60x60    -        n   n
        textEditor           horizontal  60  59x60    -        Y   n
        scrollSameAxis       alone       3   60x24    -        Y   n
        scrollSameAxis       underTitle  3   60x23    -        Y   n
        scrollSameAxis       twoStacked  3   60x12    60x12    YY  n
        scrollSameAxis       fixedSize   3   60x3     -        Y   n
        scrollSameAxis       horizontal  3   60x24    -        Y   n
        scrollSameAxis       alone       60  59x60    -        Y   n
        scrollSameAxis       underTitle  60  59x60    -        Y   n
        scrollSameAxis       twoStacked  60  59x60    59x60    YY  n
        scrollSameAxis       fixedSize   60  60x60    -        n   n
        scrollSameAxis       horizontal  60  59x60    -        Y   n
        scrollCrossAxis      alone       3   60x24    -        Y   n
        scrollCrossAxis      underTitle  3   60x23    -        Y   n
        scrollCrossAxis      twoStacked  3   60x12    60x12    YY  n
        scrollCrossAxis      fixedSize   3   60x3     -        Y   n
        scrollCrossAxis      horizontal  3   60x24    -        Y   n
        scrollCrossAxis      alone       60  59x60    -        Y   n
        scrollCrossAxis      underTitle  60  59x60    -        Y   n
        scrollCrossAxis      twoStacked  60  59x60    59x60    YY  n
        scrollCrossAxis      fixedSize   60  60x60    -        n   n
        scrollCrossAxis      horizontal  60  59x60    -        Y   n
        lazyVStack           alone       3   60x3     -        Y   n
        lazyVStack           underTitle  3   5x3      -        Y   n
        lazyVStack           twoStacked  3   5x3      5x3      YY  n
        lazyVStack           fixedSize   3   5x3      -        Y   n
        lazyVStack           horizontal  3   60x3     -        Y   n
        lazyVStack           alone       60  59x25    -        Y   n
        lazyVStack           underTitle  60  6x60     -        Y   n
        lazyVStack           twoStacked  60  6x60     6x60     YY  n
        lazyVStack           fixedSize   60  6x60     -        n   n
        lazyVStack           horizontal  60  59x25    -        Y   n
        lazyHStack           alone       3   17x1     -        Y   n
        lazyHStack           underTitle  3   17x1     -        Y   n
        lazyHStack           twoStacked  3   17x1     17x1     YY  n
        lazyHStack           fixedSize   3   17x1     -        Y   n
        lazyHStack           horizontal  3   17x1     -        Y   n
        lazyHStack           alone       60  60x1     -        n   n
        lazyHStack           underTitle  60  60x1     -        n   n
        lazyHStack           twoStacked  60  60x1     60x1     nn  n
        lazyHStack           fixedSize   60  60x1     -        n   n
        lazyHStack           horizontal  60  410x1    -        n   n
        tabView              alone       3   10x4     -        Y   n
        tabView              underTitle  3   10x4     -        Y   n
        tabView              twoStacked  3   10x4     10x4     YY  n
        tabView              fixedSize   3   10x4     -        Y   n
        tabView              horizontal  3   10x4     -        Y   n
        tabView              alone       60  10x61    -        Y   n
        tabView              underTitle  60  10x61    -        Y   n
        tabView              twoStacked  60  10x61    10x61    YY  n
        tabView              fixedSize   60  10x61    -        n   n
        tabView              horizontal  60  10x61    -        Y   n
        navigationStack      alone       3   5x3      -        Y   n
        navigationStack      underTitle  3   5x3      -        Y   n
        navigationStack      twoStacked  3   5x3      5x3      YY  n
        navigationStack      fixedSize   3   5x3      -        Y   n
        navigationStack      horizontal  3   5x3      -        Y   n
        navigationStack      alone       60  6x60     -        Y   n
        navigationStack      underTitle  60  6x60     -        Y   n
        navigationStack      twoStacked  60  6x60     6x60     YY  n
        navigationStack      fixedSize   60  6x60     -        n   n
        navigationStack      horizontal  60  6x60     -        Y   n
        navigationSplitView  alone       3   60x24    -        Y   n
        navigationSplitView  underTitle  3   60x23    -        Y   n
        navigationSplitView  twoStacked  3   60x12    60x12    YY  n
        navigationSplitView  fixedSize   3   60x1     -        n   n
        navigationSplitView  horizontal  3   60x24    -        Y   n
        navigationSplitView  alone       60  60x24    -        n   n
        navigationSplitView  underTitle  60  60x23    -        n   n
        navigationSplitView  twoStacked  60  60x12    60x12    nn  n
        navigationSplitView  fixedSize   60  60x1     -        n   n
        navigationSplitView  horizontal  60  60x24    -        n   n
        hSplitView           alone       3   60x24    -        Y   n
        hSplitView           underTitle  3   60x23    -        Y   n
        hSplitView           twoStacked  3   60x12    60x12    YY  n
        hSplitView           fixedSize   3   60x3     -        Y   n
        hSplitView           horizontal  3   60x24    -        Y   n
        hSplitView           alone       60  59x60    -        Y   n
        hSplitView           underTitle  60  59x60    -        Y   n
        hSplitView           twoStacked  60  59x60    59x60    YY  n
        hSplitView           fixedSize   60  60x60    -        n   n
        hSplitView           horizontal  60  59x60    -        Y   n
        vSplitView           alone       3   60x24    -        Y   n
        vSplitView           underTitle  3   60x23    -        Y   n
        vSplitView           twoStacked  3   60x12    60x12    YY  n
        vSplitView           fixedSize   3   60x5     -        n   n
        vSplitView           horizontal  3   60x24    -        Y   n
        vSplitView           alone       60  59x62    -        n   n
        vSplitView           underTitle  60  59x62    -        n   n
        vSplitView           twoStacked  60  59x62    59x62    nn  n
        vSplitView           fixedSize   60  60x62    -        n   n
        vSplitView           horizontal  60  59x62    -        n   n
        groupBox             alone       3   9x6      -        Y   n
        groupBox             underTitle  3   9x6      -        Y   n
        groupBox             twoStacked  3   9x6      9x6      YY  n
        groupBox             fixedSize   3   9x6      -        Y   n
        groupBox             horizontal  3   9x6      -        Y   n
        groupBox             alone       60  10x63    -        Y   n
        groupBox             underTitle  60  10x63    -        Y   n
        groupBox             twoStacked  60  10x63    10x63    YY  n
        groupBox             fixedSize   60  10x63    -        n   n
        groupBox             horizontal  60  10x63    -        Y   n
        disclosureGroup      alone       3   9x4      -        Y   Y
        disclosureGroup      underTitle  3   9x4      -        Y   Y
        disclosureGroup      twoStacked  3   9x4      9x4      YY  Y
        disclosureGroup      fixedSize   3   9x4      -        Y   Y
        disclosureGroup      horizontal  3   9x4      -        Y   Y
        disclosureGroup      alone       60  10x61    -        Y   Y
        disclosureGroup      underTitle  60  10x61    -        Y   Y
        disclosureGroup      twoStacked  60  10x61    10x61    YY  Y
        disclosureGroup      fixedSize   60  10x61    -        n   Y
        disclosureGroup      horizontal  60  10x61    -        Y   Y
        grid                 alone       3   10x3     -        Y   n
        grid                 underTitle  3   10x3     -        Y   n
        grid                 twoStacked  3   10x3     10x3     YY  n
        grid                 fixedSize   3   10x3     -        Y   n
        grid                 horizontal  3   10x3     -        Y   n
        grid                 alone       60  11x60    -        Y   n
        grid                 underTitle  60  11x60    -        Y   n
        grid                 twoStacked  60  11x60    11x60    YY  n
        grid                 fixedSize   60  11x60    -        n   n
        grid                 horizontal  60  11x60    -        Y   n
        flowLayout           alone       3   17x1     -        Y   n
        flowLayout           underTitle  3   17x1     -        Y   n
        flowLayout           twoStacked  3   17x1     17x1     YY  n
        flowLayout           fixedSize   3   17x1     -        Y   n
        flowLayout           horizontal  3   17x1     -        Y   n
        flowLayout           alone       60  60x8     -        Y   n
        flowLayout           underTitle  60  60x8     -        Y   n
        flowLayout           twoStacked  60  60x8     60x8     YY  n
        flowLayout           fixedSize   60  60x8     -        Y   n
        flowLayout           horizontal  60  410x1    -        n   n
        imageResizable       alone       3   60x24    -        n   n
        imageResizable       underTitle  3   60x23    -        n   n
        imageResizable       twoStacked  3   59x15    59x15    nn  n
        imageResizable       fixedSize   3   60x15    -        n   n
        imageResizable       horizontal  3   60x24    -        n   n
        imageAspectFit       alone       3   60x15    -        n   n
        imageAspectFit       underTitle  3   60x15    -        n   n
        imageAspectFit       twoStacked  3   59x15    59x15    nn  n
        imageAspectFit       fixedSize   3   60x15    -        n   n
        imageAspectFit       horizontal  3   60x15    -        n   n
        spacer               alone       3   1x1      -        n   n
        spacer               underTitle  3   1x1      -        n   n
        spacer               twoStacked  3   1x1      1x1      nn  n
        spacer               fixedSize   3   0x0      -        n   n
        spacer               horizontal  3   1x1      -        n   n
        color                alone       3   60x24    -        n   n
        color                underTitle  3   60x23    -        n   n
        color                twoStacked  3   60x12    60x12    nn  n
        color                fixedSize   3   0x0      -        n   n
        color                horizontal  3   60x24    -        n   n
        rectangle            alone       3   60x24    -        n   n
        rectangle            underTitle  3   60x23    -        n   n
        rectangle            twoStacked  3   60x12    60x12    nn  n
        rectangle            fixedSize   3   0x0      -        n   n
        rectangle            horizontal  3   60x24    -        n   n
        geometryReader       alone       3   59x4096  -        n   n
        geometryReader       underTitle  3   59x4095  -        n   n
        geometryReader       twoStacked  3   59x2048  59x2048  nn  n
        geometryReader       fixedSize   3   60x23    -        n   n
        geometryReader       horizontal  3   59x4096  -        n   n
        divider              alone       3   60x1     -        n   n
        divider              underTitle  3   60x1     -        n   n
        divider              twoStacked  3   60x1     60x1     nn  n
        divider              fixedSize   3   60x1     -        n   n
        divider              horizontal  3   60x1     -        n   n
        maxHeightText        alone       3   4x24     -        n   n
        maxHeightText        underTitle  3   4x23     -        n   n
        maxHeightText        twoStacked  3   4x12     4x12     nn  n
        maxHeightText        fixedSize   3   4x1      -        n   n
        maxHeightText        horizontal  3   4x24     -        n   n
        """

    static let rows: [ScrollFitBaselineRow] = table.split(separator: "\n").map { line in
        let field = line.split(separator: " ").map(String.init)
        return ScrollFitBaselineRow(
            subject: ScrollFitSubject(rawValue: field[0])!, situation: ScrollFitSituation(rawValue: field[1])!,
            rows: Int(field[2])!, sizeA: field[3], sizeB: field[4], reached: field[5], ownBar: field[6] == "Y")
    }
}
