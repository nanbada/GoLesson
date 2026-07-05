-- Revert 20260705120000_reports_ready_body_immutable: drop the ready-body lock.
-- BR-506 (docs/06) deliberately keeps a ready report's body client-editable until
-- sent (locking it at 'ready' is 과설계 for the 1-person self-approval workflow).
-- The lock was also unnecessary for send safety: the Bridge sends
-- notification_outbox.message -- the snapshot taken at enqueue (bridge.py:296) --
-- never the live reports.body, so a post-approval edit can never reach a parent;
-- it only becomes a new version on an explicit resend. Restore the original
-- sent-only immutability, identical to 20260704090100.
create or replace function trg_reports_immutable() returns trigger as $$
begin
  if old.status = 'sent'
     and (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    raise exception 'sent report is immutable (REQ-1004)';
  end if;
  return new;
end $$ language plpgsql;
-- trigger t_reports_immutable already points at this function (no re-create needed).
