// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// A Go c-archive of the tsnet package. See tailscale.h for details.
package main

//#include "errno.h"
import "C"

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"regexp"
	"strings"
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
	mu sync.Mutex
	m  map[C.int]*listener
}

type listener struct {
	s  *server
	ln net.Listener
	fd int // go side fd of socketpair sent to C
	mu sync.Mutex
	m  map[C.int]net.Addr //maps fds to remote addresses for lookup
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

//export TsnetGetIps
func TsnetGetIps(sd C.int, buf *C.char, buflen C.size_t) C.int {
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

	ip4, ip6 := s.s.TailscaleIPs()
	joined := strings.Join([]string{ip4.String(), ip6.String()}, ",")
	n := copy(out, joined)
	if len(out) < len(joined)-1 {
		out[len(out)-1] = '\x00' // always NUL-terminate
		return C.ERANGE
	}
	out[n] = '\x00'
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

	// The tailscale_listener we return to C is one side of a socketpair(2).
	// We do this so we can proactively call ln.Accept in a goroutine and
	// feed an fd for the connection through the listener. This lets C use
	// epoll on the tailscale_listener to know if it should call
	// tailscale_accept, which avoids a blocking call on the far side.
	fds, err := syscall.Socketpair(syscall.AF_LOCAL, syscall.SOCK_STREAM, 0)
	if err != nil {
		return s.recErr(err)
	}
	sp := fds[1]
	fdC := C.int(fds[0])

	listeners.mu.Lock()
	if listeners.m == nil {
		listeners.m = map[C.int]*listener{}
	}
	listener := &listener{s: s, ln: ln, fd: sp, m: map[C.int]net.Addr{}}
	listeners.m[fdC] = listener
	listeners.mu.Unlock()

	cleanup := func() {
		// If fdC is closed on the C side, then we end up calling
		// into cleanup twice. Be careful to avoid syscall.Close
		// twice as the FD may have been reallocated.
		listeners.mu.Lock()
		if tsLn, ok := listeners.m[fdC]; ok && tsLn.ln == ln {
			delete(listeners.m, fdC)
			syscall.Close(sp)
		}
		listeners.mu.Unlock()

		ln.Close()
	}
	go func() {
		// fdC is never written to, so trying to read from sp blocks
		// until fdC is closed. We use this as a signal that C is
		// done with the listener, and we can tear it down.
		//
		// TODO: would using os.NewFile avoid a locked up thread?
		var buf [256]byte
		syscall.Read(sp, buf[:])
		cleanup()
	}()
	go func() {
		defer cleanup()
		for {
			netConn, err := ln.Accept()
			if err != nil {
				return
			}
			var connFd C.int
			if err := newConn(s, netConn, &connFd); err != nil {
				if s.s.Logf != nil {
					s.s.Logf("libtailscale.accept: newConn: %v", err)
				}
				netConn.Close()
				continue
			}
			rights := syscall.UnixRights(int(connFd))
			err = syscall.Sendmsg(sp, nil, rights, nil, 0)
			if err != nil {
				// We handle sp being closed in the read goroutine above.
				if s.s.Logf != nil {
					s.s.Logf("libtailscale.accept: sendmsg failed: %v", err)
				}
				netConn.Close()
				// fallthrough to close connFd, then continue Accept()ing
			}

			// map the connection to the remote address
			listener.mu.Lock()
			listener.m[connFd] = netConn.RemoteAddr()
			listener.mu.Unlock()

			syscall.Close(int(connFd)) // now owned by recvmsg
		}
	}()

	*listenerOut = fdC
	return 0
}

//export TsnetListenFunnel
func TsnetListenFunnel(sd C.int, network, addr *C.char, funnelOnly C.int, listenerOut *C.int) C.int {
	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}

	var ln net.Listener
	if funnelOnly != 0 {
		ln, err = s.s.ListenFunnel(C.GoString(network), C.GoString(addr), tsnet.FunnelOnly())
	} else {
		ln, err = s.s.ListenFunnel(C.GoString(network), C.GoString(addr))
	}

	if err != nil {
		return s.recErr(err)
	}

	// The tailscale_listener we return to C is one side of a socketpair(2).
	// We do this so we can proactively call ln.Accept in a goroutine and
	// feed an fd for the connection through the listener. This lets C use
	// epoll on the tailscale_listener to know if it should call
	// tailscale_accept, which avoids a blocking call on the far side.
	fds, err := syscall.Socketpair(syscall.AF_LOCAL, syscall.SOCK_STREAM, 0)
	if err != nil {
		return s.recErr(err)
	}
	sp := fds[1]
	fdC := C.int(fds[0])

	listeners.mu.Lock()
	if listeners.m == nil {
		listeners.m = map[C.int]*listener{}
	}
	listeners.m[fdC] = &listener{s: s, ln: ln, fd: sp}
	listeners.mu.Unlock()

	cleanup := func() {
		// If fdC is closed on the C side, then we end up calling
		// into cleanup twice. Be careful to avoid syscall.Close
		// twice as the FD may have been reallocated.
		listeners.mu.Lock()
		if tsLn, ok := listeners.m[fdC]; ok && tsLn.ln == ln {
			delete(listeners.m, fdC)
			syscall.Close(sp)
		}
		listeners.mu.Unlock()

		ln.Close()
	}
	go func() {
		// fdC is never written to, so trying to read from sp blocks
		// until fdC is closed. We use this as a signal that C is
		// done with the listener, and we can tear it down.
		//
		// TODO: would using os.NewFile avoid a locked up thread?
		var buf [256]byte
		syscall.Read(sp, buf[:])
		cleanup()
	}()
	go func() {
		defer cleanup()
		for {
			netConn, err := ln.Accept()
			if err != nil {
				return
			}
			var connFd C.int
			if err := newConn(s, netConn, &connFd); err != nil {
				if s.s.Logf != nil {
					s.s.Logf("libtailscale.accept: newConn: %v", err)
				}
				netConn.Close()
				continue
			}
			rights := syscall.UnixRights(int(connFd))
			err = syscall.Sendmsg(sp, nil, rights, nil, 0)
			if err != nil {
				// We handle sp being closed in the read goroutine above.
				if s.s.Logf != nil {
					s.s.Logf("libtailscale.accept: sendmsg failed: %v", err)
				}
				netConn.Close()
				// fallthrough to close connFd, then continue Accept()ing
			}
			syscall.Close(int(connFd)) // now owned by recvmsg
		}
	}()

	*listenerOut = fdC
	return 0
}

