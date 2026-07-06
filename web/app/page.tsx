"use client";

import {
  AlertTriangle,
  BookOpen,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock3,
  CreditCard,
  ExternalLink,
  Home,
  Loader2,
  LogOut,
  MessageSquareText,
  MoreHorizontal,
  Plus,
  RefreshCw,
  Save,
  Search,
  Send,
  Settings,
  Users,
  Wand2,
  X
} from "lucide-react";
import type { Session } from "@supabase/supabase-js";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { FormEvent, ReactNode } from "react";
import { addDays, displayDate, formatKrw, formatTime, monthKey, nowIso, relativeHours, seoulWeekday, todaySeoul } from "./lib/date";
import { getSupabase, hasSupabaseEnv } from "./lib/supabase";
import type {
  AppData,
  Homework,
  Id,
  Lesson,
  NotificationOutbox,
  ParseResult,
  Payment,
  PaymentItem,
  Report,
  Student,
  StudentTextbook,
  Subject,
  Textbook
} from "./lib/types";

type View = "today" | "students" | "quick" | "reports" | "more";
type MoreView = "menu" | "payments" | "textbooks" | "outbox" | "shortcut" | "settings";
type LessonTarget = {
  lessonId?: Id;
  studentId: Id;
  subject: Subject;
  scheduleSlotId: Id | null;
  startTime?: string | null;
};

type AppActions = {
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
  openLesson: (target: LessonTarget) => void;
  closeLesson: () => void;
  startLesson: (target: LessonTarget) => Promise<void>;
  saveLesson: (target: LessonTarget, draft: LessonDraft, onSaved?: () => void) => Promise<void>;
  cancelLesson: (target: LessonTarget, reason: string) => Promise<void>;
  addMakeupLesson: (studentId: Id, subject: Subject) => Promise<void>;
  saveSchedule: (form: ScheduleForm) => Promise<void>;
  deleteSchedule: (slotId: Id) => Promise<void>;
  assignTextbook: (studentId: Id, textbookId: Id) => Promise<void>;
  completeAssignment: (assignmentId: Id) => Promise<void>;
  parseBatch: (text: string) => Promise<ParseResult[]>;
  saveParsed: (rows: ParseResult[]) => Promise<void>;
  generateReports: (studentIds: Id[], start: string, end: string) => Promise<void>;
  saveReportBody: (reportId: Id, body: string) => Promise<void>;
  approveReport: (reportId: Id, body?: string) => Promise<void>;
  enqueueReport: (report: Report, resend?: boolean, body?: string) => Promise<void>;
  savePayment: (form: PaymentForm) => Promise<void>;
  deletePayment: (paymentId: Id) => Promise<void>;
  saveTextbook: (form: TextbookForm) => Promise<void>;
  saveSettings: (settings: Record<string, string>) => Promise<void>;
};

const EMPTY_DATA: AppData = {
  profiles: [],
  students: [],
  parents: [],
  textbooks: [],
  studentTextbooks: [],
  enrollments: [],
  scheduleSlots: [],
  lessons: [],
  progress: [],
  homeworks: [],
  comments: [],
  attendance: [],
  payments: [],
  reports: [],
  outbox: [],
  settings: {}
};

const SUBJECTS: Subject[] = ["영어", "수학"];
const WEEKDAYS = ["월", "화", "수", "목", "금", "토", "일"];
const HOMEWORK_STATUS = [
  { value: "done", label: "완료" },
  { value: "partial", label: "부분" },
  { value: "not_done", label: "미완료" }
] as const;
const PAYMENT_METHODS = ["카드", "현금", "계좌이체", "기타"] as const;

type LessonDraft = {
  textbookId: string;
  toValue: string;
  memo: string;
  comment: string;
  homeworkText: string;
  homeworkKind: "in_class" | "take_home";
  homeworkStatus: "done" | "partial" | "not_done";
  homeworkComment: string;
  carryover: Record<string, { status: "done" | "partial" | "not_done"; comment: string }>;
};

type PaymentForm = {
  id: Id | null;
  studentId: string;
  paidOn: string;
  method: "카드" | "현금" | "계좌이체" | "기타";
  memo: string;
  items: { subject: string; amount: string }[];
};

type TextbookForm = {
  id: Id | null;
  subject: Subject;
  title: string;
  publisher: string;
  unitLabel: string;
  totalUnits: string;
  aliases: string;
  active: boolean;
};

type ScheduleForm = {
  studentId: string;
  subject: Subject;
  weekday: string;
  startTime: string;
  durationMin: string;
};

function initialLessonDraft(data: AppData, target: LessonTarget): LessonDraft {
  const assignment = activeAssignments(data, target.studentId, target.subject)[0];
  return {
    textbookId: assignment ? String(assignment.id) : "",
    toValue: "",
    memo: "",
    comment: "",
    homeworkText: "",
    homeworkKind: "in_class",
    homeworkStatus: "done",
    homeworkComment: "",
    carryover: {}
  };
}

function useStoredState<T>(key: string, initial: T): [T, (next: T | ((prev: T) => T)) => void] {
  const initialRef = useRef(initial);
  const [value, setValue] = useState<T>(() => {
    return readStoredState(key, initialRef.current);
  });

  useEffect(() => {
    initialRef.current = initial;
  }, [initial]);

  useEffect(() => {
    setValue(readStoredState(key, initialRef.current));
  }, [key]);

  const update = (next: T | ((prev: T) => T)) => {
    setValue((prev) => {
      const resolved = typeof next === "function" ? (next as (prev: T) => T)(prev) : next;
      if (typeof window !== "undefined") {
        window.localStorage.setItem(key, JSON.stringify(resolved));
      }
      return resolved;
    });
  };
  return [value, update];
}

export default function Page() {
  if (!hasSupabaseEnv()) return <MissingEnv />;
  return <GoLessonApp />;
}

