# go/Makefile
APPLE_OUT=out/apple

ios-arm64:
	CGO_ENABLED=1 \
	GOOS=ios \
	GOARCH=arm64 \
	SDK=iphoneos \
	CC=$(PWD)/clangwrap.sh \
	CGO_CFLAGS="-fembed-bitcode" \
	go build -buildmode=c-archive -tags ios -o $(APPLE_OUT)/ios_arm64.a .

ios-x86_64:
	CGO_ENABLED=1 \
	GOOS=ios \
	GOARCH=amd64 \
	SDK=iphonesimulator \
	CC=$(PWD)/clangwrap.sh \
	go build -buildmode=c-archive -tags ios -o $(APPLE_OUT)/ios_x86_64.a .

ios: ios-arm64 ios-x86_64
	lipo $(APPLE_OUT)/ios_x86_64.a $(APPLE_OUT)/ios_arm64.a -create -output $(APPLE_OUT)/ios_universal.a

macos-x86_64:
	CGO_ENABLED=1 \
	GOOS=darwin \
	GOARCH=amd64 \
	MACOSX_DEPLOYMENT_TARGET=10.6 \
	go build -buildmode=c-archive -o $(APPLE_OUT)/macos_x86_64.a .

macos-arm64:
	CGO_ENABLED=1 \
	GOOS=darwin \
	GOARCH=arm64 \
	MACOSX_DEPLOYMENT_TARGET=12.0 \
	go build -buildmode=c-archive -o $(APPLE_OUT)/macos_arm64.a .

macos: macos-x86_64 macos-arm64
	lipo $(APPLE_OUT)/macos_x86_64.a $(APPLE_OUT)/macos_arm64.a -create -output $(APPLE_OUT)/macos_universal.a

apple: macos ios
	rm -rf $(APPLE_OUT)/*.h $(APPLE_OUT)/macos_x86_64.a $(APPLE_OUT)/macos_arm64.a $(APPLE_OUT)/ios_x86_64.a $(APPLE_OUT)/ios_arm64.a

ANDROID_OUT=out/android
ANDROID_SDK=/opt/homebrew/share/android-ndk
NDK_BIN=$(ANDROID_SDK)/toolchains/llvm/prebuilt/darwin-x86_64/bin/

android-armv7a:
	CGO_ENABLED=1 \
	GOOS=android \
	GOARCH=arm \
	GOARM=7 \
	CC=$(NDK_BIN)/armv7a-linux-androideabi21-clang \
	go build -buildmode=c-shared -o $(ANDROID_OUT)/armeabi-v7a_libmirage.so .

android-arm64:
	CGO_ENABLED=1 \
	GOOS=android \
	GOARCH=arm64 \
	CC=$(NDK_BIN)/aarch64-linux-android21-clang \
	go build -buildmode=c-shared -o $(ANDROID_OUT)/arm64-v8a_libmirage.so .

android-x86:
	CGO_ENABLED=1 \
	GOOS=android \
	GOARCH=386 \
	CC=$(NDK_BIN)/i686-linux-android21-clang \
	go build -buildmode=c-shared -o $(ANDROID_OUT)/x86_libmirage.so .

android-x86_64:
	CGO_ENABLED=1 \
	GOOS=android \
	GOARCH=amd64 \
	CC=$(NDK_BIN)/x86_64-linux-android21-clang \
	go build -buildmode=c-shared -o $(ANDROID_OUT)/x86_64_libmirage.so .

android: android-armv7a android-arm64 android-x86 android-x86_64
	rm -rf $(ANDROID_OUT)/*.h

# https://rogchap.com/2020/09/14/running-go-code-on-ios-and-android/
# State file location:
# macos, ios: $HOME/Library/Application Support/tsnet-a.out
# Windows: %AppData%
