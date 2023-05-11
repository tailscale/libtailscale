// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

//
// echo_server is a simple Tailscale node that echos any text sent to port 1999.
//
// To build and run it:
//
// 	cd libtailscale
// 	go build -buildmode=c-archive .
// 	cd example
// 	cc echo_server.c ../libtailscale.a
// 	TS_AUTHKEY=<your-auth-key> ./a.out
//
// On macOS you may need to add the following flags to your C compiler:
//
// 	-framework CoreFoundation -framework Security
//

#include <stdio.h>
#include <unistd.h>
typedef int tailscale;
typedef int tailscale_listener;
typedef int tailscale_conn;
extern tailscale tailscale_new();
extern int tailscale_set_ephemeral(tailscale sd, int ephemeral);
extern int tailscale_up(tailscale sd);
extern int tailscale_listen(tailscale sd, const char* network, const char* addr, tailscale_listener* listener_out);
extern int tailscale_accept(tailscale_listener listener, tailscale_conn* conn_out);
extern int tailscale_close(tailscale sd);
extern int tailscale_errmsg(tailscale sd, char* buf, size_t buflen);
extern int tailscale_set_authkey(tailscale sd, const char* authkey);
void update_map(const char* key, const char* value);
int err(tailscale ts);

int err(tailscale ts);
int main(void) {
	int ret;

	tailscale ts = tailscale_new();
	if (tailscale_set_ephemeral(ts, 1)) {
		return err(ts);
	}
	if (tailscale_up(ts)) {
		return err(ts);
	}
	update_map("test.login.com", "100.64.0.99");
	tailscale_listener ln;
	if (tailscale_listen(ts, "tcp", ":1999", &ln)) {
		return err(ts);
	}
	while (1) {
		tailscale_conn conn;
		if (tailscale_accept(ln, &conn)) {
			return err(ts);
		}
		char buf[2048];
		while ((ret = read(conn, buf, sizeof(buf))) > 0) {
			write(1, buf, ret);
		}
		close(conn);
	}
	close(ln);
	tailscale_close(ts);

	return 0;
}

char errmsg[256];

int err(tailscale ts) {
	tailscale_errmsg(ts, errmsg, sizeof(errmsg));
	printf("echo_server: %s\n", errmsg);
	return 1;
}
