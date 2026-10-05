# UnicodeHelper

macOS 입력 소스가 **Unicode Hex Input**일 때만 화면에 자주 쓰는 문자(→ ← ↑ ↓ 등)와 그 유니코드 코드를 띄워주는 메뉴바 앱.
⌥를 누른 채 코드를 입력하면 해당 문자가 입력된다 (예: ⌥ + `2192` → `→`).

macOS 13 이상, Apple Silicon / Intel 모두 지원.

## 설치

1. [Releases](https://github.com/Essential-Citronnier/unicord-hex-helpher/releases)에서 `UnicodeHelper-x.y.z.dmg`를 받는다.
2. DMG를 열고 `UnicodeHelper`를 `Applications` 폴더로 끌어다 놓는다.
3. 응용 프로그램 폴더에서 실행한다. (DMG에서 바로 실행하면 응용 프로그램 폴더로 옮길지 물어본다.)

처음 실행하면:

- **로그인 시 자동 실행**으로 등록된다. 설정창에서 끌 수 있다.
- Unicode Hex Input이 입력 소스에 없으면 **설정 가이드**가 뜬다. **자동으로 추가** 버튼으로 바로 추가하거나, 안내에 따라 직접 추가할 수 있다 (시스템 설정 → 키보드 → 텍스트 입력 → 편집… → + → 기타 → Unicode Hex Input). 가이드는 메뉴바 `U+` → **설정 가이드…**에서 다시 열 수 있다.

## 사용

- 기호 줄을 클릭하면 지금 쓰고 있는 앱에 바로 입력된다. **손쉬운 사용** 권한이 필요하며, 권한이 없으면 클립보드에 복사된다.
- 오버레이는 드래그로 옮길 수 있고, 위치는 기억된다.
- 마우스를 올리면 배경은 반투명해지고 커서 아래 줄만 강조된다.
- 머리글이나 빈 곳을 클릭하면 설정창이 열린다. 표시할 기호를 고르거나, 코드(`2192`, `U+2192`)나 문자로 직접 추가할 수 있다.
- 메뉴바 `U+` 메뉴: 설정 / 설정 가이드 / 항상 표시 / 위치 초기화 / 종료.

## 제거

메뉴바 `U+` → 종료 후 응용 프로그램 폴더에서 `UnicodeHelper`를 휴지통으로 옮긴다. 소스에서 설치했다면 `./uninstall.sh`로 로그인 항목과 설정까지 한 번에 지운다.

## 소스에서 빌드

Xcode 프로젝트 없이 `swiftc`(Command Line Tools)만으로 빌드한다.

```sh
./install.sh     # 빌드 → ~/Applications/UnicodeHelper.app 설치 → 실행
./uninstall.sh   # 로그인 항목 해제, 앱과 설정 삭제
```

설정창에 나오는 후보 목록은 `Sources/main.swift` 상단의 `catalog`에서 바꿀 수 있다.

### 배포용 DMG 만들기

```sh
SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="my-notary-profile" \
VERSION=1.0.0 \
scripts/package.sh   # → dist/UnicodeHelper-1.0.0.dmg (서명 + 공증 + staple)
```

`NOTARY_PROFILE`은 `xcrun notarytool store-credentials`로 만든 keychain profile 이름이다.

## 라이선스

MIT
