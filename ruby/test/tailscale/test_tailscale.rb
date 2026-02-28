# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
# frozen_string_literal: true
require "test_helper"
require "fileutils"
require "tmpdir"
require "timeout"

# TestTailscaleConfig tests configuration methods that don't require networking.
# Servers are never started so never need Close (tsnet panics on Close for
# unstarted servers).
class TestTailscaleConfig < Minitest::Test
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

  def test_new_returns_valid_server
    ts = Tailscale.new
    ts.set_hostname("test-new")
  end

  def test_set_dir
    Tailscale.new.set_dir(@tmpdir)
  end

  def test_set_hostname
    Tailscale.new.set_hostname("my-ruby-host")
  end

  def test_set_auth_key
    Tailscale.new.set_auth_key("tskey-auth-fake-key")
  end

  def test_set_ephemeral_true
    Tailscale.new.set_ephemeral(true)
  end

  def test_set_ephemeral_false
    Tailscale.new.set_ephemeral(false)
  end

  def test_set_control_url
    Tailscale.new.set_control_url($testcontrol_url)
  end

  def test_set_log_fd_file
    logfile = File.join(@tmpdir, "test.log")
    fd = IO.sysopen(logfile, "w+")
    Tailscale.new.set_log_fd(fd)
  end

  def test_set_log_fd_discard
    Tailscale.new.set_log_fd(-1)
  end

  def test_closed_error_on_set_dir
    assert_raises(Tailscale::ClosedError) { new_closed_ts.set_dir("/tmp") }
  end

  def test_closed_error_on_set_hostname
    assert_raises(Tailscale::ClosedError) { new_closed_ts.set_hostname("fail") }
  end

  def test_closed_error_on_set_auth_key
    assert_raises(Tailscale::ClosedError) { new_closed_ts.set_auth_key("fail") }
  end

  def test_closed_error_on_set_control_url
    assert_raises(Tailscale::ClosedError) { new_closed_ts.set_control_url("fail") }
  end

  def test_closed_error_on_set_ephemeral
    assert_raises(Tailscale::ClosedError) { new_closed_ts.set_ephemeral(true) }
  end

  def test_closed_error_on_set_log_fd
    assert_raises(Tailscale::ClosedError) { new_closed_ts.set_log_fd(-1) }
  end

  def test_closed_error_on_dial
    assert_raises(Tailscale::ClosedError) { new_closed_ts.dial("tcp", "127.0.0.1:80") }
  end

  def test_closed_error_on_listen
    assert_raises(Tailscale::ClosedError) { new_closed_ts.listen("tcp", ":1234") }
  end

  def test_closed_error_on_get_ips
    assert_raises(Tailscale::ClosedError) { new_closed_ts.get_ips }
  end

  def test_closed_error_on_loopback
    assert_raises(Tailscale::ClosedError) { new_closed_ts.loopback }
  end

  def test_error_class_attributes
    err = Tailscale::Error.new("test error", 42)
    assert_equal "test error", err.message
    assert_equal 42, err.code
  end

  def test_closed_error_message
    err = Tailscale::ClosedError.new
    assert_match(/closed/, err.message)
  end

  def test_errmsg_on_fresh_server
    msg = Tailscale.new.errmsg
    assert_kind_of String, msg
  end

  private

  # Simulate a closed server by setting the handle to -1 so assert_open
  # raises without needing to actually start and close a server.
  def new_closed_ts
    ts = Tailscale.new
    ts.instance_variable_set(:@t, -1)
    ts
  end
end

