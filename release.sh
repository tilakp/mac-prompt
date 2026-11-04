#!/bin/sh
#
# Builds the Release app from the current checkout and packages it as
# MacPrompt.dmg in the repo root. Keep that name: quietpixel.dev links to
# releases/latest/download/MacPrompt.dmg.
#
# Requires Xcode and create-dmg (brew install create-dmg).
# Then publish: gh release create v<version> MacPrompt.dmg --target main

set -eu
cd "$(dirname "$0")"

dmg=MacPrompt.dmg
if [ -e "$dmg" ]; then
    echo "$dmg already exists. Move or delete it first." >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A clean build in a new folder, so no older build can get into the DMG.
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO: without it, Xcode adds the debugging
# entitlement get-task-allow, which a build for users must not have.
xcodebuild -project mac-prompt.xcodeproj -scheme mac-prompt -configuration Release \
    -derivedDataPath "$work/build" -destination 'generic/platform=macOS' \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -quiet build
app="$work/build/Build/Products/Release/mac-prompt.app"

codesign --verify --deep --strict "$app"
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q get-task-allow; then
    echo "The app has the get-task-allow entitlement." >&2
    exit 1
fi
version=$(defaults read "$app/Contents/Info" CFBundleShortVersionString)

# create-dmg copies everything in its source folder into the DMG, so the folder
# holds only the app.
mkdir "$work/stage"
ditto "$app" "$work/stage/mac-prompt.app"

create-dmg \
  --volname "Application Installer" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "mac-prompt.app" 200 190 \
  --hide-extension "mac-prompt.app" \
  --app-drop-link 600 185 \
  "$dmg" \
  "$work/stage/"

hdiutil verify -quiet "$dmg"
echo "Built $dmg with Prompt $version ($(lipo -archs "$app/Contents/MacOS/mac-prompt"))."
echo "Next: gh release create v$version $dmg --target main"
