-- app_settings seed -- docs/09 section 4.1 step 8.
-- Edit values before running. All values remain editable later in the settings
-- screen (docs/03_UI_SPEC section 7). Idempotent.

insert into app_settings (key, value) values
  ('academy_name', '루트원학원'),
  ('report_greeting', '안녕하세요. 이번 기간 학습 내용을 정리해 보내드립니다.'),
  ('report_closing', '궁금하신 점은 언제든 연락 주세요. 감사합니다.')
on conflict (key) do update set value = excluded.value;

-- 'bridge_last_poll_at' is not seeded here: the Bridge writes it every poll
-- cycle (docs/03_UI section 7 connectivity warning).
-- 'goalimi_admin_url' is not seeded here until the academy PC/LAN address is
-- confirmed. Settings screen can write it later.
