# TailscaleKitCLI

A minimal SwiftPM executable, built with
[swift-argument-parser](https://github.com/apple/swift-argument-parser), that joins your
tailnet from a Swift command-line tool using TailscaleKit. Needs no Xcode project.

Unlike `TailscaleKitHello` (an Xcode app that links a prebuilt `.xcframework`), this
package depends directly on `swift/Package.swift`, exercising the same SwiftPM path
covered by `swift test`/`make test-spm`.

**Linux and macOS** (arm64/x86_64). `swift/script/build-artifactbundle.sh` builds a Linux
variant of `CTailscale` from any host via cross-compilation, plus a native macOS variant
when run *on* macOS (Go/cgo needs a real Mach-O toolchain, so that leg can't be
cross-built from Linux). iOS has no SPM path; for that, use `TailscaleKitHello` (Xcode +
the `.xcframework` built by `swift/Makefile`'s `ios-fat` target).

On a fresh macOS checkout, make sure `objcopy`/`llvm-objcopy` is reachable (`xcrun -f
llvm-objcopy` if you have a swift.org toolchain installed, otherwise `brew install llvm`
or `brew install binutils`) - `fix-tstestcontrol-archive.sh` needs it, and macOS doesn't
ship one by default.

## Setup

From `/swift`, build the `libtailscale.a` artifact bundle this package links against
(this is also done automatically by `make test-spm`):

```
$ ./script/build-artifactbundle.sh
```

Generate a reusable auth key at
https://login.tailscale.com/admin/settings/keys and export it:

```
$ export TS_AUTHKEY=tskey-auth-...
```

## Usage

Each subcommand brings up its own in-process tsnet node (its own device on your tailnet),
so run `status`/`listen`/`send` as separate invocations, or from separate machines/devices
on the same tailnet entirely.

```
$ swift run tsdemo status
```
Brings up a node and prints the tailnet's backend state and peer list.

```
$ swift run tsdemo listen --port 8081
```
Brings up a node, listens on port 8081, and prints every message it receives from peers.

```
$ swift run tsdemo send --to 100.x.y.z:8081 "hello"
```
Brings up a separate node and sends a one-shot message to whatever is listening at
`--to` (an IP or MagicDNS name from `tsdemo status`/`tsdemo listen`'s output).

Pass `--hostname`/`--state-dir` to give a node a stable identity across runs (otherwise
each run gets a random hostname and a throwaway state directory, and defaults to
`--ephemeral`, so it disappears from the admin console when the process exits).

## What this is showing off

- `TailscaleNode` — bringing up an in-process node against the control plane, and reading
  back its tailnet addresses.
- `Listener`/`IncomingConnection` and `OutgoingConnection` — the raw one-directional
  send/receive primitives TailscaleKit exposes for talking directly to other devices on
  the tailnet, with no port forwarding, VPN config, or public exposure required.
- `LocalAPIClient` — querying the node's own local API for backend/peer status, the same
  API `tailscale status` itself uses.

`tsdemo send` sleeps briefly after writing before it closes the connection and tears the
node down — tsnet's virtual network stack may still be relaying the write (e.g. through
DERP) when `send()` returns, and a `--ephemeral` node exiting immediately can beat that
flush.
