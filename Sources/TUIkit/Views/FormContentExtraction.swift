//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormContentExtraction.swift
//
//  How a `Form` reads its content as rows and sections: the walk its layout
//  lays out. Split out of `Form.swift`, which had passed the file-length
//  guideline.
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Form Content Extraction

/// Views that can contribute rows/sections to a ``Form``.
///
/// Mirrors the ``ButtonProvider`` pattern ``Alert`` uses: the form walks its
/// content tree through this protocol to recover the label/control structure it
/// needs for pillar alignment (a generic `Form<Content>` can't otherwise see
/// inside its opaque content).
@MainActor
protocol FormContentExtractor {
    func extractFormElements() -> [_FormElement]
}

/// Extracts the form elements of `view`: its own contribution if it is a
/// ``FormContentExtractor``; otherwise a control row (checkbox/radio), a button
/// row, or a plain full-width row depending on its kind.
@MainActor
func formElements(from view: some View) -> [_FormElement] {
    if let aligned = view as? FormRowAligning {
        let alignment = aligned.formRowAlignmentValue
        return aligned.formRowInnerElements().map { stamped($0, alignment: alignment) }
    }
    if let extractor = view as? FormContentExtractor {
        return extractor.extractFormElements()
    }
    if view is FormControlRow {
        return [.row(_FormRow(.control(AnyView(view))))]
    }
    if view is FormButtonRow {
        return [.row(_FormRow(.button(AnyView(view))))]
    }
    return [.row(_FormRow(.plain(AnyView(view))))]
}

/// Stamps an explicit alignment onto an element's row(s), without clobbering an
/// inner override already present (the innermost `formRowAlignment` wins).
private func stamped(_ element: _FormElement, alignment: HorizontalAlignment) -> _FormElement {
    func apply(_ row: _FormRow) -> _FormRow {
        var row = row
        if row.alignment == nil { row.alignment = alignment }
        return row
    }
    switch element {
    case .row(let row):
        return .row(apply(row))
    case .section(var section):
        section.rows = section.rows.map(apply)
        return .section(section)
    }
}

/// Flattens elements to their rows (a section contributes its rows).
func formRows(of elements: [_FormElement]) -> [_FormRow] {
    elements.flatMap { element -> [_FormRow] in
        switch element {
        case .row(let row): return [row]
        case .section(let section): return section.rows
        }
    }
}

extension LabeledContent: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        [.row(_FormRow(.field(label: AnyView(label), content: AnyView(content))))]
    }
}

extension Section: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        [.section(_FormSection(
            header: (header is EmptyView) ? nil : AnyView(header),
            footer: (footer is EmptyView) ? nil : AnyView(footer),
            rows: formRows(of: formElements(from: content))))]
    }
}

extension TupleView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        var elements: [_FormElement] = []
        func collect<T: View>(_ view: T) {
            elements.append(contentsOf: formElements(from: view))
        }
        repeat collect(each children)
        return elements
    }
}

extension ForEach: FormContentExtractor where Content: View {
    func extractFormElements() -> [_FormElement] {
        data.flatMap { element in formElements(from: content(element)) }
    }
}

/// A form reads its rows through an erasure, as through a `Group` — which is
/// what lets ``Form/init(_:)`` lay out a configuration's type-erased content.
extension AnyView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        formElements(from: erasedView)
    }
}

extension EmptyView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] { [] }
}
