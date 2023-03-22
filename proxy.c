// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause


#include <stdio.h>
#include <unistd.h>
#include "tailscale.h"
extern int UpdateProxyMap(char* key, char* value);
char errmsg[256];
int err(tailscale ts) {
	tailscale_errmsg(ts, errmsg, sizeof(errmsg));
	printf("echo_server: %s\n", errmsg);
	return 1;
}

int mira_start(void) {
	int ret;

	tailscale ts = tailscale_new();
	if (tailscale_set_ephemeral(ts, 1)) {
		return err(ts);
	}
	if (tailscale_up(ts)) {
		return err(ts);
	}
	return 0;
}

void update_map(const char* key, const char* value) {
    UpdateProxyMap((char*)key, (char*)value);
}
