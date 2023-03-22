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
	update_map("openwrt.jit.com.cn", "http://100.122.189.12");
	// the end
        while(1){
	    sleep(100);
	}

	return 0;
}


