-- Transactional write helpers for UI workflows that span multiple tables.
-- These stay SECURITY INVOKER so normal authenticated RLS/GRANT checks still
-- apply; the value is one database transaction, not privilege bypass.

create or replace function trg_normalize_progress_range() returns trigger as $$
declare
  v_from integer;
  v_to integer;
begin
  v_from := least(new.from_value, new.to_value);
  v_to := greatest(new.from_value, new.to_value);
  new.from_value := v_from;
  new.to_value := v_to;
  return new;
end $$ language plpgsql;

drop trigger if exists t_progress_normalize_range on lesson_progress;
create trigger t_progress_normalize_range
  before insert or update on lesson_progress
  for each row execute function trg_normalize_progress_range();

create or replace function save_lesson_log(p_payload jsonb)
returns bigint as $$
declare
  v_lesson_id bigint := (p_payload->>'lesson_id')::bigint;
  v_student_id bigint := (p_payload->>'student_id')::bigint;
  v_subject text := p_payload->>'subject';
  v_schedule_slot_id bigint := (p_payload->>'schedule_slot_id')::bigint;
  v_lesson_date date := coalesce((p_payload->>'lesson_date')::date, current_date);
  v_progress jsonb := p_payload->'progress';
  v_carryover jsonb := coalesce(p_payload->'carryover', '[]'::jsonb);
  v_new_homework jsonb := p_payload->'new_homework';
  v_comment text := nullif(btrim(coalesce(p_payload->>'comment', '')), '');
  v_parse_log_id bigint := (p_payload->>'parse_log_id')::bigint;
  v_stb_id bigint;
  v_from integer;
  v_to integer;
  v_row record;
  v_hw_description text;
  v_hw_kind text;
  v_hw_status text;
  v_hw_comment text;
begin
  if not is_active_teacher() then
    raise exception 'active teacher required' using errcode = '42501';
  end if;
  if v_progress is not null and jsonb_typeof(v_progress) = 'null' then
    v_progress := null;
  end if;
  if v_carryover is null or jsonb_typeof(v_carryover) = 'null' then
    v_carryover := '[]'::jsonb;
  end if;
  if v_new_homework is not null and jsonb_typeof(v_new_homework) = 'null' then
    v_new_homework := null;
  end if;
  if v_student_id is null or v_subject not in ('영어', '수학') then
    raise exception 'invalid lesson payload';
  end if;

  if v_lesson_id is null then
    insert into lessons (
      student_id, teacher_id, subject, schedule_slot_id, lesson_date,
      started_at, ended_at, status, note
    ) values (
      v_student_id, auth.uid(), v_subject, v_schedule_slot_id, v_lesson_date,
      now(), now(), 'done', v_comment
    )
    returning id into v_lesson_id;
  else
    update lessons
       set status = 'done',
           ended_at = now(),
           note = v_comment
     where id = v_lesson_id
       and student_id = v_student_id
       and subject = v_subject;
    if not found then
      raise exception 'lesson not found';
    end if;
  end if;

  if v_progress is not null and jsonb_typeof(v_progress) = 'object' then
    v_stb_id := (v_progress->>'student_textbook_id')::bigint;
    v_from := coalesce((v_progress->>'from_value')::integer, 0);
    v_to := (v_progress->>'to_value')::integer;

    if v_stb_id is not null and v_to is not null then
      perform 1
        from student_textbooks
       where id = v_stb_id
         and student_id = v_student_id
         and status <> 'completed'
       for update;
      if not found then
        raise exception 'active student_textbook not found';
      end if;

      insert into lesson_progress (
        lesson_id, student_textbook_id, from_value, to_value, memo
      ) values (
        v_lesson_id, v_stb_id, v_from, v_to,
        nullif(btrim(coalesce(v_progress->>'memo', '')), '')
      );

      if coalesce((v_progress->>'complete_assignment')::boolean, false) then
        update student_textbooks
           set status = 'completed',
               completed_on = current_date
         where id = v_stb_id;
      end if;
    end if;
  elsif v_progress is not null then
    raise exception 'progress must be an object';
  end if;

  if jsonb_typeof(v_carryover) <> 'array' then
    raise exception 'carryover must be an array';
  end if;

  for v_row in
    select *
      from jsonb_to_recordset(v_carryover)
        as x(id bigint, status text, comment text)
  loop
    if v_row.id is null or v_row.status not in ('done', 'partial', 'not_done') then
      raise exception 'invalid carryover homework';
    end if;
    update homeworks
       set status = v_row.status,
           teacher_comment = nullif(btrim(coalesce(v_row.comment, '')), ''),
           checked_at = now(),
           checked_lesson_id = v_lesson_id
     where id = v_row.id
       and student_id = v_student_id
       and subject = v_subject;
    if not found then
      raise exception 'carryover homework not found';
    end if;
  end loop;

  if v_new_homework is not null and jsonb_typeof(v_new_homework) = 'object' then
    v_hw_description := nullif(btrim(coalesce(v_new_homework->>'description', '')), '');
    if v_hw_description is not null then
      v_hw_kind := coalesce(v_new_homework->>'kind', 'in_class');
      v_hw_status := coalesce(v_new_homework->>'status', 'assigned');
      v_hw_comment := nullif(btrim(coalesce(v_new_homework->>'teacher_comment', '')), '');
      if v_hw_kind not in ('in_class', 'take_home') then
        raise exception 'invalid homework kind';
      end if;
      if v_hw_kind = 'take_home' then
        v_hw_status := 'assigned';
        v_hw_comment := null;
      elsif v_hw_status not in ('done', 'partial', 'not_done') then
        raise exception 'invalid homework status';
      end if;

      insert into homeworks (
        student_id, assigned_lesson_id, subject, description, kind, status,
        teacher_comment, checked_at, checked_lesson_id
      ) values (
        v_student_id, v_lesson_id, v_subject, v_hw_description, v_hw_kind,
        v_hw_status, v_hw_comment,
        case when v_hw_kind = 'take_home' then null else now() end,
        case when v_hw_kind = 'take_home' then null else v_lesson_id end
      );
    end if;
  elsif v_new_homework is not null then
    raise exception 'new_homework must be an object';
  end if;

  if v_comment is not null then
    insert into comments (student_id, lesson_id, subject, author_id, body)
    values (v_student_id, v_lesson_id, v_subject, auth.uid(), v_comment);
  end if;

  if v_parse_log_id is not null then
    update parse_logs
       set status = 'confirmed'
     where id = v_parse_log_id;
    if not found then
      raise exception 'parse log not found';
    end if;
  end if;

  return v_lesson_id;
