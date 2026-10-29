// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

//go:build linux

package main

import "syscall"

// socketpair returns a new AF_LOCAL SOCK_STREAM socketpair whose ends
// are both close-on-exec from birth, so spawned processes do not
// inherit them. Linux creates the pair atomically with SOCK_CLOEXEC.
func socketpair() ([2]int, error) {
	return syscall.Socketpair(syscall.AF_LOCAL, syscall.SOCK_STREAM|syscall.SOCK_CLOEXEC, 0)
}

// recvFlags are the flags TsnetAccept passes to Recvmsg: MSG_WAITALL
// to keep listener socketpair record framing exact, plus
// MSG_CMSG_CLOEXEC so the connection fd installed by SCM_RIGHTS is
// close-on-exec without a race window.
const recvFlags = syscall.MSG_WAITALL | syscall.MSG_CMSG_CLOEXEC

// closeOnExec marks fd close-on-exec. It is a no-op on Linux, where
// recvFlags already made received fds close-on-exec.
func closeOnExec(fd int) {}
