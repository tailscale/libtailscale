# TailscaleKit

The TailscaleKit Swift package provides an embedded network interface that can be
used to listen for and dial connections to other [Tailscale](https://tailscale.com) nodes in addition 
to an extension to URLSession which allows you to make URL requests to nodes on you Tailnet directly.

The interfaces are similar in design to NWConnection, but are Swift 6 compliant and
designed to be used in modern async/await style code.  

## Build and Install

Build Requirements:
  - XCode 16.1 or newer

Building Tailscale.framework:

From /swift 
```
$ make build
```

Will build TailscaleKit.framework into /swift/build/Build/Products.

Separate frameworks will be built for macOS and iOS.  All dependencies (libtailscale.a)
are built automatically.  Swift 6 is supported.

Alternatively, you may build from xCode using the Tailscale scheme.

Non-apple builds are not supported (yet).  We do use URLSession and Combine though
it is possible to purge both.

## Tests

From /swift
```
$ make test
```


## Usage

Nodes need to be authorized in order to function. Set an auth key via
the config.authKey parameter, or watch the log stream and respond to the printed
authorization URL.  

Here's a working example using an auth key:

```Swift

// Configures a Tailscale node and starts it up.  The node here (and the key we would use to
// authenticate it) are marked as 'ephemeral' - meaning that the node will be disposed of as
// soon as it goes offline.
func start() -> TailscaleNode {
    let dataDir = getDocumentDirectoryPath().absoluteString + "tailscale"
    let authKey = "tsnet-auth-put-your-auth-key-key-here"
    let config = Configuration(hostName: "TSNet-Test",
                               path: dataDir,
                               authKey: authKey,
                               controlURL: Configuration.defaultControlURL,
                               ephemeral: true)

    // The logger is configurable.  The default will just print.
    let node = try TailscaleNode(config: config, logger: DefaultLogger())
    
    // Bring the node up 
    try await node.up()
    return node
}

// Do a URL request via the loopback proxy
// Where url is a node on your tailnet such as https://server.fiesty-pangolin.ts.net/thing
func fetchURL(_ url: URL, tailscale: TailscaleNode) async throws -> Data {
    // You can cache this.  It will not change once the node is up.
    let sessionConfig = try await URLSessionConfiguration.tailscaleSession(tailscale)
    let session = URLSession(configuration: sessionConfig)
    
    // Make the request
    let req = URLRequest(url: url)
    let (data, _) = try await session.data(for: req)
    return data
}
```

See the [TailscaleKitTests](./Tests/TailscaleKitTests/TailscaleKitTests.swift) for more examples.

## Contributing

Pull requests are welcome on GitHub at https://github.com/tailscale/libtailscale

Please file any issues about this code or the hosted service on
[the issue tracker](https://github.com/tailscale/tailscale/issues).
