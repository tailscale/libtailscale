# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

all: libtailscale.a libtailscale.so libtailscale.pc

libtailscale.a:
	go build -trimpath -buildmode=c-archive -o libtailscale.a

libtailscale.so:
	go build -trimpath -buildmode=c-shared -o libtailscale.so

libtailscale.pc:
	echo "prefix=/usr/local" > libtailscale.pc
	echo "exec_prefix=\${prefix}" >> libtailscale.pc
	echo "libdir=\${exec_prefix}/lib" >> libtailscale.pc
	echo "includedir=\${prefix}/include" >> libtailscale.pc
	echo "" >> libtailscale.pc
	echo "Name: libtailscale" >> libtailscale.pc
	echo "Description: Tailscale library" >> libtailscale.pc
	echo "Version: 0.0.1" >> libtailscale.pc
	echo "Libs: -L\${libdir} -ltailscale" >> libtailscale.pc
	echo "Cflags: -I\${includedir}" >> libtailscale.pc
