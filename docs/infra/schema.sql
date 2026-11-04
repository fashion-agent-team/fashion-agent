-- =====================================================================
-- 패션 에이전트 전체 DB (PostgreSQL 16 + pgvector)
-- 약속 문서 docs/contracts/README.md 7절: PostgreSQL 하나에 서비스마다 스키마 하나.
-- 다른 서비스의 스키마는 직접 읽지 않는다. 그래서 스키마를 넘는 FK는 두지 않고
-- user_id는 account.users.id를 "논리적으로" 가리킨다(값만 같음).
--
-- 각 서비스는 자기 스키마 부분만 Flyway V1__init.sql로 가져가 쓴다.
--   account  → fashion-agent-gateway
--   schedule → mcp-schedule
--   closet   → mcp-closet
--   helper   → mcp-helper
-- 시간은 모두 timestamptz(UTC 저장, 서버 시간대 Asia/Seoul로 읽음).
-- updated_at은 각 서비스가 JPA @PreUpdate로 갱신(트리거 없음, 서비스끼리 공유하는 함수가 없게).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS vector;     -- closet 임베딩 (gen_random_uuid()는 PG13+ 기본 내장)

CREATE SCHEMA IF NOT EXISTS account;
CREATE SCHEMA IF NOT EXISTS schedule;
CREATE SCHEMA IF NOT EXISTS closet;
CREATE SCHEMA IF NOT EXISTS helper;


-- =====================================================================
-- account (주인: gateway) : 계정·회원정보·푸시 토큰·리프레시 토큰
-- =====================================================================

CREATE TABLE account.users (
  id             uuid         PRIMARY KEY DEFAULT gen_random_uuid(),  -- JWT sub
  provider       varchar(10)  NOT NULL CHECK (provider IN ('apple', 'google', 'dev')),
  firebase_uid   varchar(128) UNIQUE,          -- apple·google 로그인. dev면 null
  dev_device_id  varchar(100) UNIQUE,          -- POST /auth/dev 의 deviceId. dev에서만
  last_login_at  timestamptz,
  created_at     timestamptz  NOT NULL DEFAULT now(),
  updated_at     timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT users_identity_ck CHECK (
    (provider = 'dev' AND dev_device_id IS NOT NULL) OR
    (provider <> 'dev' AND firebase_uid IS NOT NULL))
);

-- 온보딩에서 받은 회원정보. 사용자 1명당 1행, 모든 항목 건너뛰기 가능(null)
CREATE TABLE account.profiles (
  user_id     uuid          PRIMARY KEY REFERENCES account.users(id) ON DELETE CASCADE,
  name        varchar(50),
  birth_date  date,
  gender      varchar(10),                    -- 자유 입력(말로 받음). 예: 여성, 남성
  job         varchar(50),
  height_cm   numeric(4,1)  CHECK (height_cm BETWEEN 50 AND 250),
  weight_kg   numeric(4,1)  CHECK (weight_kg BETWEEN 10 AND 300),
  agent_name  varchar(30),                    -- null이면 온보딩 안 함
  created_at  timestamptz   NOT NULL DEFAULT now(),
  updated_at  timestamptz   NOT NULL DEFAULT now()
);

