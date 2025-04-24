// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import TailscaleKit

actor HelloModel: MessageConsumer {
    private let logger: LogSink

    init(logger: LogSink) {
        self.logger = logger
    }

    // MARK: - Message Consumer

    // Notify objects contain the Tailnet information we've subscribed to via
    // the bus watcher.  The state is always included.  The netmap is included
    // if we add .netmap to the watchopts.
    func notify(_ notify: TailscaleKit.Ipn.Notify) {
        if let n = notify.NetMap {
            netmap = n
            peers = n.Peers
            netmapHandlers.values.forEach { $0(n) }
            peersHandlers.values.forEach { $0(n.Peers) }

        }

        if let s = notify.State {
            logger.log("State: \(s)")
            state = s
            stateHandlers.values.forEach { $0(s) }
        }
    }

    func error(_ error: any Error) {
        logger.log("\(error)")
    }

    // MARK: - Stream Publishers

    // Alternatively, use Combine publishers

    var netmap: Netmap.NetworkMap?
    var state: Ipn.State?
    var peers: [Tailcfg.Node]?

    private var netmapHandlers: [UUID: ((Netmap.NetworkMap?) -> Void)] = [:]
    private func removeNetmapHandler(_ uuid: UUID) {
        netmapHandlers[uuid] = nil
    }

    private var stateHandlers: [UUID: ((Ipn.State?) -> Void)] = [:]
    private func removeStateHandler(_ uuid: UUID) {
        stateHandlers[uuid] = nil
    }

    private var peersHandlers: [UUID: (([Tailcfg.Node]?) -> Void)] = [:]
    private func removePeersHandler(_ uuid: UUID) {
        peersHandlers[uuid] = nil
    }

    var netmapStream: AsyncStream<Netmap.NetworkMap?> {
        AsyncStream<Netmap.NetworkMap?> { continuation in
            let uuid = UUID()
            self.netmapHandlers[uuid] = { netmap in
                _ = continuation.yield(netmap)
            }
            continuation.onTermination = { _ in
                Task { await self.removeNetmapHandler(uuid) }
            }
        }
    }

    var peersStream: AsyncStream<[Tailcfg.Node]?> {
        AsyncStream { continuation in
            let uuid = UUID()

            self.peersHandlers[uuid] = { peers in
                _ = continuation.yield(peers)
            }
            continuation.onTermination = { _ in
                Task { await self.removePeersHandler(uuid) }
            }
        }
    }

    var stateStream: AsyncStream<Ipn.State?> {
        AsyncStream { continuation in
            let uuid = UUID()
            self.stateHandlers[uuid] = { state in
                _ = continuation.yield(state)
            }
            continuation.onTermination = { _ in
                Task { await self.removeStateHandler(uuid) }
            }
        }
    }
}
