# UnicodeHelper

macOS 입력 소스가 **Unicode Hex Input**일 때만 화면에 자주 쓰는 문자(→ ← ↑ ↓ 등)와 그 유니코드 코드를 띄워주는 메뉴바 앱.
⌥를 누른 채 코드를 입력하면 해당 문자가 입력된다 (예: ⌥ + `2192` → `→`).

## 설치 / 제거

```sh
./install.sh     # 빌드 → ~/Applications/UnicodeHelper.app 설치 → 로그인 시 자동 실행 등록
./uninstall.sh   # 앱과 LaunchAgent 제거
```

Xcode 프로젝트 없이 `swiftc`만으로 빌드한다. 자동 실행은 `~/Library/LaunchAgents/io.github.lemonardo1.unicodehelper.plist`.

## 사용

- 오버레이는 드래그로 옮길 수 있고, 위치는 기억된다.
- 마우스를 올리면 반투명해진다.
- 메뉴바 `U+` 메뉴: 항상 표시 / 위치 초기화 / 종료.

## 문자 목록 수정

`Sources/main.swift` 상단의 `symbolGroups`를 고친 뒤 `./install.sh`를 다시 실행.

## 라이선스

MIT
