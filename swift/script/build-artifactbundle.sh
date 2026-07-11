#!/bin/sh
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# Cross-compiles libtailscale.a for each supported Linux triple and packages
# the results into a Swift Package Manager static-library artifact bundle
# Package.swift consumes that bundle via a binaryTarget instead of requiring a 
# prebuilt libtailscale.a to already sit at the repo root.
#
# Requires: go, and a cross C toolchain per target triple (on Debian/Ubuntu,
# `apt-get install gcc-x86-64-linux-gnu gcc-aarch64-linux-gnu` covers both;
# override CC_<goarch> to point at a different compiler).

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

# triple:GOARCH:default-cc
TARGETS="
x86_64-unknown-linux-gnu:amd64:x86_64-linux-gnu-gcc
aarch64-unknown-linux-gnu:arm64:aarch64-linux-gnu-gcc
"

variants_json=""

for entry in $TARGETS; do
    triple=$(echo "$entry" | cut -d: -f1)
    goarch=$(echo "$entry" | cut -d: -f2)
    default_cc=$(echo "$entry" | cut -d: -f3)

    cc_var="CC_$goarch"
    cc=$(eval "echo \${$cc_var:-$default_cc}")

    if ! command -v "$cc" >/dev/null 2>&1; then
        echo "error: cross compiler '$cc' not found for $triple (set $cc_var to override)" >&2
        exit 1
    fi

    echo "::: Building libtailscale.a for $triple (GOARCH=$goarch, CC=$cc) :::"

    variant_dir="$BUNDLE_DIR/$ARTIFACT_ID-$triple"
    mkdir -p "$variant_dir/include"

    (
        cd "$REPO_ROOT"
        CC="$cc" CGO_ENABLED=1 GOOS=linux GOARCH="$goarch" \
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
done

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
