#!/usr/bin/env bash
# T4 (parse-batch fixed sentences) + T5-1/3/5 (generate-report) + enqueue-report
# contract tests against the LOCAL stack (docs/10 sections T4/T5, docs/05 section 2).
# Prereq: supabase start; supabase db reset (QA fixtures seeded);
#         supabase functions serve  (running in another terminal).
# AI lines (6,10): with OPENAI_API_KEY in supabase/functions/.env they must parse
# via method=ai; without a key they must fail with ai_error. Either way proves
# the regex path did NOT swallow them and no AI ran for the regex lines.
set -u
cd "$(dirname "$0")/../.."

if [ -z "${API_URL:-}" ]; then
  eval "$(supabase status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
fi
REST="$API_URL/rest/v1"; AUTH="$API_URL/auth/v1"; FN="$API_URL/functions/v1"
JSON=(-H "Content-Type: application/json")
SVC=(-H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY")

PASS=0; FAIL=0
ok()  { echo "PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL  $1 ($2)"; FAIL=$((FAIL+1)); }
jget() { sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}[,}].*/\1/p" <<<"$1" | head -1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

SFX=$(date +%s); PW="t4-pass-123!"
R=$(curl -s -X POST "$AUTH/admin/users" "${SVC[@]}" "${JSON[@]}" \
  -d "{\"email\":\"t4-$SFX@test.local\",\"password\":\"$PW\",\"email_confirm\":true}")
UID_T=$(jget "$R" id)
curl -s -o /dev/null -X POST "$REST/profiles" "${SVC[@]}" "${JSON[@]}" \
  -d "{\"id\":\"$UID_T\",\"name\":\"t4\",\"role\":\"teacher\",\"active\":true}"
R=$(curl -s -X POST "$AUTH/token?grant_type=password" -H "apikey: $ANON_KEY" "${JSON[@]}" \
  -d "{\"email\":\"t4-$SFX@test.local\",\"password\":\"$PW\"}")
TOK=$(jget "$R" access_token)
[ -n "$TOK" ] || { echo "ABORT: sign-in failed"; exit 1; }
TH=(-H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOK")

echo "== T4: parse-batch fixed sentences (docs/10 section 3) =="
# Sentence 9 in docs/10 is "서연 영어" -- the parenthetical is doc annotation.
cat > "$TMP/req.json" <<'EOF'
{"text":"민수 영어 브릭스 38-42 숙제 43~45 독해 좋아짐\n서연 수학 쎈 120~126 계산 실수 잦음\n민수 단어 Day3 완료\n지호 영어 38~42 (복습)\n서연 수학 3단원 숙제 워크북 12-15\n민수 오늘 집중 떨어졌지만 숙제는 열심히 함\n지호 영어 리딩 55까지 숙제 56-58 단어 Day7\n없는학생 영어 10-20\n서연 영어\n민수 수학 개념 이해 좋음 계산 속도 개선 필요"}
EOF
curl -s -X POST "$FN/parse-batch" "${TH[@]}" "${JSON[@]}" -d @"$TMP/req.json" > "$TMP/t4.json"

python3 - "$TMP/t4.json" <<'PY'
import json, sys
rs = {r["line"]: r for r in json.load(open(sys.argv[1]))["results"]}
fails = []
def check(name, cond):
    print(("PY-PASS  " if cond else "PY-FAIL  ") + name)
    if not cond: fails.append(name)
def regex_line(n, name, subj, book, f, t, hw, cm):
    r = rs[n]; p = r.get("parsed") or {}
    check(f"L{n} method=regex ok", r.get("method") == "regex" and r.get("ok"))
    check(f"L{n} fields", p.get("student_name") == name and p.get("subject") == subj
          and p.get("textbook_title") == book and p.get("from_value") == f
          and p.get("to_value") == t and p.get("homework") == hw and p.get("comment") == cm)
regex_line(1, "김민수", "영어", "Bricks Reading 3", 38, 42, "43~45", "독해 좋아짐")
regex_line(2, "이서연", "수학", "쎈 5-1", 120, 126, None, "계산 실수 잦음")
regex_line(3, "김민수", "영어", "보카 트레이닝", 2, 3, None, "완료")
regex_line(4, "박지호", "영어", "리딩 엑스퍼트 1", 38, 42, None, "(복습)")
check("L4 regression warning", "역행" in rs[4].get("warning", ""))
regex_line(5, "이서연", "수학", "디딤돌 수학 4-2", 2, 3, "워크북 12-15", None)
regex_line(7, "박지호", "영어", "리딩 엑스퍼트 1", 50, 55, "56-58 단어 Day7", None)
for n in (6, 10):
    r = rs[n]
    ai_ok = r.get("method") == "ai" and r.get("ok")
    ai_attempted = r.get("error") == "ai_error"
    check(f"L{n} went to AI (not regex)", ai_ok or ai_attempted)
    if ai_ok:
        check(f"L{n} AI re-matched 김민수", (r.get("parsed") or {}).get("student_name") == "김민수")
check("L8 student_not_found + candidates",
      rs[8].get("error") == "student_not_found" and len(rs[8].get("candidates", [])) > 0)
check("L9 textbook_not_found (미수강 과목)", rs[9].get("error") == "textbook_not_found")
check("all lines have parse_log_id", all("parse_log_id" in r for r in rs.values()))
check("regex lines never method=ai", all(rs[n]["method"] == "regex" for n in (1,2,3,4,5,7)))
sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] && ok "T4 assertions" || bad "T4 assertions" "see PY-FAIL above"

