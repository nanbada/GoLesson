-- QA Fixtures for MVP testing (aidd_docs/fixtures/mvp-seed-data.md §1~§5)
-- Idempotent: safe to re-run. Wraps in a transaction.

begin;

-- 1. Students (GoAlimi sync, with stable fake goalimi_student_id values)
insert into students (goalimi_student_id, name, grade, active, synced_at)
values
  (9001, '김민수', '초5', true, now()),
  (9002, '이서연', '초4', true, now()),
  (9003, '박지호', '초6', true, now()),
  (7707, '신성화', null, true, now())
on conflict (goalimi_student_id) do nothing;

-- 2. Parents (one primary per student, notify_enabled=true)
-- Dummy kakao_name for 9001/9002/9003 (never send); 7707 uses the operator account
insert into parents (goalimi_parent_id, student_id, kakao_name, notify_enabled, is_primary)
values
  (90001, (select id from students where goalimi_student_id = 9001), '테스트-민수모', true, true),
  (90002, (select id from students where goalimi_student_id = 9002), '테스트-서연모', true, true),
  (90003, (select id from students where goalimi_student_id = 9003), '테스트-지호모', true, true),
  (77071, (select id from students where goalimi_student_id = 7707), '신성화', true, true)
on conflict (goalimi_parent_id) do nothing;

-- 3. Textbooks (§2)
insert into textbooks (subject, title, unit_label, total_units, aliases, active)
select item.subject, item.title, item.unit_label, item.total_units, item.aliases, item.active
from (values
  ('영어', 'Bricks Reading 3', '페이지', 400, array['브릭스', 'bricks']::text[], true),
  ('영어', '리딩 엑스퍼트 1', '페이지', 120, array['리딩']::text[], true),
  ('영어', '보카 트레이닝', 'Day', 60, array['단어', '단어장', '보카']::text[], true),
  ('수학', '쎈 5-1', '페이지', 200, array['쎈']::text[], true),
  ('수학', '디딤돌 수학 4-2', '단원', 10, array['디딤돌']::text[], true)
) as item(subject, title, unit_label, total_units, aliases, active)
where not exists (
  select 1 from textbooks
  where title = item.title
);

-- 4. Student-textbook assignments (§3 with last_position)
insert into student_textbooks (student_id, textbook_id, status, last_position)
select s.id, t.id, item.status, item.last_position
from (values
  (9001, 'Bricks Reading 3', 'active', 38),
  (9001, '보카 트레이닝', 'active', 2),
  (9001, '쎈 5-1', 'active', 30),
  (9002, '쎈 5-1', 'active', 120),
  (9002, '디딤돌 수학 4-2', 'active', 2),
  (9003, '리딩 엑스퍼트 1', 'active', 50),
  (7707, 'Bricks Reading 3', 'active', 10)
) as item(goalimi_student_id, title, status, last_position)
join students s on s.goalimi_student_id = item.goalimi_student_id
join textbooks t on t.title = item.title
where not exists (
  select 1 from student_textbooks stb
  where stb.student_id = s.id
    and stb.textbook_id = t.id
    and stb.status = item.status
);

-- 5. Enrollments (subjects per student)
insert into enrollments (student_id, subject, active)
values
  ((select id from students where goalimi_student_id = 9001), '영어', true),
  ((select id from students where goalimi_student_id = 9001), '수학', true),
  ((select id from students where goalimi_student_id = 9002), '수학', true),
  ((select id from students where goalimi_student_id = 9003), '영어', true),
  ((select id from students where goalimi_student_id = 7707), '영어', true)
on conflict (student_id, subject) do nothing;

