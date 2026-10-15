// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

package main

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"

	"github.com/tailscale/libtailscale/tsnetctest"
	"tailscale.com/tsnet"
)

func TestListenValidationBeforeStart(t *testing.T) {
	for _, tt := range []struct {
		name, network, addr, errorText string
	}{
		{"network", "invalid-network", ":80", "unsupported network type"},
		{"missing-port", "tcp", "127.0.0.1", "missing port in address"},
		{"port-range", "tcp", ":65536", "invalid port:"},
		{"port-name", "tcp", ":libtailscale-invalid-service", "invalid port:"},
		{"hostname", "tcp", "localhost:80", "host part must be empty or IP literal"},
		{"ipv4", "tcp4", "[::1]:80", "invalid non-IPv4 addr"},
		{"ipv6", "tcp6", "127.0.0.1:80", "invalid non-IPv6 addr"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			sd := TsnetNewServer()
			defer func() {
				if rc := TsnetClose(sd); rc != 0 {
					t.Errorf("Close = %d", rc)
				}
			}()
			// Start would fail before allocating any networking resources. Invalid
			// Listen arguments must be rejected before that initialization error.
			badDir := filepath.Join(t.TempDir(), "file")
			if err := os.WriteFile(badDir, nil, 0600); err != nil {
				t.Fatal(err)
			}
			servers.mu.Lock()
			s := servers.m[sd]
			servers.mu.Unlock()
			s.s.Dir = badDir
			rc, fd := tsnetctest.Listen(int32(sd), tt.network, tt.addr)
			if fd >= 0 {
				syscall.Close(fd)
			}
			if rc != -1 || fd != -1 {
				t.Fatalf("Listen = %d, fd=%d", rc, fd)
			}
			errRC, buf := tsnetctest.Errmsg(int32(sd), 1024)
			message, _, _ := strings.Cut(string(buf), "\x00")
			if errRC != 0 || !strings.Contains(message, tt.errorText) {
				t.Fatalf("Listen error = %d, %q; want %q before Start", errRC, message, tt.errorText)
			}
			// Compare against tsnet's own pre-initialization validation, including
			// exact error text. This also detects drift when the dependency changes.
			native := &tsnet.Server{Dir: badDir}
			ln, err := native.Listen(tt.network, tt.addr)
			if ln != nil {
				ln.Close()
			}
			if err == nil || message != err.Error() {
				t.Fatalf("bridge error %q differs from tsnet: %v", message, err)
			}
		})
	}
}
