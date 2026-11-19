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
