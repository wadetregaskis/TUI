//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputByteBufferTests.swift
//
//  The two buffers the terminal's input parser reads from, on their own:
//  `InputByteBuffer` (the bytes read and not yet parsed) and `InputQueue` (the
//  events one sequence decoded to beyond the first). TUIkit's own since they
//  replaced swift-collections' `UniqueDeque` and `Deque`; what they must keep
//  from those is order, O(1) work at the front, and copying that stays linear
//  in the bytes read, which `bytesMoved` counts.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp

extension InputByteBuffer {
    /// The live bytes, front first.
    fileprivate var contents: [UInt8] { (0..<count).map { self[$0] } }
}

@Suite("The input byte buffer")
struct InputByteBufferTests {

    @Test("An empty buffer holds nothing and pops nothing")
    func empty() {
        var buffer = InputByteBuffer(minimumCapacity: 16)
        #expect(buffer.isEmpty)
        #expect(buffer.capacity == 16)
        #expect(buffer.popFirst() == nil)
        buffer.removeFirst(0)
        #expect(buffer.isEmpty)
        #expect(InputByteBuffer(minimumCapacity: 0).capacity == 1, "room for one byte at least")
    }

    @Test("Bytes come out in the order they went in")
    func order() {
        var buffer = InputByteBuffer(minimumCapacity: 16)
        buffer.append(contentsOf: [1, 2, 3])
        buffer.append(contentsOf: [])
        buffer.append(contentsOf: [4])
        #expect(buffer.contents == [1, 2, 3, 4])
        #expect(buffer[0] == 1 && buffer[3] == 4)
        #expect(buffer.popFirst() == 1)
        buffer.removeFirst(2)
        #expect(buffer.contents == [4])
        #expect(buffer.popFirst() == 4)
        #expect(buffer.popFirst() == nil)
        #expect(buffer.isEmpty)
    }

    @Test("A buffer emptied from the front starts again at its first byte, moving nothing")
    func emptiedBufferRestartsAtTheFront() {
        var buffer = InputByteBuffer(minimumCapacity: 8)
        buffer.append(contentsOf: [1, 2, 3, 4, 5, 6])
        buffer.removeFirst(6)
        buffer.append(contentsOf: [7, 8, 9, 10, 11, 12, 13, 14])
        #expect(buffer.contents == [7, 8, 9, 10, 11, 12, 13, 14])
        #expect(buffer.capacity == 8, "all eight fit from the front: no growth")
        #expect(buffer.bytesMoved == 0)
    }

    @Test("Appending past the end slides the unread bytes to the front")
    func wraparoundSlides() {
        var buffer = InputByteBuffer(minimumCapacity: 8)
        buffer.append(contentsOf: [1, 2, 3, 4, 5, 6])
        buffer.removeFirst(4)
        buffer.append(contentsOf: [7, 8, 9, 10])
        #expect(buffer.contents == [5, 6, 7, 8, 9, 10])
        #expect(buffer.capacity == 8, "six bytes fit in eight once the two unread ones slide down")
        #expect(buffer.bytesMoved == 2, "only the two unread bytes moved")
    }

    @Test("A slide that would move more bytes than were removed grows the buffer instead")
    func expensiveSlideGrows() {
        var buffer = InputByteBuffer(minimumCapacity: 8)
        buffer.append(contentsOf: [1, 2, 3, 4, 5, 6, 7, 8])
        buffer.removeFirst(1)
        buffer.append(contentsOf: [9])
        #expect(buffer.contents == [2, 3, 4, 5, 6, 7, 8, 9])
        #expect(buffer.capacity == 12, "grown by half rather than seven bytes moved for one removed")
        #expect(buffer.bytesMoved == 7, "growth copies the seven live bytes once")
    }

    @Test("Growth keeps every byte, in order")
    func growth() {
        var buffer = InputByteBuffer(minimumCapacity: 4)
        var expected: [UInt8] = []
        for start in stride(from: 0, to: 200, by: 3) {
            let chunk = (start..<min(start + 3, 200)).map { UInt8($0) }
            buffer.append(contentsOf: chunk)
            expected += chunk
        }
        #expect(buffer.contents == expected)
        #expect(buffer.capacity >= 200)
        #expect(buffer.capacity < 300, "grown by half at a time, not doubled past what it needed twice over")
    }

