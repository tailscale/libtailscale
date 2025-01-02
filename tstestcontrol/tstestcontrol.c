// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include "tstestcontrol.h"
#include <stdio.h>

// Functions exported by go
extern long long  RunControl(char* buf, size_t buflen);
extern void StopControl();

// run_control starts an ephemeral control test server on localhost.
// buf must be a char* of sufficient size to hold the resulting URL
// stop_control must be called when you are finished with the instance
// 
// returns -1 on failure, 0 on success
int run_control(char* buf, size_t buflen) {
    return RunControl(buf, buflen);
}

// stop_control() stops the e
void stop_control() {
    StopControl();
}