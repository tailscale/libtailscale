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
        print(message)
    }
}

protocol Dialer: Actor {
    func phoneHome(_ setMessage: @escaping MessageSender) async
}

actor HelloManager: Dialer {
    var node: TailscaleNode?

    let logger = Logger()
    let config: Configuration

    init() {
        let temp = getDocumentDirectoryPath().absoluteString + "tailscale"
        self.config = Configuration(hostName: Settings.hostName,
                                    path: temp,
                                    authKey: Settings.authKey,
                                    controlURL: kDefaultControlURL,
                                    ephemeral: true)
    }

    func setupNode() throws -> TailscaleNode {
        guard self.node == nil else { return self.node! }
        self.node = try TailscaleNode(config: config, logger: logger)
        return self.node!
    }

    func phoneHome(_ setMessage: @escaping MessageSender) async {
        do {
            let node = try setupNode()
            await setMessage("Connecting to Tailnet...")

            try await node.up()

            await setMessage("Phoning " + Settings.tailnetServer + "...")

            // Create a URLSession that can access nodes on the tailnet.
            // .tailscaleSession(node) is the magic sauce.  This sends your URLRequest via
            // userspace Tailscale's SOCKS5 proxy.
            let sessionConfig = try await URLSessionConfiguration.tailscaleSession(node)
            let session = URLSession(configuration: sessionConfig)

            // Request a resource from the tailnet...
            let url = URL(string: Settings.tailnetServer)!
            let req = URLRequest(url: url)

            let (data, _) = try await session.data(for: req)
            await setMessage("\(Settings.tailnetServer) says:\n \(String(data: data, encoding: .utf8) ?? "(crickets!)")")
        } catch {
            await setMessage("Whoops!: \(error)")
        }
    }
}
