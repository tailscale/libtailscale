# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
# frozen_string_literal: true

require "tailscale"

# start a single global testcontrol instance which is far from a best practice,
# but this avoids some issues with signal propagation between ruby, threads, and
# the go runtime.
#
# grumpy. https://github.com/golang/go/issues/40467
unless system(*"go install tailscale.com/cmd/testcontrol")
  raise "failed to go install testcontrol"
end
gobin = `go env GOBIN`.strip
if gobin == ""
  gobin = `go env GOPATH`.strip + "/bin"
end

path = gobin + "/testcontrol"
if !File.executable? path
  raise "#{path} is not an executable"
end
pid = Process.spawn(path)
at_exit do
  begin
    Process.kill(0, pid)
  rescue Errno::ESRCH
    raise "testcontrol exited prematurely"
  end
  Process.kill(:TERM, pid)
  Process.wait(pid)
end
$testcontrol_url = "http://127.0.0.1:9911"
require "net/http"
attempts = 0
until (Net::HTTP::get(URI.parse($testcontrol_url + "/key")) rescue nil)
  sleep 0.001
  attempts+=1
  begin
    Process.kill(0, pid)
  rescue Errno::ESRCH
    raise "testcontrol exited prematurely"
  end
  if attempts == 10000
    raise "timed out waiting for testcontrol http to start"
  end
end

require "minitest"
Minitest.autorun
