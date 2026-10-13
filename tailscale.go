// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// A Go c-archive of the tsnet package. See tailscale.h for details.
package main

//#include "errno.h"
//
//void ts_signal_flags_restore(void);
//void tailscale_signal_restore(void);
import "C"

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/unix"
	"tailscale.com/hostinfo"
	"tailscale.com/ipn"
	"tailscale.com/tsnet"
	"tailscale.com/types/logger"
)

func main() {}

// The Go runtime's signal setup (initsig, run during library load before
// package init) adds SA_ONSTACK to the flags of every caught host signal
// handler, changing where those handlers run in memory. Undo that,
// restoring the exact host dispositions snapshotted by the constructor
// in tailscale.c before the Go runtime initialized. See SIGNALS.md.
func init() {
	C.ts_signal_flags_restore()
}

// servers tracks all the allocated *tsnet.Server objects.
var servers struct {
	mu   sync.Mutex
	next C.int
	m    map[C.int]*server
}

type server struct {
	s       *tsnet.Server
	lastErr string
	started bool

	// mu guards the pending-operation cancel slots below.
	mu         sync.Mutex
	upCancel   *pendingOp // cancels a pending TsnetUp/TsnetUpTimeout
	dialCancel *pendingOp // cancels a pending TsnetDial/TsnetDialTimeout
}

// pendingOp tracks one blocking up or dial operation so that it can be
// canceled with TsnetCancel (or by TsnetClose, so a close does not block on a
// pending up that would otherwise never finish).
type pendingOp struct {
	cancel context.CancelFunc
}

// beginOp registers a cancelable context for a blocking up or dial call and
// returns it along with a token to pass to endOp. timeoutMs <= 0 means no
// deadline. Only the most recent pending operation of each kind is
// cancellable; earlier pending operations keep running but can no longer be
// targeted individually.
func (s *server) beginOp(up bool, timeoutMs C.longlong) (context.Context, *pendingOp) {
	var ctx context.Context
	var cancel context.CancelFunc
	if timeoutMs > 0 {
		ctx, cancel = context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	} else {
		ctx, cancel = context.WithCancel(context.Background())
	}
	pc := &pendingOp{cancel: cancel}
	s.mu.Lock()
	defer s.mu.Unlock()
	if up {
		s.upCancel = pc
	} else {
		s.dialCancel = pc
	}
	return ctx, pc
}

// endOp unregisters pc if it is still the pending operation and releases
// its context resources. Safe to call when the operation has already been
// canceled.
func (s *server) endOp(up bool, pc *pendingOp) {
	s.mu.Lock()
	if up {
		if s.upCancel == pc {
			s.upCancel = nil
		}
	} else {
		if s.dialCancel == pc {
			s.dialCancel = nil
		}
	}
	s.mu.Unlock()
	pc.cancel()
}

// cancelOps cancels any pending blocking up or dial operations and reports
// whether there was anything to cancel.
func (s *server) cancelOps() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.upCancel == nil && s.dialCancel == nil {
		return false
	}
	if s.upCancel != nil {
		s.upCancel.cancel()
		s.upCancel = nil
	}
	if s.dialCancel != nil {
		s.dialCancel.cancel()
		s.dialCancel = nil
	}
	return true
}

func getServer(sd C.int) *server {
	servers.mu.Lock()
	defer servers.mu.Unlock()
	return servers.m[sd]
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
	// m maps the fd number C holds for an accepted connection (not our
	// sender-side number; recvmsg installs a new one) to its remote IP.
	m map[C.int]string
}

// listenAddrLen is the size of the fixed-size, NUL-padded record that
// carries each accepted connection's remote IP over the listener
// socketpair. Fixed size so TsnetAccept frames the stream with
// exact-size reads; 45 bytes covers the longest textual IP.
const listenAddrLen = 64

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
	// First call for (almost) every embedder (directly or via
	// tailscale_new): complete the signal-state isolation started by the
	// library constructor by restoring the loading thread's signal mask.
	// No-op once done. See SIGNALS.md.
	C.tailscale_signal_restore()

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
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	err := s.s.Start()
	if err == nil {
		s.started = true
	}
	return s.recErr(err)
}

