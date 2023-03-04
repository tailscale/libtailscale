#!/usr/bin/env bash
#
# Builds tailscale.jar.
#
# Must be run from a mac. Requires linux cross compilers.
# Set up your environment with:
#
#	brew tap messense/macos-cross-toolchains
#	brew install openjdk
#	brew install x86_64-unknown-linux-musl
#	brew install aarch64-unknown-linux-musl
#

if [ $(uname) != 'Darwin' ]; then
	echo 'build only runs on macOS'; exit 1
fi
if [ -z ${JAVA_HOME+x} ]; then
	echo 'JAVA_HOME is unset'; exit 1
fi

PATH="$JAVA_HOME/bin:$PATH"
ROOT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )

(
	set -e -x
	cd "$ROOT_DIR"

	GOOS=darwin GOARCH=arm64 go build -buildmode=c-shared && mv libtailscale java/libtailscale.dylib

	GOOS=linux GOARCH=amd64 CC=x86_64-unknown-linux-musl-cc CGO_ENABLED=1 go build -buildmode=c-shared
	mv libtailscale java/libtailscale_linux_x86_64.so

	GOOS=linux GOARCH=arm64 CC=aarch64-unknown-linux-musl-cc CGO_ENABLED=1 go build -buildmode=c-shared
	mv libtailscale java/libtailscale_linux_aarch64.so
)

(
	set -e -x
	cd "$ROOT_DIR/java"

	# In theory we need the platform-specific headers that the JDK only
	# includes for the current platform. But in practice it looks like
	# the only symbols we are using from the darwin directory have to
	# do with the size of integers and all the sizes appear to match
	# across darwin/linux. Lucky!
	INCL="-I$JAVA_HOME/include -I$JAVA_HOME/include/darwin"
	cc $INCL -o libtailscalejni.dylib -shared tailscalejni.c libtailscale.dylib
	aarch64-unknown-linux-musl-cc -fPIC -shared $INCL -o libtailscalejni_linux_aarch64.so tailscalejni.c libtailscale_linux_aarch64.so
	x86_64-unknown-linux-musl-cc -fPIC -shared $INCL -o libtailscalejni_linux_x86_64.so tailscalejni.c libtailscale_linux_x86_64.so

	javac Tailscale.java NativeUtils.java
	mkdir -p com/tailscale
	mv *.class com/tailscale/

	rm -f tailscale.jar
	jar -f tailscale.jar -c com \
		libtailscale_linux_x86_64.so libtailscalejni_linux_x86_64.so \
		libtailscale_linux_aarch64.so libtailscalejni_linux_aarch64.so \
		libtailscale.dylib libtailscalejni.dylib
	rm -f \
		libtailscale_linux_x86_64.so libtailscalejni_linux_x86_64.so \
		libtailscale_linux_aarch64.so libtailscalejni_linux_aarch64.so \
		libtailscale.dylib libtailscalejni.dylib
	rm -rf com
)
