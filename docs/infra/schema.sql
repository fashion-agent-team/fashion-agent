-- =====================================================================
-- 패션 에이전트 전체 DB (PostgreSQL 17 + pgvector). 손으로 고치지 마세요.
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

-- >>> account/V2__call_name.sql
-- 에이전트가 사용자를 부르는 말(호칭). 예: "진행 님". null이면 따로 부르지 않음.
ALTER TABLE profiles ADD COLUMN call_name varchar(30);

-- >>> account/V3__speech_rate.sql
-- 앱이 읽어 주는 말 빠르기(iOS 기준 0.5가 보통, 앱 기본 0.42). 다른 폰에서 로그인해도 같은 빠르기로 말하려고 저장. null이면 앱 기본값.
ALTER TABLE profiles ADD COLUMN speech_rate numeric(3,2);

-- >>> account/V4__user_identities.sql
-- 정규화(2026-11-20, 강사님 피드백): 로그인 수단을 users에서 user_identities로 뺍니다.
-- 예전 users는 provider에 따라 firebase_uid나 dev_device_id 중 하나만 차 있었습니다(칸이 provider에 기대는 구조).
-- 이제 users는 계정 자체만, 로그인 수단은 (issuer, subject) 한 줄씩. 한 계정에 여러 수단을 붙일 수 있습니다.
CREATE TABLE user_identities (
  id                bigint                   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id           uuid                     NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  issuer            varchar(10)              NOT NULL,   -- firebase(Apple·구글) | dev
  subject           varchar(128)             NOT NULL,   -- firebase uid 또는 POST /api/v1/auth/dev 의 deviceId
  sign_in_provider  varchar(10)              NOT NULL,   -- 마지막으로 쓴 방법 apple·google·dev. JWT provider 클레임
  created_at        timestamp with time zone NOT NULL DEFAULT now(),
  updated_at        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_identities_issuer_check   CHECK (issuer IN ('firebase', 'dev')),
  CONSTRAINT user_identities_provider_check CHECK (sign_in_provider IN ('apple', 'google', 'dev')),
  CONSTRAINT user_identities_subject_uq     UNIQUE (issuer, subject)
);
CREATE INDEX user_identities_user_idx ON user_identities (user_id);

INSERT INTO user_identities (user_id, issuer, subject, sign_in_provider, created_at)
SELECT id,
       CASE WHEN provider = 'dev' THEN 'dev' ELSE 'firebase' END,
       CASE WHEN provider = 'dev' THEN dev_device_id ELSE firebase_uid END,
       provider,
       created_at
  FROM users;

ALTER TABLE users DROP CONSTRAINT users_identity_check;
ALTER TABLE users DROP CONSTRAINT users_provider_check;
ALTER TABLE users DROP COLUMN provider;
ALTER TABLE users DROP COLUMN firebase_uid;
ALTER TABLE users DROP COLUMN dev_device_id;

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

-- >>> schedule/V2__care_reminded_at.sql
-- 격식 일정(면접·결혼식·장례식 등) 드라이클리닝 안내를 마친 시각.
-- 등록할 때 이미 3일 안쪽이라 그 자리에서 말했거나, 3일 전 알림을 보냈으면 채웁니다. 아직이면 null.
ALTER TABLE events ADD COLUMN care_reminded_at timestamp with time zone;

-- >>> schedule/V3__event_reminder.sql
-- 일정마다 폰 알림을 받을지, 며칠 전 저녁에 미리 알릴지(2026-11-11 진행 님).
-- 일정을 넣으면 agent가 "일정 전에 알림을 드릴까요?" → "며칠 전에 미리 알려 드릴까요?"를 묻고 schedule_set_reminder로 저장합니다.
-- 앱이 이 값을 보고 폰에 알림을 예약합니다. 묻기 전 일정(remind_days_before가 null)은 전날 저녁 + 당일 아침입니다.
ALTER TABLE events ADD COLUMN remind boolean NOT NULL DEFAULT TRUE;
ALTER TABLE events ADD COLUMN remind_days_before integer;

