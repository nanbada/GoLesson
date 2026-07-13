# 2026-07-13 Local Test Script

## Goal

- Provide one command that prepares the local GoLesson test environment without keeping the local stack running when it is not needed.

## Decisions

- Added `scripts/local-test.sh` with `start`, `stop`, and `status` commands.
- `start --reset-db` is opt-in because `supabase db reset --local` deletes local test data. Plain `start` preserves the local database.
- The script refuses any non-local Supabase URL before it creates local Auth users or writes the Edge Function environment file.
- `stop` stops only web and Edge Functions started by this script. `--stop-supabase` is required to stop the local Supabase containers; OrbStack itself is never stopped by the script because it can host other projects.
- Edge Functions require separate ownership tracking because the current CLI leaves the Edge Runtime container running after `functions serve` starts it.

## Changed

- `scripts/local-test.sh` (new, executable)
- `.gitignore` ignores `.local-test/`, which holds 0700 runtime logs and PIDs.
- `README.md` documents start, reset, and stop usage.

## Verification

- `bash -n scripts/local-test.sh` passed.
- `scripts/local-test.sh start` completed with local Supabase, Edge Functions, and the web server ready.
- `http://127.0.0.1:3100` returned HTTP 200.
- Local `parse-batch` returned HTTP 401 without credentials, confirming the Edge Function route was served.
- `scripts/local-test.sh stop` left local Supabase DB running while web and Edge Runtime were stopped.
- `git diff --check` passed.

## Next

- Run `scripts/local-test.sh start --reset-db` only when a fresh local fixture database is wanted; it was not run in this session because it is destructive to local test data.
