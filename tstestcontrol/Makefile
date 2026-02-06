# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

.PHONY: all clean

all: libtstestcontrol.a

libtstestcontrol.a:
	go build -buildmode=c-archive -o $@

clean:
	rm -f libtstestcontrol.a
