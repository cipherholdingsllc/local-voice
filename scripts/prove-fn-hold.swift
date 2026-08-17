import Foundation

@main
enum FnHoldReconcileProve {
    static func expect(_ cond: Bool, _ message: String) {
        if !cond {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        expect(
            HotkeyHoldReconcile.action(
                keyHeld: true,
                physicallyDown: false,
                lockEngaged: false
            ) == .endHold,
            "missed up should end hold"
        )
        expect(
            HotkeyHoldReconcile.action(
                keyHeld: false,
                physicallyDown: true,
                lockEngaged: false
            ) == .startHold,
            "missed down should start hold"
        )
        expect(
            HotkeyHoldReconcile.action(
                keyHeld: true,
                physicallyDown: false,
                lockEngaged: true
            ) == .none,
            "lock must not end on missed up"
        )
        expect(
            HotkeyHoldReconcile.action(
                keyHeld: true,
                physicallyDown: true,
                lockEngaged: false
            ) == .none,
            "stable hold is a no-op"
        )
        print("PASS: fn-hold reconcile")
    }
}
