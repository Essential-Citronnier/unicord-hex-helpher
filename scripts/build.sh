#!/bin/zsh
# Universal(arm64 + x86_64) UnicodeHelper.app을 build/에 만든다.
#   SIGN_IDENTITY="Developer ID Application: ..." 를 주면 배포용으로 서명 (hardened runtime),
#   없으면 ad-hoc 서명 (내 Mac에서만 쓸 때).
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="UnicodeHelper"
BUNDLE_ID="io.github.lemonardo1.unicodehelper"
VERSION="${VERSION:-1.0.0}"
APP="build/$NAME.app"

if ! command -v swiftc >/dev/null; then
  echo "swiftc가 없습니다. 'xcode-select --install'로 Command Line Tools를 설치하세요." >&2
  exit 1
fi

rm -rf build && mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" Sources/main.swift -o "build/$NAME-$arch"
done
lipo -create "build/$NAME-arm64" "build/$NAME-x86_64" -output "$APP/Contents/MacOS/$NAME"
rm "build/$NAME-arm64" "build/$NAME-x86_64"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "빌드 완료: $APP ($VERSION)"
