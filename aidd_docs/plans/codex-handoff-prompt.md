# Codex Handoff — GoLesson QA·코드리뷰 최종 상태

GPT Codex 세션 시작 프롬프트로 사용한다. 기본 정책은 저장소 `AGENTS.md`를 따르고, 이 문서는 그 위에 얹는 작업 브리핑이다. 세부 근거는 본문 붙여넣기 대신 파일 포인터로 따른다.

## 역할

필요 시 두 가지만 한다.

1. **검증 보조**: 남은 실기기/운영 PC QA(T1/T2/T3 시간 측정, T5-2 OpenAI, T6 실발송, T8 실동기화, T9 실폰, T11 다기기)를 근거 중심으로 판정한다.
2. **리뷰 보조**: 변경된 코드가 발송안전·RLS/GRANT·정적 PWA 원칙을 깨지 않는지 좁게 리뷰한다.

## 현재 상태 (2026-07-06)

- 운영 Supabase: `dqibhcadjxqmvahcewfn`(ap-northeast-2).
- 공개 env: `NEXT_PUBLIC_SUPABASE_URL` 운영 프로젝트 일치, `NEXT_PUBLIC_SUPABASE_ANON_KEY`에는 publishable key(`sb_publishable_...`) 사용.
- owner profile 1건, `app_settings.academy_name=루트원학원`, QA fixture 멱등 seed 확인.
- Auth "Allow new users to sign up" off.
- typecheck/build/audit 통과.
- 원격 migrations local/remote 일치. `20260705130100_restrict_log_mutation_grants.sql`, `20260705130200_transactional_lesson_payment_rpc.sql` 원격 적용 완료.
- Edge Functions 3개 원격 배포 완료: version 3, ACTIVE, verify_jwt=true.

## 검증 완료

- T4/T5 함수 하니스 원격: `RESULT: 10 passed, 0 failed`.
- T10 접근/RLS 원격: `RESULT: 27 passed, 0 failed`.
- T13 트랜잭션 RPC 원격: `RESULT: 10 passed, 0 failed`.
- T1/T2/T3/T7 핵심 DB 전이 원격 RPC 하니스: `RESULT: 11 passed, 0 failed`.
- T5 리포트 수치·구조: 실데이터 수기대조 일치. T5-2 AI 의견은 OpenAI secret 필요.
- T7 수강료: 2026-06 월합계 600,000원(카드 400,000 / 현금 200,000), audits 전후기록 확인.
- T9/T11 코드레벨: 320px/44px/PWA/offline draft, GoAlimi 새 탭/iframe 0건/다중세션 코드 없음 확인.
- T12 Bridge/GoAlimi 로컬 하니스: T6 Bridge 항목, T8, T12-6~7 통과. 마지막 라인 `PASS Bridge integration harness completed`.
- UX subagent 리뷰 반영: 수업 시작 전 폼 숨김, lesson id 반영, 리포트 본문 저장 후 승인/발송, 빠른입력 빈 숫자 방지, PWA navigation network-first. `npm --prefix web run typecheck`, `npm --prefix web run build`, `git diff --check` 통과.

## 남은 업무

- SSOT는 `aidd_docs/plans/remaining-work.md` 보드다(A 배포 전제 → B 실기기 QA → C Go-Live → D 파일럿).
- 판정/작업 완료 시 보드를 직접 체크 갱신하고 근거를 붙인다.

## 재플래그 금지 이력

- ready 리포트 본문을 `status='ready'`에서 잠그는 트리거를 적용했다가 같은 날 되돌렸다. 사유: `docs/06` BR-506이 ready 본문을 sent 전까지 수정 허용으로 명시한다. 최종 불변 강제는 sent-only다.
- `lesson_progress` update와 `homeworks` delete는 authenticated에서 금지됐다. 복습은 append-only 로그로 허용한다.
- 수업/결제 저장은 `save_lesson_log(jsonb)`, `save_payment_with_items(jsonb)` RPC로 트랜잭션화됐다.
- from/to 역순은 작은 값→큰 값으로 자동 정렬한다.

## 우선 읽을 파일

- `AGENTS.md`
- `aidd_docs/memory/internal/2026-07-06-session-t12-bridge-harness.md`
- `aidd_docs/memory/internal/2026-07-06-session-ux-subagent-review.md`
- `aidd_docs/plans/remaining-work.md` (남은 업무 보드 — 완료 시 체크+근거 갱신)
- `docs/10_ACCEPTANCE_TEST.md`
- `docs/09_DEPLOY.md §4.3`
- `docs/04_DATABASE.md §3, §5`
- `docs/05_API_SPEC.md §2.4, §3`

## 안전

- 커밋/푸시/운영 DB 쓰기는 사용자가 명시 요청할 때만.
- 발송 테스트는 GoAlimi 테스트 계정만: 출결번호 7707 신성화.
- `service_role`, `sb_secret`, OpenAI 키를 채팅·문서·프론트 번들·git에 남기지 않는다.
- `supabase config push` 금지.
- QA fixture 삭제 전 Bridge 중지 또는 GoAlimi 테스트 학생 비활성/삭제가 필요하다.
