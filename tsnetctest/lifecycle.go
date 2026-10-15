// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

package tsnetctest

/*
#include <stdlib.h>
#include "../tailscale.h"
*/
import "C"

import "unsafe"

// These helpers let Go tests exercise the C bridge without importing C in a
// _test.go file. Returned file descriptors belong to the caller.
func Dial(sd int32, network, addr string) (rc, fd int) {
	n, a := C.CString(network), C.CString(addr)
	defer C.free(unsafe.Pointer(n))
	defer C.free(unsafe.Pointer(a))
	out := C.int(-1)
	r := C.tailscale_dial(C.int(sd), n, a, &out)
	return int(r), int(out)
}

func Listen(sd int32, network, addr string) (rc, fd int) {
	n, a := C.CString(network), C.CString(addr)
	defer C.free(unsafe.Pointer(n))
	defer C.free(unsafe.Pointer(a))
	out := C.int(-1)
	r := C.tailscale_listen(C.int(sd), n, a, &out)
	return int(r), int(out)
}

func Loopback(sd int32) (rc int, addr, proxy, local string) {
	var a [128]C.char
	var p, l [33]C.char
	r := C.tailscale_loopback(C.int(sd), &a[0], C.size_t(len(a)), &p[0], &l[0])
	return int(r), C.GoString(&a[0]), C.GoString(&p[0]), C.GoString(&l[0])
}

func StatusJSON(sd int32) (rc int, body string) {
	var out *C.char
	r := C.tailscale_status_json(C.int(sd), &out)
	if out != nil {
		defer C.free(unsafe.Pointer(out))
		body = C.GoString(out)
	}
	return int(r), body
}

func Errmsg(sd int32, size int) (rc int, buf []byte) {
	buf = make([]byte, size)
	for i := range buf {
		buf[i] = 0xff
	}
	r := C.tailscale_errmsg(C.int(sd), (*C.char)(unsafe.Pointer(&buf[0])), C.size_t(size))
	return int(r), buf
}
