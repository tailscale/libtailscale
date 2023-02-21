package main

import (
	"testing"

	"github.com/tailscale/libtailscale/tsnetctest"
)

func TestConn(t *testing.T) {
	tsnetctest.RunTestConn(t)

	// RunTestConn cleans up after itself, so there shouldn't be
	// anything left in the global maps.
	conns.mu.Lock()
	rem := len(conns.m)
	conns.mu.Unlock()

	if rem > 0 {
		t.Fatalf("want no remaining tsnet_conn objects, got %d", rem)
	}

	listeners.mu.Lock()
	rem = len(listeners.m)
	listeners.mu.Unlock()

	if rem > 0 {
		t.Fatalf("want no remaining tsnet_listener objects, got %d", rem)
	}

	servers.mu.Lock()
	rem = len(servers.m)
	servers.mu.Unlock()

	if rem > 0 {
		t.Fatalf("want no remaining tsnet objects, got %d", rem)
	}
}
