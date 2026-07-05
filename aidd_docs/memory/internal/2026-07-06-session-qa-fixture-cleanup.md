# 2026-07-06 QA fixture cleanup 준비

## 목표

- 약 2주 파일럿/운영 QA 이후 운영 Supabase에서 테스트 데이터를 일괄 삭제할 수 있게 준비.
- 실제 원격 운영 데이터는 삭제하지 않음.

## 변경

- `supabase/seeds/qa_fixtures_cleanup_preview.sql`
  - read-only 삭제 대상 count preview.
  - QA 학생 stable GoAlimi IDs: 9001 김민수, 9002 이서연, 9003 박지호, 7707 신성화.
  - QA 학생과 연결된 수업/진도/과제/코멘트/출결/결제/리포트/outbox/parse_logs/audits count 확인.
  - QA 교재는 실제 학생에게 배정돼 있지 않을 때만 삭제 대상으로 표시.
- `supabase/seeds/qa_fixtures_cleanup.sql`
  - destructive cleanup 본문.
  - exact name/ID guard: QA goalimi_student_id가 다른 이름으로 존재하면 abort.
  - QA parent ID가 non-QA 학생을 가리키면 abort.
  - audit delete trigger가 만든 lessons/payments delete audit까지 같은 transaction에서 삭제.
- 문서 sync:
  - `aidd_docs/fixtures/mvp-seed-data.md`: 정리 경로와 Bridge 재동기화 주의 추가.
  - `docs/09_DEPLOY.md`: §4.4 QA fixture 정리 절차 추가.
  - `docs/10_ACCEPTANCE_TEST.md`: Go-Live checklist에 QA fixture 정리 추가.
  - `aidd_docs/plans/claude-handoff-prompt.md`, `session-kickoff-prompt.md`, `mvp-build-plan.md`: cleanup 계획 연결.

## 검증

- Supabase changelog 확인: 최근 DB 관련 breaking change 중 본 작업에 영향 있는 항목 없음. 기존 운영 원칙(RLS/GRANT, Data API 노출 주의) 유지.
- `supabase db query --local --file supabase/seeds/qa_fixtures_cleanup_preview.sql` 통과.
- 로컬 Supabase 컨테이너에서 cleanup SQL의 `commit;`을 `rollback;`으로 바꿔 실행:
  - `sed 's/^commit;/rollback;/' supabase/seeds/qa_fixtures_cleanup.sql | docker exec -i supabase_db_GoLesson psql -U postgres -d postgres -v ON_ERROR_STOP=1`
  - 삭제 notice 정상 출력 후 `ROLLBACK`.
- rollback 후 preview count가 유지됨.

## 실행 주의

- 실제 삭제는 사용자 승인 후 별도 수행.
- 실행 전 Bridge를 멈추거나 GoAlimi의 테스트 학생(9001, 9002, 9003, 7707)을 먼저 비활성/삭제한다. 그렇지 않으면 Bridge가 학생/학부모/출결을 다시 가져올 수 있다.
- `7707 신성화`가 테스트 수신자일 때만 삭제한다.
- cleanup은 GoLesson DB만 정리한다. GoAlimi 데이터는 GoAlimi 쪽에서 별도 정리한다.
