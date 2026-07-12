#!/bin/sh
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# libtailscale.a and tstestcontrol/libtstestcontrol.a are two independently
# built Go c-archives. Each embeds its own full copy of the cgo runtime glue
# (crosscall2, x_cgo_thread_start, x_cgo_init, etc.) under the same fixed
# symbol names, since that glue is plain C source in runtime/cgo with no
# per-package mangling. A handful of those names (_cgo_topofstack,
# _cgo_panic, crosscall2) are rejected outright as duplicate symbols by both
# ld.gold on Linux and Apple's linker when flat-linked into one binary
# (which is exactly what SwiftPM does for every target, on every platform -
# Xcode only avoids this because its framework build never puts both go.o's
# in the same link). Forcing Linux's linker through with
# --allow-multiple-definition isn't an option either: it silently drops one
# archive's copy, corrupting that archive's stack-unwind info at runtime.
#
# The rest of that duplicated glue (there are dozens more: x_cgo_init,
# x_cgo_thread_start, x_cgo_sys_thread_create, x_cgo_getstackbound,
# crosscall1, ...) doesn't fail the link at all - the linker just silently
# resolves each reference from whichever archive member happens to satisfy
# it first. That's just as dangerous as -allow-multiple-definition: it can
# splice one program's thread/stack bookkeeping into the other program's
# runtime, so the first time either program starts a fresh OS thread, it can
# crash deep in runtime.mstart0 with a corrupted stack pointer. So every
# overlapping global symbol needs renaming, not just the ones the linker
# happens to reject.
#
# Rather than hardcode that list (it depends on the Go version's
# runtime/cgo internals, not on anything in this repo), this script
# computes it: it diffs the defined global symbols of libtailscale.a
# (already built by build-artifactbundle.sh) against libtstestcontrol.a and
# renames every name that appears in both, inside a *copy* of
# libtstestcontrol.a (consistently, across every member object, so its own
# internal linkage stays self-consistent). Run this after building
# tstestcontrol/libtstestcontrol.a and before `swift build`/`swift test`.
#
# Mach-O object files (macOS) mangle every C symbol with an extra leading
# underscore on disk (`crosscall2` -> `_crosscall2`, `_cgo_panic` ->
# `__cgo_panic`); ELF (Linux) doesn't. objcopy/llvm-objcopy and nm operate
# on the raw on-disk name, not the source-level one, so the symbol names
# collected below are platform-dependent.

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

# Any built libtailscale.a variant works as the reference: the glue symbol
# *names* below come from Go's runtime/cgo C source, which doesn't vary by
# GOOS/GOARCH, only their addresses do.
REF_LIBTAILSCALE=$(find "$SWIFT_DIR/build" -name libtailscale.a -print -quit 2>/dev/null || true)
if [ -z "$REF_LIBTAILSCALE" ]; then
    echo "error: no built libtailscale.a found under $SWIFT_DIR/build (run 'make spm-setup' first)" >&2
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

NM=""
for candidate in nm llvm-nm gnm; do
    if command -v "$candidate" >/dev/null 2>&1; then
        NM="$candidate"
        break
    fi
done
if [ -z "$NM" ] && command -v xcrun >/dev/null 2>&1; then
    NM=$(xcrun -f llvm-nm 2>/dev/null || true)
fi
if [ -z "$NM" ]; then
    echo "error: no nm found" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Global (externally visible) *defined* symbol names in each archive - `-g
# --defined-only` skips both local symbols (which can't collide across
# archives) and undefined references (which aren't definitions to collide
# over).
"$NM" -g --defined-only "$REF_LIBTAILSCALE" 2>/dev/null | awk 'NF==3 {print $3}' | sort -u > "$WORK_DIR/libtailscale.syms"
"$NM" -g --defined-only "$SRC_ARCHIVE" 2>/dev/null | awk 'NF==3 {print $3}' | sort -u > "$WORK_DIR/libtstestcontrol.syms"
comm -12 "$WORK_DIR/libtailscale.syms" "$WORK_DIR/libtstestcontrol.syms" > "$WORK_DIR/shared.syms"

SHARED_COUNT=$(wc -l < "$WORK_DIR/shared.syms")
echo "renaming $SHARED_COUNT symbol(s) shared between libtailscale.a and libtstestcontrol.a"

REDEFINE_ARGS=""
while IFS= read -r sym; do
    [ -z "$sym" ] && continue
    REDEFINE_ARGS="$REDEFINE_ARGS --redefine-sym ${sym}=${sym}_tstestcontrol"
done < "$WORK_DIR/shared.syms"

cp "$SRC_ARCHIVE" "$WORK_DIR/libtstestcontrol.a"
cd "$WORK_DIR"
mkdir extract
cd extract
ar x ../libtstestcontrol.a

for f in *.o; do
    # shellcheck disable=SC2086
    "$OBJCOPY" $REDEFINE_ARGS "$f"
done

rm -f "$OUT_ARCHIVE"
ar rcs "$OUT_ARCHIVE" *.o

echo "wrote $OUT_ARCHIVE"
