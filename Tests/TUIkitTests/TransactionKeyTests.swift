//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransactionKeyTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

private struct Flag: TransactionKey {
    static let defaultValue = false
}

private struct Count: TransactionKey {
    static let defaultValue = 0
}

/// A value with no `==`: equal only to itself.
private final class Token: Sendable {}

private struct TokenKey: TransactionKey {
    static let defaultValue: Token? = nil
}

extension Transaction {
    fileprivate var flag: Bool {
        get { self[Flag.self] }
        set { self[Flag.self] = newValue }
    }
}

@MainActor
@Suite("Custom transaction values")
struct TransactionKeyTests {

    @Test("An unset key reads its default; a set one, its value")
    func defaultsAndValues() {
        var transaction = Transaction()
        #expect(transaction[Flag.self] == false)
        #expect(transaction[Count.self] == 0)
        transaction[Count.self] = 3
        transaction.flag = true
        #expect(transaction[Count.self] == 3)
        #expect(transaction.flag)
    }

    @Test("A copy is a value: changing it leaves the original alone")
    func copyOnWrite() {
        var original = Transaction()
        original[Count.self] = 1
        var copy = original
        copy[Count.self] = 2
        #expect(original[Count.self] == 1)
        #expect(copy[Count.self] == 2)
    }

    @Test("Equal values make equal transactions; different ones do not")
    func equality() {
        var lhs = Transaction()
        var rhs = Transaction()
        #expect(lhs == rhs)
        lhs[Count.self] = 1
        #expect(lhs != rhs)
        rhs[Count.self] = 1
        #expect(lhs == rhs, "two settings of one Equatable value compare by ==")
        rhs[Count.self] = 2
        #expect(lhs != rhs)
    }

    @Test("A value that cannot be compared equals only itself")
    func incomparableValues() {
        var transaction = Transaction()
        transaction[TokenKey.self] = Token()
        let copy = transaction
        #expect(transaction == copy, "a copy carries the same value")
        var other = Transaction()
        other[TokenKey.self] = transaction[TokenKey.self]
        #expect(transaction != other, "set again, it is not known to be the same")
    }

    @Test("Continuous and velocity-tracking are switches of their own")
    func switches() {
        var transaction = Transaction()
        #expect(!transaction.isContinuous && !transaction.tracksVelocity)
        transaction.isContinuous = true
        #expect(transaction.isContinuous && !transaction.tracksVelocity && !transaction.disablesAnimations)
        transaction.tracksVelocity = true
        transaction.isContinuous = false
        #expect(!transaction.isContinuous && transaction.tracksVelocity)
        #expect(transaction != Transaction())
    }

    @Test("withTransaction(keyPath:) sets one value on the transaction around it")
    func keyPathForm() {
        withAnimation(.linear(duration: 1)) {
            withTransaction(\.flag, true) {
                #expect(Transaction.ambient?.flag == true)
                #expect(Transaction.ambient?.animation == .linear(duration: 1), "composes with the enclosing animation")
            }
        }
        withTransaction(\.isContinuous, true) {
            #expect(Transaction.ambient?.isContinuous == true)
            #expect(Transaction.ambient?.animation == nil)
        }
        #expect(Transaction.ambient == nil)
    }

    @Test("A view's transaction modifier reads a custom value the change was made with")
    func valueReachesTheView() {
        var seen: [Bool] = []
        var context = makeRenderContext(width: 8, height: 1)
        var transaction = Transaction()
        transaction.flag = true
        context.environment.transaction = transaction
        _ = renderToBuffer(
            Text("x").transaction { seen.append($0.flag) }, context: context)
        #expect(seen.contains(true))
    }

    @Test("A transaction's custom values cost a word, with no interior padding")
    func layout() {
        // The extras lead: a reference before the 81-byte animation and the
        // byte switches after it pads nothing (84 with the 73-byte animation
        // before `logicallyComplete(after:)` added a word to it).
        #expect(MemoryLayout<Transaction>.size == 92)
        #expect(interiorPadding(of: Transaction.self).isEmpty)
    }
}
