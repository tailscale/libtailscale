// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// How to compile
// 	cc mira.c /path/to/your.a 
// On macOS you need to add the following flags to your C compiler:
// 	-framework CoreFoundation -framework Security

#include <stdio.h>
#include <unistd.h>
#include "mira.h"

int main(void) {
	mira_start();
	// here is where you need to customize
	update_map("fs.jitlib.3mao.uk", "https://100.64.0.1");
	// the end
	
	sleep (15);
	char addr_out[100];
	get_ip(addr_out, sizeof(addr_out));


	printf("-----------------------------------------\n");
	printf("IP addr %s\n", addr_out);
	printf("-----------------------------------------\n");
        while(1){
	    sleep(100);
	}

	return 0;
}


