//  🖥️ TUI — A Terminal UI framework for Swift
//  FormTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Form")
struct FormTests {
    private func lines(_ view: some View, width: Int = 50, height: Int = 20) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    /// A row's displayed value tracks external state across frames — the
    /// captured-data memo hole would freeze it at frame one.
    private struct CounterForm: View {
        let value: Int
        var body: some View {
            Form {
                Section("Counts") {
                    LabeledContent("Ticks", value: "\(value)")
                }
            }
        }
    }

    @Test("A form row rebuilt from changed data is not served frozen")
    func formRowNotFrozenByMemo() {
        // Form composes its rows with ForEach(0..<count) reading captured
        // arrays; the memo keyed on the Int index served the frame-one buffer
        // for every later frame — the documented captured-data hole, inside a
        // framework view.
        let tui = TUIContext()
        func frame(_ value: Int) -> [String] {
            let context = makeRenderContext(width: 40, height: 12)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let ctx = RenderContext(
                availableWidth: 40, availableHeight: 12,
                environment: context.environment, tuiContext: tui)
            let out = renderToBuffer(CounterForm(value: value), context: ctx)
                .lines.map { $0.stripped }
            tui.stateStorage.endRenderPass()
            return out
        }

        _ = frame(1)
        let second = frame(2)
        #expect(second.contains { $0.contains("2") }, "the row froze at frame one: \(second)")
        #expect(!second.contains { $0.contains("Ticks") && $0.contains("1") }, "\(second)")
    }

    // MARK: - Columns (default)

    @Test("Columns form right-aligns labels to a shared pillar")
    func columnsPillarAlignment() {
        let out = lines(
            Form {
                LabeledContent("Name", value: "Alice")
                LabeledContent("Email", value: "a@b.c")
            })
        let nameRow = out.first { $0.contains("Alice") } ?? ""
        let emailRow = out.first { $0.contains("a@b.c") } ?? ""
        // Pillar = widest label ("Email" = 5). "Name" (4) is right-aligned, so its
        // row gains a leading space; the values then start at the same column.
        #expect(nameRow.hasPrefix(" Name "))
        #expect(emailRow.hasPrefix("Email "))
        let aliceCol = nameRow.firstRange(of: "Alice").map { nameRow.distance(from: nameRow.startIndex, to: $0.lowerBound) }
        let valueCol = emailRow.firstRange(of: "a@b.c").map { emailRow.distance(from: emailRow.startIndex, to: $0.lowerBound) }
        #expect(aliceCol != nil && aliceCol == valueCol, "value column aligns: \(out)")
    }

    /// A labelled row of the app's own: its body is one `LabeledContent`.
    private struct NameRow: View {
        var body: some View {
            LabeledContent("Name", value: "Alice")
        }
    }

    @Test("A view of the app's own whose body is one LabeledContent is a labelled row, on the pillar")
    func ownLabeledRow() {
        // The deviations sweep's likely bug 7 (semantic audit 8): such a view
        // was a plain full-width row, out of the label column; SwiftUI's form
        // lays it out as the row written bare.
        let out = lines(
            Form {
                NameRow()
                LabeledContent("Email", value: "a@b.c")
            })
        let nameRow = out.first { $0.contains("Alice") } ?? ""
        let emailRow = out.first { $0.contains("a@b.c") } ?? ""
        #expect(nameRow.hasPrefix(" Name "), "\(out)")
        let aliceCol = nameRow.firstRange(of: "Alice").map { nameRow.distance(from: nameRow.startIndex, to: $0.lowerBound) }
        let valueCol = emailRow.firstRange(of: "a@b.c").map { emailRow.distance(from: emailRow.startIndex, to: $0.lowerBound) }
        #expect(aliceCol != nil && aliceCol == valueCol, "value column aligns: \(out)")
    }

