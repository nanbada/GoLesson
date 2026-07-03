-- GoLesson schema (docs/04_DATABASE.md section 2 -- DDL)
-- Principle: progress/homework are append-only logs. No overwrite of current
-- values, no hard delete, deactivate instead (BR-1000s).

-- Teachers (linked to Supabase Auth)
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null,
  role       text not null default 'teacher' check (role in ('owner','teacher')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- Students (master = GoAlimi, upserted by Bridge. Never created/edited in GoLesson)
create table students (
  id                 bigint generated always as identity primary key,
  goalimi_student_id integer unique not null,
  name               text not null,
  grade              text,
  school             text,
  active             boolean not null default true,
  synced_at          timestamptz
);

-- Parents (master = GoAlimi)
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

-- Textbooks
create table textbooks (
  id          bigint generated always as identity primary key,
  subject     text not null check (subject in ('영어','수학')),
  title       text not null,
  publisher   text,
  unit_label  text not null default '페이지',  -- one unit label per textbook: 페이지|단원|Day|챕터 ...
  total_units integer,                          -- null = total unknown (no auto-complete detection)
  aliases     text[] not null default '{}',     -- parser aliases ('브릭스','bricks')
  active      boolean not null default true
);

-- Student-textbook assignment (multiple per subject allowed: main book + workbook)
create table student_textbooks (
  id               bigint generated always as identity primary key,
  student_id       bigint not null references students(id),
  textbook_id      bigint not null references textbooks(id) on delete restrict,
  status           text not null default 'active' check (status in ('active','completed','paused')),
  started_on       date not null default current_date,
  completed_on     date,
  last_position    integer,      -- cache: latest to_value (display + auto-fill of "from")
  last_progress_at timestamptz
);
create index ix_stb_student on student_textbooks(student_id) where status = 'active';

-- Enrollments (subjects a student takes)
create table enrollments (
  id         bigint generated always as identity primary key,
  student_id bigint not null references students(id),
  subject    text not null check (subject in ('영어','수학')),
  active     boolean not null default true,
  unique (student_id, subject)
);

-- Weekly schedule (basis of the Today screen)
create table schedule_slots (
  id            bigint generated always as identity primary key,
  enrollment_id bigint not null references enrollments(id) on delete cascade,
  weekday       smallint not null check (weekday between 0 and 6),  -- 0=Mon (GoAlimi convention)
  start_time    time not null,
  duration_min  integer not null default 40
);

-- Lessons (student x subject x one session)
create table lessons (
  id         bigint generated always as identity primary key,
  student_id bigint not null references students(id),
  teacher_id uuid references profiles(id),
  subject    text not null check (subject in ('영어','수학')),
  schedule_slot_id bigint references schedule_slots(id) on delete set null,
                   -- Lessons started from the schedule link to their slot; makeup
                   -- (ad-hoc) lessons are null. Used to distinguish two lessons of
                   -- the same subject on the same day (BR-201) and to match status
                   -- on the Today screen.
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

-- Progress log (duplicates/review allowed -- no unique constraint)
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

-- Homework (in_class by default / take_home as exception)
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

-- Comments (report material)
create table comments (
  id         bigint generated always as identity primary key,
  student_id bigint not null references students(id),
  lesson_id  bigint references lessons(id) on delete set null,
  subject    text check (subject in ('영어','수학')),  -- null = common
  author_id  uuid references profiles(id),
  body       text not null,
  created_at timestamptz not null default now()
);
create index ix_comments_student on comments(student_id, created_at desc);

-- Attendance (copy of GoAlimi attendance_logs, incremental upsert by Bridge)
create table attendance (
  id             bigint generated always as identity primary key,
  goalimi_log_id integer unique not null,
  student_id     bigint not null references students(id),
  event_type     text not null check (event_type in ('IN','OUT')),
  event_at       timestamptz not null
);
create index ix_att_student on attendance(student_id, event_at desc);

-- Payments
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
  subject    text not null,          -- '영어'|'수학'|'교재비' etc. (free text)
  amount     integer not null        -- KRW. Refund = negative
);
create index ix_payments_paid_on on payments(paid_on);

-- Reports
create table reports (
  id           bigint generated always as identity primary key,
  student_id   bigint not null references students(id),
  period_start date not null,
  period_end   date not null,
  stats        jsonb not null default '{}',  -- aggregate snapshot (attendance/progress/homework) 07_AI_SPEC section 4
  body         text,                          -- final message body (immutable after sent)
  status       text not null default 'draft'
               check (status in ('draft','ready','sent')),
               -- Send-failure state is owned by notification_outbox, not reports.
               -- UI joins outbox for failure badges (03_UI section 6); resend history
               -- also lives in outbox (dedupe_key v{n}).
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  sent_at      timestamptz   -- first successful send
);

-- Notification outbox (polled by Bridge)
create table notification_outbox (
  id         bigint generated always as identity primary key,
  report_id  bigint references reports(id),
  student_id bigint not null references students(id),
  kakao_name text not null,           -- snapshot for UI display only. Actual recipient is
                                      -- re-resolved by GoAlimi at send time via student_id
                                      -- (master freshness -- docs/08 section 3.2)
  goalimi_custom_id integer,          -- GoAlimi custom_messages.id (saved from POST response
                                      -- for crash recovery, docs/05 section 3)
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

-- Parse logs
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

-- App settings (academy name, report phrases -- no hardcoding; lesson learned
-- from GoAlimi's academy name hardcoded in 4 places)
create table app_settings (
  key   text primary key,   -- 'academy_name' | 'report_greeting' | 'report_closing' | 'goalimi_admin_url'
                            -- | 'bridge_last_poll_at' (updated by Bridge every poll --
                            --   connectivity warning source, 03_UI section 7)
  value text not null
);

-- Audit trail (triggers on lessons/payments)
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
