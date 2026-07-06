# 2026-07-06 Source comment language cleanup

## Goal

- Keep source-code comments English-only for AI/token efficiency.
- Keep user-facing UI/runtime strings Korean.

## Scope

- Checked `web/`, `supabase/`, `bridge/`, root source/config comments.
- Excluded prose docs and `aidd_docs/` from source-comment enforcement.
- Did not change Korean test fixture data, UI labels, prompts, runtime errors, or report/message text.

## Changes

- Converted Korean or mixed-language comments to English in:
  - `.gitignore`
  - `web/app/page.tsx`
  - `supabase/functions/parse-batch/index.ts`
  - `supabase/migrations/20260704090000_init_schema.sql`
  - `supabase/migrations/20260705130000_revert_ready_body_immutable.sql`
  - `supabase/seeds/qa_fixtures_cleanup.sql`
  - `supabase/seeds/qa_fixtures_seed.sql`
  - `supabase/tests/t4-t5-functions.sh`

## Verification

- Web, Supabase, and Bridge subagents reviewed their scopes.
- `rg --hidden --no-ignore -n "(^\\s*(//|#|--|/\\*|\\*)|//|--).*[가-힣]" ...` returned no source-comment matches after exclusions.
- `git diff --check` passed.
- `npm --prefix web run typecheck` passed.
