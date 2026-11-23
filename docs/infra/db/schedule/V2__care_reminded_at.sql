-- 격식 일정(면접·결혼식·장례식 등) 드라이클리닝 안내를 마친 시각.
-- 등록할 때 이미 3일 안쪽이라 그 자리에서 말했거나, 3일 전 알림을 보냈으면 채웁니다. 아직이면 null.
ALTER TABLE events ADD COLUMN care_reminded_at timestamp with time zone;
