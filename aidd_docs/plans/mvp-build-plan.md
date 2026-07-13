# MVP 구축 계획 (빌드 순서)

원칙: 의존성 역순으로 아래부터 쌓는다. 각 단계는 완료 기준(검증)을 통과해야 다음 단계 착수. 문서 근거는 `docs/00~11`.

```
[1] GoAlimi API 확장 ──┐
                      ├→ [4] Bridge → [6] QA·Go-Live
[2] Supabase 기반  ────┤
      └→ [3] Edge Functions ─→ [5] Web PWA ─┘
```

[1]과 [2]는 병행 가능. [5]는 [2] 완료 후 [3]·[4]와 병행 가능.

## 현재 상태 (2026-07-10)

| 단계 | 상태 |
|---|---|
| [1] GoAlimi API 확장 | 완료 — GoAlimi `f9df186` push됨. mock 모드 T12-1~5 + 재기동 복구 검증 통과. 장문 900자 실측만 Go-Live 체크리스트로 이월 (08 §3.4) |
| [2] Supabase 기반 | 완료 — 서울 프로젝트 마이그레이션 적용 + T10 원격 검증 27/27 통과 |
| [3] Edge Functions | 완료 — 3개 함수 원격 배포(version 3 ACTIVE) + smoke + 원격 T4/T5 하니스 10/10 통과 |
| [4] Bridge | 완료 — `bridge/` 구현, fake client 단위테스트 9개 통과, GoAlimi Mock + 로컬 Supabase 통합 하니스로 T6·T8·T12-6~7 통과 |
| [5] Web PWA | 진행 중 — 구현·운영 env/seed/Auth gate·원격 로그인 smoke 완료. 시간대별 약 5명 그룹·학생별 오늘 진도/과제·코칭 현황을 오늘 화면에 반영하고 리포트를 더보기로 이동(2026-07-10 typecheck/build/diff-check 통과). T5 수치·구조와 T7 수강료 통과, T1/T2/T3/T7 핵심 DB 전이 원격 RPC 11/11 통과, T9·T11 코드레벨 통과. 남은 것은 새 오늘 화면 실폰 검증·OpenAI 의견·실발송·실동기화·실기기 네트워크 |
| [6] QA·Go-Live | 대기 |

남은 업무 체크리스트(SSOT): `aidd_docs/plans/remaining-work.md` — [5] 잔여와 [6] 전체를 이 보드로 관리한다.

## [1] GoAlimi API 확장 — GoAlimi 프로젝트에서 별도 작업

- 범위: `custom_messages` 테이블 + `/api/notify/custom` 2개 + `/api/golesson/*` read 3개 (docs/08 §3).
- 필수 설계 조건: 결과 갱신 경로 분리, in-flight 식별자 공간 분리, student_id 기준 발송 시점 수신자 재조회, 127.0.0.1 제한 (08 §3.2).
- 검증: Mock 모드(`GOALIMI_MOCK_SENDER=1`)로 T12-1~5. 장문(900자) 실측은 신성화 계정으로 1회 (08 §3.4).
- 주의: GoAlimi 절대 규칙 준수 — restart.bat만, kakao_pc.py 무변경, 문서 동기화(REFERENCE §8·§9).

## [2] Supabase 기반

- 범위: 프로젝트 생성 → migrations(DDL 04 §2 + 트리거·RPC 04 §3 + RLS·GRANT 04 §5) → profiles·app_settings 시드 (09 §4.1).
- 검증: T10 전 항목 (anon 차단, A군 쓰기 거부, parse_logs 컬럼 예외, sent 불변 트리거, claim_outbox 권한).

## [3] Edge Functions

- 범위: parse-batch(07 §1) → generate-report(07 §2) → enqueue-report (05 §2).
- 검증: fixtures seed 적재 후 초기 고정 문장 10개 T4 전수 통과(regex 줄 AI 미호출 확인 포함), T5-1~3. 인터뷰로 20개 확정 후 19/20 이상을 최종 기준으로 유지.

## [4] Bridge

