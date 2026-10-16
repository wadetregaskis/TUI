//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollObservationDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Watching a scroll view: where it is (`.onScrollGeometryChange`), whether
/// the user is moving it (`.onScrollPhaseChange`), whether one row is on
/// screen (`.onScrollVisibilityChange`), rows that fade as they near the edges
/// (`.scrollTransition`), and paging a screenful at a time
/// (`.scrollTargetBehavior(.paging)`).
struct ScrollObservationDemo: View {
    @State private var offset = 0
    @State private var phase = ScrollPhase.idle
    @State private var markerVisible = false
    @State private var pages = false

    private static let rowCount = 40
    private static let markedRow = 20

    var body: some View {
        DemoSection("page.scrollView.observationSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.scrollView.observationBody")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 3) {
                    ValueDisplayRow("page.scrollView.observation.offset", "\(offset)")
                    ValueDisplayRow("page.scrollView.observation.phase", "\(phase)")
                    ValueDisplayRow(
                        "page.scrollView.observation.marked",
                        markerVisible ? L("page.scrollView.observation.onScreen") : L("page.scrollView.observation.offScreen"))
                }
                Toggle("page.scrollView.observation.paging", isOn: $pages)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<Self.rowCount, id: \.self) { row in
                            Text(row == Self.markedRow ? "★ \(L("page.scrollView.positions.row")) \(row)" : "\(L("page.scrollView.positions.row")) \(row)")
                                .foregroundStyle(row == Self.markedRow ? .palette.accent : .palette.foreground)
                                // Faded at the edges, full in the middle.
                                .scrollTransition { effect, phase in
                                    effect.opacity(phase.isIdentity ? 1 : 0.35)
                                }
                                .onScrollVisibilityChange { visible in
                                    if row == Self.markedRow { markerVisible = visible }
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(pages ? AnyScrollTargetBehavior(.paging) : AnyScrollTargetBehavior(.viewAligned))
                .onScrollGeometryChange(for: Int.self, of: { $0.contentOffset.y }, action: { _, new in offset = new })
                .onScrollPhaseChange { _, new in phase = new }
                .frame(width: 40, height: 8)
                .border(.palette.border)
            }
        }
    }
}
