// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause


import SwiftUI
@preconcurrency import Combine
import TailscaleKit

@Observable
@MainActor
final class HelloViewModel: Sendable    {
    var message: String = "Ready to phone home!"
    var peerCountMessage = "Waiting for peers...."
    var stateMessage = "Waiting for state...."
    var selfNodeMessage = "Waiting for this node...."
    var authURL: URL?

    var modelObservers = [Task<Void, Never>]()

    init(model: HelloModel) {
        bindToModel(model)
    }

    func handleStateChange(_ state: Ipn.State?) {
        guard let state else {
            self.stateMessage = "Waiting for state...."
            return
        }
        self.stateMessage = "IPNState: \(state)"
    }

    func handlePeersChange(_ peers: [Tailcfg.Node]) {
        if peers.count > 0 {
            self.peerCountMessage = "Found \(peers.count) peers"
        } else {
            self.peerCountMessage = "No peers found"
        }
    }

    func handleSelfNodeChange(_ node: Tailcfg.Node?) {
        guard let node else {
            self.selfNodeMessage = "Waiting for this node...."
            return
        }
        self.selfNodeMessage = "This node: \(node.ComputedName)"
    }

    func handleBrowseToURLChange(_ url: String?) {
        self.authURL = url.flatMap { URL(string: $0) }
    }

    func bindToModel(_ model: HelloModel) {
        modelObservers.forEach { $0.cancel() }
        modelObservers.removeAll()

        Task {
            await handleStateChange(model.state)
            await handlePeersChange(model.peers)
            await handleSelfNodeChange(model.selfNode)
            await handleBrowseToURLChange(model.browseToURL)
        }

        modelObservers.append( Task { [weak self] in
            for await url in await model.browseToURLStream {
                if Task.isCancelled { return }
                guard let self = self else { return }
                await MainActor.run { handleBrowseToURLChange(url) }
            }
        })

        modelObservers.append( Task { [weak self] in
            for await peers in await model.peersStream {
                if Task.isCancelled { return }
                guard let self = self else { return }
                await MainActor.run { handlePeersChange(peers) }
            }
        })

        modelObservers.append( Task { [weak self] in
            for await node in await model.selfNodeStream {
                if Task.isCancelled { return }
                guard let self = self else { return }
                await MainActor.run { handleSelfNodeChange(node) }
            }
        })

        modelObservers.append( Task { [weak self] in
            for await state in await model.stateStream {
                if Task.isCancelled { return }
                guard let self = self else { return }
                await MainActor.run { handleStateChange(state) }
            }
        })
    }

    func setMessage(_ message: String) {
        self.message =  message
    }

    func runRequest(_ dialer: Dialer) {
        Task.detached {
            let model = self
            await dialer.phoneHome { msg in
                await MainActor.run {
                    model.setMessage(msg)
                }
            }
        }
    }
}
