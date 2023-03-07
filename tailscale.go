// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// A Go c-archive of the tsnet package. See tailscale.h for details.
package main

//#include "errno.h"
import "C"

import (
	"context"
	"fmt"
	"net"
	"os"
	"sync"
	"syscall"
	"unsafe"

	"tailscale.com/hostinfo"
	"tailscale.com/tsnet"
	"tailscale.com/types/logger"
)

func main() {}

// servers tracks all the allocated *tsnet.Server objects.
var servers struct {
	mu   sync.Mutex
	next C.int
	m    map[C.int]*server
}

type server struct {
	s       *tsnet.Server
	lastErr string
}

func getServer(sd C.int) (*server, error) {
	servers.mu.Lock()
	defer servers.mu.Unlock()

	s := servers.m[sd]
	if s == nil {
		return nil, fmt.Errorf("tsnetc: unknown server descriptors %d (of %d servers)", sd, len(servers.m))
	}
	return s, nil
}

// listeners tracks all the tsnet_listener objects allocated via tsnet_listen.
var listeners struct {
	mu   sync.Mutex
	next C.int
	m    map[C.int]*listener
}

type listener struct {
	s  *server
	ln net.Listener
}

// conns tracks all the pipe(2)s allocated via tsnet_dial.
var conns struct {
	mu sync.Mutex
	m  map[C.int]*conn // keyed by the FD given to C (w)
}

type conn struct {
	s *tsnet.Server
	c net.Conn
	r *os.File // r is the local socket to the C client
}

func (s *server) recErr(err error) C.int {
	if err == nil {
		s.lastErr = ""
		return 0
	}
	s.lastErr = err.Error()
	return -1
}

//export TsnetNewServer
func TsnetNewServer() C.int {
	servers.mu.Lock()
	defer servers.mu.Unlock()

	if servers.m == nil {
		servers.m = map[C.int]*server{}
		hostinfo.SetApp("libtailscale")
	}
	if servers.next == 0 {
		servers.next = 42<<16 + 1
	}
	sd := servers.next
	servers.next++
	s := &server{s: &tsnet.Server{}}
	servers.m[sd] = s
	return (C.int)(sd)
}

//export TsnetStart
func TsnetStart(sd C.int) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	return s.recErr(s.s.Start())
}

//export TsnetUp
func TsnetUp(sd C.int) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	_, err = s.s.Up(context.Background()) // cancellation is via TsnetClose
	return s.recErr(err)
}

//export TsnetClose
func TsnetClose(sd C.int) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}

	servers.mu.Lock()
	delete(servers.m, sd)
	servers.mu.Unlock()

	// TODO: cancel Up
	// TODO: close related listeners / conns.
	if err := s.s.Close(); err != nil {
		return -1
	}

	return 0
}

//export TsnetErrmsg
func TsnetErrmsg(sd C.int, buf *C.char, buflen C.size_t) C.int {
	if buf == nil {
		panic("errmsg passed nil buf")
	} else if buflen == 0 {
		panic("errmsg passed buflen of 0")
	}

	servers.mu.Lock()
	s := servers.m[sd]
	servers.mu.Unlock()

	out := unsafe.Slice((*byte)(unsafe.Pointer(buf)), buflen)
	if s == nil {
		out[0] = '\x00'
		return C.EBADF
	}
	n := copy(out, s.lastErr)
	if len(out) < len(s.lastErr)-1 {
		out[len(out)-1] = '\x00' // always NUL-terminate
		return C.ERANGE
	}
	out[n] = '\x00'
	return 0
}

//export TsnetListen
func TsnetListen(sd C.int, network, addr *C.char, listenerOut *C.int) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}

	ln, err := s.s.Listen(C.GoString(network), C.GoString(addr))
	if err != nil {
		return s.recErr(err)
	}

	listeners.mu.Lock()
	if listeners.next == 0 {
		// Arbitrary magic number that will hopefully help someone
		// debug some type confusion one day.
		listeners.next = 37<<16 + 1
	}
	if listeners.m == nil {
		listeners.m = map[C.int]*listener{}
	}
	ld := listeners.next
	listeners.next++
	listeners.m[ld] = &listener{s: s, ln: ln}
	listeners.mu.Unlock()

	*listenerOut = ld
	return 0
}

//export TsnetListenerClose
func TsnetListenerClose(ld C.int) C.int {
	listeners.mu.Lock()
	defer listeners.mu.Unlock()

	l := listeners.m[ld]
	err := l.ln.Close()
	delete(listeners.m, ld)

	if err != nil {
		return l.s.recErr(err)
	}
	return 0
}

