#ifdef _WIN32
#include "socketpair_handler.h"
#include "socketpair.c"
#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#include <stdio.h>
#pragma comment(lib, "ws2_32.lib")
#endif

SOCKET *get_socket_pair() {
		#ifdef _WIN32
			SOCKET* spair = (SOCKET*)malloc(2 * sizeof(SOCKET));
        	if (spair == NULL) {
            	fprintf(stderr, "Failed to allocate memory for socket pair\n");
            	return NULL;
        	}

			spair[0] = 0;
			spair[1] = 0;
			if(dumb_socketpair(spair, 1) == SOCKET_ERROR)
				fprintf(stderr, "Init failed, creating socketpair: %s\n", strerror(errno));
				free(spair);
			return spair;
		#else
			return NULL;
		#endif
		
		
}