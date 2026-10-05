#!/bin/zsh
BUNDLE_ID="io.github.lemonardo1.unicodehelper"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
rm -rf "$HOME/Applications/UnicodeHelper.app"
echo "제거 완료"
