-- GoLesson views (docs/04_DATABASE.md section 4)
-- security_invoker=on so the views run under the caller's RLS (without it a
-- view owned by postgres would bypass RLS on the underlying tables).

-- Monthly payment aggregation (REQ-802)
create view v_monthly_payments with (security_invoker = on) as
select date_trunc('month', p.paid_on)::date as month,
       p.method, i.subject,
       sum(i.amount) as total, count(distinct p.id) as cnt
from payments p join payment_items i on i.payment_id = p.id
group by 1, 2, 3;

-- Today's lessons (REQ-202): per-slot status matching -- joining on
-- schedule_slot_id keeps per-slot status correct even with two lessons of the
-- same subject on the same day (makeup, BR-201).
-- Makeup lessons (schedule_slot_id null) are fetched separately by the front
-- from today's lessons and merged into the timeline.
create view v_today_lessons with (security_invoker = on) as
select ss.id as schedule_slot_id, e.student_id, e.subject,
       ss.start_time, ss.duration_min,
       l.id as lesson_id, coalesce(l.status, 'waiting') as status
from schedule_slots ss
join enrollments e on e.id = ss.enrollment_id and e.active
join students st on st.id = e.student_id and st.active
left join lessons l on l.schedule_slot_id = ss.id
                    and l.lesson_date = current_date
where ss.weekday = extract(isodow from current_date)::int - 1;

-- Client read access (RLS of the underlying tables applies via security_invoker)
grant select on v_monthly_payments, v_today_lessons to authenticated;
