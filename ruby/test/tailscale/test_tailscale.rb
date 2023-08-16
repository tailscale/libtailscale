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
    wait_status_running ts
    s = ts.listen("tcp", ":1999")
    s.close
    ts.close
  end

  def test_dial_sorta_works
    ts = newts
    ts.up
    wait_status_running ts
    c = ts.dial("udp", "100.100.100.100:53")
    c.close
    ts.close
  end

  def test_listen_accept_dial_close
      ts = newts
      ts.up
      wait_status_running ts
      hn = ts.local_api.status["Self"]["TailscaleIPs"][0]
      s = ts.listen "tcp", "#{hn}:1999"
      c = ts.dial "tcp", "#{hn}:1999"
      ss = s.accept
      c.write "hello"
      assert_equal "hello", ss.read(5)
      ss.write "world"
      assert_equal "world", c.read(5)
      ss.close
      c.close
      ts.close
  end

  def wait_status_running ts
    while ts.local_api.status["BackendState"] != "Running"
      sleep 0.01
    end
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
