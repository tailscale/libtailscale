// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include "tailscale.h"

#include <signal.h>
#include <sys/socket.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

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
extern int TsnetListen(int sd, char* net, char* addr, int* listenerOut);
extern int TsnetAccept(int ld, int* connOut);
extern int TsnetLoopback(int sd, char* addrOut, size_t addrLen, char* proxyOut, char* localOut);

void server_loop(int fd);

int tailscale_control_server() {
	int sv[2];

	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == -1) {
		perror("socketpair");
		exit(EXIT_FAILURE);
	}

	const pid_t child_pid = fork();

	switch (child_pid) {
		case -1:
			perror("fork");
			exit(EXIT_FAILURE);
		case 0:
			printf("In child\n");
			close(sv[0]);
			printf("starting loop\n");
			server_loop(sv[1]);
		default:
			printf("Child is %d returning %d\n", child_pid, sv[0]);
			close(sv[1]);
			return sv[0];
	}
}

void server_loop(const int fd) {
	for (;;) {
		char mesg_code;
		int size = read(fd, &mesg_code, 1);
		if (size == 0) {
			continue;
		}

		if (size < 0) {
			printf("error in read: %d\n", size);
			continue;
		}

		switch (mesg_code) {
			case 1: {
				printf("calling TsnetNewServer()\n");
				const int ret = TsnetNewServer();
				printf("writing sd %d\n", ret);
				write(fd, &ret, sizeof(ret));
				break;
			}
			case 2: {
				tailscale sd;
				printf("reading sd\n");
				read(fd, &sd, sizeof(sd));

				printf("calling TsnetStart(%d)\n", sd);
				const int ret = TsnetStart(sd);
				printf("writing ret val %d\n", ret);
				write(fd, &ret, sizeof(ret));
				break;
			}
			case -1: {
				printf("closing server\n");
				tailscale sd;
				printf("reading sd\n");
				read(fd, &sd, sizeof(sd));
				printf("calling TsnetClose(%d)\n", sd);
				const int ret = TsnetClose(sd);
				printf("writing ret val %d\n", ret);
				write(fd, &ret, sizeof(ret));
				printf("closing and exiting\n");
				close(fd);
				exit(EXIT_SUCCESS);
			}
			case 5: {
				printf("error message...");
				tailscale sd;
				printf("reading sd\n");
				read(fd, &sd, sizeof(sd));
				printf("calling TsnetErrmsg(%d)\n", sd);
				char buf;
				const int ret = TsnetErrmsg(sd, &buf, 1);
				break;
			}
			default:
				printf("unexpected code: %d\n", mesg_code);
				break;
		}
	}
	close(fd);
	exit(EXIT_FAILURE);
}

tailscale tailscale_new(int fd) {
	const char mesg_code = 1;
	printf("sending new command...\n");
	write(fd, &mesg_code, sizeof(mesg_code));

	printf("reading sd...\n");
	tailscale ret;
	read(fd, &ret, sizeof(ret));

	printf("returning sd: %d\n", ret);
	return ret;
}

int tailscale_start(int fd, tailscale sd) {
	const char mesg_code = 2;
	printf("sending start command...\n");
	write(fd, &mesg_code, sizeof(mesg_code));
	printf("sending sd...\n");
	write(fd, &sd, sizeof(sd));

	printf("reading ret...\n");
	int ret;
	read(fd, &ret, sizeof(ret));

	printf("returning ret: %d\n", ret);
	return ret;
}

int tailscale_up(tailscale sd) {
	return TsnetUp(sd);
}

int tailscale_close(int fd, tailscale sd) {
	const char mesg_code = -1;
	printf("sending close command...\n");
	write(fd, &mesg_code, sizeof(mesg_code));
	printf("sending sd %d...\n", sd);
	write(fd, &sd, sizeof(sd));

	printf("reading ret...\n");
	int ret;
	read(fd, &ret, sizeof(ret));

	printf("closing fd: %d and returning %d\n", fd, ret);
	close(fd);
	return ret;
}

int tailscale_dial(tailscale sd, const char* network, const char* addr, tailscale_conn* conn_out) {
	return TsnetDial(sd, (char*)network, (char*)addr, (int*)conn_out);
}

int tailscale_listen(tailscale sd, const char* network, const char* addr, tailscale_listener* listener_out) {
	return TsnetListen(sd, (char*)network, (char*)addr, (int*)listener_out);
}

int tailscale_accept(tailscale_listener ld, tailscale_conn* conn_out) {
	return TsnetAccept(ld, (int*)conn_out);
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

int tailscale_errmsg(int fd, tailscale sd, char* buf, size_t buflen) {
	const char mesg_code = 5;
	printf("sending errormsg command...\n");
	write(fd, &mesg_code, sizeof(mesg_code));
	write(fd, &sd, sizeof(sd));

	return 0;
}
