// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include "tailscale.h"
#include <sys/socket.h>
#include <stdio.h>
#include <unistd.h>

// Host-signal-state isolation. See SIGNALS.md.
//
// The Go runtime initializes in a library constructor at load time and
// makes process-global changes to signal state:
//
//   - it installs its own handlers for SIGILL, SIGBUS, SIGFPE, SIGSEGV,
//     SIGPIPE and SIGURG (forwarding foreign faults back to the host);
//   - it adds SA_ONSTACK to the flags of every other *caught* host
//     handler (initsig's setsigstack), changing where those handlers run;
//   - it snapshots the loading thread's signal mask to seed the mask of
//     every thread it creates, so with a typical all-unblocked host those
//     Go threads accept (and route through the Go runtime) process-
//     directed signals.
//
// To keep the host runtime's signal handling working unchanged:
//
//   1. ts_signal_isolate runs BEFORE the Go runtime's own constructor
//      (prioritized constructors are sorted ahead of unprioritized ones):
//      it snapshots the host's caught signal dispositions and blocks every
//      signal on the loading thread. The thread the Go runtime creates for
//      itself inherits that mask, and it in turn seeds every Go thread, so
//      Go threads only ever accept the signals the Go runtime needs.
//   2. ts_signal_flags_restore undoes the SA_ONSTACK mutations; it is
//      invoked from the Go package init (which runs after the runtime's
//      signal setup but before the library load returns).
//   3. tailscale_signal_restore restores the loading thread's own signal
//      mask, completing the isolation. It is called automatically from
//      the first tailscale_new()/TsnetNewServer() call; embedders that
//      want host signals live before creating any server can call it
//      explicitly from the thread that loaded the library.
#if !defined(_WIN32)
#include <signal.h>
#include <pthread.h>

#define TS_NSIG 32 // signal dispositions snapshotted: signals 1..31

static struct sigaction ts_preload_sigaction[TS_NSIG];
static int ts_preload_valid[TS_NSIG];
static sigset_t ts_preload_mask;
static pthread_t ts_loader_thread;
static int ts_signal_isolation = 0; // 1 once the isolate constructor ran
static int ts_mask_restored = 0;    // 1 once the loader thread mask is back

// ts_go_owned reports whether sig is one of the signals the Go runtime
// installs its own handler for in c-archive/c-shared mode (fault recovery,
// SIGURG preemption, SIGPIPE semantics). Those dispositions belong to the
// Go runtime and are left alone.
static int ts_go_owned(int sig) {
	return sig == SIGILL || sig == SIGBUS || sig == SIGFPE ||
		sig == SIGSEGV || sig == SIGPIPE || sig == SIGURG;
}

// ts_signal_isolate snapshots the host's caught signal dispositions and
// blocks all signals on the loading thread, so that the thread the Go
// runtime creates during its own constructor (and every Go thread seeded
// from it) inherits the blocked mask.
//
// Uses only async-signal- and constructor-safe libc calls.
__attribute__((constructor(101)))
static void ts_signal_isolate(void) {
	int sig;
	for (sig = 1; sig < TS_NSIG; sig++) {
		struct sigaction sa;
		if (sig == SIGKILL || sig == SIGSTOP || ts_go_owned(sig)) {
			continue;
		}
		if (sigaction(sig, NULL, &sa) != 0) {
			continue;
		}
		if (sa.sa_handler != SIG_DFL && sa.sa_handler != SIG_IGN) {
			// The host has caught this signal; protect its disposition.
			ts_preload_sigaction[sig] = sa;
			ts_preload_valid[sig] = 1;
		}
	}
	sigset_t all;
	sigfillset(&all);
	if (pthread_sigmask(SIG_BLOCK, &all, &ts_preload_mask) == 0) {
		ts_loader_thread = pthread_self();
		ts_signal_isolation = 1;
	}
}

// ts_signal_flags_restore undoes the SA_ONSTACK flag that the Go runtime
// added to caught host signal handlers during its signal setup. Idempotent
// and process-global; called from the Go package init (before the library
// load returns) and from tailscale_signal_restore.
void ts_signal_flags_restore(void) {
	int sig;
	if (!ts_signal_isolation) {
		return;
	}
	for (sig = 1; sig < TS_NSIG; sig++) {
		struct sigaction cur;
		if (!ts_preload_valid[sig]) {
			continue;
		}
		if (sigaction(sig, NULL, &cur) != 0) {
			continue;
		}
		if (cur.sa_handler != ts_preload_sigaction[sig].sa_handler) {
			continue; // no longer the host's handler
		}
		if ((cur.sa_flags & SA_ONSTACK) == 0 ||
			(ts_preload_sigaction[sig].sa_flags & SA_ONSTACK) != 0) {
			continue; // untouched, or the host wanted SA_ONSTACK itself
		}
		// Restore the exact pre-load disposition (handler, flags, mask).
		sigaction(sig, &ts_preload_sigaction[sig], NULL);
	}
}

// tailscale_signal_restore restores the signal mask of the thread that
// loaded the library, completing the isolation begun by the constructor.
//
// The mask is per-thread, so only the loading thread can restore its own;
// the process-global flag repair happens regardless. Both parts are
// idempotent, so calling this repeatedly, or from other threads, is
// harmless.
void tailscale_signal_restore(void) {
	if (!ts_signal_isolation) {
		return;
	}
	if (!ts_mask_restored && pthread_equal(pthread_self(), ts_loader_thread)) {
		pthread_sigmask(SIG_SETMASK, &ts_preload_mask, NULL);
		ts_mask_restored = 1;
	}
	ts_signal_flags_restore();
}

