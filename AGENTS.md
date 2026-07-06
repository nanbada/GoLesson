# GoLesson - Agent Instructions

Small 1:1 academy operations tool for elementary English/math.
Target users: 1 owner, 1-3 teachers, 10-30 students. This is not an ERP.

## First Read

- At session start, read the latest file in `aidd_docs/memory/internal/`.
- At session end, record decisions and unfinished work in a new file in the same folder.
- Use `aidd_docs/plans/mvp-build-plan.md` for current stage/status.
- Use `docs/00_PROJECT.md` through `docs/11_GOALIMI_INTEGRATION_STUDY.md` as design SSOT.
- Conflict priority: `docs/01_PRD.md` > `docs/06_BUSINESS_RULE.md` > detailed docs.
- Use `aidd_docs/plans/remaining-work.md` as the live board of remaining go-live work. When you finish or discover work, update the board with evidence.
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
- Transactional multi-table writes should use Postgres RPC or Edge Functions. Current key RPCs: `save_lesson_log(jsonb)`, `save_payment_with_items(jsonb)`, `claim_outbox`.
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
- Remaining go-live QA is mostly real-device/academy-PC work: T1/T2/T3 timing, T5-2 OpenAI quality, T6 real Kakao send, T8 real GoAlimi sync, T9 phone/PWA, T11 multi-device/network.
- QA fixture cleanup is prepared in `supabase/seeds/qa_fixtures_cleanup_preview.sql` and `supabase/seeds/qa_fixtures_cleanup.sql`. Actual cleanup needs user approval and Bridge/GoAlimi re-sync precautions.

## Repository Map

```text
web/       Next.js static PWA
supabase/  migrations, Edge Functions, seeds, tests
bridge/    academy PC worker
docs/      design SSOT docs 00-11
aidd_docs/ plans, fixtures, session memory, archive
```
