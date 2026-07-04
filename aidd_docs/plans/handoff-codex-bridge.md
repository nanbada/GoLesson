# Handoff 프롬프트 — [4] Bridge 구현 (GPT Codex용)

> 상태: 완료됨. Codex가 `bridge/` 구현, 단위테스트 7개, GoAlimi Mock + 로컬 Supabase 통합 하니스 T6·T8·T12-6~7을 완료했다. 이 문서는 [4] 착수 당시의 과거 인수인계 기록이며, 새 세션은 `aidd_docs/plans/session-kickoff-prompt.md`의 [5] Web PWA 프롬프트를 사용한다.

아래 구분선 안쪽 전체를 Codex에 붙여넣는다. (작성 2026-07-04, Fable 세션 — 토큰 한도로 인계)

---

너는 GoLesson 프로젝트(`/Users/nanbada/projects/GoLesson`)의 시니어 엔지니어다.
소규모 초등 학원(원장 1 + 강사 1~3, 학생 10~30) 운영도구이며 ERP가 아니다.
빌드플랜 [4] **Bridge**(학원 PC 워커)를 구현한다. 저장소 루트의 `CLAUDE.md`가 최상위 지침이다.

## 0. 먼저 읽을 것 (이 순서로)

1. `CLAUDE.md` — 절대 규칙 (특히 발송 안전·비밀키 금지선·오버엔지니어링 금지)
2. `aidd_docs/memory/internal/2026-07-04-session-goalimi-api.md` — 직전 세션 핸드오프 ([1] 완료 상태·발송 안전 설계 확정 근거. **재논의 금지**)
3. `docs/08_GOALIMI.md` §4(Bridge 명세)·§5(동기화 정합성) + §3(GoAlimi API — 구현 완료됨)
4. `docs/05_API_SPEC.md` §3 — Bridge ↔ Supabase 계약 (이번에 확정 커밋된 최신본)
5. `docs/04_DATABASE.md` §3 — `claim_outbox` RPC 시그니처
6. `docs/09_DEPLOY.md` §4.3 — 학원 PC 설치 절차
7. `docs/10_ACCEPTANCE_TEST.md` — T6, T8, T12-6~7 (완료 기준)
8. `docs/06_BUSINESS_RULE.md` — BR-500대(발송)·BR-700대(동기화)

## 1. 현재 상태 (2026-07-04 기준, 전부 검증 완료)

- [1] GoAlimi API: **완료·push됨** — `github.com/nanbada/GoAlimi` 커밋 `f9df186`.
  `POST /api/notify/custom`(dedupe_key 멱등, 재POST는 절대 재큐잉 안 함),
  `GET /api/notify/custom/{id}`(status pending|sending|sent|failed),
  `GET /api/golesson/students|parents|attendance?since_id=`. 전부 127.0.0.1 전용.
  mock 모드 T12-1~5 + 재기동 복구 검증 통과.
- [2] Supabase: 완료 — 서울 프로젝트 `dqibhcadjxqmvahcewfn`, 마이그레이션 4/4 적용, T10 24/24 통과.
- [3] Edge Functions: 완료 — parse-batch·generate-report·enqueue-report 원격 배포됨.
- GoLesson 계약 문서 확정 커밋: `11568f7` (docs/05 §3 + docs/08 §3).
- [5] Web PWA는 미착수 — 테스트 시 outbox 행은 UI 대신 SQL/REST로 직접 만든다(아래 §4).

## 2. 작업 지시 — `bridge/` 신규 개발 (docs/08 §4가 SSOT)

단일 Python 스크립트 + 설정 파일. 외부 의존은 `requests` 정도만. 프레임워크·큐 라이브러리·비동기 금지(60초 폴링 루프면 충분한 규모다).

```
bridge/
  bridge.py                  메인 루프
  bridge_config.example.json 플레이스홀더만 (실제 키 절대 금지 — repo는 PUBLIC)
  run_bridge.bat             ASCII 전용, %~dp0, Task Scheduler ONLOGON용
  logs/                      bridge.log (UTF-8, 일 로테이션, 14일 보관) — .gitignore
```

`bridge_config.json`(실키 포함)은 **.gitignore에 추가**하고 학원 PC에만 둔다. supabase_url, service_key, goalimi_base_url, poll_sec, send_window 필드.

메인 루프 (60초 주기):

1) **발송** (send_window 09~21시만 — 시간 외 pending은 실패가 아니라 대기):
   - `POST /rest/v1/rpc/claim_outbox` `{"p_limit": 5}` — pending→processing 원자 전환 + attempts 증가. **단순 PATCH 인출 금지** (attempts 연산 불가).
   - 건별: GoAlimi `POST /api/notify/custom` `{student_id(goalimi id), body, dedupe_key}` → 응답 id를 **즉시** `outbox.goalimi_custom_id`에 PATCH (crash 회수용).
     - 422 `no_primary_parent` → outbox `{status:'failed', error:'no_primary_parent'}` 즉시 종결.
   - `GET /api/notify/custom/{id}` 폴링(주기 내 최대 60초): `pending`·`sending`은 **비종결 — 다음 주기 계속 폴링**. `sent` → outbox sent+sent_at, report_id 있으면 reports도 sent 갱신. `failed` → outbox failed+error (reports는 갱신 안 함 — 실패 상태는 outbox만, BR-506).
