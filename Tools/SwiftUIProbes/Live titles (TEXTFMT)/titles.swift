// TEXTFMT (2026-10-24): which SwiftUI consumers of a title keep a live value
// live — a timer interpolated into a button's title, a text field's and a
// secure field's title (drawn as the placeholder), a table column's header,
// and a window's navigation title. A WindowGroup app reads, at three times a
// timer second apart and more, the window's title, each field's
// placeholderString, the table's column titles, and the window's contents by
// Vision (the accessibility tree is empty without an assistive client).
import AppKit
import SwiftUI
import Vision

@MainActor func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
let start = Date()

@MainActor func snapshot(_ window: NSWindow) -> String {
    var parts: [String] = ["title=\(window.title.debugDescription)"]
    for view in window.contentView.map(views) ?? [] {
        if let field = view as? NSTextField, let placeholder = field.placeholderString {
            parts.append("placeholder=\(placeholder.debugDescription)")
        }
        if let table = view as? NSTableView { parts.append("headers=\(table.tableColumns.map(\.title))") }
    }
    if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let image = rep.cgImage {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: image).perform([request])
            parts.append("drawn=\((request.results ?? []).compactMap { $0.topCandidates(1).first?.string })")
        }
    }
    return parts.joined(separator: " ")
}

struct Row: Identifiable { let id = 1; let name = "r" }

@main struct ProbeApp: App {
    @State var text = ""
    init() {
        Task { @MainActor in
            for time in [0.5, 2.5, 4.5] {
                try? await Task.sleep(for: .seconds(time - Date().timeIntervalSince(start)))
                for window in NSApp.windows where window.isVisible {
                    print(String(format: "t=%.1f", time), snapshot(window))
                }
            }
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup {
            VStack {
                Button("Button \(start, style: .timer)") {}
                TextField("Field \(start, style: .timer)", text: $text)
                SecureField("Secure \(start, style: .timer)", text: $text)
                Table([Row()]) { TableColumn("Header \(start, style: .timer)", value: \.name) }.frame(height: 80)
            }
            .frame(width: 500, height: 300)
            .navigationTitle(Text(start, style: .timer))
        }
    }
}