-- >>> schedule/V4__places.sql
-- 정규화(3NF): 장소 이름·분류는 kakao_place_id에 딸린 값이라 events에서 places로 뺍니다(2026-11-20, 강사님 피드백).
-- events.place는 사용자가 말한 장소 그대로 남기고, 카카오에서 찾은 장소는 kakao_place_id로만 가리킵니다.
CREATE TABLE places (
  kakao_place_id  varchar(20)              PRIMARY KEY,
  place_name      varchar(200)             NOT NULL,   -- 카카오에 등록된 이름
  category        varchar(100),                        -- 카카오 분류의 마지막 마디. 예: 예식장
  created_at      timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 이미 있는 일정의 장소를 옮김. 예전엔 카카오 이름을 따로 두지 않아서 말한 장소를 이름으로 씀.
INSERT INTO places (kakao_place_id, place_name, category)
SELECT kakao_place_id, MAX(COALESCE(place, kakao_place_id)), MAX(place_category)
  FROM events
 WHERE kakao_place_id IS NOT NULL
 GROUP BY kakao_place_id;

ALTER TABLE events DROP COLUMN place_category;
ALTER TABLE events ADD CONSTRAINT events_place_fk FOREIGN KEY (kakao_place_id) REFERENCES places (kakao_place_id);

-- >>> schedule/V5__event_remind_time.sql
-- 미리 알림을 몇 시에 띄울지(2026-11-20 정지원: "약속 2일 전 오후 4시에 알려 줘").
-- null이면 아침 8시입니다. remind_days_before가 0(당일만)이면 당일 알림 시각입니다.
-- 앱이 이 값을 보고 폰에 알림을 예약합니다. remind가 false면 null로 둡니다.
ALTER TABLE events ADD COLUMN remind_time time;

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

-- >>> closet/V2__image_embedding.sql
-- 옷 사진 벡터로 같은 옷 찾기 (mcp-clothes-state 이슈 #15)
-- clothes_inspect가 옷마다 준 이미지 벡터(Marqo FashionSigLIP, 768개)를 둡니다. 사진은 여전히 저장하지 않습니다.
-- 같은 옷을 다시 보면 지금까지 본 벡터의 평균으로 바꿉니다(image_count = 평균에 들어간 사진 수, 최대 closet.image.max-count).
-- 모델이 바뀌면 벡터끼리 비교할 수 없어서 image_model이 같은 옷끼리만 비교합니다.
ALTER TABLE garments
  ADD COLUMN image_embedding public.vector(768),
  ADD COLUMN image_model     varchar(40),
  ADD COLUMN image_count     integer NOT NULL DEFAULT 0,
  ADD CONSTRAINT garments_image_model_check CHECK ((image_embedding IS NULL) = (image_model IS NULL));

-- >>> closet/V3__thumbnail.sql
-- 옷 부분 작은 사진 (2026-11-12 박창근 결정)
-- 사진 유사도가 애매할 때(closet_save maybeSameAs) agent가 GPT에게 이번 사진과 예전 사진을 비교하게 하려고,
-- 옷 부분만 자른 작은 JPEG(긴 변 256px 안팎, 얼굴 없음)를 둡니다. 우리 서버 DB에만 있고, 옷을 지우면 함께 지워집니다.
-- 같은 옷을 다시 보면 최근 사진으로 바꿉니다.
ALTER TABLE garments
  ADD COLUMN thumbnail    bytea,
  ADD COLUMN thumbnail_at timestamp with time zone,
  ADD CONSTRAINT garments_thumbnail_size CHECK (thumbnail IS NULL OR octet_length(thumbnail) <= 65536);

-- >>> closet/V4__normalize.sql
-- 정규화(2026-11-20, 강사님 피드백)
-- 1) description(jsonb) 풀기: 옷 한 벌에 하나인 값(무늬·소재·메모·보조색)은 칸으로, 여러 개인 얼룩·찢어짐은 garment_defects로(1NF).
--    사진 속 위치(box·position)·인식 확신도는 그 사진 한 장의 값이라 옷장에 두지 않습니다.
-- 2) wears.user_id 빼기: garment_id만 알면 주인이 정해져서 중복이었습니다(3NF). 그래서 garments의 (id, user_id) UNIQUE도 필요 없어집니다.

