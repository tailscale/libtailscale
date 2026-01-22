# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

"""
Tailscale embedded network interface for Python.

This module provides a Python interface to run an embedded Tailscale node
within your application, allowing you to listen for and dial connections
to other nodes on your tailnet.
"""

import io
import os

from . import _tailscale


class TSNetException(Exception):
    """Exception raised for Tailscale errors."""
    pass


class TSNet:
    """
    Tailscale network server.

    This class represents an embedded Tailscale node. Use it to connect to
    your tailnet and listen for or dial connections to other nodes.

    Example:
        with TSNet(ephemeral=True) as ts:
            ts.set_authkey(os.environ['TS_AUTHKEY'])
            ts.up()

            with ts.listen("tcp", ":1999") as ln:
                conn = ln.accept()
                data = conn.read(1024)
    """

    def __init__(self, ephemeral=False, authkey=None, hostname=None, dir=None):
        """
        Create a new Tailscale server.

        Args:
            ephemeral: If True, this node will be removed when it disconnects
            authkey: Optional auth key for automatic authentication
            hostname: Optional hostname for this node
            dir: Optional directory for storing Tailscale state
        """
        self.ts = _tailscale.new()
        if self.ts < 0:
            raise TSNetException("Failed to create Tailscale server")

        if ephemeral and _tailscale.set_ephemeral(self.ts, 1):
            raise TSNetException("Error setting ephemeral mode")

        if authkey:
            self.set_authkey(authkey)

        if hostname:
            self.set_hostname(hostname)

        if dir:
            self.set_dir(dir)

    def set_authkey(self, authkey):
        """
        Set the auth key for automatic node authentication.

        Args:
            authkey: Tailscale auth key (e.g., from admin console)
        """
        if _tailscale.set_authkey(self.ts, authkey):
            raise TSNetException("Failed to set auth key")

    def set_hostname(self, hostname):
        """
        Set the hostname for this Tailscale node.

        Args:
            hostname: Desired hostname for the node
        """
        if _tailscale.set_hostname(self.ts, hostname):
            raise TSNetException("Failed to set hostname")

    def set_dir(self, dir):
        """
        Set the directory for storing Tailscale state.

        Args:
            dir: Path to state directory
        """
        if _tailscale.set_dir(self.ts, dir):
            raise TSNetException("Failed to set state directory")

    def set_control_url(self, url):
        """
        Set the control server URL.

        Args:
            url: Control server URL
        """
        if _tailscale.set_control_url(self.ts, url):
            raise TSNetException("Failed to set control URL")

    def set_log_fd(self, fd):
        """
        Set the file descriptor for Tailscale logs.

        Args:
            fd: File descriptor for logging (use -1 to disable)
        """
        if _tailscale.set_log_fd(self.ts, fd):
            raise TSNetException("Failed to set log file descriptor")

    def up(self):
        """
        Bring up the Tailscale connection.

        This will block until the node is connected and ready to use.
        If an auth key was not provided, you may need to authenticate
        via the URL printed to the logs.
        """
        if _tailscale.up(self.ts):
            raise TSNetException("Failed to bring up Tailscale connection")

    def listen(self, proto, addr):
        """
        Listen for connections on the tailnet.

        Args:
            proto: Protocol ("tcp" or "udp")
            addr: Address to listen on (e.g., ":8080")

        Returns:
            TSNetListener object
        """
        ln, err = _tailscale.listen(self.ts, proto, addr)
        if err:
            raise TSNetException(f"Failed to listen on {proto} {addr}")
        return TSNetListener(ln)

    def close(self):
        """Close the Tailscale server and release resources."""
        if _tailscale.close(self.ts):
            raise TSNetException("Failed to close Tailscale server")

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager cleanup."""
        self.close()
        return False


class TSNetListener:
    """
    A listener for incoming connections on the tailnet.

    Use accept() to wait for and accept incoming connections.
    """

    def __init__(self, ln):
        """
        Create a listener (internal use only).

        Args:
            ln: Listener file descriptor from C library
        """
        self.ln = ln
        self._closed = False

    def accept(self):
        """
        Accept an incoming connection.

        This blocks until a connection is received.

        Returns:
            File object for reading/writing to the connection
        """
        if self._closed:
            raise TSNetException("Listener is closed")

        fd, err = _tailscale.accept(self.ln)
        if err:
            raise TSNetException("Failed to accept connection")

        return os.fdopen(fd, 'rb+', buffering=0)

    def close(self):
        """Close the listener."""
        if not self._closed:
            os.close(self.ln)
            self._closed = True

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - ensures cleanup."""
        self.close()
        return False
