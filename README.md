# GoLesson

Small 1:1 academy operations tool for elementary English/math.
Target scale: 1 owner, 1-3 teachers, 10-30 students. Not an ERP.

Primary product goal: start a lesson in 5 seconds, finish lesson notes in 30 seconds.

## Current Status

Date: 2026-07-06 KST.

- GoAlimi API extension: complete in the GoAlimi repository.
- Supabase foundation: complete. Remote T10 RLS/access QA passed `27/27`.
- Edge Functions: deployed remotely, version 3 active. T4/T5 function harness passed `10/10`.
- Bridge: implemented. Unit tests and local GoAlimi/Supabase integration harness passed.
- Web PWA: implemented. UX subagent fixes applied. Typecheck/build/diff-check passed.
- QA fixture cleanup: prepared, but destructive cleanup requires explicit user approval.
- Remaining release checks: real phone/academy PC QA for T1/T2/T3, T5-2, T6, T8, T9, T11.

Latest detailed status lives in:

- `aidd_docs/plans/mvp-build-plan.md`
- `aidd_docs/memory/internal/2026-07-06-session-ux-subagent-review.md`
- `aidd_docs/memory/internal/2026-07-06-session-t12-bridge-harness.md`
- `docs/10_ACCEPTANCE_TEST.md`

## Architecture

```text
Teacher phone/tablet/PC
        |
        | HTTPS
        v
Next.js static PWA
        |
        | supabase-js + RLS
        v
Supabase Postgres/Auth/Edge Functions
        ^
        | outbound polling only
        |
GoLesson Bridge on academy Windows PC
        |
        | localhost
        v
GoAlimi attendance service -> KakaoTalk -> parents
```

Core decisions:

- GoLesson and GoAlimi are operated separately.
- GoAlimi is the master for students, parents, and attendance.
- Progress and homework are append-only/history-oriented logs.
- Parser is regex/dictionary first, AI fallback last.
- Reports must be reviewed as `draft -> ready` before sending.
- Sent report bodies are immutable.

## Repository Map

| Path | Purpose |
|---|---|
| `web/` | Next.js static PWA |
| `supabase/` | migrations, Edge Functions, seeds, QA scripts |
| `bridge/` | academy PC worker for outbox send, sync, backup |
| `docs/` | design SSOT, `00` through `11` |
| `aidd_docs/plans/` | build plan and handoff prompts |
| `aidd_docs/fixtures/` | QA fixture specification |
| `aidd_docs/memory/internal/` | session handoff history |
| `AGENTS.md` | Codex/agent working rules |
| `CLAUDE.md` | Claude working rules, with orchestration details |

## Start A New Work Session

1. Read `AGENTS.md` or `CLAUDE.md`.
2. Read the latest file in `aidd_docs/memory/internal/`.
3. Check `aidd_docs/plans/mvp-build-plan.md`.
4. Use `docs/00_PROJECT.md` through `docs/11_GOALIMI_INTEGRATION_STUDY.md` as design SSOT.

Conflict priority:

```text
docs/01_PRD.md > docs/06_BUSINESS_RULE.md > detailed docs > implementation
```

## Common Commands

Web:

```bash
npm --prefix web run typecheck
npm --prefix web run build
npm --prefix web run dev -- --hostname 127.0.0.1 --port 3100
```

Bridge unit tests:

```bash
python3 -m unittest bridge.tests.test_bridge
```

Bridge/GoAlimi integration harness uses local Supabase and a GoAlimi mock sender. See:

```text
aidd_docs/memory/internal/2026-07-06-session-t12-bridge-harness.md
```

Supabase QA scripts:

```bash
supabase/tests/t10-access.sh
supabase/tests/t13-transaction-rpc.sh
```

QA fixture cleanup preview:

```bash
supabase db query --local --file supabase/seeds/qa_fixtures_cleanup_preview.sql
```

Do not run destructive cleanup without user approval.

## Safety Rules

- Do not commit or push unless explicitly asked.
- Do not put secrets in chat, docs, git, frontend env examples, or browser bundles.
- Supabase `service_role` belongs only in academy PC Bridge config.
- OpenAI keys belong only in Supabase secrets.
- Sending tests must use only GoAlimi test account `7707 신성화`.
- Do not use `supabase config push` unless explicitly requested and audited.
- Do not embed GoAlimi in an iframe. Use a new-tab launcher only.

## Release QA

Release judgment follows `docs/10_ACCEPTANCE_TEST.md`.

Already covered by automated/semi-automated QA:

- T4/T5 function harness
- T10 RLS/access
- T13 transaction RPC
- T1/T2/T3/T7 core DB transitions
- T12 local Bridge/GoAlimi harness
- Web typecheck/build and UX review fixes

Still requires real device or academy PC:

- T1/T2/T3: phone-based lesson flow and 30-second operation timing
- T5-2: OpenAI fallback quality with Supabase secret configured
- T6: real Bridge/GoAlimi/KakaoTalk send and 600-900 character integrity
- T8: real GoAlimi 10-minute sync
- T9: mobile PWA install/offline behavior
- T11: PC/phone sessions and real network behavior for GoAlimi launcher
