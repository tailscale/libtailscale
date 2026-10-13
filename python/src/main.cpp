// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

#include <pybind11/pybind11.h>
#include "libtailscale.h"

#define STRINGIFY(x) #x
#define MACRO_STRINGIFY(x) STRINGIFY(x)

namespace py = pybind11;

// From libtailscale's tailscale.c (see SIGNALS.md): completes the host-
// signal isolation the library constructor started while loading, by
// restoring this (importing) thread's signal mask. Also ensures the
// object containing the constructor is linked in from the archive.
extern "C" void tailscale_signal_restore(void);

PYBIND11_MODULE(_tailscale, m) {
    // Must run on the importing thread, right after load.
    tailscale_signal_restore();

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
    )pbdoc", py::call_guard<py::gil_scoped_release>());

    // The up/dial/accept calls below block, possibly indefinitely. They
    // must not hold the GIL while doing so, or the interpreter cannot run
    // other threads, process signals, or (with the cancel API below) be
    // interrupted at all.
    m.def("up", &TsnetUp, R"pbdoc(
        Brings the given tsnet server up
    )pbdoc", py::call_guard<py::gil_scoped_release>());

    m.def("up_timeout", &TsnetUpTimeout, R"pbdoc(
        Brings the given tsnet server up, blocking at most timeout_ms
        milliseconds (timeout_ms <= 0 means no deadline)
    )pbdoc", py::call_guard<py::gil_scoped_release>());

    m.def("cancel", &TsnetCancel, R"pbdoc(
        Cancels the most recent pending up or dial on the server
    )pbdoc");

    m.def("close", &TsnetClose, R"pbdoc(
        Closes a given tsnet server
    )pbdoc", py::call_guard<py::gil_scoped_release>());

    m.def("err_msg", &TsnetErrmsg, R"pbdoc(

    )pbdoc");

    m.def("listen", [](int sd, char* network, char* addr) { int listenerOut; int rv = TsnetListen(sd, network, addr, &listenerOut); return std::make_tuple(listenerOut, rv); }, R"pbdoc(
        Listen on a given protocol and port
    )pbdoc", py::call_guard<py::gil_scoped_release>());

    m.def("accept", [](int ld) { int connOut; int rv = TsnetAccept(ld, &connOut); return std::make_tuple(connOut, rv);}, R"pbdoc(
        Accept a given listener and connection
    )pbdoc", py::call_guard<py::gil_scoped_release>());

    m.def("dial", &TsnetDial, R"pbdoc(

    )pbdoc", py::call_guard<py::gil_scoped_release>());

    m.def("dial_timeout", [](int sd, char* network, char* addr, long long timeoutMs) { int connOut; int rv = TsnetDialTimeout(sd, network, addr, timeoutMs, &connOut); return std::make_tuple(connOut, rv); }, R"pbdoc(
        Dial an address, blocking at most timeout_ms milliseconds
        (timeout_ms <= 0 means no deadline)
    )pbdoc", py::call_guard<py::gil_scoped_release>());

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

    m.def("loopback", &TsnetLoopback, R"pbdoc(

    )pbdoc");

#ifdef VERSION_INFO
    m.attr("__version__") = MACRO_STRINGIFY(VERSION_INFO);
#else
    m.attr("__version__") = "dev";
#endif
}
