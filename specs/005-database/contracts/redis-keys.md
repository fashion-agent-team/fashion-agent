# Redis 키 약속

Redis는 오래 남길 필요가 없는 값만 둡니다. 꺼져도 사용자는 새 대화로 시작할 뿐 데이터는 잃지 않습니다.

| 키 | 주인 | 값 | TTL | 근거 |
| --- | --- | --- | --- | --- |
| `agent:session:{userId}:{sessionId}` | agent | 세션 JSON(아래) | 30분, 쓸 때마다 다시 30분 | agent `RedisSessionStore`, `agent.session-ttl: 30m` |
| `request_rate_limiter.{userId}.tokens` / `.timestamp` | gateway | Spring Cloud Gateway `RedisRateLimiter`가 관리 | 라이브러리가 정함 | 약속 문서 4절(분당 30회, 사진 분당 10회) |

## agent 세션 값

```json
{
  "sessionId": "s_42",
  "userId": "…",                       // 게이트웨이가 확인한 X-User-Id
  "weather": { … },                    // 1단계 weather_today 결과 (없으면 null)
  "events": [ … ],                     // 1단계 schedule_list 결과
  "closet": { … },                     // 1단계 closet_search 결과
  "advice": { … },                     // 1단계 GPT 추천 출력
  "seen": [ { "garment": { … }, "fit": "good" } ],   // 2단계에서 본 옷과 판단
  "lastDamage": [ { "where": "오른쪽 소매 끝", … } ], // "어디야?"에 답하려고
  "photoCount": 2,
  "lastPhoto": "<base64>",            // 직전 자동 전송 사진. 10분 지나면 쓰지 않음
  "lastPhotoAt": 1793777766620,
  "lastHelperRequestId": "r_…",        // "엄마 답 왔어?"
  "assistantHistory": [ { "user": true, "text": "…" } ]  // 개별 기능의 최근 몇 마디
}
```

- 키에 `userId`가 들어가 있어 다른 사람의 세션 id를 알아도 읽을 수 없습니다(게이트웨이가 확인한 `X-User-Id`로만 키를 만듦).
- 사진은 이 세션에만, 최대 10분 쓰고, 세션과 함께 30분 안에 사라집니다. DB에는 남기지 않습니다. constitution IV의 두 번째 예외입니다.
- Redis는 디스크 저장(RDB·AOF)을 끕니다(docker-compose `--save "" --appendonly no`). 재시작하면 세션이 사라지는 게 맞는 동작입니다.
- 필드 이름은 agent 코드(`session/AgentSession.java`, agent PR #4 기준)가 원본입니다. 바꾸면 이 표를 고칩니다.
