// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

let kJsonNewline = UInt8(ascii: "\n")

/// The polling interval for the message queue
let kProcessorQueuePollInterval: UInt64 = 100_000_000 // Nanos

/// A MessageConsumer consumes incoming messages from the IPNBus and handles any
/// potential errors.
public protocol MessageConsumer: Actor {
     func notify(_ notify: Ipn.Notify)
     func error(_ error: Error)
}


/// MessageProcessor pulls queued Decodable messages from a MessageReader, deserializes them
/// and forwards the deserialized objects and any errors to the consumer.
public class MessageProcessor: @unchecked Sendable {
    let consumer: any MessageConsumer
    let reader: MessageReader
    let workQueue = OperationQueue()
    var logger: LogSink?


    // A long running task to poll the queue
    var pollTask: Task<Void, Error>?

    init(consumer: any MessageConsumer, logger: LogSink?) async {
        workQueue.maxConcurrentOperationCount = 1
        workQueue.name = "io.tailscale.ipn.MessageProcessor.workQueue"

        self.logger = logger
        self.consumer = consumer
        self.reader = MessageReader()
    }

    deinit {
        cancel()
        reader.stop()
    }

    func start(_ request: URLRequest, config: URLSessionConfiguration, errorHandler: (@Sendable (Error) -> Void)? = nil) {
        workQueue.addOperation { [weak self] in
            guard let self = self else { return }
            logger?.log("Starting MessageProcessor for \(request.url?.absoluteString ?? "nil")")
            cancel()
            let errorHandler = errorHandler ?? { [weak self] error in
                self?.processError(error)
            }

            reader.start(request, config: config, errorHandler: errorHandler)
            startMessageQueuePoll()
        }
    }

    public  func cancel() {
        pollTask?.cancel()
    }

    func startMessageQueuePoll() {
        pollTask?.cancel()
        pollTask = Task {
            await watchMessageQueue()
        }
    }

    func watchMessageQueue() async {
        logger?.log("Watching MessageReader")
        while !Task.isCancelled {
            reader.consume { [weak self] data in
                if let data {
                    self?.processMessage(data)
                }
            }
            try? await Task.sleep(nanoseconds: kProcessorQueuePollInterval)
        }
        logger?.log("Unwatching MessageReader")
    }

    func processMessage(_ data: Data) {
        workQueue.addOperation { [weak self] in
            guard let self else { return }
            let lines = data.split(separator: kJsonNewline)
            for line in lines {
                do {
                    let notify = try JSONDecoder().decode(Ipn.Notify.self, from: line)
                    Task {
                        await consumer.notify(notify)
                    }
                } catch {
                    logger?.log("Failed to decode message: \(error.localizedDescription)")
                }
            }
        }
    }

    func processError(_ error: Error) {
        Task {
            await consumer.error(error)
        }
    }
}
