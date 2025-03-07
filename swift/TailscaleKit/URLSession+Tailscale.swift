// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#if os(iOS)
import UIKit
#endif

public extension URLSessionConfiguration {

    // (barnstar) TODO: kCFNetworkProxiesSOCKS* is not available on iOS
    //                   is there another way to make this work on non desktops?

    #if os(macOS)
    /// Adds the a connectionProxyDictionary to a URLSessionConfiguration to
    /// proxy all requests through the given TailscaleNode.
    ///
    /// This can also be use to make requests to LocalAPI
    func proxyVia(_ node: TailscaleNode) async throws  {
        let proxyConfig = try await node.loopback()

        // The address is always v4 and it's always <ip>:<port>
        let parts = proxyConfig.address.split(separator: ":")
        let addr = parts.first
        let port = parts.last
        guard parts.count == 2, let addr, let port else {
            throw TailscaleError.invalidProxyAddress
        }

        self.connectionProxyDictionary = [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFProxyUsernameKey: "tsnet",
            kCFProxyPasswordKey: proxyConfig.proxyCredential,
            kCFNetworkProxiesSOCKSEnable: true,
            kCFNetworkProxiesSOCKSProxy: addr,
            kCFNetworkProxiesSOCKSPort: port
        ]
    }

    public static func tailscaleSession(_ node: TailscaleNode) async throws -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        try await config.proxyVia(node)
        return config
    }
    #endif

}
