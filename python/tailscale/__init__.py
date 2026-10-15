# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

# The extension module (_tailscale) links the libtailscale c-archive, whose
# constructor isolates host signal state while the Go runtime initializes,
# and whose module init below completes the isolation by restoring this
# thread's signal mask. Python signal handling works unchanged; see
# SIGNALS.md in the libtailscale repository.
from .tsnet import TSNet, TSNetException
