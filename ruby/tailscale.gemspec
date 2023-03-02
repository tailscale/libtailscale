# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
# frozen_string_literal: true

require_relative "lib/tailscale/version"

Gem::Specification.new do |spec|
  spec.name = "tailscale"
  spec.version = Tailscale::VERSION
  spec.authors = ["Tailscale Inc & AUTHORS"]
  spec.email = ["support@tailscale.com"]

  spec.summary = "Tailscale in-process connections for Ruby"
  spec.description = "Tailscale in-process connections for Ruby"
  spec.homepage = "https://www.tailscale.com"
  spec.license = "BSD-3-Clause"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/tailscale/libtailscale/tree/main/ruby"
  spec.metadata["bug_tracker_uri"] = "https://github.com/tailscale/tailscale/issues"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end
  end
  spec.files += ["LICENSE"]
  spec.files += Dir["ext/libtailscale/*.{mod,sum,go}"]

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/libtailscale/extconf.rb"]

  spec.add_dependency "ffi", "~> 1.15.5"
end
