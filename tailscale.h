// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

//
// Tailscale C library.
//
// Use this library to compile Tailscale into your program and get
// an entirely userspace IP address on a tailnet.
//
// From here you can listen for other programs on your tailnet dialing
// you, or connect directly to other services.
//


#include <stddef.h>

#ifndef TAILSCALE_H
#define TAILSCALE_H

#ifdef __cplusplus
extern "C" {
#endif


// tailscale is a handle onto a Tailscale server.
typedef int tailscale;

// tailscale_new creates a tailscale server object.
//
// No network connection is initialized until tailscale_start is called.
extern tailscale tailscale_new();

// tailscale_start connects the server to the tailnet.
//
// Calling this function is optional as it will be called by the first use
// of tailscale_listen or tailscale_dial on a server.
//
// See also: tailscale_up.
//
// Returns zero on success or -1 on error, call tailscale_errmsg for details.
extern int tailscale_start(tailscale sd);

// tailscale_up connects the server to the tailnet and waits for it to be usable.
//
// To cancel an in-progress call to tailscale_up, use tailscale_close.
//
// Returns zero on success or -1 on error, call tailscale_errmsg for details.
extern int tailscale_up(tailscale sd);

// tailscale_close shuts down the server.
//
// Returns:
// 	0     - success
// 	EBADF - sd is not a valid tailscale
// 	-1    - other error, details printed to the tsnet logger
extern int tailscale_close(tailscale sd);

// The following set tailscale configuration options.
//
// Configure these options before any explicit or implicit call to tailscale_start.
//
// For details of each value see the godoc for the fields of tsnet.Server.
//
// Returns zero on success or -1 on error, call tailscale_errmsg for details.
extern int tailscale_set_dir(tailscale sd, const char* dir);
extern int tailscale_set_hostname(tailscale sd, const char* hostname);
extern int tailscale_set_authkey(tailscale sd, const char* authkey);
extern int tailscale_set_control_url(tailscale sd, const char* control_url);
extern int tailscale_set_ephemeral(tailscale sd, int ephemeral);

// tailscale_set_logfd instructs the tailscale instance to write logs to fd.
//
// A fd value of -1 means discard all logging.
//
// Returns zero on success or -1 on error, call tailscale_errmsg for details.
extern int tailscale_set_logfd(tailscale sd, int fd);

// A tailscale_conn is a connection to an address on the tailnet.
//
// It is a pipe(2) on which you can use read(2), write(2), and close(2).
// For extra control over the connection, see the tailscale_conn_* functions.
typedef int tailscale_conn;

// Returns the IP addresses of the Tailscale server as a comma separated list.
//
// The provided buffer must be of sufficient size to hold the concatenated
// IPs as strings.  This is typically `<ipv4>,<ipv6>` but maybe empty, or
// contain any number of ips. The caller is responsible for parsing
// the output.  You may assume the output is a list of well-formed IPs.
//
// Returns:
// 	0      - Success
// 	EBADF  - sd is not a valid tailscale, or l or conn are not valid listeners or connections
// 	ERANGE - insufficient storage for buf
extern int tailscale_getips(tailscale sd, char* buf, size_t buflen);

// tailscale_dial connects to the address on the tailnet.
//
// The newly allocated connection is written to conn_out.
//
// network is a NUL-terminated string of the form "tcp", "udp", etc.
// addr is a NUL-terminated string of an IP address or domain name.
//
// It will start the server if it has not been started yet.
//
// Returns zero on success or -1 on error, call tailscale_errmsg for details.
extern int tailscale_dial(tailscale sd, const char* network, const char* addr, tailscale_conn* conn_out);

// A tailscale_listener is a socket on the tailnet listening for connections.
//
// It is much like allocating a system socket(2) and calling listen(2).
// Accept connections with tailscale_accept and close the listener with close.
//
// Under the hood, a tailscale_listener is one half of a socketpair itself,
// used to move the connection fd from Go to C. This means you can use epoll
// or its equivalent on a tailscale_listener to know if there is a connection
// read to accept.
typedef int tailscale_listener;

// tailscale_listen listens for a connection on the tailnet.
//
// It is the spiritual equivalent to listen(2).
// The newly allocated listener is written to listener_out.
//
// network is a NUL-terminated string of the form "tcp", "udp", etc.
// addr is a NUL-terminated string of an IP address or domain name.
//
// It will start the server if it has not been started yet.
//
// Returns zero on success or -1 on error, call tailscale_errmsg for details.
extern int tailscale_listen(tailscale sd, const char* network, const char* addr, tailscale_listener* listener_out);

// tailscale_listen_funnel announces on the public internet using Tailscale Funnel.
//
// It also by default listens on your local tailnet, so connections can
// come from either inside or outside your network. To restrict connections
// to be just from the internet, use the FunnelOnly option.
//
// Currently, (2024-12-13), Funnel only supports TCP on ports 443, 8443, and 10000.
// The supported host name is limited to that configured for the tsnet.Server.
//
// It is the spiritual equivalent to listen(2).
// The newly allocated listener is written to listener_out.
//
// network is a NUL-terminated string of the form "tcp", "udp", etc.
// addr is a NUL-terminated string of an IP address or domain name.
//
// It will start the server if it has not been started yet.
//
// Returns zero on success or -1 on error, call tailscale_errmsg for details.
extern int tailscale_listen_funnel(tailscale sd, const char *network, const char *addr, int funnelOnly, tailscale_listener *listener_out);

// Returns the remote address for an incoming connection for a particular listener.
// The address (either ip4 or ip6) will ge written to buf on success.
// Returns:
// 	0      - Success
// 	EBADF  - sd is not a valid tailscale, or l or conn are not valid listeners or connections
// 	ERANGE - insufficient storage for buf
extern int tailscale_getremoteaddr(tailscale_listener l, tailscale_conn conn, char *buf, size_t buflen);

// tailscale_accept accepts a connection on a tailscale_listener.
//
// It is the spiritual equivalent to accept(2).
//
// The newly allocated connection is written to conn_out.
//
// Returns:
// 	0     - success
// 	EBADF - listener is not a valid tailscale
// 	-1    - call tailscale_errmsg for details
extern int tailscale_accept(tailscale_listener listener, tailscale_conn* conn_out);

// tailscale_accept_nonblocking accepts a connection on a tailscale_listener.
//
// Acts like tailscale_accept but if there is no connection to accept return immediately.
// Uses MSG_DONTWAIT flag to achieve this.
//
// Returns:
// 	0     - success
// 	EBADF - listener is not a valid tailscale
// 	-1    - call tailscale_errmsg for details
extern int tailscale_accept_nonblocking(tailscale_listener listener, tailscale_conn *conn_out);

// tailscale_loopback starts a loopback address server.
//
// The server has multiple functions.
//
// It can be used as a SOCKS5 proxy onto the tailnet.
// Authentication is required with the username "tsnet" and
// the value of proxy_cred used as the password.
//
// The HTTP server also serves out the "LocalAPI" on /localapi.
// As the LocalAPI is powerful, access to endpoints requires BOTH passing a
// "Sec-Tailscale: localapi" HTTP header and passing local_api_cred as
// the basic auth password.
//
// The pointers proxy_cred_out and local_api_cred_out must be non-NIL
// and point to arrays that can hold 33 bytes. The first 32 bytes are
// the credential and the final byte is a NUL terminator.
//
// If tailscale_loopback returns, then addr_our, proxy_cred_out,
// and local_api_cred_out are all NUL-terminated.
//
// Returns zero on success or -1 on error, call tailscale_errmsg for details.
extern int tailscale_loopback(tailscale sd, char* addr_out, size_t addrlen, char* proxy_cred_out, char* local_api_cred_out);

// tailscale_errmsg writes the details of the last error to buf.
// 
// After returning, buf is always NUL-terminated.
//
// Returns:
// 	0      - success
// 	EBADF  - sd is not a valid tailscale
// 	ERANGE - insufficient storage for buf
extern int tailscale_errmsg(tailscale sd, char* buf, size_t buflen);

// tailscale_cert_domains returns the list of domains for which the server can
// provide TLS certificates. These are also the DNS names for the Server.
//
// If the server is not running, it returns nil.
extern int tailscale_cert_domains(tailscale sd, char *buf, size_t buflen);

#ifdef __cplusplus
}
#endif

#endif
