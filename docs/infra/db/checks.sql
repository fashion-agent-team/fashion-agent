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
INSERT INTO account.users (id) VALUES
  ('00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000d');
INSERT INTO account.user_identities (user_id, issuer, subject, sign_in_provider) VALUES
  ('00000000-0000-0000-0000-00000000000a', 'firebase', 'fb_a',     'apple'),
  ('00000000-0000-0000-0000-00000000000b', 'firebase', 'fb_b',     'google'),
  ('00000000-0000-0000-0000-00000000000d', 'dev',      'device-1', 'dev');

SELECT pg_temp.must_fail('FR-A1 같은 Firebase 계정은 한 사용자 (issuer, subject) UNIQUE',
  $q$INSERT INTO account.user_identities (user_id, issuer, subject, sign_in_provider) VALUES ('00000000-0000-0000-0000-00000000000b', 'firebase', 'fb_a', 'google')$q$, '23505');
SELECT pg_temp.must_fail('FR-A1 issuer는 firebase·dev만',
  $q$INSERT INTO account.user_identities (user_id, issuer, subject, sign_in_provider) VALUES ('00000000-0000-0000-0000-00000000000a', 'kakao', 'k1', 'apple')$q$, '23514');
SELECT pg_temp.must_fail('FR-A1 로그인 방법은 apple·google·dev만',
  $q$INSERT INTO account.user_identities (user_id, issuer, subject, sign_in_provider) VALUES ('00000000-0000-0000-0000-00000000000a', 'firebase', 'k1', 'kakao')$q$, '23514');
-- 같은 subject라도 issuer가 다르면 다른 로그인 수단
INSERT INTO account.user_identities (user_id, issuer, subject, sign_in_provider)
  VALUES ('00000000-0000-0000-0000-00000000000d', 'firebase', 'device-1', 'google');
-- 로그인: (issuer, subject)로 사용자 찾기 (gateway AccountStore.login과 같은 모양)
SELECT pg_temp.must_be('FR-A2 로그인 수단으로 계정 찾기, 한 계정에 수단 여러 개',
  (SELECT string_agg(issuer || ':' || subject, ',' ORDER BY issuer) FROM account.user_identities
    WHERE user_id = '00000000-0000-0000-0000-00000000000d'), 'dev:device-1,firebase:device-1');

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
INSERT INTO schedule.places (kakao_place_id, place_name, category) VALUES
  ('k_1', '판교 사옥', '회사'),
  ('k_2', '더채플',   '예식장');
INSERT INTO schedule.events (id, user_id, title, start_at, place, kakao_place_id, occasion, occasion_source) VALUES
  ('e_1', '00000000-0000-0000-0000-00000000000a', '면접',   '2026-11-20T10:00:00+09:00', '판교 사옥', 'k_1', 'formal',  'title'),
  ('e_2', '00000000-0000-0000-0000-00000000000a', '결혼식', '2026-11-20T14:00:00+09:00', '더채플',   'k_2', 'wedding', 'place'),
  ('e_3', '00000000-0000-0000-0000-00000000000a', '운동',   '2026-11-21T00:30:00+09:00', NULL,       NULL,  'active',  'title'),
  ('e_4', '00000000-0000-0000-0000-00000000000b', '회의',   '2026-11-20T09:00:00+09:00', NULL,       NULL,  'business','title');

SELECT pg_temp.must_be('FR-S3 하루 일정은 그 사람 것만, 서울 날짜 기준, 시간 순',
  (SELECT string_agg(id, ',' ORDER BY start_at) FROM schedule.events
    WHERE user_id = '00000000-0000-0000-0000-00000000000a'
      AND start_at >= '2026-11-20T00:00:00+09:00' AND start_at < '2026-11-21T00:00:00+09:00'), 'e_1,e_2');
SELECT pg_temp.must_be('FR-S2 장소 분류는 places에서 (일정에는 장소 id만)',
  (SELECT p.category FROM schedule.events e JOIN schedule.places p USING (kakao_place_id) WHERE e.id = 'e_2'), '예식장');
SELECT pg_temp.must_fail('FR-S2 places에 없는 카카오 장소 id 거부',
  $q$INSERT INTO schedule.events (id, user_id, title, start_at, kakao_place_id) VALUES ('e_x', '00000000-0000-0000-0000-00000000000a', '약속', now(), 'k_none')$q$, '23503');
SELECT pg_temp.must_fail('FR-S1 제목 공백 거부',
  $q$INSERT INTO schedule.events (id, user_id, title, start_at) VALUES ('e_x', '00000000-0000-0000-0000-00000000000a', '  ', now())$q$, '23514');
