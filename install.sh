#!/bin/zsh
# 소스에서 빌드해 ~/Applications에 설치하고 실행한다.
# 로그인 시 자동 실행은 앱이 처음 실행될 때 스스로 등록한다 (설정에서 끌 수 있음).
set -euo pipefail
cd "$(dirname "$0")"

NAME="UnicodeHelper"
BUNDLE_ID="io.github.lemonardo1.unicodehelper"
APP="$HOME/Applications/$NAME.app"

scripts/build.sh

# 이전 버전이 쓰던 LaunchAgent 정리
LEGACY_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
if [[ -f "$LEGACY_AGENT" ]]; then
  launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
  rm -f "$LEGACY_AGENT"
fi

pkill -x "$NAME" 2>/dev/null || true
sleep 0.5

mkdir -p "$HOME/Applications"
rm -rf "$APP" && cp -R "build/$NAME.app" "$APP"
open "$APP"
echo "설치 완료: $APP"
