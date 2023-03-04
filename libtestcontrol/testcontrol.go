// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// A Go c-archive of the testcontrol package.
package main

import "C"
import (
	"net/http/httptest"
	"testing"

	"tailscale.com/net/netns"
	"tailscale.com/tstest/integration"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"
)

var control *testcontrol.Server

//export RunTestControl
func RunTestControl() *C.char {
	// Corp#4520: don't use netns for tests.
	netns.SetEnabled(false)

	t := new(testing.T)

	derpMap := integration.RunDERPAndSTUN(t, logger.Discard, "127.0.0.1")
	control = &testcontrol.Server{
		DERPMap: derpMap,
	}
	control.HTTPTestServer = httptest.NewUnstartedServer(control)
	control.HTTPTestServer.Start()
	controlURL := control.HTTPTestServer.URL
	return C.CString(controlURL)
}

//export CloseTestControl
func CloseTestControl() {
	control.HTTPTestServer.Close()
}

func main() {}
