# 2026-07-05 프로젝트 코드리뷰/QA 핸드오프

후속 상태(2026-07-06): 이 문서의 T12 하니스 blocked 기록은 해소됐다. Python 3.12 임시 venv와 `greenlet` 임시 설치로 `bridge.tests.integration_bridge`가 통과했으며, 최신 상태는 `aidd_docs/memory/internal/2026-07-06-session-t12-bridge-harness.md`를 우선한다.

## 변경

- `supabase/functions/generate-report/index.ts`
  - 학생, 수강권, 수업, 출결, 설정, 수업 슬롯, 진도, 숙제, 코멘트, 이전 진도, 기존 리포트 조회 오류를 무시하지 않고 즉시 실패하도록 수정.
  - 리포트가 부분 데이터나 0건 통계로 조용히 생성되는 위험 제거.
- `bridge/bridge.py`
  - Supabase REST `select_all()`에 `Range` 페이지네이션 추가.
  - 백업이 PostgREST 기본 `max_rows=1000`에서 조용히 잘리는 문제 수정.
  - GoAlimi 부모 목록에서 사라진 보호자를 GoLesson Bridge 사본에서도 삭제하도록 수정.
- `bridge/tests/test_bridge.py`
  - Range 헤더 기반 페이지네이션 더미 데이터 테스트 추가.
  - GoAlimi에서 누락된 보호자 로컬 삭제 테스트 추가.
- `supabase/migrations/20260705130100_restrict_log_mutation_grants.sql`
  - `lesson_progress` authenticated update 권한/정책 제거.
  - `homeworks` authenticated delete 권한/정책 제거.
- `docs/04_DATABASE.md`, `docs/10_ACCEPTANCE_TEST.md`, `supabase/tests/t10-access.sh`
  - 진도 로그 수정 금지, 숙제 하드 삭제 금지 규칙을 문서와 접근 테스트에 반영.
  - T10 접근 테스트가 throwaway 교재/학생교재/수업/진도/숙제 데이터를 직접 주입하고 정리하도록 보강.

## 검증

- `npm --prefix web run typecheck` 통과.
- `npm --prefix web run build` 통과.
- `npm --prefix web audit --omit=dev` 결과 `found 0 vulnerabilities`.
- `python3 -B -m unittest bridge.tests.test_bridge` 결과 `Ran 9 tests ... OK`.
- `bash -n supabase/tests/t10-access.sh supabase/tests/t4-t5-functions.sh` 통과.
- `git diff --check` 통과.
- `supabase migration up --local`로 로컬 DB에 `20260705130100_restrict_log_mutation_grants.sql` 적용.
- `./supabase/tests/t10-access.sh` 결과 `RESULT: 27 passed, 0 failed`.
- `/tmp`에서 `DENO_DIR=/tmp/golesson-deno-cache deno check --node-modules-dir=auto`로 `parse-batch`, `enqueue-report`, `generate-report` 통과.
- tracked secret 점검: `.env`, `.env.*`, `bridge_config.json`은 gitignore 대상이고 tracked 설정 파일에 실제 비밀키 없음.

## 남은 이슈

- 수동 QA 미완료: T1/T2/T3 전체 시나리오, T5-2 OpenAI fallback, T9/T11 실제 GoAlimi/카톡/작업스케줄러/백업 복구 검증.
- 원격 Supabase에는 새 마이그레이션을 배포하지 않았다.

## 추가 진행: P1/P2 반영

- 사용자 결정: 복습 기록은 가능하며, from/to 역순은 작은 값→큰 값으로 자동 정렬한다.
- `supabase/migrations/20260705130200_transactional_lesson_payment_rpc.sql`
  - `trg_normalize_progress_range()` 추가: `lesson_progress` insert/update 전 from/to를 정렬.
  - `save_lesson_log(p_payload jsonb)` 추가: lesson/progress/homework/comment/parse_log 확정을 한 트랜잭션으로 처리. SECURITY INVOKER 유지.
  - `save_payment_with_items(p_payload jsonb)` 추가: payment insert/update와 payment_items 교체를 한 트랜잭션으로 처리. SECURITY INVOKER 유지.
- `web/app/page.tsx`
  - 수업 저장, 빠른입력 저장, 수강료 저장을 RPC 호출로 전환.
  - 수업 화면과 빠른입력 저장 전에 `orderedRange()`로 from/to 정렬.
  - 완료 교재 확인 결과를 RPC payload에 포함해 진도 저장과 완료 처리를 같은 트랜잭션으로 묶음.
