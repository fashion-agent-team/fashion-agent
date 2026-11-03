# mcp-weather

**weather MCP 서버** · 패션 에이전트(시각장애인용 코디 도우미)의 한 부분입니다.

날씨를 알려 주고, 날씨에 맞게 옷의 두께와 재질을 고릅니다.

## 도구 (안)

- `get_weather(lat, lon)`: 기온, 체감 온도, 강수 확률, 일교차
- `suggest_by_weather(lat, lon)`: 날씨에 맞는 옷 두께·재질

## 지금 상태

앱 안에 있습니다. 여기로 옮길 코드:
- `fashion-agent`의 `lib/services/weather_service.dart` (Open-Meteo 호출, API 키 없음)
- `lib/models/weather.dart`
- `lib/styling/weather_rules.dart` (일교차 10도 이상이면 겉옷 등)
- 테스트 `test/weather_test.dart`

## 할 일

- [ ] MCP 서버 만들기 (`tools/list`, `tools/call`)
- [ ] 위 코드를 옮기기 (Dart → 서버 언어로)

## 전체 구조

```
application(fashion-agent) ─REST→ fashion-agent-gateway ─→ fashion-agent-agent ─MCP→ mcp-weather / mcp-schedule / mcp-clothes-state / mcp-face-check / mcp-closet
                                                                                              ↓
                                                                                              DB (계정·회원정보·일정·옷장)
```

## 브랜치

GitFlow를 따릅니다. `develop`에서 `feature/…` 브랜치를 따서 PR로 합칩니다. 규칙은 앱 레포의 `docs/GITFLOW.md`를 봅니다.

## 비밀 값

API 키와 DB 접속 정보는 레포에 넣지 않습니다. 배포 환경의 비밀 값(Secret)으로만 둡니다.
