#!/bin/zsh
# 배포용 DMG를 만든다: build → 서명 → DMG → (선택) 공증 + staple.
#   SIGN_IDENTITY  Developer ID Application 인증서 이름 (필수)
#   NOTARY_PROFILE notarytool keychain profile 이름 (있으면 공증)
#   VERSION        버전 (기본 1.0.0)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?SIGN_IDENTITY를 지정하세요 (예: Developer ID Application: NAME (TEAMID))}"
VERSION="${VERSION:-1.0.0}"
NAME="UnicodeHelper"
DMG="dist/$NAME-$VERSION.dmg"

VERSION="$VERSION" SIGN_IDENTITY="$SIGN_IDENTITY" scripts/build.sh

rm -rf dist build/dmg && mkdir -p dist build/dmg
cp -R "build/$NAME.app" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "$NAME" -srcfolder build/dmg -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
  echo "NOTARY_PROFILE이 없어 공증을 건너뜁니다. 다른 Mac에서는 Gatekeeper 경고가 뜹니다."
fi
echo "패키지 완료: $DMG"
