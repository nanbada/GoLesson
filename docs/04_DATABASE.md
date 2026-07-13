# 04. DATABASE — Supabase Postgres 설계

원칙: 진도·과제는 **로그(기록) 방식** — 현재값만 덮어쓰지 않는다. 중복(복습) 허용. 삭제 대신 비활성화.

## 1. ERD (개념)

```
profiles(강사)                    textbooks
students ──< parents              │
   │  ├──< enrollments ──< schedule_slots
   │  ├──< student_textbooks >── textbooks
   │  ├──< lessons ──< lesson_progress >── student_textbooks
   │  │        └────< homeworks (assigned/checked)
   │  ├──< comments
   │  ├──< attendance            (GoAlimi 동기화)
   │  ├──< payments ──< payment_items
   │  └──< reports ──< notification_outbox
parse_logs · audits              (독립)
```

## 2. DDL

```sql
-- 강사 (Supabase Auth 연동)
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null,
  role       text not null default 'teacher' check (role in ('owner','teacher')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- 학생 (마스터=GoAlimi, Bridge가 upsert. GoLesson에서 등록/수정 금지)
create table students (
  id                 bigint generated always as identity primary key,
  goalimi_student_id integer unique not null,
  name               text not null,
  grade              text,
  school             text,
  active             boolean not null default true,
  synced_at          timestamptz
);

-- 학부모 (마스터=GoAlimi)
create table parents (
  id                bigint generated always as identity primary key,
  goalimi_parent_id integer unique not null,
  student_id        bigint not null references students(id) on delete cascade,
  kakao_name        text not null,
  phone             text,
  relation          text,
  is_primary        boolean not null default false,
  notify_enabled    boolean not null default true,
  synced_at         timestamptz
);

-- 교재
create table textbooks (
  id          bigint generated always as identity primary key,
  subject     text not null check (subject in ('영어','수학')),
  title       text not null,
  publisher   text,
  unit_label  text not null default '페이지',  -- '페이지'|'단원'|'Day'|'챕터' 등 교재당 1개
  total_units integer,                          -- null=총량 미지정(완료 자동감지 없음)
  aliases     text[] not null default '{}',     -- 파서 별칭 ('브릭스','bricks')
  active      boolean not null default true
);

-- 학생-교재 배정 (과목별 복수 허용: 주교재+워크북)
create table student_textbooks (
  id               bigint generated always as identity primary key,
  student_id       bigint not null references students(id),
  textbook_id      bigint not null references textbooks(id) on delete restrict,
  status           text not null default 'active' check (status in ('active','completed','paused')),
  started_on       date not null default current_date,
  completed_on     date,
  last_position    integer,      -- 캐시: 최근 to_value (표시·from 자동입력용)
  last_progress_at timestamptz
);
create index ix_stb_student on student_textbooks(student_id) where status = 'active';

-- 수강 과목
create table enrollments (
  id         bigint generated always as identity primary key,
  student_id bigint not null references students(id),
  subject    text not null check (subject in ('영어','수학')),
  active     boolean not null default true,
  unique (student_id, subject)
);

-- 학생별 주간 슬롯 (오늘 화면의 근간). 같은 weekday+start_time 슬롯은
-- 학년·과목·레벨과 무관하게 하나의 운영 블록으로 파생 그룹화한다.
create table schedule_slots (
  id            bigint generated always as identity primary key,
  enrollment_id bigint not null references enrollments(id) on delete cascade,
  weekday       smallint not null check (weekday between 0 and 6),  -- 0=월 (GoAlimi 관례)
  start_time    time not null,
  duration_min  integer not null default 40
);

-- 운영 블록 안의 학생별 코칭 기록 (학생×과목×1회)
create table lessons (
  id         bigint generated always as identity primary key,
  student_id bigint not null references students(id),
  teacher_id uuid references profiles(id),
  subject    text not null check (subject in ('영어','수학')),
  schedule_slot_id bigint references schedule_slots(id) on delete set null,
                   -- 스케줄에서 시작한 수업은 슬롯 연결, 보강(임시 수업)은 null.
                   -- 같은 날 같은 과목 2회(BR-202) 구분과 오늘 화면 상태 매칭에 사용
  lesson_date date not null default current_date,
  started_at timestamptz,
  ended_at   timestamptz,
  status     text not null default 'in_progress'
             check (status in ('in_progress','done','canceled')),
  cancel_reason text,
  note       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ix_lessons_date on lessons(lesson_date);
create index ix_lessons_student on lessons(student_id, lesson_date desc);

-- 진도 로그 (중복 허용 — 유니크 제약 없음)
create table lesson_progress (
  id                  bigint generated always as identity primary key,
  lesson_id           bigint not null references lessons(id) on delete cascade,
  student_textbook_id bigint not null references student_textbooks(id),
  from_value          integer not null check (from_value >= 0),
  to_value            integer not null check (to_value >= 0),
  memo                text,
  created_at          timestamptz not null default now()
);
create index ix_progress_stb on lesson_progress(student_textbook_id, created_at desc);

-- 과제 (학원내 in_class 기본 / 집 take_home 예외)
create table homeworks (
  id                 bigint generated always as identity primary key,
  student_id         bigint not null references students(id),
  assigned_lesson_id bigint references lessons(id) on delete set null,
  subject            text not null check (subject in ('영어','수학')),
  description        text not null,
  kind               text not null default 'in_class' check (kind in ('in_class','take_home')),
  status             text not null default 'assigned'
                     check (status in ('assigned','done','partial','not_done')),
  teacher_comment    text,
  checked_at         timestamptz,
  checked_lesson_id  bigint references lessons(id) on delete set null,
  created_at         timestamptz not null default now()
);
create index ix_hw_unchecked on homeworks(student_id) where status = 'assigned';

-- 코멘트 (리포트 재료)
create table comments (
  id         bigint generated always as identity primary key,
  student_id bigint not null references students(id),
  lesson_id  bigint references lessons(id) on delete set null,
  subject    text check (subject in ('영어','수학')),  -- null=공통
  author_id  uuid references profiles(id),
  body       text not null,
  created_at timestamptz not null default now()
);
create index ix_comments_student on comments(student_id, created_at desc);

-- 출결 (GoAlimi attendance_logs 복사본, Bridge 증분 upsert)
create table attendance (
  id             bigint generated always as identity primary key,
  goalimi_log_id integer unique not null,
  student_id     bigint not null references students(id),
  event_type     text not null check (event_type in ('IN','OUT')),
  event_at       timestamptz not null
);
create index ix_att_student on attendance(student_id, event_at desc);

-- 결제
create table payments (
  id         bigint generated always as identity primary key,
  student_id bigint not null references students(id),
  paid_on    date not null default current_date,
  method     text not null check (method in ('카드','현금','계좌이체','기타')),
  memo       text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table payment_items (
  id         bigint generated always as identity primary key,
  payment_id bigint not null references payments(id) on delete cascade,
  subject    text not null,          -- '영어'|'수학'|'교재비' 등 자유
  amount     integer not null        -- 원 단위. 환불=음수
);
create index ix_payments_paid_on on payments(paid_on);

-- 리포트
create table reports (
  id           bigint generated always as identity primary key,
  student_id   bigint not null references students(id),
  period_start date not null,
  period_end   date not null,
  stats        jsonb not null default '{}',  -- 집계 스냅샷(출석·진도·과제) 07_AI_SPEC §4
  body         text,                          -- 최종 발송문 (sent 후 불변)
  status       text not null default 'draft'
               check (status in ('draft','ready','sent')),
               -- 발송 실패 상태는 reports가 아니라 notification_outbox가 소유한다.
               -- 화면은 outbox를 조인해 실패 배지를 표시(03_UI §6). 재발송 이력도 outbox(dedupe_key v{n})가 담당
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  sent_at      timestamptz   -- 최초 발송 성공 시각
);

-- 발송 아웃박스 (Bridge 폴링 대상)
create table notification_outbox (
  id         bigint generated always as identity primary key,
  report_id  bigint references reports(id),
  student_id bigint not null references students(id),
  kakao_name text not null,           -- UI 표시용 스냅샷. 실제 수신자는 GoAlimi가 발송 시점에
                                      -- student_id로 재조회 (마스터 최신 — 08 §3.2)
  goalimi_custom_id integer,          -- GoAlimi custom_messages.id (POST 응답 저장 — crash 회수용, 05 §3)
  message    text not null,
  dedupe_key text unique not null,    -- 'report:{id}:v{n}'
  status     text not null default 'pending'
             check (status in ('pending','processing','sent','failed')),
  error      text,
  attempts   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at    timestamptz
);
create index ix_outbox_pending on notification_outbox(created_at) where status = 'pending';

-- 파싱 로그
create table parse_logs (
  id         bigint generated always as identity primary key,
  raw_text   text not null,
  method     text check (method in ('regex','ai','manual')),
  result     jsonb,
  status     text not null default 'parsed' check (status in ('parsed','confirmed','failed')),
  error      text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

-- 앱 설정 (학원명·리포트 문구 — 하드코딩 금지, GoAlimi 학원명 4곳 하드코딩 교훈)
create table app_settings (
  key   text primary key,   -- 'academy_name' | 'report_greeting' | 'report_closing' | 'goalimi_admin_url'
                            -- | 'bridge_last_poll_at' (Bridge가 매 주기 갱신 — 연결 경고 근거, 03_UI §7)
  value text not null
);

-- 수정이력 (lessons·payments 트리거)
create table audits (
  id         bigint generated always as identity primary key,
  table_name text not null,
  row_id     bigint not null,
  action     text not null check (action in ('update','delete')),
  changed_by uuid,
  changed_at timestamptz not null default now(),
  before     jsonb,
  after      jsonb
);
```

