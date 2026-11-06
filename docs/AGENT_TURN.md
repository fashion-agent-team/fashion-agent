# 앱 ↔ agent 대화 (`POST /api/v1/agent/turn`)

게이트웨이에 로그인돼 있으면 앱은 들은 말을 전부 agent에 보내고, 답(`speech`)을 읽은 뒤 `next`를 따릅니다.
로그인하지 않았거나(`GATEWAY_URL` 없음, 로그인 취소) 로그인이 풀리면 예전처럼 폰 안에서 키워드로 기능을 고릅니다.
계약은 `docs/contracts/openapi.yaml`의 `TurnRequest`·`TurnResponse`입니다.

## 코드

| 파일 | 하는 일 |
| --- | --- |
| `lib/services/turn_api.dart` | `GatewayTurnApi`(토큰 붙여 부르기, 40초 제한), 요청·응답 모양, 위치(권한 없으면 서울, 10분 재사용), 오류 안내 문장 |
| `lib/agent/agent_controller.dart` | `listen`이면 바로 다시 듣기, `camera_*`면 카메라 화면 열기, `done`이면 대화 끝(sessionId 비움) |
| `lib/agent/camera_turn.dart` | 카메라 대화: 멈추면 찍어 보내기, 답이 `camera_*`면 계속, 아니면 카메라 끄고 에이전트로 돌아가기 |
| `lib/services/auto_capture.dart` | 프레임 밝기 칸(16×16)으로 1초 멈춤 판단 → 자동 촬영, 앞쪽 카메라 사진 좌우 뒤집기 |
| `lib/screens/camera_turn_screen.dart` | 위쪽 "말하기"(미리 보기 위), 아래쪽 "그만하기" |

## 카메라 대화

- 찍기 버튼은 없습니다. 화면이 1초 거의 안 바뀌고 어둡지 않으면 한 장 찍고 "찍었어요. 확인하고 있어요."라고 말합니다.
- 2초 넘게 어두우면 "불을 켜 주세요", 8초 넘게 움직이면 "잠시 멈춰 주세요"를 한 번씩 말합니다.
- 30초 동안 못 찍으면 다시 안내하고, 세 번째면 카메라를 끕니다.
- 카메라가 켜진 채 위쪽을 누르면 말할 수 있습니다("이걸로 할게", "어디야?").
- `camera_face`·`camera_teeth`는 앞쪽 카메라를 켜고, 사진을 셀카처럼 좌우로 뒤집어 보냅니다(사진 왼쪽 = 사용자 왼쪽).
- 기준값(멈춤 1초, 움직임 6, 어두움 50)은 `StillnessDetector`에 있고 실기기에서 조정합니다.

## 로컬에서 돌려 보기

1. agent: `fashion-agent-agent`에서 `./gradlew bootRun` (8081). 기본은 가짜 도구라 MCP 서버 없이 돕니다.
2. gateway: 8080 (`docs/ACCOUNT.md`와 같음). `/api/v1/agent/**`를 8081로 넘깁니다.
3. 앱: `flutter run --release --dart-define=GATEWAY_URL=http://<노트북IP>:8080`

## 이 사진의 입 박스

`imageKind: teeth`로 보낼 때 찍은 사진에서 ML Kit 얼굴 검출(`google_mlkit_face_detection`, 폰 안에서 돎)로 입을 찾아 `mouthBox`를 같이 보냅니다(`lib/services/mouth_finder.dart`).

- `UPPER_LIP_BOTTOM`과 `LOWER_LIP_TOP` 점을 감싸는 박스, 사진 크기 비율(0~1). 서버는 이 박스의 긴 변 × 1.36 정사각형으로 잘라 치아 모델에 넣습니다(학습 규칙과 같음).
- 셀카 방향으로 뒤집은 뒤의 사진에서 찾으니 좌표를 따로 뒤집지 않습니다.
- 얼굴이 여럿이면 가장 큰 얼굴. 못 찾으면 박스 없이 보내고, 서버가 사진 가운데를 봅니다.
- 입을 다물고 있어도 그대로 보냅니다. 서버가 "입을 더 벌려 주세요"라고 안내합니다.
- ML Kit 때문에 iOS 최소 버전을 15.5로 올렸습니다. 웹에서는 찾지 않습니다.

## 아직 안 한 것

- ML Kit 구도 안내(옷·얼굴 위치, `faceLandmarks`). 지금은 보내지 않고, 서버가 사진만으로 봅니다.
  - `mouthBox`는 보냅니다(아래 "이 사진의 입 박스").
- 카메라가 켜진 동안 버튼 없이 계속 듣기. 지금은 위쪽을 눌러야 듣습니다.
