-- 설계 확인용 검사. schema.sql을 실행한 DB에서 돌립니다. 끝에 ROLLBACK 하므로 데이터는 남지 않습니다.
--   psql -v ON_ERROR_STOP=1 -d fashion -f docs/infra/db/checks.sql
-- 하나라도 틀리면 오류로 멈추고, 모두 맞으면 마지막에 "checks: all passed"가 나옵니다.
-- 검사 항목은 specs/005-database/spec.md의 FR 번호와 같습니다.

\set QUIET on
\o /dev/null
BEGIN;
SET LOCAL timezone = 'Asia/Seoul';

-- 넣으면 거부돼야 하는 문장: 정해진 SQLSTATE로 실패하면 통과
CREATE FUNCTION pg_temp.must_fail(label text, stmt text, state text) RETURNS void AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = state THEN RAISE NOTICE 'PASS  %', label; RETURN; END IF;
    RAISE EXCEPTION 'FAIL  % (기대 %, 실제 % %)', label, state, SQLSTATE, SQLERRM;
  END;
  RAISE EXCEPTION 'FAIL  % (거부돼야 하는데 들어감)', label;
END $$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.must_be(label text, actual anyelement, expected anyelement) RETURNS void AS $$
BEGIN
  IF actual IS NOT DISTINCT FROM expected THEN RAISE NOTICE 'PASS  %', label;
  ELSE RAISE EXCEPTION 'FAIL  % (기대 %, 실제 %)', label, expected, actual; END IF;
END $$ LANGUAGE plpgsql;

-- 384차원 벡터 만들기: 첫 칸만 a, 둘째 칸만 b, 나머지 0.01
CREATE FUNCTION pg_temp.vec(a real, b real) RETURNS public.vector AS $$
  SELECT (('[' || a || ',' || b || ',' || array_to_string(array_fill(0.01::real, ARRAY[382]), ',') || ']'))::public.vector
$$ LANGUAGE sql;

-- ---------------------------------------------------------------- account
INSERT INTO account.users (id, provider, firebase_uid) VALUES
  ('00000000-0000-0000-0000-00000000000a', 'apple',  'fb_a'),
  ('00000000-0000-0000-0000-00000000000b', 'google', 'fb_b');
INSERT INTO account.users (id, provider, dev_device_id) VALUES
  ('00000000-0000-0000-0000-00000000000d', 'dev', 'device-1');

SELECT pg_temp.must_fail('FR-A1 같은 Firebase 계정은 한 사용자',
  $q$INSERT INTO account.users (provider, firebase_uid) VALUES ('google', 'fb_a')$q$, '23505');
SELECT pg_temp.must_fail('FR-A1 apple·google은 firebase_uid 필수',
  $q$INSERT INTO account.users (provider) VALUES ('apple')$q$, '23514');
SELECT pg_temp.must_fail('FR-A2 dev는 기기 id 필수',
  $q$INSERT INTO account.users (provider, firebase_uid) VALUES ('dev', 'x')$q$, '23514');
SELECT pg_temp.must_fail('FR-A1 로그인 방법은 apple·google·dev만',
  $q$INSERT INTO account.users (provider, firebase_uid) VALUES ('kakao', 'k1')$q$, '23514');

INSERT INTO account.profiles (user_id, height_cm) VALUES ('00000000-0000-0000-0000-00000000000a', 172.5);
SELECT pg_temp.must_be('FR-A3 키만 말하고 나머지는 건너뛰기',
  (SELECT name IS NULL AND agent_name IS NULL FROM account.profiles WHERE user_id = '00000000-0000-0000-0000-00000000000a'), true);
SELECT pg_temp.must_fail('FR-A4 키 300cm 거부',
  $q$UPDATE account.profiles SET height_cm = 300 WHERE user_id = '00000000-0000-0000-0000-00000000000a'$q$, '23514');
SELECT pg_temp.must_fail('FR-A4 몸무게 5kg 거부',
  $q$UPDATE account.profiles SET weight_kg = 5 WHERE user_id = '00000000-0000-0000-0000-00000000000a'$q$, '23514');
SELECT pg_temp.must_fail('FR-A3 에이전트 이름 공백 거부',
  $q$UPDATE account.profiles SET agent_name = '  ' WHERE user_id = '00000000-0000-0000-0000-00000000000a'$q$, '23514');

-- 같은 폰이 다른 계정으로 로그인: 토큰 주인만 바뀜 (gateway가 쓰는 upsert 그대로)
INSERT INTO account.push_tokens (user_id, token, platform) VALUES ('00000000-0000-0000-0000-00000000000a', 'tok-1', 'ios');
INSERT INTO account.push_tokens (user_id, token, platform) VALUES ('00000000-0000-0000-0000-00000000000a', 'tok-2', 'android');
INSERT INTO account.push_tokens (user_id, token, platform) VALUES ('00000000-0000-0000-0000-00000000000b', 'tok-1', 'ios')
  ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, last_seen_at = now(), updated_at = now();
