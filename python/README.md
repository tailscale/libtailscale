# tailscale

The tailscale Python package provides an embedded network interface that can be
used to listen for and dial connections to other [Tailscale](https://tailscale.com) nodes.

## Build and Install

Build Requirements:
  - Python 3.9 or greater
  - A recent Go compiler in $PATH
  - CMake (and a C compiler)
  - Git

Start by creating a virtualenv:

    $ python3 -m venv venv
    $ source venv/bin/activate

Install build dependencies, build the c-archive, and install the Python package in your virtualenv:

    $ make build

Run example echo server:

    $ python3 examples/echo.py

Build a distributable wheel:

    $ make wheel
    => tailscale-0.2.0-cp310-cp310-linux_x86_64.whl

## Usage

The node will need to be authorized in order for it to function. Set an auth key via
the `$TS_AUTHKEY` environment variable, with `TSNet.set_authkey`, or watch the log
stream and respond to the printed authorization URL.

`TSNet.up()` blocks until the node is usable, but stays responsive to interrupts
while blocked: a `KeyboardInterrupt` (Ctrl+C) cancels the underlying Go call and
re-raises, and `up(timeout_ms=...)` bounds the wait:

    t = TSNet()
    t.up(timeout_ms=30_000)  # raises TSNetException after 30 seconds

A `up()` that was interrupted or timed out may leave the server partially
started; create a new `TSNet` rather than retrying on the same one.

The package loads a Go runtime as a native extension, which normally takes over
some process-global signal handling. libtailscale isolates this while it loads,
and the package completes it at import time, so Python's own signal handling
(`signal.signal`, `KeyboardInterrupt`) keeps working unchanged. See
[SIGNALS.md](../SIGNALS.md) in the libtailscale repository for details.

## Contributing

Pull requests are welcome on GitHub at https://github.com/tailscale/libtailscale

Please file any issues about this code or the hosted service on
[the issue tracker](https://github.com/tailscale/tailscale/issues).
