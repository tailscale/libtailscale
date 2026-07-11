// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import ArgumentParser
import TailscaleKit

extension TSDemo {
    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bring up a tsnet node and print its tailnet identity, peers, and backend status."
        )

        @OptionGroup var node: NodeOptions

        func run() async throws {
            try await withTailscaleNode(node) { ts in
                let api = LocalAPIClient(localNode: ts, logger: node.logger)
                let status = try await api.backendStatus()

                print("Backend state: \(status.BackendState)")

                let peers = (status.Peer?.values).map(Array.init)?.sorted { $0.HostName < $1.HostName } ?? []
                if peers.isEmpty {
                    print("No peers visible on this tailnet yet.")
                } else {
                    print("Peers:")
                    for peer in peers {
                        let ip = peer.TailscaleIPs?.first ?? "?"
                        let mark = peer.Online ? "online " : "offline"
                        print("  [\(mark)] \(peer.HostName)  \(ip)  \(peer.DNSName)")
                    }
                }
            }
        }
    }
}
