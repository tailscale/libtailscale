// If your file name follows the structure name_{GOOS}_{GOARCH}.go or
// simply name_{GOOS}.go,
// then it will be compiled only under the target OS+architecture
// or OS+any architecture respectively without needing a special comment
package platform

//#cgo CFLAGS: -g -Wall
//#cgo LDFLAGS: -lws2_32
//#include "errno.h"
//#include "../socketpair_handler.h"
import "C"

import (
	"fmt"
	"syscall"
	"unsafe"
)

func GetSocketPair() ([]syscall.Handle, error) {
	fds := make([]syscall.Handle, 2)
	fds_pt := C.get_socket_pair()
	fds_array := (*[2]C.SOCKET)(unsafe.Pointer(fds_pt))[:]
	fds[0] = syscall.Handle(uintptr(fds_array[0]))
	fds[1] = syscall.Handle(uintptr(fds_array[1]))
	return fds, nil
}

func CloseSocket(fd syscall.Handle) error {
	fmt.Println("Closing socket", fd)
	err := syscall.Close(fd)
	errCode := syscall.GetLastError()
	// Handle the error or print it for debugging
	fmt.Printf("Error closing handle: %v\n", errCode)
	return err
}

func ReadSocket(fd syscall.Handle, buf *[256]byte) {
	fmt.Println("Reading socket", fd)
	syscall.Read(fd, (*buf)[:])
}

func SendMessage(fd syscall.Handle, p []byte, connFd int, to syscall.Sockaddr, flags int) error {
	fmt.Println("Writing socket", fd)
	_, err := syscall.Write(fd, p)
	return err
}

func Shutdown(fd syscall.Handle, how int) error {
	return syscall.Shutdown(fd, how)
}
