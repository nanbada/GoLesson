create or replace function trg_reports_immutable() returns trigger as $$
begin
  if old.status = 'sent'
     and (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    raise exception 'sent report is immutable (REQ-1004)';
  end if;
  return new;
end $$ language plpgsql;;
