#!/bin/sh
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# libtailscale.a and tstestcontrol/libtstestcontrol.a are two independently
# built Go c-archives. Each embeds its own copy of the cgo runtime glue
# (_cgo_topofstack, _cgo_panic, crosscall2) under the same fixed symbol
# names. Apple's linker tolerates the two colliding definitions, but
# ld.gold on Linux rejects them as duplicate symbols -- and forcing it
# through with --allow-multiple-definition silently drops one archive's
# copy, corrupting that archive's stack-unwind info at runtime.
#
# This rewrites those three symbol names inside a *copy* of
# libtstestcontrol.a (consistently, across every member object, so its own
# internal linkage stays self-consistent) so the two archives no longer
# collide. Run this after building tstestcontrol/libtstestcontrol.a and
# before `swift build`/`swift test`.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SWIFT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$SWIFT_DIR/.." && pwd)

SRC_ARCHIVE="$REPO_ROOT/tstestcontrol/libtstestcontrol.a"
OUT_DIR="$SWIFT_DIR/build"
OUT_ARCHIVE="$OUT_DIR/libtstestcontrol.a"

if [ ! -f "$SRC_ARCHIVE" ]; then
    echo "error: $SRC_ARCHIVE not found (run 'make all' in tstestcontrol/ first)" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

cp "$SRC_ARCHIVE" "$WORK_DIR/libtstestcontrol.a"
cd "$WORK_DIR"
mkdir extract
cd extract
ar x ../libtstestcontrol.a

for f in *.o; do
    objcopy \
        --redefine-sym _cgo_topofstack=_cgo_topofstack_tstestcontrol \
        --redefine-sym _cgo_panic=_cgo_panic_tstestcontrol \
        --redefine-sym crosscall2=crosscall2_tstestcontrol \
        "$f"
done

rm -f "$OUT_ARCHIVE"
ar rcs "$OUT_ARCHIVE" *.o

echo "wrote $OUT_ARCHIVE"
