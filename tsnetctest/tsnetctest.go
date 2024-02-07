// Package tsnetctest tests the libtailscale C bindings.
//
// It is used by tailscale_test.go, because you are not allowed to
// use the 'import "C"' directive in tests.
package tsnetctest

//#include "tsnetctest.h"
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
	"testing"
	"time"

	"tailscale.com/net/netns"
	"tailscale.com/tstest/integration"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"
)

var verboseDERP = flag.Bool("verbose-derp", false, "if set, print DERP and STUN logs")

func RunTestConn(t *testing.T) {
	fmt.Println("Start Test connection")
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
	fmt.Println("testcontrol listening on", controlURL)
	t.Logf("testcontrol listening on %s", controlURL)

	C.control_url = C.CString(controlURL)

	tmp := t.TempDir()
	tmps1 := filepath.Join(tmp, "s1")
	os.MkdirAll(tmps1, 0755)
	C.tmps1 = C.CString(tmps1)
	tmps2 := filepath.Join(tmp, "s2")
	os.MkdirAll(tmps2, 0755)
	C.tmps2 = C.CString(tmps2)
	fmt.Println("")
	if C.test_conn() != 0 {
		fmt.Println("Error", C.err)
		t.Fatal(C.GoString(C.err))
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	localAPIStatus := "http://" + C.GoString(C.addr) + "/localapi/v0/status"
	t.Logf("fetching local API status from %q", localAPIStatus)
	req, err := http.NewRequestWithContext(ctx, "GET", localAPIStatus, nil)
	if err != nil {
		fmt.Println("Error2", err)
		t.Fatal(err)
	}
	req.Header.Set("Sec-Tailscale", "localapi")
	req.SetBasicAuth("", C.GoString(C.local_api_cred))
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Println("Error3", err)
		t.Fatal(err)
	}
	b, err := io.ReadAll(res.Body)
	res.Body.Close()
	if err != nil {
		fmt.Println("Error4", err)
		t.Fatal(err)
	}
	if res.StatusCode != 200 {
		fmt.Println("Status code issue", res.StatusCode)
		t.Errorf("/status: %d: %s", res.StatusCode, b)
	}
	fmt.Println("Close connection")
	if C.close_conn() != 0 {
		t.Fatal(C.GoString(C.err))
	}
}