// Up blocks until the server is up and usable. Unlike TsnetUpTimeout, it has
// no deadline, but it is still cancellable with TsnetCancel.
//
//export TsnetUp
func TsnetUp(sd C.int) C.int {
	return up(sd, -1)
}

// UpTimeout is TsnetUp with a deadline: it blocks until the server is up and
// usable, or timeoutMs milliseconds have elapsed. timeoutMs <= 0 means no
// deadline. It is also cancellable with TsnetCancel.
//
//export TsnetUpTimeout
func TsnetUpTimeout(sd C.int, timeoutMs C.longlong) C.int {
	return up(sd, timeoutMs)
}

func up(sd C.int, timeoutMs C.longlong) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	// Cancellation is via TsnetCancel or the timeout.
	ctx, pc := s.beginOp(true, timeoutMs)
	defer s.endOp(true, pc)
	_, err := s.s.Up(ctx)
	if err == nil {
		s.started = true
	}
	return s.recErr(err)
}

// Cancel interrupts the most recent pending TsnetUp/TsnetUpTimeout and
// TsnetDial/TsnetDialTimeout on the server, making them return a
// context-canceled error. Canceling completed operations is a no-op.
//
//export TsnetCancel
func TsnetCancel(sd C.int) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	if !s.cancelOps() {
		return C.ENOENT
	}
	return 0
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

	// Cancel any pending up/dial so they return promptly instead of
	// relying on tsnet.Close to unblock them (which, without an authkey,
	// would be never).
	s.cancelOps()

	// TODO: close related listeners / conns.
	if !s.started {
		// Server was never started, nothing to close.
		return 0
	}
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
	if n >= len(out) {
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
	if n >= len(out) {
		out[len(out)-1] = '\x00' // always NUL-terminate
		return C.ERANGE
	}
	out[n] = '\x00'
	return 0
}

//export TsnetListen
func TsnetListen(sd C.int, network, addr *C.char, listenerOut *C.int) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}

	ln, err := s.s.Listen(C.GoString(network), C.GoString(addr))
	if err != nil {
		return s.recErr(err)
	}
	s.started = true

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
	listener := &listener{s: s, ln: ln, fd: sp, m: map[C.int]string{}}
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
			ip := extractIP(netConn.RemoteAddr().String())
			if len(ip) >= listenAddrLen {
				if s.s.Logf != nil {
					s.s.Logf("libtailscale.accept: remote address %q does not fit in a %d-byte record", ip, listenAddrLen)
				}
				netConn.Close()
				syscall.Close(int(connFd))
				continue
			}
			var addrRec [listenAddrLen]byte
			copy(addrRec[:], ip)

			rights := syscall.UnixRights(int(connFd))
			err = syscall.Sendmsg(sp, addrRec[:], rights, nil, 0)
			if err != nil {
				// a failed sendmsg delivered nothing (sp being closed is
				// handled by the read goroutine above)
				if s.s.Logf != nil {
					s.s.Logf("libtailscale.accept: sendmsg failed: %v", err)
				}
				netConn.Close()
			}

			syscall.Close(int(connFd)) // now owned by recvmsg
		}
	}()

	*listenerOut = fdC
	return 0
}