    /// A label of several lines is placed as one block at the pillar's
    /// trailing edge, its lines leading inside it: SwiftUI's columns `Form`
    /// draws "a" over "longer label" beside "a much longer label" with the
    /// "a" at the start of "longer label", not at its end (measured,
    /// `Tools/SwiftUIProbes/Trailing values and labels`). Until a frame placed
    /// its content as one block (e9c065a9e), each line was right-aligned on
    /// its own.
    @Test("Columns form places a label of several lines as a block at the pillar, its lines leading")
    func columnsMultilineLabel() throws {
        let out = lines(
            Form {
                LabeledContent { Text("v") } label: { Text("a\nlonger label") }
                LabeledContent { Text("w") } label: { Text("a much longer label") }
            })
        func start(of text: String, in line: String) -> Int? {
            line.range(of: text).map { line.distance(from: line.startIndex, to: $0.lowerBound) }
        }
        let longer = try #require(out.firstIndex { $0.contains("longer label") && !$0.contains("much") }, "\(out)")
        let much = try #require(out.first { $0.contains("a much longer label") }, "\(out)")
        let blockStart = try #require(start(of: "longer label", in: out[longer]))
        #expect(longer > 0 && start(of: "a", in: out[longer - 1]) == blockStart, "the lines lead: \(out)")
        #expect(
            blockStart + "longer label".count == (start(of: "a much longer label", in: much) ?? 0) + 19,
            "the block ends at the pillar's trailing edge: \(out)")
    }

    @Test("Form defaults to the columns style (no border)")
    func defaultStyleIsColumns() {
        let out = lines(
            Form {
                LabeledContent("Name", value: "Alice")
            }).joined(separator: "\n")
        #expect(out.contains("Name") && out.contains("Alice"))
        // Columns draws no box border.
        #expect(!out.contains("─") && !out.contains("│"))
    }

    // MARK: - Grouped

    @Test("Grouped form draws sections as bordered boxes")
    func groupedDrawsBoxes() {
        let out = lines(
            Form {
                Section("General") {
                    LabeledContent("Name", value: "Alice")
                }
            }
            .formStyle(.grouped)
        ).joined(separator: "\n")
        #expect(out.contains("General"))
        #expect(out.contains("Name") && out.contains("Alice"))
        // Grouped draws a border around the section's rows.
        #expect(out.contains("─") || out.contains("│"))
    }

    // MARK: - LabeledContent standalone

    @Test("LabeledContent renders its label and value standalone")
    func labeledContentStandalone() {
        let out = lines(LabeledContent("Version", value: "1.0.3")).joined(separator: "\n")
        #expect(out.contains("Version") && out.contains("1.0.3"))
    }

    /// `LabeledContent(_:value:format:)` — the row that shows a NUMBER. The
    /// point is what it saves the caller from: interpolating the value by hand
    /// is how a form ends up displaying `0.42857142857142855`. Locales are
    /// pinned so the expected text is the same on every host.
    @Test("LabeledContent formats a value rather than interpolating it")
    func labeledContentFormatsItsValue() {
        let locale = Locale(identifier: "en_US")
        let count = lines(
            LabeledContent(
                "Items", value: 1234,
                format: IntegerFormatStyle<Int>().locale(locale))
        ).joined(separator: "\n")
        #expect(count.contains("Items") && count.contains("1,234"), "got \(count)")

        let fraction = 3.0 / 7.0
        let percent = lines(
            LabeledContent(
                "Progress", value: fraction,
                format: FloatingPointFormatStyle<Double>.Percent().locale(locale))
        ).joined(separator: "\n")
        #expect(percent.contains("43%"), "not the raw Double — got \(percent)")
        #expect(!percent.contains("0.42"), "the unformatted value leaked through")
    }

    // MARK: - Custom FormStyle

    @Test("A custom FormStyle.makeBody is used")
    func customFormStyle() {
        let out = lines(
            Form {
                LabeledContent("Name", value: "Alice")
            }
            .formStyle(BannerFormStyle())
        ).joined(separator: "\n")
        #expect(out.contains("== FORM =="))
    }

    // MARK: - Sections + varied controls

    @Test("Form sections render headers, varied controls, and full-width rows")
    func sectionsWithVariedControls() {
        let out = lines(
            Form {
                Section("Profile") {
                    LabeledContent("Name") { TextField("", text: .constant("Ada")) }
                    LabeledContent("Password") { SecureField("", text: .constant("x")) }
                }
                Section("Settings") {
                    LabeledContent("Theme") {
                        Picker("", selection: .constant(0)) {
                            Text("Light").tag(0)
                            Text("Dark").tag(1)
                        }
                    }
                    LabeledContent("Volume") { Slider(value: .constant(50.0), in: 0...100) }
                    LabeledContent("Count") { Stepper("", value: .constant(3), in: 0...10) }
                    Toggle("Push", isOn: .constant(true))   // native: box-first control column
                    Button("Sign Out") {}
                }
            },
            width: 60, height: 30
        ).joined(separator: "\n")

        for label in ["Profile", "Name", "Password", "Settings", "Theme", "Volume", "Count", "Push", "Sign Out"] {
            #expect(out.contains(label), "missing '\(label)' in:\n\(out)")
        }
    }

    /// Where `text` starts on the first line holding it, in cells.
    private func column(of text: String, in out: [String]) -> Int? {
        guard let line = out.first(where: { $0.contains(text) }), let range = line.firstRange(of: text) else { return nil }
        return line.distance(from: line.startIndex, to: range.lowerBound)
    }

    /// The value column of a form whose first row is `modified` — `Name`:
    /// `Alice`, under some modifier — and whose second is a bare row with a
    /// longer label, beside the bare row's.
    private func valueColumns(_ modified: some View) -> (alice: Int?, email: Int?, out: [String]) {
        let out = lines(
            Form {
                modified
                LabeledContent("Email address", value: "a@b.c")
            })
        return (column(of: "Alice", in: out), column(of: "a@b.c", in: out), out)
    }

    /// SwiftUI's form keeps a row in its place whatever is written on it —
    /// measured: the label stays in the label column and the modifier applies
    /// to the row (DEVS #7, the semantic audit's item 8). A modifier that can
    /// be put back around the laid-out row is looked through.
    @Test("A modifier written on a LabeledContent row keeps it a labelled row, on the pillar")
    func modifiedLabeledRow() {
        let row = LabeledContent("Name", value: "Alice")
        for (name, columns) in [
            ("foregroundStyle", valueColumns(row.foregroundStyle(.red))),
            ("disabled", valueColumns(row.disabled(true))),
            ("opacity", valueColumns(row.opacity(0.5))),
            ("two modifiers", valueColumns(row.disabled(true).foregroundStyle(.red))),
        ] {
            #expect(columns.alice != nil && columns.alice == columns.email, "\(name): \(columns.out)")
            #expect(columns.out.first { $0.contains("Alice") }?.contains("         Name ") == true, "\(name): \(columns.out)")
        }
    }

    @Test("A modifier written on a Toggle row keeps it in the control column")
    func modifiedControlRow() {
        let bare = lines(Form { LabeledContent("Email address", value: "a@b.c"); Toggle("Wi-Fi", isOn: .constant(true)) })
        // `.opacity`, not `.disabled`: `Toggle` answers `.disabled` itself,
        // as a `Toggle`.
        let faded = lines(
            Form { LabeledContent("Email address", value: "a@b.c"); Toggle("Wi-Fi", isOn: .constant(true)).opacity(0.5) })
        #expect(column(of: "Wi-Fi", in: bare) != nil && column(of: "Wi-Fi", in: faded) == column(of: "Wi-Fi", in: bare), "\(bare)\n\(faded)")
    }

    // MARK: - macOS columns conventions

    @Test("A bare Toggle is box-first in the control column (its label is clickable)")
    func toggleBoxFirstInControlColumn() {
        let out = lines(Form { Toggle("Wi-Fi", isOn: .constant(true)) })
        let row = out.first { $0.contains("Wi-Fi") } ?? ""
        // Box first: the row leads with the checkbox glyph, not the label. (The
        // native Toggle's hit region — covering box, gap, and label — is what
        // makes the whole row clickable.)
        #expect(!row.hasPrefix("Wi-Fi"))
        #expect(row.contains("Wi-Fi"))
    }

    /// Where "Sign Out" starts on the row that draws it.
    private func signOutColumn(_ out: [String]) -> Int? {
        guard let row = out.first(where: { $0.contains("Sign Out") }),
            let range = row.range(of: "Sign Out")
        else { return nil }
        return row.distance(from: row.startIndex, to: range.lowerBound)
    }

    /// SwiftUI's columns form puts a bare button where a checkbox goes, in the
    /// control column after the label pillar (`Tools/SwiftUIProbes/Form rows`,
    /// "Button bare": its row starts where a Toggle's does). A-FORMS-1, the
    /// owner's option 2 (2026-10-27); it was right-aligned before.
    @Test("A Button sits in the control column of the columns layout, as SwiftUI's does")
    func buttonInControlColumn() {
        let inForm = signOutColumn(lines(
            Form {
                LabeledContent("Account email", value: "ada@example.com")
                Button("Sign Out") {}
            }))
        let atEdge = signOutColumn(lines(
            Form {
                LabeledContent("Account email", value: "ada@example.com")
                Button("Sign Out") {}.formRowAlignment(.leading)
            }))
        // The pillar is "Account email", 13 cells; the control column starts a
        // cell after it.
        #expect(inForm != nil && atEdge != nil)
        #expect((inForm ?? 0) - (atEdge ?? 0) == "Account email".count + 1)
    }

    @Test("formRowAlignment(.trailing) puts a button at the form's trailing edge")
    func formRowAlignmentTrailingButton() {
        let inColumn = signOutColumn(lines(
            Form {
                LabeledContent("Account email", value: "ada@example.com")
                Button("Sign Out") {}
            }))
        let trailing = lines(
            Form {
                LabeledContent("Account email", value: "ada@example.com")
                Button("Sign Out") {}.formRowAlignment(.trailing)
            })
        let field = trailing.first { $0.contains("ada@example.com") } ?? ""
        let button = trailing.first { $0.contains("Sign Out") } ?? ""
        // Trailing: the button's row ends where the widest row does.
        #expect((signOutColumn(trailing) ?? 0) > (inColumn ?? 0))
        #expect(
            button.trimmingCharacters(in: .whitespaces).isEmpty == false
                && button.count <= field.count)
    }

    /// SwiftUI's grouped form puts a bare button at its row's leading edge, where
    /// a field's label starts (measured, "Button bare" in the grouped table).
    @Test("A Button sits at its row's leading edge in a grouped form, as SwiftUI's does")
    func buttonLeadingInGrouped() {
        let out = lines(
            Form {
                Section {
                    LabeledContent("Account email", value: "ada@example.com")
                    Button("Sign Out") {}
                }
            }
            .formStyle(.grouped))
        let atEdge = signOutColumn(lines(Form { Button("Sign Out") {}.formRowAlignment(.leading) }))
        let label = out.first { $0.contains("Account email") }.flatMap { row in
            row.range(of: "Account email").map { row.distance(from: row.startIndex, to: $0.lowerBound) }
        }
        #expect(label != nil && atEdge != nil)
        #expect(signOutColumn(out) == (label ?? 0) + (atEdge ?? 0))
    }

    @Test("A columns section header is right-aligned to the pillar")
    func sectionHeaderRightAligned() {
        let out = lines(
            Form {
                Section("On") {
                    LabeledContent("Notifications", value: "all")
                }
            })
        // "On" (capital O) only appears in the header; the field row has "Notifications".
        let headerRow = out.first { $0.contains("On") && !$0.contains("Notifications") } ?? ""
        // Right-aligned to the "Notifications" pillar → leading whitespace.
        #expect(headerRow.hasPrefix(" "))
        #expect(headerRow.contains("On"))
    }

    /// A header wider than every field label is not cut to the label column:
    /// the column is the labels' width, and a header is not a label. Found by
    /// the `Stress` settings session, whose "Measurements" drew as
    /// "Measuremen…" over a column sized by "Page height".
    @Test("A columns section header wider than the pillar is drawn whole")
    func aWideSectionHeaderIsNotCut() {
        let out = lines(
            Form {
                Section("Measurements") {
                    LabeledContent("Gap", value: "1 mm")
                }
            })
        #expect(out.contains { $0.contains("Measurements") }, "the header was cut: \(out)")
        // And the field row keeps its column: the label pillar is still "Gap"'s.
        let fieldRow = out.first { $0.contains("Gap") } ?? ""
        #expect(fieldRow.hasPrefix("Gap"), "the header widened the label column: \(fieldRow)")
    }

    @Test("A Toggle's click zone in a form covers its label (full row clickable)")
    func toggleClickZoneCoversLabel() {
        // A field label gives the toggle a non-zero control-column indent; the
        // toggle's native hit region (box + gap + label) must shift with it.
        let ctx = makeRenderContext(width: 50, height: 10) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let buffer = renderToBuffer(
            Form {
                LabeledContent("Account name", value: "ada")
                Toggle("Wi-Fi", isOn: .constant(true))
            },
            context: ctx)
        let toggleRow = buffer.lines.firstIndex { $0.stripped.contains("Wi-Fi") } ?? -1
        let stripped = toggleRow >= 0 ? buffer.lines[toggleRow].stripped : ""
        let labelCol = stripped.range(of: "Wi-Fi").map {
            stripped.distance(from: stripped.startIndex, to: $0.lowerBound)
        } ?? -1
        let covered = buffer.hitTestRegions.contains { region in
            region.offsetY <= toggleRow && toggleRow < region.offsetY + region.height
                && region.offsetX <= labelCol && labelCol < region.offsetX + region.width
        }
        #expect(toggleRow >= 0 && labelCol >= 0)
        #expect(covered, "a hit region should cover the label at row \(toggleRow), col \(labelCol)")
    }
}

/// A custom form style exercising ``FormStyle/makeBody(configuration:)``.
private struct BannerFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("== FORM ==")
            configuration.content
        }
    }
}
