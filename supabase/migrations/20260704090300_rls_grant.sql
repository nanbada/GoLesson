-- GoLesson RLS + GRANT (docs/04_DATABASE.md section 5)
-- Single academy (single tenant). Policies are split per table group -- no
-- shared "for all" policy (avoids write policies on read-only tables).
-- Note: Supabase projects created after 2026-05-30 need explicit GRANTs for
-- Data API exposure; RLS policies alone do not open PostgREST access.

-- 0) Enable RLS on every table + identity sequence usage
do $$ declare t text;
begin
  foreach t in array array[
    'profiles','students','parents','textbooks','student_textbooks','enrollments',
    'schedule_slots','lessons','lesson_progress','homeworks','comments','attendance',
    'payments','payment_items','reports','notification_outbox','parse_logs',
    'app_settings','audits']
  loop execute format('alter table %I enable row level security', t); end loop;
end $$;
grant usage on all sequences in schema public to authenticated;

-- 1) Shared helper (security definer -> no RLS recursion on profiles)
create or replace function is_active_teacher() returns boolean as $$
  select exists (select 1 from profiles pr where pr.id = auth.uid() and pr.active);
$$ language sql stable security definer set search_path = public;

-- 2) [Group A] read-only copies: students, parents, attendance
--    (no write GRANT at all -- writes are Bridge/service_role only)
do $$ declare t text;
begin
  foreach t in array array['students','parents','attendance'] loop
    execute format('grant select on %I to authenticated', t);
    execute format('create policy p_%s_sel on %I for select to authenticated using (is_active_teacher())', t, t);
  end loop;
end $$;

-- 3) [Group B] teacher select/insert/update (no delete -- deactivate/cancel/keep history)
do $$ declare t text;
begin
  foreach t in array array['textbooks','student_textbooks','enrollments','lessons',
                           'lesson_progress','comments','reports','app_settings'] loop
    execute format('grant select, insert, update on %I to authenticated', t);
    execute format('create policy p_%s_sel on %I for select to authenticated using (is_active_teacher())', t, t);
    execute format('create policy p_%s_ins on %I for insert to authenticated with check (is_active_teacher())', t, t);
    execute format('create policy p_%s_upd on %I for update to authenticated using (is_active_teacher()) with check (is_active_teacher())', t, t);
  end loop;
end $$;

-- 3-1) reports exception: send completion (status='sent') is owned by Bridge/
--      service_role (docs/05 section 3, BR-500s). Clients may only create or
--      move reports within draft/ready, so a sent report can never be spoofed
--      from the client side.
drop policy p_reports_ins on reports;
drop policy p_reports_upd on reports;
create policy p_reports_ins on reports for insert to authenticated
  with check (is_active_teacher() and status in ('draft','ready'));
create policy p_reports_upd on reports for update to authenticated
  using (is_active_teacher() and status <> 'sent')
  with check (is_active_teacher() and status in ('draft','ready'));

-- 4) [Group C] teacher CRUD + delete
do $$ declare t text;
begin
  foreach t in array array['schedule_slots','homeworks','payments','payment_items'] loop
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('create policy p_%s_sel on %I for select to authenticated using (is_active_teacher())', t, t);
    execute format('create policy p_%s_ins on %I for insert to authenticated with check (is_active_teacher())', t, t);
    execute format('create policy p_%s_upd on %I for update to authenticated using (is_active_teacher()) with check (is_active_teacher())', t, t);
    execute format('create policy p_%s_del on %I for delete to authenticated using (is_active_teacher())', t, t);
  end loop;
end $$;

-- 5) [Group D] system-owned: clients read only (writes via service_role/Edge Functions)
do $$ declare t text;
begin
  foreach t in array array['notification_outbox','parse_logs','audits'] loop
    execute format('grant select on %I to authenticated', t);
    execute format('create policy p_%s_sel on %I for select to authenticated using (is_active_teacher())', t, t);
  end loop;
end $$;

-- 5-1) parse_logs exception (docs/05_API section 2.1): the front may flip only
--      the status of its own rows to 'confirmed' when a save is finalized
grant update (status) on parse_logs to authenticated;   -- column-level GRANT: other columns stay blocked
create policy p_parse_logs_upd on parse_logs for update to authenticated
  using (is_active_teacher() and created_by = auth.uid())
  with check (is_active_teacher() and created_by = auth.uid());

-- 6) profiles: active teachers see all; a deactivated teacher still sees own row
--    (for the "account disabled" notice). Writes are service_role only.
grant select on profiles to authenticated;
create policy p_profiles_sel on profiles for select to authenticated
  using (is_active_teacher() or id = auth.uid());

-- 7) service_role explicit grants. BYPASSRLS skips RLS but not privileges;
--    projects without default privileges would otherwise block Bridge/Edge
--    Functions PostgREST calls (student sync upsert, outbox/report updates).
grant usage on schema public to authenticated, service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- anon: no GRANT and no policy anywhere -> fully blocked.
-- claim_outbox RPC: service_role only (revoked in 20260704090100).
-- Verification procedure: docs/10_ACCEPTANCE_TEST.md T10.