-- 6. Schedule slots (§4: weekday 0=Mon, duration=40min)
-- Student 9001: Mon/Thu 15:00 English, Tue/Fri 15:00 math
-- Student 9002: Mon/Wed 16:00 math
-- Student 9003: Tue/Thu 16:00 English
-- Student 7707: Mon 17:00 English
insert into schedule_slots (enrollment_id, weekday, start_time, duration_min)
select e.id, item.weekday, item.start_time::time, item.duration_min
from (values
  (9001, '영어', 0, '15:00', 40),
  (9001, '영어', 3, '15:00', 40),
  (9001, '수학', 1, '15:00', 40),
  (9001, '수학', 4, '15:00', 40),
  (9002, '수학', 0, '16:00', 40),
  (9002, '수학', 2, '16:00', 40),
  (9003, '영어', 1, '16:00', 40),
  (9003, '영어', 3, '16:00', 40),
  (7707, '영어', 0, '17:00', 40)
) as item(goalimi_student_id, subject, weekday, start_time, duration_min)
join students s on s.goalimi_student_id = item.goalimi_student_id
join enrollments e on e.student_id = s.id and e.subject = item.subject
where not exists (
  select 1 from schedule_slots ss
  where ss.enrollment_id = e.id
    and ss.weekday = item.weekday
    and ss.start_time = item.start_time::time
    and ss.duration_min = item.duration_min
);

-- 7. Lessons & Progress (section 5: student 7707 English, two completed Monday lessons in the last two weeks)
-- Calculate Monday dates: most recent Monday <= today, then 1 week prior
-- We use date arithmetic relative to current_date so seed stays valid any day
do $$
declare
  monday_this_week date;
  monday_last_week date;
  lesson1_id bigint;
  lesson2_id bigint;
  student_id_val bigint;
  stb_id_val bigint;
begin
  -- Find the most recent Monday (or today if today is Monday)
  monday_this_week := current_date - ((extract(isodow from current_date)::int - 1) % 7) * interval '1 day';
  monday_last_week := monday_this_week - interval '1 week';

  student_id_val := (select id from students where goalimi_student_id = 7707);
  stb_id_val := (select id from student_textbooks
                 where student_id = student_id_val
                   and textbook_id = (select id from textbooks where title = 'Bricks Reading 3'));

  -- Lesson 1: 1 week ago, progress 10→20
  select id into lesson1_id
  from lessons
  where student_id = student_id_val
    and subject = '영어'
    and lesson_date = monday_last_week
    and note = 'QA: lesson 1'
  limit 1;

  if lesson1_id is null then
    insert into lessons (student_id, subject, lesson_date, status, note)
    values (student_id_val, '영어', monday_last_week, 'done', 'QA: lesson 1')
    returning id into lesson1_id;
  end if;

  insert into lesson_progress (lesson_id, student_textbook_id, from_value, to_value, memo)
  select lesson1_id, stb_id_val, 10, 20, null
  where not exists (
    select 1 from lesson_progress
    where lesson_id = lesson1_id
      and student_textbook_id = stb_id_val
      and from_value = 10
      and to_value = 20
  );

  -- Lesson 2: most recent Monday, progress 20→28
  select id into lesson2_id
  from lessons
  where student_id = student_id_val
    and subject = '영어'
    and lesson_date = monday_this_week
    and note = 'QA: lesson 2'
  limit 1;

  if lesson2_id is null then
    insert into lessons (student_id, subject, lesson_date, status, note)
    values (student_id_val, '영어', monday_this_week, 'done', 'QA: lesson 2')
    returning id into lesson2_id;
  end if;

  insert into lesson_progress (lesson_id, student_textbook_id, from_value, to_value, memo)
  select lesson2_id, stb_id_val, 20, 28, null
  where not exists (
    select 1 from lesson_progress
    where lesson_id = lesson2_id
      and student_textbook_id = stb_id_val
      and from_value = 20
      and to_value = 28
  );
end $$;

-- 8. Homework (§5)
-- Student 9001: one unchecked take_home homework row
insert into homeworks (student_id, subject, description, kind, status)
select (select id from students where goalimi_student_id = 9001),
       '영어',
       '워크북 30-32',
       'take_home',
       'assigned'
where not exists (
  select 1 from homeworks
  where student_id = (select id from students where goalimi_student_id = 9001)
    and subject = '영어'
    and description = '워크북 30-32'
    and kind = 'take_home'
    and status = 'assigned'
);

