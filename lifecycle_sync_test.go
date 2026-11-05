// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/tailscale/libtailscale/tsnetctest"
	"tailscale.com/types/logger"
)

func TestCloseNew(t *testing.T) {
	sd := TsnetNewServer()
	done := make(chan int, 1)
	go func() { done <- int(TsnetClose(sd)) }()
	if rc := awaitResult(t, done, "Close new server"); rc != 0 {
		t.Fatalf("Close = %d", rc)
	}
	if rc := TsnetClose(sd); int(rc) != int(syscall.EBADF) {
		t.Fatalf("second Close = %d", rc)
	}
}

func TestCloseOperationBoundary(t *testing.T) {
	sd := TsnetNewServer()
	s := acquireServer(sd)
	// Two operations registered before deletion must both be drained.
	second := acquireServer(sd)
	var release sync.Once
	defer release.Do(func() { s.ops.Done(); second.ops.Done() })
	done := make(chan int, 1)
	go func() { done <- int(TsnetClose(sd)) }()
	awaitCanceled(t, s.ctx)
	if late := acquireServer(sd); late != nil {
		late.ops.Done()
		t.Fatal("operation registered after cancellation and handle removal")
	}
	if rc := TsnetStart(sd); int(rc) != int(syscall.EBADF) {
		t.Fatalf("Start after deletion = %d", rc)
	}
	awaitStacks(t, 1, ".TsnetClose(", "sync.(*WaitGroup).Wait(")
	// A waiting Close must not hold the registry lock and stall another node.
	other := TsnetNewServer()
	otherDone := make(chan int, 1)
	go func() { otherDone <- int(TsnetClose(other)) }()
	if rc := awaitResult(t, otherDone, "other Close"); rc != 0 {
		t.Fatalf("other Close = %d", rc)
	}
	release.Do(func() { s.ops.Done(); second.ops.Done() })
	if rc := awaitResult(t, done, "drained Close"); rc != 0 {
		t.Fatalf("Close = %d", rc)
	}
}

func TestConcurrentClose(t *testing.T) {
	sd := TsnetNewServer()
	s := acquireServer(sd)
	var release sync.Once
	defer release.Do(s.ops.Done)
	const callers = 8
	done := make(chan int, callers)
	for range callers {
		go func() { done <- int(TsnetClose(sd)) }()
	}
	awaitCanceled(t, s.ctx)
	// The winner is held by our operation. Every loser must already see EBADF.
	for range callers - 1 {
		if rc := awaitResult(t, done, "losing Close"); rc != int(syscall.EBADF) {
			t.Fatalf("losing Close = %d", rc)
		}
	}
	awaitStacks(t, 1, ".TsnetClose(", "sync.(*WaitGroup).Wait(")
	release.Do(s.ops.Done)
	if rc := awaitResult(t, done, "winning Close"); rc != 0 {
		t.Fatalf("winning Close = %d", rc)
	}
}

func TestLastErrorConcurrent(t *testing.T) {
	sd := TsnetNewServer()
	s := acquireServer(sd)
	defer func() { s.ops.Done(); TsnetClose(sd) }()
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			for range 100 {
				if i%2 == 0 {
					s.recErr(errors.New("shared last error"))
					s.recErr(nil)
				} else {
					rc, buf := tsnetctest.Errmsg(int32(sd), 4)
					if (rc != 0 && rc != int(syscall.ERANGE)) || !bytes.Contains(buf, []byte{0}) {
						t.Errorf("Errmsg = %d, %q", rc, buf)
						return
					}
				}
			}
		}()
	}
	close(start)
	wg.Wait()
	s.recErr(errors.New("shared last error"))
	for _, size := range []int{1, 4, 64} {
		rc, buf := tsnetctest.Errmsg(int32(sd), size)
		want := 0
		if size < len("shared last error")+1 {
			want = int(syscall.ERANGE)
		}
		if rc != want || !bytes.Contains(buf, []byte{0}) {
			t.Fatalf("Errmsg(%d) = %d, %q", size, rc, buf)
		}
	}
	closed := TsnetNewServer()
	TsnetClose(closed)
	for _, size := range []int{1, 16} {
		rc, buf := tsnetctest.Errmsg(int32(closed), size)
		if rc != int(syscall.EBADF) || buf[0] != 0 {
			t.Fatalf("Errmsg after close = %d, %q", rc, buf)
		}
	}
}