func newConn(s *server, netConn net.Conn, connOut *C.int) C.int {
	fds, err := syscall.Socketpair(syscall.AF_LOCAL, syscall.SOCK_STREAM, 0)
	if err != nil {
		return s.recErr(err)
	}
	r := os.NewFile(uintptr(fds[1]), "socketpair-r")
	c := &conn{s: s.s, c: netConn, r: r}
	fdC := C.int(fds[0])

	conns.mu.Lock()
	if conns.m == nil {
		conns.m = make(map[C.int]*conn)
	}
	conns.m[fdC] = c
	conns.mu.Unlock()

	connCleanup := func() {
		r.Close()

		conns.mu.Lock()
		delete(conns.m, fdC)
		conns.mu.Unlock()
	}
	go func() {
		defer connCleanup()
		var b [1 << 16]byte
		for {
			n, err := netConn.Read(b[:])
			if err != nil {
				return
			}
			if _, err := r.Write(b[:n]); err != nil {
				return
			}
		}
	}()
	go func() {
		defer connCleanup()
		var b [1 << 16]byte
		for {
			n, err := r.Read(b[:])
			if err != nil {
				return
			}
			if _, err := netConn.Write(b[:n]); err != nil {
				return
			}
		}
	}()

	*connOut = fdC
	return 0
}

//export TsnetAccept
func TsnetAccept(ld C.int, connOut *C.int) C.int {
	listeners.mu.Lock()
	l := listeners.m[ld]
	listeners.mu.Unlock()

	if l == nil {
		return C.EBADF
	}

	netConn, err := l.ln.Accept()
	if err != nil {
		return l.s.recErr(err)
	}
	return newConn(l.s, netConn, connOut)
}

//export TsnetDial
func TsnetDial(sd C.int, network, addr *C.char, connOut *C.int) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	netConn, err := s.s.Dial(context.Background(), C.GoString(network), C.GoString(addr))
	if err != nil {
		return s.recErr(err)
	}
	return newConn(s, netConn, connOut)
}

//export TsnetSetDir
func TsnetSetDir(sd C.int, str *C.char) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	s.s.Dir = C.GoString(str)
	return 0
}

//export TsnetSetHostname
func TsnetSetHostname(sd C.int, str *C.char) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	s.s.Hostname = C.GoString(str)
	return 0
}

//export TsnetSetAuthKey
func TsnetSetAuthKey(sd C.int, str *C.char) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	s.s.AuthKey = C.GoString(str)
	return 0
}

//export TsnetSetControlURL
func TsnetSetControlURL(sd C.int, str *C.char) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	s.s.ControlURL = C.GoString(str)
	return 0
}

//export TsnetSetEphemeral
func TsnetSetEphemeral(sd C.int, e int) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	if e == 0 {
		s.s.Ephemeral = false
	} else {
		s.s.Ephemeral = true
	}
	return 0
}

//export TsnetSetLogFD
func TsnetSetLogFD(sd, fd C.int) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	if fd == -1 {
		s.s.Logf = logger.Discard
		return 0
	}
	f := os.NewFile(uintptr(fd), "logfd")
	s.s.Logf = func(format string, args ...any) {
		fmt.Fprintf(f, format, args...)
	}
	return 0
}

//export TsnetLoopback
func TsnetLoopback(sd C.int, addrOut *C.char, addrLen C.size_t, proxyOut *C.char, localOut *C.char) C.int {
	// Panic here to ensure we always leave the out values NUL-terminated.
	if addrOut == nil {
		panic("loopback_api passed nil addr_out")
	} else if addrLen == 0 {
		panic("loopback_api passed addrlen of 0")
	}

	// Start out NUL-termianted to cover error conditions.
	*addrOut = '\x00'
	*localOut = '\x00'
	*proxyOut = '\x00'

	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	addr, proxyCred, localAPICred, err := s.s.Loopback()
	if err != nil {
		return s.recErr(err)
	}
	if len(proxyCred) != 32 {
		return s.recErr(fmt.Errorf("libtailscale: len(proxyCred)=%d, want 32", len(proxyCred)))
	}
	if len(localAPICred) != 32 {
		return s.recErr(fmt.Errorf("libtailscale: len(localAPICred)=%d, want 32", len(localAPICred)))
	}
	if len(addr)+1 > int(addrLen) {
		return s.recErr(fmt.Errorf("libtailscale: loopback addr of %d bytes is too long for addrlen %d", len(addr), addrLen))
	}
	out := unsafe.Slice((*byte)(unsafe.Pointer(addrOut)), addrLen)
	n := copy(out, addr)
	out[n] = '\x00'

	// proxyOut and localOut are non-nil and 33 bytes long because
	// they are defined in C as char cred_out[static 33].
	out = unsafe.Slice((*byte)(unsafe.Pointer(proxyOut)), 33)
	copy(out, proxyCred)
	out[32] = '\x00'
	out = unsafe.Slice((*byte)(unsafe.Pointer(localOut)), 33)
	copy(out, localAPICred)
	out[32] = '\x00'

	return 0
}
