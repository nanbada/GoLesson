# 05. API SPEC — 접근 경로와 계약

## 1. 접근 경로 원칙

| 주체 | 경로 | 인증 |
|---|---|---|
| 프론트(PWA) CRUD | supabase-js 직접 (RLS) | Supabase Auth 세션 |
| 프론트 → 서버 로직 | Supabase **Edge Functions** 3개 | Auth JWT |
| Bridge(학원 PC) | Supabase REST(PostgREST) | `service_role` 키 |
| Bridge → GoAlimi | localhost HTTP | 없음 (같은 PC, 08_GOALIMI) |

Next.js API Route는 사용하지 않는다 (프론트 정적 유지 — 호스팅 교체 자유).
일반 CRUD(학생 조회, 진도/과제/결제 저장 등)는 별도 API 없이 supabase-js + RLS로 처리한다.

## 2. Edge Functions

### 2.1 POST /functions/v1/parse-batch (REQ-501~508)

정형 줄은 서버 regex로, 실패 줄만 AI로 파싱. 07_AI_SPEC 참조.

```jsonc
// Request
{ "text": "민수 영어 브릭스 38-42 숙제 43~45 독해 좋아짐\n서연 수학 쎈 3단원 ..." }

// Response 200
{ "results": [
  { "line": 1, "raw": "민수 영어 ...", "method": "regex", "ok": true,
    "parse_log_id": 142,
    "parsed": {
      "student_id": 12, "student_name": "김민수",
      "subject": "영어",
      "student_textbook_id": 3, "textbook_title": "Bricks Reading",
      "from_value": 38, "to_value": 42,
      "homework": "43~45", "comment": "독해 좋아짐"
    } },
  { "line": 2, "raw": "...", "method": "ai", "ok": false,
    "parse_log_id": 143,
    "error": "student_not_found", "candidates": [ ... ] }
] }
```

- 저장은 하지 않는다. 확정 저장은 프론트가 supabase-js로 수행(미리보기 원칙, REQ-504).
- 각 줄을 parse_logs에 기록(status=parsed/failed, created_by=요청자). 프론트가 저장 성공 시 status를 confirmed로 갱신 — 이를 위해 parse_logs는 `update(status)` 컬럼 GRANT + 본인 행(created_by=auth.uid()) RLS만 예외 허용한다 (04 §5 5-1). 응답에 각 줄의 parse_log_id를 포함해 프론트가 이를 참조할 수 있도록 함.
- 각 결과에는 warning 필드(예: 역행 경고 "역행: 42→38")와 AI 결과의 confidence("high"|"low") 필드가 있을 수 있음.
- 오류 코드: `student_not_found` `textbook_not_found` `ambiguous_student` `no_progress_found` `ai_error`.
- 400 bad_request: "200줄/20,000자 초과" 또는 text 필드 누락.

### 2.2 POST /functions/v1/generate-report (REQ-601~603, 607)

```jsonc
// Request
{ "student_id": 12, "period_start": "2026-06-20", "period_end": "2026-07-03" }

// Response 200
{ "report_id": 45, "stats": { /* 07_AI_SPEC §4 스키마 */ }, "body": "…초안 전문…" }
```

- 동작: 기간 통계 SQL 집계 → 템플릿 본문 생성 → 코멘트 존재 시 AI로 과목별 의견 문단 생성 → reports(draft) insert.
- AI 실패 시: 의견 자리에 원본 코멘트를 그대로 나열하고 `"ai_used": false` 반환 (생성 자체는 성공, REQ-506 준용).
- 같은 학생·기간의 draft가 이미 있으면 새로 만들지 않고 기존 draft 갱신: 갱신은 `status=draft` 조건부 UPDATE만 수행한다. 생성 도중 강사가 ready로 승인한 경우 승인본을 덮어쓰지 않고 새 draft를 insert한다 (race guard).
- 오류 코드: `student_not_found` (404), `ai_error`, `bad_request` (400: 날짜 형식 오류·존재하지 않는 날짜·start > end).

### 2.3 POST /functions/v1/enqueue-report (REQ-701, 704, 707)

```jsonc
// Request
{ "report_id": 45 }
// Response 200
{ "outbox_id": 101, "dedupe_key": "report:45:v1" }
// Response 409: 이미 발송 대기/완료 (재발송은 클라이언트가 재발송 의사 명시 → v2 키 발급)
// Response 422: recipient_not_found (대표 학부모 없음/notify_disabled) | report_not_ready
```

- 검증: report.status=ready → 대표 학부모 조회 → kakao_name 스냅샷 → outbox insert → report와 연결.
- 오류 코드: `report_not_found` (404), `report_not_ready` (422: draft 또는 본문 공백), `already_sent` (409: sent 상태이고 resend=true 아님), `already_queued` (409: pending/processing 존재), `recipient_not_found` (422: 대표 학부모 없음/notify_disabled), `internal` (500: DB 조회 실패 시 안전 판단용 — 404/422로 오보고하지 않음).
- 재발송 정책: `{ "report_id": 45, "resend": true }` → dedupe_key 버전 증가(`v2`). **failed 상태의 이전 outbox 행도 resend 플래그 없이 재등록 가능하며 버전만 증가한다**(v2, v3…) — 이는 사람이 [발송] 버튼을 다시 누르는 정상 복구 경로다. BR-503의 금지 대상은 자동 재발송이며 이 경로는 해당하지 않는다.

