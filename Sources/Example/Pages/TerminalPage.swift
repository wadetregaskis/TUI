//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Terminal Page

/// What an app asks the terminal itself to do, outside the app's cells: a
/// progress bar on its tab (`.terminalProgress(_:)`) and the person's attention
/// (`\.requestAttention`), with `\.terminalCapabilities` saying whether this
/// terminal does each. And, last, everything `\.terminalCapabilities` knows of
/// what this terminal can do (``TerminalCapabilitiesDemo``).
///
/// The page states its progress for as long as it is open, so the bar is up
/// while it is shown and gone when it is left.
struct TerminalPage: View {
    /// The kind of progress the page states.
    @State private var kind = Kind.value

    /// How far along the work the page reports is.
    @State private var fraction = 0.4

    /// Whether a request for attention is due in a few seconds.
    @State private var isAskingSoon = false

    @Environment(\.terminalCapabilities) private var terminal
    @Environment(\.requestAttention) private var requestAttention

    /// The progress kinds the picker offers, one per `TerminalProgress` case,
    /// and none.
    private enum Kind: Hashable, CaseIterable {
        case none, value, indeterminate, paused, error

        /// The picker's label for it.
        var key: String {
            switch self {
            case .none: "page.terminal.kind.none"
            case .value: "page.terminal.kind.value"
            case .indeterminate: "page.terminal.kind.indeterminate"
            case .paused: "page.terminal.kind.paused"
            case .error: "page.terminal.kind.error"
            }
        }
    }

    /// What the page states for the terminal to draw.
    private var progress: TerminalProgress? {
        switch kind {
        case .none: nil
        case .value: .value(fraction)
        case .indeterminate: .indeterminate
        case .paused: .paused(fraction)
        case .error: .error(fraction)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                progressSection
                attentionSection
                TerminalCapabilitiesDemo()
            }
            .padding(.horizontal, 1)
        }
        .terminalProgress(progress)
        .task(id: isAskingSoon) {
            guard isAskingSoon else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            requestAttention("page.terminal.attentionMessage")
            isAskingSoon = false
        }
        .navigationTitle("menu.item.terminal")
        .navigationSubtitle("page.terminal.subtitle")
    }

    // MARK: - Progress

    private var progressSection: some View {
        DemoSection("page.terminal.progressSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.terminal.progressExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                ValueDisplayRow(
                    "page.terminal.showsProgress",
                    L(TerminalCapabilitiesDemo.statusKey(terminal.status(of: .progressReports))))
                Picker("page.terminal.progressKind", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { kind in
                        Text(L(kind.key)).tag(kind)
                    }
                }
                Slider(value: $fraction, in: 0...1, step: 0.05) {
                    Text("\(L("page.terminal.fraction")) \(Int((fraction * 100).rounded()))%")
                }
                .disabled(kind == .none || kind == .indeterminate)
            }
        }
    }

    // MARK: - Attention

    private var attentionSection: some View {
        DemoSection("page.terminal.attentionSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.terminal.attentionExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                ValueDisplayRow(
                    "page.terminal.attentionHere",
                    // Where a notification is not known to show, TUIkit rings
                    // the bell instead.
                    L(terminal.supports(.notifications) ? "page.terminal.notification" : "page.terminal.bell"))
                Button(L(isAskingSoon ? "page.terminal.asking" : "page.terminal.ask")) {
                    isAskingSoon = true
                }
                .disabled(isAskingSoon)
            }
        }
    }
}
