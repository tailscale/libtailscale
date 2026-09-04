# Create a new Tailscale server object.
ts = Libtailscale.new()

# Set the Tailscale connection to be ephemeral.
:ok = Libtailscale.set_ephemeral(ts, 1)
:ok = Libtailscale.set_hostname(ts, "libtailscale-echo")

:ok = Libtailscale.up(ts)

{:ok, ips} = Libtailscale.getips(ts)
IO.puts("Server IPs: #{ips}")

# Create a listener socket using the NIF.
{:ok, listener_fd} = Libtailscale.listen(ts, "tcp", ":1999")

{:ok, listener_socket} = :socket.open(listener_fd)

# Customer "accept" functionality
{:ok, cmsg} = :socket.recvmsg(listener_socket)
<<socket_fd::integer-native-32>> = hd(cmsg.ctrl).data

{:ok, remoteaddr} = Libtailscale.getremoteaddr(ts, listener_fd, socket_fd)
IO.puts("Client IP: #{remoteaddr}")

{:ok, socket} = :socket.open(socket_fd)

# Now echo one message
{:ok, s} = :socket.recv(socket)

:ok = :socket.send(socket, s)

# And clean up
:socket.shutdown(socket, :read_write)

:socket.close(socket)

:socket.close(listener_socket)
