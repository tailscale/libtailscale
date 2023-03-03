# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

# Construct a source package by vendoring all source and packing it up into a
# tarball.

ifeq ($(shell uname -s),Darwin)
	TAR?=gtar
else
	TAR?=tar
endif

all: check

check: libtailscale.tar.zst
	@echo "Checking that the tarball is self-contained..."
	test `$(TAR) tf libtailscale.tar.zst | grep -c -v '^libtailscale/'` -eq 0 || (echo "Tarball is not self-contained!" && exit 1)

	@tar xf libtailscale.tar.zst
	@echo "Checking that the tarball is usable..."
	@cd libtailscale && ./configure && make


clean:
	rm -rf ./libtailscale.tar.zst ../vendor ./libtailscale

../vendor: ../go.mod ../go.sum ../tailscale.go Makefile.src Makefile
	go mod vendor

libtailscale.tar.zst: Makefile.src configure ../vendor ../LICENSE ../tailscale.go ../go.mod ../go.sum
	$(TAR) --transform 's#^#libtailscale/#' --transform 's#Makefile.src#Makefile#' -acf $@ Makefile.src configure ../vendor ../LICENSE ../tailscale.go ../go.mod ../go.sum