-- FCM 토큰 (PUT /api/v1/me/push-token). 한 사람이 폰 여러 대를 쓸 수 있어 1:N
CREATE TABLE account.push_tokens (
  id            bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       uuid         NOT NULL REFERENCES account.users(id) ON DELETE CASCADE,
  token         text         NOT NULL UNIQUE, -- 같은 폰이 다른 계정으로 로그인하면 user_id만 바꿈
  platform      varchar(10)  NOT NULL CHECK (platform IN ('ios', 'android')),
  last_seen_at  timestamptz  NOT NULL DEFAULT now(),
  created_at    timestamptz  NOT NULL DEFAULT now(),
  updated_at    timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX push_tokens_user_idx ON account.push_tokens (user_id);

-- 리프레시 토큰(30일). 원문은 저장하지 않고 SHA-256 해시만. 갱신할 때마다 새 토큰 발급 + 옛것 폐기
CREATE TABLE account.refresh_tokens (
  id          bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid         NOT NULL REFERENCES account.users(id) ON DELETE CASCADE,
  token_hash  char(64)     NOT NULL UNIQUE,
  expires_at  timestamptz  NOT NULL,
  revoked_at  timestamptz,
  created_at  timestamptz  NOT NULL DEFAULT now(),
  updated_at  timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx ON account.refresh_tokens (user_id);


-- =====================================================================
-- schedule (주인: mcp-schedule) : 일정 + 장소 분위기 + 아침 8시 알림
-- =====================================================================

CREATE TABLE schedule.events (
  id                varchar(40)   PRIMARY KEY,          -- "e_" + 임의 문자열 (도구의 eventId)
  user_id           uuid          NOT NULL,             -- account.users.id (FK 없음)
  title             varchar(200)  NOT NULL,
  start_at          timestamptz   NOT NULL,
  place             varchar(200),                       -- 사용자가 말한 장소 이름
  kakao_place_id    varchar(20),                        -- 카카오 로컬 검색 결과 id (못 찾으면 null)
  place_category    varchar(100),                       -- 카카오 분류의 마지막 마디. 예: 예식장
  occasion          varchar(20)   NOT NULL DEFAULT 'casual'
                    CHECK (occasion IN ('mourning', 'wedding', 'formal', 'business', 'active', 'casual')),
  occasion_source   varchar(10)   NOT NULL DEFAULT 'default'
                    CHECK (occasion_source IN ('title', 'place', 'default')),  -- 분위기를 무엇으로 정했나
  notified_at       timestamptz,                        -- 당일 8시 알림 보낸 시각. 아직이면 null
  created_at        timestamptz   NOT NULL DEFAULT now(),
  updated_at        timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT events_title_not_blank CHECK (length(trim(title)) > 0)
);
-- schedule_list(userId, date): 한 사람의 하루 범위 조회
CREATE INDEX events_user_start_idx ON schedule.events (user_id, start_at);
-- 아침 8시 스케줄러: "오늘 일정 중 아직 알림 안 보낸 것"만 훑음
CREATE INDEX events_unnotified_idx ON schedule.events (start_at) WHERE notified_at IS NULL;
-- (테스트를 H2로 돌리면 부분 인덱스가 안 되므로 그때는 (start_at) 일반 인덱스로 대신해도 됨)


-- =====================================================================
-- closet (주인: mcp-closet) : 내 옷장 + 입은 기록 + 코디 지식(RAG)
-- =====================================================================

CREATE TABLE closet.garments (
  id             varchar(40)   PRIMARY KEY,               -- "c_" + 임의 문자열 (garmentId)
  user_id        uuid          NOT NULL,
  category       varchar(10)   NOT NULL CHECK (category IN ('top', 'bottom', 'outer', 'dress', 'shoes', 'other')),
  name           varchar(50)   NOT NULL,                  -- 예: 니트
  color_name     varchar(30)   NOT NULL,                  -- 예: 차콜 그레이
  color_family   varchar(10)   NOT NULL CHECK (color_family IN ('black', 'white', 'gray', 'navy', 'beige', 'brown', 'khaki',
                                                              'blue', 'red', 'pink', 'orange', 'yellow', 'green', 'purple', 'unknown')),
  tone           varchar(5)    NOT NULL CHECK (tone IN ('light', 'mid', 'dark')),
  formality      varchar(10)   NOT NULL DEFAULT 'unknown' CHECK (formality IN ('formal', 'smart', 'casual', 'sporty', 'unknown')),
  description    jsonb         NOT NULL,                  -- 마지막으로 본 Garment 전체(pattern·material·notes·defects 등)
  embedding      vector(384),                             -- 설명 문장 임베딩. 같은 옷 합치기·closet_search
  first_seen_at  timestamptz   NOT NULL DEFAULT now(),
  last_seen_at   timestamptz   NOT NULL DEFAULT now(),
  created_at     timestamptz   NOT NULL DEFAULT now(),
  updated_at     timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX garments_user_category_idx ON closet.garments (user_id, category);
CREATE INDEX garments_embedding_idx ON closet.garments USING hnsw (embedding vector_cosine_ops);

-- 입은 날 (closet_wear). 같은 옷을 같은 날 두 번 기록하지 않음
CREATE TABLE closet.wears (
  id          bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid         NOT NULL,
  garment_id  varchar(40)  NOT NULL REFERENCES closet.garments(id) ON DELETE CASCADE,
  worn_on     date         NOT NULL,
  created_at  timestamptz  NOT NULL DEFAULT now(),
  updated_at  timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT wears_garment_day_uq UNIQUE (garment_id, worn_on)
);
CREATE INDEX wears_user_day_idx ON closet.wears (user_id, worn_on DESC);

-- 코디 지식 문서 조각(RAG). 모두가 같이 쓰는 지식이라 user_id 없음 (약속 문서 규칙의 유일한 예외)
CREATE TABLE closet.style_docs (
  id          bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source      varchar(200)  NOT NULL,                     -- 예: style_docs/interview.md
  chunk_no    int           NOT NULL DEFAULT 0,
  occasion    varchar(20)   CHECK (occasion IN ('mourning', 'wedding', 'formal', 'business', 'active', 'casual')),
  content     text          NOT NULL,
  embedding   vector(384)   NOT NULL,
  created_at  timestamptz   NOT NULL DEFAULT now(),
  updated_at  timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT style_docs_chunk_uq UNIQUE (source, chunk_no)
);
CREATE INDEX style_docs_embedding_idx ON closet.style_docs USING hnsw (embedding vector_cosine_ops);


-- =====================================================================
-- helper (주인: mcp-helper) : 가족·친구 연락처 + 확인 요청
-- =====================================================================

CREATE TABLE helper.contacts (
  id          varchar(40)  PRIMARY KEY,                   -- "h_" + 임의 문자열 (contactId)
  user_id     uuid         NOT NULL,
  name        varchar(50)  NOT NULL,                      -- 예: 엄마
  phone       varchar(20)  NOT NULL,                      -- 숫자만 저장(01000000000). API 응답·로그에 내보내지 않음
  relation    varchar(30),
  created_at  timestamptz  NOT NULL DEFAULT now(),
  updated_at  timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT contacts_user_phone_uq UNIQUE (user_id, phone)
);
CREATE INDEX contacts_user_idx ON helper.contacts (user_id);

CREATE TABLE helper.requests (
  id           varchar(40)  PRIMARY KEY,                  -- "r_" + 임의 문자열 (requestId)
  user_id      uuid         NOT NULL,
  contact_id   varchar(40)  NOT NULL REFERENCES helper.contacts(id) ON DELETE CASCADE,
  question     text         NOT NULL,
  image_key    varchar(200),                              -- R2 객체 키. 24시간 뒤 사진 지우면 null
  token        varchar(64)  NOT NULL UNIQUE,              -- /h/<token> 링크
  status       varchar(10)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'answered', 'expired')),
  answer       text,
  answered_at  timestamptz,
  expires_at   timestamptz  NOT NULL,
  created_at   timestamptz  NOT NULL DEFAULT now(),
  updated_at   timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT requests_answer_ck CHECK (status <> 'answered' OR (answer IS NOT NULL AND answered_at IS NOT NULL))
);
CREATE INDEX requests_user_idx ON helper.requests (user_id, created_at DESC);
-- 만료 처리 스케줄러: 아직 pending인 것만
CREATE INDEX requests_pending_expiry_idx ON helper.requests (expires_at) WHERE status = 'pending';

