# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
# frozen_string_literal: true
require "test_helper"
require "fileutils"
require "tmpdir"

class TestTailscale < Minitest::Test
  def setup
    super
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    super
    FileUtils.remove_entry_secure(@tmpdir)
  end

  def test_that_it_has_a_version_number
    refute_nil(::Tailscale::VERSION)
  end

  def test_listen_sorta_works
    ts = newts
    ts.up
    s = ts.listen("tcp", ":1999")
    s.close
    ts.close
  end

  def test_dial_sorta_works
    ts = newts
    ts.up
    c = ts.dial("udp", "100.100.100.100:53")
    c.close
    ts.close
  end

  def newts
    t = Tailscale::new
    unless ENV["VERBOSE"]
      logfd = IO.sysopen("/dev/null", "w+")
      t.set_log_fd(logfd)
    end

    t.set_ephemeral(1)
    t.set_dir(@tmpdir)
    t.set_control_url($testcontrol_url)
    t
  end
end
