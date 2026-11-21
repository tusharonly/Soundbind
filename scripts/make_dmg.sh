#!/bin/sh
# Builds a universal Release app and packages it as dist/Soundbind-<version>.dmg,
# with the drag-to-Applications window layout defined in scripts/dmg/.
# Run from the repository root. The build is ad hoc signed and not notarized.
set -eu

xcodegen generate
xcodebuild -scheme Soundbind -configuration Release -derivedDataPath build/release \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build

app="build/release/Build/Products/Release/Soundbind.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")

# dmgbuild writes the window layout without scripting Finder; keep it in a private virtualenv.
venv="build/dmg-venv"
[ -x "$venv/bin/dmgbuild" ] || { python3 -m venv "$venv" && "$venv/bin/pip" install --quiet dmgbuild; }

# One TIFF holding the 1x and 2x backgrounds, so the window is sharp on Retina displays.
tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png -out build/dmg-background.tiff

mkdir -p dist
rm -f "dist/Soundbind-$version.dmg"
"$venv/bin/dmgbuild" -s scripts/dmg/settings.py -D app="$app" -D background="build/dmg-background.tiff" \
    "Soundbind" "dist/Soundbind-$version.dmg"
echo "Created dist/Soundbind-$version.dmg"
