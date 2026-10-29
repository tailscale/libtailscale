package main

import (
	"syscall"
	"testing"
	"time"

	"github.com/tailscale/libtailscale/tsnetctest"
	"golang.org/x/sys/unix"
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

// TestSocketpairCloexec checks that socketpair returns both ends
// close-on-exec, so that spawned processes cannot inherit the
// listener and connection fds.
func TestSocketpairCloexec(t *testing.T) {
	fds, err := socketpair()
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(fds[0])
	defer syscall.Close(fds[1])

	for _, fd := range fds {
		flags, err := unix.FcntlInt(uintptr(fd), syscall.F_GETFD, 0)
		if err != nil {
			t.Fatal(err)
		}
		if flags&syscall.FD_CLOEXEC == 0 {
			t.Errorf("socketpair end %d is not close-on-exec", fd)
		}
	}
}

// TestRecvFdCloexec exercises the SCM_RIGHTS receive path TsnetAccept
// uses: an fd passed over the listener socketpair must be
// close-on-exec by the time it reaches C (via MSG_CMSG_CLOEXEC in
// recvFlags on Linux, via closeOnExec on platforms without it).
func TestRecvFdCloexec(t *testing.T) {
	sp, err := socketpair()
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(sp[0])
	defer syscall.Close(sp[1])

	// The fd we ship across the socketpair.
	pair, err := socketpair()
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(pair[0])
	defer syscall.Close(pair[1])

	var rec [listenAddrLen]byte
	copy(rec[:], "1.2.3.4")
	if err := syscall.Sendmsg(sp[0], rec[:], syscall.UnixRights(pair[0]), nil, 0); err != nil {
		t.Fatal(err)
	}

	data := make([]byte, listenAddrLen)
	cbuf := make([]byte, syscall.CmsgSpace(4))
	n, oobn, _, _, err := syscall.Recvmsg(sp[1], data, cbuf, recvFlags)
	if err != nil {
		t.Fatal(err)
	}
	if n != listenAddrLen {
		t.Fatalf("got %d bytes, want %d", n, listenAddrLen)
	}
	scms, err := syscall.ParseSocketControlMessage(cbuf[:oobn])
	if err != nil {
		t.Fatal(err)
	}
	if len(scms) != 1 {
		t.Fatalf("got %d control messages, want 1", len(scms))
	}
	fds, err := syscall.ParseUnixRights(&scms[0])
	if err != nil {
		t.Fatal(err)
	}
	if len(fds) != 1 {
		t.Fatalf("got %d fds, want 1", len(fds))
	}
	closeOnExec(fds[0]) // mirrors TsnetAccept
	defer syscall.Close(fds[0])

	flags, err := unix.FcntlInt(uintptr(fds[0]), syscall.F_GETFD, 0)
	if err != nil {
		t.Fatal(err)
	}
	if flags&syscall.FD_CLOEXEC == 0 {
		t.Errorf("fd received via SCM_RIGHTS is not close-on-exec")
	}
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
