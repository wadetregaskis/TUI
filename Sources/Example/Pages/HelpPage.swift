//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HelpPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Help and tooltips demo page: `help(_:)` on views that can take the focus
/// and on views that cannot, in both presentations, under every trigger.
///
/// - Hover any sample: its help appears once the pointer has rested
///   (`tooltipDelay`, 0.6 s), in the status bar or as a popover, as chosen.
/// - Focus a control and press `?`: its help appears at once, and `?` again
///   hides it. In the text field `?` is typed instead, the documented caveat;
///   hover still works there.
/// - "When a control is focused" (`.onFocus`) shows the focused control's help
///   after the delay, no key needed.
/// - "Always" (`.always`) shows every sample's help at once, the two texts
///   included, each panel beside its own view and none over another: the
///   keyboard's route to the help of a view that cannot take the focus.
struct HelpPage: View {
    /// The presentation, as the picker offers it: a picker's tags must be
    /// `Hashable`, and `TooltipStyle` is only `Equatable`.
    enum StyleChoice: Hashable {
        case statusBar, popover

        var style: TooltipStyle {
            switch self {
            case .statusBar: .statusBar
            case .popover: .popover
            }
        }
    }

    /// When the samples' help appears, as the picker offers it.
    enum TriggerChoice: Hashable {
        case automatic, onFocus, always

        var trigger: TooltipTrigger {
            switch self {
            case .automatic: .automatic
            case .onFocus: .onFocus
            case .always: .always
            }
        }
    }

    @State private var style: StyleChoice = .statusBar
    @State private var trigger: TriggerChoice = .automatic
    @State private var verbose = false
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection("page.help.settingsSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.help.settingsDescription")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Picker("page.help.style", selection: $style) {
                        Text("page.help.style.statusBar").tag(StyleChoice.statusBar)
                        Text("page.help.style.popover").tag(StyleChoice.popover)
                    }
                    .pickerStyle(.radioGroup)
                    Picker("page.help.trigger", selection: $trigger) {
                        Text("page.help.trigger.automatic").tag(TriggerChoice.automatic)
                        Text("page.help.trigger.onFocus").tag(TriggerChoice.onFocus)
                        Text("page.help.trigger.always").tag(TriggerChoice.always)
                    }
                    .pickerStyle(.radioGroup)
                }
            }

            DemoSection("page.help.samplesSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.help.samplesDescription")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // Packed as a page would pack them. Help changes no layout:
                    // a panel is drawn over the page, and under "Always" the
                    // panels find places beside their views that cover none of
                    // the others (below, above, right or left), a panel with no
                    // such place left out until its view is pointed at or
                    // focused. Rows kept open for them were space the page
                    // gave up whether or not a panel was showing.
                    VStack(alignment: .leading, spacing: 1) {
                        Button("page.help.rebuild") {}
                            .help("page.help.rebuildHelp")
                        Toggle("page.help.verbose", isOn: $verbose)
                            .help("page.help.verboseHelp")
                        // Neither of these can take the focus: hover them, or
                        // choose "Always".
                        Text("page.help.coverage")
                            .help("page.help.coverageHelp")
                        Text("page.help.buildStatus")
                            .help("page.help.buildStatusHelp")
                        TextField("page.help.name", text: $name, prompt: Text("page.help.namePrompt"))
                            .frame(width: 24)
                            .help("page.help.nameHelp")
                    }
                    // Scoped to the samples, so "Always" explains them and not
                    // the pickers above.
                    .tooltips(trigger.trigger)
                    .tooltipStyle(style.style)
                }
            }
        }
        .scrollableDemoPage()
        .navigationTitle("menu.item.help")
    }
}
