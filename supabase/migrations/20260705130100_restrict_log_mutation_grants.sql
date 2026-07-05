-- Tighten log mutation grants after the initial broad B/C table groups.
-- BR-101: progress is append-only; clients may insert new lesson_progress rows,
-- but must not overwrite existing ranges.
revoke update on lesson_progress from authenticated;
drop policy if exists p_lesson_progress_upd on lesson_progress;

-- Homework rows are history. Clients may update status/comment when checking a
-- task, but hard delete is not part of the product flow.
revoke delete on homeworks from authenticated;
drop policy if exists p_homeworks_del on homeworks;
