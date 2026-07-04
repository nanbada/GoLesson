# 2026-07-04 세션 핸드오프 — [3] Edge Functions (parse-batch / generate-report / enqueue-report)

## 완료

- `supabase/functions/_shared/mod.ts` — serviceClient, requireActiveTeacher(JWT→profiles.active), errorResponse, CORS.
- `supabase/functions/parse-batch/index.ts` — docs/07 §1 regex 파서 + AI 폴백(OpenAI structured output, 키 없으면 외부 호출 없이 ai_error). parse_logs 일괄 기록, 줄별 parse_log_id 반환.
- `supabase/functions/generate-report/index.ts` — 통계는 코드 계산(요일 발생수−취소, 진도 from=기간 이전 마지막 to), 본문 90% 템플릿, AI는 과목별 의견 다듬기만(실패 시 "· " 원문 리스트, ai_used=false). draft upsert.
- `supabase/functions/enqueue-report/index.ts` — 발송 안전 게이트: draft/공백본문 422, pending/processing 409, sent는 resend=true만 v2, dedupe_key unique가 최종 경쟁 가드(23505→409), 대표 학부모 kakao_name 스냅샷.
- `supabase/seeds/qa_fixtures_seed.sql` — mvp-seed-data.md 전체, 멱등, 상대날짜. config.toml [db.seed] 등록.
- `supabase/tests/t4-t5-functions.sh` — T4 고정문장 10개 전수 매핑 + T5-1/3/5 + enqueue 계약 전체. **로컬 10/10 통과** (regex 6줄에 AI 미개입을 서버 로그로 증명).
- **원격 배포 완료**: `supabase functions deploy parse-batch generate-report enqueue-report --project-ref dqibhcadjxqmvahcewfn --yes --agent yes`. 원격 함수 3개 모두 `ACTIVE`, `verify_jwt=true`, version=1.
- **원격 smoke 통과**: 임시 teacher auth/profile 생성 후 함수 3개 인증 호출 검증. `parse-batch=200/student_not_found`, `generate-report=404/student_not_found`, `enqueue-report=404/report_not_found`. 임시 auth/profile/parse_logs cleanup 확인(`remote_smoke_users=0`).
- **GitHub push 완료**: `f8cb48d` (`feat: Edge Functions 구현 및 발송 안전 검증 추가`)가 `origin/main`에 반영됨.

## 스펙 수정 결정 (docs 반영됨)

- **07 §1 ⑤ 모순 수정**: regex 성공 = 학생 + (진도 또는 과제). 코멘트만 있는 줄 → AI 폴백. (원 규칙대로면 AI가 영원히 발동 안 함.)
- 숙제 키워드는 독립 토큰만("숙제는" 불인정), 키워드 뒤 숫자범위/단위/별칭/과제유형어(워크북|문제집|프린트)만 소비.

## GoAlimi 변경 정책 완화

- 사용자 추가 결정: GoAlimi(`/Users/nanbada/projects/GoAlimi/`) 변경은 필요 시 가능하나, 기존 기능을 제한/제약하지 않는 범위여야 한다. 현재 1개 학원 사용 중이고 상용 단계가 아니므로 GoLesson 추가 학원 적용에 필요한 호환 변경은 허용한다.
- 반영 위치: `CLAUDE.md`, `AGENTS.md`. GoAlimi 실제 코드 변경은 이 저장소가 아니라 GoAlimi 프로젝트에서 별도 작업한다.

## 이중 검토 결과 (deep-reasoner + Codex 병렬, 상호 비공개)

- deep-reasoner: High 0, Medium 2 (입력 상한, docs/05 에러코드 누락) — 모두 반영.
- Codex: High 3, Medium 3, Low 6. **반영**: ① generate-report draft 경쟁 — status=draft 조건부 UPDATE + 0행이면 새 draft insert(승인본 덮어쓰기 차단, 유일한 실질 발송안전 결함), ② AI 재매칭이 regex 확정 학생 id 우선 + 동명 복수 시 ambiguous_student, ③ 200줄/20,000자 상한 + max_tokens, ④ enqueue 안전 read의 DB 오류 → 500(404/422 오보고 금지), ⑤ 공백 본문 422, 실제 날짜 검증(start≤end), 프롬프트 주입 방어 문구, 대표 학부모 order(id) 결정성.
- **기각(설계 의도, docs/06에 note 기록)**: ready 본문 클라이언트 수정 가능 + draft→ready 클라이언트 전환 — 1인 자기검토 워크플로라 서버 승인 강제는 과설계. sent 이후 불변은 DB 트리거가 담당. failed 재등록은 resend 플래그 불요(BR-503 금지 대상은 *자동* 재발송) — docs/05 §2.3에 명문화.
- 수정 후 하니스 재실행 10/10 통과.

## 미완료 / 다음 세션

1. **다음 의존성**: mvp-build-plan.md [1] GoAlimi API 확장. 2026-07-04 확인 기준 GoAlimi 코드에 `custom_messages`, `/api/notify/custom`, `/api/golesson/*` 구현 흔적 없음.
2. **OpenAI 키 (사용자 작업)**: 로컬 `supabase/functions/.env`(gitignored) + `supabase secrets set OPENAI_API_KEY=...` — 키 설정 후 T4의 AI 2줄(6·10) + T5-2 실검증 필요. 모델 env: OPENAI_MODEL_PARSE(기본 gpt-4.1-nano), OPENAI_MODEL_REPORT(기본 gpt-4.1-mini).
3. 사용자 보류: 강사 4명 초대, GoLesson-old(뭄바이) 삭제, app_settings 운영 seed.
4. 이후 빌드 단계: [1] 완료 후 [4] Bridge. [5] Web PWA는 비발송 화면부터 병행 가능.

## 재사용 정보

- Codex 세션 재개: `codex resume 019f2b61-4af2-7713-9a6f-86c64a45bc1f`
- 로컬 하니스: `./supabase/tests/t4-t5-functions.sh` (로컬 스택 + functions serve 필요, 픽스처는 남기고 테스트 행만 정리)
