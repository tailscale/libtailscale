# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
# frozen_string_literal: true
require 'test_helper'

class TestTailscale < Minitest::Test

    def test_that_it_has_a_version_number
        refute_nil ::Tailscale::VERSION
    end
    
    def test_listen_sorta_works
        # TODO: make a more useful test when we can make a client to connect with.
        ts = newts
        ts.start
        s = ts.listen "tcp", ":1999"
        s.close
        ts.close
    end

    def test_dial_sorta_works
        # TODO: make a more useful test when we can make a server to connect to.
        ts = newts
        ts.start
        c = ts.dial "udp", "100.100.100.100:53", ""
        c.close
        ts.close
    end

    def newts
        t = Tailscale::new
        unless ENV['VERBOSE']
            logfd = IO.sysopen("/dev/null", "w+")
            t.set_log_fd logfd
        end
        t
    end
end