-- Student 9003: one completed in_class homework row with a teacher comment
do $$
declare
  hw_id bigint;
  student_id_val bigint;
begin
  student_id_val := (select id from students where goalimi_student_id = 9003);

  insert into homeworks (student_id, subject, description, kind, status, teacher_comment, checked_at)
  select student_id_val, '영어', 'QA fixture homework', 'in_class', 'done', '집중 좋음', now()
  where not exists (
    select 1 from homeworks
    where student_id = student_id_val
      and subject = '영어'
      and description = 'QA fixture homework'
      and kind = 'in_class'
      and status = 'done'
      and teacher_comment = '집중 좋음'
  )
  returning id into hw_id;
end $$;

-- 9. Attendance (§5)
-- Student 7707: two IN events matching the lesson Mondays
do $$
declare
  monday_this_week date;
  monday_last_week date;
  student_id_val bigint;
  logid_counter integer := 77071001;
begin
  monday_this_week := current_date - ((extract(isodow from current_date)::int - 1) % 7) * interval '1 day';
  monday_last_week := monday_this_week - interval '1 week';
  student_id_val := (select id from students where goalimi_student_id = 7707);

  insert into attendance (goalimi_log_id, student_id, event_type, event_at)
  values
    (logid_counter, student_id_val, 'IN', monday_last_week::timestamp with time zone at time zone 'Asia/Seoul'),
    (logid_counter + 1, student_id_val, 'IN', monday_this_week::timestamp with time zone at time zone 'Asia/Seoul')
  on conflict (goalimi_log_id) do nothing;
end $$;

-- Student 9001: two IN events and two OUT events
do $$
declare
  student_id_val bigint;
  base_time timestamp with time zone;
  logid_counter integer := 90010001;
begin
  student_id_val := (select id from students where goalimi_student_id = 9001);
  base_time := (current_date - interval '3 days')::timestamp with time zone at time zone 'Asia/Seoul';

  insert into attendance (goalimi_log_id, student_id, event_type, event_at)
  values
    (logid_counter, student_id_val, 'IN', base_time),
    (logid_counter + 1, student_id_val, 'OUT', base_time + interval '40 minutes'),
    (logid_counter + 2, student_id_val, 'IN', base_time + interval '1 day'),
    (logid_counter + 3, student_id_val, 'OUT', base_time + interval '1 day 40 minutes')
  on conflict (goalimi_log_id) do nothing;
end $$;

-- 10. Payments (§5 & T7)
-- Student 9001, 2026-06-02, card payment: English 200,000 + math 200,000
-- Student 9002, 2026-06-03, cash payment: math 200,000
do $$
declare
  payment_id_1 bigint;
  payment_id_2 bigint;
begin
  select id into payment_id_1
  from payments
  where student_id = (select id from students where goalimi_student_id = 9001)
    and paid_on = '2026-06-02'::date
    and method = '카드'
  limit 1;

  if payment_id_1 is null then
    insert into payments (student_id, paid_on, method)
    values ((select id from students where goalimi_student_id = 9001), '2026-06-02'::date, '카드')
    returning id into payment_id_1;
  end if;

  insert into payment_items (payment_id, subject, amount)
  select payment_id_1, item.subject, item.amount
  from (values ('영어', 200000), ('수학', 200000)) as item(subject, amount)
  where not exists (
    select 1 from payment_items
    where payment_id = payment_id_1
      and subject = item.subject
      and amount = item.amount
  );

  select id into payment_id_2
  from payments
  where student_id = (select id from students where goalimi_student_id = 9002)
    and paid_on = '2026-06-03'::date
    and method = '현금'
  limit 1;

  if payment_id_2 is null then
    insert into payments (student_id, paid_on, method)
    values ((select id from students where goalimi_student_id = 9002), '2026-06-03'::date, '현금')
    returning id into payment_id_2;
  end if;

  insert into payment_items (payment_id, subject, amount)
  select payment_id_2, '수학', 200000
  where not exists (
    select 1 from payment_items
    where payment_id = payment_id_2
      and subject = '수학'
      and amount = 200000
  );
end $$;

commit;
