// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

//go:build !linux

package main

import "syscall"

// socketpair returns a new AF_LOCAL SOCK_STREAM socketpair whose ends
// are both close-on-exec, so spawned processes do not inherit them.
//
// Platforms without SOCK_CLOEXEC (darwin) create the pair while
// holding ForkLock's read lock, which delays any concurrent fork
// (which takes the write lock) until both ends are marked
// close-on-exec. This is the same dance package net does for
// accept(2).
func socketpair() ([2]int, error) {
	syscall.ForkLock.RLock()
	defer syscall.ForkLock.RUnlock()

	fds, err := syscall.Socketpair(syscall.AF_LOCAL, syscall.SOCK_STREAM, 0)
	if err != nil {
		return fds, err
	}
	syscall.CloseOnExec(fds[0])
	syscall.CloseOnExec(fds[1])
	return fds, nil
}

// recvFlags are the flags TsnetAccept passes to Recvmsg: MSG_WAITALL
// to keep listener socketpair record framing exact. Platforms without
// MSG_CMSG_CLOEXEC mark the fd received via SCM_RIGHTS close-on-exec
// with closeOnExec instead.
const recvFlags = syscall.MSG_WAITALL

// closeOnExec marks fd close-on-exec. It runs right after Recvmsg
// installed fd, closing the window in which a concurrent fork could
// inherit it as far as the kernel allows.
func closeOnExec(fd int) {
	syscall.CloseOnExec(fd)
}
