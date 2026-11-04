// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

// csigtest verifies libtailscale's host-signal isolation from the
// perspective of a C embedder (and of FFI-style bindings, which load the
// library the same way). Usage: csigtest <path-to-libtailscale.so>
//
// Run by `make test-signals`. See SIGNALS.md.
#include <dlfcn.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>

#include "../tailscale.h"

static volatile sig_atomic_t got_usr1 = 0;
static void usr1_handler(int sig) { got_usr1 = 1; }

static int failures = 0;
#define CHECK(cond, msg) do { \
	if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } \
	else { printf("ok: %s\n", msg); } \
} while (0)

// sigblk_of_tid reads the thread's blocked signal set from /proc, or
// returns (uint64_t)-1 on error. Linux only; the test exits early on
// other platforms.
static uint64_t sigblk_of_tid(int tid) {
	char path[64];
	snprintf(path, sizeof(path), "/proc/self/task/%d/status", tid);
	FILE* f = fopen(path, "r");
	if (f == NULL) {
		return (uint64_t)-1;
	}
	char line[256];
	uint64_t blk = (uint64_t)-1;
	while (fgets(line, sizeof(line), f) != NULL) {
		if (sscanf(line, "SigBlk: %llx", (unsigned long long*)&blk) == 1) {
			break;
		}
	}
	fclose(f);
	return blk;
}

int main(int argc, char** argv) {
	if (access("/proc/self/task", F_OK) != 0) {
		printf("skipping: no /proc\n");
		return 0;
	}

	const char* lib = argc > 1 ? argv[1] : "./libtailscale.so";

	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = usr1_handler; // deliberately no SA_ONSTACK
	if (sigaction(SIGUSR1, &sa, NULL) != 0) {
		perror("sigaction");
		return 1;
	}

	void* handle = dlopen(lib, RTLD_NOW);
	if (handle == NULL) {
		printf("FAIL: dlopen: %s\n", dlerror());
		return 1;
	}

	// Right after the load: the library's constructor ran before the Go
	// runtime's (that is what gives Go threads the blocked mask below),
	// and the Go runtime has initialized. The loading thread's mask is
	// still blocked at this point: completing the isolation is the
	// embedder's one call — either tailscale_signal_restore(), or the first
	// tailscale_new()/TsnetNewServer() call does it automatically.
	sigset_t now;
	CHECK(pthread_sigmask(SIG_SETMASK, NULL, &now) == 0, "read thread mask");
	CHECK(sigismember(&now, SIGUSR1) == 1,
	      "loading thread mask still blocked right after load (isolation active)");

	// A signal delivered now pends; it must arrive once the mask is
	// restored, without being lost.
	kill(getpid(), SIGUSR1);

	// The one explicit step an embedder can take (bindings do this right
	// after loading; it also happens automatically on the first server
	// creation):
	void (*signal_restore)(void) = (void(*)(void))dlsym(handle, "tailscale_signal_restore");
	CHECK(signal_restore != NULL, "resolve tailscale_signal_restore");
	if (signal_restore != NULL) {
		signal_restore();
	}

	// SA_ONSTACK (added by the Go runtime's initsig during the load) must
	// be gone, and the host handler back to its exact pre-load disposition.
	struct sigaction cur;
	CHECK(sigaction(SIGUSR1, NULL, &cur) == 0, "read back SIGUSR1 disposition");
	CHECK(cur.sa_handler == usr1_handler, "host handler still installed");
	CHECK((cur.sa_flags & SA_ONSTACK) == 0,
	      "tailscale_signal_restore removed the Go runtime's SA_ONSTACK");

	CHECK(pthread_sigmask(SIG_SETMASK, NULL, &now) == 0, "read thread mask again");
	CHECK(sigismember(&now, SIGUSR1) == 0, "thread mask restored by tailscale_signal_restore");
	usleep(200 * 1000);
	CHECK(got_usr1 == 1, "SIGUSR1 sent during the blocked window was delivered after restore");

	// The Go package init repairs flags again, idempotently; make sure it
	// does not re-mutate them after a moment.
	usleep(300 * 1000);
	CHECK(sigaction(SIGUSR1, NULL, &cur) == 0 && (cur.sa_flags & SA_ONSTACK) == 0,
	      "SA_ONSTACK still absent after the Go package init ran");

	tailscale (*new_server)(void) = (tailscale(*)(void))dlsym(handle, "tailscale_new");
	CHECK(new_server != NULL, "resolve tailscale_new");
	tailscale sd = -1;
	if (new_server != NULL) {
		sd = new_server();
	}
	CHECK(sd >= 0, "tailscale_new works");

	// Go runtime threads (they have SIGURG unblocked for preemption) must
	// not accept host signals (SIGINT, SIGUSR1): they must have inherited
	// the constructor's blocked mask.
	int go_threads = 0, unisolated = 0;
	DIR* d = opendir("/proc/self/task");
	if (d != NULL) {
		struct dirent* de;
		while ((de = readdir(d)) != NULL) {
			int tid = atoi(de->d_name);
			if (tid <= 0 || tid == (int)getpid()) {
				continue; // this (host) thread
			}
			uint64_t blk = sigblk_of_tid(tid);
			if (blk == (uint64_t)-1) {
				continue;
			}
			int urg_unblocked = !((blk >> (SIGURG - 1)) & 1);
			int host_blocked = ((blk >> (SIGINT - 1)) & 1) && ((blk >> (SIGUSR1 - 1)) & 1);
			if (urg_unblocked) {
				go_threads++;
				if (!host_blocked) {
					unisolated++;
					printf("FAIL: go thread %d accepts host signals (SigBlk=%llx)\n",
					       tid, (unsigned long long)blk);
				}
			}
		}
		closedir(d);
	}
	CHECK(go_threads > 0, "Go runtime threads observed");
	CHECK(unisolated == 0, "Go threads inherited the blocked signal mask");

	int (*close_server)(tailscale) = (int(*)(tailscale))dlsym(handle, "tailscale_close");
	if (close_server != NULL && sd >= 0) {
		close_server(sd); // never started; early-returns
	}

	if (failures != 0) {
		printf("csigtest: %d FAILURES\n", failures);
		return 1;
	}
	printf("csigtest: all checks passed\n");
	return 0;
}