echo "== T5: generate-report for 신성화 (2-week window) =="
SHID=$(curl -s "${SVC[@]}" "$REST/students?goalimi_student_id=eq.7707&select=id")
SHID=$(jget "$SHID" id)
PEND=$(date +%F)
PSTART=$(date -v-13d +%F 2>/dev/null || date -d "-13 days" +%F)
gen() { curl -s -X POST "$FN/generate-report" "${TH[@]}" "${JSON[@]}" \
  -d "{\"student_id\":$SHID,\"period_start\":\"$PSTART\",\"period_end\":\"$PEND\"}"; }
R1=$(gen); echo "$R1" > "$TMP/t5.json"
RID=$(jget "$R1" report_id)

python3 - "$TMP/t5.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
fails = []
def check(name, cond):
    print(("PY-PASS  " if cond else "PY-FAIL  ") + name)
    if not cond: fails.append(name)
att = d["stats"]["attendance"]
check("T5-1 attendance scheduled=2 done=2 checkin=2",
      att == {"scheduled": 2, "done": 2, "checkin": 2})
prog = d["stats"]["subjects"].get("영어", {}).get("progress", [])
check("T5-1 progress Bricks 10->28 페이지",
      prog == [{"textbook": "Bricks Reading 3", "unit": "페이지", "from": 10, "to": 28}])
check("T5-1 body header + numbers", "신성화 학습 리포트" in d["body"]
      and "출석: 2회 수업 / 예정 2회" in d["body"] and "10→28페이지" in d["body"])
check("T5-3 no-comment sections omitted", "선생님 의견" not in d["body"])
check("T5 ai_used=false without comments", d["ai_used"] is False)
sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] && ok "T5 stats/body assertions" || bad "T5 assertions" "see PY-FAIL above"

R2=$(gen); RID2=$(jget "$R2" report_id)
[ "$RID" = "$RID2" ] && ok "T5-5 regenerate updates same draft (id=$RID)" \
                     || bad "T5-5 draft dedup" "got $RID then $RID2"

echo "== enqueue-report: send-safety contract (local, no Bridge/GoAlimi) =="
enq() { curl -s -o "$TMP/enq.json" -w '%{http_code}' -X POST "$FN/enqueue-report" \
  "${TH[@]}" "${JSON[@]}" -d "$1"; }
