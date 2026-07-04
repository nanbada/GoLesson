# 세션 킥오프 프롬프트 (Claude Code)

전제: Fable 5 = 메인 모델(/model, reasoning effort max), /agents로 deep-reasoner(Opus)·fast-worker(Sonnet) 생성, Codex 플러그인 세팅(예정 시 Codex 위임 문구는 자동 생략됨 — CLAUDE.md Orchestration 참조).
작성 원칙: **Goal은 docs/10의 T항목으로 검증 가능하게, Context는 파일 포인터만**(본문 붙여넣기 금지 — 오케스트레이터 컨텍스트 절약).

## 1. 현재 상태 (2026-07-04)

- [2] Supabase 기반 완료: 서울 프로젝트 `dqibhcadjxqmvahcewfn`, 마이그레이션 적용, 원격 T10 통과.
- [3] Edge Functions 완료: `parse-batch`, `generate-report`, `enqueue-report` 구현·로컬 하니스 10/10·원격 배포·smoke 통과.
- [1] GoAlimi API 확장 완료: GoAlimi `f9df186`, mock 모드 T12-1~5 + 재기동 복구 검증 통과.
- GoLesson 계약 문서 최신 커밋: `11568f7` (`docs: GoAlimi 연동 계약 확정 — sending 상태·재기동 복구·실패 코드 구분 반영`).
- [4] Bridge 완료: `bridge/` 구현, 단위테스트 7개, GoAlimi Mock + 로컬 Supabase 통합 하니스 T6·T8·T12-6~7 통과.
- 다음 작업: [5] Web PWA 착수.

## 2. 완료된 단계 참고 — 빌드플랜 [1] GoAlimi API 확장

```
Goal: GoLesson 연동용 GoAlimi API 확장 — /Users/nanbada/projects/GoLesson/docs/08_GOALIMI.md §3 명세 구현.
custom_messages 테이블 + POST·GET /api/notify/custom + GET /api/golesson/{students,parents,attendance}.
필수 조건(08 §3.2): 결과 갱신 경로 분리, in-flight 식별자 공간 분리, student_id 기준 발송 시점 수신자 재조회, 127.0.0.1 제한.
완료 기준: GOALIMI_MOCK_SENDER=1로 GoLesson docs/10 T12-1~5 통과 + REFERENCE.md §8 동기화.

Context: GoAlimi 저장소의 CLAUDE.md 절대 규칙 최우선. GoLesson 추가 결정: 기존 기능을 제한/제약하지 않는 범위에서 GoAlimi 변경 가능하나, kakao_pc.py 직접 우회와 기존 발송 안전 훼손 금지.
GoLesson 쪽 계약 문서: /Users/nanbada/projects/GoLesson/docs/08_GOALIMI.md, docs/05_API_SPEC.md §3, docs/10_ACCEPTANCE_TEST.md T12.

You're the lead. Delegate reasoning to deep-reasoner, grunt work to fast-worker,
fresh-perspective problems to Codex. Show me your plan first, then execute.
```

## 3. 완료된 단계 참고 — 빌드플랜 [4] Bridge

```
Goal: aidd_docs/plans/mvp-build-plan.md의 [4] Bridge 완료.
claim_outbox 발송 루프, GoAlimi 동기화 3종, 출결 일일 대사, 야간 백업, run_bridge.bat/Task Scheduler 문서화.
완료 기준: docs/10_ACCEPTANCE_TEST.md T6, T8, T12-6~7 로컬/Mock 검증 통과.

Context: 설계 SSOT는 docs/00~11 (01 > 06 > 상세). 직전 상태: aidd_docs/memory/internal/ 최신 핸드오프.
핵심 문서: docs/08_GOALIMI.md §4·§5, docs/05_API_SPEC.md §3, docs/09_DEPLOY.md §4.3, aidd_docs/plans/handoff-codex-bridge.md.
검증 명령: `python3 -m unittest bridge.tests.test_bridge`, `python3 -m bridge.tests.integration_bridge --config bridge/bridge_config.json --goalimi-repo /Users/nanbada/projects/GoAlimi --port 8000`.

You're the lead. Delegate reasoning to deep-reasoner, grunt work to fast-worker,
fresh-perspective problems to Codex. Show me your plan first, then execute.
```

## 4. 다음 세션용 — 빌드플랜 [5] Web PWA (GoLesson 저장소)

```
Goal: aidd_docs/plans/mvp-build-plan.md의 [5] Web PWA 구현.
로그인 → 오늘 → 수업 → 학생 → 빠른입력 → 리포트 → 발송현황 → 수강료 → 교재 → 바로가기 → 설정 화면을 정적 export 유지 조건으로 구현한다.
완료 기준: docs/10_ACCEPTANCE_TEST.md T1~T3, T5, T7, T9, T11 수동 검증 가능 상태.

Context: 설계 SSOT는 docs/00~11 (01 > 06 > 상세). 프론트는 Next.js 정적 PWA, API Route/SSR/호스팅 전용 기능 금지. 일반 CRUD는 supabase-js + RLS, 서버 로직은 Supabase Edge Functions.
핵심 문서: docs/02_ARCHITECTURE.md, docs/03_UI_SPEC.md, docs/05_API_SPEC.md, docs/10_ACCEPTANCE_TEST.md.
직전 상태: aidd_docs/memory/internal/ 최신 핸드오프.

You're the lead. Delegate reasoning to deep-reasoner, grunt work to fast-worker,
fresh-perspective problems to Codex. Show me your plan first, then execute.
```

## 5. 범용 템플릿

```
Goal: aidd_docs/plans/mvp-build-plan.md의 [N단계] — [산출물 한 줄].
완료 기준: docs/10_ACCEPTANCE_TEST.md [해당 T항목] 통과.

Context: 설계 SSOT는 docs/00~11 (01 > 06 > 상세). CLAUDE.md 절대 규칙 준수.
직전 상태: aidd_docs/memory/internal/ 최신 핸드오프. [단계 핵심 문서 1~2개만 지정: 예 [3]=docs/05·07, [4]=docs/08·05, [5]=docs/03·02]

You're the lead. Delegate reasoning to deep-reasoner, grunt work to fast-worker,
fresh-perspective problems to Codex. Show me your plan first, then execute.
```
