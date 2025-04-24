// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum MessageQueueError: Error {
    case queueCongested
}

/// The maximum number of unprocessed messages that can be queued before we start discarding
/// This needs to be large enough to handle the bursty "first time" connection messages but
/// small enough to avoid our memory footprint growing arbitrarily large.
let kMaxQueueSize = 24

/// Provides a queue for incoming messages on the IPN bus.  This will keep a maximum of
/// the last kMaxQueueSize inbound messages pending processing. If the queue is congested, we will
/// stop queueing messages and throw an error once the queue has been drained.
final class MessageReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// All mutation and reading of local state happens in workQueue.
    let workQueue = OperationQueue()

    /// Holds partial incoming messages
    var buffer: Data = Data()
    var ipnWatchSession: URLSession?
    var dataTask: URLSessionDataTask?

    var logger: LogSink?

    /// FIFO queue for messages awaiting processing
    var pendingMessages: [Data] = []

    /// Once congested, we will allow the processor to empty the queue, but we will stop queueing messages.
    /// consume()ing the last messages will trigger a MessageQueueError.queueCongested error which the
    /// upstream consumer can use.  Typically, this means we lost messages, so the correct action is to
    /// restart the processor and queue with an .initialState flag.
    var congested = false

    var errorHandler: (@Sendable (Error) -> Void)?

    init(logger: LogSink? = nil) {
        self.logger = logger
        workQueue.maxConcurrentOperationCount = 1
        workQueue.name = "io.tailscale.ipn.MessageReader.workQueue"
    }

    func stop() {
        ipnWatchSession?.invalidateAndCancel()
        workQueue.cancelAllOperations()
    }

    func start(_ request: URLRequest, config: URLSessionConfiguration, errorHandler: @escaping @Sendable (Error) -> Void  ) {
        workQueue.addOperation { [weak self] in
            guard let self = self else { return }

            self.errorHandler = errorHandler

            buffer = Data()
            pendingMessages = []
            congested = false

            dataTask?.cancel()
            ipnWatchSession?.invalidateAndCancel()

            ipnWatchSession = URLSession(configuration: config,
                                         delegate: self,
                                         delegateQueue: workQueue)

            dataTask = ipnWatchSession?.dataTask(with: request)
            dataTask?.resume()
        }
    }

    func consume(_ completion: @escaping @Sendable (Data?) -> Void) {
        workQueue.addOperation { [weak self] in
            guard let self else { return }
            if congested && pendingMessages.count == 0 {
                errorHandler?(MessageQueueError.queueCongested)
                completion(nil)
                return
            }

            guard pendingMessages.count > 0 else {
                completion(nil)
                return
            }
            completion(pendingMessages.removeFirst())
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            // Ignore cancellation errors, those are deliberate.
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            errorHandler?(error)
        }
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        if congested {
            return
        }
        receiveData(data)
    }

    func receiveData(_ data: Data) {
        workQueue.addOperation { [weak self] in
            guard let self else { return }

            buffer.append(data)
            if buffer[buffer.count - 1] == kJsonNewline {
                if pendingMessages.count >= kMaxQueueSize {
                    congested = true
                    return
                }
                pendingMessages.append(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
    }
}
