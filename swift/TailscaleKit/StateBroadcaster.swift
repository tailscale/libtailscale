// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

/// Holds a current value and broadcasts changes to any number of independent
/// AsyncStream subscribers. New subscribers immediately receive the current
/// value (matching CurrentValueSubject semantics). Duplicate sets are
/// suppressed at the source (matching `removeDuplicates()`).
struct StateBroadcaster<Value: Equatable & Sendable>: ~Copyable {
    private(set) var value: Value
    private var continuations: [Int: AsyncStream<Value>.Continuation] = [:]
    private var nextID = 0

    init(_ initial: Value) {
        self.value = initial
    }

    deinit {
        // Dropping an unfinished continuation finishes its stream anyway;
        // this just makes that behavior explicit rather than incidental.
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    /// Sets a new value and notifies all live subscribers.
    /// No-op if the value is unchanged (removeDuplicates behavior).
    mutating func set(_ newValue: Value) {
        guard newValue != value else { return }
        value = newValue
        for (id, continuation) in continuations {
            // Lazily prune subscribers whose iteration was cancelled.
            if case .terminated = continuation.yield(newValue) {
                continuations[id] = nil
            }
        }
    }

    /// Returns a new stream that yields the current value immediately,
    /// then every subsequent (distinct) value.
    mutating func subscribe() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Value.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.yield(value)
        continuations[nextID] = continuation
        nextID += 1
        return stream
    }

    /// Ends all subscriber streams. Call this when the owning object
    /// reaches a terminal state (e.g. after yielding .closed).
    mutating func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}

/// StateBroadcaster must be owned by exactly one actor; it must never cross an
/// isolation boundary
/// TODO: Once the minimum toolchain is Swift 6.4, delete this extension and
/// add `~Sendable` to the type declaration instead (SE-0518; the swap is source-compatible).
@available(*, unavailable)
extension StateBroadcaster: Sendable {}
