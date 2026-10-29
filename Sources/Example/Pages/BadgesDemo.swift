//  🖥️ TUI — A Terminal UI framework for Swift
//  BadgesDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Every badge there is, in one place: what a badge can hold (a count, a text,
/// and the zero or absent text that hides it), the three prominences
/// (`.badgeProminence`) set row by row and for a whole list, and the badge a
/// tab carries in a tab view's strip.
///
/// The badge rows once sat beside the list's other row decorations
/// (``ListRowsDemo``); a badge is one idea with several variants, so they were
/// gathered here.
struct BadgesDemo: View {
    /// The prominence the list sets for every badge that does not state its
    /// own — `.badgeProminence` written around the list.
    @State private var listProminence = BadgeProminence.standard
    @State private var tabSelection = 0

    var body: some View {
        DemoSection("page.list.badges.section") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.list.badges.explain")
                    .foregroundStyle(.palette.foregroundSecondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 2) {
                        listColumn
                        tabColumn
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        listColumn
                        tabColumn
                    }
                }
            }
        }
    }

    /// The prominence choice, and a list with a badge of every kind.
    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Picker("page.list.badges.listProminence", selection: $listProminence) {
                Text("page.list.badges.standard").tag(BadgeProminence.standard)
                Text("page.list.badges.increased").tag(BadgeProminence.increased)
                Text("page.list.badges.decreased").tag(BadgeProminence.decreased)
            }
            .pickerStyle(.segmented)
            List {
                Section("page.list.badges.kinds") {
                    Text("page.list.badges.count").badge(3)
                    Text("page.list.badges.text").badge(L("page.list.badges.newText"))
                    Text("page.list.badges.zero").badge(0)
                    Text("page.list.badges.noText").badge(String?.none)
                }
                // A badge's own prominence, written around it, beats the
                // list's: these three stay as they are whatever the picker says.
                Section("page.list.badges.perRow") {
                    Text("page.list.badges.standard").badge(12).badgeProminence(.standard)
                    Text("page.list.badges.increased").badge(12).badgeProminence(.increased)
                    Text("page.list.badges.decreased").badge(12).badgeProminence(.decreased)
                }
            }
            .badgeProminence(listProminence)
            .frame(width: 36, height: 13)
        }
    }

    /// A tab view whose tabs carry a count, a text and nothing (a zero).
    private var tabColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("page.list.badges.tabsHint")
                .foregroundStyle(.palette.foregroundSecondary)
                .frame(width: 36, alignment: .leading)
            TabView(selection: $tabSelection) {
                Tab("page.list.rows.inbox", value: 0) {
                    Text("page.list.badges.tabInboxBody")
                }
                .badge(4)
                Tab("page.list.badges.tabAlerts", value: 1) {
                    Text("page.list.badges.tabAlertsBody")
                }
                .badge(L("page.list.badges.newText"))
                Tab("page.list.badges.tabArchive", value: 2) {
                    Text("page.list.badges.tabArchiveBody")
                }
                .badge(0)
            }
            .tabViewStyle(.compact)
            .tabViewHeaderAlignment(.leading)
        }
    }
}