SELECT pg_temp.must_be('FR-A5 폰 두 대 + 같은 폰은 주인 하나',
  (SELECT string_agg(token || '=' || right(user_id::text, 1), ',' ORDER BY token) FROM account.push_tokens
    WHERE token IN ('tok-1', 'tok-2')), 'tok-1=b,tok-2=a');

INSERT INTO account.refresh_tokens (user_id, token_hash, expires_at)
  VALUES ('00000000-0000-0000-0000-00000000000a', repeat('a', 64), now() + interval '30 days');
SELECT pg_temp.must_fail('FR-A6 같은 갱신 토큰 해시 두 번 저장 금지',
  $q$INSERT INTO account.refresh_tokens (user_id, token_hash, expires_at) VALUES ('00000000-0000-0000-0000-00000000000b', repeat('a', 64), now())$q$, '23505');

-- ---------------------------------------------------------------- schedule
INSERT INTO schedule.events (id, user_id, title, start_at, place, place_category, occasion, occasion_source) VALUES
  ('e_1', '00000000-0000-0000-0000-00000000000a', '면접',   '2026-11-20T10:00:00+09:00', '판교 사옥', '회사',   'formal',  'title'),
  ('e_2', '00000000-0000-0000-0000-00000000000a', '결혼식', '2026-11-20T14:00:00+09:00', '더채플',   '예식장', 'wedding', 'place'),
  ('e_3', '00000000-0000-0000-0000-00000000000a', '운동',   '2026-11-21T00:30:00+09:00', NULL,       NULL,     'active',  'title'),
  ('e_4', '00000000-0000-0000-0000-00000000000b', '회의',   '2026-11-20T09:00:00+09:00', NULL,       NULL,     'business','title');

SELECT pg_temp.must_be('FR-S3 하루 일정은 그 사람 것만, 서울 날짜 기준, 시간 순',
  (SELECT string_agg(id, ',' ORDER BY start_at) FROM schedule.events
    WHERE user_id = '00000000-0000-0000-0000-00000000000a'
      AND start_at >= '2026-11-20T00:00:00+09:00' AND start_at < '2026-11-21T00:00:00+09:00'), 'e_1,e_2');
SELECT pg_temp.must_fail('FR-S1 제목 공백 거부',
  $q$INSERT INTO schedule.events (id, user_id, title, start_at) VALUES ('e_x', '00000000-0000-0000-0000-00000000000a', '  ', now())$q$, '23514');
SELECT pg_temp.must_fail('FR-S2 자리 종류는 6개 중 하나',
  $q$INSERT INTO schedule.events (id, user_id, title, start_at, occasion) VALUES ('e_x', '00000000-0000-0000-0000-00000000000a', '파티', now(), 'party')$q$, '23514');
INSERT INTO schedule.events (id, user_id, title, start_at) VALUES ('e_5', '00000000-0000-0000-0000-00000000000b', '약속', '2026-11-22T12:00:00+09:00');
SELECT pg_temp.must_be('FR-S2 장소를 못 찾으면 평상·기본값',
  (SELECT occasion || '/' || occasion_source FROM schedule.events WHERE id = 'e_5'), 'casual/default');

-- 아침 8시: 오늘 일정 중 알림 안 보낸 것만, 보낸 뒤에는 다시 안 잡힘
UPDATE schedule.events SET notified_at = now() WHERE id = 'e_1';
SELECT pg_temp.must_be('FR-S4 알림은 일정마다 한 번',
  (SELECT string_agg(id, ',' ORDER BY id) FROM schedule.events
    WHERE id IN ('e_1', 'e_2', 'e_3', 'e_4', 'e_5') AND notified_at IS NULL AND start_at >= '2026-11-20T00:00:00+09:00' AND start_at < '2026-11-21T00:00:00+09:00'), 'e_2,e_4');

-- ---------------------------------------------------------------- closet
INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, formality, description, embedding) VALUES
  ('c_1', '00000000-0000-0000-0000-00000000000a', 'top',   '셔츠',   '흰색',   'white', 'light', 'smart',  '{"pattern":"solid"}', pg_temp.vec(1, 0)),
  ('c_2', '00000000-0000-0000-0000-00000000000a', 'top',   '니트',   '흰색',   'white', 'light', 'casual', '{"pattern":"solid"}', pg_temp.vec(0.9, 0.3)),
  ('c_3', '00000000-0000-0000-0000-00000000000a', 'outer', '자켓',   '회색',   'gray',  'mid',   'smart',  '{}',                  pg_temp.vec(0, 1)),
  ('c_9', '00000000-0000-0000-0000-00000000000b', 'top',   '셔츠',   '흰색',   'white', 'light', 'smart',  '{}',                  pg_temp.vec(1, 0));

