// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include <pybind11/pybind11.h>
#include "libtailscale.h"
#include <sys/socket.h>
#include <unistd.h>

#define STRINGIFY(x) #x
#define MACRO_STRINGIFY(x) STRINGIFY(x)

namespace py = pybind11;

// tailscale_accept 
static int accept_connection(int ld, int* conn_out) {
    struct msghdr msg = {0};

    char mbuf[256];
    struct iovec io = { .iov_base = mbuf, .iov_len = sizeof(mbuf) };
    msg.msg_iov = &io;
    msg.msg_iovlen = 1;

    char cbuf[256];
    msg.msg_control = cbuf;
    msg.msg_controllen = sizeof(cbuf);

    if (recvmsg(ld, &msg, 0) == -1) {
        return -1;
    }

    struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
    unsigned char* data = CMSG_DATA(cmsg);

    int fd = *(int*)data;
    *conn_out = fd;
    return 0;
}

PYBIND11_MODULE(_tailscale, m) {
    m.doc() = R"pbdoc(
        Embedded Tailscale
        -----------------------

        .. currentmodule:: _tailscale

        .. autosummary::
           :toctree: _generate
    )pbdoc";

    m.def("new", &TsnetNewServer, R"pbdoc(
        Create a new tsnet server
    )pbdoc");

    m.def("start", &TsnetStart, R"pbdoc(
        Starts a tsnet server
    )pbdoc");

    m.def("up", &TsnetUp, R"pbdoc(
        Brings the given tsnet server up
    )pbdoc");

    m.def("close", &TsnetClose, R"pbdoc(
        Closes a given tsnet server
    )pbdoc");

    m.def("err_msg", &TsnetErrmsg, R"pbdoc(
        Get error message for a server
    )pbdoc");

    m.def("listen", [](int sd, char* network, char* addr) { int listenerOut; int rv = TsnetListen(sd, network, addr, &listenerOut); return std::make_tuple(listenerOut, rv); }, R"pbdoc(
        Listen on a given protocol and port
    )pbdoc");

    m.def("accept", [](int ld) { int connOut; int rv = accept_connection(ld, &connOut); return std::make_tuple(connOut, rv);}, R"pbdoc(
        Accept a given listener and connection
    )pbdoc");

    m.def("dial", [](int sd, char* network, char* addr) { int connOut; int rv = TsnetDial(sd, network, addr, &connOut); return std::make_tuple(connOut, rv); }, R"pbdoc(
        Dial a connection on the tailnet
    )pbdoc");

    m.def("set_dir", &TsnetSetDir, R"pbdoc(
        Set the state directory
    )pbdoc");

    m.def("set_hostname", &TsnetSetHostname, R"pbdoc(
        Set the hostname
    )pbdoc");

    m.def("set_authkey", &TsnetSetAuthKey, R"pbdoc(
        Set the auth key
    )pbdoc");

    m.def("set_control_url", &TsnetSetControlURL, R"pbdoc(
        Set the control URL
    )pbdoc");

    m.def("set_ephemeral", &TsnetSetEphemeral, R"pbdoc(
        Set the given tsnet server to be an ephemeral node.
    )pbdoc");

    m.def("set_log_fd", &TsnetSetLogFD, R"pbdoc(
        Set the log file descriptor
    )pbdoc");

    m.def("loopback", &TsnetLoopback, R"pbdoc(
        Start a loopback server
    )pbdoc");

#ifdef VERSION_INFO
    m.attr("__version__") = MACRO_STRINGIFY(VERSION_INFO);
#else
    m.attr("__version__") = "dev";
#endif
}
