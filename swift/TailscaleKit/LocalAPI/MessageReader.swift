// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

public enum MessageProcessorError: Error, Equatable {
    case busClosedUnexpectedly
}

/// MessageStreamDelegate owns all of the mutable state belonging to a single URLSession:
/// the partial message buffer and the continuation for the stream of completed messages.
///
/// Everything here runs on `queue`, the serial OperationQueue that the owning session
/// delivers its callbacks on, so messages are yielded in arrival order without locking.
final class MessageStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// The serial delegate queue for the owning session.  All state in this class is
    /// confined to it.
    let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation

    /// Holds partial incoming messages.  Must only be read/mutated on `queue`.
    private(set) var buffer = Data()

    init(continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    /// Ends the message stream without an error.  Idempotent, and safe to call from
    /// any thread.
    func finish() {
        continuation.finish()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        receive(data)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: (any Error)?) {
        complete(with: error)
    }

    // MARK: - Queue confined state

    /// Buffers `data`, yielding to the stream once we have at least one complete line.
    /// LocalAPI bus messages are line delimited.
    /// Must be invoked on `queue`.
    func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.last == kJsonNewline else { return }
        continuation.yield(buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    /// Ends the message stream, reporting `error` to the consumer unless the session
    /// was cancelled deliberately.  Must be invoked on `queue`.
    func complete(with error: (any Error)?) {
        // Anything still buffered was cut off mid-line and can never be parsed.
        buffer.removeAll()

        guard let error else {
            // The long poll went away without telling us why.
            continuation.finish(throwing: MessageProcessorError.busClosedUnexpectedly)
            return
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            // Deliberate cancellation, not a failure.
            continuation.finish()
            return
        }

        continuation.finish(throwing: error)
    }
}

/// MessageReader manages the URLSession long poll against the IPN bus and vends an
/// ordered stream of newline delimited messages from it.
actor MessageReader {
    private var session: URLSession?
    private var delegate: MessageStreamDelegate?

    let logger: LogSink?

    init(logger: LogSink? = nil) {
        self.logger = logger
    }

    /// (Re)starts the long poll, discarding any existing session and its pending
    /// messages, and returns the message stream for the new session.
    ///
    /// The stream ends when the session is stopped, and throws if the long poll fails
    /// or closes unexpectedly.  Abandoning the stream stops the long poll: the reader
    /// deliberately doesn't hold on to the stream, so the consumer's iteration is what
    /// keeps the session alive.
    func start(_ request: URLRequest,
               config: URLSessionConfiguration) -> AsyncThrowingStream<Data, any Error> {
        stop()

        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let delegate = MessageStreamDelegate(continuation: continuation)
        let session = URLSession(configuration: config,
                                 delegate: delegate,
                                 delegateQueue: delegate.queue)

        continuation.onTermination = { [weak session] _ in
            session?.invalidateAndCancel()
        }

        self.session = session
        self.delegate = delegate

        session.dataTask(with: request).resume()
        logger?.log("Started IPN watch session")

        return stream
    }

    /// Cancels the long poll and ends the message stream.
    func stop() {
        guard let session else { return }
        logger?.log("Stopping IPN watch session")

        delegate?.finish()
        session.invalidateAndCancel()

        self.session = nil
        self.delegate = nil
    }
}
