#!/bin/zsh
# Builds Coffeine.app and Coffeine.zip.
#   ./build.sh --install   also copies the app to /Applications and starts it.
#   ./build.sh --release   also publishes Coffeine.zip as a GitHub Release (tag v<CFBundleShortVersionString>).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Coffeine.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macos13.0 -o build/Coffeine-arm64 Sources/main.swift
swiftc -O -target x86_64-apple-macos13.0 -o build/Coffeine-x86_64 Sources/main.swift
lipo -create build/Coffeine-arm64 build/Coffeine-x86_64 -output "$APP/Contents/MacOS/Coffeine"
rm build/Coffeine-arm64 build/Coffeine-x86_64

cp Info.plist "$APP/Contents/Info.plist"

# App icon: compile the Icon Composer file into Assets.car (Liquid Glass) + .icns (fallback).
xcrun actool CoffeeeCup.icon --compile "$APP/Contents/Resources" \
  --output-format human-readable-text --errors --warnings \
  --output-partial-info-plist build/icon-partial.plist \
  --app-icon CoffeeeCup --include-all-app-icons \
  --enable-on-demand-resources NO --development-region en \
  --target-device mac --minimum-deployment-target 13.0 --platform macosx > /dev/null
rm -f build/icon-partial.plist
codesign --force --sign - "$APP"
echo "Built $APP"

# Zip for the GitHub Release (ditto keeps the bundle structure and signature).
ditto -c -k --keepParent "$APP" build/Coffeine.zip
echo "Built build/Coffeine.zip"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Coffeine 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Coffeine.app
  cp -R "$APP" /Applications/
  # Refresh the Finder icon cache for the new bundle.
  touch /Applications/Coffeine.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Coffeine.app
  open /Applications/Coffeine.app
  echo "Installed to /Applications/Coffeine.app"
fi

if [[ "${1:-}" == "--release" ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
  TAG="v$VERSION"
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Commit your changes before a release." >&2; exit 1
  fi
  git push
  gh release create "$TAG" build/Coffeine.zip --target "$(git rev-parse HEAD)" \
    --title "Coffeine $VERSION" --generate-notes
  echo "Released $TAG"
fi
