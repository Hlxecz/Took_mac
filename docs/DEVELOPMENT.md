# 개발 가이드

## 구성

| 경로 | 역할 |
| --- | --- |
| `Sources/TookCore` | 계획·기록·파일 저장·두드림 판정 |
| `Sources/TookMac` | 메뉴 막대, 계획 화면, 설정, 몸체 센서 |
| `Sources/TookWidgets` | 정식 WidgetKit 위젯과 타임라인 |
| `Shared` | 위젯에서 완료하는 App Intent |
| `Configuration` | 앱·위젯의 서명 권한과 위젯 정보 |
| `Tests` | 핵심 동작 자동 테스트 |
| `docs/assets` | README 로고, 대표 이미지, 소개 화면 |

## 환경과 명령

macOS 14 이상, Xcode 및 Swift 6가 필요합니다. 외부 앱 런타임 패키지 의존성은 없습니다.

```sh
swift test
Scripts/build-app.sh
Scripts/install-app.sh
```

빌드 결과는 `dist/Took Mac.app`과 `dist/Took-Mac.zip`입니다. 설치는 `~/Applications/Took Mac.app` 경로를 일관되게 사용합니다. `TookMac.xcodeproj`가 포함되어 있어 XcodeGen 없이도 빌드할 수 있으며, 프로젝트 구조를 바꿀 때는 `project.yml`에서 다시 생성합니다.

GitHub Actions는 푸시 시 테스트와 앱·위젯 빌드를 실행하고 ZIP을 보관합니다. 자동 설치·자동 업데이트 서비스나 바탕화면 위젯 자동 배치는 포함하지 않습니다.

## 로컬 빌드와 서명

기본 개인용 빌드는 로컬 서명을 사용합니다. 센서에 접근하는 일반 앱과, 전용 저장 폴더에만 파일 접근 예외를 둔 샌드박스 위젯 확장으로 구성됩니다.

공식 배포·공증에는 별도 서명 설정이 필요합니다. 개발자 서명 시에는 App Groups 모드로 빌드할 수 있습니다.

```sh
TOOK_DEVELOPMENT_TEAM=개발팀ID TOOK_APP_GROUP=등록한앱그룹ID Scripts/build-app.sh
```

## 위젯 갱신 진단

앱의 계획 변경과 위젯의 완료 동작은 저장 후 WidgetCenter에 갱신을 요청합니다. 위젯 자체의 주기적 갱신 시점은 macOS가 관리합니다.

```sh
"$HOME/Applications/Took Mac.app/Contents/MacOS/TookMac" --widget-check
```

저장 위치, 계획·기록 개수, 배치된 위젯 종류를 확인하고 갱신을 요청합니다. 계획 제목은 출력하지 않습니다.

개발본과 설치본의 버전 등록이 섞이거나, 앱 교체 후 이전 위젯 프로세스가 남으면 WidgetKit에서 `Bundle version did not match` 오류가 나며 갱신이 중단될 수 있습니다. 전체 시스템 등록을 초기화하지 말고 `Scripts/install-app.sh`로 설치합니다. 이 스크립트는 개발본과 설치본 등록을 해제하고, 설치 경로가 정확히 일치하는 Took 위젯 프로세스가 종료된 뒤 앱을 교체·재등록합니다. 빌드 단계에서 앱과 위젯의 버전 일치도 확인합니다.

## 센서와 창 진단

```sh
"$HOME/Applications/Took Mac.app/Contents/MacOS/TookMac" --motion-check 3
"$HOME/Applications/Took Mac.app/Contents/MacOS/TookMac" --verify-window-toggle
```

두드리기 감지는 실제 센서 표본 수신을 확인했고, 창 열기·숨기기·같은 창 재사용을 검증했습니다. 실제 사용자의 두드림 세기는 감도 조절이 필요할 수 있습니다.

## 검증과 데이터

자동 테스트 17개가 저장·완료·복원·반복·파일 보호·계획 순서·내일 예고·완료·삭제 기록 비우기와 진행 중·예정 계획 보존·센서 보고서·두 번 두드림 및 입력 억제를 검증합니다. Apple Silicon·Intel Release 빌드와 위젯 등록·타임라인 갱신도 확인합니다.

저장 파일 형식이 손상되면 기존 파일을 덮어쓰지 않고 편집을 중지합니다. 직접 수정하기 전에는 앱을 종료하고 파일을 복사해 백업해 주세요. README 화면은 개인 내역이 없는 별도 소개용 데이터로 촬영합니다.
