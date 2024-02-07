// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// A Go c-archive of the tsnet package. See tailscale.h for details.
package main

//#include "errno.h"
//#include "socketpair_handler.h"
//#include "tailscale.h"
import "C"

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"syscall"
	"unsafe"

	"github.com/tailscale/libtailscale/platform"

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
	mu sync.Mutex
	m  map[C.int]*listener
}

type listener struct {
	s  *server
	ln net.Listener
	fd C.SOCKET // go side fd of socketpair sent to C
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

//export TsnetAccept
func TsnetAccept(sd C.int, connOut *C.int) C.int {
	return C.tailscale_accept(sd, connOut)
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
	fmt.Println("CLOSING TSNET")
	servers.mu.Lock()
	s := servers.m[sd]
	if s != nil {
		delete(servers.m, sd)
	}
	servers.mu.Unlock()

	if s == nil {
		return C.EBADF
	}

	// TODO: cancel Up
	// TODO: close related listeners / conns.
	if err := s.s.Close(); err != nil {
		s.s.Logf("tailscale_close: failed with %v", err)
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
	fmt.Println("start listening, ", network, addr)
	s, err := getServer(sd)
	if err != nil {
		fmt.Println("error No server")
		return s.recErr(err)
	}

	ln, err := s.s.Listen(C.GoString(network), C.GoString(addr))
	if err != nil {
		fmt.Println("error somewhere in the listening - ", err)
		return s.recErr(err)
	}
	// The tailscale_listener we return to C is one side of a socketpair(2).
	// We do this so we can proactively call ln.Accept in a goroutine and
	// feed an fd for the connection through the listener. This lets C use
	// epoll on the tailscale_listener to know if it should call
	// tailscale_accept, which avoids a blocking call on the far side.
	fds, fdPt, err := platform.GetSocketPair()

	if err != nil {
		fmt.Println("error in getting socketpair")
		return s.recErr(err)
	}

	sp := fds[1]
	fdC := C.int(fds[0])

	listeners.mu.Lock()
	if listeners.m == nil {
		listeners.m = map[C.int]*listener{}
	}
	listeners.m[fdC] = &listener{s: s, ln: ln, fd: C.SOCKET(sp)}
	listeners.mu.Unlock()

	fmt.Println("listener setup")
	cleanup := func() {
		// If fdC is closed on the C side, then we end up calling
		// into cleanup twice. Be careful to avoid syscall.Close
		// twice as the FD may have been reallocated.
		listeners.mu.Lock()
		if tsLn, ok := listeners.m[fdC]; ok && tsLn.ln == ln {
			delete(listeners.m, fdC)
			platform.CloseSocket(sp)
		}
		listeners.mu.Unlock()
		C.free(unsafe.Pointer(fdPt))

		fmt.Println("ln closing...")
		ln.Close()
		fmt.Println("ln closed")

	}
	go func() {
		// fdC is never written to, so trying to read from sp blocks
		// until fdC is closed. We use this as a signal that C is
		// done with the listener, and we can tear it down.
		//
		// TODO: would using os.NewFile avoid a locked up thread?
		var buf [256]byte
		platform.ReadSocket(sp, &buf)
		//cleanup()
	}()
	go func() {
		defer cleanup()
		for {
			fmt.Println("cleanup starting")
			fmt.Println("listener: ", ln)
			netConn, err := ln.Accept()
			fmt.Println("accept", netConn, err)
			if err != nil {
				fmt.Println("error in accept")
				s.s.Logf("libtailscale.accept: newConn: %v", err)
				return
			}
			var connFd C.int
			if err := newConn(s, netConn, &connFd); err != nil {
				if s.s.Logf != nil {
					s.s.Logf("libtailscale.accept: newConn: %v", err)
				}
				fmt.Println(("net closed 1"))
				netConn.Close()
				continue
			}
			fmt.Println("send message")
			err = platform.SendMessage(sp, []byte("hello"), int(connFd), nil, 0)

			if err != nil {
				// We handle sp being closed in the read goroutine above.
				if s.s.Logf != nil {
					s.s.Logf("libtailscale.accept: sendmsg failed: %v", err)
				}
				fmt.Println("net closed 12", err)
				netConn.Close()
				// fallthrough to close connFd, then continue Accept()ing
			}
			platform.CloseSocket(sp) // now owned by recvmsg
			netConn.Close()
			fmt.Println(("net closed 3"))
		}
	}()

	*listenerOut = fdC
	fmt.Println("returning 0 ")
	return 0
}

func newConn(s *server, netConn net.Conn, connOut *C.int) error {
	fmt.Println("newconn starting")
	fds, fdPt, err := platform.GetSocketPair()
	if err != nil {
		fmt.Println("Error getting new socketpair ")
		return err
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
		fmt.Println("Connection cleanup")
		var inCleanup bool
		conns.mu.Lock()
		fmt.Println("Locked")
		if tsConn, ok := conns.m[fdC]; ok && tsConn.c == netConn {
			fmt.Println("Connection is alive")
			delete(conns.m, fdC)
			inCleanup = true
		}
		conns.mu.Unlock()
		fmt.Println("Unlocked + cleanup: ", inCleanup, conns)
		if !inCleanup {
			return
		}

		C.free(unsafe.Pointer(fdPt))
		r.Close()
		fmt.Println("netconn closing ", conns)
		fmt.Println("servers: ", servers)
		fmt.Println("listeners: ", listeners)
		netConn.Close()
	}
	go func() {
		defer connCleanup()
		var b [1 << 16]byte
		io.CopyBuffer(r, netConn, b[:])
		platform.Shutdown(syscall.Handle(r.Fd()), syscall.SHUT_RD)
		if cr, ok := netConn.(interface{ CloseRead() error }); ok {
			cr.CloseRead()
		}
	}()
	go func() {
		defer connCleanup()
		var b [1 << 16]byte
		io.CopyBuffer(netConn, r, b[:])
		platform.Shutdown(syscall.Handle(r.Fd()), syscall.SHUT_WR)
		if cw, ok := netConn.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
	}()
	*connOut = fdC
	return nil
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
	if newConn(s, netConn, connOut); err != nil {
		return s.recErr(err)
	}
	return 0
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
	} else if proxyOut == nil {
		panic("loopback_api passed nil proxy_cred_out")
	} else if localOut == nil {
		panic("loopback_api passed nil local_api_cred_out")
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
