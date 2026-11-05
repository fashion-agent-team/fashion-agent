-- =====================================================================
-- 패션 에이전트 전체 DB (PostgreSQL 16 + pgvector). 손으로 고치지 마세요.
-- docs/infra/db/build-schema.sh 가 docs/infra/db/<서비스>/V*.sql 을 이어 붙여 만듭니다.
-- 설계: specs/005-database/data-model.md, 실행 확인: docs/infra/db/README.md
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS vector SCHEMA public;

-- ---------------------------------------------------------------------
-- schema: account
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS account;
SET search_path TO account, public;

-- >>> account/V1__init.sql
-- fashion-agent-gateway: account 스키마 (specs/005-database/data-model.md 1절)
-- Flyway 설정: spring.flyway.schemas=account, default-schema=account, create-schemas=true
-- 그래서 이 파일은 스키마 이름을 붙이지 않고 account 안에서 실행됩니다.
-- 이 스키마 안의 표끼리만 FK를 둡니다. 다른 서비스는 user_id 값만 같이 씁니다(FK 없음).

-- 계정. id가 JWT sub이자 모든 서비스의 user_id
CREATE TABLE users (
  id             uuid                     PRIMARY KEY DEFAULT gen_random_uuid(),
  provider       varchar(10)              NOT NULL,   -- 처음 가입한 방법. 계정 연결(Apple↔구글)은 Firebase가 같은 firebase_uid로 묶음
  firebase_uid   varchar(128)             UNIQUE,     -- apple·google. dev면 null
  dev_device_id  varchar(100)             UNIQUE,     -- POST /api/v1/auth/dev 의 deviceId. dev에서만
  last_login_at  timestamp with time zone,
  created_at     timestamp with time zone NOT NULL DEFAULT now(),
  updated_at     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT users_provider_check CHECK (provider IN ('apple', 'google', 'dev')),
  CONSTRAINT users_identity_check CHECK (
    (provider = 'dev' AND dev_device_id IS NOT NULL) OR
    (provider <> 'dev' AND firebase_uid IS NOT NULL))
);

-- 음성 온보딩 회원정보. 사용자당 1행, 항목마다 건너뛰기 가능(null)
-- agent_name이 있으면 온보딩을 마친 것으로 봄
CREATE TABLE profiles (
  user_id     uuid                     PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  name        varchar(50),
  birth_date  date,
  gender      varchar(20),                    -- 말로 받은 그대로(정해진 목록 아님)
  job         varchar(50),
  height_cm   numeric(4,1),
  weight_kg   numeric(4,1),
  agent_name  varchar(30),
  created_at  timestamp with time zone NOT NULL DEFAULT now(),
  updated_at  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT profiles_height_check CHECK (height_cm BETWEEN 50 AND 250),
  CONSTRAINT profiles_weight_check CHECK (weight_kg BETWEEN 10 AND 300),
  CONSTRAINT profiles_birth_check  CHECK (birth_date >= DATE '1900-01-01'),
  CONSTRAINT profiles_agent_name_not_blank CHECK (agent_name IS NULL OR length(trim(agent_name)) > 0)
);

-- FCM 토큰 (PUT /api/v1/me/push-token). 사용자 1 : 폰 N, 폰 1대는 주인 1명
CREATE TABLE push_tokens (
  id            bigint                   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       uuid                     NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token         text                     NOT NULL UNIQUE,   -- 같은 폰이 다른 계정으로 로그인하면 user_id만 바꿈
  platform      varchar(10)              NOT NULL,
  last_seen_at  timestamp with time zone NOT NULL DEFAULT now(),
  created_at    timestamp with time zone NOT NULL DEFAULT now(),
  updated_at    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT push_tokens_platform_check CHECK (platform IN ('ios', 'android'))
);
CREATE INDEX push_tokens_user_idx ON push_tokens (user_id);

