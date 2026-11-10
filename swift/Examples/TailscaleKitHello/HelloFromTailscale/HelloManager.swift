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

/// Bounds for the reconnect delay after the IPN bus long poll fails.
let kMinBusRestartDelay: UInt64 = 1_000_000_000 // Nanos
let kMaxBusRestartDelay: UInt64 = 30_000_000_000

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

    // .initialStatus seeds the peer set; .peerChanges and .peerPatches keep it current.
    let busEventMask: Ipn.NotifyWatchOpt = [
        .initialState, .prefs, .initialStatus, .peerChanges, .peerPatches,
    ]

    private var busRestartDelay = kMinBusRestartDelay
    private var restartingBus = false

    init() {
        let temp = getDocumentDirectoryPath().path() + "tailscale"
        // A nil auth key puts the node on the interactive login path, which
        // surfaces a URL to visit via Ipn.Notify.BrowseToURL.
        self.config = Configuration(hostName: Settings.hostName,
                                    path: temp,
                                    authKey: Settings.authKey.isEmpty ? nil : Settings.authKey,
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
            // The initializer starts the node, which is all localAPI needs.  up() then
            // blocks until the node is authorized, so the bus watch has to be running
            // before we call it: a node awaiting login or machine approval never
            // finishes up(), and the bus is how we learn that (State, BrowseToURL).
            let node = try setupNode()

            // Create a localAPIClient instance for our local node
            let localAPIClient = LocalAPIClient(localNode: node, logger: logger)
            setLocalAPIClient(localAPIClient)

            await model.setBusHandlers(
                onNotify: { [weak self] in await self?.resetBusRestartDelay() },
                onError: { [weak self] in await self?.restartBusWatch() })

            try await startBusWatch()

            // Blocks until the node is authorized and usable.
            try await node.up()
            setReady(true)
        } catch {
            Logger().log("Error setting up Tailscale: \(error)")
            setReady(false)
        }
    }

    // This sets up a bus watcher to listen for changes to the tailnet.  These will be sent to the given consumer, in
    // this case, a HelloModel which will keep track of the changes and publish them.
    private func startBusWatch() async throws {
        guard let localAPIClient else { throw HelloError.noNode }
        setProcessor(try await localAPIClient.watchIPNBus(mask: busEventMask,
                                                          consumer: model))
    }

    /// Reconnects after the long poll behind the bus fails.  The new watch carries
    /// .initialStatus, so the model reseeds and no state is carried over the gap.
    func restartBusWatch() async {
        guard !restartingBus else { return }
        restartingBus = true
        defer { restartingBus = false }

        await processor?.cancel()
        processor = nil

        while true {
            logger.log("Reconnecting to the IPN bus in \(busRestartDelay / 1_000_000_000)s")
            try? await Task.sleep(nanoseconds: busRestartDelay)
            busRestartDelay = min(busRestartDelay * 2, kMaxBusRestartDelay)

            do {
                try await startBusWatch()
                return
            } catch {
                logger.log("Failed to reconnect to the IPN bus: \(error)")
            }
        }
    }

    func resetBusRestartDelay() {
        busRestartDelay = kMinBusRestartDelay
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

            await setMessage("Phoning " + Settings.tailnetURL + "...")

            // Create a URLSession that can access nodes on the tailnet.
            // .tailscaleSession(node) is the magic sauce.  This sends your URLRequest via
            // userspace Tailscale's SOCKS5 proxy.
            let (sessionConfig, _) = try await URLSessionConfiguration.tailscaleSession(node)
            let session = URLSession(configuration: sessionConfig)

            // Request a resource from the tailnet...
            let url = URL(string: Settings.tailnetURL)!
            let req = URLRequest(url: url)

            let (data, _) = try await session.data(for: req)
            await setMessage("\(Settings.tailnetURL) says:\n \(String(data: data, encoding: .utf8) ?? "(crickets!)")")
        } catch {
            await setMessage("Whoops!: \(error)")
        }
    }
}