SELECT pg_temp.must_fail('FR-S2 자리 종류는 6개 중 하나',
  $q$INSERT INTO schedule.events (id, user_id, title, start_at, occasion) VALUES ('e_x', '00000000-0000-0000-0000-00000000000a', '파티', now(), 'party')$q$, '23514');
INSERT INTO schedule.events (id, user_id, title, start_at) VALUES ('e_5', '00000000-0000-0000-0000-00000000000b', '약속', '2026-11-22T12:00:00+09:00');
SELECT pg_temp.must_be('FR-S2 장소를 못 찾으면 평상·기본값, 알림은 켜짐·며칠 전은 아직 안 물음',
  (SELECT occasion || '/' || occasion_source || '/' || remind || '/' || coalesce(remind_days_before::text, 'null')
     FROM schedule.events WHERE id = 'e_5'), 'casual/default/true/null');

-- 아침 8시: 오늘 일정 중 알림 안 보낸 것만, 보낸 뒤에는 다시 안 잡힘
UPDATE schedule.events SET notified_at = now() WHERE id = 'e_1';
SELECT pg_temp.must_be('FR-S4 알림은 일정마다 한 번',
  (SELECT string_agg(id, ',' ORDER BY id) FROM schedule.events
    WHERE id IN ('e_1', 'e_2', 'e_3', 'e_4', 'e_5') AND notified_at IS NULL AND start_at >= '2026-11-20T00:00:00+09:00' AND start_at < '2026-11-21T00:00:00+09:00'), 'e_2,e_4');

-- ---------------------------------------------------------------- closet
INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, formality, pattern, embedding) VALUES
  ('c_1', '00000000-0000-0000-0000-00000000000a', 'top',   '셔츠',   '흰색',   'white', 'light', 'smart',  'solid', pg_temp.vec(1, 0)),
  ('c_2', '00000000-0000-0000-0000-00000000000a', 'top',   '니트',   '흰색',   'white', 'light', 'casual', 'solid', pg_temp.vec(0.9, 0.3)),
  ('c_3', '00000000-0000-0000-0000-00000000000a', 'outer', '자켓',   '회색',   'gray',  'mid',   'smart',  NULL,    pg_temp.vec(0, 1)),
  ('c_9', '00000000-0000-0000-0000-00000000000b', 'top',   '셔츠',   '흰색',   'white', 'light', 'smart',  NULL,    pg_temp.vec(1, 0));

-- 같은 옷 찾기: 내 옷 중 종류·색 계열이 같고 가장 가까운 것 (agent가 정한 기준값 이상이면 합침)
SELECT pg_temp.must_be('FR-C2 같은 옷 후보는 내 옷·같은 종류·같은 색 계열에서만',
  (SELECT id FROM closet.garments
    WHERE user_id = '00000000-0000-0000-0000-00000000000a' AND category = 'top' AND color_family = 'white'
    ORDER BY embedding OPERATOR(public.<=>) pg_temp.vec(1, 0.05) LIMIT 1), 'c_1');
SELECT pg_temp.must_be('FR-C2 유사도 계산(코사인 1 - 거리)',
  (SELECT round((1 - (embedding OPERATOR(public.<=>) pg_temp.vec(1, 0)))::numeric, 3) FROM closet.garments WHERE id = 'c_1'), 1.000);

INSERT INTO closet.wears (garment_id, worn_on) VALUES ('c_1', '2026-11-19');
INSERT INTO closet.wears (garment_id, worn_on) VALUES ('c_1', '2026-11-19')
  ON CONFLICT ON CONSTRAINT wears_garment_day_uq DO NOTHING;
SELECT pg_temp.must_be('FR-C4 같은 날 같은 옷은 한 번만 (garment_id, worn_on) UNIQUE', (SELECT count(*) FROM closet.wears WHERE garment_id = 'c_1'), 1::bigint);
SELECT pg_temp.must_fail('FR-C4 없는 옷에 입은 날 기록 금지',
  $q$INSERT INTO closet.wears (garment_id, worn_on) VALUES ('c_none', '2026-11-20')$q$, '23503');
-- 입은 날의 주인은 옷을 따라감: 사용자별 입은 날은 garments와 조인
SELECT pg_temp.must_be('FR-C4 입은 날 주인은 옷의 주인',
  (SELECT string_agg(DISTINCT g.user_id::text, ',') FROM closet.wears w JOIN closet.garments g ON g.id = w.garment_id), '00000000-0000-0000-0000-00000000000a');

-- 얼룩·찢어짐: 옷마다 여러 줄, 옷을 지우면 같이 지워짐
INSERT INTO closet.garment_defects (garment_id, kind, location, confidence, checked_by) VALUES
  ('c_2', 'stain', '왼쪽 소매', 0.82, 'model'),
  ('c_2', 'tear',  NULL,        NULL, 'gpt');
