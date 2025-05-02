// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import TailscaleKit

enum HelloError: Error {
    case noNode
}

typealias MessageSender = @Sendable (String) async  -> Void

struct Logger: TailscaleKit.LogSink {
    var logFileHandle: Int32? = STDOUT_FILENO

    func log(_ message: String) {
        print("hello: \(message)")
    }
}

protocol Dialer: Actor {
    func phoneHome(_ setMessage: @escaping MessageSender) async
}

actor HelloManager: Dialer {
    var node: TailscaleNode?

    static let shared = HelloManager()

    let logger = Logger()

    let config: Configuration
    var ready = false

    // The model will be the consumer for our the busWatcher
    let model: HelloModel

    var localAPIClient: LocalAPIClient?
    var processor: MessageProcessor?

    init() {
        let temp = getDocumentDirectoryPath().path() + "tailscale"
        self.config = Configuration(hostName: Settings.hostName,
                                    path: temp,
                                    authKey: Settings.authKey,
                                    controlURL: kDefaultControlURL,
                                    ephemeral: true)

        let model = HelloModel(logger: logger)
        self.model = model

        Task {
            await startTailscale()
        }
    }

    private func startTailscale() async {
        do {
            /// This sets up a localAPI client attached to the local node.
            let node = try setupNode()
            try await node.up()
            let localAPIClient = LocalAPIClient(localNode: node, logger: logger)

            // Once we have our local node, we can set up the local API client.
            setLocalAPIClient(localAPIClient)
            setReady(true)

            /// This sets up a bus watcher to listen for changes in the netmap.  These will be sent to the given consumer, uin
            /// this case, a HelloModel which will keep track of the changes and publish them.
            if let processor = await localAPIClient.watchIPNBus(mask: [.initialState, .netmap, .rateLimitNetmaps, .noPrivateKeys],
                                                                consumer: model) {
                setProcessor(processor)
            }
        } catch {
            Logger().log("Error setting up Tailscale: \(error)")
            setReady(false)
        }
    }

    func setLocalAPIClient(_ client: TailscaleKit.LocalAPIClient) {
        self.localAPIClient = client
    }

    func setReady(_ value: Bool) {
        self.ready = value
    }

    func setProcessor(_ processor: MessageProcessor) {
        self.processor = processor
    }

    func setupNode() throws -> TailscaleNode {
        guard self.node == nil else { return self.node! }
        self.node = try TailscaleNode(config: config, logger: logger)
        return self.node!
    }

    func phoneHome(_ setMessage: @escaping MessageSender) async {
        do {
            guard let node, ready else {
                await setMessage("Not ready yet!")
                return
            }

            await setMessage("Phoning " + Settings.tailnetServer + "...")

            // Create a URLSession that can access nodes on the tailnet.
            // .tailscaleSession(node) is the magic sauce.  This sends your URLRequest via
            // userspace Tailscale's SOCKS5 proxy.
            let (sessionConfig, _) = try await URLSessionConfiguration.tailscaleSession(node)
            let session = URLSession(configuration: sessionConfig)

            // Request a resource from the tailnet...
            let url = URL(string: Settings.tailnetServer)!
            var req = URLRequest(url: url)


            let (data, _) = try await session.data(for: req)
            await setMessage("\(Settings.tailnetServer) says:\n \(String(data: data, encoding: .utf8) ?? "(crickets!)")")
        } catch {
            await setMessage("Whoops!: \(error)")
        }
    }
}