func newConn(s *server, netConn net.Conn, connOut *C.int) error {
	fds, err := syscall.Socketpair(syscall.AF_LOCAL, syscall.SOCK_STREAM, 0)
	if err != nil {
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
		var inCleanup bool
		conns.mu.Lock()
		if tsConn, ok := conns.m[fdC]; ok && tsConn.c == netConn {
			delete(conns.m, fdC)
			inCleanup = true
		}
		conns.mu.Unlock()

		if !inCleanup {
			return
		}

		r.Close()
		netConn.Close()
	}
	go func() {
		defer connCleanup()
		var b [1 << 16]byte
		io.CopyBuffer(r, netConn, b[:])
		syscall.Shutdown(int(r.Fd()), syscall.SHUT_WR)
		if cr, ok := netConn.(interface{ CloseRead() error }); ok {
			cr.CloseRead()
		}
	}()
	go func() {
		defer connCleanup()
		var b [1 << 16]byte
		io.CopyBuffer(netConn, r, b[:])
		syscall.Shutdown(int(r.Fd()), syscall.SHUT_RD)
		if cw, ok := netConn.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
	}()

	*connOut = fdC
	return nil
}

//export TsnetGetRemoteAddr
func TsnetGetRemoteAddr(listener C.int, conn C.int, buf *C.char, buflen C.size_t) C.int {
	if buf == nil {
		panic("errmsg passed nil buf")
	} else if buflen == 0 {
		panic("errmsg passed buflen of 0")
	}
	out := unsafe.Slice((*byte)(unsafe.Pointer(buf)), buflen)

	listeners.mu.Lock()
	defer listeners.mu.Unlock()
	l := listeners.m[listener]
	if l == nil {
		out[0] = '\x00'
		return C.EBADF
	}

	l.mu.Lock()
	defer l.mu.Unlock()
	addr, ok := l.m[conn]
	if !ok {
		out[0] = '\x00'
		return C.EBADF
	}

	ip := extractIP(addr.String())

	n := copy(out, ip)
	if len(out) < len(ip)-1 {
		out[len(out)-1] = '\x00' // always NUL-terminate
		return C.ERANGE
	}
	out[n] = '\x00'
	return 0
}

// Strips the port from connection IPs
func extractIP(ipWithPort string) string {
	re := regexp.MustCompile(`(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})|\[([0-9a-fA-F:]+)\]`)
	match := re.FindString(ipWithPort)
	return match
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
		fmt.Fprintf(f, "\n")
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

//export TsnetGetCertDomains
func TsnetGetCertDomains(sd C.int, buf *C.char, buflen C.size_t) C.int {
	if buf == nil {
		panic("TsnetGetCertDomains passed nil buf")
	} else if buflen == 0 {
		panic("TsnetGetCertDomains passed buflen of 0")
	}

	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}

	domains := s.s.CertDomains()
	if len(domains) == 0 {
		return s.recErr(fmt.Errorf("no domains available"))
	}
	firstDomain := domains[0]
	if C.size_t(len(firstDomain)+1) > buflen {
		return C.ERANGE // buffer too small
	}
	output := unsafe.Slice((*byte)(unsafe.Pointer(buf)), buflen)
	copy(output, firstDomain)
	output[len(firstDomain)] = 0 // null-terminate
	return 0
}
