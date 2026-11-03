# fashion-agent-agent

**agent** · 패션 에이전트(시각장애인용 코디 도우미)의 한 부분입니다.

사용자가 한 말을 듣고 어떤 기능(MCP 서버)을 부를지 고르는 두뇌입니다. Gemini API를 쓰며, 옷장 기록을 바탕으로 사용자 맞춤 패션을 추천합니다.

## 하는 일

- gateway에서 사용자 말(글자)과 사진을 받음
- Gemini에 MCP 도구 목록을 주고, 어떤 도구를 부를지 고르게 함 (MCP 클라이언트)
- 도구 결과를 모아 사용자에게 들려줄 한국어 문장을 만듦
- closet 기록을 바탕으로 맞춤 패션 추천

## 지금 상태

없음. 지금은 앱의 키워드 라우터(`fashion-agent`의 `lib/agent/intent_router.dart`)가 기능을 고릅니다. 여기 agent가 생기면 그 역할을 넘겨받습니다.

## 할 일

- [ ] MCP 클라이언트 구성 (서버 5개 연결)
- [ ] Gemini 함수 호출(function calling)로 도구 고르기
- [ ] 답변 말투 정하기 (존댓말, 짧게, 화면 없이 소리로만 들음)

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