#else // _WIN32: no signals to isolate.
void ts_signal_flags_restore(void) {}
void tailscale_signal_restore(void) {}
#endif

// Functions exported by Go.
extern int TsnetNewServer();
extern int TsnetStart(int sd);
extern int TsnetUp(int sd);
extern int TsnetUpTimeout(int sd, long long timeoutMs);
extern int TsnetCancel(int sd);
extern int TsnetClose(int sd);
extern int TsnetErrmsg(int sd, char* buf, size_t buflen);
extern int TsnetDial(int sd, char* net, char* addr, int* connOut);
extern int TsnetDialTimeout(int sd, char* net, char* addr, long long timeoutMs, int* connOut);
extern int TsnetSetDir(int sd, char* str);
extern int TsnetSetHostname(int sd, char* str);
extern int TsnetSetAuthKey(int sd, char* str);
extern int TsnetSetControlURL(int sd, char* str);
extern int TsnetSetEphemeral(int sd, int ephemeral);
extern int TsnetSetLogFD(int sd, int fd);
extern int TsnetGetIps(int sd, char *buf, size_t buflen);
extern int TsnetGetRemoteAddr(int listener, int conn, char *buf, size_t buflen);
extern int TsnetListen(int sd, char* net, char* addr, int* listenerOut);
extern int TsnetAccept(int ld, int* connOut);
extern int TsnetLoopback(int sd, char* addrOut, size_t addrLen, char* proxyOut, char* localOut);
extern int TsnetStatusJSON(int sd, char** jsonOut);
extern int TsnetEnableFunnelToLocalhostPlaintextHttp1(int sd, int localhostPort);

tailscale tailscale_new() {
	// First call for (almost) every embedder: complete the signal-state
	// isolation started by the library constructor. No-op once done.
	tailscale_signal_restore();
	return TsnetNewServer();
}

int tailscale_start(tailscale sd) {
	return TsnetStart(sd);
}

int tailscale_up(tailscale sd) {
	return TsnetUp(sd);
}

int tailscale_up_timeout(tailscale sd, long long timeout_ms) {
	return TsnetUpTimeout(sd, timeout_ms);
}

int tailscale_cancel(tailscale sd) {
	return TsnetCancel(sd);
}

int tailscale_close(tailscale sd) {
	return TsnetClose(sd);
}

int tailscale_dial(tailscale sd, const char* network, const char* addr, tailscale_conn* conn_out) {
	return TsnetDial(sd, (char*)network, (char*)addr, (int*)conn_out);
}

int tailscale_dial_timeout(tailscale sd, const char* network, const char* addr, long long timeout_ms, tailscale_conn* conn_out) {
	return TsnetDialTimeout(sd, (char*)network, (char*)addr, timeout_ms, (int*)conn_out);
}

int tailscale_listen(tailscale sd, const char* network, const char* addr, tailscale_listener* listener_out) {
	return TsnetListen(sd, (char*)network, (char*)addr, (int*)listener_out);
}

int tailscale_accept(tailscale_listener ld, tailscale_conn* conn_out) {
	return TsnetAccept(ld, (int*)conn_out);
}

int tailscale_getremoteaddr(tailscale_listener l, tailscale_conn conn, char* buf, size_t buflen) {
	return TsnetGetRemoteAddr(l, conn, buf, buflen);
}

int tailscale_getips(tailscale sd, char* buf, size_t buflen) {
	return TsnetGetIps(sd, buf, buflen);
}

int tailscale_set_dir(tailscale sd, const char* dir) {
	return TsnetSetDir(sd, (char*)dir);
}
int tailscale_set_hostname(tailscale sd, const char* hostname) {
	return TsnetSetHostname(sd, (char*)hostname);
}
int tailscale_set_authkey(tailscale sd, const char* authkey) {
	return TsnetSetAuthKey(sd, (char*)authkey);
}
int tailscale_set_control_url(tailscale sd, const char* control_url) {
	return TsnetSetControlURL(sd, (char*)control_url);
}
int tailscale_set_ephemeral(tailscale sd, int ephemeral) {
	return TsnetSetEphemeral(sd, ephemeral);
}
int tailscale_set_logfd(tailscale sd, int fd) {
	return TsnetSetLogFD(sd, fd);
}

int tailscale_loopback(tailscale sd, char* addr_out, size_t addrlen, char* proxy_cred_out, char* local_api_cred_out) {
	return TsnetLoopback(sd, addr_out, addrlen, proxy_cred_out, local_api_cred_out);
}

int tailscale_status_json(tailscale sd, char** json_out) {
	return TsnetStatusJSON(sd, json_out);
}

int tailscale_errmsg(tailscale sd, char* buf, size_t buflen) {
	return TsnetErrmsg(sd, buf, buflen);
}

int tailscale_enable_funnel_to_localhost_plaintext_http1(tailscale sd, int localhostPort) {
	return TsnetEnableFunnelToLocalhostPlaintextHttp1(sd, localhostPort);
}
