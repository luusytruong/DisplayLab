#!/bin/zsh
# Build DisplayLab.app as a universal (Apple Silicon + Intel) binary. No Xcode project needed,
# only the Command Line Tools (swiftc). Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

APP=build/DisplayLab.app
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # regenerate: see scripts/make-icon.swift

for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -swift-version 5 \
        -target "$arch-apple-macos14.0" \
        Sources/*.swift -o "build/obj/DisplayLab-$arch"
done
lipo -create build/obj/DisplayLab-arm64 build/obj/DisplayLab-x86_64 -output "$APP/Contents/MacOS/DisplayLab"

# Ad-hoc signature: required to run on Apple Silicon. Not a Developer ID, so not notarized.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x DisplayLab 2>/dev/null || true
    rm -rf /Applications/DisplayLab.app
    cp -R "$APP" /Applications/
    open /Applications/DisplayLab.app
    echo "Installed to /Applications"
fi
