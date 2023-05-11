package main

import (
	"C"
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"unsafe"

	"tailscale.com/tsnet"
)

func proxy(s *tsnet.Server) {
	tsnetServer = s
	http.HandleFunc("/", handleRequest)

	log.Fatal(http.ListenAndServeTLS("127.0.0.1:9099", "cert.pem", "key.pem", nil))
}

var tsnetServer *tsnet.Server
var proxyMap = map[string]string{}

//export UpdateProxyMap
func UpdateProxyMap(key *C.char, value *C.char) {
	proxyMap[C.GoString(key)] = C.GoString(value)
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	var targetURL string

	host, port, _ := net.SplitHostPort(r.Host)
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
		DialContext:       tsnetServer.Dial,
		DisableKeepAlives: true,
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: true,
		},
	}

	// Update the headers to allow for SSL redirection
	r.URL.Host = target.Host
	r.URL.Scheme = target.Scheme
	r.Header.Set("Host", r.Host)
	r.Header.Set("Port", port)
	r.Header.Set("X-Forwarded-Host", host)
	r.Header.Set("X-Forwarded-Port", port)
	r.Header.Set("X-Forwarded-For", r.RemoteAddr)
	r.Header.Set("X-Forwarded-Proto", r.URL.Scheme)

	// Note that ServeHttp is non blocking and uses a go routine under the hood
	proxy.ServeHTTP(w, r)
}

//export TsnetIPAddr
func TsnetIPAddr(sd C.int, addrOut *C.char, addrLen C.size_t) C.int {
	// Panic here to ensure we always leave the out values NUL-terminated.
	if addrOut == nil {
		panic("loopback_api passed nil addr_out")
	} else if addrLen == 0 {
		panic("loopback_api passed addrlen of 0")
	}

	// Start out NUL-termianted to cover error conditions.
	*addrOut = '\x00'

	s, err := getServer(sd)
	if err != nil {
		return s.recErr(err)
	}
	lc, _ := s.s.LocalClient()
	status, _ := lc.Status(context.Background())
	for _, ip := range status.TailscaleIPs {
		if ip.Is4() {
			addr := ip.String()
			if len(addr)+1 > int(addrLen) {
				fmt.Printf("addr of %d bytes is too long for addrlen %d", len(addr), addrLen)
			}
			out := unsafe.Slice((*byte)(unsafe.Pointer(addrOut)), addrLen)
			n := copy(out, addr)
			out[n] = '\x00'
			return 0
		}
	}
	return 0
}
