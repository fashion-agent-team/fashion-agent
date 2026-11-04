# 마이그레이션 약속 (Flyway)

## 파일

- 위치: 각 서비스 레포 `src/main/resources/db/migration/`. 같은 내용을 앱 레포 `docs/infra/db/<스키마>/`에도 둡니다.
- 이름: `V<번호>__<영어_설명>.sql` (예: `V2__add_garment_brand.sql`). 번호는 서비스마다 1부터.
- 파일 안에서는 스키마 이름을 붙이지 않습니다(`CREATE TABLE garments`). pgvector 타입만 `public.vector`로 적습니다.
- 머지된 파일은 **고치지 않습니다**. Flyway가 checksum이 바뀌었다고 서비스를 띄우지 않습니다. 고칠 일이 있으면 새 번호를 더합니다.
- 발표 전(2026-11-20)까지 아직 아무도 실제 데이터를 쌓지 않았다면, 팀이 합의하고 V1을 고친 뒤 각자 로컬 DB를 지우는 것도 허용합니다(이 경우 PR에 적기).

## 서비스 설정

```yaml
spring:
  flyway:
    schemas: <스키마>          # account | schedule | closet | helper
    default-schema: <스키마>
    create-schemas: true
  jpa:
    hibernate.ddl-auto: validate   # 표는 Flyway가, JPA는 확인만
    properties.hibernate.default_schema: <스키마>
```

closet은 추가로:

```yaml
spring:
  ai:
    vectorstore:
      pgvector:
        schema-name: closet
        table-name: style_docs
        dimensions: 384
        distance-type: COSINE_DISTANCE
        index-type: HNSW
        initialize-schema: false      # 표는 Flyway가 만듦
        schema-validation: true       # 모양이 다르면 뜰 때 알려 줌
```

## DB 계정

- 발표 범위에서는 모든 서비스가 같은 계정(`fashion`)을 씁니다(docker-compose `POSTGRES_USER`).
- 경계는 코드 리뷰로 지킵니다: 다른 스키마 이름이 들어간 SQL·엔티티는 머지하지 않습니다.
- 발표 후에는 서비스별 계정 + 자기 스키마 권한만 주는 것을 권장합니다(그때 `GRANT`용 V를 더함).

## 바꾸는 순서

1. 앱 레포에 `docs/infra/db/<스키마>/V<n>__….sql`과 `specs/005-database/data-model.md` 변경을 PR로 올립니다.
2. `./build-schema.sh`로 `schema.sql`을 다시 만들고 `checks.sql`이 통과하는지 확인합니다(필요하면 검사 추가).
3. 머지 뒤 같은 파일을 서비스 레포에 PR로 넣습니다.
