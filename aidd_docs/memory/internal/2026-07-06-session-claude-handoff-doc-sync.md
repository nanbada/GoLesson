# 2026-07-06 Claude handoff 문서 동기화

## 목표

- Claude handoff용 자료를 최신 QA 상태로 정리.
- 2026-07-05 handoff의 stale 항목(T1~T3 대기, T12 blocked, 원격 마이그레이션/함수 상태)을 2026-07-06 검증 결과와 맞춤.

## 변경

- `aidd_docs/plans/claude-handoff-prompt.md`
  - 다음 Claude 세션 Goal을 `[5] Web PWA 운영 수동 QA`에서 `QA·Go-Live 실기기 마감`으로 변경.
  - 이미 완료된 원격 QA와 남은 실기기/운영 PC QA를 분리.
  - 필수 파일 포인터를 최신 메모리(`2026-07-06-session-t12-bridge-harness.md`) 중심으로 축소.
- `aidd_docs/plans/codex-handoff-prompt.md`
  - 2026-07-06 기준 코드리뷰/QA 최종 상태로 재작성.
  - T12 blocked 기록 제거, T10/T13/T4-T5/핵심 DB 전이 결과 반영.
- `aidd_docs/plans/session-kickoff-prompt.md`
  - 현재 상태를 2026-07-06 기준으로 정리.
  - 다음 세션용 Goal을 실기기/운영 PC QA 마감으로 변경.
- `aidd_docs/plans/mvp-build-plan.md`
  - [2]/[3]/[4]/[5] 상태와 검증 수치 갱신.
  - [6] Go-Live 범위를 T1~T13으로 갱신.
- `aidd_docs/plans/handoff-codex-bridge.md`
  - 상단 상태를 단위테스트 9개와 최신 Claude handoff 포인터로 갱신.
- `docs/09_DEPLOY.md`
  - 원격 migration/functions, T10/T13/T4-T5/핵심 DB 전이 상태 갱신.
  - Bridge 개발 하니스 Python 3.12/greenlet 주의 추가.
- `docs/10_ACCEPTANCE_TEST.md`
  - T12 하니스 Python 3.12 주의 추가.
  - T13 실행 범위를 로컬/명시 env 원격으로 정정.
  - 2026-07-06 자동/반자동 검증 상태 요약 추가.
- `supabase/tests/t10-access.sh`, `supabase/tests/t13-transaction-rpc.sh`
  - 주석을 로컬 전용에서 원격 env 실행 가능으로 정정.
- `aidd_docs/memory/internal/2026-07-05-session-web-pwa-qa.md`
  - 최신 handoff 우선 안내 추가.
- `aidd_docs/memory/internal/2026-07-05-session-project-review-qa.md`
  - T12 blocked 항목을 후속 완료로 정정.

## 검증

- stale 검색:
  - `rg -n "2026-07-05 일요일|수동 QA\\(2026-07-05\\)|T1은 07-06|T12.*requests|원격 T10 24|마이그레이션 4개 원격|version=1|version 1|단위테스트 7개|Web PWA 실계정 수동 QA" docs aidd_docs/plans supabase -g '!node_modules'`
  - 결과 없음.
- `git diff --check` 통과.
- `bash -n supabase/tests/t10-access.sh supabase/tests/t13-transaction-rpc.sh supabase/tests/t4-t5-functions.sh` 통과.

## 남은 일

- 커밋/푸시는 하지 않았다.
- 남은 실제 QA는 `aidd_docs/plans/claude-handoff-prompt.md`의 Goal을 따른다:
  - T1/T2/T3 실폰 시간 측정.
  - T5-2 OpenAI 의견.
  - T6 실제 카톡 발송/장문 온전성/21시 window.
  - T8 실제 GoAlimi 10분 동기화.
  - T9 실폰 설치/오프라인.
  - T11 PC·폰 동시세션/GoAlimi 새 탭.