2) **stale processing 회수** (기동 시 + 매 주기): 오래된 processing을 **임의로 failed 전환 금지**. ① goalimi_custom_id 있으면 상태 조회로 종결 ② 없으면 dedupe_key 멱등 재POST(재발송 안 일어남 — GoAlimi가 기존 행 반환만) → id 저장 후 ① ③ GoAlimi 다운이면 processing 유지.
3) **동기화** (10분마다): `/api/golesson/students`(비활성 포함)→upsert on goalimi_student_id, `/api/golesson/parents`→upsert on goalimi_parent_id, `/api/golesson/attendance?since_id=`→insert(goalimi_log_id unique 멱등). GoAlimi에서 사라진 학생은 active=false(하드 삭제 금지, BR-702).
4) **출결 일일 대사** (매일 1회): 최근 30일 goalimi_log_id 집합 대조 → GoAlimi에 없는 행을 GoLesson attendance에서 삭제 (GoAlimi는 hard delete 가능).
5) **야간 백업** (매일 03시): 전 테이블 `GET …?select=*` → `backup/YYYY-MM-DD/*.json`, 30일 보관.
6) **heartbeat**: 매 주기 `app_settings.bridge_last_poll_at` 갱신.

날짜/시간은 naive local(Asia/Seoul). `toISOString()`류 UTC 변환으로 날짜 밀림 금지.

## 3. 필수 조건 (위반 시 재작업)

- **자동 재발송 금지(BR-503)**: Bridge는 어떤 실패도 스스로 재전송하지 않는다. 재발송은 사람이 새 dedupe_key(v2)를 만드는 경로뿐.
- failed 중 `error='timeout'|'interrupted'`는 "발송 여부 불확실" — 그대로 기록만 한다(문서 docs/05 §3 참조). 그 외 코드(focus_not_acquired 등)는 발송 전 확정 실패.
- Supabase `service_role` 키는 bridge_config.json에만. **git·코드·로그·채팅 출력 금지** (repo PUBLIC). 존재 확인은 `grep -c`.
- GoAlimi 코드는 이 작업에서 변경하지 않는다 (필요 시 사용자에게 보고만).
- sent 리포트 본문 불변(DB 트리거가 강제) — Bridge는 body를 절대 만지지 않는다.
- 오버엔지니어링 금지: 재시도 백오프 라이브러리, 스레드풀, 설정 항목 확장 등 요구되지 않은 것 추가 금지.

## 4. 완료 기준 (검증 명령+출력 요약을 증거로 남길 것)

로컬 검증 환경: GoAlimi를 `GOALIMI_MOCK_SENDER=1`로 로컬 기동(발송 로그 `[MockSender]` 라인 수 = 물리 발송 횟수) + 로컬 Supabase. 하니스는 원격 Supabase 실행을 거부한다. service_role 키가 필요하면 **사용자에게 bridge_config.json 직접 배치를 요청**한다(키를 받아 적지 말 것).

- **T6 중 Bridge 항목**: outbox pending 행을 REST로 직접 insert(UI 미완) → 2분 내 processing→sent, reports sent 갱신 / GoAlimi 중지 후 발송 → pending 유지, 기동 후 다음 주기 발송 / send_window 밖 등록 → pending 대기.
- **T8**: GoAlimi에 학생 등록 → 10분 내 GoLesson 반영 / 비활성화 → active=false 전파.
- **T12-6**: GoAlimi 출결 1건 hard delete → 일일 대사 후 GoLesson에서도 제거.
- **T12-7**: 발송 도중 Bridge 강제 종료 → 재기동 → stale processing이 goalimi_custom_id 조회로 sent 반영, **`[MockSender]` 발송 로그 증가 0** (이중발송 0건).
- 멱등: 같은 outbox 행 이중 claim 불가(RPC가 보장) 확인 + dedupe 재POST 시 발송 로그 증가 0.

`.bat`·Task Scheduler 등록은 파일 작성까지만 (macOS 개발 환경 — 실등록은 학원 PC에서 사용자와 09 §4.3 절차로).

## 5. 마무리

- 문서와 다르게 구현한 것이 생기면 같은 작업에서 docs/05 §3·docs/08 §4를 고친다.
- 세션 종료 시 `aidd_docs/memory/internal/2026-07-XX-session-bridge.md`에 결정·증거·미완료를 기록한다.
- **커밋/푸시는 사용자가 요청할 때만.**
- 이 작업 범위 밖 (건드리지 말 것): OpenAI 키 설정, 강사 초대, GoLesson-old 프로젝트 삭제, 장문 900자 실발송(7707 계정 — Go-Live 체크리스트), Web PWA.

---
