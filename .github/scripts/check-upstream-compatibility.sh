#!/usr/bin/env bash
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

cd "$(dirname "$0")/../.."

# Fail early if a job did not receive the exact dependency update being tested.
actual=$(go list -m -f '{{.Version}}' tailscale.com)
printf 'tailscale.com=%s (expected %s)\n' "$actual" "$TAILSCALE_VERSION"
test "$actual" = "$TAILSCALE_VERSION"
go version
go env GOOS GOARCH CGO_ENABLED

# The Swift make recipes pipe xcodebuild through a formatter. Propagate failures
# through those pipelines and through recursive make invocations.
swift_make() {
    # Put flags in SHELL for compatibility with macOS's GNU make 3.81.
    make -C swift 'SHELL=/bin/bash -eu -o pipefail' "$@"
}

swift_sample() {
    xcodebuild build \
        -project swift/Examples/TailscaleKitHello/TailscaleKitHello.xcodeproj \
        -scheme "$1" \
        -configuration Release \
        -derivedDataPath "swift/sample-build-$2" \
        -destination "$3" \
        CODE_SIGNING_ALLOWED=NO
}

case "${1:?expected a compatibility suite}" in
    go-c)
        go test -v -count=1 -timeout 15m ./...
        make c-archive shared
        cc -Wall -Wextra -o "$RUNNER_TEMP/libtailscale-echo" \
            example/echo_server.c libtailscale.a -lpthread -ldl -lm
        ;;
    ruby)
        (cd ruby && bundle exec rake build test)
        ruby -c ruby/bin/echo_server
        ;;
    python)
        # Use the binding's documented, pinned pybind11 checkout and build path.
        make -C python build
        python -m pip wheel --no-deps ./python --wheel-dir "$RUNNER_TEMP/wheels"
        # Run outside python/ so the import resolves to the installed package.
        python -c 'from tailscale import TSNet; assert callable(TSNet)'
        python -m py_compile python/examples/echo.py
        ;;
    source-package)
        make -C sourcepkg check
        ;;
    swift-tests)
        test "$(uname -m)" = arm64
        swift_make test
        ;;
    swift-macos)
        test "$(uname -m)" = arm64
        swift_make macos
        swift_sample HelloFromTailscale_macOS macos 'platform=macOS,arch=arm64'
        ;;
    swift-ios)
        test "$(uname -m)" = arm64
        swift_make ios-fat
        swift_sample 'HelloFromTailscale iOS' ios 'generic/platform=iOS'
        swift_sample 'HelloFromTailscale iOS' ios-sim 'generic/platform=iOS Simulator'
        ;;
    *)
        echo "Unknown compatibility suite: $1" >&2
        exit 2
        ;;
esac
