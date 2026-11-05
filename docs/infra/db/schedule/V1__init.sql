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
