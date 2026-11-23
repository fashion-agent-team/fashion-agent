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
