-- 개발용 예시 데이터 (APP_ENV=dev에서만). 발표·운영 DB에는 넣지 않습니다.
--   psql -d fashion -f docs/infra/db/seed-dev.sql
-- 여러 번 실행해도 되게 ON CONFLICT로 씁니다. 일정은 실행할 때마다 그날(서울) 기준 오늘·내일로 다시 맞춥니다.
-- dev 로그인(POST /api/v1/auth/dev {"deviceId":"dev-seed-device"})이 이 사용자로 들어옵니다.
-- 그 deviceId로 먼저 로그인해 다른 id의 사용자가 이미 있으면 사용자는 넣지 않고, 아래 표들은 FK 오류로 멈춥니다(그 사용자를 지우고 다시 실행).

INSERT INTO account.users (id, last_login_at)
VALUES ('11111111-1111-1111-1111-111111111111', now())
ON CONFLICT DO NOTHING;

INSERT INTO account.user_identities (user_id, issuer, subject, sign_in_provider)
VALUES ('11111111-1111-1111-1111-111111111111', 'dev', 'dev-seed-device', 'dev')
ON CONFLICT (issuer, subject) DO NOTHING;

INSERT INTO account.profiles (user_id, name, job, height_cm, agent_name)
VALUES ('11111111-1111-1111-1111-111111111111', '테스트', '대학생', 172.0, '코디')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO schedule.places (kakao_place_id, place_name, category)
VALUES ('seed_1', '판교 사옥', '회사'), ('seed_2', '더채플앳청담', '예식장')
ON CONFLICT (kakao_place_id) DO NOTHING;

INSERT INTO schedule.events (id, user_id, title, start_at, place, kakao_place_id, occasion, occasion_source)
VALUES
  ('e_seed_1', '11111111-1111-1111-1111-111111111111', '면접',
   (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') + interval '10 hours') AT TIME ZONE 'Asia/Seoul',
   '판교 사옥', 'seed_1', 'formal', 'title'),
  ('e_seed_2', '11111111-1111-1111-1111-111111111111', '친구 결혼식',
   (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') + interval '1 day 14 hours') AT TIME ZONE 'Asia/Seoul',
   '더채플앳청담', 'seed_2', 'wedding', 'title')
ON CONFLICT (id) DO UPDATE SET start_at = EXCLUDED.start_at, notified_at = NULL, updated_at = now();

INSERT INTO closet.garments (id, user_id, category, name, color_name, color_family, tone, formality, pattern)
VALUES
  ('c_seed_1', '11111111-1111-1111-1111-111111111111', 'top',   '셔츠', '흰색', 'white', 'light', 'smart', 'solid'),
  ('c_seed_2', '11111111-1111-1111-1111-111111111111', 'outer', '자켓', '회색', 'gray',  'mid',   'smart', 'solid')
ON CONFLICT (id) DO NOTHING;
-- 임베딩은 SQL로 만들 수 없어 비워 둡니다. mcp-closet이 embedding IS NULL인 옷을 채웁니다(specs/005-database/tasks.md T014).
