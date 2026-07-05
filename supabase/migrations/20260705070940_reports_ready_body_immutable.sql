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
end $$ language plpgsql;;
