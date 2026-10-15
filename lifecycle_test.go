// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

package main

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"

	"tailscale.com/types/logger"
)

// Run the real-server cases in subprocesses: even a broken Close must not leave
// a blocked Up or a partially initialized tsnet server in the test process.
func TestClosePendingUp(t *testing.T) {
	if mode := os.Getenv("LIBTAILSCALE_UP_CHILD"); mode != "" {
		testClosePendingUp(t, mode)
		return
	}
	for _, mode := range []string{"explicit", "implicit", "multiple"} {
		t.Run(mode, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestClosePendingUp$", "-test.v", "-test.timeout=40s", "-test.cpu="+strconv.Itoa(runtime.GOMAXPROCS(0)))
			cmd.Env = lifecycleEnv()
			cmd.Env = append(cmd.Env, "LIBTAILSCALE_UP_CHILD="+mode, "LIBTAILSCALE_STATE="+t.TempDir())
			out, err := cmd.CombinedOutput() // CommandContext kills and Wait reaps on timeout.
			t.Logf("child output:\n%s", out)
			if err != nil {
				t.Fatalf("child: %v (deadline: %v)", err, ctx.Err())
			}
		})
	}
}

func lifecycleEnv() []string {
	var env []string
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		upper := strings.ToUpper(key)
		if strings.HasPrefix(upper, "TS_") || strings.HasPrefix(upper, "TSNET_") || strings.HasPrefix(upper, "TAILSCALE_") || strings.HasPrefix(upper, "LIBTAILSCALE_") || strings.HasSuffix(upper, "_PROXY") {
			continue
		}
		env = append(env, entry)
	}
	return append(env, "TS_NO_LOGS_NO_SUPPORT=true")
}

func testClosePendingUp(t *testing.T, mode string) {
	release := make(chan struct{})
	control := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-release:
		case <-r.Context().Done():
		}
	}))
	defer control.Close()
	defer close(release) // Independent of the implementation of TsnetClose.
	sd := TsnetNewServer()
	servers.mu.Lock()
	s := servers.m[sd] // Configure before any operation starts.
	servers.mu.Unlock()
	s.s.Dir = os.Getenv("LIBTAILSCALE_STATE")
	s.s.Hostname = "close-pending-up"
	s.s.ControlURL = control.URL
	s.s.Logf = logger.Discard
	if mode == "explicit" {
		if rc := TsnetStart(sd); rc != 0 {
			t.Fatalf("Start = %d", rc)
		}
		t.Log("STAGE: explicit Start succeeded")
	}
	n := 1
	if mode == "multiple" {
		n = 3
	}
	upDone := make(chan int, n)
	for range n {
		go func() { upDone <- int(TsnetUp(sd)) }()
	}
	// Observe the actual Go-side bridge calls inside Next's blocking read. The
	// control endpoint alone is insufficient evidence: Start also contacts it.
	stacks := awaitStacks(t, n, ".TsnetUp(", "(*IPNBusWatcher).Next(", "encoding/json.(*Decoder).refill(")
	t.Logf("STAGE: %d Up calls in watcher read, still pending\n%s", n, stacks)
	select {
	case rc := <-upDone:
		t.Fatalf("Up completed before Close: %d", rc)
	default:
	}
	closeDone := make(chan int, 1)
	go func() { closeDone <- int(TsnetClose(sd)) }()
	if rc := awaitResult(t, closeDone, "Close"); rc != 0 {
		t.Fatalf("Close = %d", rc)
	}
	t.Log("STAGE: Close returned 0")
	for range n {
		if rc := awaitResult(t, upDone, "Up"); rc != -1 {
			t.Fatalf("Up = %d, want -1 for control that can never reach Running", rc)
		}
		t.Log("STAGE: Up returned -1")
	}
	// Cancellation alone is not enough: implicit Up must also have recorded
	// successful initialization so that Close tears down the native server.
	// The observed watcher proves initialization finished, making this safe.
	if err := s.s.Close(); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("Close left the underlying server open: %v", err)
	}
	t.Log("STAGE: underlying server confirmed closed")
}

func goroutineStacks() string {
	buf := make([]byte, 2<<20)
	n := runtime.Stack(buf, true)
	return string(buf[:n])
}

func awaitStacks(t *testing.T, count int, frames ...string) string {
	t.Helper()
	deadline := time.NewTimer(10 * time.Second)
	defer deadline.Stop()
	tick := time.NewTicker(time.Millisecond)
	defer tick.Stop()
	for {
		var found []string
		for _, stack := range strings.Split(goroutineStacks(), "\n\n") {
			match := true
			for _, frame := range frames {
				match = match && strings.Contains(stack, frame)
			}
			if match {
				found = append(found, stack)
			}
		}
		if len(found) == count {
			return strings.Join(found, "\n\n")
		}
		select {
		case <-deadline.C:
			t.Fatalf("precondition: did not observe %d stacks with %v\n%s", count, frames, goroutineStacks())
		case <-tick.C:
		}
	}
}

func awaitResult(t *testing.T, done <-chan int, stage string) int {
	t.Helper()
	select {
	case rc := <-done:
		return rc
	case <-time.After(10 * time.Second):
		t.Fatalf("STAGE: %s did not complete\n%s", stage, goroutineStacks())
		return 0
	}
}