    @Test("A byte put back at the front reuses the room the parser took it from")
    func prependReusesTheRoomInFront() {
        var buffer = InputByteBuffer(minimumCapacity: 8)
        buffer.append(contentsOf: [0x1B, 0x5B, 0x41])
        buffer.removeFirst(1)
        buffer.prepend(0x1B)
        #expect(buffer.contents == [0x1B, 0x5B, 0x41])
        #expect(buffer.bytesMoved == 0)
    }

    @Test("Bytes put back where there is no room in front move the live ones up")
    func prependWithoutRoomMovesTheLiveBytes() {
        var buffer = InputByteBuffer(minimumCapacity: 8)
        buffer.append(contentsOf: [0x5B, 0x5A])
        buffer.prepend(contentsOf: [0x1B, 0x1B])
        #expect(buffer.contents == [0x1B, 0x1B, 0x5B, 0x5A])
        #expect(buffer.bytesMoved == 2)

        var empty = InputByteBuffer(minimumCapacity: 8)
        empty.prepend(0x1B)
        #expect(empty.contents == [0x1B])
        empty.prepend(contentsOf: [])
        #expect(empty.contents == [0x1B])
    }

    @Test("Bytes put back at the front of a full buffer grow it")
    func prependIntoAFullBufferGrows() {
        var buffer = InputByteBuffer(minimumCapacity: 4)
        buffer.append(contentsOf: [1, 2, 3, 4])
        buffer.prepend(contentsOf: [8, 9])
        #expect(buffer.contents == [8, 9, 1, 2, 3, 4])
        #expect(buffer.capacity >= 6)
    }

    @Test("A read is given exactly the room asked for, after the bytes already there")
    func readIsGivenTheRoomAskedFor() {
        var buffer = InputByteBuffer(minimumCapacity: 8)
        buffer.append(contentsOf: [1, 2])
        var offered = -1
        let added = buffer.append(upTo: 5) { room in
            offered = room.count
            room[0] = 3
            room[1] = 4
            room[2] = 5
            return 3
        }
        #expect(offered == 5)
        #expect(added == 3)
        #expect(buffer.contents == [1, 2, 3, 4, 5], "only the bytes the read wrote are kept")
    }

    @Test("A read that wrote nothing, or failed, adds nothing", arguments: [0, -1])
    func emptyOrFailedReadAddsNothing(result: Int) {
        var buffer = InputByteBuffer(minimumCapacity: 8)
        buffer.append(contentsOf: [1])
        let added = buffer.append(upTo: 4) { room in
            room[0] = 9
            return result
        }
        #expect(added == 0)
        #expect(buffer.contents == [1])
    }

    @Test("A read larger than the buffer grows it first")
    func largeReadGrows() {
        var buffer = InputByteBuffer(minimumCapacity: 4)
        buffer.append(contentsOf: [1])
        let added = buffer.append(upTo: 10) { room in
            for index in room.indices { room[index] = UInt8(index + 2) }
            return room.count
        }
        #expect(added == 10)
        #expect(buffer.contents == Array(1...11))
    }

    @Test("Reallocating gives the storage back and keeps every live byte")
    func reallocate() {
        var buffer = InputByteBuffer(minimumCapacity: 4)
        buffer.append(contentsOf: Array(0..<100))
        buffer.removeFirst(90)
        buffer.reallocate(capacity: 16)
        #expect(buffer.capacity == 16)
        #expect(buffer.contents == Array(90..<100))

        buffer.reallocate(capacity: 4)
        #expect(buffer.capacity == 10, "never smaller than the live bytes")
        #expect(buffer.contents == Array(90..<100))
    }

    /// The pattern a slide-whenever-it-fits rule makes quadratic: a nearly full
    /// buffer that loses one byte from the front and gains one at the back, over
    /// and over. With the rule swapped in — slide whenever the live bytes and
    /// the request fit — this moved 20.5 million bytes (measured 2026-10-10);
    /// growing until the room in front pays for a slide moves a few times what
    /// goes in.
    @Test("One byte out, one byte in, over a full buffer, copies linearly")
    func steadyTrickleCopiesLinearly() {
        var buffer = InputByteBuffer(minimumCapacity: 4096)
        buffer.append(contentsOf: [UInt8](repeating: 7, count: 4095))
        var appended = 4095
        for step in 0..<10_000 {
            buffer.removeFirst(1)
            buffer.append(contentsOf: [UInt8(truncatingIfNeeded: step)])
            appended += 1
        }
        #expect(buffer.count == 4095)
        #expect(buffer[4094] == UInt8(truncatingIfNeeded: 9999))
        #expect(buffer.bytesMoved <= 4 * appended, "\(buffer.bytesMoved) bytes moved for \(appended) appended")
        #expect(buffer.capacity <= 4 * 4096, "the buffer settles rather than growing without end")
    }