-- 같은 옷 찾기: 내 옷 중 종류·색 계열이 같고 가장 가까운 것 (agent가 정한 기준값 이상이면 합침)
SELECT pg_temp.must_be('FR-C2 같은 옷 후보는 내 옷·같은 종류·같은 색 계열에서만',
  (SELECT id FROM closet.garments
    WHERE user_id = '00000000-0000-0000-0000-00000000000a' AND category = 'top' AND color_family = 'white'
    ORDER BY embedding OPERATOR(public.<=>) pg_temp.vec(1, 0.05) LIMIT 1), 'c_1');
SELECT pg_temp.must_be('FR-C2 유사도 계산(코사인 1 - 거리)',
  (SELECT round((1 - (embedding OPERATOR(public.<=>) pg_temp.vec(1, 0)))::numeric, 3) FROM closet.garments WHERE id = 'c_1'), 1.000);

INSERT INTO closet.wears (user_id, garment_id, worn_on) VALUES ('00000000-0000-0000-0000-00000000000a', 'c_1', '2026-11-19');
INSERT INTO closet.wears (user_id, garment_id, worn_on) VALUES ('00000000-0000-0000-0000-00000000000a', 'c_1', '2026-11-19')
  ON CONFLICT ON CONSTRAINT wears_garment_day_uq DO NOTHING;
SELECT pg_temp.must_be('FR-C4 같은 날 같은 옷은 한 번만', (SELECT count(*) FROM closet.wears WHERE garment_id = 'c_1'), 1::bigint);
SELECT pg_temp.must_fail('FR-C4 남의 옷에 입은 날 기록 금지',
  $q$INSERT INTO closet.wears (user_id, garment_id, worn_on) VALUES ('00000000-0000-0000-0000-00000000000b', 'c_1', '2026-11-20')$q$, '23503');

-- closet_search: 내 옷만, 제외 목록 빼고, 가까운 순, 마지막으로 입은 날 함께
SELECT pg_temp.must_be('FR-C5·C6 후보 검색(내 옷, 제외 목록, 최대 개수)',
  (SELECT string_agg(id || '@' || coalesce(last_worn::text, '-'), ',') FROM (
     SELECT g.id, (SELECT max(w.worn_on) FROM closet.wears w WHERE w.garment_id = g.id) AS last_worn
       FROM closet.garments g
      WHERE g.user_id = '00000000-0000-0000-0000-00000000000a' AND g.id <> ALL (ARRAY['c_2'])
      ORDER BY g.embedding OPERATOR(public.<=>) pg_temp.vec(1, 0.1) LIMIT 5) t), 'c_1@2026-11-19,c_3@-');

SELECT pg_temp.must_fail('FR-C1 종류는 정해진 6개 중 하나',
  $q$INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, description) VALUES ('c_x', '00000000-0000-0000-0000-00000000000a', 'hat', '모자', '검정', 'black', 'dark', '{}')$q$, '23514');
SELECT pg_temp.must_fail('FR-C1 설명은 JSON 객체',
  $q$INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, description) VALUES ('c_x', '00000000-0000-0000-0000-00000000000a', 'top', '티', '검정', 'black', 'dark', '[]')$q$, '23514');
SELECT pg_temp.must_fail('FR-C1 임베딩은 384차원',
  $q$INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, description, embedding) VALUES ('c_x', '00000000-0000-0000-0000-00000000000a', 'top', '티', '검정', 'black', 'dark', '{}', '[1,2,3]')$q$, '22000');

-- 코디 지식: Spring AI PgVectorStore와 같은 모양으로 넣고 찾기(메타데이터로 자리 거르기)
INSERT INTO closet.style_docs (content, metadata, embedding) VALUES
  ('면접에는 어두운 슬랙스와 셔츠', '{"source":"style_docs/interview.md","chunkNo":0,"occasion":"formal"}',  pg_temp.vec(1, 0)),
  ('결혼식 하객은 흰 상의를 피한다', '{"source":"style_docs/wedding.md","chunkNo":0,"occasion":"wedding"}',  pg_temp.vec(0.8, 0.2)),
  ('장례식은 검정·무채색',          '{"source":"style_docs/mourning.md","chunkNo":0,"occasion":"mourning"}', pg_temp.vec(0, 1));
SELECT pg_temp.must_fail('FR-C7 같은 문서 조각 두 번 넣기 금지',
  $q$INSERT INTO closet.style_docs (content, metadata, embedding) VALUES ('중복', '{"source":"style_docs/interview.md","chunkNo":0}', pg_temp.vec(1, 0))$q$, '23505');
