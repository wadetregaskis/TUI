//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragSessionValueTests.swift
//
//  macOS 26's drag and drop session values, as SwiftUI documents them: the
//  phases with their operations, the dragged items' identifiers filtered by
//  type, the operations a drag configuration allows, a drop configuration's
//  choice, and the preview formations.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("Drag and drop session values")
struct DragSessionValueTests {
    @Test("A phase that ended carries its operation, and phases compare and hash by it")
    func phasesCarryTheirOperation() {
        #expect(DragSession.Phase.ended(.move) == .ended(.move))
        #expect(DragSession.Phase.ended(.move) != .ended(.copy))
        #expect(Set<DropSession.Phase>([.entering, .active, .exiting, .ended(.copy), .ended(.copy)]).count == 4)
        #expect(DragSession.Phase.ended(.delete).description == ".ended(.delete)")
        #expect(DropSession.Phase.dataTransferCompleted.description == ".dataTransferCompleted")
    }

    @Test("The dragged items' identifiers are the ones of the type asked for, in the drag's order")
    func draggedItemIDsFilterByType() {
        let ids: [AnyHashable] = [AnyHashable(3), AnyHashable("a"), AnyHashable(1)]
        let drag = DragSession(
            id: DragSession.ID(raw: 7), phase: .active, location: CellPoint(x: 2, y: 1),
            draggedItemIndex: 2, itemIDs: ids)
        #expect(drag.draggedItemIDs(for: Int.self) == [3, 1])
        #expect(drag.draggedItemIDs(for: String.self) == ["a"])
        #expect(drag.draggedItemIDs(for: Double.self).isEmpty)
        #expect(drag.draggedItemIndex == 2)
        #expect(drag.id == DragSession.ID(raw: 7))
        #expect(drag.id.debugDescription == "DragSession.ID(7)")

        let drop = DropSession(
            id: DropSession.ID(raw: 7), phase: .entering, location: .zero,
            size: CellSize(width: 10, height: 4), itemsCount: 3,
            localSession: DropSession.LocalSession(itemIDs: ids))
        #expect(drop.localSession?.draggedItemIDs(for: Int.self) == [3, 1])
        #expect(drop.suggestedOperations == .copy, "a drag allows copying unless it says otherwise")
    }

    @Test("A drag configuration allows copying by default, and moving and deleting when asked")
    func dragConfigurationOperations() {
        let plain = DragConfiguration()
        #expect(plain.operationsWithinApp.operations == [.copy])
        #expect(plain.operationsOutsideApp.operations == [.copy])
        let moving = DragConfiguration(allowMove: true)
        #expect(moving.operationsWithinApp.operations == [.copy, .move])
        #expect(moving.operationsOutsideApp.operations == [.copy, .move], "on macOS a move may leave the app too")
        let deleting = DragConfiguration(allowMove: false, allowDelete: true)
        #expect(deleting.operationsWithinApp.operations == [.copy, .delete])
        var aliasing = DragConfiguration.OperationsWithinApp(allowCopy: false)
        aliasing.allowAlias = true
        #expect(aliasing.operations == [.alias])
        #expect(
            DragConfiguration(operationsWithinApp: .init(allowMove: true)).debugDescription
                == "DragConfiguration(operationsWithinApp: [.copy, .move], operationsOutsideApp: [.copy])")
    }

    @Test("A drop configuration names its operation, and accepts every item unless it says how many")
    func dropConfiguration() {
        var configuration = DropConfiguration(operation: .move)
        #expect(configuration.operation == .move)
        #expect(configuration.acceptedItemCount == nil)
        configuration.acceptedItemCount = 2
        #expect(configuration.acceptedItemCount == 2)
    }

    @Test("The five preview formations are distinct and describe themselves")
    func formations() {
        let all: [DragDropPreviewsFormation] = [.default, .list, .none, .pile, .stack]
        #expect(Set(all).count == 5)
        #expect(all.map(\.description) == [".default", ".list", ".none", ".pile", ".stack"])
    }
}
