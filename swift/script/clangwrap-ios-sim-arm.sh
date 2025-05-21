#!/bin/sh

SDK=iphonesimulator
PLATFORM=ios-simulator

CLANGARCH=arm64

SDK_PATH=`xcrun --sdk $SDK --show-sdk-path`

# cmd/cgo doesn't support llvm-gcc-4.2, so we have to use clang.
CLANG=`xcrun --sdk $SDK --find clang`

exec "$CLANG" -arch $CLANGARCH -isysroot "$SDK_PATH" -m${PLATFORM}-version-min=12.0 "$@"
