# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

import io
import threading

from . import _tailscale


class TSNetException(Exception): pass


class TSNet:
    def __init__(self, ephemeral=False):
        self.ts = _tailscale.new()
        if ephemeral and _tailscale.set_ephemeral(self.ts, 1):
            raise TSNetException("Error setting ephemeral")

    def up(self, timeout_ms=None):
        """Bring the tailscale server up and wait for it to be usable.

        If timeout_ms is given, the call blocks at most that many
        milliseconds. While blocked, the call stays responsive to
        interrupts such as KeyboardInterrupt (Ctrl+C): the underlying Go
        call runs on a helper thread and is canceled if this thread is
        interrupted, after which the interrupt is re-raised.
        """
        if timeout_ms is not None:
            rv = self._call_interruptible(lambda: _tailscale.up_timeout(self.ts, timeout_ms))
        else:
            rv = self._call_interruptible(lambda: _tailscale.up(self.ts))
        if rv:
            raise TSNetException("Error coming up")

    def listen(self, proto, addr):
        ln, err = _tailscale.listen(self.ts, proto, addr)
        if err:
            raise TSNetException("Error listening: %s on %s" % (proto, addr))
        return TSNetListener(ln)

    def close(self):
        if _tailscale.close(self.ts):
            raise TSNetException("Failed to close")

    def cancel(self):
        """Cancel the most recent pending up (or dial), making it return
        a canceled error. Also performed automatically by close() and
        when an interrupted up() is winding down."""
        return _tailscale.cancel(self.ts)

    def _call_interruptible(self, fn):
        """Run a blocking libtailscale call on a helper thread so this
        thread stays responsive to interrupts (KeyboardInterrupt et al.)
        while the Go call blocks. If interrupted, the Go call is canceled
        with tailscale cancel and the interrupt is re-raised.

        Requires a libtailscale with the cancel API; falls back to a
        plain blocking call otherwise."""
        if not hasattr(_tailscale, "cancel"):
            return fn()

        result = {}

        def worker():
            try:
                result["rv"] = fn()
            except BaseException as e:
                result["exc"] = e

        t = threading.Thread(target=worker, daemon=True)
        t.start()
        try:
            t.join()
        except BaseException:
            _tailscale.cancel(self.ts)
            # Bound the wait: a canceled call returns promptly, but a
            # wedged runtime must not turn an interrupt into a new hang.
            t.join(10)
            raise
        if "exc" in result:
            raise result["exc"]
        return result.get("rv")


class TSNetListener:
    def __init__(self, ln):
        self.ln = ln

    def accept(self):
        fd, err = _tailscale.accept(self.ln)
        if err:
            raise TSNetException("Failed to accept conn")
        return fd
