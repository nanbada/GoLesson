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
-- Dummy kakao_name for 9001/9002/9003 (never send); 신성화 uses '신성화' (operator account)
insert into parents (goalimi_parent_id, student_id, kakao_name, notify_enabled, is_primary)
values
  (90001, (select id from students where goalimi_student_id = 9001), '테스트-민수모', true, true),
  (90002, (select id from students where goalimi_student_id = 9002), '테스트-서연모', true, true),
  (90003, (select id from students where goalimi_student_id = 9003), '테스트-지호모', true, true),
  (77071, (select id from students where goalimi_student_id = 7707), '신성화', true, true)
on conflict (goalimi_parent_id) do nothing;

-- 3. Textbooks (§2)
insert into textbooks (subject, title, unit_label, total_units, aliases, active)
values
  ('영어', 'Bricks Reading 3', '페이지', 400, array['브릭스', 'bricks'], true),
  ('영어', '리딩 엑스퍼트 1', '페이지', 120, array['리딩'], true),
  ('영어', '보카 트레이닝', 'Day', 60, array['단어', '단어장', '보카'], true),
  ('수학', '쎈 5-1', '페이지', 200, array['쎈'], true),
  ('수학', '디딤돌 수학 4-2', '단원', 10, array['디딤돌'], true)
on conflict do nothing;

-- 4. Student-textbook assignments (§3 with last_position)
insert into student_textbooks (student_id, textbook_id, status, last_position)
values
  ((select id from students where goalimi_student_id = 9001),
   (select id from textbooks where title = 'Bricks Reading 3'),
   'active', 38),
  ((select id from students where goalimi_student_id = 9001),
   (select id from textbooks where title = '보카 트레이닝'),
   'active', 2),
  ((select id from students where goalimi_student_id = 9001),
   (select id from textbooks where title = '쎈 5-1'),
   'active', 30),
  ((select id from students where goalimi_student_id = 9002),
   (select id from textbooks where title = '쎈 5-1'),
   'active', 120),
  ((select id from students where goalimi_student_id = 9002),
   (select id from textbooks where title = '디딤돌 수학 4-2'),
   'active', 2),
  ((select id from students where goalimi_student_id = 9003),
   (select id from textbooks where title = '리딩 엑스퍼트 1'),
   'active', 50),
  ((select id from students where goalimi_student_id = 7707),
   (select id from textbooks where title = 'Bricks Reading 3'),
   'active', 10)
on conflict do nothing;

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
-- 김민수: 월·목 15:00 영어, 화·금 15:00 수학
-- 이서연: 월·수 16:00 수학
-- 박지호: 화·목 16:00 영어
-- 신성화: 월 17:00 영어
insert into schedule_slots (enrollment_id, weekday, start_time, duration_min)
values
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 9001) and subject = '영어'),
   0, '15:00'::time, 40),
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 9001) and subject = '영어'),
   3, '15:00'::time, 40),
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 9001) and subject = '수학'),
   1, '15:00'::time, 40),
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 9001) and subject = '수학'),
   4, '15:00'::time, 40),
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 9002) and subject = '수학'),
   0, '16:00'::time, 40),
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 9002) and subject = '수학'),
   2, '16:00'::time, 40),
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 9003) and subject = '영어'),
   1, '16:00'::time, 40),
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 9003) and subject = '영어'),
   3, '16:00'::time, 40),
  ((select id from enrollments where student_id = (select id from students where goalimi_student_id = 7707) and subject = '영어'),
   0, '17:00'::time, 40)
on conflict do nothing;

-- 7. Lessons & Progress (§5: 신성화 영어 done 2회, within last 2 weeks on Mondays)
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
  insert into lessons (student_id, subject, lesson_date, status, note)
  values (student_id_val, '영어', monday_last_week, 'done', 'QA: lesson 1')
  returning id into lesson1_id;

  insert into lesson_progress (lesson_id, student_textbook_id, from_value, to_value, memo)
  values (lesson1_id, stb_id_val, 10, 20, null);

  -- Lesson 2: most recent Monday, progress 20→28
  insert into lessons (student_id, subject, lesson_date, status, note)
  values (student_id_val, '영어', monday_this_week, 'done', 'QA: lesson 2')
  returning id into lesson2_id;

  insert into lesson_progress (lesson_id, student_textbook_id, from_value, to_value, memo)
  values (lesson2_id, stb_id_val, 20, 28, null);
end $$;

-- 8. Homework (§5)
-- 김민수: take_home 1건 unchecked "워크북 30-32"
insert into homeworks (student_id, subject, description, kind, status)
values ((select id from students where goalimi_student_id = 9001),
        '영어', '워크북 30-32', 'take_home', 'assigned')
on conflict do nothing;

-- 박지호: in_class 1건 done with comment "집중 좋음"
do $$
declare
  hw_id bigint;
  student_id_val bigint;
begin
  student_id_val := (select id from students where goalimi_student_id = 9003);

  insert into homeworks (student_id, subject, description, kind, status, teacher_comment, checked_at)
  values (student_id_val, '영어', 'QA fixture homework', 'in_class', 'done', '집중 좋음', now())
  returning id into hw_id;
end $$;

-- 9. Attendance (§5)
-- 신성화: IN 2건 matching the lesson dates (mondays from lessons)
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

-- 김민수: IN/OUT 각 2건
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
-- 김민수 2026-06-02 카드 [영어 200,000 + 수학 200,000]
-- 이서연 2026-06-03 현금 [수학 200,000]
do $$
declare
  payment_id_1 bigint;
  payment_id_2 bigint;
begin
  insert into payments (student_id, paid_on, method)
  values ((select id from students where goalimi_student_id = 9001), '2026-06-02'::date, '카드')
  returning id into payment_id_1;

  insert into payment_items (payment_id, subject, amount)
  values
    (payment_id_1, '영어', 200000),
    (payment_id_1, '수학', 200000);

  insert into payments (student_id, paid_on, method)
  values ((select id from students where goalimi_student_id = 9002), '2026-06-03'::date, '현금')
  returning id into payment_id_2;

  insert into payment_items (payment_id, subject, amount)
  values (payment_id_2, '수학', 200000);
end $$;

commit;
