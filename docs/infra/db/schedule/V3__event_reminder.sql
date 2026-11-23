-- 일정마다 폰 알림을 받을지, 며칠 전 저녁에 미리 알릴지(2026-11-11 진행 님).
-- 일정을 넣으면 agent가 "일정 전에 알림을 드릴까요?" → "며칠 전에 미리 알려 드릴까요?"를 묻고 schedule_set_reminder로 저장합니다.
-- 앱이 이 값을 보고 폰에 알림을 예약합니다. 묻기 전 일정(remind_days_before가 null)은 전날 저녁 + 당일 아침입니다.
ALTER TABLE events ADD COLUMN remind boolean NOT NULL DEFAULT TRUE;
ALTER TABLE events ADD COLUMN remind_days_before integer;
