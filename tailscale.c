// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include "tailscale.h"
#if defined(__APPLE__) || defined(__linux__)
#include <sys/socket.h>
#elif _WIN32
#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#else
#include <unistd.h>
#endif

#include <stdio.h>


// Functions exported by Go.
extern int TsnetNewServer();
extern int TsnetStart(int sd);
extern int TsnetUp(int sd);
extern int TsnetClose(int sd);
extern int TsnetErrmsg(int sd, char *buf, size_t buflen);
extern int TsnetDial(int sd, char *net, char *addr, int *connOut);
extern int TsnetSetDir(int sd, char *str);
extern int TsnetSetHostname(int sd, char *str);
extern int TsnetSetAuthKey(int sd, char *str);
extern int TsnetSetControlURL(int sd, char *str);
extern int TsnetSetEphemeral(int sd, int ephemeral);
extern int TsnetSetLogFD(int sd, int fd);
extern int TsnetListen(int sd, char *net, char *addr, int *listenerOut);
extern int TsnetLoopback(int sd, char *addrOut, size_t addrLen, char *proxyOut, char *localOut);

tailscale tailscale_new()
{
	return TsnetNewServer();
}

int tailscale_start(tailscale sd)
{
	return TsnetStart(sd);
}

int tailscale_up(tailscale sd)
{
	return TsnetUp(sd);
}

int tailscale_close(tailscale sd)
{
	return TsnetClose(sd);
}

int tailscale_dial(tailscale sd, const char *network, const char *addr, tailscale_conn *conn_out)
{
	return TsnetDial(sd, (char *)network, (char *)addr, (int *)conn_out);
}

int tailscale_listen(tailscale sd, const char *network, const char *addr, tailscale_listener *listener_out)
{
	return TsnetListen(sd, (char *)network, (char *)addr, (int *)listener_out);
}

int tailscale_accept(tailscale_listener ld, tailscale_conn *conn_out)
{

#if defined(__APPLE__) || defined(__linux__)
	struct msghdr msg = {0};

	char mbuf[256];
	struct iovec io = {.iov_base = mbuf, .iov_len = sizeof(mbuf)};
	msg.msg_iov = &io;
	msg.msg_iovlen = 1;

	char cbuf[256];
	msg.msg_control = cbuf;
	msg.msg_controllen = sizeof(cbuf);

	if (recvmsg(ld, &msg, 0) == -1)
	{
		return -1;
	}

	struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
	unsigned char *data = CMSG_DATA(cmsg);

	int fd = *(int *)data;
	*conn_out = fd;
	return 0;
#elif _WIN32

	// SOCKET ListenSocket = ld;
	// fd_set readfds;
	// struct timeval tv;
	// int result;

	// // Initialize the set
	// FD_ZERO(&readfds);
	// FD_SET(ListenSocket, &readfds);

	// // Set timeout to zero, for non-blocking operation
	// tv.tv_sec = 1;
	// tv.tv_usec = 0;

	// result = select(ListenSocket + 1, &readfds, NULL, NULL, &tv);

	// if (result == -1) {
	// 	printf("select failed with error: %u\n", WSAGetLastError());
	// } else if (result == 0) {
	// 	printf("No incoming connections\n");
	// } else {
	// 	printf("Socket is ready to accept a connection\n");
	// }
	// char mbuf[256];
	// WSABUF wsaBuf;
	// DWORD bytesReceived;
	// DWORD flags = 0;
	// SOCKET fd;

	// wsaBuf.buf = mbuf;
	// wsaBuf.len = sizeof(mbuf);

	// if (WSARecv(ld, &wsaBuf, 1, &bytesReceived, &flags, NULL, NULL) == SOCKET_ERROR)
	// {
	// 	// Print the error code
	// 	int error = WSAGetLastError();
	// 	fprintf(stderr, "WSARecv failed with error: %d\n", error);
	// 	return -1;
	// }

	// // Extract the socket descriptor from the received control information
	// if (WSAGetOverlappedResult(ld, NULL, &bytesReceived, FALSE, &flags) == SOCKET_ERROR)
	// {
	// 	int error = WSAGetLastError();
	// 	fprintf(stderr, "WSAGetOverlappedResult failed with error: %d\n", error);
	// 	return -1;
	// }
	// second attemp
	// WSADATA wsaData;
	// int error = WSAStartup(MAKEWORD(2,2), &wsaData);
    // if (error) {
    //     printf("WSAStartup() failed with error: %d\n", error);
    //     return 1;
    // }
	// fd =  WSAAccept(ListenSocket + 1, NULL, NULL, NULL, 0);
	// if (fd == INVALID_SOCKET) 
	// {	
	// 	int error = WSAGetLastError();
	// 	fprintf(stderr, "WSAAccept failed with error: %d\n", error);
	// 	//return -1;
	// } 
	
	// *conn_out = fd;
	// return 0;
	// third attempt
	// char mbuf[256];
	// WSABUF wsaBuf;
	// DWORD bytesReceived;
	// DWORD flags = 0;

	// wsaBuf.buf = mbuf;
	// wsaBuf.len = sizeof(mbuf);

	// if (WSARecv(ld, &wsaBuf, 1, &bytesReceived, &flags, NULL, NULL) == SOCKET_ERROR)
	// {
	// 	// Print the error code
	// 	int error = WSAGetLastError();
	// 	fprintf(stderr, "WSARecv failed with error: %d\n", error);
	// 	return -1;
	// }

	// // If WSARecv succeeded, return the socket
	// *conn_out = ld;
	// return 0;
	struct sockaddr clientAddr;
    int clientAddrSize = sizeof(clientAddr);

    // Accept incoming connection
    *conn_out = accept(ld, &clientAddr, &clientAddrSize);
    if (*conn_out == INVALID_SOCKET) {
        printf("Accept failed with error code: %d\n", WSAGetLastError());
        return -1;
    }

    return 0;

#endif
}

int tailscale_set_dir(tailscale sd, const char *dir)
{
	return TsnetSetDir(sd, (char *)dir);
}
int tailscale_set_hostname(tailscale sd, const char *hostname)
{
	return TsnetSetHostname(sd, (char *)hostname);
}
int tailscale_set_authkey(tailscale sd, const char *authkey)
{
	return TsnetSetAuthKey(sd, (char *)authkey);
}
int tailscale_set_control_url(tailscale sd, const char *control_url)
{
	return TsnetSetControlURL(sd, (char *)control_url);
}
int tailscale_set_ephemeral(tailscale sd, int ephemeral)
{
	return TsnetSetEphemeral(sd, ephemeral);
}
int tailscale_set_logfd(tailscale sd, int fd)
{
	return TsnetSetLogFD(sd, fd);
}

int tailscale_loopback(tailscale sd, char *addr_out, size_t addrlen, char *proxy_cred_out, char *local_api_cred_out)
{
	return TsnetLoopback(sd, addr_out, addrlen, proxy_cred_out, local_api_cred_out);
}

int tailscale_errmsg(tailscale sd, char *buf, size_t buflen)
{
	return TsnetErrmsg(sd, buf, buflen);
}