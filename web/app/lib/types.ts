export type Id = number;

export type Profile = {
  id: string;
  name: string;
  role: "owner" | "teacher";
  active: boolean;
  created_at: string;
};

export type Student = {
  id: Id;
  goalimi_student_id: number;
  name: string;
  grade: string | null;
  school: string | null;
  active: boolean;
  synced_at: string | null;
};

export type Parent = {
  id: Id;
  student_id: Id;
  kakao_name: string;
  phone: string | null;
  relation: string | null;
  is_primary: boolean;
  notify_enabled: boolean;
};

export type Textbook = {
  id: Id;
  subject: Subject;
  title: string;
  publisher: string | null;
  unit_label: string;
  total_units: number | null;
  aliases: string[];
  active: boolean;
};

export type StudentTextbook = {
  id: Id;
  student_id: Id;
  textbook_id: Id;
  status: "active" | "completed" | "paused";
  started_on: string;
  completed_on: string | null;
  last_position: number | null;
  last_progress_at: string | null;
};

export type Subject = "영어" | "수학";

export type Enrollment = {
  id: Id;
  student_id: Id;
  subject: Subject;
  active: boolean;
};

export type ScheduleSlot = {
  id: Id;
  enrollment_id: Id;
  weekday: number;
  start_time: string;
  duration_min: number;
};

export type Lesson = {
  id: Id;
  student_id: Id;
  teacher_id: string | null;
  subject: Subject;
  schedule_slot_id: Id | null;
  lesson_date: string;
  started_at: string | null;
  ended_at: string | null;
  status: "in_progress" | "done" | "canceled";
  cancel_reason: string | null;
  note: string | null;
  created_at: string;
  updated_at: string;
};

export type LessonProgress = {
  id: Id;
  lesson_id: Id;
  student_textbook_id: Id;
  from_value: number;
  to_value: number;
  memo: string | null;
  created_at: string;
};

export type Homework = {
  id: Id;
  student_id: Id;
  assigned_lesson_id: Id | null;
  subject: Subject;
  description: string;
  kind: "in_class" | "take_home";
  status: "assigned" | "done" | "partial" | "not_done";
  teacher_comment: string | null;
  checked_at: string | null;
  checked_lesson_id: Id | null;
  created_at: string;
};

export type LessonComment = {
  id: Id;
  student_id: Id;
  lesson_id: Id | null;
  subject: Subject | null;
  body: string;
  created_at: string;
};

export type Attendance = {
  id: Id;
  goalimi_log_id: number;
  student_id: Id;
  event_type: "IN" | "OUT";
  event_at: string;
};

export type PaymentItem = {
  id: Id;
  payment_id: Id;
  subject: string;
  amount: number;
};

export type Payment = {
  id: Id;
  student_id: Id;
  paid_on: string;
  method: "카드" | "현금" | "계좌이체" | "기타";
  memo: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  payment_items?: PaymentItem[];
};

export type Report = {
  id: Id;
  student_id: Id;
  period_start: string;
  period_end: string;
  stats: Record<string, unknown>;
  body: string | null;
  status: "draft" | "ready" | "sent";
  created_at: string;
  updated_at: string;
  sent_at: string | null;
};

export type NotificationOutbox = {
  id: Id;
  report_id: Id | null;
  student_id: Id;
  kakao_name: string;
  goalimi_custom_id: number | null;
  message: string;
  dedupe_key: string;
  status: "pending" | "processing" | "sent" | "failed";
  error: string | null;
  attempts: number;
  created_at: string;
  updated_at: string;
  sent_at: string | null;
};

export type AppSetting = {
  key: string;
  value: string;
};

export type AppData = {
  profiles: Profile[];
  students: Student[];
  parents: Parent[];
  textbooks: Textbook[];
  studentTextbooks: StudentTextbook[];
  enrollments: Enrollment[];
  scheduleSlots: ScheduleSlot[];
  lessons: Lesson[];
  progress: LessonProgress[];
  homeworks: Homework[];
  comments: LessonComment[];
  attendance: Attendance[];
  payments: Payment[];
  reports: Report[];
  outbox: NotificationOutbox[];
  settings: Record<string, string>;
};

export type ParseResult = {
  line: number;
  raw: string;
  method: "regex" | "ai" | null;
  ok: boolean;
  parse_log_id?: number;
  warning?: string;
  confidence?: "high" | "low";
  error?: string;
  candidates?: { id: number; name: string }[];
  parsed?: {
    student_id: Id;
    student_name: string;
    subject: Subject | null;
    student_textbook_id: Id | null;
    textbook_title: string | null;
    from_value: number | null;
    to_value: number | null;
    homework: string | null;
    comment: string | null;
  };
};
