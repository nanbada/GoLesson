-- GoLesson functions & triggers (docs/04_DATABASE.md section 3)

-- Refresh student_textbooks cache when progress is saved
create or replace function trg_update_last_position() returns trigger as $$
begin
  update student_textbooks
     set last_position = new.to_value, last_progress_at = new.created_at
   where id = new.student_textbook_id;
  return new;
end $$ language plpgsql;
create trigger t_progress_cache after insert on lesson_progress
  for each row execute function trg_update_last_position();

-- Auto-refresh updated_at (attached to lessons, payments, reports, notification_outbox)
create or replace function trg_set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end $$ language plpgsql;
create trigger t_lessons_updated_at before update on lessons
  for each row execute function trg_set_updated_at();
create trigger t_payments_updated_at before update on payments
  for each row execute function trg_set_updated_at();
create trigger t_reports_updated_at before update on reports
  for each row execute function trg_set_updated_at();
create trigger t_outbox_updated_at before update on notification_outbox
  for each row execute function trg_set_updated_at();

-- Audit trail for lessons/payments: record before/after on update/delete.
-- One shared trigger function attached to both tables (payment_items changes
-- count as an update of the parent payment).
-- security definer: audits has RLS enabled with no client write GRANT, so the
-- insert must run with definer privileges when fired by an authenticated user.
create or replace function trg_audit_row() returns trigger as $$
begin
  if tg_op = 'UPDATE' then
    insert into audits (table_name, row_id, action, changed_by, before, after)
    values (tg_table_name, old.id, 'update', auth.uid(), to_jsonb(old), to_jsonb(new));
    return new;
  else
    insert into audits (table_name, row_id, action, changed_by, before, after)
    values (tg_table_name, old.id, 'delete', auth.uid(), to_jsonb(old), null);
    return old;
  end if;
end $$ language plpgsql security definer set search_path = public;
create trigger t_lessons_audit after update or delete on lessons
  for each row execute function trg_audit_row();
create trigger t_payments_audit after update or delete on payments
  for each row execute function trg_audit_row();

-- Enforce sent-report immutability (REQ-1004, BR-405) -- the DB blocks it, not a comment.
-- Full-row jsonb comparison (minus updated_at) instead of a column list: also
-- blocks sent_at/created_by/created_at tampering and covers future columns.
create or replace function trg_reports_immutable() returns trigger as $$
begin
  if old.status = 'sent'
     and (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    raise exception 'sent report is immutable (REQ-1004)';
  end if;
  return new;
end $$ language plpgsql;
create trigger t_reports_immutable before update on reports
  for each row execute function trg_reports_immutable();
-- ready->sent transition (Bridge) passes because old.status='ready'.
-- After sent, everything except updated_at is blocked.

-- Bridge outbox claim (PostgREST PATCH cannot do computed updates like
-- attempts+1 -> atomic claim via RPC)
create or replace function claim_outbox(p_limit int default 5)
returns setof notification_outbox as $$
  update notification_outbox o
     set status = 'processing', attempts = o.attempts + 1, updated_at = now()
   where o.id in (
     select id from notification_outbox
      where status = 'pending'
      order by created_at
      for update skip locked
      limit p_limit)
  returning o.*;
$$ language sql security definer set search_path = public;

-- service_role only. Revoking from public alone would also strip service_role
-- (PostgREST sets role per request), so grant it back explicitly.
revoke execute on function claim_outbox(int) from public, anon, authenticated;
grant execute on function claim_outbox(int) to service_role;
