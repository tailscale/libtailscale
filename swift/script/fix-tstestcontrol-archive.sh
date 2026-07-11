#!/bin/sh
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# libtailscale.a and tstestcontrol/libtstestcontrol.a are two independently
# built Go c-archives. Each embeds its own copy of the cgo runtime glue
# (_cgo_topofstack, _cgo_panic, crosscall2) under the same fixed symbol
# names. Both ld.gold on Linux and Apple's linker reject them as duplicate
# symbols when flat-linked into one binary (which is exactly what SwiftPM
# does for every target, on every platform - Xcode only avoids this because
# its framework build never puts both go.o's in the same link). Forcing
# Linux's linker through with --allow-multiple-definition silently drops one
# archive's copy, corrupting that archive's stack-unwind info at runtime, so
# that's not an option either.
#
# This rewrites those three symbol names inside a *copy* of
# libtstestcontrol.a (consistently, across every member object, so its own
# internal linkage stays self-consistent) so the two archives no longer
# collide. Run this after building tstestcontrol/libtstestcontrol.a and
# before `swift build`/`swift test`.
#
# Mach-O object files (macOS) mangle every C symbol with an extra leading
# underscore on disk (`crosscall2` -> `_crosscall2`, `_cgo_panic` ->
# `__cgo_panic`); ELF (Linux) doesn't. objcopy/llvm-objcopy operate on the
# raw on-disk name, not the source-level one, so the symbol list below is
# platform-dependent.

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

# macOS doesn't ship objcopy on PATH by default. Xcode's command line tools are
# built on LLVM but don't expose llvm-objcopy; a swift.org open-source toolchain
# sometimes does under its own usr/bin, which `xcrun -f` can find even when it's
# not on PATH. Otherwise fall back to a Homebrew binutils/llvm install.
OBJCOPY=""
for candidate in objcopy gobjcopy llvm-objcopy; do
    if command -v "$candidate" >/dev/null 2>&1; then
        OBJCOPY="$candidate"
        break
    fi
done
if [ -z "$OBJCOPY" ] && command -v xcrun >/dev/null 2>&1; then
    OBJCOPY=$(xcrun -f llvm-objcopy 2>/dev/null || true)
fi
if [ -z "$OBJCOPY" ]; then
    echo "error: no objcopy found. On macOS, install one with:" >&2
    echo "  brew install binutils   # provides gobjcopy" >&2
    echo "  brew install llvm       # provides llvm-objcopy" >&2
    exit 1
fi
echo "using $OBJCOPY"

# See the Mach-O note above: on-disk symbol names need an extra leading `_`
# on Darwin that ELF doesn't have.
if [ "$(uname -s)" = "Darwin" ]; then
    SYM_PREFIX="_"
else
    SYM_PREFIX=""
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
    "$OBJCOPY" \
        --redefine-sym "${SYM_PREFIX}_cgo_topofstack=${SYM_PREFIX}_cgo_topofstack_tstestcontrol" \
        --redefine-sym "${SYM_PREFIX}_cgo_panic=${SYM_PREFIX}_cgo_panic_tstestcontrol" \
        --redefine-sym "${SYM_PREFIX}crosscall2=${SYM_PREFIX}crosscall2_tstestcontrol" \
        "$f"
done

rm -f "$OUT_ARCHIVE"
ar rcs "$OUT_ARCHIVE" *.o

echo "wrote $OUT_ARCHIVE"
