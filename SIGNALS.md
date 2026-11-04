# libtailscale and host signal handling

libtailscale embeds a Go runtime (`tsnet`) into non-Go host processes, as
a c-shared library (`.so`), a c-archive (`.a`), or through the Ruby and
Python bindings. The Go runtime initializes at library load time and makes
process-global changes to signal state. This document describes exactly
what changes, what libtailscale does to keep host signal handling intact,
and what embedders need to know.

## What the Go runtime does at library load

With a modern Go toolchain (this is Go 1.27 behavior; older toolchains were
more invasive), a Go c-shared/c-archive library:

* **Installs its own handlers only for** `SIGILL`, `SIGBUS`, `SIGFPE`,
  `SIGSEGV`, `SIGPIPE` and `SIGURG`. It needs these for its own fault
  recovery (stack growth, panics), its preemption signal (`SIGURG`), and
  SIGPIPE semantics. Signals raised on host threads are forwarded to the
  handler the host had installed at load time, and if the host had no
  handler (SIG_DFL), the signal is re-raised with the default action: a
  broken-pipe write still kills the process, a stack-overflow guard
  (e.g. Ruby's `SystemStackError`) still works.
* **Adds `SA_ONSTACK` to the flags of every other *caught* host handler**
  (e.g. Ruby's `SIGINT` trap), so that if such a signal is delivered while
  running on a Go stack, the host handler runs on a valid alternate stack.
  The handler function itself is left in place; only its flags change.
* **Snapshots the loading thread's signal mask** to seed the mask of every
  thread the Go runtime creates. Hosts typically run with no signals
  blocked, so **Go threads come up with all signals unblocked** and accept
  process-directed signals, routing them through the Go runtime's signal
  trampoline (and, because of the `SA_ONSTACK` flag change, onto whatever
  alternate signal stack the delivering thread happens to have) instead of
  delivering them directly to host threads.

## What libtailscale does about it

### Cancelable blocking calls

The biggest practical problem for host runtimes is not the handler table:
`Ctrl+C` in irb "stops working" mainly because `up()`/`dial()` block in a
cgo call that the host runtime cannot interrupt. The Ruby trap fires, but
the interpreter thread sitting in the FFI call can never return to a safe
point.

The C API therefore has explicit cancellation:

* `tailscale_up_timeout(sd, timeout_ms)` — like `tailscale_up`, but blocks
  at most `timeout_ms` milliseconds (`<= 0` means no deadline).
* `tailscale_dial_timeout(sd, network, addr, timeout_ms, conn_out)` —
  same for dial.
* `tailscale_cancel(sd)` — interrupts the most recent pending up/dial,
  making it return a `context canceled` error. `ENOENT` if nothing is
  pending.
* `tailscale_close(sd)` also cancels pending operations, so it cannot
  hang behind a `up()` that would otherwise never finish (e.g. no
  authkey, waiting for interactive login).

The Ruby and Python bindings run blocking calls on a helper thread and
call `cancel` if the calling thread is interrupted (`Ctrl+C`,
`Timeout.timeout`, `KeyboardInterrupt`), then re-raise the interrupt. A
canceled up may leave the server partially started; create a new server
after such a failure.

### Built-in signal-state isolation

The signal-state isolation lives inside the library (`tailscale.c`), so
embedders and bindings do not have to reimplement it:

1. **`__attribute__((constructor(101)))` in `tailscale.c`** runs before
   the Go runtime's own (unprioritized) library constructor: it
   snapshots the dispositions of the host's caught signal handlers and
   blocks every signal on the loading thread. The thread the Go runtime
   creates during its constructor inherits that mask, and it seeds every
   thread the Go runtime creates later, so Go threads only ever accept
   the signals the Go runtime needs (the synchronous fault signals and
   its preemption signal). Host signals are only ever delivered to host
   threads, where the host's own handlers run directly.
2. **The Go package `init()`** repairs the `SA_ONSTACK` flag the Go
   runtime added to caught host handlers (the library exports its
   snapshot to it via `ts_signal_flags_restore`). This runs
   asynchronously just after the load completes; the synchronous
   guarantee comes from:
3. **`tailscale_signal_restore()`** — restores the loading thread's
   signal mask (masks are per-thread, so only the loading thread can do
   this) and re-runs the flag repair. It is called automatically by the
   first `tailscale_new()` / Go-side `TsnetNewServer()` call — the one
   entry point every embedder must use — and bindings call it
   explicitly right after loading the library so host signal handling
   is fully live immediately (e.g. `Ctrl+C` at the irb prompt between
   `require "tailscale"` and the first server creation).

If the constructor ordering does not hold on some platform/linker, the
result is a graceful fallback to today's Go behavior (Go threads
unmasked, `SA_ONSTACK` left in place) — never a worse state.

Notes on the two pieces embedders used to be told to do themselves:

* Ruby previously did both steps binding-side via
  `Tailscale::SignalSafety`; that module is gone, and the gem's only
  remaining obligation is the one `tailscale_signal_restore` call after
  `ffi_lib`.
* Python gets the same treatment from the pybind module init
  (`main.cpp` calls `tailscale_signal_restore()` at import, which also
  makes the linker pull in the object containing the constructor).
* Python deliberately does not rewrite sigaction flags beyond the
  library's own repair: CPython installs no alternate stacks, so the
  flag would be inert there anyway.

### Never link `os/signal`

If Go code in the library calls `signal.Notify`, the Go runtime installs a
handler for the notified signal and steals it from the host — silently
breaking, e.g., `SIGTERM` handling. libtailscale must never (transitively)
import `os/signal`. `make check-signals` enforces this and runs as part of
`make test` and `make test-go`.

## What embedders should know

**dlopen (c-shared, ctypes, FFI):** the library's constructor isolates
signal state during the load itself. To have host signal handling fully
live immediately after the load (rather than at the first server
creation), call the one exported function from the thread that loaded
the library:

```c
void* handle = dlopen("libtailscale.so", RTLD_NOW);
// signals are snapshotted and the loading thread's mask is still blocked:
tailscale_signal_restore();  // resolve from the same handle
```

The first `tailscale_new()` (or Go-side `TsnetNewServer()`) call does
this automatically, so embedders that immediately create a server can
skip even that.

**c-archive (linking libtailscale.a, e.g. Swift/iOS):** same mechanics —
the constructor runs at program startup, before the Go runtime
initializes, and the first `tailscale_new()`/`TsnetNewServer()` call
restores the main thread's mask. Embedders that link the archive but
reference only `Tsnet*` symbols directly (e.g. some FFI-style bindings)
must make sure `tailscale.o` is actually linked in, or they get the
unisolated legacy behavior: the archive's object is only pulled in when
a `tailscale_*` symbol is referenced.

**fork():** the Go runtime does not survive `fork()`. Do not call into
libtailscale from forked children; `exec` is fine.

**SIGURG:** the Go runtime uses `SIGURG` for goroutine preemption and
does not forward host `SIGURG` handlers reliably. If your host
application needs `SIGURG`, the process must be started with
`GODEBUG=asyncpreemptoff=1` in the environment (it cannot be set from
within a library, after runtime init), trading Go-side preemption for the
signal. This is rare enough that libtailscale does not do it by default.

**SIGSEGV/SIGBUS/SIGFPE/SIGILL/SIGPIPE:** these belong to the Go runtime
while the library is loaded. Host handlers are forwarded (host
stack-overflow guards keep working), but installing a *new* host handler
for them after load is not reliable. Hosts that require their own
`SIGSEGV` handler (some JVM configurations) should treat embedding a Go
runtime as incompatible.

## Testing

* `make check-signals` — fails the build if `os/signal` is linked.
* `make test-signals` (also part of `make test`) — runs the C embedder
  verification (`csigtest/main.c`: constructor ordering, mask inheritance
  and restoration, `SA_ONSTACK` repair, pending-signal delivery, all via
  `dlopen`) and the Ruby suite `ruby/test/test_signal_safety.rb` (traps
  keep firing, flags clean, Go threads masked in a pristine child
  process, `up` interruptible).
* `go test ./...` — exercises `tailscale_up_timeout`/`tailscale_cancel`/
  close-cancels-up through the C API (`tsnetctest`).
