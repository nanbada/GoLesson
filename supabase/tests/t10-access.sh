#!/usr/bin/env bash
# T10 access tests (docs/10_ACCEPTANCE_TEST.md) against local Supabase, or a
# remote project when API_URL, ANON_KEY, and SERVICE_ROLE_KEY are passed as env
# vars.
# Covers: anon blocked / group-A write denial / append-only progress + homework
# delete denial / parse_logs row+column exception / sent-report immutability
# trigger / inactive profile blocked / claim_outbox service_role-only / no
# service key in git.
# Local run: needs a running local stack (supabase start); keys are read from
# `supabase status`. Remote run: pass API_URL, ANON_KEY, SERVICE_ROLE_KEY as env
# vars (docs/09 section 4.1 step 3). Creates throwaway auth users and rows via
# service_role and removes them at the end.
set -u
cd "$(dirname "$0")/../.."

if [ -z "${API_URL:-}" ]; then
  eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
fi
REST="$API_URL/rest/v1"; AUTH="$API_URL/auth/v1"
JSON=(-H "Content-Type: application/json")
SVC=(-H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY")

PASS=0; FAIL=0
ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1 ($2)"; FAIL=$((FAIL+1)); }
# expect_deny <name> <http_code>: any 4xx counts as denied
expect_deny() { case "$2" in 4*) ok "$1";; *) bad "$1" "expected 4xx, got $2";; esac; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
jget() { sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}[,}].*/\1/p" <<<"$1" | head -1; }

SFX=$(date +%s)
PW="t10-pass-123!"

mkuser() { # $1 email  $2 active(true|false)  -> USER_ID, USER_TOKEN
  local r; r=$(curl -s -X POST "$AUTH/admin/users" "${SVC[@]}" "${JSON[@]}" \
    -d "{\"email\":\"$1\",\"password\":\"$PW\",\"email_confirm\":true}")
  USER_ID=$(jget "$r" id)
  curl -s -o /dev/null -X POST "$REST/profiles" "${SVC[@]}" "${JSON[@]}" \
    -d "{\"id\":\"$USER_ID\",\"name\":\"t10\",\"role\":\"teacher\",\"active\":$2}"
  r=$(curl -s -X POST "$AUTH/token?grant_type=password" -H "apikey: $ANON_KEY" "${JSON[@]}" \
    -d "{\"email\":\"$1\",\"password\":\"$PW\"}")
  USER_TOKEN=$(jget "$r" access_token)
  [ -n "$USER_TOKEN" ] || { echo "ABORT: could not sign in $1"; exit 1; }
}

echo "== setup: users A(active) B(inactive) C(active), fixture rows =="
mkuser "t10-a-$SFX@test.local" true;  A_ID=$USER_ID; A_TOK=$USER_TOKEN
mkuser "t10-b-$SFX@test.local" false; B_ID=$USER_ID; B_TOK=$USER_TOKEN
mkuser "t10-c-$SFX@test.local" true;  C_ID=$USER_ID; C_TOK=$USER_TOKEN
AH=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $A_TOK")
BH=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $B_TOK")
CH=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $C_TOK")
NH=(-H "apikey: $ANON_KEY")

R=$(curl -s -X POST "$REST/students" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"goalimi_student_id\":$((SFX % 1000000000)),\"name\":\"T10학생\"}")
SID=$(jget "$R" id)
[ -n "$SID" ] || { echo "ABORT: student fixture insert failed: $R"; exit 1; }

echo "== 1) anon: REST fully blocked =="
expect_deny "anon select students"      "$(code "${NH[@]}" "$REST/students")"
expect_deny "anon select app_settings"  "$(code "${NH[@]}" "$REST/app_settings")"
expect_deny "anon rpc claim_outbox"     "$(code -X POST "${NH[@]}" "${JSON[@]}" -d '{}' "$REST/rpc/claim_outbox")"

