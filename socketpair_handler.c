#ifdef _WIN32
#include "socketpair.c"
#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#include <stdio.h>
#pragma comment(lib, "ws2_32.lib")
#endif

int *get_socket_pair() {
		#ifdef _WIN32
			SOCKET spair[2];
			spair[0] = 0;
			spair[1] = 0;
			if(dumb_socketpair(spair, 1) == SOCKET_ERROR)
				fprintf(stderr, "Init failed, creating socketpair: %s\n", strerror(errno));
			return spair;
		#endif
		return -1;
}