// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause


#include <stdio.h>
#include <unistd.h>
#include "tailscale.h"
extern int UpdateProxyMap(char* key, char* value);
extern int TsnetIPAddr(tailscale sd, char *addrOut, size_t addrLen);
char errmsg[256];
int err(tailscale ts) {
	tailscale_errmsg(ts, errmsg, sizeof(errmsg));
	printf("echo_server: %s\n", errmsg);
	return 1;
}

int mira_start(const char* authkey, const char* control_url) {
	int ret;

	tailscale ts = tailscale_new();
	tailscale_set_authkey(ts, authkey);
	tailscale_set_control_url(ts, control_url);
	if (tailscale_set_ephemeral(ts, 1)) {
		return err(ts);
	}
	if (tailscale_up(ts)) {
		return err(ts);
	}
	return ts;
}

int get_ip(tailscale sd, char* addr_out, size_t addrlen) {
	return TsnetIPAddr(sd, addr_out, addrlen);
}
void update_map(const char* key, const char* value) {
    UpdateProxyMap((char*)key, (char*)value);
}
