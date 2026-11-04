# 기능 spec (Spec Kit)

[Spec Kit](https://github.com/github/spec-kit)으로 정리한 기능 명세입니다. 팀 원칙은 [.specify/memory/constitution.md](../.specify/memory/constitution.md)에 있습니다. Spec Kit을 쓰지 않는 팀원도 그냥 마크다운으로 읽으면 됩니다.

| 번호 | 기능 | 주인 서비스 | DB 스키마 |
| --- | --- | --- | --- |
| [001](001-account-profile/spec.md) | 계정과 회원정보 | gateway | `account` |
| [002](002-schedule/spec.md) | 일정과 장소 분위기 | mcp-schedule | `schedule` |
| [003](003-closet/spec.md) | 디지털 옷장 | mcp-closet | `closet` |
| [004](004-helper/spec.md) | 가족·친구에게 확인 요청 | mcp-helper | `helper` |

날씨(mcp-weather), 옷 상태 검사(mcp-clothes-state), 얼굴 확인(mcp-face-check)은 저장하는 데이터가 없어 이번 정리에서 뺐습니다. 필요하면 005번부터 더합니다.

## 팀이 정할 것 (clarify)

spec에 `[NEEDS CLARIFICATION]`으로 남긴 질문입니다. 정해지면 spec과 `docs/contracts/`를 함께 고칩니다.

| # | 질문 | spec | 제안 |
| --- | --- | --- | --- |
| Q1 | 제목과 장소가 서로 다른 분위기를 가리키면 무엇을 우선하나? (약속 문서는 장소 우선, 첫 구현은 제목 우선) | 002 US2, 시나리오 3 | 제목 우선: "회의"처럼 사용자가 직접 말한 목적이 더 정확하고, 장소 분류는 못 찾는 경우가 많음 |
| Q2 | 일정 알림을 어떻게 보내나? (알림 토큰은 계정 서비스에만 있음) | 002 FR-008, 001 FR-011 | 게이트웨이 내부 API `POST /internal/push {userId, title, body}`. 가족 답장 알림도 같은 통로 |
| Q3 | 탈퇴하면 다른 서비스의 데이터(일정·옷장·연락처)는? | 001 FR-012 | 발표 범위에서는 탈퇴 기능을 빼고, 이후 게이트웨이가 각 서비스에 삭제를 요청 |

## 새 spec 만들기

Claude Code에서 `/speckit-specify <기능 설명>`을 쓰면 `specs/NNN-이름/`이 생깁니다. 이 레포에서는 기능마다 브랜치를 따로 만들지 않고, GitFlow대로 `feature/…` 브랜치에서 PR로 올립니다.
