// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include <stddef.h>

// External definitions for libtstestcontrol

// TODO: Is there away to avoid the header duplication here?
// WARNING: Adding/changing the libtstestcontrol functions must be replicated here

// Runs a new control.  Returns the URL in the buffer
extern int run_control(char* buf, size_t buflen);

// Stops the running control
extern void stop_control();
