#!/bin/sh
# Builds a universal Release app and packages it as dist/Soundbind-<version>.zip,
# the file the Homebrew cask installs from. Prints the SHA-256 the cask needs.
# Run from the repository root. The build is ad hoc signed and not notarized.
set -eu

xcodegen generate
xcodebuild -scheme Soundbind -configuration Release -derivedDataPath build/release \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build

app="build/release/Build/Products/Release/Soundbind.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
zip="dist/Soundbind-$version.zip"

mkdir -p dist
rm -f "$zip"
# ditto keeps the bundle's symlinks, permissions and signature intact.
ditto -c -k --keepParent "$app" "$zip"
echo "Created $zip"
shasum -a 256 "$zip"
