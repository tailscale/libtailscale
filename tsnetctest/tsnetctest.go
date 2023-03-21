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
*/
import "C"
import (
	"context"
	"flag"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

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
