-- Preview rows that qa_fixtures_cleanup.sql will remove.
-- Read-only. Safe to run in the Supabase SQL editor before the destructive
-- cleanup. Counts are based on stable QA fixture identifiers.

with expected_students(goalimi_student_id, name) as (
  values
    (9001, '김민수'),
    (9002, '이서연'),
    (9003, '박지호'),
    (7707, '신성화')
),
qa_students as (
  select s.id, s.goalimi_student_id
  from students s
  join expected_students e
    on e.goalimi_student_id = s.goalimi_student_id
   and e.name = s.name
),
qa_student_textbooks as (
  select id from student_textbooks where student_id in (select id from qa_students)
),
qa_enrollments as (
  select id from enrollments where student_id in (select id from qa_students)
),
qa_lessons as (
  select id from lessons where student_id in (select id from qa_students)
),
qa_payments as (
  select id from payments where student_id in (select id from qa_students)
),
qa_reports as (
  select id from reports where student_id in (select id from qa_students)
),
qa_outbox as (
  select id
  from notification_outbox
  where student_id in (select id from qa_students)
     or report_id in (select id from qa_reports)
),
qa_parse_logs as (
  select id
  from parse_logs
  where (
      result ? 'student_id'
      and (result->>'student_id') ~ '^[0-9]+$'
      and (result->>'student_id')::bigint in (select id from qa_students)
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
    )
),
qa_textbooks_orphan_after_cleanup as (
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
      and stb.student_id not in (select id from qa_students)
  )
),
qa_audits as (
  select id
  from audits
  where (table_name = 'lessons' and row_id in (select id from qa_lessons))
     or (table_name = 'payments' and row_id in (select id from qa_payments))
)
select 'students' as table_name, count(*) from qa_students
union all select 'parents', count(*) from parents where student_id in (select id from qa_students)
union all select 'enrollments', count(*) from qa_enrollments
union all select 'schedule_slots', count(*) from schedule_slots where enrollment_id in (select id from qa_enrollments)
union all select 'student_textbooks', count(*) from qa_student_textbooks
union all select 'textbooks_orphan_after_cleanup', count(*) from qa_textbooks_orphan_after_cleanup
union all select 'lessons', count(*) from qa_lessons
union all select 'lesson_progress', count(*) from lesson_progress where lesson_id in (select id from qa_lessons) or student_textbook_id in (select id from qa_student_textbooks)
union all select 'homeworks', count(*) from homeworks where student_id in (select id from qa_students)
union all select 'comments', count(*) from comments where student_id in (select id from qa_students)
union all select 'attendance', count(*) from attendance where student_id in (select id from qa_students)
union all select 'payments', count(*) from qa_payments
union all select 'payment_items', count(*) from payment_items where payment_id in (select id from qa_payments)
union all select 'reports', count(*) from qa_reports
union all select 'notification_outbox', count(*) from qa_outbox
union all select 'parse_logs', count(*) from qa_parse_logs
union all select 'audits_lesson_payment_existing', count(*) from qa_audits
union all select 'audits_created_by_cleanup_triggers', (select count(*) from qa_lessons) + (select count(*) from qa_payments)
order by table_name;
