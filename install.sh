#!/bin/zsh
# 빌드 → ~/Applications 설치 → 로그인 시 자동 실행 등록 → 실행
set -e
cd "$(dirname "$0")"

NAME="UnicodeHelper"
BUNDLE_ID="com.daeseongkim.unicodehelper"
APP="$HOME/Applications/$NAME.app"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

rm -rf build && mkdir -p "build/$NAME.app/Contents/MacOS"
swiftc -O Sources/main.swift -o "build/$NAME.app/Contents/MacOS/$NAME"

cat > "build/$NAME.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - "build/$NAME.app"

launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
pkill -x "$NAME" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP" && cp -R "build/$NAME.app" "$APP"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/$NAME</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "설치 완료: $APP (로그인 시 자동 실행)"
