# libtailscale

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

## Signal handling

Embedding a Go runtime into a host process changes process-global signal
state, and libtailscale takes care to keep the host runtime's signal
handling (traps, `Ctrl+C`, stack-overflow guards) working unchanged, plus
provides cancellable blocking calls so hosts like Ruby or Python can
interrupt `up`/`dial`. See [SIGNALS.md](SIGNALS.md) for the details, the
trade-offs, and what C embedders should do.

## Bugs

Please file any issues about this code or the hosted service on
[the issue tracker](https://github.com/tailscale/tailscale/issues).

## License

BSD 3-Clause for this repository, see LICENSE.