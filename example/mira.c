// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// How to compile
// 	cc mira.c /path/to/your.a 
// On macOS you need to add the following flags to your C compiler:
// 	-framework CoreFoundation -framework Security
// On Windows you need to add the following flags to your C compiler:
// 	 -lcrypt32 -lncrypt

#include <stdio.h>
#include <unistd.h>
#include "mira.h"

int main(void) {
	int sd;
	sd = mira_start("5b4958754e0648075c2ce386365e26a99d19b490dbcbb846", "http://8.140.130.195:8888");
	// here is where you need to customize
	update_map("fs.jitlib.3mao.uk", "https://100.64.0.1");
	// the end
	
	sleep (5);
	char addr_out[100];
	get_ip(sd, addr_out, sizeof(addr_out));


	printf("-----------------------------------------\n");
	printf("IP addr %s\n", addr_out);
	printf("-----------------------------------------\n");
        while(1){
	    sleep(100);
	}

	return 0;
}


