// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

import ArgumentParser
import TailscaleKit

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Darwin)
@preconcurrency import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#endif

@main
struct TSDemo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tsdemo",
        abstract: "A minimal example of joining a tailnet from a Swift command-line tool using TailscaleKit.",
        discussion: """
            Each invocation brings up its own in-process tsnet node, so "tsdemo status" and
            "tsdemo listen" are different nodes on your tailnet even if you run them back to back.

            All subcommands need a Tailscale auth key. Generate a reusable one at
            https://login.tailscale.com/admin/settings/keys and pass it via --auth-key or the
            TS_AUTHKEY environment variable.
            """,
        subcommands: [Status.self, Listen.self, Send.self]
    )
}

/// Options shared by every subcommand for bringing up a tsnet node.
struct NodeOptions: ParsableArguments {
    @Option(help: "Hostname to advertise on the tailnet. Defaults to a random tsdemo-<id> name.")
    var hostname: String = "tsdemo-\(UUID().uuidString.prefix(8))"

    @Option(help: "Tailscale auth key. Defaults to the TS_AUTHKEY environment variable.")
    var authKey: String?

    @Option(help: "Control plane URL.")
    var controlURL: String = kDefaultControlURL

    @Option(
        help:
            "Directory used to persist this node's tsnet state. Defaults to a fresh temporary directory; pass a stable path to reuse the same node identity across runs."
    )
    var stateDir: String?

    @Flag(inversion: .prefixedNo, help: "Register the node as ephemeral, so it disappears from the tailnet admin console when this process exits.")
    var ephemeral: Bool = true

    @Flag(help: "Log tsnet's internal activity to stderr instead of discarding it.")
    var verbose: Bool = false

    func makeConfiguration() throws -> Configuration {
        guard let authKey = authKey ?? ProcessInfo.processInfo.environment["TS_AUTHKEY"] else {
            throw ValidationError(
                "Provide --auth-key or set TS_AUTHKEY. Generate one at https://login.tailscale.com/admin/settings/keys"
            )
        }

        let dir = stateDir ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("tsdemo-\(hostname)").path

        return Configuration(
            hostName: hostname,
            path: dir,
            authKey: authKey,
            controlURL: controlURL,
            ephemeral: ephemeral)
    }

    var logger: LogSink {
        verbose ? DefaultLogger() : BlackholeLogger()
    }
}

/// Brings a node up, waits for it to associate an address, and hands it to `body`.
/// The node is always torn down afterwards, even if `body` throws.
func withTailscaleNode<T>(
    _ options: NodeOptions,
    _ body: (TailscaleNode) async throws -> T
) async throws -> T {
    setvbuf(stdout, nil, _IOLBF, 0)

    let config = try options.makeConfiguration()
    let node = try TailscaleNode(config: config, logger: options.logger)

    print("Bringing up \"\(config.hostName)\", waiting to associate with the tailnet...")
    try await node.up()

    let addrs = try await node.addrs()
    let addrDescription = [addrs.ip4, addrs.ip6].compactMap { $0 }.joined(separator: ", ")
    print("\"\(config.hostName)\" is up at \(addrDescription)")

    do {
        let result = try await body(node)
        try await node.close()
        return result
    } catch {
        try? await node.close()
        throw error
    }
}
