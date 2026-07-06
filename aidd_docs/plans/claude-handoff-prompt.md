# Claude Handoff Prompt — GoLesson QA·Go-Live 마감

아래 블록을 Claude Code 새 세션 시작 프롬프트로 사용한다. 토큰 절약용 단축본이며, 세부 근거는 파일 포인터만 따른다.

```text
Goal: GoLesson MVP 출시 전 남은 실기기/운영 PC QA를 끝내고, 결과를 docs/10_ACCEPTANCE_TEST.md §2 Go-Live Checklist와 aidd_docs/memory/internal/에 기록한다.

완료 기준:
- T1/T2/T3: 실제 폰에서 오늘 수업 시작→진도→과제→완료 흐름을 수행. REQ-902 기록 조작 합계 30초 이내를 직접 측정.
- T5-2: Supabase secret OPENAI_API_KEY가 설정된 상태에서 AI 의견이 입력 코멘트 밖의 사실·수치를 만들지 않는지 확인. secret 미설정이면 "수치·구조 PASS, AI 의견 보류"로 명시.
- T6: 테스트 학생 7707 신성화만 사용. Bridge/GoAlimi 실발송, 600~900자 카톡 온전성, dedupe 409, GoAlimi 중지 후 pending 유지, 21시 이후 window를 확인.
- T8: 실제 GoAlimi 운영 데이터에서 학생 등록/비활성화가 Bridge 10분 주기 안에 GoLesson에 반영되는지 확인.
- T9: 실제 모바일 홈 화면 설치, standalone 실행, 비행기 모드 입력 보존, 복귀 후 재제출 성공 확인.
- T11: 같은 계정 PC·폰 동시 세션 유지, GoAlimi 바로가기 새 탭, 학원 밖 네트워크 미도달 안내 확인.
- QA fixture cleanup: 파일럿 종료 시점에는 preview SQL로 count 확인 후 cleanup SQL 실행 계획만 기록한다. 실제 삭제는 사용자 승인 후 별도 수행.

이미 완료된 것(2026-07-06 기준):
- 원격 Supabase project ref: dqibhcadjxqmvahcewfn, region ap-northeast-2.
- DB migrations local/remote 일치. 20260705130100(restrict log mutation grants), 20260705130200(transactional lesson/payment RPC)까지 원격 적용.
- Edge Functions parse-batch/generate-report/enqueue-report 원격 배포 완료: version 3, ACTIVE, verify_jwt=true.
- 원격 자동 QA:
  - supabase/tests/t10-access.sh: RESULT 27 passed, 0 failed.
  - supabase/tests/t13-transaction-rpc.sh: RESULT 10 passed, 0 failed.
  - supabase/tests/t4-t5-functions.sh: RESULT 10 passed, 0 failed.
  - 별도 원격 RPC 하니스 T1/T2/T3/T7 핵심 DB 전이: RESULT 11 passed, 0 failed.
- Web PWA: typecheck/build/audit 통과, 원격 env 로그인 smoke 통과.
- UX subagent 리뷰 반영: 수업 시작 전 폼 숨김, lesson id 반영, 리포트 본문 저장 후 승인/발송, 빠른입력 빈 숫자 방지, PWA navigation network-first. typecheck/build/diff-check 통과.
- T5 수치·구조, T7 수강료는 수동+DB 대조 통과. T9/T11은 코드레벨 통과, 실기기만 남음.
- Bridge/GoAlimi 로컬 하니스: T6 Bridge 항목, T8, T12-6~7 PASS. 마지막 라인: PASS Bridge integration harness completed.

남은 배포 전제와 실기기 QA 목록의 SSOT는 aidd_docs/plans/remaining-work.md 보드다(A 배포 전제 → B 실기기 QA). 시작 시 보드를 읽고, 항목 완료 시 체크+근거로 갱신한다.

필수로 먼저 읽을 파일:
- CLAUDE.md
- aidd_docs/memory/internal/2026-07-06-session-ux-subagent-review.md
- aidd_docs/memory/internal/2026-07-06-session-t12-bridge-harness.md
- aidd_docs/plans/remaining-work.md (남은 업무 보드 — 완료 시 체크+근거 갱신)
- docs/10_ACCEPTANCE_TEST.md
- docs/09_DEPLOY.md §4.3

보조 확인 파일:
- aidd_docs/plans/mvp-build-plan.md
- aidd_docs/archive/2026-07-05-session-project-review-qa.md (지난 QA 상세)
- aidd_docs/fixtures/mvp-seed-data.md
- docs/03_UI_SPEC.md §0, §7
- docs/08_GOALIMI.md §3~§5
- bridge/tests/integration_bridge.py

주의:
- 커밋/푸시는 사용자가 요청할 때만.
- service_role/sb_secret/OpenAI 키를 채팅, 문서, web/.env, git에 남기지 않는다.
- supabase config push 금지. 로컬 supabase/config.toml은 운영 Auth 설정을 덮을 수 있다.
- 발송 테스트는 GoAlimi 테스트 계정 7707 신성화만 사용한다.
- Bridge 하니스는 원격 Supabase 실행을 거부한다. 실제 발송 QA는 학원 PC/운영 GoAlimi에서 한다.
- QA fixture 삭제는 `supabase/seeds/qa_fixtures_cleanup_preview.sql` → `supabase/seeds/qa_fixtures_cleanup.sql` 순서. 실행 전 Bridge 중지 또는 GoAlimi 테스트 학생 비활성/삭제가 필요하다.
- 개발 Mac의 python3가 3.14이면 GoAlimi pydantic-core 호환성 때문에 하니스가 실패한다. Python 3.12 venv 사용. GoAlimi async startup에는 greenlet이 필요했으나 GoAlimi repo는 아직 수정하지 않았다.

실행 방식:
1. 먼저 위 완료/미완료 상태가 실제 파일·대시보드와 맞는지 확인한다.
2. 남은 QA만 수행한다. 이미 통과한 자동 QA를 반복하지 않는다.
3. PASS/FAIL/PARTIAL을 docs/10 §2와 새 memory 파일에 근거와 함께 남기고, remaining-work.md 보드를 체크 갱신한다.

You're the lead. Show the shortest executable QA plan first, then execute.
```
