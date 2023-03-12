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

#include "../tailscale.h"
#include <stdio.h>
#include <unistd.h>

int main(void) {
	int ret;

	tailscale ts = tailscale_new();
	if (tailscale_set_ephemeral(ts, 1)) {
		return err(ts);
	}
	if (tailscale_up(ts)) {
		return err(ts);
	}
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