echo "== 2) group A (students/parents/attendance): authenticated writes denied =="
expect_deny "auth insert students"   "$(code -X POST "${AH[@]}" "${JSON[@]}" -d '{"goalimi_student_id":1,"name":"x"}' "$REST/students")"
expect_deny "auth update students"   "$(code -X PATCH "${AH[@]}" "${JSON[@]}" -d '{"name":"x"}' "$REST/students?id=eq.$SID")"
expect_deny "auth insert parents"    "$(code -X POST "${AH[@]}" "${JSON[@]}" -d "{\"goalimi_parent_id\":1,\"student_id\":$SID,\"kakao_name\":\"x\"}" "$REST/parents")"
expect_deny "auth insert attendance" "$(code -X POST "${AH[@]}" "${JSON[@]}" -d "{\"goalimi_log_id\":1,\"student_id\":$SID,\"event_type\":\"IN\",\"event_at\":\"2026-07-04T10:00:00+09:00\"}" "$REST/attendance")"
expect_deny "auth delete students"   "$(code -X DELETE "${AH[@]}" "$REST/students?id=eq.$SID")"

echo "== 2b) log mutation boundaries: progress append-only, homework no hard delete =="
R=$(curl -s -X POST "$REST/textbooks" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"subject\":\"영어\",\"title\":\"T10교재-$SFX\",\"unit_label\":\"페이지\"}")
TBID=$(jget "$R" id)
R=$(curl -s -X POST "$REST/student_textbooks" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"student_id\":$SID,\"textbook_id\":$TBID,\"status\":\"active\"}")
STBID=$(jget "$R" id)
R=$(curl -s -X POST "$REST/lessons" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"student_id\":$SID,\"subject\":\"영어\",\"lesson_date\":\"2026-07-04\",\"status\":\"done\"}")
LID=$(jget "$R" id)
R=$(curl -s -X POST "$REST/lesson_progress" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"lesson_id\":$LID,\"student_textbook_id\":$STBID,\"from_value\":1,\"to_value\":2}")
PRID=$(jget "$R" id)
expect_deny "auth update lesson_progress denied" \
  "$(code -X PATCH "${AH[@]}" "${JSON[@]}" -d '{"to_value":99}' "$REST/lesson_progress?id=eq.$PRID")"
R=$(curl -s -X POST "$REST/homeworks" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"student_id\":$SID,\"assigned_lesson_id\":$LID,\"subject\":\"영어\",\"description\":\"T10과제\",\"kind\":\"take_home\",\"status\":\"assigned\"}")
HWID=$(jget "$R" id)
C=$(code -X PATCH "${AH[@]}" "${JSON[@]}" -d '{"status":"done"}' "$REST/homeworks?id=eq.$HWID")
[ "$C" = "204" ] && ok "auth update homeworks still allowed" || bad "auth update homeworks" "got $C"
expect_deny "auth delete homeworks denied" \
  "$(code -X DELETE "${AH[@]}" "$REST/homeworks?id=eq.$HWID")"

