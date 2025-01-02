// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include <stddef.h>

#ifndef TAILSCALE_H
#define TAILSCALE_H

#ifdef __cplusplus
extern "C" {
#endif

// External definitions for libtstestcontrol.h

// Runs a new control.  Returns the URL in the buffer
// returns 0 on success, an error code on failure
extern int run_control(char* buf, size_t buflen);

// Stops the running control
extern void stop_control();

#ifdef __cplusplus
}
#endif

#endif