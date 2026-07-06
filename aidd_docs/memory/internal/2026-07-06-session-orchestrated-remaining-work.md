# 2026-07-06 Orchestrated Remaining Work Handoff

## Goal

- Review `aidd_docs/plans/remaining-work.md` as the current go-live board.
- Delegate independent checks to subagents and advance anything possible from the local/remote environment.
- Sync docs so the next Codex or Claude session starts from verified state, not stale assumptions.

## Completed

- Cloudflare Pages production deployment is complete.
  - Project: `golesson`
  - URL: `https://golesson.pages.dev`
  - Deployment: `1982fa86-32ca-47c8-888a-326c613d0abe`
  - Build config: root `web`, build command `npm run build`, output `out`
  - Pages env: `NODE_VERSION=22.16.0`, publishable Supabase URL/key only
  - Public checks: home page returns HTTP 200, deployed bundle contains remote project ref `dqibhcadjxqmvahcewfn`, and does not contain `127.0.0.1:54321` or `example.supabase`
  - Service worker is deployed with `golesson-shell-v2`
- Added `web/.node-version` with `22.16.0` for local/build-host parity.
- Updated remaining work and handoff docs:
  - `aidd_docs/plans/remaining-work.md`
  - `aidd_docs/plans/mvp-build-plan.md`
  - `aidd_docs/plans/claude-handoff-prompt.md`
  - `aidd_docs/plans/codex-handoff-prompt.md`
  - `aidd_docs/plans/session-kickoff-prompt.md`
  - `docs/09_DEPLOY.md`
  - `README.md`

## Subagent Results

- Cloudflare deploy readiness subagent initially reported A1 incomplete from stale project state. Main session then updated Pages build config/env, retried deployment, and verified the live site. Treat the main-session Cloudflare result above as current.
- GoAlimi/Bridge subagent verified code readiness but not PC installation:
  - GoAlimi HEAD contains `f9df186`; current inspected HEAD was `e77a19d`.
  - GoAlimi has GoLesson API router and localhost-only custom notify endpoint.
  - Bridge install files are coherent: `bridge/run_bridge.bat`, `bridge/requirements.txt`, and `bridge_config.example.json`.
  - GoAlimi requirements do not explicitly list `greenlet`; install/boot on the academy PC must verify this.
  - A3 remains open until the real academy PC is updated, Bridge config is installed, foreground run succeeds, ONLOGON task is registered, and reboot/logon auto-start is observed.

## OpenAI / T5-2 Result

- `OPENAI_API_KEY` is registered in Supabase secrets and visible to Edge Runtime.
- `OPENAI_MODEL_PARSE` and `OPENAI_MODEL_REPORT` are registered with the code-default model names.
- Remote `generate-report` works as a fallback path, but AI opinion is not currently usable:
  - Diagnostic Edge Function returned OpenAI `429 insufficient_quota`.
  - The diagnostic function was deleted after the check.
  - Remote cleanup was verified: temporary B2 comments/reports/profiles were removed.
- Added A5 to `remaining-work.md`: restore OpenAI quota/billing.
- B2 remains blocked until A5 is resolved, then T5-2 must be rerun on real comments.

## Verification

- `npm --prefix web run typecheck` passed.
- `set -a; . ./web/.env; set +a; npm --prefix web run build` passed.
- `curl -I https://golesson.pages.dev` returned HTTP 200.
- Remote Supabase functions list after diagnostic cleanup contains only:
  - `parse-batch`
  - `generate-report`
  - `enqueue-report`

## Remaining Work

- A2 is complete; model secrets do not unblock B2 because the current blocker is OpenAI quota/billing.
- A3 academy PC install blocks B3/B4/B7.
- A4 `goalimi_admin_url` LAN address blocks B6.
- A5 OpenAI quota/billing blocks B2.
- B1/B5 can now proceed on a real phone because A1 is complete.
- No commit or push was performed.
