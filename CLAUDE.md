# GoLesson - Claude Code 작업 지침

소규모 초등 영어/수학 1:1 학원 운영도구.
대상은 원장 1명 + 강사 1~3명, 학생 10~30명이다. ERP가 아니다.

## 기준 문서

- 설계 SSOT는 `docs/00_PROJECT.md` ~ `docs/11_GOALIMI_INTEGRATION_STUDY.md`.
- 충돌 시 우선순위: `docs/01_PRD.md` > `docs/06_BUSINESS_RULE.md` > 각 상세 문서.
- `docs/GoLesson AI용 추천 구조 및 개발자료.md`는 히스토리 문서다. SSOT로 쓰지 않는다.
- 코드와 문서가 다르면 문서를 기준으로 판단하되, 실제 구현과 충돌하면 먼저 근거를 확인하고 질문한다.
- 설계 변경을 하면 같은 작업에서 관련 `docs/` 문서도 고친다. 새 업무 규칙은 `06`, 요구사항 변경은 `01`에 반영한다.
- 구현 순서는 `aidd_docs/plans/mvp-build-plan.md`를 따른다. QA seed는 `aidd_docs/fixtures/mvp-seed-data.md`(`docs/10` §3 고정 문장과 짝으로 관리).
- 세션 시작 시 `aidd_docs/memory/internal/`의 최신 핸드오프를 읽는다. 세션 종료 시 결정 사항과 미완료 작업을 같은 폴더에 기록한다.

## 확정 방향

- 구조: Next.js 정적 PWA + Supabase(Postgres/Auth/Edge Functions) + 학원 PC Bridge + GoAlimi.
- 프론트는 정적 export 유지. Next.js API Route, SSR 의존, 호스팅 사업자 전용 API 금지.
- 서버 로직은 Supabase Edge Functions에 둔다.
- 일반 CRUD는 `supabase-js` + RLS로 처리한다.
- 호스팅은 정적 호스팅 교체 가능성을 유지한다. Vercel 전용 기능에 기대지 않는다.
- GoAlimi 통합은 분리 운영 확정. `docs/11_*` 재검토 트리거 없이는 기능 흡수, iframe, 양방향 동기화를 제안하지 않는다.

## 절대 규칙

1. 오버엔지니어링 금지. 사용자 5명 규모다. 요구되지 않은 추상화, 설정, 에러처리, 라이브러리, 실시간화, 자동화는 넣지 않는다.
2. GoAlimi(`/Users/nanbada/projects/GoAlimi/`) 변경은 필요 시 가능하나, 기존 기능을 제한/제약하지 않는 범위여야 한다(2026-07-04 완화 — 현재 1개 학원 사용, 상용 단계 아님). 단, 이 저장소에서 직접 수정하지 않고 GoAlimi 프로젝트에서 별도 작업한다. Claude-Setup은 읽기 전용 참고다.
3. GoAlimi 연동은 `docs/08_GOALIMI.md`에 명세한다. 실제 GoAlimi 변경은 GoAlimi 프로젝트에서 별도 작업한다.
4. GoAlimi API, DB, 발송 동작은 추측하지 않는다. 로컬/GitHub `nanbada/GoAlimi`의 실제 코드와 `docs/REFERENCE.md`를 확인한 뒤 의존한다.
5. 발송 안전을 우선한다. 자동 재발송 금지(BR-503), `dedupe_key` 필수, draft -> ready 검토 우회 금지, sent 본문 불변.
6. 발송 테스트는 GoAlimi 테스트 계정만 사용한다: 출결번호 7707 신성화 = 운영자 카톡.
7. 학생/학부모 생성·수정·비활성화의 마스터는 GoAlimi다. GoLesson의 `students`, `parents`, `attendance`는 Bridge 전용 사본이며 클라이언트 쓰기 금지.
8. 진도와 과제는 로그 방식이다. 현재값 덮어쓰기, 하드 삭제, 이력 재사용으로 처리하지 않는다.
9. 비밀키 금지선: Supabase `service_role` 키는 학원 PC `bridge_config.json`에만, OpenAI 키는 Supabase secrets에만 둔다. 프론트 번들·git·문서 예시에 넣지 않는다.
10. 커밋/푸시는 사용자가 요청할 때만 한다.

