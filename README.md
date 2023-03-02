# libtailscale

libtailscale is a C library that embeds Tailscale into a process.

Use this library to compile Tailscale into your program and get
an IP address on a tailnet, entirely from userspace.

## Building

With the latest version of Go, run:

```
go build -buildmode=c-archive
```

This will produce a `libtailscale.a` file. Link it into your binary,
and use the `tailscale.h` header to reference it.

It is also possible to build a shared library using

```
go build -buildmode=c-shared
```

## Bugs

Please file any issues about this code or the hosted service on
[the issue tracker](https://github.com/tailscale/tailscale/issues).

## License

BSD 3-Clause for this repository, see LICENSE.