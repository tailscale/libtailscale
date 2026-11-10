// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import TailscaleKit

actor HelloModel: MessageConsumer {
    private let logger: LogSink

    init(logger: LogSink) {
        self.logger = logger
    }

    // MARK: - Message Consumer

    private var onNotify: (@Sendable () async -> Void)?
    private var onBusError: (@Sendable () async -> Void)?

    // The long poll behind the bus can drop at any time.  HelloManager supplies
    // handlers so it can reconnect on failure and reset its backoff once
    // messages are flowing again.
    func setBusHandlers(onNotify: @escaping @Sendable () async -> Void,
                        onError: @escaping @Sendable () async -> Void) {
        self.onNotify = onNotify
        self.onBusError = onError
    }

    // The bus delivers an InitialStatus snapshot to seed from, then only what
    // changed.  Deltas must be applied in arrival order, which MessageProcessor
    // guarantees.
    func notify(_ notify: TailscaleKit.Ipn.Notify) async {
        if let url = notify.BrowseToURL {
            logger.log("Auth required, visit: \(url)")
            browseToURL = url
        }

        if let s = notify.State {
            logger.log("State: \(s)")
            state = s
            if s == .NoState || s == .Stopped {
                selfNode = nil
                peersByID = [:]
                tailnetStatus = nil
            }
            stateHandlers.values.forEach { $0(s) }
        }

        if let status = notify.InitialStatus {
            seed(from: status)
        }

        if let selfChange = notify.SelfChange {
            selfNode = selfChange
        }

        applyPeerUpdates(notify)

        await onNotify?()
    }

    func error(_ error: any Error) {
        logger.log("\(error)")
        Task { await onBusError?() }
    }

    // MARK: - Tailnet State

    private(set) var state: Ipn.State?
    private(set) var tailnetStatus: IpnState.TailnetStatus?
    private(set) var selfNode: Tailcfg.Node? {
        didSet { selfNodeHandlers.values.forEach { $0(selfNode) } }
    }

    /// Set when the node needs interactive web auth.
    private(set) var browseToURL: String? {
        didSet { browseToURLHandlers.values.forEach { $0(browseToURL) } }
    }
    private(set) var userProfiles: [Tailcfg.UserID: Tailcfg.UserProfile] = [:]
    private(set) var peersByID: [Tailcfg.NodeID: Tailcfg.Node] = [:] {
        didSet { peersHandlers.values.forEach { $0(peers) } }
    }

    var peers: [Tailcfg.Node] {
        peersByID.values.sorted { $0.ComputedName < $1.ComputedName }
    }

    private func seed(from status: IpnState.Status) {
        tailnetStatus = status.CurrentTailnet
        selfNode = status.SelfStatus.map { Tailcfg.Node(from: $0, status: status) }

        var nextPeers: [Tailcfg.NodeID: Tailcfg.Node] = [:]
        for peer in (status.Peer ?? [:]).values {
            let node = Tailcfg.Node(from: peer, status: status)
            nextPeers[node.ID] = node
        }
        peersByID = nextPeers

        var profiles: [Tailcfg.UserID: Tailcfg.UserProfile] = [:]
        for (key, profile) in status.User ?? [:] {
            if let id = Tailcfg.UserID(key) {
                profiles[id] = profile
            }
        }
        userProfiles = profiles
    }

    private func applyPeerUpdates(_ notify: Ipn.Notify) {
        if let profiles = notify.UserProfiles, !profiles.isEmpty {
            for (key, profile) in profiles {
                if let id = Tailcfg.UserID(key) {
                    userProfiles[id] = profile
                }
            }
        }

        var next = peersByID
        var changed = false

        if let peersChanged = notify.PeersChanged, !peersChanged.isEmpty {
            for peer in peersChanged {
                next[peer.ID] = peer
            }
            changed = true
        }

        if let peersRemoved = notify.PeersRemoved, !peersRemoved.isEmpty {
            for id in peersRemoved {
                next.removeValue(forKey: id)
            }
            changed = true
        }

        if let patches = notify.PeerChangedPatch, !patches.isEmpty {
            for patch in patches {
                guard var peer = next[patch.NodeID] else {
                    logger.log("PeerChange for unknown NodeID \(patch.NodeID); ignoring")
                    continue
                }
                patch.applyTo(node: &peer)
                next[patch.NodeID] = peer
                changed = true
            }
        }

        if changed {
            peersByID = next
        }
    }

    // MARK: - Stream Publishers

    // Alternatively, use Combine publishers

    private var stateHandlers: [UUID: ((Ipn.State?) -> Void)] = [:]
    private func removeStateHandler(_ uuid: UUID) {
        stateHandlers[uuid] = nil
    }

    private var peersHandlers: [UUID: (([Tailcfg.Node]) -> Void)] = [:]
    private func removePeersHandler(_ uuid: UUID) {
        peersHandlers[uuid] = nil
    }

    private var selfNodeHandlers: [UUID: ((Tailcfg.Node?) -> Void)] = [:]
    private func removeSelfNodeHandler(_ uuid: UUID) {
        selfNodeHandlers[uuid] = nil
    }

    private var browseToURLHandlers: [UUID: ((String?) -> Void)] = [:]
    private func removeBrowseToURLHandler(_ uuid: UUID) {
        browseToURLHandlers[uuid] = nil
    }

    var browseToURLStream: AsyncStream<String?> {
        AsyncStream { continuation in
            let uuid = UUID()
            self.browseToURLHandlers[uuid] = { url in
                _ = continuation.yield(url)
            }
            continuation.onTermination = { _ in
                Task { await self.removeBrowseToURLHandler(uuid) }
            }
        }
    }

    var peersStream: AsyncStream<[Tailcfg.Node]> {
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

    var selfNodeStream: AsyncStream<Tailcfg.Node?> {
        AsyncStream { continuation in
            let uuid = UUID()
            self.selfNodeHandlers[uuid] = { node in
                _ = continuation.yield(node)
            }
            continuation.onTermination = { _ in
                Task { await self.removeSelfNodeHandler(uuid) }
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
