#!/bin/zsh
# Build and package release artifacts into dist/: DisplayLab-<version>.dmg and .zip.
# Usage: scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
rm -rf dist && mkdir -p dist/stage

# Zip (ditto keeps the code signature and extended attributes intact)
ditto -c -k --keepParent build/DisplayLab.app "dist/DisplayLab-$VERSION.zip"

# DMG with a drag-to-Applications shortcut
cp -R build/DisplayLab.app dist/stage/
ln -s /Applications dist/stage/Applications
hdiutil create -volname "DisplayLab $VERSION" -srcfolder dist/stage -ov -format UDZO \
    "dist/DisplayLab-$VERSION.dmg" >/dev/null
rm -rf dist/stage

(cd dist && shasum -a 256 DisplayLab-* > SHA256SUMS.txt)
ls -lh dist
