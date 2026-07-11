// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import ArgumentParser
import TailscaleKit

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension TSDemo {
    struct Send: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bring up a tsnet node and send a one-shot message to a peer running \"tsdemo listen\"."
        )

        @OptionGroup var node: NodeOptions

        @Argument(help: "Message to send.")
        var message: String

        @Option(help: "Destination on the tailnet, e.g. 100.x.y.z:8081 or a MagicDNS name:8081.")
        var to: String

        @Option(help: "IP protocol to dial with: tcp or udp.")
        var proto: String = "tcp"

        func run() async throws {
            guard let ipProto = NetProtocol(rawValue: proto) else {
                throw ValidationError("--proto must be tcp or udp")
            }

            try await withTailscaleNode(node) { ts in
                guard let handle = await ts.tailscale else {
                    throw ValidationError("Node has no handle")
                }

                let outgoing = try await OutgoingConnection(
                    tailscale: handle, to: to, proto: ipProto, logger: node.logger)
                try await outgoing.connect()
                try await outgoing.send(Data(message.utf8))

                // Give tsnet's virtual network stack a moment to actually flush the
                // write onto the wire (it may still be relaying through DERP) before
                // we tear the connection and node down.
                try await Task.sleep(for: .seconds(2))
                await outgoing.close()

                print("Sent \(message.utf8.count) bytes to \(to).")
            }
        }
    }
}
