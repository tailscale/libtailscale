package main

import (
	"C"
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
)
import (
	"context"
	"unsafe"

	"tailscale.com/client/tailscale"
)

func proxy() {
	http.HandleFunc("/", handleRequest)
	err := http.ListenAndServe("127.0.0.1:9099", nil)
	if err != nil {
		fmt.Printf("Error starting reverse proxy: %v", err)
	}
}

var proxyMap = map[string]string{}

//export UpdateProxyMap
func UpdateProxyMap(key *C.char, value *C.char) {
	proxyMap[C.GoString(key)] = C.GoString(value)
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	var targetURL string

	host, _, _ := net.SplitHostPort(r.Host)
	if val, ok := proxyMap[host]; ok {
		targetURL = val
	} else {
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprint(w, "custom 404")
		return
	}
	target, err := url.Parse(targetURL)
	if err != nil {
		http.Error(w, "Error parsing target URL", http.StatusInternalServerError)
		return
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.Transport = &http.Transport{
		DisableKeepAlives: true,
	}

	// Update the headers to allow for SSL redirection
	r.URL.Host = target.Host
	r.URL.Scheme = target.Scheme
	r.Header.Set("X-Forwarded-Host", r.Header.Get("Host"))
	r.Host = target.Host

	// Note that ServeHttp is non blocking and uses a go routine under the hood
	proxy.ServeHTTP(w, r)
}

//export TsnetIPAddr
func TsnetIPAddr(addrOut *C.char, addrLen C.size_t) C.int {
	// Panic here to ensure we always leave the out values NUL-terminated.
	if addrOut == nil {
		panic("loopback_api passed nil addr_out")
	} else if addrLen == 0 {
		panic("loopback_api passed addrlen of 0")
	}

	// Start out NUL-termianted to cover error conditions.
	*addrOut = '\x00'

	status, _ := tailscale.Status(context.Background())
	for _, ip := range status.TailscaleIPs {
		if ip.Is4() {
			addr := ip.String()
			if len(addr)+1 > int(addrLen) {
				fmt.Printf("libtailscale: loopback addr of %d bytes is too long for addrlen %d", len(addr), addrLen)
			}
			out := unsafe.Slice((*byte)(unsafe.Pointer(addrOut)), addrLen)
			n := copy(out, addr)
			out[n] = '\x00'
			return 0
		}
	}
	return 0
}
