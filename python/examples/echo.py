# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

import os
import signal
import sys
from tailscale import TSNet

def handler(conn):
    """Handle a single connection - echo all received data."""
    try:
        while True:
            data = conn.read(2048)
            if not data:  # Connection closed
                break
            try:
                print(data.decode('utf-8'), end="")
            except UnicodeDecodeError:
                print(data.decode('utf-8', errors='replace'), end="")
    finally:
        conn.close()


def main():
    def shutdown(signum, frame):
        print("\nShutting down...")
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    # Get auth key from environment
    # If not provided, library outputs an auth URL
    authkey = os.environ.get('TS_AUTHKEY')

    with TSNet(ephemeral=True, authkey=authkey) as ts:
        ts.up()

        with ts.listen("tcp", ":1999") as ln:
            print("Listening on :1999")
            while True:
                conn = ln.accept()
                handler(conn)


if __name__ == "__main__":
    main()
