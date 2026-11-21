#!/bin/sh
# Builds a universal Release app and packages it as dist/Soundbind-<version>.dmg.
# Run from the repository root. The build is ad hoc signed and not notarized.
set -eu

xcodegen generate
xcodebuild -scheme Soundbind -configuration Release -derivedDataPath build/release \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build

app="build/release/Build/Products/Release/Soundbind.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

ditto "$app" "$stage/Soundbind.app"
ln -s /Applications "$stage/Applications"
mkdir -p dist
hdiutil create -volname "Soundbind" -srcfolder "$stage" -ov -format UDZO -fs HFS+ "dist/Soundbind-$version.dmg"
echo "Created dist/Soundbind-$version.dmg"
