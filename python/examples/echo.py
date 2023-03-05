# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
# TODO(shayne): proper select/poll/epoll + os.set_blocking(conn, False)
import os
import select
from tailscale import TSNet

def handler(conn):
    while True:
        r, _, _ = select.select([conn], [], [], 10)
        if not conn in r:
            os._exit(0)
        data = os.read(conn, 2048)
        print(data.decode(), end="")


def main():
    procs = []

    ts = TSNet(ephemeral=True)
    ts.up()

    ln = ts.listen("tcp", ":1999")
    while True:
        while procs:
            pid, exit_code = os.waitpid(-1, os.WNOHANG)
            if pid == 0:
                break
            procs.remove(pid)

        conn = ln.accept()
        pid = os.fork()
        if pid == 0:
            return handler(conn)
        procs.append(pid)

    ln.close()
    ts.close()


if __name__ == "__main__":
    main()
