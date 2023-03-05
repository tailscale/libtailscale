# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 3.4...3.18)
project(tailscale)

add_subdirectory(pybind11)

link_directories(.)

pybind11_add_module(_tailscale src/main.cpp)

target_link_libraries(_tailscale PRIVATE tailscale)

target_compile_definitions(_tailscale PRIVATE VERSION_INFO=${TAILSCALE_VERSION_INFO})

target_include_directories(_tailscale PRIVATE .)
