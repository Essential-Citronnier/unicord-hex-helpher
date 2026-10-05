#!/bin/zsh
# 로그인 항목 해제 → 종료 → 앱과 설정 삭제.
NAME="UnicodeHelper"
BUNDLE_ID="io.github.lemonardo1.unicodehelper"

for APP in "$HOME/Applications/$NAME.app" "/Applications/$NAME.app"; do
  [[ -d "$APP" ]] || continue
  "$APP/Contents/MacOS/$NAME" --unregister-login-item 2>/dev/null
done

pkill -x "$NAME" 2>/dev/null

# 이전 버전이 쓰던 LaunchAgent
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

rm -rf "$HOME/Applications/$NAME.app" "/Applications/$NAME.app"
defaults delete "$BUNDLE_ID" 2>/dev/null
echo "제거 완료"
