# 패션 에이전트 DB 설계 (PostgreSQL)

2026-11-04 Spec Kit으로 다시 정리했습니다. 이 문서는 요약이고, 원본은 아래입니다.

| 무엇 | 어디 |
| --- | --- |
| 요구사항 통합(spec), 결정과 이유, ERD·컬럼 규칙, 할 일 | [specs/005-database/](../../specs/005-database/spec.md) ([data-model.md](../../specs/005-database/data-model.md), [research.md](../../specs/005-database/research.md), [tasks.md](../../specs/005-database/tasks.md)) |
| 서비스별 Flyway 마이그레이션(각 레포에 그대로 복사) | [db/](db/README.md): `account/` `schedule/` `closet/` `helper/` |
| 전체를 한 번에 만드는 SQL (생성 파일) | [schema.sql](schema.sql) (`db/build-schema.sh`가 만듦) |
| 검사 34개 / 개발용 예시 데이터 | [db/checks.sql](db/checks.sql) / [db/seed-dev.sql](db/seed-dev.sql) |
| Redis 키 | [specs/005-database/contracts/redis-keys.md](../../specs/005-database/contracts/redis-keys.md) |

PostgreSQL 16.15 + pgvector 0.6.0에서 실행하고 검사가 모두 통과하는 것을 확인했습니다(2026-11-04).

## 큰 원칙

- **PostgreSQL 하나, 서비스마다 스키마 하나.** docker-compose의 `pgvector/pgvector:pg16` 한 대를 같이 씁니다.
- 다른 서비스 스키마는 직접 읽지 않습니다. 그래서 **스키마를 넘는 FK는 없습니다.** `user_id`는 `account.users.id`와 값만 같습니다.
- 표는 각 서비스가 뜰 때 Flyway로 만듭니다. 머지된 마이그레이션은 고치지 않고 새 버전을 더합니다.
- 사진은 저장하지 않습니다. agent는 DB 없이 Redis에 대화 상태를 30분 둡니다.

## 표 (10개)

| 스키마 | 주인 | 표 |
| --- | --- | --- |
| `account` | gateway | users, profiles, push_tokens, refresh_tokens |
| `schedule` | mcp-schedule | events |
| `closet` | mcp-closet | garments, wears, style_docs |
| `helper` | mcp-helper | contacts, requests |

PR #14 초안에서 바뀐 점은 [data-model.md "바뀐 점"](../../specs/005-database/data-model.md#바뀐-점-pr-14-초안-대비)에 있습니다. 가장 큰 두 가지: 내 옷 검색에서 HNSW 인덱스를 빼고(남의 옷 사이에서 거르면 내 옷이 빠질 수 있음), 코디 지식 표를 Spring AI PgVectorStore 모양으로 바꿨습니다.

## 아침 8시 일정 알림은 어떻게 도나

FCM 토큰은 `account.push_tokens`(gateway)에 있고, 약속상 mcp-schedule은 그 스키마를 못 읽습니다. 그래서 **토큰을 옮기지 않고 gateway에 "이 사용자에게 푸시 보내 줘" 내부 API를 하나 두는 방식**을 제안합니다.

```
mcp-schedule (매일 08:00 Asia/Seoul)
  1. SELECT … FROM schedule.events
       WHERE notified_at IS NULL AND start_at >= 오늘 0시 AND start_at < 내일 0시
  2. 사용자별로 묶어 gateway 내부 API 호출
       POST http://gateway:8080/internal/push  { userId, title, body }
         → gateway가 push_tokens로 FCM 전송 (만료된 토큰은 지움)
  3. 성공한 일정만 UPDATE schedule.events SET notified_at = now()
```

- 이렇게 하면 mcp-helper의 "가족 답장 왔어요" 알림도 같은 API를 씁니다. FCM 비밀 키도 gateway 한 곳에만 둡니다.
- `/internal/**`은 게이트웨이가 밖에서 오는 요청은 막습니다(Docker 내부망에서만).
- 아침 8시 이후에 등록한 오늘 일정은 알림을 보내지 않습니다(지금 설계 그대로).

## 팀이 정해야 할 것

1. **`/internal/push` 방식** 채택 여부(위). DB 설계와는 상관없습니다.
2. ~~탈퇴~~: 만들지 않기로 정함(2026-11-04). 나중에 만들면 gateway가 각 서비스에 삭제를 요청합니다(005 FR-X5).
3. ~~분위기 제목 우선 vs 장소 우선~~: 제목 → 장소 → 평상으로 정함(2026-11-04, 앱 PR #15).
4. 임베딩 차원 384는 multilingual-e5-small 기준입니다. 모델을 바꾸면 closet V2로 바꿉니다. GPT로 바꾼 것과는 상관없습니다(임베딩은 서버 안 모델).
