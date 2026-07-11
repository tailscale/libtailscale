# TailscaleKitCLI

A minimal SwiftPM executable, built with [swift-argument-parser](https://github.com/apple/swift-argument-parser), that joins your tailnet and lists its devices using TailscaleKit. Needs no Xcode project — it exists purely as a proof that TailscaleKit works from plain SwiftPM, including on Linux.

Unlike `TailscaleKitHello` (an Xcode app that links a prebuilt `.xcframework`), this package depends directly on `swift/Package.swift`, exercising the same SwiftPM path covered by `swift test`/`make test-spm`.

## Setup

From this directory, build the artifact bundle this package needs. Run this once:

```sh
$ make spm-setup
```

Generate and export an auth key at https://login.tailscale.com/admin/settings/keys.

```sh
$ export TS_AUTHKEY=tskey-auth-...
```

## Usage

```sh
$ swift run tsdemo
```

Example output:

```
make spm-setup
make[1]: Entering directory '/workspace/swift'

::: Building SwiftPM artifact bundle for TailscaleKit :::
./script/build-artifactbundle.sh
::: Building libtailscale.a for x86_64-unknown-linux-gnu (GOOS=linux GOARCH=amd64, CC=x86_64-linux-gnu-gcc) :::
::: Building libtailscale.a for aarch64-unknown-linux-gnu (GOOS=linux GOARCH=arm64, CC=aarch64-linux-gnu-gcc) :::
::: Skipping macOS variants (not running on a Darwin host) :::
wrote /workspace/swift/build/TailscaleKit.artifactbundle
make[1]: Leaving directory '/workspace/swift'
root@82cf0493d6f1:/workspace/swift/Examples/TailscaleKitCLI# export TS_AUTHKEY=tskey-auth-...
root@82cf0493d6f1:/workspace/swift/Examples/TailscaleKitCLI# swift run tsdemo
[1/1] Planning build
Building for debugging...
clang: warning: argument unused during compilation: '-F/workspace/swift/Examples/TailscaleKitCLI/.build/aarch64-unknown-linux-gnu/debug' [-Wunused-command-line-argument]
[40/40] Linking tsdemo
Build of product 'tsdemo' complete! (2.97s)
2026/07/11 21:14:20 tsnet running state path /tmp/tsdemo-FF27454D/tailscaled.state
2026/07/11 21:14:20 tsnet starting with hostname "tsdemo-FF27454D", varRoot "/tmp/tsdemo-FF27454D"
2026/07/11 21:14:20 LocalBackend state is NeedsLogin; running StartLoginInteractive...
Bringing up "tsdemo-FF27454D", waiting to associate with the tailnet...
2026/07/11 21:14:22 localapi tcp serve error: use of closed network connection
2026/07/11 21:14:22 socks5: SOCKS5 server exited: use of closed network connection
Backend state: Running
Devices on this tailnet:
  [offline] xxx  100.xx.xx.xx  xxx.my-tailnet-name.ts.net.
  [online ] xxx  100.xx.xx.xx  xxx.my-tailnet-name.ts.net.
  [online ] xxx  100.xx.xx.xx  xxx.my-tailnet-name.ts.net.
  [offline] xxx  100.xx.xx.xx  xxx.my-tailnet-name.ts.net.
  [online ] xxx  100.xx.xx.xx  xxx.my-tailnet-name.ts.net.
  [online ] xxx  100.xx.xx.xx  xxx.my-tailnet-name.ts.net.
  [offline] xxx  100.xx.xx.xx  xxx.my-tailnet-name.ts.net.
```

Brings up a throwaway, ephemeral in-process tsnet node, then prints the tailnet's backend state and every other device currently visible on it. Needs a real Tailscale auth key and network access.

## What this is showing off

- `TailscaleNode` — bringing up an in-process node against the control plane.
- `LocalAPIClient` — querying the node's own local API for backend/peer status, the same API `tailscale status` itself uses.

For the raw send/receive primitives (`Listener`/`IncomingConnection`/`OutgoingConnection`), see `swift/TailscaleKitXCTests/TailscaleKitTests.swift`.
