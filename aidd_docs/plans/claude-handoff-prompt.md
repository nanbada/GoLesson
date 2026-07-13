# Claude Handoff Prompt — GoLesson QA·Go-Live 마감

아래 블록을 Claude Code 새 세션 시작 프롬프트로 사용한다. 토큰 절약용 단축본이며, 세부 근거는 파일 포인터만 따른다.

```text
Goal: GoLesson MVP 출시 전 남은 실기기/운영 PC QA를 끝내고, 결과를 docs/10_ACCEPTANCE_TEST.md §2 Go-Live Checklist와 aidd_docs/memory/internal/에 기록한다.

2026-07-10 로컬 변경(아직 커밋·푸시·재배포 안 됨):
- 수업 편성 SSOT를 학년/과목/레벨 반이 아니라 같은 요일+시작 시각의 약 5명 운영 블록으로 정정. 기본 40분 수업 + 40분 과제·보강, 전 구간 학생별 5~10분 1:1 코칭.
- 별도 class 테이블은 추가하지 않음. 같은 시각에 독립 반이 동시에 없다는 가정이며, 있으면 명시적 block_id 설계가 먼저 필요.
- 오늘 화면을 시작 시각별 그룹으로 변경: 블록 학생 수·코칭 완료 n/전체, 학생별 코칭 전/중/완료, 시작 전 직전 진도/미체크 과제, 기록 후 오늘 진도/오늘 과제 결과 표시.
- 수업 UI 문구를 [1:1 코칭 시작] → [코칭 기록 완료]로 변경. 코칭 상태는 lesson waiting/in_progress/done을 사용하며 수업/과제 단계별 별도 코칭 로그는 아직 없음.
- 하단 탭을 오늘·학생·빠른입력·더보기 4개로 축소하고, 2주/월 단위 리포트는 더보기로 이동.
- 로그인은 이메일+비밀번호 유지. 기기별 최초 로그인 후 세션 유지 안내와 명시적 label 추가. 로컬 Supabase 정책은 영문+숫자 8자 이상으로 변경했으나 운영 Dashboard 설정은 미변경(A6).
- 공통 AGENTS.md를 Sol/Terra/Luna/GPT-5.5 예외 라우팅, 토큰 절약, 문서 라우팅, 범위별 검증 명령 중심으로 갱신. Claude는 CLAUDE.md의 @AGENTS.md import로 이를 함께 읽음.
- 변경 핵심 파일: web/app/page.tsx, web/app/globals.css, docs/00/01/02/03/04/06/10/11, supabase/config.toml, AGENTS.md.
- 검증: `npm --prefix web run typecheck`, `npm --prefix web run build`, `git diff --check` PASS. 320px 로그인 렌더 확인. 인증된 오늘 화면과 실폰 흐름은 아직 미검증.
- 상세 근거: aidd_docs/memory/internal/2026-07-10-session-time-block-coaching-login.md, aidd_docs/memory/internal/2026-07-10-session-agents-optimization.md.

완료 기준:
- T1/T2/T3: 실제 폰에서 같은 시각 학생 약 5명이 한 블록으로 표시되는지 확인 → 학생별 코칭 시작→진도→과제→완료 → 블록 완료 수와 오늘 요약 갱신 확인. REQ-902 학생당 30초 이내 직접 측정.
- T5-2: OpenAI quota/billing 복구 후 AI 의견이 입력 코멘트 밖의 사실·수치를 만들지 않는지 확인. 현재 `OPENAI_API_KEY`는 Edge Runtime에 보이나 OpenAI가 `429 insufficient_quota`를 반환해 fallback 처리됨.
- T6: 테스트 학생 7707 신성화만 사용. Bridge/GoAlimi 실발송, 600~900자 카톡 온전성, dedupe 409, GoAlimi 중지 후 pending 유지, 21시 이후 window를 확인.
- T8: 실제 GoAlimi 운영 데이터에서 학생 등록/비활성화가 Bridge 10분 주기 안에 GoLesson에 반영되는지 확인.
- T9: 실제 모바일 홈 화면 설치, standalone 실행, 비행기 모드 입력 보존, 복귀 후 재제출 성공 확인.
- T11: 같은 계정 PC·폰 동시 세션 유지, GoAlimi 바로가기 새 탭, 학원 밖 네트워크 미도달 안내 확인.
- QA fixture cleanup: 파일럿 종료 시점에는 preview SQL로 count 확인 후 cleanup SQL 실행 계획만 기록한다. 실제 삭제는 사용자 승인 후 별도 수행.

이미 완료된 것(2026-07-10 기준, 07-10 로컬 변경은 미배포):
- 원격 Supabase project ref: dqibhcadjxqmvahcewfn, region ap-northeast-2.
- DB migrations local/remote 일치. 20260705130100(restrict log mutation grants), 20260705130200(transactional lesson/payment RPC)까지 원격 적용.
- Edge Functions parse-batch/generate-report/enqueue-report 원격 배포 완료: version 3, ACTIVE, verify_jwt=true.
- 원격 자동 QA:
  - supabase/tests/t10-access.sh: RESULT 27 passed, 0 failed.
  - supabase/tests/t13-transaction-rpc.sh: RESULT 10 passed, 0 failed.
  - supabase/tests/t4-t5-functions.sh: RESULT 10 passed, 0 failed.
  - 별도 원격 RPC 하니스 T1/T2/T3/T7 핵심 DB 전이: RESULT 11 passed, 0 failed.
- Web PWA: 2026-07-06 버전은 Cloudflare Pages `https://golesson.pages.dev` 배포 완료. 2026-07-10 시간대 그룹·코칭 현황·4탭·로그인 안내 변경은 로컬 typecheck/build/diff-check만 통과했고 아직 재배포하지 않음.
- UX subagent 리뷰 반영: 수업 시작 전 폼 숨김, lesson id 반영, 리포트 본문 저장 후 승인/발송, 빠른입력 빈 숫자 방지, PWA navigation network-first. typecheck/build/diff-check 통과.
- T5 수치·구조, T7 수강료는 수동+DB 대조 통과. T9/T11은 코드레벨 통과, 실기기만 남음.
- Bridge/GoAlimi 로컬 하니스: T6 Bridge 항목, T8, T12-6~7 PASS. 마지막 라인: PASS Bridge integration harness completed.

남은 배포 전제와 실기기 QA 목록의 SSOT는 aidd_docs/plans/remaining-work.md 보드다(A 배포 전제 → B 실기기 QA). 시작 시 보드를 읽고, 항목 완료 시 체크+근거로 갱신한다.

필수로 먼저 읽을 파일:
- CLAUDE.md
- aidd_docs/memory/internal/2026-07-10-session-time-block-coaching-login.md
- aidd_docs/memory/internal/2026-07-10-session-agents-optimization.md
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