ALTER TABLE garments ADD COLUMN pattern            varchar(30);
ALTER TABLE garments ADD COLUMN pattern_checked_by varchar(5);
ALTER TABLE garments ADD COLUMN pattern_guess      varchar(30);
ALTER TABLE garments ADD COLUMN material           varchar(50);
ALTER TABLE garments ADD COLUMN notes              varchar(500);
ALTER TABLE garments ADD COLUMN sub_color_name     varchar(30);
ALTER TABLE garments ADD COLUMN sub_color_family   varchar(10);

UPDATE garments SET
  pattern            = left(NULLIF(description ->> 'pattern', ''), 30),
  pattern_checked_by = CASE WHEN description ->> 'patternCheckedBy' IN ('model', 'gpt') THEN description ->> 'patternCheckedBy' END,
  pattern_guess      = left(NULLIF(description ->> 'patternGuess', ''), 30),
  material           = left(NULLIF(description ->> 'material', ''), 50),
  notes              = left(NULLIF(description ->> 'notes', ''), 500),
  sub_color_name     = left(NULLIF(description ->> 'subColorName', ''), 30),
  sub_color_family   = left(NULLIF(lower(description ->> 'subColorFamily'), ''), 10);

ALTER TABLE garments ADD CONSTRAINT garments_pattern_checked_by_check CHECK (pattern_checked_by IN ('model', 'gpt'));

CREATE TABLE garment_defects (
  id          bigint                   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  garment_id  varchar(40)              NOT NULL REFERENCES garments (id) ON DELETE CASCADE,
  kind        varchar(20)              NOT NULL,   -- stain·tear 등
  location    varchar(50),                         -- 어디쯤. 예: 왼쪽 소매
  confidence  numeric(4,3),
  checked_by  varchar(5),                          -- model | gpt
  created_at  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT garment_defects_checked_by_check CHECK (checked_by IN ('model', 'gpt')),
  CONSTRAINT garment_defects_confidence_check CHECK (confidence BETWEEN 0 AND 1)
);
CREATE INDEX garment_defects_garment_idx ON garment_defects (garment_id);

INSERT INTO garment_defects (garment_id, kind, location, confidence, checked_by)
SELECT g.id,
       left(d ->> 'kind', 20),
       left(NULLIF(d ->> 'where', ''), 50),
       CASE WHEN jsonb_typeof(d -> 'confidence') = 'number' AND (d ->> 'confidence')::numeric BETWEEN 0 AND 1
            THEN round((d ->> 'confidence')::numeric, 3) END,
       CASE WHEN d ->> 'checkedBy' IN ('model', 'gpt') THEN d ->> 'checkedBy' END
  FROM garments g
 CROSS JOIN LATERAL jsonb_array_elements(
         CASE WHEN jsonb_typeof(g.description -> 'defects') = 'array' THEN g.description -> 'defects' ELSE '[]'::jsonb END) d
 WHERE NULLIF(d ->> 'kind', '') IS NOT NULL;

ALTER TABLE garments DROP CONSTRAINT garments_description_object;
ALTER TABLE garments DROP COLUMN description;

ALTER TABLE wears DROP CONSTRAINT wears_garment_owner_fk;
DROP INDEX wears_user_day_idx;
ALTER TABLE wears DROP COLUMN user_id;
ALTER TABLE wears ADD CONSTRAINT wears_garment_fk FOREIGN KEY (garment_id) REFERENCES garments (id) ON DELETE CASCADE;
CREATE INDEX wears_day_idx ON wears (worn_on DESC);
ALTER TABLE garments DROP CONSTRAINT garments_id_user_uq;

RESET search_path;
