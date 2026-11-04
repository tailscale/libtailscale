// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import ArgumentParser
import TailscaleKit

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A minimal proof that TailscaleKit works via plain SwiftPM (including on Linux)
@main
struct TSDemo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tsdemo",
        abstract: "Joins a tailnet and lists its devices, using TailscaleKit via SwiftPM.",
        discussion: """
            Needs a Tailscale auth key. Generate a reusable one at
            https://login.tailscale.com/admin/settings/keys and pass it via --auth-key or the
            TS_AUTHKEY environment variable.
            """
    )

    @Option(help: "Tailscale auth key. Defaults to the TS_AUTHKEY environment variable.")
    var authKey: String?

    @Option(help: "Control plane URL.")
    var controlURL: String = kDefaultControlURL

    @Flag(help: "Log tsnet's internal activity to stderr instead of discarding it.")
    var verbose: Bool = false

    func run() async throws {
        guard let authKey = authKey ?? ProcessInfo.processInfo.environment["TS_AUTHKEY"] else {
            throw ValidationError(
                "Provide --auth-key or set TS_AUTHKEY. Generate one at https://login.tailscale.com/admin/settings/keys"
            )
        }

        let hostname = "tsdemo-\(UUID().uuidString.prefix(8))"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(hostname).path
        let config = Configuration(
            hostName: hostname, 
            path: dir, 
            authKey: authKey, 
            controlURL: controlURL, 
            ephemeral: true
        )
        let logger: LogSink = verbose ? DefaultLogger() : BlackholeLogger()
        let node = try TailscaleNode(config: config, logger: logger)

        print("Bringing up \"\(hostname)\", waiting to associate with the tailnet...")
        try await node.up()

        do {
            let api = LocalAPIClient(localNode: node, logger: logger)
            let status = try await api.backendStatus()

            print("Backend state: \(status.BackendState)")

            let peers = (status.Peer?.values).map(Array.init)?.sorted { $0.HostName < $1.HostName } ?? []
            if peers.isEmpty {
                print("No other devices visible on this tailnet yet.")
            } else {
                print("Devices on this tailnet:")
                for peer in peers {
                    let ip = peer.TailscaleIPs?.first ?? "?"
                    let mark = peer.Online ? "online " : "offline"
                    print("  [\(mark)] \(peer.HostName)  \(ip)  \(peer.DNSName)")
                }
            }
            try await node.close()
        } catch {
            try? await node.close()
            throw error
        }
    }
}