C=$(enq "{\"report_id\":$RID}")
[ "$C" = "422" ] && grep -q report_not_ready "$TMP/enq.json" \
  && ok "draft -> 422 report_not_ready" || bad "draft enqueue" "got $C: $(cat "$TMP/enq.json")"

curl -s -o /dev/null -X PATCH "${TH[@]}" "${JSON[@]}" -d '{"status":"ready"}' "$REST/reports?id=eq.$RID"
C=$(enq "{\"report_id\":$RID}")
DK=$(jget "$(cat "$TMP/enq.json")" dedupe_key)
OBID=$(jget "$(cat "$TMP/enq.json")" outbox_id)
[ "$C" = "200" ] && [ "$DK" = "report:$RID:v1" ] \
  && ok "ready -> 200, dedupe_key v1" || bad "ready enqueue" "got $C key=$DK"
OB=$(curl -s "${SVC[@]}" "$REST/notification_outbox?id=eq.$OBID&select=kakao_name,status,message")
grep -q '"kakao_name":"신성화"' <<<"$OB" && grep -q '"status":"pending"' <<<"$OB" \
  && ok "outbox row: kakao_name snapshot + pending" || bad "outbox row" "got: $OB"

C=$(enq "{\"report_id\":$RID}")
[ "$C" = "409" ] && ok "double-tap -> 409" || bad "double-tap" "got $C: $(cat "$TMP/enq.json")"

# Simulate Bridge completing the send, then test the resend path (v2)
curl -s -o /dev/null -X PATCH "${SVC[@]}" "${JSON[@]}" \
  -d "{\"status\":\"sent\",\"sent_at\":\"$(date +%FT%T)+09:00\"}" "$REST/notification_outbox?id=eq.$OBID"
curl -s -o /dev/null -X PATCH "${SVC[@]}" "${JSON[@]}" \
  -d "{\"status\":\"sent\",\"sent_at\":\"$(date +%FT%T)+09:00\"}" "$REST/reports?id=eq.$RID"
C=$(enq "{\"report_id\":$RID}")
[ "$C" = "409" ] && ok "sent without resend -> 409" || bad "sent no-resend" "got $C"
C=$(enq "{\"report_id\":$RID,\"resend\":true}")
DK=$(jget "$(cat "$TMP/enq.json")" dedupe_key)
OBID2=$(jget "$(cat "$TMP/enq.json")" outbox_id)
[ "$C" = "200" ] && [ "$DK" = "report:$RID:v2" ] \
  && ok "resend -> 200, dedupe_key v2" || bad "resend" "got $C key=$DK"

# recipient_not_found: throwaway student without a primary parent
R=$(curl -s -X POST "$REST/students" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"goalimi_student_id\":$((SFX % 1000000000)),\"name\":\"T4수신자없음\"}")
XSID=$(jget "$R" id)
R=$(curl -s -X POST "$REST/reports" "${SVC[@]}" "${JSON[@]}" -H "Prefer: return=representation" \
  -d "{\"student_id\":$XSID,\"period_start\":\"$PSTART\",\"period_end\":\"$PEND\",\"body\":\"t\",\"status\":\"ready\"}")
XRID=$(jget "$R" id)
C=$(enq "{\"report_id\":$XRID}")
[ "$C" = "422" ] && grep -q recipient_not_found "$TMP/enq.json" \
  && ok "no primary parent -> 422 recipient_not_found" || bad "recipient" "got $C: $(cat "$TMP/enq.json")"

echo "== cleanup (fixtures stay; only test-created rows) =="
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/notification_outbox?report_id=eq.$RID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/reports?id=in.($RID,$XRID)"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/students?id=eq.$XSID"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$REST/parse_logs?created_by=eq.$UID_T"
curl -s -o /dev/null -X DELETE "${SVC[@]}" "$AUTH/admin/users/$UID_T"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
