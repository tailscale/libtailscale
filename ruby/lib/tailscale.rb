# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
# frozen_string_literal: true

require 'tailscale/version'
require 'ffi'
require 'rbconfig'

# Tailscale provides an embedded tailscale network interface for ruby programs.
class Tailscale 

    # Libtailscale is a FFI wrapper around the libtailscale C library.
    module Libtailscale
        extend FFI::Library

        # In development or in precompiled gems the library is in the lib
        # directory, and when installed by rubygems it's in the ruby site lib
        # directory.
        [__dir__, RbConfig::CONFIG['sitelibdir']].find do |dir|
            lib = File.expand_path("libtailscale.#{RbConfig::CONFIG["DLEXT"]}", dir)
            if File.exist?(lib)
                ffi_lib lib
                true
            end
        end

        attach_function :TsnetNewServer, [], :int
        attach_function :TsnetStart, [:int], :int
        attach_function :TsnetUp, [:int], :int, blocking: true
        attach_function :TsnetClose, [:int], :int
        attach_function :TsnetSetDir, [:int, :string], :int
        attach_function :TsnetSetHostname, [:int, :string], :int
        attach_function :TsnetSetAuthKey, [:int, :string], :int
        attach_function :TsnetSetControlURL, [:int, :string], :int
        attach_function :TsnetSetEphemeral, [:int, :int], :int
        attach_function :TsnetSetLogFD, [:int, :int], :int
        attach_function :TsnetDial, [:int, :string, :string, :pointer], :int, blocking: true
        attach_function :TsnetListen, [:int, :string, :string, :pointer], :int
        attach_function :TsnetListenerClose, [:int], :int
        attach_function :TsnetAccept, [:int, :pointer], :int, blocking: true
        attach_function :TsnetErrmsg, [:int, :pointer, :size_t], :int
    end

    class ClosedError < StandardError
        def initialize
            super "tailscale error: the server is closed"
        end
    end

    class Error < StandardError
        attr_reader :code

        def initialize(msg, code = -1)
            @code = code
            super msg
        end

        def self.check(ts, code)
            return if code == 0

            if code == -1
                msg = ts.errmsg
            else
                msg = "tailscale error: code: #{code}"
            end
            raise Error.new(msg, code)
        end
    end

    # A listening socket on the tailscale network.
    class Listener
        # Create a new listener, user code should not call this directly,
        # instead use +Tailscale#listen+.
        def initialize(ts, listener)
            @ts = ts
            @listener = listener
        end

        # Accept a new connection. This method blocks until a new connection is
        # recieved. An +IO+ object is returned which can be used to read and
        # write.
        def accept
            @ts.assert_open
            conn = FFI::MemoryPointer.new(:int)
            Error.check @ts, Libtailscale::TsnetAccept(@listener, conn)
            IO::new conn.read_int
        end

        # Close the listener.
        def close
            @ts.assert_open
            Error.check @ts, Libtailscale::TsnetListenerClose(@listener)
        end
    end

    # Create a new tailscale server.
    #
    # The server is not started, and no network traffic will occur until start
    # is called or network operations are used (such as dial or listen).
    def initialize
        @t = Libtailscale::TsnetNewServer()
        raise Error.new("tailscale error: failed to initialize", @t) if @t < 0
    end

    # Start the tailscale server asynchronously.
    def start
        Error.check self, Libtailscale::TsnetStart(@t)
    end

    # Bring the tailscale server up and wait for it to be usable. This method
    # blocks until the node is fully authorized.
    def up
        Error.check self, Libtailscale::TsnetUp(@t)
    end

    # Close the tailscale server.
    def close
        Error.check self, Libtailscale::TsnetClose(@t)
        @t = -1
    end

    # Set the directory to store tailscale state in.
    def set_dir(dir)
        assert_open
        Error.check self, Libtailscale::TsnetSetDir(@t, dir)
    end

    # Set the hostname to use for the tailscale node.
    def set_hostname(hostname)
        assert_open
        Error.check self, Libtailscale::TsnetSetHostname(@t, hostname)
    end

    # Set the auth key to use for the tailscale node.
    def set_auth_key(auth_key)
        assert_open
        Error.check self, Libtailscale::TsnetSetAuthKey(@t, auth_key)
    end

    # Set the control URL the node will connect to.
    def set_control_url(control_url)
        assert_open
        Error.check self, Libtailscale::TsnetSetControlURL(@t, control_url)
    end

    # Set whether the node is ephemeral or not.
    def set_ephemeral(ephemeral)
        assert_open
        Error.check self, Libtailscale::TsnetSetEphemeral(@t, ephemeral ? 1 : 0)
    end

    # Set the file descriptor to use for logging. The file descriptor must be
    # open for writing. e.g. use `IO.sysopen("/dev/null", "w")` to disable
    # logging.
    def set_log_fd(log_fd)
        assert_open
        Error.check self, Libtailscale::TsnetSetLogFD(@t, log_fd)
    end

    # Dial a network address. +network+ is one of "tcp" or "udp". +addr+ is the
    # remote address to connect to, and +local_addr+ is the local address to
    # bind to. This method blocks until the connection is established.
    def dial(network, addr, local_addr)
        assert_open
        conn = FFI::MemoryPointer.new(:int)
        Error.check self, Libtailscale::TsnetDial(@t, network, addr, conn)
        IO::new conn.read_int
    end

    # Listen on a network address. +network+ is one of "tcp" or "udp". +addr+ is
    # the local address to bind to.
    def listen(network, addr)
        assert_open
        listener = FFI::MemoryPointer.new(:int)
        Error.check self, Libtailscale::TsnetListen(@t, network, addr, listener)
        Listener.new self, listener.read_int
    end

    # Get the last detailed error message from the tailscale server. This method
    # is typically not needed by user code, as the library will raise an
    # +Error+ with the error message.
    def errmsg
        buf = FFI::MemoryPointer.new(:char, 1024)
        r = Libtailscale::TsnetErrmsg(@t, buf, buf.size)
        if r != 0
            return "tailscale internal error: failed to get error message"
        end
        buf.read_string
    end

    # Check if the tailscale server is open.
    def assert_open
        raise ClosedError if @t <= 0
    end
end
