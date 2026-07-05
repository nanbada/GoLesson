# 세션 킥오프 프롬프트 (Claude Code)

전제: Fable 5 = 메인 모델(/model, reasoning effort max), /agents로 deep-reasoner(Opus)·fast-worker(Sonnet) 생성, Codex 플러그인 세팅(예정 시 Codex 위임 문구는 자동 생략됨 — CLAUDE.md Orchestration 참조).
작성 원칙: **Goal은 docs/10의 T항목으로 검증 가능하게, Context는 파일 포인터만**(본문 붙여넣기 금지 — 오케스트레이터 컨텍스트 절약).

토큰 제한이 빡빡하면 `aidd_docs/plans/claude-handoff-prompt.md`의 단축 프롬프트를 우선 사용한다.

## 1. 현재 상태 (2026-07-05)

- [2] Supabase 기반 완료: 서울 프로젝트 `dqibhcadjxqmvahcewfn`, 마이그레이션 적용, 원격 T10 통과.
- [3] Edge Functions 완료: `parse-batch`, `generate-report`, `enqueue-report` 구현·로컬 하니스 10/10·원격 배포·smoke 통과.
- [1] GoAlimi API 확장 완료: GoAlimi `f9df186`, mock 모드 T12-1~5 + 재기동 복구 검증 통과.
- GoLesson 계약 문서 최신 커밋: `11568f7` (`docs: GoAlimi 연동 계약 확정 — sending 상태·재기동 복구·실패 코드 구분 반영`).
- [4] Bridge 완료: `bridge/` 구현, 단위테스트 7개, GoAlimi Mock + 로컬 Supabase 통합 하니스 T6·T8·T12-6~7 통과.
- [5] Web PWA 1차 구현 완료: `web/` 정적 Next PWA, Supabase Auth/CRUD/Edge Function 호출 연결, audit/typecheck/static build 통과.
- [5] 운영 QA 전제 완료: `web/.env` 공개 env가 운영 프로젝트 `dqibhcadjxqmvahcewfn`와 일치, 공개 key는 publishable key(`sb_publishable_...`) 사용, owner profile 1건 존재, `app_settings.academy_name=루트원학원`, QA fixture seed 적재 및 멱등성 재실행 확인, Auth "Allow new users to sign up" off. 정적 산출물 320px 로그인 화면은 가로스크롤 없음·입력/버튼 44px·콘솔 오류 없음.
- [5] 남은 완료 판정: 운영 계정 로그인 후 docs/10 T1~T3·T5·T7·T9·T11 수동 QA.

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

## 4. 다음 세션용 — 빌드플랜 [5] Web PWA 실계정 수동 QA (GoLesson 저장소)

> [5]는 1차 구현·정적 빌드·모바일/데스크톱 렌더까지 완료. 남은 "완료" 판정은 운영 Supabase 실계정으로 `web/`를 띄워 docs/10 수동 시나리오를 통과시키는 것. 실행 주체는 사람(실기기 폰) — 자동 E2E는 MVP 기준 아님(CLAUDE.md).

```
Goal: aidd_docs/plans/mvp-build-plan.md의 [5] Web PWA 실계정 수동 QA 완료.
운영 Supabase 공개 env로 web/를 띄우고 docs/10_ACCEPTANCE_TEST.md §1의 T1~T3·T5·T7·T9·T11을 실기기(폰)로 통과시킨다.
완료 기준(전부 사람 판정): T1-6 기록 조작 합계 30초 이내(REQ-902, 실폰 측정) · T2 진도 경계 저장/거부 · T3 과제 이월 이력 2건 · T5 draft 수치가 실데이터 수기 대조 일치 · T7 수강료 월합계 일치+audits 전후기록 · T9 320px 무가로스크롤·홈설치·오프라인 입력보존 · T11 PC·폰 동시 세션 유지.

Context: 설계 SSOT docs/00~11 (01 > 06 > 상세). 프론트는 Next 정적 export 유지 — API Route/SSR 금지, 일반 CRUD는 supabase-js+RLS, 서버 로직은 Edge Functions 3개만 호출.
선행 게이트: ① web/.env 운영 NEXT_PUBLIC_SUPABASE_URL·ANON_KEY 확인됨. ANON_KEY 변수명에는 publishable key 사용 ② profiles owner 1건 + app_settings 운영 seed 확인됨 ③ aidd_docs/fixtures/mvp-seed-data.md 고정 seed 적재됨(교재·별칭·스케줄·직전 진도·과제·결제), `supabase/seeds/qa_fixtures_seed.sql` 재실행 카운트 유지 확인됨 ④ Auth 이메일 가입 비활성화 확인됨. 강사 초대는 실제 운영 필요 시 별도 진행. T5-2 AI 의견 검증은 OpenAI 키(Supabase secrets) 필요 — 없으면 T5는 수치·구조까지만.
핵심 문서: docs/03_UI_SPEC.md(0장 UI 규칙), docs/02_USER_FLOW.md, docs/10_ACCEPTANCE_TEST.md §1. 스키마 확인 시 supabase/migrations/*_init_schema.sql·*_rls_grant.sql.
직전 상태: aidd_docs/memory/internal/2026-07-05-session-web-pwa-qa.md.
범위 밖(→[6] Go-Live): T4 파싱·T6 실발송·T8 실동기화·T10 원격 RLS(이미 통과)·T12 GoAlimi 정합·장문 900자 실측(7707 계정). 이들은 Edge/Bridge/GoAlimi 계층에서 이미 Mock/원격 검증됨.
주의: 고정 fixture 스케줄은 월~금만 있음. 2026-07-05 일요일에는 T1 "오늘 화면 수업 표시" 판정 불가.

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
