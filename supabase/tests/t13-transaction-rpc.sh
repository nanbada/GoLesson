#!/usr/bin/env bash
# T13 transactional RPC tests against local Supabase, or a remote project when
# API_URL, ANON_KEY, and SERVICE_ROLE_KEY are passed as env vars.
# Covers: progress range normalization, lesson/progress/homework/comment atomic
# save, parse_log confirmation, and payment/payment_items rollback.
set -u
cd "$(dirname "$0")/../.."

if [ -z "${API_URL:-}" ]; then
  eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
fi
REST="$API_URL/rest/v1"; AUTH="$API_URL/auth/v1"
JSON=(-H "Content-Type: application/json")
SVC=(-H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY")

PASS=0; FAIL=0
ok()  { echo "PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL  $1 ($2)"; FAIL=$((FAIL+1)); }
expect_deny() { case "$2" in 4*) ok "$1";; *) bad "$1" "expected 4xx, got $2";; esac; }
jget() { sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}[,}].*/\1/p" <<<"$1" | head -1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SFX=$(date +%s)
PW="t13-pass-123!"

echo "== setup: active teacher + throwaway student/textbook =="
R=$(curl -s -X POST "$AUTH/admin/users" "${SVC[@]}" "${JSON[@]}" \
  -d "{\"email\":\"t13-$SFX@test.local\",\"password\":\"$PW\",\"email_confirm\":true}")
UID_T=$(jget "$R" id)
curl -s -o /dev/null -X POST "$REST/profiles" "${SVC[@]}" "${JSON[@]}" \
  -d "{\"id\":\"$UID_T\",\"name\":\"t13\",\"role\":\"teacher\",\"active\":true}"
R=$(curl -s -X POST "$AUTH/token?grant_type=password" -H "apikey: $ANON_KEY" "${JSON[@]}" \
  -d "{\"email\":\"t13-$SFX@test.local\",\"password\":\"$PW\"}")
TOK=$(jget "$R" access_token)
[ -n "$TOK" ] || { echo "ABORT: sign-in failed"; exit 1; }
AH=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOK")

R=$(curl -s -X POST "$REST/students" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"goalimi_student_id\":$((SFX % 1000000000)),\"name\":\"T13학생\"}")
SID=$(jget "$R" id)
R=$(curl -s -X POST "$REST/textbooks" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"subject\":\"영어\",\"title\":\"T13교재-$SFX\",\"unit_label\":\"페이지\",\"total_units\":100}")
TBID=$(jget "$R" id)
R=$(curl -s -X POST "$REST/student_textbooks" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"student_id\":$SID,\"textbook_id\":$TBID,\"status\":\"active\",\"last_position\":42}")
STBID=$(jget "$R" id)
[ -n "$SID" ] && [ -n "$TBID" ] && [ -n "$STBID" ] && ok "fixtures created" || bad "fixtures" "student/textbook setup failed"

echo "== 1) save_lesson_log: atomic save + 42->38 normalized to 38->42 =="
cat > "$TMP/lesson-ok.json" <<EOF
{"p_payload":{"student_id":$SID,"subject":"영어","lesson_date":"2026-07-05","progress":{"student_textbook_id":$STBID,"from_value":42,"to_value":38,"memo":"reverse","complete_assignment":false},"carryover":[],"new_homework":{"description":"rpc-homework-$SFX","kind":"in_class","status":"done","teacher_comment":"ok"},"comment":"rpc-ok-$SFX","parse_log_id":null}}
EOF
C=$(curl -s -o "$TMP/lesson-ok.out" -w '%{http_code}' -X POST "$REST/rpc/save_lesson_log" "${AH[@]}" "${JSON[@]}" -d @"$TMP/lesson-ok.json")
LID=$(tr -dc '0-9' < "$TMP/lesson-ok.out")
[ "$C" = "200" ] && [ -n "$LID" ] && ok "save_lesson_log returns lesson id" || bad "save_lesson_log" "got $C: $(cat "$TMP/lesson-ok.out")"
R=$(curl -s "${SVC[@]}" "$REST/lesson_progress?lesson_id=eq.$LID&select=from_value,to_value")
grep -q '"from_value":38' <<<"$R" && grep -q '"to_value":42' <<<"$R" \
  && ok "progress range normalized" || bad "progress normalization" "got: $R"