## 3. 트리거·함수

```sql
-- 진도 저장 시 student_textbooks 캐시 갱신
-- from/to 역순 입력은 저장 전 작은 값→큰 값으로 정규화한다(BR-104).
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
create trigger t_progress_normalize_range before insert or update on lesson_progress
  for each row execute function trg_normalize_progress_range();

create or replace function trg_update_last_position() returns trigger as $$
begin
  update student_textbooks
     set last_position = new.to_value, last_progress_at = new.created_at
   where id = new.student_textbook_id;
  return new;
end $$ language plpgsql;
create trigger t_progress_cache after insert on lesson_progress
  for each row execute function trg_update_last_position();

-- lessons·payments 수정이력 (audits)
-- update/delete 시 before/after를 audits에 기록하는 공용 트리거 함수 1개 작성 후
-- lessons, payments 두 테이블에 부착. (payment_items는 부모 payments 갱신으로 간주)
-- 트리거 함수는 security definer로 작성한다 — audits는 클라이언트 쓰기 GRANT가 없어
-- authenticated 트랜잭션에서 발화하면 invoker 권한으로는 insert가 거부된다.
```

`updated_at` 자동 갱신 트리거를 lessons, payments, reports, notification_outbox에 부착.

```sql
-- 발송본 불변 강제 (REQ-1004, BR-405) — 주석이 아니라 DB가 막는다.
-- 컬럼 열거가 아니라 전체 row jsonb 비교(updated_at 제외) — sent_at·created_by·
-- created_at 변조까지 차단하고 컬럼 추가에도 안전하다.
create or replace function trg_reports_immutable() returns trigger as $$
begin
  if old.status = 'sent'
     and (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    raise exception 'sent report is immutable (REQ-1004)';
  end if;
  return new;
end $$ language plpgsql;
create trigger t_reports_immutable before update on reports
  for each row execute function trg_reports_immutable();
-- ready→sent 전환(Bridge)은 old.status='ready'라 통과. sent 후에는 updated_at 외 전부 차단
```

