# GoLesson - Claude Code 작업 지침

소규모 초등 영어/수학 1:1 학원 운영도구.
대상은 원장 1명 + 강사 1~3명, 학생 10~30명이다. ERP가 아니다.

프로젝트 공통 규칙의 SSOT는 `AGENTS.md` 하나다(Claude·Codex 공용). 아래 import로 전체가 로드되며, 규칙 추가/수정은 AGENTS.md에서 한다.

@AGENTS.md

## Claude 세션 운영

- 세션 시작: `aidd_docs/memory/internal/` 최신 핸드오프를 읽고, 남은 업무는 `aidd_docs/plans/remaining-work.md` 보드로, 단계 현황은 `aidd_docs/plans/mvp-build-plan.md`로 확인한다.
- QA·Go-Live 마감 세션은 `aidd_docs/plans/claude-handoff-prompt.md`의 프롬프트 블록으로 시작한다. 일반 킥오프 템플릿은 `aidd_docs/plans/session-kickoff-prompt.md`.
- 코드와 문서가 다르면 문서를 기준으로 판단하되, 실제 구현과 충돌하면 먼저 근거를 확인하고 질문한다.
- Claude-Setup은 읽기 전용 참고다.

## Orchestration workflow (Claude Code 전용)

You are the orchestrator. Plan, decompose, synthesize. Keep your own context lean — read pointers(문서 경로), delegate the heavy reading.

- Reasoning-heavy phases → **deep-reasoner** (Opus): 아키텍처, RLS/보안 설계, 복잡한 디버깅, 알고리즘 설계. 간결한 결론만 회수한다.
- Mechanical work → **fast-worker** (Sonnet): boilerplate, 테스트 코드, 포매팅, 단순 수정, 문서 반영.
- **Codex** (`/codex:rescue --background`)는 관점이 다른 peer senior engineer다. 리뷰어가 아니라 동료로 대한다. 미설치/미세팅 상태면 이 단계는 생략하고 deep-reasoner로 대체.
- High-stakes — **발송 안전(BR-500대), RLS/GRANT, GoAlimi 연동 계약(docs/08), 데이터 무결성(1000대)** — 는 deep-reasoner와 Codex를 같은 문제에 병렬 투입하고, **서로의 답을 보여주지 않은 채** 종합한다.
