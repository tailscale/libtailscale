#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include "tsnetctest.h"

// Define Windows equivalent types and functions
typedef SOCKET tailscale_conn_w;
typedef SOCKET tailscale_listener_w;

// Define Windows equivalent error reporting
#define snprintf _snprintf

char* tmps1;
char* tmps2;

char* control_url = 0;

int addrlen  = 128;
char* addr;
char* proxy_cred;
char* local_api_cred ;

int errlen = 512;
char* err ;

tailscale s1, s2;

int set_err(tailscale sd, char tag) {
    // Implement your error reporting logic here
    return 1;
}

void print_error(const char* prefix) {
    LPSTR messageBuffer;
    DWORD errorCode = WSAGetLastError();

    FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, errorCode, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), (LPSTR)&messageBuffer, 0, NULL);

    printf("%s: %s\n", prefix, messageBuffer);

    LocalFree(messageBuffer);
}

int test_conn() {
    err = calloc(errlen, 1);
    addr = calloc(addrlen, 1);
    proxy_cred = calloc(33, 1);
    local_api_cred = calloc(33, 1);
    int ret;

    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        printf("WSAStartup failed\n");
        return 1;
    }

    s1 = tailscale_new();
    // Set control_url, tmps1, and other configurations for s1

    s2 = tailscale_new();
    // Set control_url, tmps2, and other configurations for s2

    int ln;
    // Setup listener ln

    int w;
    // Dial connection using s2

    int r;
    // Accept connection using ln

	if ((ret = tailscale_set_control_url(s1, control_url)) != 0) {
		return set_err(s1, '0');
	}
	if ((ret = tailscale_set_dir(s1, tmps1)) != 0) {
		return set_err(s1, '1');
	}
	if ((ret = tailscale_set_logfd(s1, -1)) != 0) {
		return set_err(s1, '2');
	}
	if ((ret = tailscale_up(s1)) != 0) {
		return set_err(s1, '3');
	}

	if ((ret = tailscale_set_control_url(s2, control_url)) != 0) {
		return set_err(s2, '4');
	}
	if ((ret = tailscale_set_dir(s2, tmps2)) != 0) {
		return set_err(s2, '5');
	}
	if ((ret = tailscale_set_logfd(s2, -1)) != 0) {
		return set_err(s1, '6');
	}
	if ((ret = tailscale_up(s2)) != 0) {
		return set_err(s2, '7');
	}

	if ((ret = tailscale_listen(s1, "tcp", ":8081", &ln)) != 0) {
		return set_err(s1, '8');
	}

	if ((ret = tailscale_dial(s2, "tcp", "100.64.0.1:8081", &w)) != 0) {
		return set_err(s2, '9');
	}

	if ((ret = tailscale_accept(ln, &r)) != 0) {
		return set_err(s2, 'a');
	}

    const char want[] = "hello";
    SSIZE_T wret;
    if ((wret = send(w, want, sizeof(want), 0)) != sizeof(want)) {
        print_error("SEND error");
    }
    char got[sizeof(want)];
    SSIZE_T rret;
    int error = 0;
    socklen_t len = sizeof (error);
    int retval = getsockopt (r, SOL_SOCKET, SO_ERROR, &error, &len);

    if (retval != 0) {
        // There was a problem getting the error code
        fprintf(stderr, "error getting socket error code: %s\n", strerror(retval));
    }

    if (error != 0) {
        // socket has a non zero error status
        fprintf(stderr, "socket error: %s\n", strerror(error));
    }
    if ((rret = recv(r, got, sizeof(got), 0)) != sizeof(want)) {
        print_error("RECEIVE error");
    }
    if ((ret = tailscale_loopback(s1, addr, addrlen, proxy_cred, local_api_cred)) != 0) {
        // Handle error
    }
    // Compare got with want

    closesocket(w);
    closesocket(r);
    closesocket(ln);

    WSACleanup();

    // Cleanup resources

    return 0;
}

int close_conn() {
    if (tailscale_close(s1) != 0) {
		return set_err(s1, 'd');
	}
	if (tailscale_close(s2) != 0) {
		return set_err(s2, 'e');
	}
	return 0;
}
