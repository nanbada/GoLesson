# 세션 킥오프 프롬프트 (Claude Code)

전제: Fable 5 = 메인 모델(/model, reasoning effort max), /agents로 deep-reasoner(Opus)·fast-worker(Sonnet) 생성, Codex 플러그인 세팅(예정 시 Codex 위임 문구는 자동 생략됨 — CLAUDE.md Orchestration 참조).
작성 원칙: **Goal은 docs/10의 T항목으로 검증 가능하게, Context는 파일 포인터만**(본문 붙여넣기 금지 — 오케스트레이터 컨텍스트 절약).

## 1. 다음 세션용 — 빌드플랜 [2] Supabase 기반 (복사해서 사용)

```
Goal: aidd_docs/plans/mvp-build-plan.md의 [2] Supabase 기반 완성.
supabase/migrations/ 를 docs/04_DATABASE.md 그대로 구현한다
(DDL + updated_at·last_position·t_reports_immutable 트리거 + claim_outbox RPC + §5 RLS/GRANT).
로컬 supabase db reset으로 적용 검증 후 docs/10_ACCEPTANCE_TEST.md T10 접근 테스트 전 항목 통과.
완료 기준: T10 통과 + profiles·app_settings 시드 스크립트(docs/09 §4.1 순서 5·8) 준비.

Context: 설계 SSOT는 docs/00~11 (충돌 시 01_PRD > 06_BUSINESS_RULE > 상세).
CLAUDE.md 절대 규칙 준수 — 특히 오버엔지니어링 금지(사용자 5명), 비밀키 금지선, GoAlimi 읽기 전용.
직전 상태: aidd_docs/memory/internal/ 최신 핸드오프. QA seed: aidd_docs/fixtures/mvp-seed-data.md.
빌드플랜 [1](GoAlimi API 확장)은 별도 저장소 작업 — 이 세션 범위 아님, docs/08 §3 계약만 준수.

You're the lead. Delegate reasoning to deep-reasoner, grunt work to fast-worker,
fresh-perspective problems to Codex. Show me your plan first, then execute.
```

## 2. 빌드플랜 [1]용 — GoAlimi API 확장 (GoAlimi 저장소에서 실행)

```
Goal: GoLesson 연동용 GoAlimi API 확장 — /Users/nanbada/projects/GoLesson/docs/08_GOALIMI.md §3 명세 구현.
custom_messages 테이블 + POST·GET /api/notify/custom + GET /api/golesson/{students,parents,attendance}.
필수 조건(08 §3.2): 결과 갱신 경로 분리, in-flight 식별자 공간 분리, student_id 기준 발송 시점 수신자 재조회, 127.0.0.1 제한.
완료 기준: GOALIMI_MOCK_SENDER=1로 GoLesson docs/10 T12-1~5 통과 + REFERENCE.md §8 동기화.

Context: 이 저장소(GoAlimi)의 CLAUDE.md 절대 규칙 최우선 — 운영 중 실서비스, restart.bat만, kakao_pc.py 무변경.
GoLesson 쪽 계약 문서: /Users/nanbada/projects/GoLesson/docs/08_GOALIMI.md, docs/05_API_SPEC.md §3.

You're the lead. Delegate reasoning to deep-reasoner, grunt work to fast-worker,
fresh-perspective problems to Codex. Show me your plan first, then execute.
```

## 3. 범용 템플릿 (이후 단계 [3]~[6])

```
Goal: aidd_docs/plans/mvp-build-plan.md의 [N단계] — [산출물 한 줄].
완료 기준: docs/10_ACCEPTANCE_TEST.md [해당 T항목] 통과.

Context: 설계 SSOT는 docs/00~11 (01 > 06 > 상세). CLAUDE.md 절대 규칙 준수.
직전 상태: aidd_docs/memory/internal/ 최신 핸드오프. [단계 핵심 문서 1~2개만 지정: 예 [3]=docs/05·07, [4]=docs/08·05, [5]=docs/03·02]

You're the lead. Delegate reasoning to deep-reasoner, grunt work to fast-worker,
fresh-perspective problems to Codex. Show me your plan first, then execute.
```
