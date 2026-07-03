-- profiles seed -- docs/09 section 4.1 step 5.
-- Run AFTER inviting teacher accounts via Supabase Auth (step 4), in the SQL
-- editor or psql (postgres/service_role -- clients cannot write profiles).
--
-- WARNING: if this step is skipped, is_active_teacher() stays false and every
-- logged-in teacher is blocked from all data (docs/04 section 5).
--
-- Edit the rows below to the invited accounts, then run. Idempotent.

with teacher_list (email, name, role) as (
  values
    ('owner@example.com',    '원장 이름', 'owner'),
    ('teacher1@example.com', '강사 이름', 'teacher')
)
insert into profiles (id, name, role, active)
select u.id, t.name, t.role, true
from teacher_list t
join auth.users u on u.email = t.email
on conflict (id) do update
  set name = excluded.name, role = excluded.role, active = true;

-- Verify every invited account got a profiles row (no NULLs on the right side):
-- select u.email, p.name, p.role, p.active
-- from auth.users u left join profiles p on p.id = u.id;
