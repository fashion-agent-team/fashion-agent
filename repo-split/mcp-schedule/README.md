# mcp-schedule

**schedule MCP 서버** · 패션 에이전트(시각장애인용 코디 도우미)의 한 부분입니다.

사용자에게 일정을 묻고 기록·알림하며, 일정에 맞는 옷차림을 추천합니다.

## 도구 (안)

- `add_schedule(date, title, kind)`: 일정 기록 (면접, 결혼식, 장례식, 회의, 운동 등)
- `get_today()`: 오늘 일정
- `suggest_by_schedule(kind)`: 일정에 맞는 격식(formal / smart / casual / sporty)

## 지금 상태

앱 안에 저장소와 규칙만 있고, 말로 등록하는 기능은 없습니다. 여기로 옮길 코드:
- `fashion-agent`의 `lib/services/schedule_store.dart`, `lib/models/schedule_event.dart`
- `lib/styling/schedule_rules.dart`

## 할 일

- [ ] MCP 서버 만들기
- [ ] 일정을 DB에 저장
- [ ] 일정 알림 방식 정하기

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
