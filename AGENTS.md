# GoLesson - Agent Instructions

Small time-block academy operations tool for elementary English/math with rotating 1:1 coaching.
Target users: 1 owner, 1-3 teachers, 10-30 students. This is not an ERP.

## Agent Orchestration

- The root orchestrator owns scope, constraints, routing, user communication, write authority, conflict resolution, integration, and final verification. Work directly when delegation costs more than it saves.
- Preferred models when per-agent selection is available:
  - **Sol (`gpt-5.6-sol`)**: root orchestration plus ambiguous, high-risk, architecture, security, cross-cutting, and final-quality work. Medium reasoning first; raise only for consequential uncertainty.
  - **Terra (`gpt-5.6-terra`)**: bounded complex implementation, root-cause tracing, multi-file review, API research, and test design. Medium by default; high for difficult edge cases.
  - **Luna (`gpt-5.6-luna`)**: targeted search, inventory, extraction, formatting, mechanical edits, deterministic checks, and concise summaries. Low reasoning.
  - **GPT-5.5**: exception only for 5.6 unavailability, pinned compatibility, or an independent previous-generation second opinion. Not a routine worker.
- Sol is deepest; Terra is the balanced workhorse; Luna is the fast repeatable-task worker. If model selection is unavailable, preserve these role boundaries and never claim a model ran.
- Delegate only independent or noisy read-heavy lanes. Avoid delegation for trivial, serial, user-blocked, or tightly coupled work. Default cap: root + two workers, depth one.
- Prefer read-only parallel audits. The root edits shared files unless write scopes are disjoint, waits for workers, integrates distilled results, and rechecks decisive evidence.
- Sol directly reviews final decisions involving Sending Safety, RLS/GRANT, GoAlimi contracts, irreversible production actions, and history preservation.

## Context and Token Discipline

- Start with `rg`/`rg --files`; read only relevant ranges, never all `docs/00` through `docs/11` by default.
- Worker prompts contain only objective, scope, constraints, ownership, done criteria, and evidence. Workers return distilled decisions, risks, `file:line`/command evidence, and unknowns, not raw logs or full files.
- Batch independent checks, cap output, and quote only decisive error lines. Link SSOT instead of copying it into plans or memory.
- Use the lowest-cost reliable model and reasoning level. Do not spawn every role automatically.

## First Read

- At session start, read the latest file in `aidd_docs/memory/internal/`.
- For material work, read only the relevant sections of `aidd_docs/plans/mvp-build-plan.md` and `aidd_docs/plans/remaining-work.md`; the latter is the live go-live board and must be updated with evidence when work is finished or discovered.
- Route design questions through `docs/01_PRD.md`, then `docs/06_BUSINESS_RULE.md`, then the relevant detailed document. Do not read unrelated SSOT files.
- Document routing: UI `01/02/03`; DB/RLS/API `04/05/06`; AI/parser/report `07`; GoAlimi/sending `08`; deploy `09`; release `10`; integration study `11` only when explicitly reopened.
- Conflict priority: `docs/01_PRD.md` > `docs/06_BUSINESS_RULE.md` > detailed docs > implementation.
- After material decisions, verified changes, or unfinished work, create one concise session file in `aidd_docs/memory/internal/`. Skip memory churn for simple read-only answers with no durable outcome.
- Superseded handoffs and the pre-project history doc live in `aidd_docs/archive/`. Do not treat them as SSOT.

## Current Architecture

- Frontend: Next.js static PWA in `web/`.
- Backend: Supabase Postgres/Auth/Edge Functions in `supabase/`.
- Local worker: academy PC Bridge in `bridge/`.
- External attendance/messaging system: GoAlimi, operated separately.
- Static export must remain portable. Do not add Next API routes, SSR dependencies, or host-specific server features.
- Server logic belongs in Supabase Edge Functions or Postgres RPC. Ordinary CRUD uses `supabase-js` plus RLS.

## Non-Negotiables

1. Keep the system small. Avoid unrequested abstractions, realtime, global state managers, automation, heavy libraries, and broad refactors.
2. Do not commit or push unless the user explicitly asks.
3. Do not guess APIs, DB shape, or GoAlimi behavior. Read actual local/GitHub code and GoAlimi `docs/REFERENCE.md` first.
4. Do not write secrets to chat, docs, git, frontend env examples, or browser bundles.
5. Supabase `service_role` belongs only on the academy PC Bridge config. OpenAI keys belong only in Supabase secrets.
6. Student, parent, and attendance master data belongs to GoAlimi. GoLesson keeps Bridge-synced read copies.
7. Progress and homework are log/history based. Do not solve changes by overwriting current values, hard deleting history, or reusing old rows.
8. Design changes must update the relevant `docs/` file in the same task. New business rules go in `docs/06_BUSINESS_RULE.md`; requirement changes go in `docs/01_PRD.md`.

