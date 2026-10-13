// Package tsnetctest tests the libtailscale C bindings.
//
// It is used by tailscale_test.go, because you are not allowed to
// use the 'import "C"' directive in tests.
package tsnetctest

/*
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "../tailscale.h"

char* tmps1;
char* tmps2;

char* control_url = 0;

int addrlen = 128;
char* addr = NULL;
char* proxy_cred = NULL;
char* local_api_cred = NULL;

int errlen = 512;
char* err = NULL;

tailscale s1, s2;

int set_err(tailscale sd, char tag) {
	err[0] = tag;
	err[1] = ':';
	err[2] = ' ';
	tailscale_errmsg(sd, &err[3], errlen-3);
	return 1;
}

int test_conn() {
	err = calloc(errlen, 1);
	addr = calloc(addrlen, 1);
	proxy_cred = calloc(33, 1);
	local_api_cred = calloc(33, 1);
	int ret;

	s1 = tailscale_new();
	if ((ret = tailscale_set_control_url(s1, control_url)) != 0) {
		return set_err(s1, '0');
	}
	if ((ret = tailscale_set_dir(s1, tmps1)) != 0) {
		return set_err(s1, '1');
	}
	if ((ret = tailscale_set_logfd(s1, -1)) != 0) {
		return set_err(s1, '2');
	}
	if ((ret = tailscale_up(s1)) != 0) {
		return set_err(s1, '3');
	}

	s2 = tailscale_new();
	if ((ret = tailscale_set_control_url(s2, control_url)) != 0) {
		return set_err(s2, '4');
	}
	if ((ret = tailscale_set_dir(s2, tmps2)) != 0) {
		return set_err(s2, '5');
	}
	if ((ret = tailscale_set_logfd(s2, -1)) != 0) {
		return set_err(s1, '6');
	}
	if ((ret = tailscale_up(s2)) != 0) {
		return set_err(s2, '7');
	}

	tailscale_listener ln;
	if ((ret = tailscale_listen(s1, "tcp", ":8081", &ln)) != 0) {
		return set_err(s1, '8');
	}

	tailscale_conn w;
	if ((ret = tailscale_dial(s2, "tcp", "100.64.0.1:8081", &w)) != 0) {
		return set_err(s2, '9');
	}

	tailscale_conn r;
	if ((ret = tailscale_accept(ln, &r)) != 0) {
		return set_err(s2, 'a');
	}

	const char want[] = "hello";
	ssize_t wret;
	if ((wret = write(w, want, sizeof(want))) != sizeof(want)) {
		snprintf(err, errlen, "short write: %zd, errno: %d (%s)", wret, errno, strerror(errno));
		return 1;
	}
	char* got = malloc(sizeof(want));
	if ((wret = read(r, got, sizeof(want))) != sizeof("hello")) {
		snprintf(err, errlen, "short read: %zd on fd %d, errno: %d (%s)", wret, r, errno, strerror(errno));
		return 1;
	}
	if (strncmp(got, want, sizeof(want)) != 0) {
		snprintf(err, errlen, "got '%s' want '%s'", got, want);
		return 1;
	}

	if ((ret = close(w)) != 0) {
		snprintf(err, errlen, "failed to close w: %d (%s)", errno, strerror(errno));
		return 1;
	}
	if ((ret = close(r)) != 0) {
		snprintf(err, errlen, "failed to close r: %d (%s)", errno, strerror(errno));
		return 1;
	}
	if ((ret = close(ln)) != 0) {
		return set_err(s1, 'a');
	}
	if ((ret = close(ln)) == 0 || errno != EBADF) {
		snprintf(err, errlen, "double tailscale_listener close = %d (errno %d: %s), want EBADF", ret, errno, strerror(errno));
		return 1;
	}

	if ((ret = tailscale_loopback(s1, addr, addrlen, proxy_cred, local_api_cred)) != 0) {
		return set_err(s1, 'b');
	}

	return 0;
}

int close_conn() {
	if (tailscale_close(s1) != 0) {
		return set_err(s1, 'd');
	}
	if (tailscale_close(s2) != 0) {
		return set_err(s2, 'e');
	}
	return 0;
}

tailscale sa, sb, sc;
char* tmpsa = NULL;
char* tmpsb = NULL;
char* tmpsc = NULL;

// ga_up starts a tsnet node with the shared control URL and state dir.
int ga_up(tailscale s, char* dir) {
	if (tailscale_set_control_url(s, control_url) != 0) {
		return set_err(s, 'u');
	}
	if (tailscale_set_dir(s, dir) != 0) {
		return set_err(s, 'v');
	}
	if (tailscale_set_logfd(s, -1) != 0) {
		return set_err(s, 'w');
	}
	if (tailscale_up(s) != 0) {
		return set_err(s, 'x');
	}
	return 0;
}

// ga_ip4 writes s's first (IPv4) tailnet address into buf as a
// NUL-terminated string.
int ga_ip4(tailscale s, char* buf, size_t buflen) {
	int ret = tailscale_getips(s, buf, buflen);
	if (ret != 0) {
		return ret;
	}
	char* comma = strchr(buf, ',');
	if (comma != NULL) {
		*comma = '\0';
	}
	return 0;
}

// test_getremoteaddr exercises the accept path under fd-number reuse:
// two client nodes alternate dialing a server node, each announcing
// its own tailnet IP on the connection, and the server checks that
// tailscale_getremoteaddr reports exactly the announced address for
// every accepted connection.
int test_getremoteaddr() {
	int ret;
	char msg[256];
	char ipbuf[128];

	if (err == NULL) {
		err = calloc(errlen, 1);
	}

	sa = tailscale_new();
	sb = tailscale_new();
	sc = tailscale_new();
	if ((ret = ga_up(sa, tmpsa)) != 0) return ret;
	if ((ret = ga_up(sb, tmpsb)) != 0) return ret;
	if ((ret = ga_up(sc, tmpsc)) != 0) return ret;

	char serverip[64];
	if ((ret = ga_ip4(sa, serverip, sizeof serverip)) != 0) {
		return set_err(sa, 'd');
	}
	char* ipb;
	char* ipc;
	if ((ret = ga_ip4(sb, ipbuf, sizeof ipbuf)) != 0) {
		return set_err(sb, 'e');
	}
	ipb = strdup(ipbuf);
	if ((ret = ga_ip4(sc, ipbuf, sizeof ipbuf)) != 0) {
		return set_err(sc, 'f');
	}
	ipc = strdup(ipbuf);

	char serveraddr[80];
	snprintf(serveraddr, sizeof serveraddr, "%s:8181", serverip);

	tailscale_listener ln;
	if ((ret = tailscale_listen(sa, "tcp", ":8181", &ln)) != 0) {
		return set_err(sa, 'g');
	}

	for (int i = 0; i < 200; i++) {
		tailscale client = (i % 2) ? sc : sb;
		char* ip = (i % 2) ? ipc : ipb;

		tailscale_conn w;
		if ((ret = tailscale_dial(client, "tcp", serveraddr, &w)) != 0) {
			msg[0] = '\0';
			tailscale_errmsg(client, msg, sizeof msg - 1);
			snprintf(err, errlen, "conn %d: dial: %s", i, msg);
			return 1;
		}

		size_t iplen = strlen(ip);
		if (write(w, ip, iplen) != (ssize_t)iplen) {
			snprintf(err, errlen, "conn %d: short write: errno %d (%s)", i, errno, strerror(errno));
			return 1;
		}

		tailscale_conn r;
		if ((ret = tailscale_accept(ln, &r)) != 0) {
			msg[0] = '\0';
			tailscale_errmsg(sa, msg, sizeof msg - 1);
			snprintf(err, errlen, "conn %d: accept: %s", i, msg);
			return 1;
		}

		char got[64] = {0};
		if ((ret = tailscale_getremoteaddr(ln, r, got, sizeof got)) != 0) {
			msg[0] = '\0';
			tailscale_errmsg(sa, msg, sizeof msg - 1);
			snprintf(err, errlen, "conn %d: getremoteaddr: %d (%s)", i, ret, msg);
			return 1;
		}

		char want[64] = {0};
		size_t off = 0;
		while (off < iplen) {
			ssize_t n = read(r, want + off, iplen - off);
			if (n <= 0) {
				snprintf(err, errlen, "conn %d: short read: %zd, errno %d (%s)", i, n, errno, strerror(errno));
				return 1;
			}
			off += n;
		}

		if (strcmp(got, want) != 0) {
			snprintf(err, errlen, "conn %d: getremoteaddr returned %s, want %s", i, got, want);
			return 1;
		}

		if (close(w) != 0 || close(r) != 0) {
			snprintf(err, errlen, "conn %d: close: errno %d (%s)", i, errno, strerror(errno));
			return 1;
		}
	}

	if ((ret = close(ln)) != 0) {
		snprintf(err, errlen, "close listener: errno %d (%s)", errno, strerror(errno));
		return 1;
	}

	free(ipb);
	free(ipc);

	if (tailscale_close(sc) != 0 || tailscale_close(sb) != 0 || tailscale_close(sa) != 0) {
		snprintf(err, errlen, "close nodes failed");
		return 1;
	}
	return 0;
}

// up_cancel_* test helpers: a server pointed at an unreachable control
// URL, so that tailscale_up blocks indefinitely (until canceled or timed
// out) without needing testcontrol.
int up_cancel_sd = 0;

int up_cancel_setup(const char* dir) {
	up_cancel_sd = tailscale_new();
	if (up_cancel_sd < 0) return 1;
	if (tailscale_set_control_url(up_cancel_sd, "http://127.0.0.1:1") != 0) return 2;
	if (tailscale_set_dir(up_cancel_sd, dir) != 0) return 3;
	if (tailscale_set_hostname(up_cancel_sd, "up-cancel-test") != 0) return 4;
	if (tailscale_set_ephemeral(up_cancel_sd, 1) != 0) return 5;
	if (tailscale_set_logfd(up_cancel_sd, -1) != 0) return 6;
	return 0;
}

int up_cancel_start() {
	return tailscale_up(up_cancel_sd);
}

int up_cancel_timeout(long long ms) {
	return tailscale_up_timeout(up_cancel_sd, ms);
}

// up_cancel_poll returns 0 once a pending up was found and canceled, or
// ENOENT if there is nothing pending yet. Lets tests poll for the up to
// have started without a TOCTOU race.
int up_cancel_poll() {
	return tailscale_cancel(up_cancel_sd);
}

int up_cancel_close() {
	return tailscale_close(up_cancel_sd);
}

int up_cancel_errmsg(char* buf, size_t len) {
	return tailscale_errmsg(up_cancel_sd, buf, len);}
*/
import "C"
import (
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"unsafe"

	"tailscale.com/net/netns"
	"tailscale.com/tstest/integration"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"
)

