/// Carries a non-Sendable value (an AXUIElement, a CF object) from a C
/// callback that already runs on the main thread into `MainActor.assumeIsolated`.
/// Only for values that never leave the main thread.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