end $$ language plpgsql set search_path = public;

revoke execute on function save_lesson_log(jsonb) from public, anon;
grant execute on function save_lesson_log(jsonb) to authenticated;

create or replace function save_payment_with_items(p_payload jsonb)
returns bigint as $$
declare
  v_payment_id bigint := (p_payload->>'payment_id')::bigint;
  v_student_id bigint := (p_payload->>'student_id')::bigint;
  v_paid_on date := coalesce((p_payload->>'paid_on')::date, current_date);
  v_method text := p_payload->>'method';
  v_memo text := nullif(btrim(coalesce(p_payload->>'memo', '')), '');
  v_items jsonb := p_payload->'items';
  v_expected integer;
  v_inserted integer;
begin
  if not is_active_teacher() then
    raise exception 'active teacher required' using errcode = '42501';
  end if;
  if v_student_id is null or v_method not in ('카드', '현금', '계좌이체', '기타') then
    raise exception 'invalid payment payload';
  end if;
  if v_items is null or jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    raise exception 'payment items required';
  end if;

  v_expected := jsonb_array_length(v_items);

  if v_payment_id is null then
    insert into payments (student_id, paid_on, method, memo, created_by)
    values (v_student_id, v_paid_on, v_method, v_memo, auth.uid())
    returning id into v_payment_id;
  else
    update payments
       set student_id = v_student_id,
           paid_on = v_paid_on,
           method = v_method,
           memo = v_memo
     where id = v_payment_id;
    if not found then
      raise exception 'payment not found';
    end if;
    delete from payment_items where payment_id = v_payment_id;
  end if;

  insert into payment_items (payment_id, subject, amount)
  select v_payment_id, nullif(btrim(subject), ''), amount
    from jsonb_to_recordset(v_items) as x(subject text, amount integer);
  get diagnostics v_inserted = row_count;

  if v_inserted <> v_expected then
    raise exception 'invalid payment item';
  end if;

  return v_payment_id;
end $$ language plpgsql set search_path = public;

revoke execute on function save_payment_with_items(jsonb) from public, anon;
grant execute on function save_payment_with_items(jsonb) to authenticated;
