-- Freeze the report body once approved (status='ready'), not only when sent.
-- Rationale (send safety, BR-405 / BR-500s): an approved report may already be
-- queued in notification_outbox (snapshot taken at enqueue). Editing the body
-- after approval made reports.body diverge from the queued message, so the
-- Bridge would send stale content. Lock the body at 'ready' so approve == final.
--
-- 'sent' keeps the existing full-row immutability. 'ready' locks ONLY the body,
-- so the Bridge's ready->sent completion (status + sent_at, body unchanged)
-- still passes.
create or replace function trg_reports_immutable() returns trigger as $$
begin
  if old.status = 'sent'
     and (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    raise exception 'sent report is immutable (REQ-1004)';
  end if;
  if old.status = 'ready' and new.body is distinct from old.body then
    raise exception 'approved (ready) report body is immutable';
  end if;
  return new;
end $$ language plpgsql;
-- trigger t_reports_immutable already points at this function (no re-create needed).
