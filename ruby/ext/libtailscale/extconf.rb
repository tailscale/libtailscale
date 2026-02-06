# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
# frozen_string_literal: true
require "rbconfig"

open("Makefile", "w") do |f|
  f.puts("libtailscale.#{RbConfig::CONFIG["DLEXT"]}:")
  f.puts("\tgo build -C #{File.expand_path(__dir__)} -buildmode=c-shared -o \"#{Dir.pwd}/$@\" .")

  f.puts("install: libtailscale.#{RbConfig::CONFIG["DLEXT"]}")
  f.puts("\tmkdir -p \"#{RbConfig::CONFIG["sitelibdir"]}\"")
  f.puts("\tcp libtailscale.#{RbConfig::CONFIG["DLEXT"]} \"#{RbConfig::CONFIG["sitelibdir"]}/\"")
end
