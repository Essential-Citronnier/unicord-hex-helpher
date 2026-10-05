#!/bin/zsh
# Universal(arm64 + x86_64) UnicodeHelper.app을 build/에 만든다.
#   SIGN_IDENTITY  서명 인증서. 없으면 이 Mac의 Developer ID / Apple Development 인증서,
#                  그것도 없으면 ad-hoc 서명 (재빌드할 때마다 손쉬운 사용 권한을 다시 줘야 함).
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

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
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
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

# 서명 인증서를 따로 주지 않으면 이 Mac에 있는 개발자 인증서를 쓴다.
# ad-hoc 서명은 빌드할 때마다 서명이 바뀌어서 손쉬운 사용 권한이 매번 풀린다.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning \
    | grep -E '"(Developer ID Application|Apple Development):' | grep -v REVOKED \
    | head -1 | awk '{print $2}') || true
fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # 배포용(Developer ID)만 hardened runtime + 타임스탬프 (타임스탬프는 네트워크가 필요하다).
  if security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" | grep -q "Developer ID Application"; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  else
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
  fi
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "빌드 완료: $APP ($VERSION)"
