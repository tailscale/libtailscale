// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include "tailscale.h"
#include <sys/socket.h>
#include <stdio.h>
#include <unistd.h>

// Functions exported by Go.
extern int TsnetNewServer();
extern int TsnetStart(int sd);
extern int TsnetUp(int sd);
extern int TsnetClose(int sd);
extern int TsnetErrmsg(int sd, char* buf, size_t buflen);
extern int TsnetDial(int sd, char* net, char* addr, int* connOut);
extern int TsnetSetDir(int sd, char* str);
extern int TsnetSetHostname(int sd, char* str);
extern int TsnetSetAuthKey(int sd, char* str);
extern int TsnetSetControlURL(int sd, char* str);
extern int TsnetSetEphemeral(int sd, int ephemeral);
extern int TsnetSetLogFD(int sd, int fd);
extern int TsnetGetIps(int sd, char *buf, size_t buflen);
extern int TsnetGetRemoteAddr(int listener, int conn, char *buf, size_t buflen);
extern int TsnetListen(int sd, char* net, char* addr, int* listenerOut);
extern int TsnetLoopback(int sd, char* addrOut, size_t addrLen, char* proxyOut, char* localOut);

tailscale tailscale_new() {
	return TsnetNewServer();
}

int tailscale_start(tailscale sd) {
	return TsnetStart(sd);
}

int tailscale_up(tailscale sd) {
	return TsnetUp(sd);
}

int tailscale_close(tailscale sd) {
	return TsnetClose(sd);
}

int tailscale_dial(tailscale sd, const char* network, const char* addr, tailscale_conn* conn_out) {
	return TsnetDial(sd, (char*)network, (char*)addr, (int*)conn_out);
}

int tailscale_listen(tailscale sd, const char* network, const char* addr, tailscale_listener* listener_out) {
	return TsnetListen(sd, (char*)network, (char*)addr, (int*)listener_out);
}

int tailscale_accept(tailscale_listener ld, tailscale_conn* conn_out) {
	struct msghdr msg = {0};

	char mbuf[256];
	struct iovec io = { .iov_base = mbuf, .iov_len = sizeof(mbuf) };
	msg.msg_iov = &io;
	msg.msg_iovlen = 1;

	char cbuf[256];
	msg.msg_control = cbuf;
	msg.msg_controllen = sizeof(cbuf);

	if (recvmsg(ld, &msg, 0) == -1) {
		return -1;
	}

	struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
	unsigned char* data = CMSG_DATA(cmsg);

	int fd = *(int*)data;
	*conn_out = fd;
	return 0;
}

int tailscale_getremoteaddr(tailscale_listener l, tailscale_conn conn, char* buf, size_t buflen) {
	return TsnetGetRemoteAddr(l, conn, buf, buflen);
}

int tailscale_getips(tailscale sd, char* buf, size_t buflen) {
	return TsnetGetIps(sd, buf, buflen);
}

int tailscale_set_dir(tailscale sd, const char* dir) {
	return TsnetSetDir(sd, (char*)dir);
}
int tailscale_set_hostname(tailscale sd, const char* hostname) {
	return TsnetSetHostname(sd, (char*)hostname);
}
int tailscale_set_authkey(tailscale sd, const char* authkey) {
	return TsnetSetAuthKey(sd, (char*)authkey);
}
int tailscale_set_control_url(tailscale sd, const char* control_url) {
	return TsnetSetControlURL(sd, (char*)control_url);
}
int tailscale_set_ephemeral(tailscale sd, int ephemeral) {
	return TsnetSetEphemeral(sd, ephemeral);
}
int tailscale_set_logfd(tailscale sd, int fd) {
	return TsnetSetLogFD(sd, fd);
}

int tailscale_loopback(tailscale sd, char* addr_out, size_t addrlen, char* proxy_cred_out, char* local_api_cred_out) {
	return TsnetLoopback(sd, addr_out, addrlen, proxy_cred_out, local_api_cred_out);
}

int tailscale_errmsg(tailscale sd, char* buf, size_t buflen) {
	return TsnetErrmsg(sd, buf, buflen);
}