echo "== 3) parse_logs: own-row, status-column-only update =="
R=$(curl -s -X POST "$REST/parse_logs" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"raw_text\":\"t10\",\"created_by\":\"$A_ID\"}")
PLID=$(jget "$R" id)
R=$(curl -s -X PATCH "${CH[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d '{"status":"confirmed"}' "$REST/parse_logs?id=eq.$PLID")
[ "$R" = "[]" ] && ok "other user's row: 0 rows updated" || bad "other user's row" "got: $R"
expect_deny "own row, non-status column" \
  "$(code -X PATCH "${AH[@]}" "${JSON[@]}" -d '{"raw_text":"hack"}' "$REST/parse_logs?id=eq.$PLID")"
R=$(curl -s -X PATCH "${AH[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d '{"status":"confirmed"}' "$REST/parse_logs?id=eq.$PLID")
grep -q '"status":"confirmed"' <<<"$R" && ok "own row status -> confirmed" || bad "own row status" "got: $R"

echo "== 4) sent report immutability (trigger) =="
R=$(curl -s -X POST "$REST/reports" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"student_id\":$SID,\"period_start\":\"2026-06-01\",\"period_end\":\"2026-06-30\",\"body\":\"v1\"}")
RID=$(jget "$R" id)
curl -s -o /dev/null -X PATCH "${SVC[@]}" "${JSON[@]}" -d '{"status":"ready"}' "$REST/reports?id=eq.$RID"
C=$(code -X PATCH "${SVC[@]}" "${JSON[@]}" -d '{"status":"sent","sent_at":"2026-07-04T12:00:00+09:00"}' "$REST/reports?id=eq.$RID")
[ "$C" = "204" ] && ok "ready->sent transition allowed" || bad "ready->sent" "got $C"
R=$(curl -s -X PATCH "${SVC[@]}" "${JSON[@]}" -d '{"body":"v2"}' "$REST/reports?id=eq.$RID")
grep -q "immutable" <<<"$R" && ok "service_role: sent body update blocked" || bad "service_role sent body" "got: $R"
R=$(curl -s -X PATCH "${SVC[@]}" "${JSON[@]}" -d '{"sent_at":"2027-01-01T00:00:00+09:00"}' "$REST/reports?id=eq.$RID")
grep -q "immutable" <<<"$R" && ok "service_role: sent_at tamper blocked" || bad "sent_at tamper" "got: $R"
R=$(curl -s -X PATCH "${AH[@]}" "${JSON[@]}" -H "Prefer: return=representation" -d '{"body":"v2"}' "$REST/reports?id=eq.$RID")
[ "$R" = "[]" ] && ok "authenticated: sent report filtered by RLS (0 rows)" || bad "auth sent body" "got: $R"

echo "== 4b) reports status: client limited to draft/ready (sent = Bridge only) =="
R=$(curl -s -X POST "$REST/reports" "${AH[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"student_id\":$SID,\"period_start\":\"2026-06-01\",\"period_end\":\"2026-06-30\"}")
RID2=$(jget "$R" id)
[ -n "$RID2" ] && ok "auth insert draft report" || bad "auth insert draft" "got: $R"
C=$(code -X PATCH "${AH[@]}" "${JSON[@]}" -d '{"status":"ready"}' "$REST/reports?id=eq.$RID2")
[ "$C" = "204" ] && ok "auth draft->ready allowed" || bad "draft->ready" "got $C"
expect_deny "auth ready->sent denied" \
  "$(code -X PATCH "${AH[@]}" "${JSON[@]}" -d '{"status":"sent"}' "$REST/reports?id=eq.$RID2")"
expect_deny "auth insert with status=sent denied" \
  "$(code -X POST "${AH[@]}" "${JSON[@]}" -d "{\"student_id\":$SID,\"period_start\":\"2026-06-01\",\"period_end\":\"2026-06-30\",\"status\":\"sent\"}" "$REST/reports")"

echo "== 5) inactive profile: no data access =="
R=$(curl -s "${BH[@]}" "$REST/students?select=id")
[ "$R" = "[]" ] && ok "inactive: students empty" || bad "inactive students" "got: $R"
R=$(curl -s "${BH[@]}" "$REST/profiles?select=id")
if grep -q "$B_ID" <<<"$R" && ! grep -q "$A_ID" <<<"$R"; then
  ok "inactive: sees only own profile row"
else bad "inactive profiles" "got: $R"; fi

echo "== 6) claim_outbox: service_role only =="
expect_deny "authenticated rpc denied" \
  "$(code -X POST "${AH[@]}" "${JSON[@]}" -d '{}' "$REST/rpc/claim_outbox")"
curl -s -o /dev/null -X POST "$REST/notification_outbox" "${SVC[@]}" "${JSON[@]}" \
  -d "{\"student_id\":$SID,\"kakao_name\":\"테스트\",\"message\":\"t10\",\"dedupe_key\":\"report:t10:$SFX\"}"
R=$(curl -s -X POST "${SVC[@]}" "${JSON[@]}" -d '{"p_limit":5}' "$REST/rpc/claim_outbox")
if grep -q '"status":"processing"' <<<"$R" && grep -q '"attempts":1' <<<"$R"; then
  ok "service_role claim: processing + attempts=1"
else bad "service_role claim" "got: $R"; fi

echo "== 7) no service key in git-tracked files =="
if git grep -IhoE 'eyJ[A-Za-z0-9_-]{30,}\.[A-Za-z0-9_-]{20,}' -- . >/dev/null 2>&1; then
  bad "git tracked files" "JWT-like string found (git grep eyJ...)"
else ok "no JWT-like secret in tracked files"; fi

echo "== cleanup: remove throwaway rows and users =="
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/notification_outbox?dedupe_key=eq.report:t10:$SFX"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/reports?id=in.($RID,$RID2)"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/parse_logs?id=eq.$PLID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/homeworks?id=eq.$HWID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/lesson_progress?id=eq.$PRID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/lessons?id=eq.$LID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/student_textbooks?id=eq.$STBID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/textbooks?id=eq.$TBID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/students?id=eq.$SID"
for u in $A_ID $B_ID $C_ID; do
  curl -s -o /dev/null -X DELETE "${SVC[@]}" "$AUTH/admin/users/$u"   # cascades to profiles
done

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
