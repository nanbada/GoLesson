# Codex Handoff — GoLesson [5] Web PWA: QA + 코드리뷰

GPT Codex 세션 시작 프롬프트로 사용한다. 기본 정책은 저장소 `AGENTS.md`(= CLAUDE.md와 동일 정책, 오케스트레이션 섹션 제외)를 따르고, 이 문서는 그 위에 얹는 작업 브리핑이다. 세부 근거는 본문 붙여넣기 대신 파일 포인터로 따른다.

## 역할

두 가지를 한다. 둘 다 **read-only** — 파일 수정·커밋·푸시·배포·운영 DB 쓰기 금지.

1. **코드리뷰**: `web/` 정적 PWA와 그것이 호출하는 발송 파이프라인(Edge Functions·Bridge·마이그레이션)을 발송안전·정합·과설계 관점에서 리뷰.
2. **QA 검증**: `docs/10_ACCEPTANCE_TEST.md` §1 T항목 중 코드/빌드로 검증 가능한 부분을 판정하고, 실기기(사람)만 가능한 부분은 분리해 러브릭으로 넘긴다.

## 지금까지 검증된 상태 (2026-07-05, 사람 조작 + Claude MCP 검증)

선행 게이트(운영 env·seed·Auth): 운영 프로젝트 `dqibhcadjxqmvahcewfn`(ap-northeast-2) / 공개 key는 publishable key(`sb_publishable_...`) / owner profile 1건 / `app_settings.academy_name=루트원학원` seed / QA fixture 멱등 seed(학생 4·교재 5·스케줄 9·결제 2) / Auth "Allow new users to sign up" off / typecheck·static build·`npm audit --omit=dev` clean. 상세: `aidd_docs/memory/internal/2026-07-05-session-web-pwa-qa.md`.

docs/10 §1 T-by-T 원장(정직 원장 — 통과한 것만 통과로):

- **T5 리포트** ✅(수치·구조) — draft 수치 = 실데이터 수기대조 일치. T5-2 AI 의견은 `OPENAI_API_KEY`(Supabase secret) 미설정 시 보류.
- **T7 수강료** ✅ — 2026-06 월합계 600,000원(카드 400,000 / 현금 200,000) 화면·DB·수기 일치. 수정·삭제 시 audits 전후기록 검증(payments AFTER UPDATE/DELETE 트리거; 클라이언트 삭제로 결제 row_id=4의 before 스냅샷 캡처). 참고: audit before는 payments 행 수준 — 금액은 payment_items(별도 테이블).
- **T9 모바일·네트워크** — 코드레벨 ✅(320px 무가로스크롤·44px·PWA 설치요건·오프라인 입력보존), 실기기 확인 대기. ⚠ 오프라인 테스트 전 real-env 재빌드 + SW 캐시 클리어 선행.
- **T11 계정·바로가기** — 코드레벨 ✅(GoAlimi 새 탭 `target=_blank`, iframe 0건, 다중세션 허용), 실기기 확인 대기.
- **T1 오늘 화면 수업 + REQ-902(30초)** — 대기. 고정 fixture는 월~금이라 2026-07-06 월요일부터 판정.
- **T2 진도 경계·T3 과제 이월 이력** — 실행 대기(미판정).

## 이번 세션 발송안전 변경 이력 (리뷰 시 참고 — 재플래그 방지)

- ready 리포트 본문을 `status='ready'`에서 잠그는 트리거(마이그레이션 `20260705120000`)를 잠깐 적용했다가 **같은 날 되돌렸다**(`20260705130000`). 사유: (1) `docs/06` **BR-506**이 ready 본문을 sent 전까지 클라이언트 수정 허용으로 명시(1인 자기검토 워크플로 — ready-lock은 과설계), (2) Bridge는 `notification_outbox.message`(enqueue 시점 스냅샷, `bridge/bridge.py:296`)를 보내고 live `reports.body`를 재독하지 않으므로 승인 후 편집이 발송에 도달하지 못함(무해). 최종 트리거는 sent-only 불변만 강제. 두 마이그레이션이 모두 남은 것은 의도된 정직한 이력.
- `web/app/page.tsx`에 `edgeError()` 헬퍼 추가(유지) — `supabase.functions.invoke` 오류의 `context`(Response)에서 `{message}`를 풀어 실제 Edge 오류("이미 발송 대기 중입니다." 등)를 사용자에게 노출. generateReports·enqueueReport에서 사용.

## 코드리뷰 중점 (불변식 대비)

- **발송 안전(BR-500s)**: 자동 재발송 금지(BR-503), `dedupe_key` 필수(`report:{id}:v{n}`), draft→ready 검토 우회 금지, sent 본문 불변(트리거 `t_reports_immutable`), enqueue-report 409/422 계약, Bridge는 `claim_outbox` RPC로만 인출.
- **RLS/GRANT**: `students`·`parents`·`attendance`는 클라이언트 select만(insert/update/delete는 Bridge/service_role 전용). `payments`·`payment_items`·`lessons`·`reports` 등은 클라이언트 쓰기 허용 + audit.
- **정적 export 유지**: Next API Route·SSR·호스팅 전용 기능 금지. 서버 로직은 Edge Functions 3개(`parse-batch`·`generate-report`·`enqueue-report`)만.
- **과설계 금지**: 사용자 5명 규모. 요구되지 않은 추상화·설정·실시간화·에러처리 금지.
- **날짜**: naive local(Asia/Seoul). 프론트 `toISOString()` 하루 밀림 주의.

## 리뷰 대상 파일

- `web/app/page.tsx`(SPA 전체), `web/app/lib/{supabase,types,date}.ts`, `web/app/globals.css`, `web/public/{manifest.webmanifest,service-worker.js}`
- `supabase/functions/{parse-batch,generate-report,enqueue-report}/index.ts`
- `supabase/migrations/*.sql`(특히 `*_functions_triggers`, `*_rls_grant`, `20260705120000`/`20260705130000`)
- `bridge/bridge.py`(발송·`claim_outbox`·동기화·발송 시간창 09~21)

## 출력

파일:라인 근거를 단 리뷰 소견(심각도순) + QA 판정표(criterion | 코드레벨 verdict PASS/FAIL/PARTIAL | 근거 file:line | 실기기 확인 필요 여부). 발견은 검증 후 보고 — 추측 금지, self-critique 대신 근거 제시.

## 안전

read-only. 커밋/푸시/배포/운영 DB 쓰기 금지. 발송 테스트는 GoAlimi 테스트 계정만(출결번호 7707 신성화 = 운영자 카톡). `service_role`은 `bridge_config.json`에만, OpenAI 키는 Supabase secrets에만 — 프론트 번들·git·문서 예시에 금지. `supabase config push` 금지(로컬 config.toml은 dev 설정).