```sql
-- Bridge의 outbox 인출 (PostgREST PATCH는 attempts 증가 같은 연산 불가 → RPC로 원자 처리)
create or replace function claim_outbox(p_limit int default 5)
returns setof notification_outbox as $$
  update notification_outbox o
     set status = 'processing', attempts = o.attempts + 1, updated_at = now()
   where o.id in (
     select id from notification_outbox
      where status = 'pending'
      order by created_at
      for update skip locked
      limit p_limit)
  returning o.*;
$$ language sql security definer set search_path = public;

-- service_role 전용. PUBLIC revoke만 하면 service_role의 기본 실행권도 사라지므로
-- 명시적으로 재부여한다 (PostgREST는 요청마다 해당 role로 실행).
revoke execute on function claim_outbox(int) from public, anon, authenticated;
grant execute on function claim_outbox(int) to service_role;
```

```sql
-- 프론트 수업 저장 RPC: lesson/progress/homework/comment/parse_log 확정을
-- 한 DB 트랜잭션으로 처리한다. SECURITY INVOKER라 RLS/GRANT는 그대로 적용된다.
create or replace function save_lesson_log(p_payload jsonb) returns bigint ...
revoke execute on function save_lesson_log(jsonb) from public, anon;
grant execute on function save_lesson_log(jsonb) to authenticated;

-- 프론트 수강료 저장 RPC: payments update/insert + payment_items 교체를
-- 한 DB 트랜잭션으로 처리한다. 중간 실패 시 부모/항목 모두 롤백된다.
create or replace function save_payment_with_items(p_payload jsonb) returns bigint ...
revoke execute on function save_payment_with_items(jsonb) from public, anon;
grant execute on function save_payment_with_items(jsonb) to authenticated;
```