## GoAlimi Rules

- GoAlimi integration is specified in `docs/08_GOALIMI.md`.
- GoAlimi must stay a separate app unless `docs/11_*` is explicitly reopened.
- No iframe embedding of local HTTP GoAlimi inside HTTPS GoLesson. Use a new-tab launcher only.
- If GoAlimi must change, work in `/Users/nanbada/projects/GoAlimi/`, not inside this repository.
- Do not restrict existing GoAlimi behavior without direct user approval.
- Sending tests may use only the GoAlimi test account: attendance number `7707 신성화` = operator KakaoTalk.

## Sending Safety

- No automatic resend. Follow BR-503.
- `dedupe_key` is mandatory for outbox sends.
- Draft -> ready review must not be bypassed.
- Sent report body is immutable through DB trigger `t_reports_immutable`.
- Bridge must claim outbox rows only through `claim_outbox`.
- Do not mark old `processing` outbox rows failed by timeout alone. Resolve through GoAlimi status lookup or idempotent re-POST with the same `dedupe_key`.
- Bridge send window is 09:00-21:00 local time. Outside the window, pending means waiting, not failed.
- GoAlimi Kakao automation must use its existing serialized queue and recipient validation path. Do not call `kakao_pc.py` directly.

## Supabase Rules

- Migrations must handle RLS and explicit GRANT together. Do not assume Data API exposure.
- `students`, `parents`, `attendance`: client select only; insert/update/delete via Bridge/service_role only.
- `parse_logs`: client may update only its own row status as specified in `docs/04_DATABASE.md`.
- Transactional multi-table writes should use Postgres RPC or Edge Functions. Confirm current RPC contracts in `docs/04_DATABASE.md`, `docs/05_API_SPEC.md`, and the actual migrations before changing them.
- `supabase config push` is forbidden unless the user explicitly requests and current local config has been audited against production.

## Frontend/UX Rules

- Mobile portrait first from 320px.
- Touch targets at least 44px.
- One screen, one task. Follow `docs/03_UI_SPEC.md`.
- Default shell width should stay narrow; use wide/split views only for comparison-heavy screens.
- Preserve offline drafts where the current implementation supports them.
- Dates/times follow naive local Asia/Seoul. Avoid `toISOString()` for user-facing dates that can shift by timezone.

## Code Conventions

- Source comments, docstrings, and log messages are English-only. User-facing UI/runtime strings stay Korean.
- Bridge `.bat` files: ASCII only, no hardcoded paths (use `%~dp0`), Task Scheduler `ONLOGON`.

## QA Rules

- Release judgment follows `docs/10_ACCEPTANCE_TEST.md`, not automated E2E alone.
- Parser changes must be checked against fixed sentences in `docs/10_ACCEPTANCE_TEST.md` and `aidd_docs/fixtures/mvp-seed-data.md`. Target: 5-element mapping at 95% or higher (19/20).
- AI is fallback only. Regex/dictionary parsing comes first, and report numbers are computed by code.
- Current go-live status belongs only in `aidd_docs/plans/remaining-work.md`; do not duplicate it here.
- QA fixture cleanup is prepared in `supabase/seeds/qa_fixtures_cleanup_preview.sql` and `supabase/seeds/qa_fixtures_cleanup.sql`. Actual cleanup needs user approval and Bridge/GoAlimi re-sync precautions.

## Verification Commands

- Every change: `git diff --check` plus a targeted diff review.
- Web code: `npm --prefix web run typecheck`; also run `npm --prefix web run build` for runtime, dependency, config, PWA, or pre-handoff changes.
- Bridge code: `python3 -m unittest bridge.tests.test_bridge`.
- Parser, DB, Edge Function, integration, or release changes: run only the relevant harness defined in `docs/10_ACCEPTANCE_TEST.md`; inspect its prerequisites first and do not guess remote flags or credentials.
- Use Python 3.12 for the Bridge/GoAlimi integration harness. Real Kakao sends, production mutations, fixture cleanup, and remote destructive tests remain approval-gated by the safety rules above.
