# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

# frozen_string_literal: true

# Signal-safety tests. These are self-contained and deliberately do NOT
# require "test_helper": they must run without the test control server so
# they can be exercised standalone (rake test:signals, make test-signals)
# and assert process-global behavior that requires a pristine process:
# handler flags, thread signal masks, and interruptibility of blocking
# calls.

require "minitest/autorun"
require "fileutils"
require "tmpdir"

require "tailscale"

# Host sigaction probing helpers for the SA_ONSTACK assertions below.
module SigactionProbe
  SA_ONSTACK = 0x08000000 # linux

  # glibc struct sigaction on x86_64 linux: handler(8), sa_mask(128),
  # sa_flags(int @136), sa_restorer(8). Only the flags offset is read.
  SIZE = 152
  FLAGS_OFFSET = 136

  def self.supported?
    RbConfig::CONFIG["host_os"].include?("linux") &&
      ["x86_64", "aarch64"].include?(RbConfig::CONFIG["target_cpu"])
  end

  def self.flags(sig)
    Libc.sigaction(sig, nil, @buf ||= FFI::MemoryPointer.new(SIZE))
    @buf.get_uint32(FLAGS_OFFSET)
  end

  module Libc
    extend FFI::Library
    ffi_lib FFI::Library::LIBC
    attach_function :sigaction, [:int, :pointer, :pointer], :int
  end
end

# Tests that the Ruby process's own signal handling keeps working exactly
# as before the libtailscale (Go c-shared) library was loaded, that the
# load-time signal isolation took effect, and that blocking calls can be
# interrupted.
class TestSignalSafety < Minitest::Test
  def setup
    super
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    super
    FileUtils.remove_entry_secure(@tmpdir) if File.directory?(@tmpdir)
  end

  def test_traps_still_work_after_library_load
    ran = 0
    old_int = Signal.trap("INT") { ran += 1 }
    old_usr1 = Signal.trap("USR1") { ran += 1 }
    begin
      Process.kill("INT", $$)
      Process.kill("USR1", $$)
      sleep 0.05 # trap handlers run at the next safe point
      assert_equal 2, ran, "host signal traps must keep firing after libtailscale loads"
    ensure
      Signal.trap("INT", old_int)
      Signal.trap("USR1", old_usr1)
    end
  end

  def test_go_did_not_add_sa_onstack_to_host_handlers
    skip("host sigaction ABI unknown") unless SigactionProbe.supported?

    # The Go runtime adds SA_ONSTACK to every caught host handler at library
    # load; libtailscale must have removed it again (its constructor
    # snapshots the host dispositions and tailscale_signal_restore — called
    # by the gem at load, or by the Go package init — restores them).
    ran = 0
    old = Signal.trap("USR2") { ran += 1 }
    begin
      flags = SigactionProbe.flags(Signal.list.fetch("USR2"))
      assert_equal 0, flags & SigactionProbe::SA_ONSTACK,
                   "Go runtime SA_ONSTACK leaked onto a host signal handler"
    ensure
      Signal.trap("USR2", old)
    end
  end

  # A pristine child process requires the library and reports every
  # thread's signal mask. Go threads must have inherited the constructor's
  # blocked mask (everything blocked except the signals the Go runtime
  # needs), so that host signals are only ever delivered to host threads.
  # The main (host) thread's own mask must already be restored when the
  # require returns: the gem calls tailscale_signal_restore right after
  # loading the library.
  def test_go_threads_inherited_the_blocked_mask
    skip("linux only") unless RbConfig::CONFIG["host_os"].include?("linux")

    script = <<~'RUBY'
      require "tailscale"
      main_blk = File.read("/proc/self/status")[/^SigBlk:\s+([0-9a-f]+)/, 1].to_i(16)
      puts "main_blocked=#{main_blk != 0}"
      Tailscale.new
      int_bit = 1 << (Signal.list.fetch("INT") - 1)
      urg_bit = 1 << (Signal.list.fetch("URG") - 1)
      go_threads = 0
      Dir.children("/proc/self/task").each do |tid|
        # The main thread is the host's own thread: host signals
        # delivered to it is exactly what the isolation is for.
        next if tid.to_i == Process.pid
        blk = File.read("/proc/self/task/#{tid}/status")[/^SigBlk:\s+([0-9a-f]+)/, 1].to_i(16)
        # Go runtime threads unblock SIGURG (their preemption signal); a
        # Go thread that also has SIGINT unblocked means the load-time
        # signal isolation did not take effect.
        if (blk & urg_bit) == 0 && (blk & int_bit) == 0
          puts "BAD: tid #{tid} accepts host signals (SigBlk=#{blk})"
        end
        go_threads += 1 if (blk & urg_bit) == 0
      end
      puts "go_threads=#{go_threads}"
    RUBY

    out, ok = run_child(script)
    assert ok, "child ruby failed:\n#{out}"
    assert_equal "main_blocked=false", out[/^main_blocked=(\w+)$/, 0],
                 "the loading thread's mask must be restored when require returns:\n#{out}"
    assert_empty out.lines.grep(/^BAD:/), "Go threads with host signals unblocked:\n#{out}"
    assert_match(/^go_threads=\d+$/, out)
    refute_equal "go_threads=0", out[/^go_threads=(\d+)$/, 0],
                 "no Go threads observed; test could not verify isolation"
  end

  # The irb failure mode this whole exercise exists for: TsnetUp blocking
  # forever, with Ctrl+C doing nothing. With the cancellable API, an
  # interrupt (here simulated with Thread#raise, the same mechanism Ctrl+C
  # uses to interrupt the main thread) must cancel the Go call and surface.
  def test_interrupt_cancels_up
    ts = new_unreachable_server
    main = Thread.current
    kicker = Thread.new { sleep 0.5; main.raise(Interrupt, "simulated ctrl+c") }
    begin
      # The server never comes up (unreachable control URL); without
      # cancellation this would hang for minutes.
      assert_raises(Interrupt) { ts.up }
    ensure
      kicker.join
      ts.close
    end
  end

  def test_up_timeout_returns_promptly
    ts = new_unreachable_server
    begin
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(Tailscale::Error) { ts.up(timeout: 0.5) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_match(/deadline|timeout/i, ts.errmsg)
      assert_operator elapsed, :<, 10, "up(timeout: 0.5) took #{elapsed.round(1)}s to give up"
      assert_operator elapsed, :>=, 0.4, "up returned before its deadline expired"
    ensure
      ts.close
    end
  end

  def test_cancel_is_a_noop_when_idle
    ts = Tailscale.new
    begin
      assert_equal 2, ts.cancel, "expected ENOENT when there is no pending operation to cancel"
    ensure
      ts.close
    end
  end

  private

  # A server pointed at an unreachable control URL, so that up blocks
  # indefinitely (until canceled or timed out) without needing testcontrol.
  def new_unreachable_server
    ts = Tailscale.new
    ts.set_dir(@tmpdir)
    ts.set_hostname("signal-safety-test")
    ts.set_control_url("http://127.0.0.1:1")
    ts.set_ephemeral(true)
    ts.set_log_fd(IO.sysopen(File::NULL, "w"))
    ts
  end

  def run_child(script)
    out = IO.popen([RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", script],
                   err: [:child, :out], &:read)
    [out, $?.success?]
  end
end
