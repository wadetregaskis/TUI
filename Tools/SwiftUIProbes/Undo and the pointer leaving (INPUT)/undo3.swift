import Foundation

// Review follow-up (lane INPUT, 2026-10-18): does an undo group's user info
// (macOS 15) name the newest step, so a text control can ask whether its
// typing run's step is still the newest one in the app's undo manager?
final class Mark: NSObject {}
let key = UndoManager.UserInfoKey("tuikit.textStep")

@MainActor
func run() {
    func turn() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    func top(_ m: UndoManager) -> String {
        let value = m.undoActionUserInfoValue(forKey: key)
        return value.map { "\(ObjectIdentifier($0 as AnyObject).hashValue % 10000)" } ?? "nil"
    }
    // 1. Grouping by event: register, set the user info, turn the run loop.
    let m = UndoManager()
    let a = Mark(), b = Mark(), other = Mark()
    print("ids a", ObjectIdentifier(a).hashValue % 10000, "b", ObjectIdentifier(b).hashValue % 10000)
    m.registerUndo(withTarget: a) { _ in }
    m.setActionUserInfoValue(a, forKey: key)
    print("1 same pass: level", m.groupingLevel, "top", top(m), "undoCount", m.undoCount)
    turn()
    print("1 next pass: level", m.groupingLevel, "top", top(m), "undoCount", m.undoCount)
    // 2. Another registration with no user info, in a later pass.
    m.registerUndo(withTarget: other) { _ in }
    print("2 same pass: top", top(m), "undoCount", m.undoCount)
    turn()
    print("2 next pass: top", top(m), "undoCount", m.undoCount)
    // 3. Undo it: is ours the top again?
    m.undo(); turn()
    print("3 after undo of other: top", top(m), "undoCount", m.undoCount, "redo top", m.redoActionUserInfoValue(forKey: key).map { _ in "set" } ?? "nil")
    // 4. Explicit group, grouping by event off.
    let n = UndoManager()
    n.groupsByEvent = false
    n.beginUndoGrouping(); n.registerUndo(withTarget: b) { _ in }; n.setActionUserInfoValue(b, forKey: key); n.endUndoGrouping()
    print("4 explicit, set inside: top", top(n))
    // Set after the group's end, it raises: "must begin a group before
    // setting undo action user info" (measured; not run again here).
    // 5. A registration in the same pass as ours joins our group: still ours.
    let p = UndoManager()
    p.registerUndo(withTarget: a) { _ in }; p.setActionUserInfoValue(a, forKey: key)
    p.registerUndo(withTarget: other) { _ in }
    turn()
    print("5 same group: top", top(p), "undoCount", p.undoCount)
    // 6. Action name kept beside the user info?
    let q = UndoManager()
    q.registerUndo(withTarget: a) { _ in }; q.setActionName("Typing"); q.setActionUserInfoValue(a, forKey: key)
    turn()
    print("6 name", q.undoActionName.debugDescription, "top", top(q))
    // 7. removeAllActions(withTarget:) of the top step: what is the top then?
    let r = UndoManager()
    r.registerUndo(withTarget: b) { _ in }; r.setActionUserInfoValue(b, forKey: key); turn()
    r.registerUndo(withTarget: a) { _ in }; r.setActionUserInfoValue(a, forKey: key); turn()
    r.removeAllActions(withTarget: a)
    print("7 after removing the top step: top", top(r), "undoCount", r.undoCount)
}

MainActor.assumeIsolated { run() }

// 8. Does an undone step's user info go with it to the redo stack, and back?
@MainActor
func redoCarry() {
    func turn() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    final class Box: NSObject {}
    let m = UndoManager()
    let a = Box()
    func reg() {
        m.registerUndo(withTarget: a) { _ in reg() }
    }
    reg(); m.setActionUserInfoValue(a, forKey: key); turn()
    m.undo(); turn()
    print("8 after undo: undo top", m.undoActionUserInfoValue(forKey: key) == nil ? "nil" : "set",
          "redo top", m.redoActionUserInfoValue(forKey: key) == nil ? "nil" : "set")
    m.redo(); turn()
    print("8 after redo: undo top", m.undoActionUserInfoValue(forKey: key) == nil ? "nil" : "set")
}
MainActor.assumeIsolated { redoCarry() }