# TestTailscaleNetwork tests operations that require a running server.
# A single shared server is brought up once and used for all tests,
# including self-dial (listen + dial to own IP on the same node).
class TestTailscaleNetwork < Minitest::Test
  @@mu = Mutex.new
  @@server = nil
  @@ip = nil
  @@tmpdir = nil

  def self.ensure_server
    @@mu.synchronize do
      return if @@server
      @@tmpdir = Dir.mktmpdir

      dir = File.join(@@tmpdir, "s")
      FileUtils.mkdir_p(dir)
      ts = Tailscale.new
      unless ENV["VERBOSE"]
        logfd = IO.sysopen("/dev/null", "w+")
        ts.set_log_fd(logfd)
      end
      ts.set_ephemeral(true)
      ts.set_dir(dir)
      ts.set_control_url($testcontrol_url)
      ts.up

      deadline = Time.now + 30
      loop do
        break if ts.local_api.status["BackendState"] == "Running"
        raise "timed out waiting for BackendState Running" if Time.now > deadline
        sleep 0.05
      end

      @@server = ts
      @@ip = ts.local_api.status["Self"]["TailscaleIPs"][0]
    end
  end

  Minitest.after_run do
    @@mu.synchronize do
      @@server&.close rescue nil
      @@server = nil
      FileUtils.remove_entry_secure(@@tmpdir) if @@tmpdir
    end
  end

  def setup
    super
    self.class.ensure_server
  end

  def ts; @@server; end
  def ip; @@ip; end

  def test_start_async
    tmpdir = Dir.mktmpdir
    t = newts(tmpdir)
    t.start
    sleep 0.5
    t.close
    FileUtils.remove_entry_secure(tmpdir)
  end

  def test_up_and_close
    tmpdir = Dir.mktmpdir
    t = newts(tmpdir)
    t.up
    wait_running(t)
    assert_equal "Running", t.local_api.status["BackendState"]
    t.close
    assert_raises(Tailscale::ClosedError) { t.set_hostname("fail") }
    FileUtils.remove_entry_secure(tmpdir)
  end

  def test_set_hostname_visible_in_status
    tmpdir = Dir.mktmpdir
    t = newts(tmpdir)
    t.set_hostname("my-ruby-host")
    t.up
    wait_running(t)
    assert_match(/my-ruby-host/, t.local_api.status["Self"]["HostName"])
    t.close
    FileUtils.remove_entry_secure(tmpdir)
  end

  def test_get_ips
    ips = ts.get_ips
    assert_kind_of Array, ips
    refute_empty ips
    assert ips.any? { |i| i.start_with?("100.") },
      "expected a 100.x.y.z tailscale IPv4, got: #{ips}"
  end

  def test_loopback
    addr, proxy_cred, local_cred = ts.loopback
    assert_match(/:\d+$/, addr)
    assert_equal 32, proxy_cred.length
    assert_equal 32, local_cred.length
  end

  def test_local_api_client
    client = ts.local_api_client
    assert_kind_of Tailscale::LocalAPIClient, client
    refute_nil client.address
    refute_nil client.credential
    response = client.get("/localapi/v0/status")
    assert_equal "200", response.code
  end

  def test_local_api_status
    status = ts.local_api.status
    assert_kind_of Hash, status
    assert_equal "Running", status["BackendState"]
    assert_kind_of Hash, status["Self"]
    refute_empty status["Self"]["TailscaleIPs"]
  end

  def test_listen_and_close
    s = ts.listen("tcp", ":1999")
    s.close
  end

  def test_dial_udp
    c = ts.dial("udp", "100.100.100.100:53")
    c.close
  end

  def test_listen_accept_dial_data_transfer
    Timeout.timeout(30) do
      ln = ts.listen("tcp", "#{ip}:8081")
      c = ts.dial("tcp", "#{ip}:8081")
      c.sync = true
      ss = ln.accept
      ss.sync = true
      c.syswrite "hello"
      assert_equal "hello", ss.sysread(5)
      ss.syswrite "world"
      assert_equal "world", c.sysread(5)
      ss.close
      c.close
      ln.close
    end
  end

  def test_listen_accept_dial_large_data
    Timeout.timeout(30) do
      ln = ts.listen("tcp", "#{ip}:8082")
      c = ts.dial("tcp", "#{ip}:8082")
      c.sync = true
      ss = ln.accept
      ss.sync = true

      payload = "A" * 8192
      c.syswrite(payload)
      received = "".b
      while received.length < payload.length
        chunk = ss.sysread([payload.length - received.length, 65536].min)
        received << chunk
      end
      assert_equal payload.length, received.length
      assert_equal payload, received

      ss.close
      c.close
      ln.close
    end
  end

  def test_get_remote_addr
    Timeout.timeout(30) do
      ln = ts.listen("tcp", "#{ip}:8083")
      c = ts.dial("tcp", "#{ip}:8083")
      ss = ln.accept
      remote_addr = ln.get_remote_addr(ss)
      refute_nil remote_addr
      refute_empty remote_addr
      assert_match(/\d+\.\d+\.\d+\.\d+|\[.+\]/, remote_addr)
      ss.close
      c.close
      ln.close
    end
  end

  private

  def wait_running(t)
    deadline = Time.now + 30
    loop do
      break if t.local_api.status["BackendState"] == "Running"
      raise "timed out waiting for BackendState Running" if Time.now > deadline
      sleep 0.05
    end
  end

  def newts(dir)
    t = Tailscale.new
    unless ENV["VERBOSE"]
      logfd = IO.sysopen("/dev/null", "w+")
      t.set_log_fd(logfd)
    end
    t.set_ephemeral(true)
    t.set_dir(dir)
    t.set_control_url($testcontrol_url)
    t
  end
end
