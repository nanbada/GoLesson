# 2026-07-10 Time-Block Coaching and Login Handoff

## Goal

- Align GoLesson with the actual academy operation: classes are grouped by scheduled time, not grade, subject, or level.
- Prioritize the Today screen for roughly five students per time block, individual progress/homework visibility, and 1:1 coaching workflow status.
- Move parent reports out of the daily primary navigation because they are generated every two weeks or monthly.
- Review whether login can be simplified for roughly five users on multiple devices.

## Decisions

- No class table was added. The current schema already has student slots and no grade/level class entity. Active slots sharing weekday and start time form one derived operating block.
- This assumes the academy does not run independent classes at the exact same time. If it does, an explicit block identifier and membership model are required before production use.
- Existing lesson status is displayed as coaching workflow status: waiting = coaching not started, in_progress = coaching in progress, done = coaching complete. No separate phase timer or coaching log table was added in this MVP change.
- Each operating block is shown as the configured lesson duration (normally 40 minutes) plus 40 minutes of homework/remedial work. Coaching may occur in either segment.
- Reports remain manual multi-student generation. No scheduler, cron, or new queue was added.
- Email/password remains the MVP login. Supabase supports full phone number + password or phone OTP, but phone login adds phone confirmation/operations and OTP adds an SMS provider. A phone-number suffix is not a supported identifier.
- The last six phone digits are prohibited as a password: only one million combinations and directly derived from personal information. Local Auth configuration now requires letters and digits with a minimum length of eight. Production Dashboard configuration is not changed automatically because `supabase config push` is forbidden.

## Implemented

- Updated SSOT and live plans:
  - `docs/00_PROJECT.md`
  - `docs/01_PRD.md`
  - `docs/02_USER_FLOW.md`
  - `docs/03_UI_SPEC.md`
  - `docs/04_DATABASE.md`
  - `docs/06_BUSINESS_RULE.md`
  - `docs/10_ACCEPTANCE_TEST.md`
  - `docs/11_GOALIMI_INTEGRATION_STUDY.md`
  - `aidd_docs/plans/mvp-build-plan.md`
  - `aidd_docs/plans/remaining-work.md`
- Today UI now groups scheduled students by start time, shows block student count and coaching completion count, and shows today's progress/homework results after recording.
- Renamed the lesson workflow UI to 1:1 coaching start/completion.
- Moved Reports from the bottom tab bar to More; bottom navigation now has four tabs.
- Login screen now explains persistent per-device sessions and has explicit email/password labels.
- Updated local `supabase/config.toml` password minimum from 6 to 8 and set `password_requirements = "letters_digits"`.

## Verification

- `npm --prefix web run typecheck` passed.
- `set -a; . ./web/.env; set +a; npm --prefix web run build` passed with static export routes `/` and `/_not-found`.
- `git diff --check` passed.
- In-app browser rendered the revised login form at a 320x800 viewport with no horizontal overflow. Authenticated Today UI was not browser-tested because no user credentials were used.

## Remaining Work

- B1 now requires a real phone test with roughly five students at the same start time, coaching status updates, today's progress/homework summaries, and the 30-second per-student target.
- A6 requires checking the production Supabase Dashboard Auth password policy and rotating weak/personal-information-derived passwords. Do not use `supabase config push`.
- Confirm whether independent classes can run at the exact same weekday/time. If yes, replace derived time grouping with an explicit block ID before the pilot.
- Phase-specific coaching history and an in-class homework `assigned -> result` workflow were not added. Add them only if the owner needs separate first-40-minute and second-40-minute coaching checkpoints rather than one overall per-student coaching status.
- No commit, push, production deployment, migration application, account update, or password change was performed.
