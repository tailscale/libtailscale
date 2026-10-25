package main

import (
	"net"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/tailscale/libtailscale/tsnetctest"
)

func TestConn(t *testing.T) {
	tsnetctest.RunTestConn(t)

	// RunTestConn cleans up after itself, so there shouldn't be
	// anything left in the global maps.

	servers.mu.Lock()
	rem := len(servers.m)
	servers.mu.Unlock()

	if rem > 0 {
		t.Fatalf("want no remaining tsnet objects, got %d", rem)
	}

	var remConns, remLns int

	for i := 0; i < 50; i++ {
		conns.mu.Lock()
		remConns = len(conns.m)
		conns.mu.Unlock()

		listeners.mu.Lock()
		remLns = len(listeners.m)
		listeners.mu.Unlock()

		if remConns == 0 && remLns == 0 {
			break
		}

		// We are waiting for cleanup goroutines to finish.
		//
		// libtailscale closes one side of a socketpair and
		// then Go responds to the other side being unreadable
		// by closing the connections and listeners.
		//
		// This is inherently asynchronous.
		// Without ditching the standard close(2) and having our
		// own close functions.
		//
		// So we spin for a while
		time.Sleep(100 * time.Millisecond)
	}

	if remConns > 0 {
		t.Errorf("want no remaining tsnet_conn objects, got %d", remConns)
	}

	if remLns > 0 {
		t.Errorf("want no remaining tsnet_listener objects, got %d", remLns)
	}
}

// TestGetRemoteAddr checks that tailscale_getremoteaddr reports the
// right peer address for every accepted connection while fd numbers
// are being reused across connections (tailscale/tailscale#18310).
func TestGetRemoteAddr(t *testing.T) {
	tsnetctest.RunTestGetRemoteAddr(t)
}

func TestExtractIP(t *testing.T) {
	ipv4 := "1.23.33.4:12343"
	ipv6 := "[1::2234::34fc::44]:56576"

	got4 := extractIP(ipv4)
	got6 := extractIP(ipv6)

	want4 := "1.23.33.4"
	want6 := "[1::2234::34fc::44]"

	if got4 != want4 {
		t.Errorf("ipv4 port stripping failed")
	}

	if got6 != want6 {
		t.Errorf("ipv6 port stripping failed %s != %s", got6, want6)
	}
}

type closeTrackingConn struct {
	net.Conn
	once   sync.Once
	closed chan struct{}
}

func (c *closeTrackingConn) Close() error {
	c.once.Do(func() { close(c.closed) })
	return c.Conn.Close()
}

// TestConnCleanupAfterFDReuse checks that every connection is cleaned up
// when the number of its C-side fd is reused while it is still alive.
// TsnetListen closes that fd right after passing it to C, so the next
// connection's socketpair usually gets the same number.
func TestConnCleanupAfterFDReuse(t *testing.T) {
	const n = 8
	var tracked []*closeTrackingConn
	var peers []net.Conn
	var fds []int
	for range n {
		c, peer := net.Pipe()
		tc := &closeTrackingConn{Conn: c, closed: make(chan struct{})}
		tracked = append(tracked, tc)
		peers = append(peers, peer)
		fd, err := newConn(&server{}, tc)
		if err != nil {
			t.Fatal(err)
		}
		fds = append(fds, int(fd))
		syscall.Close(int(fd))
	}
	t.Logf("C-side fds: %v", fds)

	for _, peer := range peers {
		peer.Close()
	}
	timeout := time.After(5 * time.Second)
	for i, tc := range tracked {
		select {
		case <-tc.closed:
		case <-timeout:
			t.Fatalf("connection %d (C-side fd %d) was never closed", i, fds[i])
		}
	}
}