-- 리프레시 토큰 30일. 원문 대신 SHA-256 hex. 갱신할 때마다 새로 발급하고 쓴 것은 revoked_at
CREATE TABLE refresh_tokens (
  id          bigint                   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid                     NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash  char(64)                 NOT NULL UNIQUE,
  expires_at  timestamp with time zone NOT NULL,
  revoked_at  timestamp with time zone,
  created_at  timestamp with time zone NOT NULL DEFAULT now(),
  updated_at  timestamp with time zone NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

-- ---------------------------------------------------------------------
-- schema: schedule
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS schedule;
SET search_path TO schedule, public;

-- >>> schedule/V1__init.sql
-- mcp-schedule: schedule 스키마 (프로젝트 DB 설계 db/schema.sql 의 schedule 부분)
-- Flyway가 schedule 스키마를 먼저 만들고(create-schemas) 이 파일을 그 안에서 실행합니다.
-- 테스트는 H2(PostgreSQL 모드)로도 돌기 때문에 둘 다 되는 문법만 씁니다.

CREATE TABLE events (
  id                varchar(40)              PRIMARY KEY,          -- "e_" + 임의 문자열 (도구의 eventId)
  user_id           uuid                     NOT NULL,             -- account.users.id (스키마가 달라 FK 없음)
  title             varchar(200)             NOT NULL,
  start_at          timestamp with time zone NOT NULL,
  place             varchar(200),                                  -- 사용자가 말한 장소 이름
  kakao_place_id    varchar(20),                                   -- 카카오 로컬 검색 결과 id (못 찾으면 null)
  place_category    varchar(100),                                  -- 카카오 분류의 마지막 마디. 예: 예식장
  occasion          varchar(20)              NOT NULL DEFAULT 'casual',
  occasion_source   varchar(10)              NOT NULL DEFAULT 'default',  -- 분위기를 무엇으로 정했나
  notified_at       timestamp with time zone,                      -- 당일 8시 알림 보낸 시각. 아직이면 null
  created_at        timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT events_occasion_check
    CHECK (occasion IN ('mourning', 'wedding', 'formal', 'business', 'active', 'casual')),
  CONSTRAINT events_occasion_source_check
    CHECK (occasion_source IN ('title', 'place', 'default')),
  CONSTRAINT events_title_not_blank CHECK (length(trim(title)) > 0)
);

-- schedule_list(userId, date): 한 사람의 하루 범위 조회
CREATE INDEX events_user_start_idx ON events (user_id, start_at);

-- 아침 8시 스케줄러. DB 설계는 부분 인덱스(WHERE notified_at IS NULL)지만 H2가 지원하지 않아 일반 인덱스로 둡니다.
CREATE INDEX events_start_idx ON events (start_at);

-- ---------------------------------------------------------------------
-- schema: closet
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS closet;
SET search_path TO closet, public;

-- >>> closet/V1__init.sql
-- mcp-closet: closet 스키마 (specs/005-database/data-model.md 3절)
-- Flyway 설정: spring.flyway.schemas=closet, default-schema=closet, create-schemas=true
-- pgvector 타입은 public 스키마의 확장이라 public.vector로 적습니다(search_path와 상관없이 동작).
-- 사진은 저장하지 않습니다. 옷의 설명(JSON)과 그 설명의 임베딩만 남깁니다.

CREATE EXTENSION IF NOT EXISTS vector SCHEMA public;

-- 내 옷. 같은 옷이면 새로 만들지 않고 last_seen_at·description·embedding만 바꿈
CREATE TABLE garments (
  id             varchar(40)              PRIMARY KEY,   -- "c_" + 임의 문자열 (도구의 garmentId)
  user_id        uuid                     NOT NULL,      -- account.users.id (FK 없음)
  category       varchar(10)              NOT NULL,
  name           varchar(50)              NOT NULL,      -- 예: 니트
  color_name     varchar(30)              NOT NULL,      -- 예: 차콜 그레이
  color_family   varchar(10)              NOT NULL,
  tone           varchar(5)               NOT NULL,
  formality      varchar(10)              NOT NULL DEFAULT 'unknown',
  description    jsonb                    NOT NULL,      -- 마지막으로 본 Garment 전체(pattern·material·defects 등)
  embedding      public.vector(384),                     -- multilingual-e5-small. 같은 옷 찾기·closet_search
  first_seen_at  timestamp with time zone NOT NULL DEFAULT now(),
  last_seen_at   timestamp with time zone NOT NULL DEFAULT now(),
  created_at     timestamp with time zone NOT NULL DEFAULT now(),
  updated_at     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT garments_category_check  CHECK (category IN ('top', 'bottom', 'outer', 'dress', 'shoes', 'other')),
  CONSTRAINT garments_color_family_check CHECK (color_family IN ('black', 'white', 'gray', 'navy', 'beige', 'brown', 'khaki',
                                                  'blue', 'red', 'pink', 'orange', 'yellow', 'green', 'purple', 'unknown')),
  CONSTRAINT garments_tone_check      CHECK (tone IN ('light', 'mid', 'dark')),
  CONSTRAINT garments_formality_check CHECK (formality IN ('formal', 'smart', 'casual', 'sporty', 'unknown')),
  CONSTRAINT garments_description_object CHECK (jsonb_typeof(description) = 'object'),
  CONSTRAINT garments_seen_order      CHECK (last_seen_at >= first_seen_at),
  CONSTRAINT garments_id_user_uq      UNIQUE (id, user_id)   -- wears가 (옷, 주인)을 함께 가리키게
);
-- 한 사람의 옷만 훑습니다(100벌 안팎). 벡터 근사 인덱스(HNSW)는 두지 않습니다:
-- 모든 사람의 옷에서 가까운 40개를 먼저 뽑은 뒤 user_id로 거르면 내 옷이 빠질 수 있어서입니다.
-- 내 옷만 골라 정확한 거리로 정렬하는 편이 빠르고 틀리지 않습니다(research.md R3).
CREATE INDEX garments_user_category_idx ON garments (user_id, category);
CREATE INDEX garments_user_seen_idx     ON garments (user_id, last_seen_at DESC);

-- 입은 날 (closet_wear). 같은 옷을 같은 날 두 번 기록하지 않음
CREATE TABLE wears (
  id          bigint                   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid                     NOT NULL,
  garment_id  varchar(40)              NOT NULL,
  worn_on     date                     NOT NULL,
  created_at  timestamp with time zone NOT NULL DEFAULT now(),
  updated_at  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT wears_garment_day_uq UNIQUE (garment_id, worn_on),
  -- 남의 옷에 내 입은 날이 붙지 않게: 옷과 주인을 함께 참조
  CONSTRAINT wears_garment_owner_fk FOREIGN KEY (garment_id, user_id)
    REFERENCES garments (id, user_id) ON DELETE CASCADE
);
CREATE INDEX wears_user_day_idx ON wears (user_id, worn_on DESC);

-- 코디 지식(RAG). 모두가 같이 쓰는 문서라 user_id 없음.
-- Spring AI PgVectorStore가 쓰는 표 모양(id, content, metadata, embedding) 그대로 둡니다.
--   spring.ai.vectorstore.pgvector: schema-name=closet, table-name=style_docs,
--   dimensions=384, distance-type=COSINE_DISTANCE, index-type=HNSW, initialize-schema=false
-- metadata 예: {"source":"style_docs/interview.md","chunkNo":3,"occasion":"formal"}
CREATE TABLE style_docs (
  id         uuid               PRIMARY KEY DEFAULT gen_random_uuid(),
  content    text               NOT NULL,
  metadata   json               NOT NULL,
  embedding  public.vector(384) NOT NULL
);
CREATE INDEX style_docs_embedding_idx ON style_docs USING hnsw (embedding public.vector_cosine_ops);
-- 같은 문서 조각을 두 번 넣지 않게(다시 넣을 때는 id를 source+chunkNo로 만든 UUID로 두면 PgVectorStore가 덮어씀)
CREATE UNIQUE INDEX style_docs_source_chunk_uq ON style_docs (((metadata::jsonb ->> 'source')), ((metadata::jsonb ->> 'chunkNo')));

-- ---------------------------------------------------------------------
-- schema: helper
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS helper;
SET search_path TO helper, public;

-- >>> helper/V1__init.sql
-- mcp-helper: helper 스키마 (specs/005-database/data-model.md 4절)
-- Flyway 설정: spring.flyway.schemas=helper, default-schema=helper, create-schemas=true

-- 가족·친구 연락처. 전화번호는 숫자만, 응답·로그·음성에 내보내지 않음
CREATE TABLE contacts (
  id          varchar(40)              PRIMARY KEY,   -- "h_" + 임의 문자열 (contactId)
  user_id     uuid                     NOT NULL,      -- account.users.id (FK 없음)
  name        varchar(50)              NOT NULL,      -- 예: 엄마
  phone       varchar(20)              NOT NULL,      -- 01012345678
  relation    varchar(30),
  created_at  timestamp with time zone NOT NULL DEFAULT now(),
  updated_at  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT contacts_user_phone_uq UNIQUE (user_id, phone),
  CONSTRAINT contacts_phone_digits  CHECK (phone ~ '^[0-9]{9,15}$'),
  CONSTRAINT contacts_name_not_blank CHECK (length(trim(name)) > 0)
);

-- 확인 요청. 사진은 R2에 24시간만, 지우면 image_key를 null로
CREATE TABLE requests (
  id           varchar(40)              PRIMARY KEY,   -- "r_" + 임의 문자열 (requestId)
  user_id      uuid                     NOT NULL,
  contact_id   varchar(40)              NOT NULL REFERENCES contacts (id) ON DELETE CASCADE,
  question     text                     NOT NULL,
  image_key    varchar(200),
  token        varchar(64)              NOT NULL UNIQUE,   -- /h/<token> 링크. 추측할 수 없는 임의 값
  status       varchar(10)              NOT NULL DEFAULT 'pending',
  answer       text,
  answered_at  timestamp with time zone,
  expires_at   timestamp with time zone NOT NULL,          -- 보낸 뒤 24시간
  created_at   timestamp with time zone NOT NULL DEFAULT now(),
  updated_at   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT requests_status_check CHECK (status IN ('pending', 'answered', 'expired')),
  CONSTRAINT requests_answer_check CHECK (status <> 'answered' OR (answer IS NOT NULL AND answered_at IS NOT NULL))
);
CREATE INDEX requests_user_idx ON requests (user_id, created_at DESC);
-- 만료 스케줄러: 아직 pending인 것만 훑음
CREATE INDEX requests_pending_expiry_idx ON requests (expires_at) WHERE status = 'pending';

RESET search_path;