- 범위: claim_outbox 발송 루프(+goalimi_custom_id 저장, stale 회수) · 동기화 3종 · 출결 일일 대사 · 야간 백업 · Task Scheduler 등록 (08 §4, 05 §3, 09 §4.3).
- 검증: `python3 -m unittest bridge.tests.test_bridge` 통과, `python3 -m bridge.tests.integration_bridge --config bridge/bridge_config.json --goalimi-repo /Users/nanbada/projects/GoAlimi --port 8000` 통과. 통합 하니스 범위는 T6 Bridge 항목, T8, T12-6~7이며 GoAlimi 임시 DB + MockSender를 사용한다.

## [5] Web PWA

- 범위: 로그인 → 오늘 시간대 블록·학생별 코칭 현황 → 코칭 기록 → 학생 → 빠른입력 → 더보기(리포트·발송현황·수강료·교재·바로가기·설정). 리포트는 2주/월 단위 저빈도 일괄 작업.
- 검증: T1~T3, T5, T7, T9, T11. 30초 기록(REQ-902)은 실기기(폰)로 측정.
- 운영 QA 전제(2026-07-06 확인): `web/.env`의 공개 URL/key는 `dqibhcadjxqmvahcewfn` 운영 프로젝트와 일치하고 key 값은 publishable key(`sb_publishable_...`) 사용, owner profile 1건 존재, `app_settings.academy_name=루트원학원`, QA fixture는 학생 4·교재 5·스케줄 9·결제 2건 적재, Auth `Allow new users to sign up` off. `supabase/seeds/qa_fixtures_seed.sql`은 원격 drift 보정 후 재실행됨.
- QA 결과(2026-07-06): T10 원격 27/27, T13 원격 10/10, T4/T5 함수 원격 10/10, T1/T2/T3/T7 핵심 DB 전이 원격 RPC 11/11 통과. T7 수강료 월합계=수기계산 통과(2026-06 600,000/카드 400,000/현금 200,000), 수정·삭제 audits 전후기록 검증. T5 리포트 수치·구조 실데이터 일치. OpenAI 관련 Supabase secrets 3개(`OPENAI_API_KEY`, `OPENAI_MODEL_PARSE`, `OPENAI_MODEL_REPORT`) 등록 완료. T5-2 AI 의견은 OpenAI `429 insufficient_quota`로 fallback 처리되어 quota/billing 복구 후 재검증 필요. T9·T11 코드레벨 검증 통과. UX subagent 리뷰 후 `npm --prefix web run typecheck`, `npm --prefix web run build`, `git diff --check` 통과. T12 Bridge/GoAlimi 로컬 하니스 통과. Cloudflare Pages `golesson.pages.dev` 배포 완료.
- 남은 확인: T1/T2/T3 실제 손 입력 시간 측정, T5-2 OpenAI AI 의견 품질(quota/billing 복구 후), T6 실제 카톡 발송·600~900자 온전성·21시 window, T8 실제 GoAlimi 10분 동기화, T9 실폰 설치/오프라인, T11 실기기 다중세션/GoAlimi 새 탭.

## [6] QA·Go-Live

- fixtures 초기화 → 10_ACCEPTANCE T1~T13 전체 → Go-Live 체크리스트 (§2).
- 파일럿 종료 후 QA fixture 정리: `supabase/seeds/qa_fixtures_cleanup_preview.sql`로 count 확인 → 사용자 승인 후 `supabase/seeds/qa_fixtures_cleanup.sql` 실행. 실행 전 Bridge 중지 또는 GoAlimi 테스트 학생 비활성/삭제 필요.
- 파일럿 진입: 1주차 기존 방식 병행 → 2주차 첫 리포트 실발송은 소수 학생부터 (10 §2).

## 단계별 산출물 위치

| 단계 | 저장소 경로 |
|---|---|
| [1] | GoAlimi 저장소 (이 저장소 아님) |
| [2] | `supabase/migrations/` |
| [3] | `supabase/functions/{parse-batch,generate-report,enqueue-report}/` |
| [4] | `bridge/` |
| [5] | `web/` |
| [6] | 체크 결과를 `aidd_docs/memory/internal/`에 기록 |