## 4. 뷰

뷰는 `security_invoker = on`으로 만든다 — 기본(owner 실행)이면 postgres 소유 뷰가
기저 테이블 RLS를 우회한다. 뷰 자체 접근은 별도 GRANT가 필요하다.

```sql
-- 월별 수납 집계 (REQ-802)
create view v_monthly_payments with (security_invoker = on) as
select date_trunc('month', p.paid_on)::date as month,
       p.method, i.subject,
       sum(i.amount) as total, count(distinct p.id) as cnt
from payments p join payment_items i on i.payment_id = p.id
group by 1, 2, 3;

-- 오늘 수업 (REQ-202): 슬롯 단위 상태 매칭 — schedule_slot_id로 join해야
-- 같은 날 같은 과목 2회(보강, BR-202)에도 슬롯별 상태가 정확하다.
-- 보강 수업(schedule_slot_id null)은 프론트가 당일 lessons에서 별도 조회해 타임라인에 병합
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

-- 클라이언트 조회 허용 (security_invoker라 기저 테이블 RLS가 그대로 적용됨)
grant select on v_monthly_payments, v_today_lessons to authenticated;
```

## 5. RLS + GRANT (Row Level Security)

단일 학원(싱글 테넌트). **정책은 테이블군별로 분리한다** — 공통 `for all` 정책 하나로 처리하지 않는다 (읽기 전용 테이블에 쓰기 정책이 생기는 모순 방지).

주의: 신규 Supabase 프로젝트(2026-05-30 이후)는 Data API 노출에 **명시적 GRANT가 필요**하다. RLS 정책만으로는 PostgREST 접근이 열리지 않으므로 마이그레이션에서 GRANT와 RLS를 항상 함께 다룬다.

아래 SQL은 마이그레이션에 그대로 넣을 수 있는 실행 가능 기준본이다 (placeholder 아님).

