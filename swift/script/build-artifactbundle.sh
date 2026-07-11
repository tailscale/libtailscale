#!/bin/sh
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# Cross/native-compiles libtailscale.a for each supported triple and packages
# the results into a Swift Package Manager static-library artifact bundle
# (SE-0482). swift/Package.swift consumes that bundle via a binaryTarget
# instead of requiring a prebuilt libtailscale.a to already sit on disk.
#
# Linux triples are cross-compiled from any host given a real cross C
# toolchain per target triple (on Debian/Ubuntu, `apt-get install
# gcc-x86-64-linux-gnu gcc-aarch64-linux-gnu` covers both). Override
# CC_<mangled triple> to point at a different compiler for a given triple.
#
# macOS triples can only be built when this script itself runs on macOS -
# Go's cgo needs a real Mach-O-emitting C toolchain, which isn't available
# cross-platform the way Linux's cross-gcc toolchains are. Apple's own clang
# can target the other CPU architecture via `-arch`, so a single Mac (either
# arch) covers both arm64 and x86_64 without needing two machines. macOS
# variants are only attempted on a Darwin host.
#
# Any triple whose compiler isn't found is skipped with a warning rather than
# failing the whole run - e.g. a plain Mac without the Linux cross-gcc
# toolchains installed will still get its two macOS variants built, which is
# all that's needed for `swift build`/`swift test` on that same Mac.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SWIFT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$SWIFT_DIR/.." && pwd)

BUNDLE_NAME="TailscaleKit.artifactbundle"
BUNDLE_DIR="$SWIFT_DIR/build/$BUNDLE_NAME"
ARTIFACT_ID="libtailscale"
VERSION="1.0.0"

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

HOST_OS=$(uname -s)

# triple:GOOS:GOARCH:default-cc
LINUX_TARGETS="
x86_64-unknown-linux-gnu:linux:amd64:x86_64-linux-gnu-gcc
aarch64-unknown-linux-gnu:linux:arm64:aarch64-linux-gnu-gcc
"

# Only attempted when HOST_OS = Darwin; see note above.
MACOS_TARGETS="
arm64-apple-macosx:darwin:arm64:clang -arch arm64
x86_64-apple-macosx:darwin:amd64:clang -arch x86_64
"

variants_json=""

# build_variant <triple> <goos> <goarch> <cc>
build_variant() {
    triple="$1"
    goos="$2"
    goarch="$3"
    cc="$4"

    cc_bin=$(echo "$cc" | cut -d' ' -f1)
    if ! command -v "$cc_bin" >/dev/null 2>&1; then
        echo "warning: C compiler '$cc_bin' not found, skipping $triple (set $(cc_override_var "$triple") to point at one)" >&2
        return 0
    fi

    echo "::: Building libtailscale.a for $triple (GOOS=$goos GOARCH=$goarch, CC=$cc) :::"

    variant_dir="$BUNDLE_DIR/$ARTIFACT_ID-$triple"
    mkdir -p "$variant_dir/include"

    (
        cd "$REPO_ROOT"
        CC="$cc" CGO_ENABLED=1 GOOS="$goos" GOARCH="$goarch" \
            go build -buildmode=c-archive -o "$variant_dir/libtailscale.a" .
    )
    rm -f "$variant_dir/libtailscale.h" # go build also writes a header; we ship our own below

    cp "$REPO_ROOT/tailscale.h" "$variant_dir/include/tailscale.h"
    cat > "$variant_dir/include/module.modulemap" <<'EOF'
module CTailscale [system] {
    header "tailscale.h"
    export *
}
EOF

    variant_json=$(cat <<EOF
    {
      "path": "$ARTIFACT_ID-$triple/libtailscale.a",
      "supportedTriples": ["$triple"],
      "staticLibraryMetadata": {
        "headerPaths": ["$ARTIFACT_ID-$triple/include"],
        "moduleMapPath": "$ARTIFACT_ID-$triple/include/module.modulemap"
      }
    }
EOF
)
    if [ -z "$variants_json" ]; then
        variants_json="$variant_json"
    else
        variants_json="$variants_json,$variant_json"
    fi
}

# cc_override_var <triple> -> env var name a caller can set to override the
# compiler used for that triple, e.g. arm64-apple-macosx -> CC_arm64_apple_macosx.
cc_override_var() {
    printf '%s' "CC_$1" | tr -c 'A-Za-z0-9_' '_'
}

build_target_table() {
    table="$1"
    # Some default_cc values contain a space (e.g. "clang -arch arm64"); split
    # entries on newline only, or the default whitespace-IFS word-splitting
    # would tear a single entry into multiple bogus ones.
    old_ifs="$IFS"
    IFS='
'
    for entry in $table; do
        IFS="$old_ifs"
        triple=$(echo "$entry" | cut -d: -f1)
        goos=$(echo "$entry" | cut -d: -f2)
        goarch=$(echo "$entry" | cut -d: -f3)
        default_cc=$(echo "$entry" | cut -d: -f4)

        cc_var=$(cc_override_var "$triple")
        cc=$(eval "echo \${$cc_var:-\$default_cc}")

        build_variant "$triple" "$goos" "$goarch" "$cc"
        IFS='
'
    done
    IFS="$old_ifs"
}

build_target_table "$LINUX_TARGETS"

if [ "$HOST_OS" = "Darwin" ]; then
    build_target_table "$MACOS_TARGETS"
else
    echo "::: Skipping macOS variants (not running on a Darwin host) :::"
fi

cat > "$BUNDLE_DIR/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "$ARTIFACT_ID": {
      "type": "staticLibrary",
      "version": "$VERSION",
      "variants": [
$variants_json
      ]
    }
  }
}
EOF

echo "wrote $BUNDLE_DIR"
