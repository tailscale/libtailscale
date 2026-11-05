# libtailscale

[![Upstream Tailscale compatibility](https://github.com/tailscale/libtailscale/actions/workflows/upstream-compatibility.yml/badge.svg?branch=main)](https://github.com/tailscale/libtailscale/actions/workflows/upstream-compatibility.yml)

libtailscale is a C library that embeds Tailscale into a process.

Use this library to compile Tailscale into your program and get
an IP address on a tailnet, entirely from userspace.

## Building

With the latest version of Go, run:

```
go build -buildmode=c-archive
```

or 

```
make archive
```

This will produce a `libtailscale.a` file. Link it into your binary,
and use the `tailscale.h` header to reference it.

It is also possible to build a shared library using

```
go build -buildmode=c-shared
```

or

```
make shared
```

## Upstream compatibility checks

The **Upstream Tailscale compatibility** GitHub Action runs weekly or manually
to test the library, bindings, and samples against the latest stable Tailscale
release. Matching versions skip the builds and report success. See the workflow
run for results and logs.

## Bugs

Please file any issues about this code or the hosted service on
[the issue tracker](https://github.com/tailscale/tailscale/issues).

## License

BSD 3-Clause for this repository, see LICENSE.