    /// A paste: nothing is removed until its end arrives, so every drain adds
    /// a read's worth and the buffer only grows. Growth by half copies at most
    /// three times what was appended in all.
    @Test("A megabyte read in 4 KiB pieces copies linearly")
    func pasteSizedGrowthCopiesLinearly() {
        var buffer = InputByteBuffer(minimumCapacity: 4096)
        var appended = 0
        while appended < 1 << 20 {
            appended += buffer.append(upTo: 4096) { room in
                for index in room.indices { room[index] = UInt8(truncatingIfNeeded: index) }
                return room.count
            }
        }
        #expect(buffer.count == appended)
        #expect(buffer.bytesMoved <= 3 * appended, "\(buffer.bytesMoved) bytes moved for \(appended) appended")
    }

    /// What a paste's end-marker scan finds each `ESC` with: offsets from the
    /// front, however far the front has moved into the storage, and only
    /// within the range asked about.
    @Test("A byte is found by its offset from the front, within the range searched")
    func firstIndexWithinRange() {
        var buffer = InputByteBuffer(minimumCapacity: 16)
        buffer.append(contentsOf: [9, 9, 9, 1, 0x1B, 2, 3, 0x1B, 4])
        buffer.removeFirst(3)
        #expect(buffer.firstIndex(of: 0x1B, in: 0..<6) == 1)
        #expect(buffer.firstIndex(of: 0x1B, in: 2..<6) == 4)
        // Compared with a named `nil`: SwiftLint takes `firstIndex(…) == nil` for
        // the collection method and asks for `contains`, which this has not.
        let notFound: Int? = nil
        #expect(buffer.firstIndex(of: 0x1B, in: 2..<4) == notFound, "the second ESC is past the range")
        #expect(buffer.firstIndex(of: 0x1B, in: 1..<1) == notFound)
        #expect(buffer.firstIndex(of: 9, in: 0..<6) == notFound, "the bytes removed from the front are not searched")
    }
}

@Suite("The input event queue")
struct InputQueueTests {

    @Test("An empty queue pops nothing")
    func empty() {
        var queue = InputQueue<Int>()
        #expect(queue.isEmpty)
        #expect(queue.popFirst() == nil)
    }

    @Test("Elements come out in the order they went in, appended singly or together")
    func order() {
        var queue = InputQueue<Int>()
        queue.append(1)
        queue.append(contentsOf: [2, 3])
        #expect(queue.count == 3)
        #expect(queue.popFirst() == 1)
        queue.append(4)
        #expect(queue.popFirst() == 2)
        #expect(queue.popFirst() == 3)
        #expect(queue.popFirst() == 4)
        #expect(queue.popFirst() == nil)
        #expect(queue.isEmpty)
    }

    @Test("A queue that never empties keeps its order")
    func neverEmptyingQueueKeepsOrder() {
        var queue = InputQueue<Int>()
        var next = 0
        var expected = 0
        for _ in 0..<1000 {
            queue.append(next)
            queue.append(next + 1)
            next += 2
            #expect(queue.popFirst() == expected)
            expected += 1
        }
        #expect(queue.count == 1000)
        while let element = queue.popFirst() {
            #expect(element == expected)
            expected += 1
        }
        #expect(expected == 2000)
    }

    private final class Payload {}

    @Test("An element handed out is not kept by the queue")
    func poppedElementIsReleased() {
        var queue = InputQueue<Payload>()
        weak var first: Payload?
        do {
            let payload = Payload()
            first = payload
            queue.append(payload)
            queue.append(Payload())
            queue.append(Payload())
        }
        #expect(first != nil)
        _ = queue.popFirst()
        #expect(first == nil, "the queue still held the payload it had handed out")
        #expect(queue.count == 2)
    }
}