## 구현 주의

- Supabase 마이그레이션은 RLS와 명시적 GRANT를 함께 다룬다. Data API 노출을 기본값으로 가정하지 않는다.
- RLS는 테이블군별로 분리한다. `students`, `parents`, `attendance`는 클라이언트 select만 허용하고 insert/update/delete는 Bridge/service_role 전용으로 둔다.
- Bridge는 service_role로 Supabase REST(PostgREST)를 호출한다. outbox 인출은 `claim_outbox` RPC로만 한다 — 단순 PATCH로는 attempts 증가 불가(docs/04 §3).
- 오래된 processing outbox를 임의로 failed 처리하지 않는다. `goalimi_custom_id` 상태 조회 또는 dedupe_key 멱등 재POST로만 종결한다(docs/05 §3 — 이중발송 방지).
- 발송된 리포트 본문 불변은 DB 트리거(`t_reports_immutable`)가 강제한다. parse_logs는 본인 행의 status 컬럼만 클라이언트 갱신 가능(docs/04 §5).
- Bridge 발송 시간창은 09~21시다. 시간 외 pending은 실패가 아니라 대기다.
- GoAlimi 카톡 자동화는 기존 직렬 큐와 수신자 검증 경로를 사용한다. `kakao_pc.py` 직접 우회 금지.
- GoAlimi 화면은 새 탭 런처만 제공한다. HTTPS GoLesson 안에 로컬 HTTP GoAlimi iframe을 넣지 않는다.
- 날짜/시간은 naive local(Asia/Seoul) 원칙. 프론트에서 `toISOString()`으로 날짜가 하루 밀리지 않게 주의한다.
- Bridge `.bat`은 ASCII 전용, 경로 하드코딩 금지(`%~dp0`), Task Scheduler `ONLOGON`.

## UI와 QA

- 모바일 세로 우선(320px~), 버튼 44px 이상, 한 화면 한 작업. `docs/03_UI_SPEC.md` 0장을 따른다.
- 자동 E2E는 MVP 기준 아님. 출시 판정은 `docs/10_ACCEPTANCE_TEST.md` 수동 시나리오다.
- 파서 변경 시 `docs/10_ACCEPTANCE_TEST.md`의 고정 문장으로 검증한다. 목표는 5요소 매핑 95% 이상.
- AI는 최후 수단이다. 정형 파싱은 regex+사전 우선, 리포트 수치는 코드가 계산한다.

## Orchestration workflow (Claude Code 전용)

You (Fable) are the orchestrator. Plan, decompose, synthesize. Keep your own context lean — read pointers(문서 경로), delegate the heavy reading.

- Reasoning-heavy phases → **deep-reasoner** (Opus): 아키텍처, RLS/보안 설계, 복잡한 디버깅, 알고리즘 설계. Think thoroughly, return a concise conclusion the orchestrator can act on.
- Mechanical work → **fast-worker** (Sonnet): boilerplate, 테스트 코드, 포매팅, 단순 수정, 문서 반영. Execute efficiently.
- **Codex** (`/codex:rescue --background`) is a peer senior engineer with a different perspective. Treat as a peer, not a reviewer. 미설치/미세팅 상태면 이 단계는 생략하고 deep-reasoner로 대체.
- High-stakes decisions — 이 프로젝트에서는 **발송 안전(BR-500대), RLS/GRANT, GoAlimi 연동 계약(08), 데이터 무결성(1000대)** — task deep-reasoner + Codex on the same problem in parallel, synthesize the best of both **without showing either the other's answer**.
- 세션 킥오프 프롬프트는 `aidd_docs/plans/session-kickoff-prompt.md` 템플릿을 사용한다.

## 구조

```text
web/       Next.js 정적 PWA
supabase/  migrations, Edge Functions(parse-batch, generate-report, enqueue-report)
bridge/    학원 PC 워커(발송 폴링, GoAlimi 동기화, 야간 백업)
docs/      00_PROJECT ~ 11_GOALIMI_INTEGRATION_STUDY
```
