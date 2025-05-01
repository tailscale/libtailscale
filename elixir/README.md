# Libtailscale

Thin NIF-wrapper around
[libtailscale](https://github.com/tailscale/libtailscale/).

> #### Warning {: .warning}
>
> Should not be used directly. Use
> [`gen_tailscale`](https://hex.pm/packages/gen_tailscale) or
> [`TailscaleTransport`](https://hex.pm/packages/tailscale_transport) instead.


## Dependencies

Building this package requires access to a Go compiler as well as GCC.

## Usage

There's one working example in `examples/echo.exs`. To run, first run `mix
deps.get` and then `mix run examples/echo.exs`. You will need a
[Tailscale](https://tailscale.com/) account. The first time you run the example,
it will ask you to log in by following a link. Alternatively, here is the
simplest possible echo server:

```elixir
# Create a new Tailscale server object.
ts = Libtailscale.new()

# Set the Tailscale connection to be ephemeral.
:ok = Libtailscale.set_ephemeral(ts, 1)
:ok = Libtailscale.set_hostname(ts, "libtailscale-echo")

:ok = Libtailscale.up(ts)

# Create a listener socket using the NIF.
{:ok, listener_fd} = Libtailscale.listen(ts, "tcp", ":1999")

{:ok, listener_socket} = :socket.open(listener_fd)

# Customer "accept" functionality
{:ok, cmsg} = :socket.recvmsg(listener_socket)
<<socket_fd::integer-native-32>> = hd(cmsg.ctrl).data

{:ok, socket} = :socket.open(socket_fd)

# Now echo one message
{:ok, s} = :socket.recv(socket)
:ok = :socket.send(socket, s)

# And clean up
:socket.shutdown(socket, :read_write)
:socket.close(socket)
:socket.close(listener_socket)
```

After running the server (wait for the "state is Running" message), simply use
`telnet libtailscale-echo 1999` in another terminal to connect to it over the
tailnet. The server that's running is a simple echo server that will wait for a
single line of input, return it to the client and then close the connection.

## Warning

This Elixir library (which is also published to
[Hex](https://hex.pm/packages/libtailscale), the Elixir package manager), but it
should probably not be used directly. Instead, the
[`gen_tailscale`](https://hex.pm/packages/gen_tailscale) library should be used,
which wraps the libtailscale sockets in a `gen_tcp`-like interface. There's also
also [`tailscale_transport`](https://hex.pm/packages/tailscale_transport), which
allows users to expose their bandit/phoenix-based app directly to their tailnet
using `libtailscale` and the `gen_tailscale` wrapper.

Everything in this chain of packages should be considered proof of concept at
this point and should not be used for anything important. Especially the
`gen_tailscale` library has been constructed by crudely hacing the original
`gen_tcp` module to use `libtailscale` and could use a total rewrite at some
point. However, it works well enough that my example application
[`tschat`](https://github.com/Munksgaard/tschat) is able to accept connections
from different Tailscale users and show their username by retrieving data from
the Tailscale connection.