func awaitCanceled(t *testing.T, ctx context.Context) {
	t.Helper()
	select {
	case <-ctx.Done():
	case <-time.After(10 * time.Second):
		t.Fatal("Close did not cancel the lifetime context")
	}
}

func TestLifecycleInitialization(t *testing.T) {
	if mode := os.Getenv("LIBTAILSCALE_INIT_CHILD"); mode != "" {
		testLifecycleInitialization(t, mode)
		return
	}
	for _, mode := range []string{"failure-Start", "failure-Up", "failure-Dial", "failure-Listen", "failure-Loopback", "failure-StatusJSON", "failure-Funnel", "initializing", "initializing-Up", "concurrent-close", "Dial", "Listen", "Listen-reconfigure", "Loopback", "StatusJSON", "pending-StatusJSON", "pending-Funnel"} {
		t.Run(mode, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestLifecycleInitialization$", "-test.v", "-test.timeout=40s", "-test.cpu="+strconv.Itoa(runtime.GOMAXPROCS(0)))
			cmd.Env = append(lifecycleEnv(), "LIBTAILSCALE_INIT_CHILD="+mode, "LIBTAILSCALE_STATE="+t.TempDir())
			out, err := cmd.CombinedOutput()
			t.Logf("child output:\n%s", out)
			if err != nil {
				t.Fatalf("child: %v (deadline: %v)", err, ctx.Err())
			}
		})
	}
}