function GoLessonApp() {
  const supabase = useMemo(() => getSupabase(), []);
  const [session, setSession] = useState<Session | null>(null);
  const [sessionReady, setSessionReady] = useState(false);
  const [data, setData] = useState<AppData>(EMPTY_DATA);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<string>("");
  const [view, setView] = useState<View>("today");
  const [moreView, setMoreView] = useState<MoreView>("menu");
  const [lessonTarget, setLessonTarget] = useState<LessonTarget | null>(null);
  const [loginError, setLoginError] = useState("");

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const [
        profiles,
        students,
        parents,
        textbooks,
        studentTextbooks,
        enrollments,
        scheduleSlots,
        lessons,
        progress,
        homeworks,
        comments,
        attendance,
        payments,
        reports,
        outbox,
        settings
      ] = await Promise.all([
        supabase.from("profiles").select("id,name,role,active,created_at").order("name"),
        supabase.from("students").select("id,goalimi_student_id,name,grade,school,active,synced_at").order("name"),
        supabase.from("parents").select("id,student_id,kakao_name,phone,relation,is_primary,notify_enabled"),
        supabase.from("textbooks").select("id,subject,title,publisher,unit_label,total_units,aliases,active").order("subject").order("title"),
        supabase.from("student_textbooks").select("id,student_id,textbook_id,status,started_on,completed_on,last_position,last_progress_at"),
        supabase.from("enrollments").select("id,student_id,subject,active"),
        supabase.from("schedule_slots").select("id,enrollment_id,weekday,start_time,duration_min").order("start_time"),
        supabase.from("lessons").select("id,student_id,teacher_id,subject,schedule_slot_id,lesson_date,started_at,ended_at,status,cancel_reason,note,created_at,updated_at").order("lesson_date", { ascending: false }).limit(500),
        supabase.from("lesson_progress").select("id,lesson_id,student_textbook_id,from_value,to_value,memo,created_at").order("created_at", { ascending: false }).limit(1000),
        supabase.from("homeworks").select("id,student_id,assigned_lesson_id,subject,description,kind,status,teacher_comment,checked_at,checked_lesson_id,created_at").order("created_at", { ascending: false }).limit(1000),
        supabase.from("comments").select("id,student_id,lesson_id,subject,body,created_at").order("created_at", { ascending: false }).limit(1000),
        supabase.from("attendance").select("id,goalimi_log_id,student_id,event_type,event_at").order("event_at", { ascending: false }).limit(1000),
        supabase.from("payments").select("id,student_id,paid_on,method,memo,created_by,created_at,updated_at,payment_items(id,payment_id,subject,amount)").order("paid_on", { ascending: false }).limit(500),
        supabase.from("reports").select("id,student_id,period_start,period_end,stats,body,status,created_at,updated_at,sent_at").order("created_at", { ascending: false }).limit(500),
        supabase.from("notification_outbox").select("id,report_id,student_id,kakao_name,goalimi_custom_id,message,dedupe_key,status,error,attempts,created_at,updated_at,sent_at").order("created_at", { ascending: false }).limit(500),
        supabase.from("app_settings").select("key,value")
      ]);
      const results = [profiles, students, parents, textbooks, studentTextbooks, enrollments, scheduleSlots, lessons, progress, homeworks, comments, attendance, payments, reports, outbox, settings];
      const firstError = results.find((r) => r.error)?.error;
      if (firstError) throw firstError;
      setData({
        profiles: (profiles.data ?? []) as AppData["profiles"],
        students: (students.data ?? []) as AppData["students"],
        parents: (parents.data ?? []) as AppData["parents"],
        textbooks: (textbooks.data ?? []) as AppData["textbooks"],
        studentTextbooks: (studentTextbooks.data ?? []) as AppData["studentTextbooks"],
        enrollments: (enrollments.data ?? []) as AppData["enrollments"],
        scheduleSlots: (scheduleSlots.data ?? []) as AppData["scheduleSlots"],
        lessons: (lessons.data ?? []) as AppData["lessons"],
        progress: (progress.data ?? []) as AppData["progress"],
        homeworks: (homeworks.data ?? []) as AppData["homeworks"],
        comments: (comments.data ?? []) as AppData["comments"],
        attendance: (attendance.data ?? []) as AppData["attendance"],
        payments: (payments.data ?? []) as AppData["payments"],
        reports: (reports.data ?? []) as AppData["reports"],
        outbox: (outbox.data ?? []) as AppData["outbox"],
        settings: Object.fromEntries(((settings.data ?? []) as { key: string; value: string }[]).map((s) => [s.key, s.value]))
      });
    } catch (error) {
      setToast(toMessage(error));
    } finally {
      setLoading(false);
    }
  }, [supabase]);

  useEffect(() => {
    if (process.env.NODE_ENV === "production" && "serviceWorker" in navigator) {
      navigator.serviceWorker.register("/service-worker.js").catch(() => undefined);
    }
  }, []);

  useEffect(() => {
    let alive = true;
    const timeout = new Promise<null>((resolve) => window.setTimeout(() => resolve(null), 3000));
    Promise.race([supabase.auth.getSession(), timeout])
      .then((result) => {
        if (!alive) return;
        if (result && "data" in result) {
          setSession(result.data.session);
        } else {
          setSession(null);
        }
        setSessionReady(true);
      })
      .catch(() => {
        if (!alive) return;
        setSession(null);
        setSessionReady(true);
      });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setSessionReady(true);
      if (!nextSession) setData(EMPTY_DATA);
    });
    return () => {
      alive = false;
      sub.subscription.unsubscribe();
    };
  }, [supabase]);

  useEffect(() => {
    if (session) void loadData();
  }, [session, loadData]);

  const profile = data.profiles.find((p) => p.id === session?.user.id) ?? null;

  async function login(email: string, password: string) {
    setLoginError("");
    setBusy(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) setLoginError(toLoginMessage(error.message));
  }

  async function signOut() {
    await supabase.auth.signOut();
    setView("today");
    setMoreView("menu");
  }

  async function run(action: () => Promise<void>, success?: string) {
    setBusy(true);
    setToast("");
    try {
      await action();
      if (success) setToast(success);
      await loadData();
    } catch (error) {
      setToast(toMessage(error));
    } finally {
      setBusy(false);
    }
  }

  const actions = {
    refresh: loadData,
    signOut,
    openLesson: (target: LessonTarget) => {
      setLessonTarget(target);
      setView("today");
    },
    closeLesson: () => setLessonTarget(null),
    startLesson: (target: LessonTarget) =>
      run(async () => {
        const lessonId = await startLesson(supabase, data, target);
        setLessonTarget({ ...target, lessonId });
      }, "수업 시작 기록"),
    saveLesson: (target: LessonTarget, draft: LessonDraft, onSaved?: () => void) =>
      run(async () => {
        await saveLesson(supabase, data, target, draft);
        onSaved?.();
        setLessonTarget(null);
      }, "수업 기록 저장"),
    cancelLesson: (target: LessonTarget, reason: string) =>
      run(async () => {
        await cancelLesson(supabase, target, reason);
        setLessonTarget(null);
      }, "수업 취소 기록"),
    addMakeupLesson: (studentId: Id, subject: Subject) =>
      run(async () => {
        const { data: row, error } = await supabase
          .from("lessons")
          .insert({ student_id: studentId, subject, lesson_date: todaySeoul(), started_at: nowIso(), status: "in_progress", teacher_id: session?.user.id ?? null })
          .select("id")
          .single();
        if (error || !row) throw error ?? new Error("보강 수업 생성 실패");
        setLessonTarget({ lessonId: row.id as number, studentId, subject, scheduleSlotId: null });
      }, "보강 수업 추가"),
    saveSchedule: (form: ScheduleForm) => run(() => saveSchedule(supabase, data, form), "스케줄 저장"),
    deleteSchedule: (slotId: Id) => run(() => deleteRow(supabase, "schedule_slots", slotId), "스케줄 삭제"),
    assignTextbook: (studentId: Id, textbookId: Id) => run(() => assignTextbook(supabase, studentId, textbookId), "교재 배정 저장"),
    completeAssignment: (assignmentId: Id) => run(() => completeAssignment(supabase, assignmentId), "교재 완료 처리"),
    parseBatch: async (text: string) => {
      const { data: response, error } = await supabase.functions.invoke("parse-batch", { body: { text } });
      if (error) throw error;
      return (response as { results: ParseResult[] }).results;
    },
    saveParsed: (rows: ParseResult[]) => run(() => saveParsedRows(supabase, data, rows), "빠른 입력 저장"),
    generateReports: (studentIds: Id[], start: string, end: string) => run(() => generateReports(supabase, studentIds, start, end), "리포트 초안 생성"),
    saveReportBody: (reportId: Id, body: string) => run(() => updateReport(supabase, reportId, { body }), "리포트 본문 저장"),
    approveReport: (reportId: Id, body?: string) =>
      run(async () => {
        if (body !== undefined) await updateReport(supabase, reportId, { body });
        await updateReport(supabase, reportId, { status: "ready" });
      }, "발송 승인 완료"),
    enqueueReport: (report: Report, resend = false, body?: string) =>
      run(async () => {
        if (body !== undefined && report.status !== "sent") await updateReport(supabase, report.id, { body });
        await enqueueReport(supabase, report, resend);
      }, "발송 대기열 등록"),
    savePayment: (form: PaymentForm) => run(() => savePayment(supabase, form), "수강료 저장"),
    deletePayment: (paymentId: Id) => run(() => deleteRow(supabase, "payments", paymentId), "수강료 삭제"),
    saveTextbook: (form: TextbookForm) => run(() => saveTextbook(supabase, form), "교재 저장"),
    saveSettings: (settings: Record<string, string>) => run(() => saveSettings(supabase, settings), "설정 저장")
  };

  if (!sessionReady) return <LoadingScreen label="세션 확인 중" />;
  if (!session) return <LoginScreen onLogin={login} busy={busy} error={loginError} />;
  if (loading && data.students.length === 0) return <LoadingScreen label="데이터 불러오는 중" />;
  if (profile && !profile.active) return <DisabledAccount onSignOut={signOut} />;

  const wideLayout = !lessonTarget && (
    view === "students" ||
    view === "reports" ||
    (view === "more" && ["payments", "textbooks", "settings"].includes(moreView))
  );

  return (
    <main className={wideLayout ? "app-shell wide-shell" : "app-shell"}>
      <header className="topbar">
        <div>
          <p className="eyebrow">{data.settings.academy_name || "GoLesson"}</p>
          <h1>{titleFor(view, moreView, lessonTarget)}</h1>
        </div>
        <button className="icon-button" onClick={() => void loadData()} title="새로고침" disabled={loading || busy}>
          <RefreshCw size={20} className={loading ? "spin" : ""} />
        </button>
      </header>

      {toast ? (
        <div className="toast" role="status">
          {toast}
          <button onClick={() => setToast("")} title="닫기"><X size={16} /></button>
        </div>
      ) : null}

      {busy ? <div className="busy"><Loader2 className="spin" size={18} /> 처리 중</div> : null}

      <section className="content">
        {lessonTarget ? (
          <LessonScreen data={data} target={lessonTarget} actions={actions} />
        ) : view === "today" ? (
          <TodayScreen data={data} actions={actions} />
        ) : view === "students" ? (
          <StudentsScreen data={data} actions={actions} />
        ) : view === "quick" ? (
          <QuickInputScreen data={data} actions={actions} />
        ) : view === "reports" ? (
          <ReportsScreen data={data} actions={actions} />
        ) : (
          <MoreScreen
            data={data}
            profile={profile}
            moreView={moreView}
            setMoreView={setMoreView}
            actions={actions}
          />
        )}
      </section>

      <nav className="tabbar" aria-label="주요 메뉴">
        <TabButton label="오늘" active={view === "today"} icon={<Home size={20} />} onClick={() => { setLessonTarget(null); setView("today"); }} />
        <TabButton label="학생" active={view === "students"} icon={<Users size={20} />} onClick={() => { setLessonTarget(null); setView("students"); }} />
        <TabButton label="빠른입력" active={view === "quick"} icon={<Wand2 size={20} />} onClick={() => { setLessonTarget(null); setView("quick"); }} />
        <TabButton label="리포트" active={view === "reports"} icon={<MessageSquareText size={20} />} onClick={() => { setLessonTarget(null); setView("reports"); }} />
        <TabButton label="더보기" active={view === "more"} icon={<MoreHorizontal size={20} />} onClick={() => { setLessonTarget(null); setMoreView("menu"); setView("more"); }} />
      </nav>
    </main>
  );
}