SELECT pg_temp.must_be('FR-C7 코디 지식 검색(출처와 함께, 자리로 거르기)',
  (SELECT metadata::jsonb ->> 'source' FROM closet.style_docs
    WHERE metadata::jsonb @@ '$.occasion == "formal"'
    ORDER BY embedding OPERATOR(public.<=>) pg_temp.vec(1, 0) LIMIT 1), 'style_docs/interview.md');

-- ---------------------------------------------------------------- helper
INSERT INTO helper.contacts (id, user_id, name, phone, relation) VALUES
  ('h_1', '00000000-0000-0000-0000-00000000000a', '엄마', '01012345678', '가족');
SELECT pg_temp.must_fail('FR-H1 같은 사용자가 같은 번호 두 번 등록 금지',
  $q$INSERT INTO helper.contacts (id, user_id, name, phone) VALUES ('h_2', '00000000-0000-0000-0000-00000000000a', '엄마2', '01012345678')$q$, '23505');
SELECT pg_temp.must_fail('FR-H1 전화번호는 숫자만',
  $q$INSERT INTO helper.contacts (id, user_id, name, phone) VALUES ('h_2', '00000000-0000-0000-0000-00000000000a', '아빠', '010-1234-5678')$q$, '23514');
INSERT INTO helper.contacts (id, user_id, name, phone) VALUES
  ('h_3', '00000000-0000-0000-0000-00000000000b', '엄마', '01012345678');  -- 다른 사용자는 같은 번호 가능

INSERT INTO helper.requests (id, user_id, contact_id, question, image_key, token, expires_at) VALUES
  ('r_1', '00000000-0000-0000-0000-00000000000a', 'h_1', '이 옷 괜찮아?', 'helper/r_1.jpg', 'tk1', now() - interval '1 hour'),
  ('r_2', '00000000-0000-0000-0000-00000000000a', 'h_1', '이건?',          'helper/r_2.jpg', 'tk2', now() + interval '23 hours');
SELECT pg_temp.must_fail('FR-H3 답함이면 답과 답한 시각 필수',
  $q$UPDATE helper.requests SET status = 'answered' WHERE id = 'r_2'$q$, '23514');
-- 첫 답만 인정: pending일 때만 바뀜
UPDATE helper.requests SET status = 'answered', answer = '좋아', answered_at = now() WHERE token = 'tk2' AND status = 'pending';
UPDATE helper.requests SET status = 'answered', answer = '별로', answered_at = now() WHERE token = 'tk2' AND status = 'pending';
SELECT pg_temp.must_be('FR-H5 첫 답만 인정', (SELECT answer FROM helper.requests WHERE id = 'r_2'), '좋아');
-- 만료 스케줄러: 지난 pending은 expired + 사진 키 지움
UPDATE helper.requests SET status = 'expired', image_key = NULL, updated_at = now()
 WHERE status = 'pending' AND expires_at < now();
SELECT pg_temp.must_be('FR-H4 만료된 요청은 expired, 사진 키 없음',
  (SELECT status || '/' || coalesce(image_key, 'null') FROM helper.requests WHERE id = 'r_1'), 'expired/null');

-- ---------------------------------------------------------------- 공통
SELECT pg_temp.must_be('FR-X1 스키마를 넘는 FK 0개',
  (SELECT count(*) FROM pg_constraint c
     JOIN pg_class s ON s.oid = c.conrelid JOIN pg_class t ON t.oid = c.confrelid
    WHERE c.contype = 'f' AND s.relnamespace <> t.relnamespace), 0::bigint);
SELECT pg_temp.must_be('FR-X2 user_id가 없는 표는 account.users·closet.style_docs뿐',
  (SELECT string_agg(table_schema || '.' || table_name, ',' ORDER BY table_schema, table_name) FROM information_schema.tables t
    WHERE table_schema IN ('account', 'schedule', 'closet', 'helper') AND table_type = 'BASE TABLE'
      AND table_name <> 'flyway_schema_history'
      AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                       WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name AND c.column_name = 'user_id')),
  'account.users,closet.style_docs');
SELECT pg_temp.must_be('FR-X3 시간 컬럼은 모두 timestamptz',
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema IN ('account', 'schedule', 'closet', 'helper') AND table_name <> 'flyway_schema_history'
      AND data_type = 'timestamp without time zone'), 0::bigint);
SELECT pg_temp.must_be('FR-X4 사진 원본을 담을 bytea 컬럼 0개',
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema IN ('account', 'schedule', 'closet', 'helper') AND data_type = 'bytea'), 0::bigint);

\echo 'checks: all passed'
ROLLBACK;
