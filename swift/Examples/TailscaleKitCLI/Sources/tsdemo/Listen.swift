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
    struct Listen: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bring up a tsnet node and print every message received from peers on the tailnet."
        )

        @OptionGroup var node: NodeOptions

        @Option(help: "Port to listen on.")
        var port: Int = 8081

        @Option(help: "IP protocol to listen with: tcp or udp.")
        var proto: String = "tcp"

        func run() async throws {
            guard let ipProto = NetProtocol(rawValue: proto) else {
                throw ValidationError("--proto must be tcp or udp")
            }

            try await withTailscaleNode(node) { ts in
                guard let handle = await ts.tailscale else {
                    throw ValidationError("Node has no handle")
                }

                let listener = try await Listener(
                    tailscale: handle, proto: ipProto, address: ":\(port)", logger: node.logger)

                print(
                    "Listening on \(proto)/\(port). From another node, run: tsdemo send --to <this-node-ip>:\(port) \"hello\". Ctrl-C to stop."
                )

                while true {
                    let inbound = try await listener.accept(timeout: 300)
                    let data = try await inbound.receiveMessage(timeout: 5000)
                    let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
                    let remote = await inbound.remoteAddress ?? "unknown"
                    print("[\(remote)] \(text)")
                }
            }
        }
    }
}