```sql
-- 0) 전 테이블 RLS 활성화 + identity 시퀀스 사용 권한
do $$ declare t text;
begin
  foreach t in array array[
    'profiles','students','parents','textbooks','student_textbooks','enrollments',
    'schedule_slots','lessons','lesson_progress','homeworks','comments','attendance',
    'payments','payment_items','reports','notification_outbox','parse_logs',
    'app_settings','audits']
  loop execute format('alter table %I enable row level security', t); end loop;
end $$;
grant usage on all sequences in schema public to authenticated;

-- 1) 공통 헬퍼 (security definer → profiles RLS 재귀 없음)
create or replace function is_active_teacher() returns boolean as $$
  select exists (select 1 from profiles pr where pr.id = auth.uid() and pr.active);
$$ language sql stable security definer set search_path = public;

-- 2) [A군] 읽기 전용 사본: students, parents, attendance (쓰기 GRANT 자체를 주지 않음)
do $$ declare t text;
begin
  foreach t in array array['students','parents','attendance'] loop
    execute format('grant select on %I to authenticated', t);
    execute format('create policy p_%s_sel on %I for select to authenticated using (is_active_teacher())', t, t);
  end loop;
end $$;

-- 3) [B군] 강사 select/insert/update (delete 없음 — 비활성화·취소·이력 보존)
do $$ declare t text;
begin
  foreach t in array array['textbooks','student_textbooks','enrollments','lessons',
                           'lesson_progress','comments','reports','app_settings'] loop
    execute format('grant select, insert, update on %I to authenticated', t);
    execute format('create policy p_%s_sel on %I for select to authenticated using (is_active_teacher())', t, t);
    execute format('create policy p_%s_ins on %I for insert to authenticated with check (is_active_teacher())', t, t);
    execute format('create policy p_%s_upd on %I for update to authenticated using (is_active_teacher()) with check (is_active_teacher())', t, t);
  end loop;
end $$;

-- 3-1) reports 예외: 발송 완료(status='sent')는 Bridge/service_role 소유(05 §3, BR-500대).
--      클라이언트는 draft/ready 안에서만 생성·전환 가능 — sent 위조 불가.
drop policy p_reports_ins on reports;
drop policy p_reports_upd on reports;
create policy p_reports_ins on reports for insert to authenticated
  with check (is_active_teacher() and status in ('draft','ready'));
create policy p_reports_upd on reports for update to authenticated
  using (is_active_teacher() and status <> 'sent')
  with check (is_active_teacher() and status in ('draft','ready'));

-- 3-2) lesson_progress 예외: 진도는 append-only 로그(BR-101)다.
--      강사는 새 구간을 insert할 수 있지만 기존 구간 overwrite는 금지.
revoke update on lesson_progress from authenticated;
drop policy if exists p_lesson_progress_upd on lesson_progress;

-- 4) [C군] 강사 CRUD + delete
do $$ declare t text;
begin
  foreach t in array array['schedule_slots','homeworks','payments','payment_items'] loop
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('create policy p_%s_sel on %I for select to authenticated using (is_active_teacher())', t, t);
    execute format('create policy p_%s_ins on %I for insert to authenticated with check (is_active_teacher())', t, t);
    execute format('create policy p_%s_upd on %I for update to authenticated using (is_active_teacher()) with check (is_active_teacher())', t, t);
    execute format('create policy p_%s_del on %I for delete to authenticated using (is_active_teacher())', t, t);
  end loop;
end $$;

-- 4-1) homeworks 예외: 과제 체크/코멘트 update는 허용하지만 hard delete는 금지.
--      미완료 재부여는 새 homework 행으로 남긴다(BR-305).
revoke delete on homeworks from authenticated;
drop policy if exists p_homeworks_del on homeworks;

-- 5) [D군] 시스템 전용: 클라이언트는 조회만 (쓰기는 service_role/Edge Functions)
do $$ declare t text;
begin
  foreach t in array array['notification_outbox','parse_logs','audits'] loop
    execute format('grant select on %I to authenticated', t);
    execute format('create policy p_%s_sel on %I for select to authenticated using (is_active_teacher())', t, t);
  end loop;
end $$;

-- 5-1) parse_logs 예외 (05_API §2.1): 프론트가 저장 확정 시 본인 행의 status만 confirmed로 갱신
grant update (status) on parse_logs to authenticated;   -- 컬럼 단위 GRANT — 다른 컬럼 갱신 불가
create policy p_parse_logs_upd on parse_logs for update to authenticated
  using (is_active_teacher() and created_by = auth.uid())
  with check (is_active_teacher() and created_by = auth.uid());

-- 6) profiles: 활성 강사는 전체 조회, 본인 row는 비활성이어도 조회(안내용). 쓰기는 service_role만
grant select on profiles to authenticated;
create policy p_profiles_sel on profiles for select to authenticated
  using (is_active_teacher() or id = auth.uid());

-- 7) service_role 명시 GRANT — BYPASSRLS는 RLS만 우회하고 privilege는 우회하지 않는다.
--    기본 privilege가 없는 신규 프로젝트에서 Bridge/Edge Functions의 PostgREST 호출
--    (동기화 upsert, outbox/report 갱신)이 막히지 않도록 명시한다.
grant usage on schema public to authenticated, service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
```

- 모든 테이블 RLS enable. anon에게는 GRANT 없음 + 정책 없음 (전면 차단).
- Bridge·Edge Functions는 `service_role` 키 사용 — RLS는 우회하지만 GRANT는 우회하지 않으므로 위 7) 명시 GRANT가 필요. 키는 학원 PC와 Supabase secrets에만 존재.
- `claim_outbox` RPC는 service_role 전용 (execute 권한 revoke).
- 마이그레이션 검증 절차: anon으로 select 시도 → 거부, authenticated로 students insert 시도 → 거부 확인 (10_ACCEPTANCE T10).

## 6. 용량 검증 (Supabase 무료 500MB)

30명 × 주 2과목 × 연 100회 수업 ≈ lessons 6천 행/년, progress·homeworks 각 1~2만 행/년.
행당 1KB 잡아도 연 50MB 미만 → **수년간 무료 티어로 충분.** 사진 첨부(Phase 4)만 Storage 1GB 한도 주의.
