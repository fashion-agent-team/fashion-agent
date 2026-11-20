-- 미리 알림을 몇 시에 띄울지(2026-11-20 정지원: "약속 2일 전 오후 4시에 알려 줘").
-- null이면 아침 8시입니다. remind_days_before가 0(당일만)이면 당일 알림 시각입니다.
-- 앱이 이 값을 보고 폰에 알림을 예약합니다. remind가 false면 null로 둡니다.
ALTER TABLE events ADD COLUMN remind_time time;
