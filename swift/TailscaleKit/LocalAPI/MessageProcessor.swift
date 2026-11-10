// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

let kJsonNewline = UInt8(ascii: "\n")

/// A MessageConsumer consumes incoming messages from the IPNBus and handles any
/// potential errors.
public protocol MessageConsumer: Actor {
    /// Invoked once per Notify, in arrival order.  Peer deltas are
    /// order-dependent, so the implementation must complete all state
    /// mutation before returning.
    func notify(_ notify: Ipn.Notify) async
    func error(_ error: any Error)
}


/// MessageProcessor reads messages from a MessageReader, deserializes them and
/// forwards the deserialized objects and any errors to the consumer.
///
/// Messages are processed in the actor's context, which serializes the
/// operations so order is maintained.
public actor MessageProcessor {
    let consumer: any MessageConsumer
    let reader: MessageReader
    let logger: LogSink?

    var pollTask: Task<Void, Never>?

    init(consumer: any MessageConsumer, logger: LogSink?) async {
        self.logger = logger
        self.consumer = consumer
        self.reader = MessageReader(logger: logger)
    }

    func start(_ request: URLRequest,
               config: URLSessionConfiguration,
               errorHandler: (@Sendable (any Error) -> Void)? = nil) {
        logger?.log("Starting MessageProcessor for \(request.url?.absoluteString ?? "nil")")

        let errorHandler = errorHandler ?? { [weak self] error in
            self?.processError(error)
        }

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let messages = await reader.start(request, config: config)
            await watchMessageQueue(messages, errorHandler: errorHandler)
        }
    }

    /// Ends the subscription, closing the underlying long poll.
    public func cancel() async {
        pollTask?.cancel()
        pollTask = nil
        await reader.stop()
    }

    /// Consumes messages in arrival order until the poll task is cancelled, the reader is
    /// stopped, or the long poll fails.  Failures are handed to errorHandler, which is
    /// responsible for restarting the bus.
    func watchMessageQueue(_ messages: AsyncThrowingStream<Data, any Error>,
                           errorHandler: @escaping @Sendable (any Error) -> Void) async {
        logger?.log("Watching MessageReader")
        do {
            for try await data in messages {
                if Task.isCancelled { break }
                await processMessage(data)
            }
        } catch {
            errorHandler(error)
        }
        logger?.log("Unwatching MessageReader")
    }

    func processMessage(_ data: Data) async {
        let lines = data.split(separator: kJsonNewline)
        for line in lines {
            do {
                let notify = try JSONDecoder().decode(Ipn.Notify.self, from: line)
                // No spawned tasks here.  Ordering is critical.
                await consumer.notify(notify)
            } catch {
                logger?.log("Failed to decode message: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func processError(_ error: some Error) {
        Task {
            await consumer.error(error)
        }
    }
}