//export TsnetAccept
func TsnetAccept(listenerFd C.int, connOut *C.int) C.int {
	listeners.mu.Lock()
	ln := listeners.m[listenerFd]
	listeners.mu.Unlock()

	if ln == nil {
		return C.EBADF
	}

	// One record per connection: the fd via SCM_RIGHTS plus its remote
	// IP. The fd parsed below is the number the kernel installed, i.e.
	// the number C will hold.
	//
	// The socketpair is a stream socket, so records are framed here:
	// each read asks for the remaining bytes of the head record, with
	// MSG_WAITALL. The FIFO never serves a later record's bytes first,
	// so each accept consumes exactly one record, even concurrently or
	// after EINTR.
	data := make([]byte, listenAddrLen)
	cbuf := make([]byte, unix.CmsgLen(int(unsafe.Sizeof((C.int)(0)))))
	var n, oobn int
	for n < len(data) {
		buf := data[n:]
		if n > 0 {
			// the cmsg rode with the record's first byte; only the tail remains
			cbuf = nil
		}
		nn, on, _, _, err := syscall.Recvmsg(int(listenerFd), buf, cbuf, syscall.MSG_WAITALL)
		n += nn
		if nn > 0 {
			oobn = on
		}
		if err == syscall.EINTR {
			continue // partial bytes stay record-aligned, keep draining
		}
		if err != nil {
			return ln.s.recErr(err)
		}
		if nn == 0 {
			// EOF mid-record: the listener was closed on the C side.
			return ln.s.recErr(fmt.Errorf("libtailscale: listener closed mid-record: got %d of %d bytes", n, len(data)))
		}
	}

	scms, err := syscall.ParseSocketControlMessage(cbuf[:oobn])
	if err != nil {
		return ln.s.recErr(err)
	}
	if len(scms) != 1 {
		return ln.s.recErr(fmt.Errorf("libtailscale: got %d control messages, want 1", len(scms)))
	}
	fds, err := syscall.ParseUnixRights(&scms[0])
	if err != nil {
		return ln.s.recErr(err)
	}
	if len(fds) != 1 {
		return ln.s.recErr(fmt.Errorf("libtailscale: got %d FDs, want 1", len(fds)))
	}
	fd := C.int(fds[0])

	// the entry must exist before C can learn this fd number
	addrLen := bytes.IndexByte(data, 0)
	if addrLen < 0 {
		addrLen = listenAddrLen
	}
	ln.mu.Lock()
	ln.m[fd] = string(data[:addrLen])
	ln.mu.Unlock()

	*connOut = fd

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
	// the Shutdowns below must precede connCleanup: r.Fd() after Close
	// can return a reused fd number. Wait for both copy directions.
	var copies sync.WaitGroup
	copies.Add(2)
	go func() {
		defer copies.Done()
		var b [1 << 16]byte
		io.CopyBuffer(r, netConn, b[:])
		syscall.Shutdown(int(r.Fd()), syscall.SHUT_WR)
		if cr, ok := netConn.(interface{ CloseRead() error }); ok {
			cr.CloseRead()
		}
	}()
	go func() {
		defer copies.Done()
		var b [1 << 16]byte
		io.CopyBuffer(netConn, r, b[:])
		syscall.Shutdown(int(r.Fd()), syscall.SHUT_RD)
		if cw, ok := netConn.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
	}()
	go func() {
		copies.Wait()
		connCleanup()
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
	ip, ok := l.m[conn]
	if !ok {
		// set errmsg too: EBADF with an empty message is not debuggable
		l.s.lastErr = fmt.Sprintf("libtailscale: getremoteaddr: no remote address recorded for conn %d on listener %d", conn, listener)
		out[0] = '\x00'
		return C.EBADF
	}

	n := copy(out, ip)
	if n >= len(out) {
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

// Dial blocks until the connection is established. Unlike
// TsnetDialTimeout, it has no deadline, but it is still cancellable with
// TsnetCancel.
//
//export TsnetDial
func TsnetDial(sd C.int, network, addr *C.char, connOut *C.int) C.int {
	return dial(sd, network, addr, -1, connOut)
}

// DialTimeout is TsnetDial with a deadline: it blocks until the connection
// is established or timeoutMs milliseconds have elapsed. timeoutMs <= 0
// means no deadline. It is also cancellable with TsnetCancel.
//
//export TsnetDialTimeout
func TsnetDialTimeout(sd C.int, network, addr *C.char, timeoutMs C.longlong, connOut *C.int) C.int {
	return dial(sd, network, addr, timeoutMs, connOut)
}

func dial(sd C.int, network, addr *C.char, timeoutMs C.longlong, connOut *C.int) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	// Cancellation is via TsnetCancel or the timeout.
	ctx, pc := s.beginOp(false, timeoutMs)
	defer s.endOp(false, pc)
	netConn, err := s.s.Dial(ctx, C.GoString(network), C.GoString(addr))
	if err != nil {
		return s.recErr(err)
	}
	s.started = true
	if err := newConn(s, netConn, connOut); err != nil {
		return s.recErr(err)
	}
	return 0
}

//export TsnetSetDir
func TsnetSetDir(sd C.int, str *C.char) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	s.s.Dir = C.GoString(str)
	return 0
}

//export TsnetSetHostname
func TsnetSetHostname(sd C.int, str *C.char) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	s.s.Hostname = C.GoString(str)
	return 0
}

