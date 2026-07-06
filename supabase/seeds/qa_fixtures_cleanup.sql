-- Remove GoLesson MVP QA fixture data from an operating Supabase project.
--
-- Intended use: after pilot/QA is finished, run
--   1) supabase/seeds/qa_fixtures_cleanup_preview.sql
--   2) this file
--
-- Preconditions:
-- - Stop Bridge or remove/deactivate the same test students in GoAlimi first.
--   Otherwise Bridge can sync 7707/9001/9002/9003 back into GoLesson.
-- - Confirm student 7707 is still only the test recipient, not production data.
-- - Run as database owner/service role from Supabase SQL editor or psql.
--
-- Safety:
-- - Student rows are selected only by stable fake GoAlimi IDs plus exact names.
-- - If a QA GoAlimi ID exists with a different name, this script aborts.
-- - QA textbooks are deleted only when no non-QA student is assigned to them.

begin;

create temp table _qa_expected_students (
  goalimi_student_id integer primary key,
  name text not null
) on commit drop;

insert into _qa_expected_students (goalimi_student_id, name)
values
  (9001, '김민수'),
  (9002, '이서연'),
  (9003, '박지호'),
  (7707, '신성화');

do $$
begin
  if exists (
    select 1
    from students s
    join _qa_expected_students e on e.goalimi_student_id = s.goalimi_student_id
    where s.name <> e.name
  ) then
    raise exception 'QA cleanup aborted: a QA goalimi_student_id exists with a non-fixture name. Inspect students 9001,9002,9003,7707 first.';
  end if;
end $$;

create temp table _qa_students on commit drop as
select s.id, s.goalimi_student_id, s.name
from students s
join _qa_expected_students e
  on e.goalimi_student_id = s.goalimi_student_id
 and e.name = s.name;

do $$
begin
  if exists (
    select 1
    from parents p
    where p.goalimi_parent_id in (90001, 90002, 90003, 77071)
      and p.student_id not in (select id from _qa_students)
  ) then
    raise exception 'QA cleanup aborted: a QA goalimi_parent_id points to a non-QA student.';
  end if;
end $$;

create temp table _qa_student_textbooks on commit drop as
select id from student_textbooks where student_id in (select id from _qa_students);

create temp table _qa_enrollments on commit drop as
select id from enrollments where student_id in (select id from _qa_students);

create temp table _qa_lessons on commit drop as
select id from lessons where student_id in (select id from _qa_students);

create temp table _qa_payments on commit drop as
select id from payments where student_id in (select id from _qa_students);

create temp table _qa_reports on commit drop as
select id from reports where student_id in (select id from _qa_students);

create temp table _qa_outbox on commit drop as
select id
from notification_outbox
where student_id in (select id from _qa_students)
   or report_id in (select id from _qa_reports);

create temp table _qa_parse_logs on commit drop as
select id
from parse_logs
where (
    result ? 'student_id'
    and (result->>'student_id') ~ '^[0-9]+$'
    and (result->>'student_id')::bigint in (select id from _qa_students)
  )
  or raw_text in (
    '민수 영어 브릭스 38-42 숙제 43~45 독해 좋아짐',
    '서연 수학 쎈 120~126 계산 실수 잦음',
    '민수 단어 Day3 완료',
    '지호 영어 38~42 (복습)',
    '서연 수학 3단원 숙제 워크북 12-15',
    '민수 오늘 집중 떨어졌지만 숙제는 열심히 함',
    '지호 영어 리딩 55까지 숙제 56-58 단어 Day7',
    '없는학생 영어 10-20',
    '서연 영어',
    '민수 수학 개념 이해 좋음 계산 속도 개선 필요'
  );

create temp table _qa_textbooks_orphan on commit drop as
select t.id
from textbooks t
where t.title in (
  'Bricks Reading 3',
  '리딩 엑스퍼트 1',
  '보카 트레이닝',
  '쎈 5-1',
  '디딤돌 수학 4-2'
)
and not exists (
  select 1
  from student_textbooks stb
  where stb.textbook_id = t.id
    and stb.student_id not in (select id from _qa_students)
);

create temp table _qa_cleanup_counts (
  table_name text primary key,
  deleted integer not null
) on commit drop;

with d as (delete from notification_outbox where id in (select id from _qa_outbox) returning 1)
insert into _qa_cleanup_counts select 'notification_outbox', count(*)::integer from d;

with d as (delete from reports where id in (select id from _qa_reports) returning 1)
insert into _qa_cleanup_counts select 'reports', count(*)::integer from d;

with d as (delete from parse_logs where id in (select id from _qa_parse_logs) returning 1)
insert into _qa_cleanup_counts select 'parse_logs', count(*)::integer from d;

with d as (delete from comments where student_id in (select id from _qa_students) returning 1)
insert into _qa_cleanup_counts select 'comments', count(*)::integer from d;

with d as (delete from homeworks where student_id in (select id from _qa_students) returning 1)
insert into _qa_cleanup_counts select 'homeworks', count(*)::integer from d;

with d as (
  delete from lesson_progress
  where lesson_id in (select id from _qa_lessons)
     or student_textbook_id in (select id from _qa_student_textbooks)
  returning 1
)
insert into _qa_cleanup_counts select 'lesson_progress', count(*)::integer from d;

with d as (delete from lessons where id in (select id from _qa_lessons) returning 1)
insert into _qa_cleanup_counts select 'lessons', count(*)::integer from d;

with d as (delete from attendance where student_id in (select id from _qa_students) returning 1)
insert into _qa_cleanup_counts select 'attendance', count(*)::integer from d;

with d as (delete from payment_items where payment_id in (select id from _qa_payments) returning 1)
insert into _qa_cleanup_counts select 'payment_items', count(*)::integer from d;

with d as (delete from payments where id in (select id from _qa_payments) returning 1)
insert into _qa_cleanup_counts select 'payments', count(*)::integer from d;

with d as (delete from schedule_slots where enrollment_id in (select id from _qa_enrollments) returning 1)
insert into _qa_cleanup_counts select 'schedule_slots', count(*)::integer from d;

with d as (delete from enrollments where id in (select id from _qa_enrollments) returning 1)
insert into _qa_cleanup_counts select 'enrollments', count(*)::integer from d;

with d as (delete from parents where student_id in (select id from _qa_students) returning 1)
insert into _qa_cleanup_counts select 'parents', count(*)::integer from d;

with d as (delete from student_textbooks where id in (select id from _qa_student_textbooks) returning 1)
insert into _qa_cleanup_counts select 'student_textbooks', count(*)::integer from d;

with d as (delete from students where id in (select id from _qa_students) returning 1)
insert into _qa_cleanup_counts select 'students', count(*)::integer from d;

with d as (delete from textbooks where id in (select id from _qa_textbooks_orphan) returning 1)
insert into _qa_cleanup_counts select 'textbooks_orphan', count(*)::integer from d;

-- Delete audit rows after lessons/payments deletes, because the delete triggers
-- create fresh audit rows inside this same transaction.
with d as (
  delete from audits
  where (table_name = 'lessons' and row_id in (select id from _qa_lessons))
     or (table_name = 'payments' and row_id in (select id from _qa_payments))
  returning 1
)
insert into _qa_cleanup_counts select 'audits_lesson_payment', count(*)::integer from d;

do $$
declare
  rec record;
begin
  for rec in
    select table_name, deleted from _qa_cleanup_counts order by table_name
  loop
    raise notice 'QA cleanup deleted % rows from %', rec.deleted, rec.table_name;
  end loop;
end $$;

commit;
