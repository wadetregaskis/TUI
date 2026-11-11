//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedRowRemovalTests.swift
//
//  A row that plays its own removal where the rows around it move at once —
//  a lazy stack's — is drawn where it was, over the row that has taken its
//  place. Only the cells it paints are drawn: its blank cells are its
//  silhouette, and drawn as cells they hid the row beneath for the whole
//  removal. A `Grid` and an eager stack draw the removal beneath their rows,
//  which glide over it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// The containers under test.
enum RemovalShape: String, CaseIterable, Sendable {
    case lazyStack, scrolledLazyStack, grid, eagerStack
}

/// A transition a row leaves by, as a test argument.
enum RemovalTransition: String, CaseIterable, Sendable {
    case moveTrailing, moveLeading, opacity, slide

    var transition: AnyTransition {
        switch self {
        case .moveTrailing: .move(edge: .trailing)
        case .moveLeading: .move(edge: .leading)
        case .opacity: .opacity
        case .slide: .slide
        }
    }
}

/// Rows of `shape`, each as wide as the stack, as a row of a list is — a
/// label and a spacer — and leaving by `transition`; the second paints only
/// two cells of its width. The button above them removes the second under a
/// one-second linear animation.
private struct RemovingRows: View {
    let shape: RemovalShape
    let transition: AnyTransition
    @State private var ids = [1, 2, 3, 4]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("drop") { withAnimation(.linear(duration: 1)) { ids.removeAll { $0 == 2 } } }
            rows
        }
    }

    /// Row 2 paints two cells; every other row paints six.
    private static func name(_ id: Int) -> String {
        String(repeating: "\(id)", count: id == 2 ? 2 : 6)
    }

    @ViewBuilder private var rows: some View {
        switch shape {
        case .lazyStack:
            LazyVStack(alignment: .leading, spacing: 0) { content }
        case .scrolledLazyStack:
            ScrollView { LazyVStack(alignment: .leading, spacing: 0) { content } }.frame(height: 6)
        case .grid:
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(ids, id: \.self) { id in GridRow { row(id) } }
            }
        case .eagerStack:
            VStack(alignment: .leading, spacing: 0) { content }
        }
    }

    private var content: some View {
        ForEach(ids, id: \.self) { id in row(id) }
    }

    private func row(_ id: Int) -> some View {
        HStack(spacing: 0) {
            Text(Self.name(id))
            Spacer(minLength: 0)
        }
        .transition(transition)
    }
}

@MainActor
@Suite("A row playing its own removal draws only the cells it paints")
struct WindowedRowRemovalTests {
    /// Every frame of the removal, three sixtieths of a second apart, shows the
    /// row that moved into the removed row's place: the cells the removed row
    /// does not paint are that row's. Row 3 paints six cells and row 2 two, so
    /// at least four of row 3's show however row 2 is drawn over it. In a lazy
    /// stack row 3 is in row 2's place from the change on; in a `Grid` and an
    /// eager stack it glides there, over the removal.
    @Test(
        "The row that moves into a removed row's place shows through the removal",
        arguments: RemovalShape.allCases, RemovalTransition.allCases)
    func rowBeneathShows(shape: RemovalShape, transition: RemovalTransition) {
        let app = TestApp(width: 16, height: 8) { RemovingRows(shape: shape, transition: transition.transition) }
        #expect(app.screen.lines[2].hasPrefix("22"), "before: \(app.screen.lines)")
        #expect(app.press(.enter))
        var frames = 0
        var seenLeaving = false
        while app.elapsed < .milliseconds(1100) {
            let lines = app.screen.lines
            #expect(
                lines.contains { $0.filter { $0 == "3" }.count >= 4 },
                "frame \(frames), \(app.elapsed): \(lines)")
            if lines.dropFirst().contains(where: { $0.contains("2") }) { seenLeaving = true }
            app.advance(by: .nanoseconds(16_666_667 * 3))
            frames += 1
        }
        #expect(seenLeaving, "the removal played: \(shape), \(transition)")
        #expect(!app.screen.contains("22"), "gone: \(app.screen.lines)")
    }
}
