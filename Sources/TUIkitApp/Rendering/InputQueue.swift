//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputQueue.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Events waiting their turn

/// A first-in, first-out queue: where ``Terminal`` keeps the events one
/// sequence decoded to beyond the first, until ``Terminal/readEvent()`` hands
/// them out.
///
/// TUIkit's own rather than swift-collections' `Deque`, for the reason
/// ``InputByteBuffer`` gives.
///
/// An array of slots and the index of the first one still occupied. Appending
/// and removing from the front are amortised O(1): a removed slot is emptied at
/// once, so an event's payload (a paste's text) is not kept after it is handed
/// out, and the emptied slots are dropped from the array once they are at
/// least half of it, which moves no more elements than were removed since.
struct InputQueue<Element> {
    /// `nil` before `head`; every slot from `head` on holds an element.
    private var slots: [Element?] = []

    /// Index of the first occupied slot.
    private var head = 0

    /// How many elements are waiting.
    var count: Int { slots.count - head }

    /// Whether nothing is waiting.
    var isEmpty: Bool { head == slots.count }

    /// Adds `element` at the back.
    mutating func append(_ element: Element) {
        slots.append(element)
    }

    /// Adds `elements` at the back, in their order.
    mutating func append(contentsOf elements: some Sequence<Element>) {
        for element in elements { slots.append(element) }
    }

    /// Removes and returns the element at the front, or `nil` when nothing is
    /// waiting.
    mutating func popFirst() -> Element? {
        guard head < slots.count else { return nil }
        let element = slots[head]
        slots[head] = nil
        head += 1
        if head == slots.count {
            slots.removeAll(keepingCapacity: true)
            head = 0
        } else if head * 2 >= slots.count {
            slots.removeFirst(head)
            head = 0
        }
        return element
    }
}
