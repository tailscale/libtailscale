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
```bash
$ make macos
$ make ios
$ make ios-sim
$ make ios-fat
```

These recipes build different variants of TailscaleKit.framework into /swift/build/Build/Products.

Separate frameworks will be built for macOS and iOS and the iOS Simulator.  All dependencies (libtailscale*.a)
are built automatically.  Swift 6 is supported.

The ios and ios-sim frameworks are purposefully separated.  The former is free of any simulator segments
and is suitable for app-store submissions.   The latter is suitable for embedding when you 
wish to run on a simulator in dev though 'make ios-fat' will produce an xcframework bundle including
both simulator and device frameworks for development.

The frameworks are not signed and must be signed when they are embedded.

Alternatively, you may build from xCode using the Tailscale scheme but the 
libraries must be built first (since xCode will complain about paths and
permissions)

To build only the static libraries, from / 
```bash
$ make c-archive
$ make c-archive-ios 
$ make c-archive-ios-sim
```

If you're writing pure C, or C++, link these and use the generated tailscale.h header.  
make c-archive builds for the local machine architecture/platform (arm64 macOS from a mac)

Non-apple swift builds are not supported (yet) but should be possible with a little tweaking.

## Tests

From /swift
```bash
$ make test
```


## Usage

Nodes need to be authorized in order to function. Set an auth key via
the config.authKey parameter, or watch the ipn bus (see the example) for
the browseToURL field for interactive web-based auth.

Here's a working example using an auth key:

```Swift
func start() -> TailscaleNode {
    let dataDir = getDocumentDirectoryPath().absoluteString + "tailscale"
    let authKey = "tsnet-auth-put-your-auth-key-key-here"
    let config = Configuration(hostName: "TSNet-Test",
                               path: dataDir,
                               authKey: authKey,
                               controlURL: Configuration.defaultControlURL,
                               ephemeral: false)

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

The "node" created here should show up in the Tailscale admin panel as "TSNet-Test"

### LocalAPI

TailscaleKit.framework also includes a functional (though somewhat incomplete) implementation of 
LocalAPI which can be used to track the state of the embedded tailscale instance in much greater
detail.

### Examples

See the TailscaleKitHello example for a relatively complete implementation demonstrating proxied
HTTP and usage of LocalAPI to track the tailnet state.

## Contributing

Pull requests are welcome on GitHub at https://github.com/tailscale/libtailscale

Please file any issues about this code or the hosted service on
[the issue tracker](https://github.com/tailscale/tailscale/issues).
