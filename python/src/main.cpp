// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include <pybind11/pybind11.h>
#include "libtailscale.h"

#define STRINGIFY(x) #x
#define MACRO_STRINGIFY(x) STRINGIFY(x)

namespace py = pybind11;

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

    )pbdoc");

    m.def("listen", [](int sd, char* network, char* addr) { int listenerOut; int rv = TsnetListen(sd, network, addr, &listenerOut); return std::make_tuple(listenerOut, rv); }, R"pbdoc(
        Listen on a given protocol and port
    )pbdoc");

    m.def("close_listener", &TsnetListenerClose, R"pbdoc(
        Create a new tsnet server
    )pbdoc");

    m.def("accept", [](int ld) { int connOut; int rv = TsnetAccept(ld, &connOut); return std::make_tuple(connOut, rv);}, R"pbdoc(
        Accept a given listener and connection
    )pbdoc");

    m.def("dial", &TsnetDial, R"pbdoc(

    )pbdoc");

    m.def("set_dir", &TsnetSetDir, R"pbdoc(

    )pbdoc");

    m.def("set_hostname", &TsnetSetHostname, R"pbdoc(

    )pbdoc");

    m.def("set_authkey", &TsnetSetAuthKey, R"pbdoc(

    )pbdoc");

    m.def("set_control_url", &TsnetSetControlURL, R"pbdoc(

    )pbdoc");

    m.def("set_ephemeral", &TsnetSetEphemeral, R"pbdoc(
        Set the given tsnet server to be an ephemeral node.
    )pbdoc");

    m.def("set_log_fd", &TsnetSetLogFD, R"pbdoc(

    )pbdoc");

    m.def("loopback_api", &TsnetLoopbackAPI, R"pbdoc(

    )pbdoc");

#ifdef VERSION_INFO
    m.attr("__version__") = MACRO_STRINGIFY(VERSION_INFO);
#else
    m.attr("__version__") = "dev";
#endif
}
