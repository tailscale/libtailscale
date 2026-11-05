// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import XCTest
@testable import TailscaleKit

/// Covers the per-session state of the IPN bus reader: message framing and the
/// session completion paths.
final class MessageStreamDelegateTests: XCTestCase {
    /// Consumes messages to completion, returning the error the stream threw, if any.
    private func drain(_ messages: AsyncThrowingStream<Data, any Error>) async -> (any Error)? {
        do {
            for try await _ in messages {}
            return nil
        } catch {
            return error
        }
    }

    /// Messages must reach the stream in the order the session delivered them, even when
    /// the delegate queue is handed work faster than it drains it.
    func test_sequencing() async throws {
        let (messages, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)

        // Don't forget the newlines... We read until a newline...
        let sequence = ["the", "quick", "brown", "fox", "jumped", "over", "the", "lazy", "dog"]
        let want = sequence.reduce("", { $0 + $1 + "\n" })

        for s in sequence {
            delegate.queue.addOperation {
                let ms = Int.random(in: 5...25)
                Thread.sleep(forTimeInterval: Double(ms) / 1000.0)
                delegate.receive(Data((s + "\n").utf8))
            }
        }

        var got = ""
        var count = 0
        for try await data in messages {
            got.append(String(decoding: data, as: UTF8.self))
            count += 1
            if count == sequence.count { break }
        }
        XCTAssertEqual(got, want)
    }

    /// A message split across reads stays buffered until its newline arrives.
    func test_multiline_data() {
        let (messages, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)

        delegate.receive(Data("{".utf8))
        delegate.receive(Data("}\n".utf8))
        XCTAssertEqual(delegate.buffer.count, 0)

        delegate.receive(Data("{".utf8))
        XCTAssertEqual(delegate.buffer.count, 1)

        withExtendedLifetime(messages) {}
    }

    /// An empty read must not be mistaken for a complete line, with or without a
    /// partial message already buffered.
    func test_empty_data() {
        let (messages, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)

        delegate.receive(Data())
        XCTAssertEqual(delegate.buffer.count, 0)

        delegate.receive(Data("{".utf8))
        delegate.receive(Data())
        XCTAssertEqual(delegate.buffer.count, 1)

        withExtendedLifetime(messages) {}
    }

    /// Stopping the reader ends the stream so the processor's loop exits.
    func test_finish_ends_stream() async {
        let (messages, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)

        delegate.finish()

        let err = await drain(messages)
        XCTAssertNil(err)
    }

    /// A long poll that completes without an error has closed out from under us.  That
    /// must surface as an error so the consumer restarts the bus.
    func test_unexpected_close_is_an_error() async {
        let (messages, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)

        delegate.complete(with: nil)

        let err = await drain(messages)
        XCTAssertEqual(err as? MessageProcessorError, .busClosedUnexpectedly)
    }

    /// Cancellation is deliberate, so it ends the stream cleanly rather than kicking off
    /// a restart.
    func test_cancellation_is_not_an_error() async {
        let (messages, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)

        delegate.complete(with: NSError(domain: NSURLErrorDomain,
                                        code: NSURLErrorCancelled,
                                        userInfo: nil))

        let err = await drain(messages)
        XCTAssertNil(err)
    }

    /// Any other session failure is reported to the consumer.
    func test_session_error_is_reported() async {
        let (messages, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)

        let want = NSError(domain: NSURLErrorDomain,
                           code: NSURLErrorNetworkConnectionLost,
                           userInfo: nil)
        delegate.complete(with: want)

        let err = await drain(messages)
        XCTAssertEqual(err as? NSError, want)
    }

    /// A partial message left over from a failed session is discarded, not carried into
    /// whatever reads the stream next.
    func test_partial_message_is_discarded_on_completion() {
        let (messages, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)

        delegate.receive(Data("{\"partial\":".utf8))
        delegate.complete(with: nil)
        XCTAssertEqual(delegate.buffer.count, 0)

        withExtendedLifetime(messages) {}
    }
}