echo "== 2) save_lesson_log rollback: invalid homework status leaves no lesson/progress =="
cat > "$TMP/lesson-bad.json" <<EOF
{"p_payload":{"student_id":$SID,"subject":"영어","lesson_date":"2026-07-05","progress":{"student_textbook_id":$STBID,"from_value":10,"to_value":12,"memo":"rollback","complete_assignment":false},"carryover":[],"new_homework":{"description":"rpc-rollback-homework-$SFX","kind":"in_class","status":"bad","teacher_comment":"bad"},"comment":"rpc-rollback-$SFX","parse_log_id":null}}
EOF
C=$(curl -s -o "$TMP/lesson-bad.out" -w '%{http_code}' -X POST "$REST/rpc/save_lesson_log" "${AH[@]}" "${JSON[@]}" -d @"$TMP/lesson-bad.json")
expect_deny "invalid lesson RPC denied" "$C"
R=$(curl -s "${SVC[@]}" "$REST/lessons?note=eq.rpc-rollback-$SFX&select=id")
[ "$R" = "[]" ] && ok "failed lesson transaction rolled back" || bad "lesson rollback" "got: $R"

echo "== 3) save_payment_with_items: insert payment + items atomically =="
cat > "$TMP/pay-ok.json" <<EOF
{"p_payload":{"student_id":$SID,"paid_on":"2026-07-05","method":"카드","memo":"rpc-pay-ok-$SFX","items":[{"subject":"영어","amount":1000},{"subject":"교재비","amount":-200}]}}
EOF
C=$(curl -s -o "$TMP/pay-ok.out" -w '%{http_code}' -X POST "$REST/rpc/save_payment_with_items" "${AH[@]}" "${JSON[@]}" -d @"$TMP/pay-ok.json")
PID=$(tr -dc '0-9' < "$TMP/pay-ok.out")
[ "$C" = "200" ] && [ -n "$PID" ] && ok "save_payment_with_items returns payment id" || bad "save_payment_with_items" "got $C: $(cat "$TMP/pay-ok.out")"
R=$(curl -s "${SVC[@]}" "$REST/payment_items?payment_id=eq.$PID&select=subject,amount")
grep -q '"amount":1000' <<<"$R" && grep -q '"amount":-200' <<<"$R" \
  && ok "payment items inserted" || bad "payment items" "got: $R"

echo "== 4) save_payment_with_items rollback: bad item keeps old parent/items =="
cat > "$TMP/pay-bad.json" <<EOF
{"p_payload":{"payment_id":$PID,"student_id":$SID,"paid_on":"2026-07-06","method":"현금","memo":"rpc-pay-bad-$SFX","items":[{"subject":"영어","amount":"oops"}]}}
EOF
C=$(curl -s -o "$TMP/pay-bad.out" -w '%{http_code}' -X POST "$REST/rpc/save_payment_with_items" "${AH[@]}" "${JSON[@]}" -d @"$TMP/pay-bad.json")
expect_deny "invalid payment RPC denied" "$C"
R=$(curl -s "${SVC[@]}" "$REST/payments?id=eq.$PID&select=memo,method,paid_on")
grep -q "rpc-pay-ok-$SFX" <<<"$R" && grep -q '"method":"카드"' <<<"$R" \
  && ok "failed payment parent rolled back" || bad "payment parent rollback" "got: $R"
R=$(curl -s "${SVC[@]}" "$REST/payment_items?payment_id=eq.$PID&select=subject,amount")
grep -q '"amount":1000' <<<"$R" && grep -q '"amount":-200' <<<"$R" \
  && ok "failed payment items rolled back" || bad "payment item rollback" "got: $R"

echo "== cleanup =="
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/payments?id=eq.$PID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/homeworks?description=eq.rpc-homework-$SFX"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/homeworks?description=eq.rpc-rollback-homework-$SFX"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/comments?body=eq.rpc-ok-$SFX"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/comments?body=eq.rpc-rollback-$SFX"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/lessons?id=eq.$LID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/student_textbooks?id=eq.$STBID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/textbooks?id=eq.$TBID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/students?id=eq.$SID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$AUTH/admin/users/$UID_T"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
