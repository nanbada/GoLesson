# 세션 킥오프 프롬프트 (Claude Code)

전제: Fable 5 = 메인 모델(/model, reasoning effort max), /agents로 deep-reasoner(Opus)·fast-worker(Sonnet) 생성, Codex 플러그인 사용 가능. 작성 원칙: **Goal은 docs/10의 T항목으로 검증 가능하게, Context는 파일 포인터만** 둔다.

토큰 제한이 빡빡하면 `aidd_docs/plans/claude-handoff-prompt.md`의 단축 프롬프트를 우선 사용한다.

## 1. 현재 상태 (2026-07-06)

- [1] GoAlimi API 확장 완료: GoAlimi `f9df186`, mock 모드 T12-1~5 + 재기동 복구 검증 통과. 장문 900자 실측은 Go-Live에서 확인.
- [2] Supabase 기반 완료: 서울 프로젝트 `dqibhcadjxqmvahcewfn`, 마이그레이션 local/remote 일치, 원격 T10 27/27 통과.
- [3] Edge Functions 완료: `parse-batch`, `generate-report`, `enqueue-report` 원격 배포 version 3 ACTIVE, 원격 T4/T5 하니스 10/10 통과.
- [4] Bridge 완료: `bridge/` 구현, 단위테스트 9개, GoAlimi Mock + 로컬 Supabase 통합 하니스 T6·T8·T12-6~7 통과.
- [5] Web PWA 진행 중: 구현·정적 빌드·운영 env/seed/Auth gate·원격 로그인 smoke 완료, Cloudflare Pages `https://golesson.pages.dev` 배포 완료. UX subagent 리뷰 반영(typecheck/build/diff-check 통과). T5 수치·구조, T7 수강료, T1/T2/T3/T7 핵심 DB 전이는 통과. T5-2 AI 의견은 OpenAI `429 insufficient_quota` 해소 후 재검증. 남은 것은 실폰/운영 PC에서만 판정 가능한 항목.

최신 근거:
- `aidd_docs/plans/remaining-work.md` (남은 업무 보드)
- `aidd_docs/memory/internal/2026-07-06-session-t12-bridge-harness.md`
- `aidd_docs/memory/internal/2026-07-06-session-ux-subagent-review.md`
- `aidd_docs/archive/2026-07-05-session-project-review-qa.md`
- `aidd_docs/plans/mvp-build-plan.md`
- `docs/09_DEPLOY.md`
- `docs/10_ACCEPTANCE_TEST.md`

## 2. 다음 세션용 — QA·Go-Live 실기기 마감

```
Goal: GoLesson MVP 출시 전 남은 실기기/운영 PC QA 완료.

완료 기준:
- T1/T2/T3: 실제 폰으로 오늘 수업 시작→진도→과제→완료를 수행하고 REQ-902 30초 조작 시간을 측정.
- T5-2: OpenAI quota/billing 복구 후 AI 의견 품질 확인. 현재 secret은 보이나 OpenAI `429 insufficient_quota`로 fallback 처리됨.
- T6: 테스트 학생 7707 신성화로 실제 Bridge/GoAlimi/카톡 발송, dedupe, GoAlimi down recovery, 21시 window 확인.
- T8: 실제 GoAlimi 등록/비활성화가 Bridge 10분 주기 안에 반영되는지 확인.
- T9: 실제 모바일 홈설치·standalone·비행기모드 입력 보존·복귀 재제출 확인.
- T11: PC/폰 동시 세션, GoAlimi 새 탭, 학원 밖 미도달 안내 확인.
- QA fixture cleanup: 파일럿 종료 시점에는 preview SQL로 count 확인 후 cleanup SQL 실행 계획만 기록한다. 실제 삭제는 사용자 승인 후 별도 수행.

Context: 설계 SSOT docs/00~11 (01 > 06 > 상세). 프론트는 Next 정적 export 유지. 서버 로직은 Supabase Edge Functions, 일반 CRUD는 supabase-js+RLS.
필수 파일: CLAUDE.md, aidd_docs/plans/remaining-work.md, aidd_docs/plans/claude-handoff-prompt.md, aidd_docs/memory/internal/2026-07-06-session-ux-subagent-review.md, aidd_docs/memory/internal/2026-07-06-session-t12-bridge-harness.md, docs/10_ACCEPTANCE_TEST.md, docs/09_DEPLOY.md §4.3.
주의: 커밋/푸시는 요청 전 금지. service_role/sb_secret/OpenAI 키를 채팅·문서·git에 남기지 않는다. supabase config push 금지. 발송 테스트는 7707 신성화만. QA fixture 삭제는 `supabase/seeds/qa_fixtures_cleanup_preview.sql` → `supabase/seeds/qa_fixtures_cleanup.sql` 순서이며, 실행 전 Bridge 중지 또는 GoAlimi 테스트 학생 비활성/삭제가 필요하다.

You're the lead. Show the shortest executable QA plan first, then execute.
```

## 3. 완료된 단계 참고 — GoAlimi API 확장

```
Goal: GoLesson 연동용 GoAlimi API 확장 — /Users/nanbada/projects/GoLesson/docs/08_GOALIMI.md §3 명세 구현.
custom_messages 테이블 + POST·GET /api/notify/custom + GET /api/golesson/{students,parents,attendance}.
완료 기준: GoAlimi mock 모드 T12-1~5 통과, REFERENCE.md §8 동기화.
```

## 4. 완료된 단계 참고 — Bridge

```
Goal: aidd_docs/plans/mvp-build-plan.md의 [4] Bridge 완료.
완료 기준: docs/10_ACCEPTANCE_TEST.md T6 Bridge 항목, T8, T12-6~7 로컬/Mock 검증 통과.
검증 명령: Python 3.12 venv에서 `python -m bridge.tests.integration_bridge --config <local-config> --goalimi-repo /Users/nanbada/projects/GoAlimi --port 8000`.
주의: 하니스는 원격 Supabase 실행을 거부한다. GoAlimi async startup에 greenlet이 필요할 수 있다.
```

## 5. 범용 템플릿

```
Goal: aidd_docs/plans/mvp-build-plan.md의 [N단계] — [산출물 한 줄].
완료 기준: docs/10_ACCEPTANCE_TEST.md [해당 T항목] 통과.

Context: 설계 SSOT는 docs/00~11 (01 > 06 > 상세). CLAUDE.md 절대 규칙 준수.
직전 상태: aidd_docs/memory/internal/ 최신 핸드오프. 남은 업무: aidd_docs/plans/remaining-work.md.

You're the lead. Show the shortest executable plan first, then execute.
```
