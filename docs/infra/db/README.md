# DB 마이그레이션 (서비스별)

설계와 이유는 [specs/005-database](../../../specs/005-database/spec.md)에 있습니다(Spec Kit). 이 폴더는 그 설계를 실제로 실행하는 SQL입니다.

| 폴더 | 스키마 | 주인 레포 | 레포 안 위치 |
| --- | --- | --- | --- |
| [account/](account/V1__init.sql) | `account` | fashion-agent-gateway | `src/main/resources/db/migration/` |
| [schedule/](schedule/V1__init.sql) | `schedule` | mcp-schedule | 같음 (이미 들어가 있음, mcp-schedule#3) |
| [closet/](closet/V1__init.sql) | `closet` | mcp-closet | 같음 |
| [helper/](helper/V1__init.sql) | `helper` | mcp-helper(보관) | 쓰지 않음. `schema.sql`·`checks.sql`에서 뺐음 |

2026-11-20 기준 각 폴더는 그 레포 `develop`의 V4까지와 똑같습니다(account V1~V4, schedule V1~V4, closet V1~V4). 레포에 새 버전이 들어가면 이 폴더에도 같은 파일을 넣습니다.

agent·mcp-weather·mcp-clothes-state·mcp-face-check는 DB가 없습니다. agent의 대화 상태는 Redis에 둡니다(게이트웨이 사용량 제한은 메모리)([redis-keys.md](../../../specs/005-database/contracts/redis-keys.md)).

## 각 서비스에 넣는 법

1. 자기 폴더의 `V1__init.sql`을 레포의 `src/main/resources/db/migration/`에 그대로 복사합니다.
2. `application.yml`에 Flyway 설정을 넣습니다(mcp-schedule과 같은 방식).

   ```yaml
   spring:
     flyway:
       schemas: closet          # 자기 스키마
       default-schema: closet
       create-schemas: true
     jpa:
       hibernate.ddl-auto: validate
       properties.hibernate.default_schema: closet
   ```
3. 표를 바꿀 때는 이미 머지된 `V1`을 고치지 않고 `V2__설명.sql`을 더합니다. 이 폴더에도 같은 파일을 PR로 올립니다.

자세한 규칙은 [contracts/migrations.md](../../../specs/005-database/contracts/migrations.md)에 있습니다.

## 한 번에 만들어 보기 (로컬)

서비스 없이 DB만 확인할 때 씁니다. `../schema.sql`은 세 폴더(account·schedule·closet)를 이어 붙인 파일이라 손으로 고치지 않습니다.

```bash
./build-schema.sh                                     # 폴더의 V*.sql → ../schema.sql 다시 만들기
createdb fashion_check
psql -v ON_ERROR_STOP=1 -d fashion_check -f ../schema.sql
psql -v ON_ERROR_STOP=1 -d fashion_check -f checks.sql  # 마지막 줄 "checks: all passed"
psql -v ON_ERROR_STOP=1 -d fashion_check -f seed-dev.sql # 선택: 개발용 예시 데이터
```

`docker compose`로 띄운 DB에서 서비스들이 Flyway로 표를 만든 경우에도 `checks.sql`은 그대로 돌릴 수 있습니다(끝에 ROLLBACK, Flyway 이력 표는 검사에서 빼고, 이미 있는 데이터와 겹치지 않는 시험용 id만 씀). 세 서비스 표가 모두 있어야 합니다. 다만 `../schema.sql`을 서비스 DB에 직접 실행하면 Flyway 이력 표가 없어 서비스가 뜨지 않으니, 확인용 DB(`fashion_check`)에서만 쓰세요.

## 확인한 것 (2026-11-20, V4 정규화 뒤)

- PostgreSQL 16.15 + pgvector에서 `../schema.sql` 한 번에 실행 → 표 11개 (운영 젯슨은 PostgreSQL 17, 같은 마이그레이션이 Flyway로 적용됨)
- `checks.sql` 검사 36개 통과 (로그인 수단 (issuer, subject) UNIQUE, 장소 FK, 입은 날 (garment_id, worn_on) UNIQUE, 얼룩 기록과 옷 지우기, 사진 칸은 옷 작은 사진 하나, 스키마를 넘는 FK 0개 등)
- `seed-dev.sql` 두 번 실행해도 같은 결과

## 처음 확인한 것 (2026-11-04, V1)

- PostgreSQL 16.15 + pgvector 0.6.0에서 네 파일을 각각 **search_path를 그 스키마 하나로만 둔 채** 실행(Flyway보다 엄격한 조건) → 모두 성공
- `../schema.sql` 한 번에 실행 → 표 10개
- `checks.sql` 검사 34개 통과 (제약 조건, 하루 일정 조회, 8시 알림 한 번, 같은 옷 찾기, 옷장·코디 지식 검색, 첫 답만 인정, 만료, 스키마를 넘는 FK 0개 등)
- `seed-dev.sql` 두 번 실행해도 같은 결과
