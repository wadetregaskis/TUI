//  🖥️ TUI — A Terminal UI framework for Swift
//  DragAndDrop+Form.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - In a Form

/// A drag source written on a form row is the row the form lays out, which
/// keeps its place, as SwiftUI's form keeps a row under every modifier
/// measured (`Tools/SwiftUIProbes/Form rows`): the whole row drags, its label
/// too, as what it was written on is the whole row.
extension DraggableModifier: FormRowRewrapping {
    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        DraggableModifier<V, Payload>(content: row, payload: payload, preview: preview)
    }
}

/// A drop destination written on a form row is the row the form lays out,
/// which keeps its place, as SwiftUI's form keeps a row under every modifier
/// measured (`Tools/SwiftUIProbes/Form rows`).
extension DropDestinationModifier: FormRowRewrapping {
    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        DropDestinationModifier<V, Payload>(
            content: row, isEnabled: isEnabled, action: action, isTargeted: isTargeted)
    }
}

#if canImport(UniformTypeIdentifiers)
    /// And so is an `onDrop(of:…)`'s.
    extension ItemProviderDropModifier: FormRowRewrapping {
        func rewrappingFormRow<V: View>(_ row: V) -> any View {
            ItemProviderDropModifier<V>(content: row, install: install)
        }
    }
#endif