func testLifecycleInitialization(t *testing.T, mode string) {
	releaseControl := make(chan struct{})
	control := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-releaseControl:
		case <-r.Context().Done():
		}
	}))
	defer control.Close()
	defer close(releaseControl)
	sd := TsnetNewServer()
	s := acquireServer(sd)
	s.s.Dir = os.Getenv("LIBTAILSCALE_STATE")
	s.s.Hostname = "lifecycle-init"
	s.s.ControlURL = control.URL
	s.s.Logf = logger.Discard
	s.s.UserLogf = logger.Discard
	s.ops.Done() // All configuration is complete before starting operations.

	entry := strings.TrimPrefix(strings.TrimPrefix(mode, "failure-"), "pending-")
	call := func() int {
		switch entry {
		case "Start":
			return int(TsnetStart(sd))
		case "Up":
			return int(TsnetUp(sd))
		case "Dial":
			rc, fd := tsnetctest.Dial(int32(sd), "tcp", "100.64.0.1:80")
			if fd >= 0 {
				syscall.Close(fd)
			}
			return rc
		case "Listen":
			rc, fd := tsnetctest.Listen(int32(sd), "tcp", ":8081")
			if fd >= 0 {
				syscall.Close(fd)
			}
			return rc
		case "Loopback":
			rc, _, _, _ := tsnetctest.Loopback(int32(sd))
			return rc
		case "StatusJSON":
			rc, _ := tsnetctest.StatusJSON(int32(sd))
			return rc
		case "Funnel":
			return int(TsnetEnableFunnelToLocalhostPlaintextHttp1(sd, 8080))
		}
		panic("unknown entry: " + entry)
	}
	closeDone := make(chan int, 1)
	startClose := func() { go func() { closeDone <- int(TsnetClose(sd)) }() }
	if strings.HasPrefix(mode, "failure-") {
		badDir := filepath.Join(s.s.Dir, "file")
		if err := os.WriteFile(badDir, nil, 0600); err != nil {
			t.Fatal(err)
		}
		s.s.Dir = badDir
		for range 2 {
			if rc := call(); rc != -1 {
				t.Fatalf("%s = %d, want initialization error", entry, rc)
			}
		}
		if s.started || s.startErr == nil {
			t.Fatal("failed initialization recorded as successful")
		}
		if entry == "Up" {
			rc, msg := tsnetctest.Errmsg(int32(sd), 1024)
			if rc != 0 || !bytes.HasPrefix(msg, []byte("tsnet.Up: ")) {
				t.Fatalf("Up initialization error lost its prefix: %d, %q", rc, msg)
			}
		}
		startClose()
		if rc := awaitResult(t, closeDone, "Close failed initialization"); rc != 0 {
			t.Fatalf("Close = %d", rc)
		}
		return
	}

	switch mode {
	case "Listen-reconfigure":
		stateDir := s.s.Dir
		badDir := filepath.Join(stateDir, "file")
		if err := os.WriteFile(badDir, nil, 0600); err != nil {
			t.Fatal(err)
		}
		s.s.Dir = badDir
		rc, fd := tsnetctest.Listen(int32(sd), "invalid-network", ":8081")
		if fd >= 0 {
			syscall.Close(fd)
		}
		if rc != -1 {
			t.Fatalf("invalid Listen = %d", rc)
		}
		// Invalid arguments did not initialize the node. Configuration is still
		// permitted; a failed early Start would have poisoned both sync.Once's.
		s.s.Dir = stateDir
		if rc := TsnetStart(sd); rc != 0 {
			t.Fatalf("invalid Listen consumed initialization: subsequent Start = %d", rc)
		}
		startClose()
	case "concurrent-close":
		if rc := TsnetStart(sd); rc != 0 {
			t.Fatalf("Start = %d", rc)
		}
		hold := acquireServer(sd)
		var release sync.Once
		defer release.Do(hold.ops.Done)
		losers := make(chan int, 8)
		for range 8 {
			go func() { losers <- int(TsnetClose(sd)) }()
		}
		awaitCanceled(t, s.ctx)
		for range 7 {
			if rc := awaitResult(t, losers, "losing initialized Close"); rc != int(syscall.EBADF) {
				t.Fatalf("losing Close = %d", rc)
			}
		}
		awaitStacks(t, 1, ".TsnetClose(", "sync.(*WaitGroup).Wait(")
		release.Do(hold.ops.Done)
		closeDone <- awaitResult(t, losers, "winning initialized Close")
	case "pending-StatusJSON", "pending-Funnel":
		if rc := TsnetStart(sd); rc != 0 {
			t.Fatalf("Start = %d", rc)
		}
		lc, err := s.s.LocalClient()
		if err != nil {
			t.Fatal(err)
		}
		entered, release := make(chan context.Context, 1), make(chan struct{})
		defer close(release)
		transport := &http.Transport{DialContext: lc.Dial}
		defer transport.CloseIdleConnections()
		// Set Transport before the first LocalClient request. Gate admission to
		// the real in-memory transport, preserving its behavior once released.
		lc.Transport = &cancelGateTransport{transport, entered, release}
		done := make(chan int, 1)
		callStart := time.Now()
		go func() { done <- call() }()
		var requestCtx context.Context
		select {
		case requestCtx = <-entered:
		case <-time.After(10 * time.Second):
			t.Fatal("LocalAPI request did not reach transport")
		}
		if mode == "pending-StatusJSON" {
			// Context creation happened between callStart and this observation.
			// Check the existing timeout without assuming scheduling latency.
			deadline, ok := requestCtx.Deadline()
			if !ok || deadline.Before(callStart.Add(10*time.Second)) || deadline.After(time.Now().Add(10*time.Second)) {
				t.Fatalf("StatusJSON did not retain its 10s timeout: deadline=%v, present=%v", deadline, ok)
			}
		}
		startClose()
		if rc := awaitResult(t, done, "pending LocalAPI call"); rc != -1 {
			t.Fatalf("%s = %d", entry, rc)
		}
		if err := requestCtx.Err(); !errors.Is(err, context.Canceled) {
			t.Fatalf("LocalAPI request was not canceled by Close: %v", err)
		}
	case "initializing", "initializing-Up":
		entered, release := make(chan struct{}), make(chan struct{})
		var once, releaseOnce sync.Once
		defer releaseOnce.Do(func() { close(release) })
		// UserLogf is called synchronously by tsnet.start, before it completes.
		s.s.UserLogf = func(string, ...any) { once.Do(func() { close(entered); <-release }) }
		startDone := make(chan int, 1)
		go func() {
			if mode == "initializing-Up" {
				startDone <- int(TsnetUp(sd))
			} else {
				startDone <- int(TsnetStart(sd))
			}
		}()
		select {
		case <-entered:
		case <-time.After(10 * time.Second):
			t.Fatal("initialization barrier not reached")
		}
		queued := make(chan int, 2)
		if mode == "initializing-Up" {
			for range 2 {
				go func() { queued <- int(TsnetUp(sd)) }()
			}
			awaitStacks(t, 2, ".TsnetUp(", "(*server).start(", "sync.(*Mutex).Lock(")
		}
		startClose()
		awaitCanceled(t, s.ctx)
		awaitStacks(t, 1, ".TsnetClose(", "sync.(*WaitGroup).Wait(")
		t.Log("STAGE: initialization held; cancellation delivered; Close waiting for operation")
		releaseOnce.Do(func() { close(release) })
		want := 0
		if mode == "initializing-Up" {
			want = -1
		}
		if rc := awaitResult(t, startDone, "initializing operation after barrier"); rc != want {
			t.Fatalf("initializing operation = %d, want %d", rc, want)
		}
		if mode == "initializing-Up" {
			for range 2 {
				if rc := awaitResult(t, queued, "Up queued on initialization"); rc != -1 {
					t.Fatalf("queued Up = %d", rc)
				}
			}
		}
	case "Dial":
		done := make(chan int, 1)
		go func() { done <- call() }()
		awaitStacks(t, 1, ".TsnetDial(", "(*Server).awaitRunning(", "(*LocalBackend).WatchNotificationsAs(")
		startClose()
		if rc := awaitResult(t, done, "pending Dial"); rc != -1 {
			t.Fatalf("Dial = %d", rc)
		}
	case "Listen":
		rc, fd := tsnetctest.Listen(int32(sd), "tcp", ":8081")
		if rc != 0 {
			t.Fatalf("implicit Listen = %d", rc)
		}
		defer syscall.Close(fd)
		// A failure after successful initialization must not erase its result.
		rc, duplicate := tsnetctest.Listen(int32(sd), "tcp", ":8081")
		if duplicate >= 0 {
			syscall.Close(duplicate)
		}
		if rc != -1 {
			t.Fatalf("duplicate Listen = %d", rc)
		}
		for _, args := range [][2]string{{"", ":8082"}, {"tcp", ":http"}, {"tcp6", "[::]:8083"}} {
			rc, fd := tsnetctest.Listen(int32(sd), args[0], args[1])
			if rc != 0 {
				t.Fatalf("Listen(%q, %q) = %d", args[0], args[1], rc)
			}
			defer syscall.Close(fd)
		}
		startClose()
	case "Loopback":
		rc, addr, proxy, local := tsnetctest.Loopback(int32(sd))
		if rc != 0 || addr == "" || len(proxy) != 32 || len(local) != 32 {
			t.Fatalf("Loopback result invalid: rc=%d", rc)
		}
		startClose()
	case "StatusJSON":
		rc, body := tsnetctest.StatusJSON(int32(sd))
		var status struct{ BackendState string }
		if rc != 0 || json.Unmarshal([]byte(body), &status) != nil || status.BackendState == "" || status.BackendState == "Running" {
			t.Fatalf("StatusJSON = %d, %s", rc, body)
		}
		startClose()
	}
	if rc := awaitResult(t, closeDone, "Close initialized server"); rc != 0 {
		t.Fatalf("Close = %d", rc)
	}
	// After the bridge has drained and closed, a second underlying close must
	// report already-closed. This detects missed implicit initialization.
	if !s.started {
		t.Fatal("successful initialization not recorded")
	}
	if err := s.s.Close(); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("underlying server was not closed: %v", err)
	}
}

type cancelGateTransport struct {
	base    http.RoundTripper
	entered chan context.Context
	release <-chan struct{}
}

func (tr *cancelGateTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	tr.entered <- req.Context()
	select {
	case <-req.Context().Done():
	case <-tr.release:
	}
	return tr.base.RoundTrip(req)
}
