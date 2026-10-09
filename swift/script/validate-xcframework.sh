#!/bin/bash
# Validates TailscaleKit.xcframework against the things Apple rejects for.
#
# Every check here corresponds to a failure that happens at UPLOAD, not at
# build: the xcframework compiles and links fine, the app runs fine locally,
# and then App Store Connect rejects the binary minutes after submission.
# That gap is why this script exists.
#
# Only rejection causes fail the script. Anything that merely makes the bundle
# less useful to an adopter is reported as WARN.
#
# Usage: ./script/validate-xcframework.sh [path-to-TailscaleKit.xcframework]
# Exit 0 = valid, exit 1 = would be rejected.
set -euo pipefail

XCFW="${1:-./build/Build/Products/Release-all/TailscaleKit.xcframework}"

if [ ! -d "$XCFW" ]; then
  echo "ERROR: $XCFW not found — run 'make xcframework' first"
  exit 1
fi

FAIL=0
echo "=== Validating $XCFW ==="

# 1. Symlinks in an iOS slice are rejected outright. macOS frameworks are
#    versioned bundles and legitimately contain symlinks, so only iOS slices
#    are checked.
for slice in "$XCFW"/ios-*; do
  [ -d "$slice" ] || continue
  if find "$slice" -type l | grep -q .; then
    echo "FAIL: symlinks found in $(basename "$slice")"
    find "$slice" -type l | sed 's/^/       /'
    FAIL=1
  fi
done
[ $FAIL -eq 0 ] && echo "OK: no symlinks in iOS slices (macOS versioned-bundle symlinks are expected)"

# 2. ITMS-91053: a missing privacy manifest in an embedded iOS framework
#    fails the upload with no build-time warning.
for slice in "$XCFW"/ios-*; do
  [ -d "$slice" ] || continue
  if [ -f "$slice/TailscaleKit.framework/PrivacyInfo.xcprivacy" ]; then
    echo "OK: PrivacyInfo.xcprivacy present in $(basename "$slice")"
  else
    echo "FAIL: PrivacyInfo.xcprivacy missing from $(basename "$slice") (ITMS-91053)"
    FAIL=1
  fi
done

# 3. macOS slices are versioned bundles: the manifest must sit inside
#    Versions/A/Resources so the _CodeSignature seal covers it. At the bundle
#    root it is unsealed and upload fails with error 90238.
for slice in "$XCFW"/macos-*; do
  [ -d "$slice" ] || continue
  if [ -f "$slice/TailscaleKit.framework/Versions/A/Resources/PrivacyInfo.xcprivacy" ]; then
    echo "OK: PrivacyInfo.xcprivacy sealed in $(basename "$slice")"
  else
    echo "FAIL: PrivacyInfo.xcprivacy not in Versions/A/Resources of $(basename "$slice") (error 90238)"
    FAIL=1
  fi
done

# 4. Simulator code must never end up in a slice that ships. This is the rule
#    usually remembered as "no simulator binaries in an App Store submission",
#    and it is why fat frameworks — where lipo put device and simulator
#    architectures in one binary — were rejected. An xcframework keeps them in
#    separate slices and Xcode embeds only the slice matching the build
#    destination, so a simulator slice in the bundle is never submitted. What is
#    worth checking is that each slice really is what its name claims: a slice
#    mislabelled at assembly time would ship simulator code and be rejected.
#    So verify the platform of every architecture in every slice.
slice_binary() {
  if [ -f "$1/TailscaleKit.framework/TailscaleKit" ]; then
    echo "$1/TailscaleKit.framework/TailscaleKit"
  elif [ -f "$1/TailscaleKit.framework/Versions/A/TailscaleKit" ]; then
    echo "$1/TailscaleKit.framework/Versions/A/TailscaleKit"
  fi
}

for slice in "$XCFW"/*/; do
  slice="${slice%/}"
  name="$(basename "$slice")"

  case "$name" in
    *-simulator) want="IOSSIMULATOR" ;;
    ios-*)       want="IOS" ;;
    macos-*)     want="MACOS" ;;
    *)           continue ;;
  esac

  bin="$(slice_binary "$slice")"
  if [ -z "$bin" ]; then
    echo "FAIL: no TailscaleKit binary found in $name"
    FAIL=1
    continue
  fi

  got="$(vtool -show-build "$bin" 2>/dev/null | awk '$1 == "platform" { print $2 }' | sort -u)"
  if [ -z "$got" ]; then
    echo "FAIL: could not read the build platform of $name"
    FAIL=1
  elif [ "$got" = "$want" ]; then
    echo "OK: $name is built for $want"
  else
    echo "FAIL: $name declares $want but its binary is built for: $(echo "$got" | tr '\n' ' ')"
    FAIL=1
  fi
done

# 5. tailscale/tailscale#15802: a prebuilt binary carrying the vendor's team
#    identifier in its signature collides with the adopter's own signing
#    identity. The distributed xcframework must be unsigned or ad-hoc so the
#    consuming app signs it on embed.
if codesign -dv "$XCFW"/*/TailscaleKit.framework 2>&1 | grep -qi "TeamIdentifier=[A-Z0-9]"; then
  echo "FAIL: a team identifier is embedded in the framework signature (see tailscale/tailscale#15802)"
  FAIL=1
else
  echo "OK: no vendor team identifier in the signature (#15802 not regressed)"
fi

# 6. xcodebuild -create-xcframework generates this; its absence means the
#    bundle was assembled by hand and Xcode will not resolve slices.
if [ -f "$XCFW/Info.plist" ]; then
  echo "OK: Info.plist present at xcframework root"
else
  echo "FAIL: Info.plist missing at xcframework root"
  FAIL=1
fi

# Advisory. Not a rejection check: a bundle without a simulator slice uploads
# and ships perfectly well. It is only a problem for whoever consumes the
# bundle, who then cannot build for the simulator and sees it as a link error
# with no obvious cause. Warn, do not fail — "ios-fat" and a device-only
# framework are both legitimate outputs.
if ls -d "$XCFW"/ios-*simulator* >/dev/null 2>&1; then
  echo "OK: iOS simulator slice present (adopters can build for the simulator)"
else
  echo "WARN: no iOS simulator slice — adopters of this bundle cannot build for the simulator"
fi

echo "==="
if [ $FAIL -eq 0 ]; then
  echo "xcframework validation PASSED"
else
  echo "xcframework validation FAILED — this bundle would be rejected at upload"
fi
exit $FAIL
