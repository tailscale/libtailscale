// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause


import SwiftUI
@preconcurrency import Combine
import TailscaleKit

@Observable
class HelloViewModel: @unchecked Sendable    {
    var message: String = "Ready to phone home!"
    var peerCountMessage = "Waiting for peers...."
    var stateMessage = "Waiting for state...."

    var modelObservers = [Task<Void, Never>]()

    @MainActor
    init(model: HelloModel) {
        bindToModel(model)
    }

    deinit {
        modelObservers.forEach { $0.cancel() }
    }

    @MainActor
    func handleStateChange(_ state: Ipn.State?) {
        guard let state else {
            self.stateMessage = "Waiting for state...."
            return
        }
        self.stateMessage = "IPNState: \(state)"
    }

    @MainActor
    func handlePeersChange(_ peers: [Tailcfg.Node]?) {
        guard let peers else {
            self.peerCountMessage = "Waiting for peers..."
            return
        }
        
        if peers.count > 0 {
            self.peerCountMessage = "Found \(peers.count) peers"
        } else {
            self.peerCountMessage = "No peers found"
        }
    }

    @MainActor
    func bindToModel(_ model: HelloModel) {
        modelObservers.forEach { $0.cancel() }
        modelObservers.removeAll()

        Task {
            await handleStateChange(model.state)
            await handlePeersChange(model.peers)
        }

        modelObservers.append( Task { [weak self] in
            for await peers in await model.peersStream {
                if Task.isCancelled { return }
                guard let self = self else { return }
                await MainActor.run { handlePeersChange(peers) }
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

    @MainActor
    func setMessage(_ message: String) {
        self.message =  message
    }

    func runRequest(_ dialer: Dialer) {
        Task {
            let model = self
            await dialer.phoneHome { msg in
                await MainActor.run {
                    model.setMessage(msg)
                }
            }
        }
    }
}
