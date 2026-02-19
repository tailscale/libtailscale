// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#if os(iOS)
import UIKit
#endif

import Network

public extension URLSessionConfiguration {

    /// Adds the a ProxyConfiguration to a URLSessionConfiguration to
    /// proxy all requests through the given TailscaleNode.
    ///
    /// This can also be use to make requests to LocalAPI.  See LocalAPIClient
    @discardableResult
    func proxyVia(_ node: TailscaleNode) async throws -> TailscaleNode.LoopbackConfig {
        let proxyConfig = try await node.loopback()

        guard let ip = proxyConfig.ip, let port = proxyConfig.port else {
            throw TailscaleError.invalidProxyAddress
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip),
                                           port: NWEndpoint.Port(rawValue: UInt16(port))!)

        let sessionProxyConfig = ProxyConfiguration(socksv5Proxy: endpoint)
        sessionProxyConfig.applyCredential(username: "tsnet", password:
                                            proxyConfig.proxyCredential)

        self.proxyConfigurations = [sessionProxyConfig]

        return proxyConfig
    }

    static func tailscaleSession(_ node: TailscaleNode) async throws -> (URLSessionConfiguration, TailscaleNode.LoopbackConfig) {
        let session  = URLSessionConfiguration.default
        let config = try await session.proxyVia(node)
        return (session, config)
    }
}