function TodayScreen({ data, actions }: { data: AppData; actions: AppActions }) {
  const [addOpen, setAddOpen] = useState(false);
  const [studentId, setStudentId] = useState("");
  const [subject, setSubject] = useState<Subject>("영어");
  const today = todaySeoul();
  const items = todayItems(data, today);
  const stale = bridgeWarning(data);

  return (
    <div className="stack">
      <div className="date-row">
        <div>
          <p className="eyebrow">{displayDate(today)}</p>
          <h2>오늘 수업</h2>
        </div>
        <button className="secondary-button compact" onClick={() => setAddOpen(true)}>
          <Plus size={18} /> 수업 추가
        </button>
      </div>
      {stale ? <Warning text={stale} /> : null}

      {items.length === 0 ? (
        <EmptyState title="오늘 수업이 없습니다" action="보강 수업 추가" onAction={() => setAddOpen(true)} />
      ) : (
        <div className="lesson-list">
          {items.map((item) => {
            const student = findStudent(data, item.studentId);
            const last = lastProgressSummary(data, item.studentId, item.subject, today);
            const pendingHw = data.homeworks.filter((h) => h.student_id === item.studentId && h.subject === item.subject && h.status === "assigned").length;
            return (
              <button
                key={item.key}
                className={`lesson-card ${item.status}`}
                onClick={() => actions.openLesson({ lessonId: item.lesson?.id, studentId: item.studentId, subject: item.subject, scheduleSlotId: item.scheduleSlotId, startTime: item.startTime })}
              >
                <span className="time">{formatTime(item.startTime) || "보강"}</span>
                <span className="lesson-main">
                  <strong>{student?.name ?? "학생"}</strong>
                  <span>{item.subject} · {last || "직전 진도 없음"}</span>
                  {pendingHw > 0 ? <em>미체크 과제 {pendingHw}건</em> : null}
                </span>
                <StatusPill status={item.status} />
              </button>
            );
          })}
        </div>
      )}

      {addOpen ? (
        <div className="modal-backdrop" role="dialog" aria-modal="true">
          <form
            className="modal"
            onSubmit={(event) => {
              event.preventDefault();
              if (!studentId) return;
              void actions.addMakeupLesson(Number(studentId), subject);
              setAddOpen(false);
            }}
          >
            <h3>보강 수업 추가</h3>
            <label>학생
              <select value={studentId} onChange={(e) => setStudentId(e.target.value)} required>
                <option value="">선택</option>
                {data.students.filter((s) => s.active).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </label>
            <Segmented<Subject> value={subject} options={SUBJECTS} onChange={setSubject} />
            <div className="modal-actions">
              <button type="button" className="ghost-button" onClick={() => setAddOpen(false)}>닫기</button>
              <button type="submit" className="primary-button">추가</button>
            </div>
          </form>
        </div>
      ) : null}
    </div>
  );
}

function LessonScreen({ data, target, actions }: { data: AppData; target: LessonTarget; actions: AppActions }) {
  const lesson = target.lessonId ? data.lessons.find((l) => l.id === target.lessonId) ?? null : null;
  const student = findStudent(data, target.studentId);
  const assignments = activeAssignments(data, target.studentId, target.subject);
  const initial = useMemo(() => initialLessonDraft(data, target), [data, target]);
  const draftKey = `lesson-draft-${target.lessonId ?? `${target.studentId}-${target.subject}-${todaySeoul()}`}`;
  const [draft, setDraft] = useStoredState<LessonDraft>(draftKey, initial);
  const selectedAssignment = assignments.find((a) => String(a.id) === draft.textbookId) ?? assignments[0] ?? null;
  const selectedTextbook = selectedAssignment ? textbookFor(data, selectedAssignment.textbook_id) : null;
  const isStarted = Boolean(lesson?.started_at);
  const fromValue = selectedAssignment?.last_position ?? 0;
  const toNumber = draft.toValue ? Number(draft.toValue) : null;
  const progressWarning = toNumber !== null && selectedAssignment ? progressMessage(selectedAssignment, selectedTextbook, toNumber) : "";
  const carryovers = data.homeworks.filter((h) => h.student_id === target.studentId && h.subject === target.subject && h.kind === "take_home" && h.status === "assigned");
  const previous = previousLessonSummary(data, target.studentId, target.subject, lesson?.lesson_date ?? todaySeoul());

  const updateCarryover = (homeworkId: Id, patch: { status?: "done" | "partial" | "not_done"; comment?: string }) => {
    setDraft((prev) => ({
      ...prev,
      carryover: {
        ...prev.carryover,
        [homeworkId]: {
          status: patch.status ?? prev.carryover[String(homeworkId)]?.status ?? "done",
          comment: patch.comment ?? prev.carryover[String(homeworkId)]?.comment ?? ""
        }
      }
    }));
  };

  return (
    <form
      className="lesson-workspace"
      onSubmit={(event) => {
        event.preventDefault();
        void actions.saveLesson(target, draft, () => window.localStorage.removeItem(draftKey));
      }}
    >
      <button type="button" className="back-button" onClick={actions.closeLesson}><ChevronLeft size={18} /> 오늘으로</button>
      <section className="panel">
        <p className="eyebrow">{student?.name ?? "학생"} · {target.subject} · {formatTime(target.startTime)}</p>
        <h2>{lesson?.status === "done" ? "완료 수업 수정" : "수업 기록"}</h2>
        {previous ? <p className="muted">지난 수업: {previous}</p> : <p className="muted">지난 수업 기록 없음</p>}
        {!lesson?.started_at ? (
          <button type="button" className="primary-button" onClick={() => void actions.startLesson(target)}>
            <Clock3 size={18} /> 수업 시작
          </button>
        ) : null}
        {!isStarted ? (
          <button type="button" className="ghost-button" onClick={() => {
            if (!window.confirm("이 수업을 결석/취소로 기록할까요?")) return;
            const reason = window.prompt("취소 사유", "결석");
            if (reason) void actions.cancelLesson(target, reason);
          }}>결석/취소 기록</button>
        ) : null}
      </section>

      {isStarted ? (
        <>
          {carryovers.length > 0 ? (
            <section className="panel">
              <h3>미체크 집 과제</h3>
              {carryovers.map((hw) => {
                const state = draft.carryover[String(hw.id)] ?? { status: "done", comment: "" };
                return (
                  <div key={hw.id} className="inline-block">
                    <strong>{hw.description}</strong>
                    <Segmented value={state.status} options={HOMEWORK_STATUS.map((o) => o.value)} labels={Object.fromEntries(HOMEWORK_STATUS.map((o) => [o.value, o.label]))} onChange={(value) => updateCarryover(hw.id, { status: value })} />
                    <input aria-label={`${hw.description} 과제 코멘트`} value={state.comment} onChange={(e) => updateCarryover(hw.id, { comment: e.target.value })} placeholder="과제 코멘트" />
                  </div>
                );
              })}
            </section>
          ) : null}

          <section className="panel">
            <h3>진도</h3>
            {assignments.length === 0 ? (
              <Warning text="배정된 활성 교재가 없습니다. 학생 상세 또는 교재 관리에서 먼저 배정하세요." />
            ) : (
              <>
                <label>교재
                  <select value={draft.textbookId} onChange={(e) => setDraft({ ...draft, textbookId: e.target.value })}>
                    {assignments.map((a) => {
                      const tb = textbookFor(data, a.textbook_id);
                      return <option key={a.id} value={a.id}>{tb?.title ?? "교재"} ({a.last_position ?? 0}{tb?.unit_label ?? ""})</option>;
                    })}
                  </select>
                </label>
                <div className="progress-row">
                  <span>{fromValue}</span>
                  <ChevronRight size={18} />
                  <input aria-label="이번 수업 끝 진도" inputMode="numeric" value={draft.toValue} onChange={(e) => setDraft({ ...draft, toValue: onlyNumber(e.target.value) })} placeholder={selectedTextbook?.unit_label ?? "to"} />
                </div>
                {progressWarning ? <p className="form-warning">{progressWarning}</p> : null}
                <input aria-label="진도 메모" value={draft.memo} onChange={(e) => setDraft({ ...draft, memo: e.target.value })} placeholder="진도 메모(선택)" />
              </>
            )}
          </section>

          <section className="panel">
            <h3>새 과제(선택)</h3>
            <textarea aria-label="새 과제 내용" value={draft.homeworkText} onChange={(e) => setDraft({ ...draft, homeworkText: e.target.value })} placeholder="예: 워크북 30-32" rows={2} />
            <div className="two-col">
              <Segmented value={draft.homeworkKind} options={["in_class", "take_home"]} labels={{ in_class: "학원내", take_home: "집" }} onChange={(value) => setDraft({ ...draft, homeworkKind: value })} />
              <Segmented value={draft.homeworkStatus} options={HOMEWORK_STATUS.map((o) => o.value)} labels={Object.fromEntries(HOMEWORK_STATUS.map((o) => [o.value, o.label]))} onChange={(value) => setDraft({ ...draft, homeworkStatus: value })} />
            </div>
            <input aria-label="과제 코멘트" value={draft.homeworkComment} onChange={(e) => setDraft({ ...draft, homeworkComment: e.target.value })} placeholder="과제 코멘트" />
          </section>

          <section className="panel">
            <h3>코멘트</h3>
            <textarea aria-label="수업 코멘트" value={draft.comment} onChange={(e) => setDraft({ ...draft, comment: e.target.value })} placeholder="리포트에 들어갈 수업 코멘트" rows={3} />
          </section>

          <div className="sticky-actions">
            <button type="submit" className="primary-button"><Check size={18} /> 수업 완료</button>
          </div>
          <button type="button" className="cancel-link-button" onClick={() => {
            if (!window.confirm("이 수업을 결석/취소로 기록할까요?")) return;
            const reason = window.prompt("취소 사유", "결석");
            if (reason) void actions.cancelLesson(target, reason);
          }}>결석/취소 기록</button>
        </>
      ) : null}
    </form>
  );
}

function StudentsScreen({ data, actions }: { data: AppData; actions: AppActions }) {
  const [query, setQuery] = useState("");
  const [showInactive, setShowInactive] = useState(false);
  const [selectedId, setSelectedId] = useState<Id | null>(data.students.find((s) => s.active)?.id ?? null);
  const students = data.students.filter((s) => (showInactive || s.active) && s.name.includes(query));
  const selected = selectedId ? findStudent(data, selectedId) : null;

  useEffect(() => {
    if (!selectedId && students[0]) setSelectedId(students[0].id);
  }, [selectedId, students]);

  return (
    <div className="split-layout">
      <section className="panel">
        <div className="search-row">
          <Search size={18} />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="학생 검색" />
        </div>
        <label className="check-line">
          <input type="checkbox" checked={showInactive} onChange={(e) => setShowInactive(e.target.checked)} />
          비활성 포함
        </label>
        {bridgeWarning(data) ? <Warning text={bridgeWarning(data) ?? ""} /> : null}
        <div className="student-list">
          {students.map((student) => (
            <button key={student.id} className={selected?.id === student.id ? "selected row-button" : "row-button"} onClick={() => setSelectedId(student.id)}>
              <span>
                <strong>{student.name}{student.grade ? ` (${student.grade})` : ""}</strong>
                <em>{subjectsFor(data, student.id).join(" · ") || "과목 없음"}</em>
              </span>
              {!student.active ? <small>비활성</small> : null}
            </button>
          ))}
        </div>
      </section>
      {selected ? <StudentDetail data={data} student={selected} actions={actions} /> : null}
    </div>
  );
}

function StudentDetail({ data, student, actions }: { data: AppData; student: Student; actions: AppActions }) {
  const [tab, setTab] = useState<"summary" | "progress" | "homework" | "payments">("summary");
  const [scheduleForm, setScheduleForm] = useState<ScheduleForm>({ studentId: String(student.id), subject: "영어", weekday: "0", startTime: "15:00", durationMin: "40" });
  const [assignTextbookId, setAssignTextbookId] = useState("");
  const slots = scheduleForStudent(data, student.id);
  const assignments = data.studentTextbooks.filter((a) => a.student_id === student.id);
  const recentComments = data.comments.filter((c) => c.student_id === student.id).slice(0, 5);
  const studentPayments = data.payments.filter((p) => p.student_id === student.id).slice(0, 5);
  const unchecked = data.homeworks.filter((h) => h.student_id === student.id && h.status === "assigned");

  useEffect(() => {
    setScheduleForm((prev) => ({ ...prev, studentId: String(student.id) }));
  }, [student.id]);

  return (
    <section className="panel detail-panel">
      <p className="eyebrow">{student.school ?? "학교 미등록"}</p>
      <h2>{student.name}{student.grade ? ` · ${student.grade}` : ""}</h2>
      <p className="muted">학생 정보는 GoAlimi에서 관리합니다.</p>
      <Segmented value={tab} options={["summary", "progress", "homework", "payments"]} labels={{ summary: "요약", progress: "진도", homework: "과제", payments: "결제" }} onChange={setTab} />

      {tab === "summary" ? (
        <div className="stack">
          <InfoGrid items={[
            ["과목", subjectsFor(data, student.id).join(", ") || "-"],
            ["대표 학부모", primaryParent(data, student.id)?.kakao_name ?? "없음"],
            ["최근 출결", data.attendance.find((a) => a.student_id === student.id)?.event_at?.slice(0, 10) ?? "-"]
          ]} />
          <h3>주간 스케줄</h3>
          <div className="compact-list">
            {slots.map(({ slot, enrollment }) => (
              <div key={slot.id} className="compact-row">
                <span>{WEEKDAYS[slot.weekday]} {formatTime(slot.start_time)} · {enrollment.subject} · {slot.duration_min}분</span>
                <button className="icon-button danger" onClick={() => {
                  if (window.confirm("이 스케줄을 삭제할까요?")) void actions.deleteSchedule(slot.id);
                }} title="삭제"><X size={16} /></button>
              </div>
            ))}
          </div>
          <form className="inline-form" onSubmit={(e) => { e.preventDefault(); void actions.saveSchedule(scheduleForm); }}>
            <select value={scheduleForm.subject} onChange={(e) => setScheduleForm({ ...scheduleForm, subject: e.target.value as Subject })}>{SUBJECTS.map((s) => <option key={s}>{s}</option>)}</select>
            <select value={scheduleForm.weekday} onChange={(e) => setScheduleForm({ ...scheduleForm, weekday: e.target.value })}>{WEEKDAYS.map((w, i) => <option key={w} value={i}>{w}</option>)}</select>
            <input type="time" value={scheduleForm.startTime} onChange={(e) => setScheduleForm({ ...scheduleForm, startTime: e.target.value })} />
            <input inputMode="numeric" value={scheduleForm.durationMin} onChange={(e) => setScheduleForm({ ...scheduleForm, durationMin: onlyNumber(e.target.value) })} />
            <button className="secondary-button" type="submit"><Plus size={16} /> 저장</button>
          </form>
          {unchecked.length ? <Warning text={`미체크 과제 ${unchecked.length}건`} /> : null}
          {recentComments.map((c) => <p key={c.id} className="note-line">{c.subject ?? "공통"} · {c.body}</p>)}
        </div>
      ) : tab === "progress" ? (
        <div className="stack">
          <h3>교재 배정</h3>
          {assignments.map((a) => {
            const tb = textbookFor(data, a.textbook_id);
            const pct = tb?.total_units && a.last_position ? Math.min(100, Math.round((a.last_position / tb.total_units) * 100)) : 0;
            return (
              <div key={a.id} className="book-row">
                <span><strong>{tb?.title ?? "교재"}</strong><em>{a.status} · {a.last_position ?? 0}{tb?.unit_label}</em></span>
                <span className="bar"><span style={{ width: `${pct}%` }} /></span>
                {a.status === "active" ? <button className="secondary-button compact" onClick={() => {
                  if (window.confirm(`${tb?.title ?? "교재"}를 완료 처리할까요?`)) void actions.completeAssignment(a.id);
                }}>완료 처리</button> : null}
              </div>
            );
          })}
          <form className="inline-form" onSubmit={(e) => { e.preventDefault(); if (assignTextbookId) void actions.assignTextbook(student.id, Number(assignTextbookId)); }}>
            <select value={assignTextbookId} onChange={(e) => setAssignTextbookId(e.target.value)}>
              <option value="">교재 선택</option>
              {data.textbooks.filter((tb) => tb.active).map((tb) => <option key={tb.id} value={tb.id}>{tb.subject} · {tb.title}</option>)}
            </select>
            <button className="secondary-button" type="submit"><BookOpen size={16} /> 배정</button>
          </form>
          <h3>최근 진도</h3>
          {data.progress.filter((p) => {
            const a = assignments.find((x) => x.id === p.student_textbook_id);
            return Boolean(a);
          }).slice(0, 20).map((p) => {
            const a = assignments.find((x) => x.id === p.student_textbook_id);
            const tb = a ? textbookFor(data, a.textbook_id) : null;
            return <p key={p.id} className="note-line">{p.created_at.slice(0, 10)} · {tb?.title} {p.from_value}→{p.to_value}</p>;
          })}
        </div>
      ) : tab === "homework" ? (
        <div className="stack">
          {data.homeworks.filter((h) => h.student_id === student.id).map((hw) => (
            <p key={hw.id} className="note-line">{hw.subject} · {hw.description} · {homeworkStatusLabel(hw.status)}{hw.teacher_comment ? ` · ${hw.teacher_comment}` : ""}</p>
          ))}
        </div>
      ) : (
        <div className="stack">
          {studentPayments.map((p) => <p key={p.id} className="note-line">{p.paid_on} · {p.method} · {formatKrw(paymentTotal(p))}원</p>)}
        </div>
      )}
    </section>
  );
}

function QuickInputScreen({ data, actions }: { data: AppData; actions: AppActions }) {
  const [text, setText] = useStoredState("quick-input-draft", "");
  const [results, setResults] = useState<ParseResult[]>([]);
  const [parsing, setParsing] = useState(false);
  const [error, setError] = useState("");
  const okCount = results.filter(isSavableParseResult).length;
  const errorCount = results.length - okCount;

  async function parse() {
    setParsing(true);
    setError("");
    try {
      const rows = await actions.parseBatch(text);
      setResults(rows);
    } catch (err) {
      setError(toMessage(err));
    } finally {
      setParsing(false);
    }
  }

  const updateRow = (line: number, patch: Partial<NonNullable<ParseResult["parsed"]>>) => {
    setResults((prev) => prev.map((row) => {
      if (row.line !== line) return row;
      const parsed = row.parsed;
      const nextParsed: NonNullable<ParseResult["parsed"]> = {
        student_id: "student_id" in patch ? patch.student_id ?? 0 : parsed?.student_id ?? 0,
        student_name: "student_name" in patch ? patch.student_name ?? "" : parsed?.student_name ?? "",
        subject: "subject" in patch ? patch.subject ?? null : parsed?.subject ?? null,
        student_textbook_id: "student_textbook_id" in patch ? patch.student_textbook_id ?? null : parsed?.student_textbook_id ?? null,
        textbook_title: "textbook_title" in patch ? patch.textbook_title ?? null : parsed?.textbook_title ?? null,
        from_value: "from_value" in patch ? patch.from_value ?? null : parsed?.from_value ?? null,
        to_value: "to_value" in patch ? patch.to_value ?? null : parsed?.to_value ?? null,
        homework: "homework" in patch ? patch.homework ?? null : parsed?.homework ?? null,
        comment: "comment" in patch ? patch.comment ?? null : parsed?.comment ?? null
      };
      const canSave = Boolean(nextParsed.student_id && nextParsed.subject && hasRecordableParseContent(nextParsed));
      return {
        ...row,
        ok: canSave,
        error: canSave ? undefined : row.error ?? "학생·과목·기록 내용을 확인하세요.",
        parsed: nextParsed
      };
    }));
  };

  return (
    <div className="stack">
      <section className="panel">
        <h2>텍스트 붙여넣기</h2>
        <textarea aria-label="빠른 입력 원문" value={text} onChange={(e) => setText(e.target.value)} rows={8} placeholder="민수 영어 브릭스 38-42 숙제 43~45 독해 좋아짐" />
        {error ? <Warning text={error} /> : null}
        <button className="primary-button" onClick={() => void parse()} disabled={!text.trim() || parsing}>
          {parsing ? <Loader2 className="spin" size={18} /> : <Wand2 size={18} />} 파싱하기
        </button>
      </section>

      {results.length > 0 ? (
        <section className="panel">
          <h3>결과 카드</h3>
          <div className={errorCount ? "summary-strip warning-strip" : "summary-strip"}>
            <span>저장 가능 {okCount}건</span>
            {errorCount ? <span>확인 필요 {errorCount}건</span> : <span>모두 저장 가능</span>}
          </div>
          {errorCount ? <p className="muted">오류 카드는 저장하지 않습니다. 필요한 카드는 학생·과목·교재를 고친 뒤 저장하세요.</p> : null}
          <div className="stack">
            {results.map((row) => (
              <div key={`${row.line}-${row.raw}`} className={row.ok ? "parse-card" : "parse-card error"}>
                <p className="eyebrow">{row.method ?? "manual"} · {row.raw}</p>
                {!row.ok ? <strong>오류: {row.error}</strong> : null}
                <div className="two-col">
                  <select aria-label={`${row.line}번 카드 학생`} value={row.parsed?.student_id ?? ""} onChange={(e) => {
                    const studentId = e.target.value ? Number(e.target.value) : 0;
                    const student = studentId ? findStudent(data, studentId) : null;
                    updateRow(row.line, { student_id: studentId, student_name: student?.name ?? "" });
                  }}>
                    <option value="">학생 선택</option>
                    {data.students.filter((s) => s.active).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                  <select aria-label={`${row.line}번 카드 과목`} value={row.parsed?.subject ?? ""} onChange={(e) => updateRow(row.line, { subject: e.target.value ? e.target.value as Subject : null })}>
                    <option value="">과목</option>
                    {SUBJECTS.map((s) => <option key={s}>{s}</option>)}
                  </select>
                </div>
                <select aria-label={`${row.line}번 카드 교재`} value={row.parsed?.student_textbook_id ?? ""} onChange={(e) => {
                  const assignmentId = e.target.value ? Number(e.target.value) : null;
                  const a = assignmentId ? data.studentTextbooks.find((x) => x.id === assignmentId) : null;
                  const tb = a ? textbookFor(data, a.textbook_id) : null;
                  updateRow(row.line, { student_textbook_id: assignmentId, textbook_title: tb?.title ?? null, from_value: a?.last_position ?? null });
                }}>
                  <option value="">교재 선택</option>
                  {activeAssignments(data, row.parsed?.student_id ?? 0, row.parsed?.subject ?? null).map((a) => {
                    const tb = textbookFor(data, a.textbook_id);
                    return <option key={a.id} value={a.id}>{tb?.title}</option>;
                  })}
                </select>
                <div className="two-col">
                  <input aria-label={`${row.line}번 카드 시작 진도`} inputMode="numeric" value={row.parsed?.from_value ?? ""} onChange={(e) => updateRow(row.line, { from_value: optionalNumber(e.target.value) })} placeholder="from" />
                  <input aria-label={`${row.line}번 카드 끝 진도`} inputMode="numeric" value={row.parsed?.to_value ?? ""} onChange={(e) => updateRow(row.line, { to_value: optionalNumber(e.target.value) })} placeholder="to" />
                </div>
                <input aria-label={`${row.line}번 카드 과제`} value={row.parsed?.homework ?? ""} onChange={(e) => updateRow(row.line, { homework: e.target.value })} placeholder="과제" />
                <input aria-label={`${row.line}번 카드 코멘트`} value={row.parsed?.comment ?? ""} onChange={(e) => updateRow(row.line, { comment: e.target.value })} placeholder="코멘트" />
                {row.warning ? <p className="form-warning">{row.warning}</p> : null}
              </div>
            ))}
          </div>
          <button className="primary-button" onClick={() => void actions.saveParsed(results)} disabled={okCount === 0}>
            <Save size={18} /> {errorCount ? `정상 ${okCount}건만 저장` : `${okCount}건 저장`}
          </button>
        </section>
      ) : null}
    </div>
  );
}

function ReportsScreen({ data, actions }: { data: AppData; actions: AppActions }) {
  const today = todaySeoul();
  const [start, setStart] = useState(addDays(today, -13));
  const [end, setEnd] = useState(today);
  const [selectedStudents, setSelectedStudents] = useState<Id[]>(data.students.filter((s) => s.active).map((s) => s.id));
  const [status, setStatus] = useState<"all" | Report["status"]>("all");
  const [selectedReportId, setSelectedReportId] = useState<Id | null>(null);
  const selected = data.reports.find((r) => r.id === selectedReportId) ?? data.reports[0] ?? null;
  const [body, setBody] = useState(selected?.body ?? "");

  useEffect(() => setBody(selected?.body ?? ""), [selected?.id, selected?.body]);

  const reports = data.reports.filter((r) => status === "all" || r.status === status);
  const selectedParent = selected ? primaryParent(data, selected.student_id) : null;
  const confirmSend = (report: Report, resend: boolean) => {
    const student = studentName(data, report.student_id);
    const verb = resend ? "재발송" : "카카오톡 발송";
    if (window.confirm(`${student} 리포트를 ${verb}할까요?`)) void actions.enqueueReport(report, resend, report.status === "sent" ? undefined : body);
  };

  return (
    <div className="split-layout">
      <section className="panel">
        <h2>리포트 생성</h2>
        <div className="two-col">
          <label>시작일<input type="date" value={start} onChange={(e) => setStart(e.target.value)} /></label>
          <label>종료일<input type="date" value={end} onChange={(e) => setEnd(e.target.value)} /></label>
        </div>
        <div className="chip-list">
          {data.students.filter((s) => s.active).map((s) => (
            <button key={s.id} className={selectedStudents.includes(s.id) ? "chip active" : "chip"} onClick={() => setSelectedStudents((prev) => prev.includes(s.id) ? prev.filter((id) => id !== s.id) : [...prev, s.id])}>{s.name}</button>
          ))}
        </div>
        <button className="primary-button" onClick={() => void actions.generateReports(selectedStudents, start, end)} disabled={selectedStudents.length === 0}>
          <Wand2 size={18} /> 초안 생성
        </button>
        <Segmented value={status} options={["all", "draft", "ready", "sent"]} labels={{ all: "전체", draft: "초안", ready: "승인", sent: "발송" }} onChange={setStatus} />
        <div className="compact-list">
          {reports.map((report) => {
            const failed = latestOutbox(data, report.id, "failed");
            return (
              <button key={report.id} className={selected?.id === report.id ? "row-button selected" : "row-button"} onClick={() => setSelectedReportId(report.id)}>
                <span><strong>{studentName(data, report.student_id)}</strong><em>{report.period_start}~{report.period_end}</em></span>
                {failed ? <small className="fail">실패</small> : <StatusPill status={report.status} />}
              </button>
            );
          })}
        </div>
      </section>
      {selected ? (
        <section className="panel detail-panel">
          <p className="eyebrow">{studentName(data, selected.student_id)} · {selected.status}</p>
          <h2>검토</h2>
          <StatsSummary report={selected} />
          <p className={selectedParent?.notify_enabled ? "muted" : "form-warning"}>
            발송 대상: {selectedParent?.kakao_name ?? "대표 학부모 없음"}
          </p>
          <textarea aria-label="리포트 본문" value={body} onChange={(e) => setBody(e.target.value)} rows={14} readOnly={selected.status === "sent"} />
          <p className={body.length >= 600 && body.length <= 900 ? "muted" : "form-warning"}>{body.length}자 · 권장 600~900자</p>
          <div className="button-row">
            {selected.status !== "sent" ? <button className="secondary-button" onClick={() => void actions.saveReportBody(selected.id, body)}><Save size={16} /> 저장</button> : null}
            {selected.status === "draft" ? <button className="primary-button" onClick={() => void actions.approveReport(selected.id, body)}><Check size={16} /> 저장 후 발송 승인</button> : null}
            {selected.status === "ready" ? <button className="primary-button" onClick={() => confirmSend(selected, false)} disabled={!selectedParent?.notify_enabled}><Send size={16} /> 저장 후 카카오톡 발송</button> : null}
            {selected.status === "sent" ? <button className="secondary-button" onClick={() => confirmSend(selected, true)}><Send size={16} /> 재발송</button> : null}
          </div>
        </section>
      ) : null}
    </div>
  );
}

function MoreScreen({ data, profile, moreView, setMoreView, actions }: { data: AppData; profile: AppData["profiles"][number] | null; moreView: MoreView; setMoreView: (view: MoreView) => void; actions: AppActions }) {
  if (moreView === "payments") return <PaymentsScreen data={data} actions={actions} onBack={() => setMoreView("menu")} />;
  if (moreView === "textbooks") return <TextbooksScreen data={data} actions={actions} onBack={() => setMoreView("menu")} />;
  if (moreView === "outbox") return <OutboxScreen data={data} actions={actions} onBack={() => setMoreView("menu")} />;
  if (moreView === "shortcut") return <ShortcutScreen data={data} onBack={() => setMoreView("menu")} />;
  if (moreView === "settings") return <SettingsScreen data={data} profile={profile} actions={actions} onBack={() => setMoreView("menu")} />;
  return (
    <div className="stack">
      <MenuButton icon={<CreditCard size={20} />} title="수강료" detail="결제 입력·월별 집계" onClick={() => setMoreView("payments")} />
      <MenuButton icon={<BookOpen size={20} />} title="교재" detail="교재 등록·배정" onClick={() => setMoreView("textbooks")} />
      <MenuButton icon={<Send size={20} />} title="발송현황" detail="대기·성공·실패 확인" onClick={() => setMoreView("outbox")} />
      <MenuButton icon={<ExternalLink size={20} />} title="GoAlimi 출결 관리" detail="학원 네트워크에서만 열립니다" onClick={() => setMoreView("shortcut")} />
      <MenuButton icon={<Settings size={20} />} title="설정" detail="계정·문구·동기화 상태" onClick={() => setMoreView("settings")} />
    </div>
  );
}

function PaymentsScreen({ data, actions, onBack }: { data: AppData; actions: AppActions; onBack: () => void }) {
  const [form, setForm] = useStoredState<PaymentForm>("payment-draft", { id: null, studentId: "", paidOn: todaySeoul(), method: "카드", memo: "", items: [{ subject: "영어", amount: "" }] });
  const [month, setMonth] = useState(monthKey());
  const monthly = data.payments.filter((p) => p.paid_on.startsWith(month));
  const total = monthly.reduce((sum, p) => sum + paymentTotal(p), 0);
  const byMethod = Object.fromEntries(PAYMENT_METHODS.map((m) => [m, monthly.filter((p) => p.method === m).reduce((sum, p) => sum + paymentTotal(p), 0)]));

  const edit = (payment: Payment) => setForm({
    id: payment.id,
    studentId: String(payment.student_id),
    paidOn: payment.paid_on,
    method: payment.method,
    memo: payment.memo ?? "",
    items: (payment.payment_items ?? []).map((item) => ({ subject: item.subject, amount: String(item.amount) }))
  });

  return (
    <div className="split-layout">
      <section className="panel">
        <button className="back-button" onClick={onBack}><ChevronLeft size={18} /> 더보기</button>
        <h2>결제 입력</h2>
        <form className="stack" onSubmit={(e) => { e.preventDefault(); void actions.savePayment(form); }}>
          <select value={form.studentId} onChange={(e) => setForm({ ...form, studentId: e.target.value })} required>
            <option value="">학생 선택</option>
            {data.students.filter((s) => s.active).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
          <input type="date" value={form.paidOn} onChange={(e) => setForm({ ...form, paidOn: e.target.value })} />
          <Segmented value={form.method} options={[...PAYMENT_METHODS]} onChange={(value) => setForm({ ...form, method: value })} />
          {form.items.map((item, index) => (
            <div key={index} className="two-col">
              <input value={item.subject} onChange={(e) => setForm({ ...form, items: replaceAt(form.items, index, { ...item, subject: e.target.value }) })} placeholder="과목" />
              <input inputMode="numeric" value={item.amount} onChange={(e) => setForm({ ...form, items: replaceAt(form.items, index, { ...item, amount: signedNumber(e.target.value) }) })} placeholder="금액" />
            </div>
          ))}
          <button type="button" className="ghost-button" onClick={() => setForm({ ...form, items: [...form.items, { subject: "교재비", amount: "" }] })}><Plus size={16} /> 항목</button>
          <input value={form.memo} onChange={(e) => setForm({ ...form, memo: e.target.value })} placeholder="메모" />
          <button className="primary-button" type="submit"><Save size={18} /> 저장</button>
        </form>
      </section>
      <section className="panel detail-panel">
        <div className="month-row">
          <button className="icon-button" onClick={() => setMonth(shiftMonth(month, -1))}><ChevronLeft size={18} /></button>
          <strong>{month}</strong>
          <button className="icon-button" onClick={() => setMonth(shiftMonth(month, 1))}><ChevronRight size={18} /></button>
        </div>
        <InfoGrid items={[
          ["총액", `${formatKrw(total)}원`],
          ["카드", `${formatKrw(byMethod["카드"])}원`],
          ["현금", `${formatKrw(byMethod["현금"])}원`],
          ["이체", `${formatKrw(byMethod["계좌이체"])}원`]
        ]} />
        {monthly.map((p) => (
          <div key={p.id} className="compact-row">
            <button className="row-button" onClick={() => edit(p)}>
              <span><strong>{studentName(data, p.student_id)}</strong><em>{p.paid_on} · {p.method}</em></span>
              <small>{formatKrw(paymentTotal(p))}원</small>
            </button>
            <button className="icon-button danger" onClick={() => {
              if (window.confirm("이 결제 기록을 삭제할까요? 삭제 이력은 남습니다.")) void actions.deletePayment(p.id);
            }} title="삭제"><X size={16} /></button>
          </div>
        ))}
      </section>
    </div>
  );
}

function TextbooksScreen({ data, actions, onBack }: { data: AppData; actions: AppActions; onBack: () => void }) {
  const empty: TextbookForm = { id: null, subject: "영어", title: "", publisher: "", unitLabel: "페이지", totalUnits: "", aliases: "", active: true };
  const [form, setForm] = useState<TextbookForm>(empty);
  const [subject, setSubject] = useState<"all" | Subject>("all");
  const list = data.textbooks.filter((tb) => subject === "all" || tb.subject === subject);
  const edit = (tb: Textbook) => setForm({ id: tb.id, subject: tb.subject, title: tb.title, publisher: tb.publisher ?? "", unitLabel: tb.unit_label, totalUnits: tb.total_units ? String(tb.total_units) : "", aliases: tb.aliases.join(", "), active: tb.active });

  return (
    <div className="split-layout">
      <section className="panel">
        <button className="back-button" onClick={onBack}><ChevronLeft size={18} /> 더보기</button>
        <h2>교재 관리</h2>
        <Segmented value={subject} options={["all", "영어", "수학"]} labels={{ all: "전체", 영어: "영어", 수학: "수학" }} onChange={setSubject} />
        <div className="compact-list">
          {list.map((tb) => (
            <button key={tb.id} className="row-button" onClick={() => edit(tb)}>
              <span><strong>{tb.title}</strong><em>{tb.subject} · {tb.unit_label} · {tb.aliases.join(", ")}</em></span>
              {!tb.active ? <small>비활성</small> : null}
            </button>
          ))}
        </div>
      </section>
      <section className="panel detail-panel">
        <h2>{form.id ? "교재 수정" : "교재 등록"}</h2>
        <form className="stack" onSubmit={(e) => { e.preventDefault(); void actions.saveTextbook(form); setForm(empty); }}>
          <Segmented value={form.subject} options={SUBJECTS} onChange={(value) => setForm({ ...form, subject: value })} />
          <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="교재명" required />
          <input value={form.publisher} onChange={(e) => setForm({ ...form, publisher: e.target.value })} placeholder="출판사" />
          <div className="two-col">
            <input value={form.unitLabel} onChange={(e) => setForm({ ...form, unitLabel: e.target.value })} placeholder="진도 단위" />
            <input inputMode="numeric" value={form.totalUnits} onChange={(e) => setForm({ ...form, totalUnits: onlyNumber(e.target.value) })} placeholder="총량" />
          </div>
          <input value={form.aliases} onChange={(e) => setForm({ ...form, aliases: e.target.value })} placeholder="별칭, 쉼표 구분" />
          <label className="check-line"><input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} /> 활성</label>
          <button className="primary-button" type="submit"><Save size={18} /> 저장</button>
        </form>
      </section>
    </div>
  );
}

function OutboxScreen({ data, actions, onBack }: { data: AppData; actions: AppActions; onBack: () => void }) {
  const pending = data.outbox.filter((o) => o.status === "pending" || o.status === "processing").length;
  const sent = data.outbox.filter((o) => o.status === "sent").length;
  const failed = data.outbox.filter((o) => o.status === "failed").length;
  const stale = bridgeWarning(data);

  return (
    <div className="stack">
      <section className="panel">
        <button className="back-button" onClick={onBack}><ChevronLeft size={18} /> 더보기</button>
        <h2>발송 현황</h2>
        {stale ? <Warning text={stale} /> : null}
        <InfoGrid items={[["대기", String(pending)], ["성공", String(sent)], ["실패", String(failed)]]} />
      </section>
      {data.outbox.map((row) => {
        const report = row.report_id ? data.reports.find((r) => r.id === row.report_id) : null;
        const uncertain = row.error === "timeout" || row.error === "interrupted";
        return (
          <section className="panel outbox-row" key={row.id}>
            <div>
              <p className="eyebrow">{row.created_at.slice(0, 16).replace("T", " ")}</p>
              <h3>{studentName(data, row.student_id)} · {row.kakao_name}</h3>
              <p className="muted">{row.dedupe_key}</p>
              {row.error ? <p className="form-warning">{row.error}{uncertain ? " · 수신 확인 후 재발송" : ""}</p> : null}
            </div>
            <div className="outbox-actions">
              <StatusPill status={row.status} />
              {row.status === "failed" && report ? <button className="secondary-button compact" onClick={() => {
                if (window.confirm(`${studentName(data, row.student_id)} 리포트를 다시 발송 대기열에 넣을까요?`)) {
                  void actions.enqueueReport(report, report.status === "sent");
                }
              }}>재전송</button> : null}
            </div>
          </section>
        );
      })}
    </div>
  );
}

function ShortcutScreen({ data, onBack }: { data: AppData; onBack: () => void }) {
  const url = data.settings.goalimi_admin_url || "http://127.0.0.1:8000/admin";
  return (
    <section className="panel">
      <button className="back-button" onClick={onBack}><ChevronLeft size={18} /> 더보기</button>
      <h2>GoAlimi 출결 관리</h2>
      <p className="muted">학원 네트워크에서만 열립니다. GoLesson 안에 삽입하지 않고 새 탭으로 엽니다.</p>
      <a className="primary-button link-button" href={url} target="_blank" rel="noopener">
        <ExternalLink size={18} /> GoAlimi 열기
      </a>
    </section>
  );
}

function SettingsScreen({ data, profile, actions, onBack }: { data: AppData; profile: AppData["profiles"][number] | null; actions: AppActions; onBack: () => void }) {
  const [settings, setSettings] = useState({
    academy_name: data.settings.academy_name ?? "",
    report_greeting: data.settings.report_greeting ?? "",
    report_closing: data.settings.report_closing ?? "",
    goalimi_admin_url: data.settings.goalimi_admin_url ?? "http://127.0.0.1:8000/admin"
  });

  return (
    <div className="split-layout">
      <section className="panel">
        <button className="back-button" onClick={onBack}><ChevronLeft size={18} /> 더보기</button>
        <h2>내 계정</h2>
        <InfoGrid items={[["이름", profile?.name ?? "-"], ["역할", profile?.role ?? "-"]]} />
        <button className="danger-button" onClick={() => void actions.signOut()}><LogOut size={18} /> 로그아웃</button>
        <h3>강사 목록</h3>
        {data.profiles.map((p) => <p key={p.id} className="note-line">{p.name} · {p.role}{!p.active ? " · 비활성" : ""}</p>)}
        <h3>동기화 상태</h3>
        <p className="note-line">Bridge: {data.settings.bridge_last_poll_at ?? "기록 없음"}</p>
      </section>
      <section className="panel detail-panel">
        <h2>운영 설정</h2>
        <form className="stack" onSubmit={(e) => { e.preventDefault(); void actions.saveSettings(settings); }}>
          <input value={settings.academy_name} onChange={(e) => setSettings({ ...settings, academy_name: e.target.value })} placeholder="학원명" />
          <textarea value={settings.report_greeting} onChange={(e) => setSettings({ ...settings, report_greeting: e.target.value })} placeholder="리포트 인사말" rows={3} />
          <textarea value={settings.report_closing} onChange={(e) => setSettings({ ...settings, report_closing: e.target.value })} placeholder="리포트 맺음말" rows={3} />
          <input value={settings.goalimi_admin_url} onChange={(e) => setSettings({ ...settings, goalimi_admin_url: e.target.value })} placeholder="GoAlimi 주소" />
          <button className="primary-button" type="submit"><Save size={18} /> 저장</button>
        </form>
      </section>
    </div>
  );
}

function LoginScreen({ onLogin, busy, error }: { onLogin: (email: string, password: string) => void; busy: boolean; error: string }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  return (
    <main className="login-shell">
      <form className="login-panel" onSubmit={(event: FormEvent) => { event.preventDefault(); onLogin(email, password); }}>
        <div className="brand-mark"><BookOpen size={28} /></div>
        <h1>GoLesson</h1>
        <p>사전 등록된 강사 계정으로 로그인</p>
        <input type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="email@example.com" required />
        <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호" required />
        {error ? <p className="form-warning">{error}</p> : null}
        <button className="primary-button" disabled={busy}>{busy ? <Loader2 className="spin" size={18} /> : null} 로그인</button>
      </form>
    </main>
  );
}

function MissingEnv() {
  return (
    <main className="login-shell">
      <section className="login-panel">
        <div className="brand-mark"><AlertTriangle size={28} /></div>
        <h1>환경 변수 필요</h1>
        <p>NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY를 web 실행 환경에 설정하세요.</p>
      </section>
    </main>
  );
}

function DisabledAccount({ onSignOut }: { onSignOut: () => void }) {
  return (
    <main className="login-shell">
      <section className="login-panel">
        <h1>비활성 계정</h1>
        <p>이 계정은 사용 중지 상태입니다. 원장에게 계정 활성화를 요청하세요.</p>
        <button className="danger-button" onClick={onSignOut}>로그아웃</button>
      </section>
    </main>
  );
}

function LoadingScreen({ label }: { label: string }) {
  return <main className="login-shell"><section className="login-panel"><Loader2 className="spin" /><p>{label}</p></section></main>;
}

function TabButton({ label, icon, active, onClick }: { label: string; icon: ReactNode; active: boolean; onClick: () => void }) {
  return <button className={active ? "tab active" : "tab"} onClick={onClick}>{icon}<span>{label}</span></button>;
}

function Segmented<T extends string>({ value, options, labels, onChange }: { value: T; options: readonly T[]; labels?: Record<string, string>; onChange: (value: T) => void }) {
  return (
    <div className="segmented">
      {options.map((option) => <button type="button" key={option} className={option === value ? "active" : ""} aria-pressed={option === value} onClick={() => onChange(option)}>{labels?.[option] ?? option}</button>)}
    </div>
  );
}

function Warning({ text }: { text: string }) {
  return <div className="warning"><AlertTriangle size={18} /> {text}</div>;
}

function EmptyState({ title, action, onAction }: { title: string; action: string; onAction: () => void }) {
  return <section className="empty-state"><p>{title}</p><button className="secondary-button" onClick={onAction}><Plus size={18} /> {action}</button></section>;
}

function StatusPill({ status }: { status: string }) {
  return <span className={`status-pill ${status}`}>{statusLabel(status)}</span>;
}

function InfoGrid({ items }: { items: [string, string][] }) {
  return <div className="info-grid">{items.map(([label, value]) => <div key={label}><span>{label}</span><strong>{value}</strong></div>)}</div>;
}

function MenuButton({ icon, title, detail, onClick }: { icon: ReactNode; title: string; detail: string; onClick: () => void }) {
  return <button className="menu-button" onClick={onClick}>{icon}<span><strong>{title}</strong><em>{detail}</em></span><ChevronRight size={18} /></button>;
}

function StatsSummary({ report }: { report: Report }) {
  const attendance = (report.stats?.attendance ?? {}) as { scheduled?: number; done?: number; checkin?: number };
  const subjects = (report.stats?.subjects ?? {}) as Record<string, { progress?: { textbook: string; from: number; to: number; unit: string }[]; homework?: { checked?: number; done?: number } }>;
  return (
    <div className="stats-box">
      <p>출석: {attendance.done ?? 0}회 / 예정 {attendance.scheduled ?? 0}회 · 등원 {attendance.checkin ?? 0}회</p>
      {Object.entries(subjects).map(([subject, value]) => (
        <p key={subject}>{subject}: {(value.progress ?? []).map((p) => `${p.textbook} ${p.from}→${p.to}${p.unit}`).join(", ") || "진도 없음"} · 과제 {value.homework?.done ?? 0}/{value.homework?.checked ?? 0}</p>
      ))}
    </div>
  );
}

async function startLesson(supabase: ReturnType<typeof getSupabase>, data: AppData, target: LessonTarget): Promise<Id> {
  if (target.lessonId) {
    const { error } = await supabase.from("lessons").update({ started_at: nowIso(), status: "in_progress" }).eq("id", target.lessonId);
    if (error) throw error;
    return target.lessonId;
  }
  const student = findStudent(data, target.studentId);
  if (!student) throw new Error("학생을 찾을 수 없습니다.");
  const { data: row, error } = await supabase
    .from("lessons")
    .insert({
      student_id: target.studentId,
      subject: target.subject,
      schedule_slot_id: target.scheduleSlotId,
      lesson_date: todaySeoul(),
      started_at: nowIso(),
      status: "in_progress"
    })
    .select("id")
    .single();
  if (error || !row) throw error ?? new Error("수업 시작 기록 실패");
  return row.id as number;
}

async function saveLesson(supabase: ReturnType<typeof getSupabase>, data: AppData, target: LessonTarget, draft: LessonDraft) {
  let progress: Record<string, unknown> | null = null;
  if (draft.textbookId && draft.toValue) {
    const assignment = data.studentTextbooks.find((a) => a.id === Number(draft.textbookId));
    if (assignment?.status === "completed") throw new Error("완료된 교재에는 진도를 입력할 수 없습니다.");
    const tb = assignment ? textbookFor(data, assignment.textbook_id) : null;
    const [fromValue, toValue] = orderedRange(assignment?.last_position ?? 0, Number(draft.toValue));
    const completeAssignmentNow = Boolean(
      assignment &&
      tb?.total_units &&
      toValue >= tb.total_units &&
      window.confirm(`${tb.title} 완료 처리할까요?`)
    );
    progress = {
      student_textbook_id: Number(draft.textbookId),
      from_value: fromValue,
      to_value: toValue,
      memo: draft.memo || null,
      complete_assignment: completeAssignmentNow
    };
  }

  const newHomework = draft.homeworkText.trim()
    ? {
        description: draft.homeworkText.trim(),
        kind: draft.homeworkKind,
        status: draft.homeworkStatus,
        teacher_comment: draft.homeworkComment || null
      }
    : null;

  const { error } = await supabase.rpc("save_lesson_log", {
    p_payload: {
      lesson_id: target.lessonId ?? null,
      student_id: target.studentId,
      subject: target.subject,
      schedule_slot_id: target.scheduleSlotId ?? null,
      lesson_date: todaySeoul(),
      progress,
      carryover: Object.entries(draft.carryover).map(([id, state]) => ({
        id: Number(id),
        status: state.status,
        comment: state.comment || null
      })),
      new_homework: newHomework,
      comment: draft.comment.trim() || null
    }
  });
  if (error) throw error;
}

async function cancelLesson(supabase: ReturnType<typeof getSupabase>, target: LessonTarget, reason: string) {
  if (target.lessonId) {
    const { error } = await supabase.from("lessons").update({ status: "canceled", cancel_reason: reason }).eq("id", target.lessonId);
    if (error) throw error;
    return;
  }
  const { error } = await supabase.from("lessons").insert({
    student_id: target.studentId,
    subject: target.subject,
    schedule_slot_id: target.scheduleSlotId,
    lesson_date: todaySeoul(),
    status: "canceled",
    cancel_reason: reason
  });
  if (error) throw error;
}

async function saveSchedule(supabase: ReturnType<typeof getSupabase>, data: AppData, form: ScheduleForm) {
  const studentId = Number(form.studentId);
  if (!studentId) throw new Error("학생을 선택하세요.");
  let enrollment = data.enrollments.find((e) => e.student_id === studentId && e.subject === form.subject);
  if (!enrollment) {
    const { data: row, error } = await supabase.from("enrollments").insert({ student_id: studentId, subject: form.subject, active: true }).select("id,student_id,subject,active").single();
    if (error || !row) throw error ?? new Error("과목 등록 실패");
    enrollment = row as unknown as AppData["enrollments"][number];
  }
  const { error } = await supabase.from("schedule_slots").insert({
    enrollment_id: enrollment.id,
    weekday: Number(form.weekday),
    start_time: form.startTime,
    duration_min: Number(form.durationMin || 40)
  });
  if (error) throw error;
}

async function assignTextbook(supabase: ReturnType<typeof getSupabase>, studentId: Id, textbookId: Id) {
  const { error } = await supabase.from("student_textbooks").insert({ student_id: studentId, textbook_id: textbookId, status: "active", started_on: todaySeoul() });
  if (error) throw error;
}

async function completeAssignment(supabase: ReturnType<typeof getSupabase>, assignmentId: Id) {
  const { error } = await supabase.from("student_textbooks").update({ status: "completed", completed_on: todaySeoul() }).eq("id", assignmentId);
  if (error) throw error;
}

async function saveParsedRows(supabase: ReturnType<typeof getSupabase>, data: AppData, rows: ParseResult[]) {
  const okRows = rows.filter(isSavableParseResult);
  if (okRows.length < rows.length && !window.confirm("오류 카드는 제외하고 저장할까요?")) return;
  for (const row of okRows) {
    const parsed = row.parsed!;
    const existing = data.lessons.find((l) => l.student_id === parsed.student_id && l.subject === parsed.subject && l.lesson_date === todaySeoul() && l.status !== "canceled");
    const progress = parsed.student_textbook_id && parsed.to_value !== null
      ? (() => {
          const [fromValue, toValue] = orderedRange(parsed.from_value ?? 0, parsed.to_value);
          return {
            student_textbook_id: parsed.student_textbook_id,
            from_value: fromValue,
            to_value: toValue,
            memo: row.warning ?? null,
            complete_assignment: false
          };
        })()
      : null;
    const { error } = await supabase.rpc("save_lesson_log", {
      p_payload: {
        lesson_id: existing?.id ?? null,
        student_id: parsed.student_id,
        subject: parsed.subject,
        schedule_slot_id: existing?.schedule_slot_id ?? null,
        lesson_date: todaySeoul(),
        progress,
        carryover: [],
        new_homework: parsed.homework?.trim()
          ? {
              description: parsed.homework.trim(),
              kind: "take_home",
              status: "assigned",
              teacher_comment: null
            }
          : null,
        comment: parsed.comment?.trim() || null,
        parse_log_id: row.parse_log_id ?? null
      }
    });
    if (error) throw error;
  }
}

// Surface the Edge Function's JSON { message } (for example a 409 conflict)
// instead of supabase-js's generic "Edge Function returned a non-2xx status code".
async function edgeError(error: unknown): Promise<Error> {
  const context = (error as { context?: unknown }).context;
  if (context instanceof Response) {
    try {
      const parsed = await context.clone().json();
      if (parsed && typeof parsed.message === "string") return new Error(parsed.message);
    } catch { /* body was not JSON */ }
  }
  return error instanceof Error ? error : new Error("요청을 처리하지 못했습니다.");
}

async function generateReports(supabase: ReturnType<typeof getSupabase>, studentIds: Id[], start: string, end: string) {
  for (const studentId of studentIds) {
    const { error } = await supabase.functions.invoke("generate-report", { body: { student_id: studentId, period_start: start, period_end: end } });
    if (error) throw await edgeError(error);
  }
}

async function updateReport(supabase: ReturnType<typeof getSupabase>, reportId: Id, values: Partial<Pick<Report, "body" | "status">>) {
  const { error } = await supabase.from("reports").update(values).eq("id", reportId);
  if (error) throw error;
}

async function enqueueReport(supabase: ReturnType<typeof getSupabase>, report: Report, resend: boolean) {
  const { error } = await supabase.functions.invoke("enqueue-report", { body: { report_id: report.id, resend } });
  if (error) throw await edgeError(error);
}

async function savePayment(supabase: ReturnType<typeof getSupabase>, form: PaymentForm) {
  const studentId = Number(form.studentId);
  if (!studentId) throw new Error("학생을 선택하세요.");
  const items = form.items.filter((i) => i.subject.trim() && i.amount.trim()).map((i) => ({ subject: i.subject.trim(), amount: Number(i.amount) }));
  if (items.length === 0) throw new Error("결제 항목이 필요합니다.");
  if (items.some((item) => !Number.isFinite(item.amount))) throw new Error("금액은 숫자로 입력하세요.");
  const { error } = await supabase.rpc("save_payment_with_items", {
    p_payload: {
      payment_id: form.id,
      student_id: studentId,
      paid_on: form.paidOn,
      method: form.method,
      memo: form.memo || null,
      items
    }
  });
  if (error) throw error;
}

async function saveTextbook(supabase: ReturnType<typeof getSupabase>, form: TextbookForm) {
  const payload = {
    subject: form.subject,
    title: form.title.trim(),
    publisher: form.publisher.trim() || null,
    unit_label: form.unitLabel.trim() || "페이지",
    total_units: form.totalUnits ? Number(form.totalUnits) : null,
    aliases: form.aliases.split(",").map((s) => s.trim()).filter(Boolean),
    active: form.active
  };
  if (!payload.title) throw new Error("교재명이 필요합니다.");
  const query = form.id ? supabase.from("textbooks").update(payload).eq("id", form.id) : supabase.from("textbooks").insert(payload);
  const { error } = await query;
  if (error) throw error;
}

async function saveSettings(supabase: ReturnType<typeof getSupabase>, settings: Record<string, string>) {
  const rows = Object.entries(settings).map(([key, value]) => ({ key, value }));
  const { error } = await supabase.from("app_settings").upsert(rows, { onConflict: "key" });
  if (error) throw error;
}

async function deleteRow(supabase: ReturnType<typeof getSupabase>, table: "payments" | "schedule_slots", id: Id) {
  const { error } = await supabase.from(table).delete().eq("id", id);
  if (error) throw error;
}

function todayItems(data: AppData, date: string) {
  const weekday = seoulWeekday(date);
  const scheduled = data.scheduleSlots.flatMap((slot) => {
    if (slot.weekday !== weekday) return [];
    const enrollment = data.enrollments.find((e) => e.id === slot.enrollment_id && e.active);
    const student = enrollment ? findStudent(data, enrollment.student_id) : null;
    if (!enrollment || !student?.active) return [];
    const lesson = data.lessons.find((l) => l.lesson_date === date && l.schedule_slot_id === slot.id);
    return [{
      key: `slot-${slot.id}`,
      studentId: enrollment.student_id,
      subject: enrollment.subject,
      scheduleSlotId: slot.id,
      startTime: slot.start_time,
      lesson,
      status: lesson?.status ?? "waiting"
    }];
  });
  const makeups = data.lessons.filter((l) => l.lesson_date === date && l.schedule_slot_id === null).map((lesson) => ({
    key: `lesson-${lesson.id}`,
    studentId: lesson.student_id,
    subject: lesson.subject,
    scheduleSlotId: null,
    startTime: lesson.started_at,
    lesson,
    status: lesson.status
  }));
  return [...scheduled, ...makeups].sort((a, b) => String(a.startTime ?? "99:99").localeCompare(String(b.startTime ?? "99:99")));
}

function activeAssignments(data: AppData, studentId: Id, subject: Subject | null): StudentTextbook[] {
  return data.studentTextbooks.filter((a) => {
    const tb = textbookFor(data, a.textbook_id);
    return a.student_id === studentId && a.status === "active" && (!subject || tb?.subject === subject);
  });
}

function scheduleForStudent(data: AppData, studentId: Id) {
  return data.scheduleSlots.flatMap((slot) => {
    const enrollment = data.enrollments.find((e) => e.id === slot.enrollment_id && e.student_id === studentId);
    return enrollment ? [{ slot, enrollment }] : [];
  }).sort((a, b) => a.slot.weekday - b.slot.weekday || a.slot.start_time.localeCompare(b.slot.start_time));
}

function subjectsFor(data: AppData, studentId: Id): Subject[] {
  return data.enrollments.filter((e) => e.student_id === studentId && e.active).map((e) => e.subject);
}

function findStudent(data: AppData, id: Id): Student | null {
  return data.students.find((s) => s.id === id) ?? null;
}

function studentName(data: AppData, id: Id): string {
  return findStudent(data, id)?.name ?? "학생";
}

function textbookFor(data: AppData, id: Id): Textbook | null {
  return data.textbooks.find((tb) => tb.id === id) ?? null;
}

function primaryParent(data: AppData, studentId: Id) {
  return data.parents.find((p) => p.student_id === studentId && p.is_primary && p.notify_enabled) ?? null;
}

function paymentTotal(payment: Payment): number {
  return (payment.payment_items ?? []).reduce((sum, item: PaymentItem) => sum + item.amount, 0);
}

function latestOutbox(data: AppData, reportId: Id, status?: NotificationOutbox["status"]) {
  return data.outbox.find((o) => o.report_id === reportId && (!status || o.status === status)) ?? null;
}

function lastProgressSummary(data: AppData, studentId: Id, subject: Subject, beforeDate: string): string {
  const assignments = activeAssignments(data, studentId, subject);
  for (const assignment of assignments) {
    const tb = textbookFor(data, assignment.textbook_id);
    if (assignment.last_position !== null) return `${tb?.title ?? "교재"} ${assignment.last_position}${tb?.unit_label ?? ""}까지`;
  }
  const progress = data.progress.find((p) => {
    const assignment = data.studentTextbooks.find((a) => a.id === p.student_textbook_id && a.student_id === studentId);
    const tb = assignment ? textbookFor(data, assignment.textbook_id) : null;
    const lesson = data.lessons.find((l) => l.id === p.lesson_id);
    return tb?.subject === subject && (!lesson || lesson.lesson_date < beforeDate);
  });
  if (!progress) return "";
  const assignment = data.studentTextbooks.find((a) => a.id === progress.student_textbook_id);
  const tb = assignment ? textbookFor(data, assignment.textbook_id) : null;
  return `${tb?.title ?? "교재"} ${progress.to_value}${tb?.unit_label ?? ""}까지`;
}

function previousLessonSummary(data: AppData, studentId: Id, subject: Subject, beforeDate: string): string {
  const lesson = data.lessons.find((l) => l.student_id === studentId && l.subject === subject && l.lesson_date < beforeDate && l.status === "done");
  if (!lesson) return "";
  const progress = data.progress.filter((p) => p.lesson_id === lesson.id).map((p) => `${p.from_value}→${p.to_value}`).join(", ");
  const comment = data.comments.find((c) => c.lesson_id === lesson.id)?.body;
  return `${lesson.lesson_date}${progress ? ` · ${progress}` : ""}${comment ? ` · ${comment}` : ""}`;
}

function progressMessage(assignment: StudentTextbook, textbook: Textbook | null, toValue: number): string {
  const from = assignment.last_position ?? 0;
  if (toValue <= from) return `이전 진도(${from})보다 낮거나 같습니다. 복습 기록으로 저장할 수 있습니다.`;
  if (textbook?.total_units && toValue >= textbook.total_units) return "저장 시 교재 완료 확인이 표시됩니다.";
  return "";
}

function bridgeWarning(data: AppData): string | null {
  const hours = relativeHours(data.settings.bridge_last_poll_at);
  if (hours === null) return null;
  if (hours > 24) return `동기화 ${Math.round(hours)}시간 전`;
  if (hours > 0.5) return "학원 PC 연결 확인 필요";
  return null;
}

function statusLabel(status: string): string {
  return ({
    waiting: "대기",
    in_progress: "진행",
    done: "완료",
    canceled: "취소",
    draft: "초안",
    ready: "승인",
    sent: "성공",
    pending: "대기",
    processing: "처리중",
    failed: "실패"
  } as Record<string, string>)[status] ?? status;
}

function homeworkStatusLabel(status: Homework["status"]): string {
  return ({ assigned: "미체크", done: "완료", partial: "부분", not_done: "미완료" })[status];
}

function titleFor(view: View, moreView: MoreView, lessonTarget: LessonTarget | null): string {
  if (lessonTarget) return "수업";
  if (view !== "more") return ({ today: "오늘", students: "학생", quick: "빠른입력", reports: "리포트" } as Record<View, string>)[view];
  return ({ menu: "더보기", payments: "수강료", textbooks: "교재", outbox: "발송현황", shortcut: "바로가기", settings: "설정" })[moreView];
}

function onlyNumber(value: string): string {
  return value.replace(/\D/g, "");
}

function optionalNumber(value: string): number | null {
  const numeric = onlyNumber(value);
  return numeric ? Number(numeric) : null;
}

function isSavableParseResult(row: ParseResult): boolean {
  return Boolean(row.ok && row.parsed?.student_id && row.parsed.subject && hasRecordableParseContent(row.parsed));
}

function hasRecordableParseContent(parsed: NonNullable<ParseResult["parsed"]>): boolean {
  return Boolean(
    (parsed.student_textbook_id && parsed.to_value !== null) ||
    parsed.homework?.trim() ||
    parsed.comment?.trim()
  );
}

function orderedRange(fromValue: number, toValue: number): [number, number] {
  return fromValue <= toValue ? [fromValue, toValue] : [toValue, fromValue];
}

function signedNumber(value: string): string {
  return value.replace(/[^\d-]/g, "").replace(/(?!^)-/g, "");
}

function replaceAt<T>(items: T[], index: number, next: T): T[] {
  return items.map((item, i) => i === index ? next : item);
}

function shiftMonth(value: string, diff: number): string {
  const [year, month] = value.split("-").map(Number);
  const date = new Date(year, month - 1 + diff, 1);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function toMessage(error: unknown): string {
  if (!error) return "알 수 없는 오류";
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && "message" in error && typeof error.message === "string") return error.message;
  return JSON.stringify(error);
}

function readStoredState<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  const saved = window.localStorage.getItem(key);
  if (!saved) return fallback;
  try {
    return JSON.parse(saved) as T;
  } catch {
    return fallback;
  }
}

function toLoginMessage(message: string): string {
  const lower = message.toLowerCase();
  if (lower.includes("invalid login credentials")) return "이메일 또는 비밀번호가 맞지 않습니다.";
  if (lower.includes("email not confirmed")) return "이메일 확인이 완료되지 않은 계정입니다.";
  if (lower.includes("rate limit")) return "로그인 시도가 너무 많습니다. 잠시 후 다시 시도하세요.";
  return message;
}
