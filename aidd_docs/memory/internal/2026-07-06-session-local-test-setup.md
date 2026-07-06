# 2026-07-06 Local Test Setup Handoff

## Result

- Local Supabase is running.
- Web dev server is running at `http://127.0.0.1:3100`.
- Supabase Studio is available at `http://127.0.0.1:54323`.
- Edge Functions are served locally through Supabase at `http://127.0.0.1:54321/functions/v1/*`.
- `web/.env.local` points the web app at the local Supabase API and is ignored by git.
- `/tmp/golesson-functions.env` contains local-only function environment values for the current function server process.

## Local Test Accounts

- Owner: `owner@example.com` / `localtest1234`
- Teacher: `teacher1@example.com` / `localtest1234`

## Setup Commands Used

```sh
supabase db reset --local
supabase db query --local --file supabase/seeds/prod_profiles_seed.sql
supabase functions serve --env-file /tmp/golesson-functions.env
npm --prefix web run dev -- --hostname 127.0.0.1 --port 3100
```

## Verification

- `curl -I http://127.0.0.1:3100` returned `HTTP/1.1 200 OK`.
- `curl -sS http://127.0.0.1:54321/functions/v1/parse-batch -X OPTIONS -i` returned `HTTP/1.1 200 OK`.
- Local password login succeeded for `owner@example.com`.
- Authenticated REST read against local `students` succeeded.
- `npm --prefix web run typecheck` passed.
- `supabase/tests/t4-t5-functions.sh` passed: `RESULT: 10 passed, 0 failed`.
- `supabase/tests/t10-access.sh` passed: `RESULT: 27 passed, 0 failed`.
- `supabase/tests/t13-transaction-rpc.sh` passed: `RESULT: 10 passed, 0 failed`.

## Notes

- A stale local database caused the first T5 enqueue check to fail. A full local reset fixed it.
- Keep `web/.env.local` out of commits. It is already ignored by `.gitignore`.
- Do not print local Supabase keys in chat or docs beyond local-only environment files.
