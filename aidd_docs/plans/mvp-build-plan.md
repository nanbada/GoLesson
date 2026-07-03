# MVP 구축 계획 (빌드 순서)

원칙: 의존성 역순으로 아래부터 쌓는다. 각 단계는 완료 기준(검증)을 통과해야 다음 단계 착수. 문서 근거는 `docs/00~11`.

```
[1] GoAlimi API 확장 ──┐
                      ├→ [4] Bridge → [6] QA·Go-Live
[2] Supabase 기반  ────┤
      └→ [3] Edge Functions ─→ [5] Web PWA ─┘
```

[1]과 [2]는 병행 가능. [5]는 [2] 완료 후 [3]·[4]와 병행 가능.

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
- 검증: fixtures seed 적재 후 고정 문장 20개 T4 (regex 줄 AI 미호출 확인 포함), T5-1~3.

## [4] Bridge

- 범위: claim_outbox 발송 루프(+goalimi_custom_id 저장, stale 회수) · 동기화 3종 · 출결 일일 대사 · 야간 백업 · Task Scheduler 등록 (08 §4, 05 §3, 09 §4.3).
- 검증: T6 전 항목(발송·멱등·재발송·시간창), T8, T12-6~7 (crash 회수 = 이중발송 0건).

## [5] Web PWA

- 범위: 로그인 → 오늘 → 수업 → 학생 → 빠른입력 → 리포트 → 발송현황 → 수강료 → 교재 → 바로가기 → 설정 (03 화면 순서 = 사용 빈도 순).
- 검증: T1~T3, T5, T7, T9, T11. 30초 기록(REQ-902)은 실기기(폰)로 측정.

## [6] QA·Go-Live

- fixtures 초기화 → 10_ACCEPTANCE T1~T12 전체 → Go-Live 체크리스트 (§2).
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