## 3. Bridge ↔ Supabase 계약 (service_role)

Bridge는 PostgREST를 직접 호출한다. 발송 트랜잭션 순서가 핵심:

```
1. POST /rest/v1/rpc/claim_outbox  body: {"p_limit": 5}
   → pending을 원자적으로 processing 전환 + attempts 증가 (04_DATABASE §3 RPC.
     PostgREST PATCH로는 attempts 증가 같은 연산이 불가하므로 RPC 필수)
2. GoAlimi POST /api/notify/custom  (08_GOALIMI §3)
   → 응답 id를 즉시 outbox.goalimi_custom_id에 PATCH 저장 (crash 회수용 — 아래)
   → 422 no_primary_parent는 접수 자체가 거절된 것(GoAlimi에 행 없음)
     → outbox {status:'failed', error:'no_primary_parent'} 즉시 종결
3. GoAlimi 상태 폴링 → GoAlimi status는 pending|sending|sent|failed.
   pending·sending은 비종결 — 다음 주기 계속 폴링. 종결 시:
   PATCH {status:'sent', sent_at} 또는 {status:'failed', error}
   sent이고 report_id 있으면 reports도 {status:'sent', sent_at} 갱신
   ※ 실패 상태는 outbox만 갖는다 — reports.status에 failed 없음(04 §2 reports 주석)
   ※ failed 중 error='timeout'|'interrupted'는 "발송 여부 불확실" —
     실제로는 학부모에게 도달했을 수 있다. UI는 이 두 코드에
     "수신 확인 후 재발송" 안내를 표시하고, 재발송은 원장이 확인 후
     새 dedupe_key(…:v2)로만 한다 (BR-503 자동 재발송 금지).
   ※ 그 외 실패 코드(focus_not_acquired·room_mismatch·out_of_hours·
     no_primary_parent·precheck_failed 등)는 키 입력 전 확정 실패 —
     발송되지 않은 것이 확실하므로 새 dedupe_key 재발송이 즉시 안전하다.
```

- **stale processing 회수 (이중발송 방지)**: processing 10분 초과 행을 임의로 failed 처리하지 않는다 — GoAlimi에 이미 접수된 뒤 Bridge가 죽었을 수 있고, failed→재전송이 중복 발송이 된다. Bridge는 기동 시와 매 주기에 stale 행을 다음 절차로만 종결한다:
  1. `goalimi_custom_id` 있음 → `GET /api/notify/custom/{id}` 상태 조회 → sent/failed/pending 그대로 반영
  2. 없음(POST 전 crash) → `POST /api/notify/custom` 재호출 — dedupe_key 멱등이므로 기존 접수가 있으면 그 행이 반환됨 → id 저장 후 1번 절차. **재POST는 절대 재발송을 일으키지 않는다** — GoAlimi는 기존 행 반환만 하고 재큐잉하지 않으며, GoAlimi측 큐 유실 복구는 GoAlimi 재기동 스캔이 전담한다(08 §3.2).
  3. 어느 쪽도 실패(GoAlimi 다운)하면 processing 유지, 다음 주기 재시도. 'bridge_interrupted' 같은 임의 failed 전환 금지.
- 동기화 계약 (10분 주기) — **GoAlimi 기존 API는 이 용도에 부족**(`/api/students`는 active만 반환, parents 목록·attendance since_id 조회 없음). 08_GOALIMI §3.3의 GoLesson 전용 read API 3개를 사용한다:
  - students: `GET /api/golesson/students` (비활성 포함) → upsert on goalimi_student_id (name/grade/school/active/synced_at)
  - parents: `GET /api/golesson/parents` → upsert on goalimi_parent_id
  - attendance: `GET /api/golesson/attendance?since_id=` 증분 → insert (goalimi_log_id unique로 멱등)
- 출결 삭제 대사 (매일 1회): GoAlimi는 출결 hard delete가 가능하므로 증분 복사만으로는 삭제가 반영되지 않는다. 최근 30일 goalimi_log_id 집합을 대조해 GoAlimi에 없는 행을 GoLesson에서도 삭제 (리포트 출석 수치 정합성).
- 백업 계약 (매일 03시): 전 테이블 `GET …?select=*` → `backup/YYYY-MM-DD/*.json` 저장, 30일 보관.

## 4. 오류 공통 형식

Edge Functions 오류 응답: `{ "error": "<code>", "message": "<사람용 설명>" }` + 적절한 HTTP 상태.
프론트는 code 기준 분기, message는 그대로 토스트 표시.
