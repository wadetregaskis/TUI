//  🖥️ TUI — A Terminal UI framework for Swift
//  AboutPanel.swift
//
//  What the app menu's About says of the app: as the scene states it, from
//  its bundle's Info.plist, or the process's name.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIApp
import TUIFoundation

// MARK: - Public Modifier

extension Scene {
    /// States what the menu bar's About *app* says of the app — its name,
    /// version, copyright and credits — where its bundle does not, or to say
    /// otherwise. A TUI modifier with no SwiftUI counterpart.
    ///
    /// On macOS, SwiftUI's About panel reads the app's Info.plist, and an app
    /// says more through AppKit's `orderFrontStandardAboutPanel(options:)`,
    /// whose option keys these parameters are named for. A terminal app is
    /// mostly a command-line executable — a SwiftPM product, or any program on
    /// Linux — with no Info.plist, so its About has only the process's name to
    /// go on; this is where such an app says the rest.
    ///
    /// Each value the app leaves `nil` comes from the bundle's Info.plist where
    /// it has one, as macOS's About panel takes them:
    ///
    /// | Parameter | Info.plist key | Otherwise |
    /// |---|---|---|
    /// | `applicationName` | `CFBundleDisplayName`, then `CFBundleName` | the process's name |
    /// | `applicationVersion` | `CFBundleShortVersionString` | none |
    /// | `version` | `CFBundleVersion` | none |
    /// | `copyright` | `NSHumanReadableCopyright` | none |
    /// | `credits` | — | none |
    ///
    /// The name titles the app's menu too, and its About and Quit items. The
    /// About alert shows the name, then "Version *applicationVersion*
    /// (*version*)" — the build beside the version only where the two differ —
    /// then the credits and the copyright, each where there is one.
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .commands { TextEditingCommands() }
    ///     .aboutPanel(applicationName: "Notes", applicationVersion: "1.2", copyright: "© 2026 Me")
    /// ```
    ///
    /// - Parameters:
    ///   - applicationName: The app's name.
    ///   - applicationVersion: The app's version, as people read it ("1.2").
    ///   - version: The build ("42").
    ///   - copyright: The copyright line.
    ///   - credits: Anything more: authors, acknowledgements, a link.
    /// - Returns: A scene whose About says these.
    public func aboutPanel(
        applicationName: String? = nil, applicationVersion: String? = nil, version: String? = nil,
        copyright: String? = nil, credits: String? = nil
    ) -> some Scene {
        environment(
            \.aboutPanel,
            AboutPanelInfo(
                applicationName: applicationName, applicationVersion: applicationVersion, version: version,
                copyright: copyright, credits: credits))
    }
}

// MARK: - What About Says

/// What the scene states for the About alert (``Scene/aboutPanel(applicationName:applicationVersion:version:copyright:credits:)``),
/// each value `nil` where it states none.
struct AboutPanelInfo: Equatable, Sendable {
    var applicationName: String?
    var applicationVersion: String?
    var version: String?
    var copyright: String?
    var credits: String?

    /// The values About shows: those stated, the gaps filled from `bundle`
    /// (an Info.plist's keys, or `nil` for none) and the name, failing both,
    /// `processName`.
    func resolved(bundle: [String: Any]?, processName: String) -> ResolvedAboutPanel {
        func string(_ key: String) -> String? {
            (bundle?[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        return ResolvedAboutPanel(
            name: applicationName ?? string("CFBundleDisplayName") ?? string("CFBundleName") ?? processName,
            applicationVersion: applicationVersion ?? string("CFBundleShortVersionString"),
            version: version ?? string("CFBundleVersion"),
            copyright: copyright ?? string("NSHumanReadableCopyright"),
            credits: credits)
    }
}

/// What About shows, every source consulted.
struct ResolvedAboutPanel: Equatable {
    let name: String
    let applicationVersion: String?
    let version: String?
    let copyright: String?
    let credits: String?

    /// The version as macOS's About panel words it: "1.2 (42)", the build
    /// beside the version only where the two differ; the build alone where
    /// there is no version; `nil` with neither.
    var versionText: String? {
        switch (applicationVersion, version) {
        case (let short?, let build?) where build != short: "\(short) (\(build))"
        case (let short?, _): short
        case (nil, let build?): "(\(build))"
        case (nil, nil): nil
        }
    }

    /// The About alert's title: the app menu's About item's.
    var aboutTitle: String {
        LocalizedStringKey.substituting(
            [name], into: LocalizationService.shared.string(for: LocalizationKey.Menu.about))
    }

    /// The About alert's message: the name, then the version, the credits and
    /// the copyright, each on a line of its own where there is one.
    var aboutMessage: String {
        let versionLine = versionText.map {
            LocalizedStringKey.substituting(
                [$0], into: LocalizationService.shared.string(for: LocalizationKey.Menu.aboutVersion))
        }
        return [name, versionLine, credits, copyright].compactMap(\.self).joined(separator: "\n")
    }
}

extension EnvironmentValues {
    /// What the scene states for the About alert; `nil` where it states
    /// nothing.
    var aboutPanel: AboutPanelInfo? {
        get { self[AboutPanelKey.self] }
        set { self[AboutPanelKey.self] = newValue }
    }

    /// What About shows, as of this environment: the scene's values, the
    /// main bundle's Info.plist, and the process's name.
    var resolvedAboutPanel: ResolvedAboutPanel {
        (aboutPanel ?? AboutPanelInfo()).resolved(
            bundle: Bundle.main.infoDictionary, processName: ProcessInfo.processInfo.processName)
    }
}

private struct AboutPanelKey: EnvironmentKey {
    static let defaultValue: AboutPanelInfo? = nil
}