SELECT pg_temp.must_fail('FR-C3 확신도는 0~1',
  $q$INSERT INTO closet.garment_defects (garment_id, kind, confidence) VALUES ('c_2', 'stain', 1.5)$q$, '23514');
SELECT pg_temp.must_fail('FR-C3 누가 봤는지는 model·gpt만',
  $q$INSERT INTO closet.garment_defects (garment_id, kind, checked_by) VALUES ('c_2', 'stain', 'human')$q$, '23514');

-- closet_search: 내 옷만, 제외 목록 빼고, 가까운 순, 마지막으로 입은 날 함께
SELECT pg_temp.must_be('FR-C5·C6 후보 검색(내 옷, 제외 목록, 최대 개수)',
  (SELECT string_agg(id || '@' || coalesce(last_worn::text, '-'), ',') FROM (
     SELECT g.id, (SELECT max(w.worn_on) FROM closet.wears w WHERE w.garment_id = g.id) AS last_worn
       FROM closet.garments g
      WHERE g.user_id = '00000000-0000-0000-0000-00000000000a' AND g.id <> ALL (ARRAY['c_2'])
      ORDER BY g.embedding OPERATOR(public.<=>) pg_temp.vec(1, 0.1) LIMIT 5) t), 'c_1@2026-11-19,c_3@-');

SELECT pg_temp.must_fail('FR-C1 종류는 정해진 6개 중 하나',
  $q$INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone) VALUES ('c_x', '00000000-0000-0000-0000-00000000000a', 'hat', '모자', '검정', 'black', 'dark')$q$, '23514');
SELECT pg_temp.must_fail('FR-C1 무늬 판단은 model·gpt만',
  $q$INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, pattern_checked_by) VALUES ('c_x', '00000000-0000-0000-0000-00000000000a', 'top', '티', '검정', 'black', 'dark', 'me')$q$, '23514');
SELECT pg_temp.must_fail('FR-C1 임베딩은 384차원',
  $q$INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, embedding) VALUES ('c_x', '00000000-0000-0000-0000-00000000000a', 'top', '티', '검정', 'black', 'dark', '[1,2,3]')$q$, '22000');
SELECT pg_temp.must_fail('FR-C1 옷 사진은 64KB 이하',
  $q$INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, thumbnail) VALUES ('c_x', '00000000-0000-0000-0000-00000000000a', 'top', '티', '검정', 'black', 'dark', decode(repeat('00', 70000), 'hex'))$q$, '23514');
DELETE FROM closet.garments WHERE id = 'c_2';
SELECT pg_temp.must_be('FR-C3 옷을 지우면 얼룩 기록도 지워짐', (SELECT count(*) FROM closet.garment_defects WHERE garment_id = 'c_2'), 0::bigint);

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

-- ---------------------------------------------------------------- 공통
SELECT pg_temp.must_be('FR-X1 스키마를 넘는 FK 0개',
  (SELECT count(*) FROM pg_constraint c
     JOIN pg_class s ON s.oid = c.conrelid JOIN pg_class t ON t.oid = c.confrelid
    WHERE c.contype = 'f' AND s.relnamespace <> t.relnamespace), 0::bigint);
-- V4 정규화(2026-11-20)로 주인이 다른 칸으로 정해지는 표에서는 user_id를 뺐습니다:
-- places(공용 장소), wears·garment_defects(garment_id → garments.user_id), style_docs(공용 지식)
SELECT pg_temp.must_be('FR-X2 user_id가 없는 표는 계정 자신·공용 표·옷을 따라가는 표뿐',
  (SELECT string_agg(table_schema || '.' || table_name, ',' ORDER BY table_schema, table_name) FROM information_schema.tables t
    WHERE table_schema IN ('account', 'schedule', 'closet') AND table_type = 'BASE TABLE'
      AND table_name <> 'flyway_schema_history'
      AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                       WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name AND c.column_name = 'user_id')),
  'account.users,closet.garment_defects,closet.style_docs,closet.wears,schedule.places');
SELECT pg_temp.must_be('FR-X3 시간 컬럼은 모두 timestamptz',
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema IN ('account', 'schedule', 'closet') AND table_name <> 'flyway_schema_history'
      AND data_type = 'timestamp without time zone'), 0::bigint);
SELECT pg_temp.must_be('FR-X4 사진 칸은 옷 부분 작은 사진(garments.thumbnail) 하나뿐',
  (SELECT string_agg(table_name || '.' || column_name, ',') FROM information_schema.columns
    WHERE table_schema IN ('account', 'schedule', 'closet') AND data_type = 'bytea'), 'garments.thumbnail');

\echo 'checks: all passed'
ROLLBACK;
