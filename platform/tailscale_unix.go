//go:build darwin || linux
// +build darwin linux

package platform

//#include "errno.h"
//#include "../socketpair_handler.h"
import "C"

import (
	"syscall"
)

func GetSocketPair() ([2]int, error) {
	return syscall.Socketpair(syscall.AF_LOCAL, syscall.SOCK_STREAM, 0)
}

func CloseSocket(fd interface{}) (err error) {
	return syscall.Close(fd.(int))
}

func ReadSocket(fd interface{}, buf *[256]byte) {
	syscall.Read(fd.(int), (*buf)[:])
}

func SendMessage(fd interface{}, p []byte, connFd int, to syscall.Sockaddr, flags int) (err error) {
	rights := syscall.UnixRights(int(connFd))
	return syscall.Sendmsg(fd.(int), p, rights, to, flags)
}

func Shutdown(fd interface{}, how int) (err error) {
	return syscall.Shutdown(fd.(int), how)
}
