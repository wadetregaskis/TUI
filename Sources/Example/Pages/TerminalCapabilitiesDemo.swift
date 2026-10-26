//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalCapabilitiesDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Every feature `\.terminalCapabilities` knows of, with what it says of this
/// terminal: yes, no, or not known. Live: a feature that only a keypress shows
/// (Option sent as Meta) changes here as it is learnt, and under tmux the
/// progress bar's answer follows the terminals attached.
struct TerminalCapabilitiesDemo: View {
    @Environment(\.terminalCapabilities) private var terminal

    /// One group of features, under its heading, each with its name.
    private struct Group {
        let title: String
        let features: [(feature: TerminalCapabilities.Feature, name: String)]
    }

    /// The groups, in the order `TerminalCapabilities.Feature` declares them.
    private var groups: [Group] {
        [
            Group(
                title: "page.terminal.group.drawing",
                features: [
                    (.doubleUnderline, "page.terminal.feature.doubleUnderline"),
                    (.curlyUnderline, "page.terminal.feature.curlyUnderline"),
                    (.dottedUnderline, "page.terminal.feature.dottedUnderline"),
                    (.dashedUnderline, "page.terminal.feature.dashedUnderline"),
                    (.underlineColor, "page.terminal.feature.underlineColor"),
                    (.strikethrough, "page.terminal.feature.strikethrough"),
                    (.strikethroughColor, "page.terminal.feature.strikethroughColor"),
                    (.pictures, "page.terminal.feature.pictures"),
                ]),
            Group(
                title: "page.terminal.group.host",
                features: [
                    (.hyperlinks, "page.terminal.feature.hyperlinks"),
                    (.clipboardWrites, "page.terminal.feature.clipboardWrites"),
                    (.notifications, "page.terminal.feature.notifications"),
                    (.progressReports, "page.terminal.feature.progressReports"),
                    (.pointerShapes, "page.terminal.feature.pointerShapes"),
                ]),
            Group(
                title: "page.terminal.group.keyboard",
                features: [
                    (.disambiguatedKeys, "page.terminal.feature.disambiguatedKeys"),
                    (.shiftedKeys, "page.terminal.feature.shiftedKeys"),
                    (.keyRepeats, "page.terminal.feature.keyRepeats"),
                    (.keyReleases, "page.terminal.feature.keyReleases"),
                    (.modifierKeys, "page.terminal.feature.modifierKeys"),
                    (.capsLock, "page.terminal.feature.capsLock"),
                    (.numericPad, "page.terminal.feature.numericPad"),
                    (.optionAsMeta, "page.terminal.feature.optionAsMeta"),
                ]),
        ]
    }

    var body: some View {
        DemoSection("page.terminal.capabilitiesSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.terminal.capabilitiesExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                ValueDisplayRow("page.terminal.colorDepth", L(Self.depthKey(terminal.colorDepth)))
                ForEach(groups.indices, id: \.self) { index in
                    group(groups[index])
                }
            }
        }
    }

    /// A group's heading and its features, one a line.
    private func group(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L(group.title)).bold()
            ForEach(group.features.indices, id: \.self) { index in
                let entry = group.features[index]
                ValueDisplayRow(L(entry.name), L(Self.statusKey(terminal.status(of: entry.feature))))
            }
        }
    }

    /// The word for `status`: also the Terminal page's, for whether the
    /// progress bar shows.
    static func statusKey(_ status: TerminalCapabilities.Status) -> String {
        switch status {
        case .supported: "page.terminal.yes"
        case .unsupported: "page.terminal.no"
        case .undetermined: "page.terminal.unknown"
        }
    }

    /// The words for `depth`.
    private static func depthKey(_ depth: ColorDepth) -> String {
        switch depth {
        case .noColor: "page.terminal.depth.none"
        case .basic16: "page.terminal.depth.16"
        case .palette256: "page.terminal.depth.256"
        case .truecolor: "page.terminal.depth.truecolor"
        }
    }
}
