-- Local dev seed. Runs automatically on `supabase db reset` (config.toml [db.seed]).
-- Production seeding is a manual step: supabase/seeds/*.sql (docs/09 section 4.1, steps 5 & 8).

insert into app_settings (key, value) values
  ('academy_name', '테스트학원'),
  ('report_greeting', '안녕하세요. 이번 기간 학습 내용을 정리해 보내드립니다.'),
  ('report_closing', '궁금하신 점은 언제든 연락 주세요. 감사합니다.'),
  ('goalimi_admin_url', 'http://192.168.0.100:8000/admin')
on conflict (key) do update set value = excluded.value;
