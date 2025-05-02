// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#if os(iOS)
import UIKit
#endif

public extension URLSessionConfiguration {

    /// Adds the a connectionProxyDictionary to a URLSessionConfiguration to
    /// proxy all requests through the given TailscaleNode.
    ///
    /// This can also be use to make requests to LocalAPI.  See LocalAPIClient
    @discardableResult
    func proxyVia(_ node: TailscaleNode) async throws -> TailscaleNode.LoopbackConfig {
        let proxyConfig = try await node.loopback()

        guard let ip = proxyConfig.ip, let port = proxyConfig.port else {
            throw TailscaleError.invalidProxyAddress
        }


        let config: [CFString: Any] = [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFProxyUsernameKey: "tsnet",
            kCFProxyPasswordKey: proxyConfig.proxyCredential,
            kCFProxyHostNameKey: ip,
            kCFProxyPortNumberKey: port
        ]

        self.connectionProxyDictionary = config
        
        return proxyConfig
    }

    static func tailscaleSession(_ node: TailscaleNode) async throws -> (URLSessionConfiguration, TailscaleNode.LoopbackConfig) {
        let session  = URLSessionConfiguration.default
        let config = try await session.proxyVia(node)
        return (session, config)
    }
}