//export TsnetSetAuthKey
func TsnetSetAuthKey(sd C.int, str *C.char) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	s.s.AuthKey = C.GoString(str)
	return 0
}

//export TsnetSetControlURL
func TsnetSetControlURL(sd C.int, str *C.char) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	s.s.ControlURL = C.GoString(str)
	return 0
}

//export TsnetSetEphemeral
func TsnetSetEphemeral(sd C.int, e int) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
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
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	if fd == -1 {
		s.s.Logf = logger.Discard
		return 0
	}
	f := os.NewFile(uintptr(fd), "logfd")
	logf := func(format string, args ...any) {
		fmt.Fprintf(f, format, args...)
		fmt.Fprintf(f, "\n")
	}
	// tsnet routes some messages through UserLogf (falling back to Go's
	// standard log.Printf, bypassing Logf entirely), so both must be set
	// for the fd to receive everything.
	s.s.Logf = logf
	s.s.UserLogf = logf
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

	s := getServer(sd)
	if s == nil {
		return C.EBADF
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

	out := unsafe.Slice((*byte)(unsafe.Pointer(addrOut)), addrLen)
	n := copy(out, addr)
	if n >= len(out) {
		out[len(out)-1] = '\x00' // always NUL-terminate
		return C.ERANGE
	}
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

//export TsnetStatusJSON
func TsnetStatusJSON(sd C.int, jsonOut **C.char) C.int {
	if jsonOut == nil {
		panic("status_json passed nil json_out")
	}
	*jsonOut = nil
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	// LocalClient rides tsnet's in-memory LocalAPI listener — unlike
	// Loopback()'s TCP listener it cannot be reclaimed by the OS while
	// the process is suspended (iOS), so status reads keep working on
	// long-lived nodes.
	lc, err := s.s.LocalClient()
	if err != nil {
		return s.recErr(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	st, err := lc.Status(ctx)
	if err != nil {
		return s.recErr(err)
	}
	b, err := json.Marshal(st)
	if err != nil {
		return s.recErr(err)
	}
	*jsonOut = C.CString(string(b))
	return 0
}

//export TsnetEnableFunnelToLocalhostPlaintextHttp1
func TsnetEnableFunnelToLocalhostPlaintextHttp1(sd C.int, localhostPort C.int) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}

	ctx := context.Background()
	lc, err := s.s.LocalClient()
	if err != nil {
		return s.recErr(err)
	}

	st, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		return s.recErr(err)
	}
	domain := st.CertDomains[0]

	hp := ipn.HostPort(net.JoinHostPort(domain, strconv.Itoa(443)))
	tcpForward := fmt.Sprintf("127.0.0.1:%d", localhostPort)
	sc := &ipn.ServeConfig{
		TCP: map[uint16]*ipn.TCPPortHandler{
			443: {
				TCPForward:   tcpForward,
				TerminateTLS: domain,
			},
		},
		AllowFunnel: map[ipn.HostPort]bool{
			hp: true,
		},
	}

	lc.SetServeConfig(ctx, sc)
	if !sc.AllowFunnel[hp] {
		return s.recErr(fmt.Errorf("libtailscale: failed to enable funnel"))
	}

	return 0
}
