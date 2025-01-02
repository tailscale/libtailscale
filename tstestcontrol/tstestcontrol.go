// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// A Go c-archive of tsnet integration/control test utilities
// This mirrors athe functionality in tstest without the depenency
// on go tests so it can be bundled as a static library and used to drive
// integration tests on other platforms
package main

import "C"

//#include "errno.h"
import (
	"context"
	"crypto/tls"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"unsafe"

	"tailscale.com/net/netaddr"
	"tailscale.com/net/netns"
	"tailscale.com/net/stun"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"

	"tailscale.com/derp"
	"tailscale.com/derp/derphttp"
	"tailscale.com/tailcfg"
	"tailscale.com/types/key"
	"tailscale.com/types/nettype"
)

func main() {}

//export StopControl
func StopControl() {
	netns.SetEnabled(true)
    if control != nil  {
        control.HTTPTestServer.Close()
    }
	cleanup()
	control = nil
}

var control *testcontrol.Server
var cleanup func()

// TODO(barnstar): by purging this of the go testing dependency, we lost some logging and things fail silently.
//                 that needs to be plumbed back in.

//export RunControl
func RunControl(buf *C.char, buflen C.size_t) C.int {
	if control != nil {
		return -1
	}

	if buf == nil {
		return -1
	} else if buflen == 0 {
		return -1
	}
	out := unsafe.Slice((*byte)(unsafe.Pointer(buf)), buflen)

	// Corp#4520: don't use netns for tests.
	netns.SetEnabled(false)

	derpLogf := logger.Discard
	derpMap, c, err := runDERPAndSTUN(derpLogf, "127.0.0.1")
	if err != nil {
		out[0] = '\x00'
		return -1
	}

	control := &testcontrol.Server{
		DERPMap: derpMap,
	}
	control.HTTPTestServer = httptest.NewUnstartedServer(control)
	control.HTTPTestServer.Start()
	controlURL := control.HTTPTestServer.URL
	cleanup = c

	n := copy(out, controlURL)
	out[n] = '\x00'

	return 0
}

// RunDERPAndSTUN runs a local DERP and STUN server for tests, returning the derpMap
// that clients should use. This creates resources that must be cleaned up with the
// returned cleanup function.
func runDERPAndSTUN(logf logger.Logf, ipAddress string) (derpMap *tailcfg.DERPMap, cleanup func(), err error) {
	d := derp.NewServer(key.NewNode(), logf)

	ln, err := net.Listen("tcp", net.JoinHostPort(ipAddress, "0"))
	if err != nil {
		return nil, nil, err
	}

	httpsrv := httptest.NewUnstartedServer(derphttp.Handler(d))
	httpsrv.Listener.Close()
	httpsrv.Listener = ln
	httpsrv.Config.ErrorLog = logger.StdLogger(logf)
	httpsrv.Config.TLSNextProto = make(map[string]func(*http.Server, *tls.Conn, http.Handler))
	httpsrv.StartTLS()

	stunAddr, stunCleanup, err := serveWithPacketListener(nettype.Std{})
	if err != nil {
		return nil, nil, err
	}

	m := &tailcfg.DERPMap{
		Regions: map[int]*tailcfg.DERPRegion{
			1: {
				RegionID:   1,
				RegionCode: "test",
				Nodes: []*tailcfg.DERPNode{
					{
						Name:             "t1",
						RegionID:         1,
						HostName:         ipAddress,
						IPv4:             ipAddress,
						IPv6:             "none",
						STUNPort:         stunAddr.Port,
						DERPPort:         httpsrv.Listener.Addr().(*net.TCPAddr).Port,
						InsecureForTests: true,
						STUNTestIP:       ipAddress,
					},
				},
			},
		},
	}

	logf("DERP httpsrv listener: %v", httpsrv.Listener.Addr())

	cleanupfn := func() {
		httpsrv.CloseClientConnections()
		httpsrv.Close()
		d.Close()
		stunCleanup()
		ln.Close()
	}

	return m, cleanupfn, nil
}

type stunStats struct {
	mu sync.Mutex
	// +checklocks:mu
	readIPv4 int
	// +checklocks:mu
	readIPv6 int
}

func serveWithPacketListener(ln nettype.PacketListener) (addr *net.UDPAddr, cleanupFn func(), err error) {
	// TODO(crawshaw): use stats to test re-STUN logic
	var stats stunStats

	pc, err := ln.ListenPacket(context.Background(), "udp4", ":0")
	if err != nil {
		return nil, nil, err
	}
	addr = pc.LocalAddr().(*net.UDPAddr)
	if len(addr.IP) == 0 || addr.IP.IsUnspecified() {
		addr.IP = net.ParseIP("127.0.0.1")
	}
	doneCh := make(chan struct{})
	go runSTUN(pc.(nettype.PacketConn), &stats, doneCh)
	return addr, func() {
		pc.Close()
		<-doneCh
	}, nil
}

func runSTUN(pc nettype.PacketConn, stats *stunStats, done chan<- struct{}) {
	defer close(done)

	var buf [64 << 10]byte
	for {
		n, src, err := pc.ReadFromUDPAddrPort(buf[:])
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			continue
		}
		src = netaddr.Unmap(src)
		pkt := buf[:n]
		if !stun.Is(pkt) {
			continue
		}
		txid, err := stun.ParseBindingRequest(pkt)
		if err != nil {
			continue
		}

		stats.mu.Lock()
		if src.Addr().Is4() {
			stats.readIPv4++
		} else {
			stats.readIPv6++
		}
		stats.mu.Unlock()

		res := stun.Response(txid, src)
		if _, err := pc.WriteToUDPAddrPort(res, src); err != nil {
			// TODO(barnstar): inject logging from C
		}
	}
}
