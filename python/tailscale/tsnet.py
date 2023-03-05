# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

import io

from . import _tailscale

class TSNetException(Exception): pass


class TSNet:
    def __init__(self, ephemeral=False):
        self.ts = _tailscale.new()
        if ephemeral and _tailscale.set_ephemeral(self.ts, 1):
            raise TSNetException("Error setting ephemeral")

    def up(self):
        if _tailscale.up(self.ts):
            raise TSNetException("Error coming up")

    def listen(self, proto, addr):
        ln, err = _tailscale.listen(self.ts, proto, addr)
        if err:
            raise TSNetException("Error listening: %s on %s" % (proto, addr))
        return TSNetListener(ln)

    def close(self):
        if _tailscale.close(self.ts):
            raise TSNetException("Failed to close")


class TSNetListener:
    def __init__(self, ln):
        self.ln = ln

    def accept(self):
        fd, err = _tailscale.accept(self.ln)
        if err:
            raise TSNetException("Failed to accept conn")
        return fd

    def close(self):
        if _tailscale.close_listener(self.ln):
            raise TSNetException("Failed to close")