var verboseDERP = flag.Bool("verbose-derp", false, "if set, print DERP and STUN logs")

func RunTestConn(t *testing.T) {
	// Corp#4520: don't use netns for tests.
	netns.SetEnabled(false)
	t.Cleanup(func() {
		netns.SetEnabled(true)
	})

	derpLogf := logger.Discard
	if *verboseDERP {
		derpLogf = t.Logf
	}
	derpMap := integration.RunDERPAndSTUN(t, derpLogf, "127.0.0.1")
	control := &testcontrol.Server{
		DERPMap: derpMap,
	}
	control.HTTPTestServer = httptest.NewUnstartedServer(control)
	control.HTTPTestServer.Start()
	t.Cleanup(control.HTTPTestServer.Close)
	controlURL := control.HTTPTestServer.URL
	t.Logf("testcontrol listening on %s", controlURL)

	C.control_url = C.CString(controlURL)

	tmp := t.TempDir()
	tmps1 := filepath.Join(tmp, "s1")
	os.MkdirAll(tmps1, 0755)
	C.tmps1 = C.CString(tmps1)
	tmps2 := filepath.Join(tmp, "s2")
	os.MkdirAll(tmps2, 0755)
	C.tmps2 = C.CString(tmps2)

	if C.test_conn() != 0 {
		t.Fatal(C.GoString(C.err))
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	localAPIStatus := "http://" + C.GoString(C.addr) + "/localapi/v0/status"
	t.Logf("fetching local API status from %q", localAPIStatus)
	req, err := http.NewRequestWithContext(ctx, "GET", localAPIStatus, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Sec-Tailscale", "localapi")
	req.SetBasicAuth("", C.GoString(C.local_api_cred))
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	b, err := io.ReadAll(res.Body)
	res.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if res.StatusCode != 200 {
		t.Errorf("/status: %d: %s", res.StatusCode, b)
	}

	if C.close_conn() != 0 {
		t.Fatal(C.GoString(C.err))
	}
}

// RunTestGetRemoteAddr runs the C-side test_getremoteaddr.
func RunTestGetRemoteAddr(t *testing.T) {
	// Corp#4520: don't use netns for tests.
	netns.SetEnabled(false)
	t.Cleanup(func() {
		netns.SetEnabled(true)
	})

	derpLogf := logger.Discard
	if *verboseDERP {
		derpLogf = t.Logf
	}
	derpMap := integration.RunDERPAndSTUN(t, derpLogf, "127.0.0.1")
	control := &testcontrol.Server{
		DERPMap: derpMap,
	}
	control.HTTPTestServer = httptest.NewUnstartedServer(control)
	control.HTTPTestServer.Start()
	t.Cleanup(control.HTTPTestServer.Close)
	t.Logf("testcontrol listening on %s", control.HTTPTestServer.URL)

	C.control_url = C.CString(control.HTTPTestServer.URL)

	tmp := t.TempDir()
	for _, d := range []string{"ga", "gb", "gc"} {
		os.MkdirAll(filepath.Join(tmp, d), 0755)
	}
	C.tmpsa = C.CString(filepath.Join(tmp, "ga"))
	C.tmpsb = C.CString(filepath.Join(tmp, "gb"))
	C.tmpsc = C.CString(filepath.Join(tmp, "gc"))

	if C.test_getremoteaddr() != 0 {
		t.Fatal(C.GoString(C.err))
	}
}

// upCancelErrmsg fetches the last error message for the up_cancel test
// server as a Go string.
func upCancelErrmsg() string {
	buf := make([]byte, 512)
	if rv := C.up_cancel_errmsg((*C.char)(unsafe.Pointer(&buf[0])), C.size_t(len(buf))); rv != 0 {
		return fmt.Sprintf("errmsg failed: %d", rv)
	}
	return C.GoString((*C.char)(unsafe.Pointer(&buf[0])))
}

func upCancelSetup(t *testing.T) {
	t.Helper()
	dir := t.TempDir()
	if rv := C.up_cancel_setup(C.CString(dir)); rv != 0 {
		t.Fatalf("up_cancel_setup failed with setup code %d", rv)
	}
}

// RunTestUpTimeout tests that tailscale_up_timeout returns promptly with
// a deadline error, and that canceling after completion is a no-op.
func RunTestUpTimeout(t *testing.T) {
	upCancelSetup(t)

	start := time.Now()
	if rv := C.up_cancel_timeout(500); rv != -1 {
		t.Fatalf("tailscale_up_timeout = %d, want -1", rv)
	}
	if d := time.Since(start); d > 5*time.Second {
		t.Errorf("tailscale_up_timeout took %v; want it to respect the deadline", d)
	}
	if msg := upCancelErrmsg(); !strings.Contains(msg, "context deadline exceeded") {
		t.Errorf("errmsg = %q; want context deadline exceeded", msg)
	}

	// After the operation completed, canceling is a no-op (ENOENT).
	if rv := C.up_cancel_poll(); rv != C.ENOENT {
		t.Errorf("tailscale_cancel after completed up = %d, want ENOENT", rv)
	}

	if rv := C.up_cancel_close(); rv != 0 {
		t.Errorf("tailscale_close = %d, want 0", rv)
	}
}

// RunTestUpCancel tests that tailscale_cancel interrupts a pending
// tailscale_up, making it return promptly with a canceled error.
func RunTestUpCancel(t *testing.T) {
	upCancelSetup(t)

	done := make(chan int32, 1)
	go func() {
		done <- int32(C.up_cancel_start())
	}()

	// Poll until the up has registered itself as a cancelable operation;
	// ENOENT means it has not started yet.
	deadline := time.Now().Add(10 * time.Second)
	for {
		rv := C.up_cancel_poll()
		if rv == 0 {
			break
		}
		if rv != C.ENOENT {
			t.Fatalf("tailscale_cancel = %d, want 0 or ENOENT", rv)
		}
		select {
		case upRv := <-done:
			t.Fatalf("up returned %d before it could be canceled", upRv)
		default:
		}
		if time.Now().After(deadline) {
			t.Fatal("up never registered a pending operation")
		}
		time.Sleep(10 * time.Millisecond)
	}

	select {
	case rv := <-done:
		if rv != -1 {
			t.Errorf("canceled tailscale_up = %d, want -1", rv)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("tailscale_up did not return after tailscale_cancel")
	}
	if msg := upCancelErrmsg(); !strings.Contains(msg, "context canceled") {
		t.Errorf("errmsg = %q; want context canceled", msg)
	}

	if rv := C.up_cancel_close(); rv != 0 {
		t.Errorf("tailscale_close = %d, want 0", rv)
	}
}

// RunTestCloseCancelsUp tests that tailscale_close cancels a pending
// tailscale_up instead of leaving it blocked forever.
func RunTestCloseCancelsUp(t *testing.T) {
	upCancelSetup(t)

	done := make(chan int32, 1)
	go func() {
		done <- int32(C.up_cancel_start())
	}()

	// Give the up a moment to start, then close the server out from
	// under it. Even if close lands before the up registers, the closed
	// backend makes the up return anyway.
	time.Sleep(500 * time.Millisecond)
	if rv := C.up_cancel_close(); rv != 0 {
		t.Errorf("tailscale_close during pending up = %d, want 0", rv)
	}

	select {
	case rv := <-done:
		if rv != -1 {
			t.Errorf("tailscale_up after close = %d, want -1", rv)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("tailscale_up did not return after tailscale_close")
	}
}
