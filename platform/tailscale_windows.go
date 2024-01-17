// If your file name follows the structure name_{GOOS}_{GOARCH}.go or
// simply name_{GOOS}.go,
// then it will be compiled only under the target OS+architecture
// or OS+any architecture respectively without needing a special comment
package platform

//#cgo LDFLAGS: -lws2_32
//#include "errno.h"
//#include "../socketpair_handler.h"
import "C"

import (
	"fmt"
	"syscall"
	"unsafe"
)

func GetSocketPair() ([2]int, error) {
	var fds [2]int
	fds_pt := C.get_socket_pair()
	fds_array := (*[1 << 30]int)(unsafe.Pointer(fds_pt))[:2:2]
	fds[0] = fds_array[0]
	fds[1] = fds_array[1]
	return fds, nil
}

func CloseSocket(fd interface{}) error {
	fmt.Println("Closing socket", fd.(syscall.Handle))
	return syscall.Close(fd.(syscall.Handle))
}

func ReadSocket(fd interface{}, buf *[256]byte) {
	syscall.Read(fd.(syscall.Handle), (*buf)[:])
}

func SendMessage(fd interface{}, p []byte, connFd int, to syscall.Sockaddr, flags int) error {
	_, err := syscall.Write(fd.(syscall.Handle), p)
	return err
}

func Shutdown(fd interface{}, how int) error {
	return syscall.Shutdown(fd.(syscall.Handle), how)
}
