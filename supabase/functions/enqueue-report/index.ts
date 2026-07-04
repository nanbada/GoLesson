// POST /functions/v1/enqueue-report (docs/05 section 2.3, BR-500s send safety)
// Validates report readiness and the primary parent, snapshots kakao_name, and
// inserts exactly one outbox row per dedupe_key version. The unique constraint
// on dedupe_key is the final race guard -- a concurrent double-tap gets 409.
// No auto-resend here ever (BR-503): a new version requires an explicit
// resend=true from the client, and the report body is sent as-is (immutable).

import {
  errorResponse,
  handleOptions,
  jsonResponse,
  requireActiveTeacher,
  serviceClient,
} from "../_shared/mod.ts";

Deno.serve(async (req) => {
  const opt = handleOptions(req);
  if (opt) return opt;

  const svc = serviceClient();
  const auth = await requireActiveTeacher(req, svc);
  if (auth instanceof Response) return auth;

  let reportId: number, resend: boolean;
  try {
    const body = await req.json();
    reportId = Number(body.report_id);
    resend = body.resend === true;
    if (!reportId) throw new Error("bad");
  } catch {
    return errorResponse(400, "bad_request", "report_id가 필요합니다.");
  }

  // Safety reads below must not degrade DB errors into 404/422/"no rows":
  // a failed read is 500, never a green light or a wrong verdict.
  const { data: report, error: reportErr } = await svc
    .from("reports")
    .select("id, student_id, status, body")
    .eq("id", reportId)
    .maybeSingle();
  if (reportErr) return errorResponse(500, "internal", "리포트 조회에 실패했습니다.");
  if (!report) return errorResponse(404, "report_not_found", "리포트를 찾을 수 없습니다.");

  // Readiness (05 section 2.3): draft is never sendable; sent needs resend=true
  if (report.status === "draft" || !report.body?.trim()) {
    return errorResponse(422, "report_not_ready", "발송 승인(ready)된 리포트만 등록할 수 있습니다.");
  }
  if (report.status === "sent" && !resend) {
    return errorResponse(409, "already_sent", "이미 발송된 리포트입니다. 재발송은 재발송 버튼으로 진행하세요.");
  }

  // Existing queue state: pending/processing always blocks (never queue twice);
  // a prior sent row blocks unless resend; failed rows just bump the version.
  const { data: existing, error: existingErr } = await svc
    .from("notification_outbox")
    .select("id, status, dedupe_key")
    .eq("report_id", reportId);
  if (existingErr) return errorResponse(500, "internal", "발송 이력 조회에 실패했습니다.");
  const rows = existing ?? [];
  if (rows.some((r) => r.status === "pending" || r.status === "processing")) {
    return errorResponse(409, "already_queued", "이미 발송 대기 중입니다.");
  }
  if (!resend && rows.some((r) => r.status === "sent")) {
    return errorResponse(409, "already_sent", "이미 발송된 리포트입니다. 재발송은 재발송 버튼으로 진행하세요.");
  }

  // Primary parent with notifications enabled (05 section 2.3).
  // order(id) makes the pick deterministic if data ever has two primaries
  // (GoAlimi is the master; Bridge sync owns that invariant).
  const { data: parent, error: parentErr } = await svc
    .from("parents")
    .select("id, kakao_name")
    .eq("student_id", report.student_id)
    .eq("is_primary", true)
    .eq("notify_enabled", true)
    .order("id", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (parentErr) return errorResponse(500, "internal", "학부모 조회에 실패했습니다.");
  if (!parent) {
    return errorResponse(422, "recipient_not_found", "알림 수신 가능한 대표 학부모가 없습니다.");
  }

  // Next version from existing dedupe_keys: report:{id}:v{n}
  let maxV = 0;
  for (const r of rows) {
    const m = r.dedupe_key.match(/:v(\d+)$/);
    if (m) maxV = Math.max(maxV, parseInt(m[1]));
  }
  const dedupeKey = `report:${reportId}:v${maxV + 1}`;

  const { data: inserted, error } = await svc
    .from("notification_outbox")
    .insert({
      report_id: reportId,
      student_id: report.student_id,
      kakao_name: parent.kakao_name,
      message: report.body,
      dedupe_key: dedupeKey,
      status: "pending",
    })
    .select("id")
    .single();
  if (error) {
    // 23505 = unique_violation on dedupe_key: concurrent request won the race
    if (error.code === "23505") {
      return errorResponse(409, "already_queued", "이미 발송 대기 중입니다.");
    }
    console.error(`[enqueue-report] insert error: ${error.message}`);
    return errorResponse(500, "internal", "발송 등록에 실패했습니다.");
  }

  console.log(`[enqueue-report] queued report=${reportId} key=${dedupeKey} by=${auth.userId}`);
  return jsonResponse(200, { outbox_id: inserted.id, dedupe_key: dedupeKey });
});
