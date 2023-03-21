package main

import (
	"C"
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"
)

func proxy() {
	http.HandleFunc("/", handleRequest)
	err := http.ListenAndServe("127.0.0.1:9099", nil)
	if err != nil {
		fmt.Printf("Error starting reverse proxy: %v", err)
	}
}

var proxyMap = map[string]string{
	"login.matesec.cn":   "http://100.64.0.5",
	"file.matesec.cn":    "http://100.64.0.3",
	"openwrt.matesec.cn": "http://100.122.189.12",
}

//export UpdateProxyMap
func UpdateProxyMap(key *C.char, value *C.char) {
	proxyMap[C.GoString(key)] = C.GoString(value)
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	var targetURL string

	if val, ok := proxyMap[r.Host]; ok {
		targetURL = val
	} else {
		targetURL = "http://100.64.0.5"
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