- `supabase/functions/parse-batch/index.ts`
  - regex/AI fallback 모두 from/to 역순을 정렬해서 반환.
  - 단일값 복습 입력은 입력한 to 기준으로 역행 경고 유지.
- `supabase/tests/t13-transaction-rpc.sh`
  - throwaway 학생/교재/결제 데이터를 주입하고 정리.
  - 진도 정렬, lesson RPC 롤백, payment RPC 롤백을 검증.
- 문서 갱신: `docs/04_DATABASE.md`, `docs/05_API_SPEC.md`, `docs/06_BUSINESS_RULE.md`, `docs/07_AI_SPEC.md`, `docs/10_ACCEPTANCE_TEST.md`, `aidd_docs/plans/mvp-build-plan.md`.

## 추가 검증

- `supabase migration up --local`로 `20260705130200_transactional_lesson_payment_rpc.sql` 적용.
- `./supabase/tests/t10-access.sh` 결과 `RESULT: 27 passed, 0 failed`.
- `./supabase/tests/t13-transaction-rpc.sh` 결과 `RESULT: 10 passed, 0 failed`.
- `npm --prefix web run typecheck` 통과.
- `npm --prefix web run build` 통과.
- `python3 -B -m unittest bridge.tests.test_bridge` 결과 `Ran 9 tests ... OK`.
- `DENO_DIR=/tmp/golesson-deno-cache deno check --node-modules-dir=auto`로 `parse-batch`, `generate-report`, `enqueue-report` 통과.
- `git diff --check` 통과.

## 추가 진행: 원격 배포와 QA

- `supabase migration fetch --linked`로 원격에만 있던 `20260705070940_reports_ready_body_immutable.sql`, `20260705075105_revert_ready_body_immutable.sql` 회수.
  - fetch가 기존 4개 migration 파일을 formatting 변경했으나 배포에 불필요해 복구함.
- `supabase db push --linked --yes`로 원격 적용:
  - `20260705120000_reports_ready_body_immutable.sql`
  - `20260705130000_revert_ready_body_immutable.sql`
  - `20260705130100_restrict_log_mutation_grants.sql`
  - `20260705130200_transactional_lesson_payment_rpc.sql`
- push 끝에 pg-delta catalog cache 경고가 있었지만 exit 0이며 `supabase migration list --linked`에서 local/remote 일치 확인.
- Edge Functions도 원격 배포:
  - `supabase functions deploy parse-batch generate-report enqueue-report --use-api`
  - `supabase functions list`에서 세 함수 모두 version 3, ACTIVE, verify_jwt=true 확인.
- 원격 QA fixture drift 보정:
  - 박지호(9003) 리딩 교재 배정을 active/last_position=50으로 복구.
  - 신성화(7707) 추가 수강/스케줄/비QA lesson/comment를 QA 고정 시나리오에 맞게 정리.
  - `supabase/seeds/qa_fixtures_seed.sql` 원격 재실행.
- 원격 자동 QA 결과:
  - `./supabase/tests/t10-access.sh` 원격: `RESULT: 27 passed, 0 failed`.
  - `./supabase/tests/t13-transaction-rpc.sh` 원격: `RESULT: 10 passed, 0 failed`.
  - `./supabase/tests/t4-t5-functions.sh` 원격: 첫 실행은 QA fixture drift로 실패, 보정 후 `RESULT: 10 passed, 0 failed`.
  - 별도 원격 RPC 하니스로 T1/T2/T3/T7 핵심 DB 전이 검증: `RESULT: 11 passed, 0 failed`.
- UI 브라우저 smoke:
  - 로컬 dev server(`127.0.0.1:3100`)가 원격 Supabase `.env`로 정상 기동.
  - 임시 active teacher 로그인 성공, 오늘 화면 표시 확인.
  - 임시 UI 계정은 삭제했고 dev server는 종료함.

## 아직 수동/실기기 필요

- T1/T2/T3의 실제 손 입력 시간 측정과 전체 모바일 조작 30초 기준.
- T5-2 OpenAI 실제 fallback 품질. 원격에서는 `OPENAI_API_KEY` 부재/비활성 시 `ai_error` 경로까지만 확인됨.
- T6-3~8 실제 Bridge polling, GoAlimi, 카톡 수신, 21시 이후 window.
- T8 실제 GoAlimi 동기화 10분 주기와 비활성화 반영.
- T9 홈 화면 설치, 비행기 모드, 모바일 실제 기기.
- T11 같은 계정 다기기와 GoAlimi 새 탭 실제 네트워크.
- T12 GoAlimi 확장 API/Bridge 정합은 2026-07-06 후속 하니스로 완료됨. 최신 기록은 `2026-07-06-session-t12-bridge-harness.md`.
