# 남은 업무 보드 (Go-Live까지)

남은 업무의 SSOT. Claude(Opus/Fable)와 Codex 세션이 공동으로 관리한다.

## 관리 규칙

- 항목을 끝내면 같은 세션에서 `[x]` 체크하고 끝에 `(YYYY-MM-DD, 근거)`를 붙인다. 근거는 테스트 결과, 로그, 또는 memory 파일 경로.
- 새로 발견한 업무는 해당 섹션 끝에 ID를 이어서 추가한다.
- 항목은 지우지 않는다. 취소는 ~~취소선~~ + 사유.
- 이 목록을 다른 문서에 복제하지 않는다. 단계 요약은 `mvp-build-plan.md`, 시나리오 정의는 `docs/10_ACCEPTANCE_TEST.md` 담당.
- 실행 중 안전 규칙은 `AGENTS.md`를 따른다(발송은 7707 신성화만, 커밋/푸시·config push 금지 등).

## A. 배포 전제 (순서대로 — 실기기 QA 차단 요소)

- [x] A1. 프론트 Cloudflare Pages 배포 — 운영 env(publishable key)로 빌드 (docs/09 §4.2). 주의 1: 이전 로컬 빌드가 example.supabase.co를 번들에 구운 이력 있음 → real env 재빌드 + SW 캐시 클리어 확인. 주의 2: 빌드 Node 버전 고정 — `web/.node-version` 또는 Pages env `NODE_VERSION`으로 `web/package.json` engines(node>=20.9.0) 충족 보장. (2026-07-06, Cloudflare Pages deployment `1982fa86` success; `https://golesson.pages.dev` HTTP 200; deployed bundle contains `dqibhcadjxqmvahcewfn` and not `127.0.0.1:54321`/`example.supabase`; service-worker `golesson-shell-v2`)
- [x] A2. Supabase secrets `OPENAI_MODEL_PARSE`, `OPENAI_MODEL_REPORT` 등록 — 운영 모델 고정용. 코드 기본값과 동일하게 `gpt-4.1-nano`, `gpt-4.1-mini` 등록. `OPENAI_API_KEY`도 등록됨. (2026-07-06, `supabase secrets set` count=2, `supabase secrets list`에서 3개 이름 확인)
- [ ] A3. 학원 PC 설치: GoAlimi `f9df186` 이후로 최신화 + Bridge 설치(bridge_config.json, run_bridge.bat, Task Scheduler ONLOGON) (docs/09 §4.3) — B3/B4 전제. 주의: GoAlimi requirements.txt에 greenlet 명시 없음(T12 하니스에서 async 기동에 필요했음) → 최신화 후 기동 확인, 실패 시 PC venv에 greenlet>=3,<4 설치 또는 GoAlimi repo requirements 반영.
- [ ] A4. `app_settings.goalimi_admin_url` 설정 — 반드시 `http://<학원PC-LAN-IP>:8000/admin` 형식. 미설정 기본값 `http://127.0.0.1:8000/admin`(web/app/page.tsx:1167)은 폰에서 폰 자신을 가리켜 T11-3 검증 불가 — B6(T11-3) 전제.
- [ ] A5. OpenAI 계정 quota/billing 복구 — Edge Runtime에서 `OPENAI_API_KEY`는 보이나 OpenAI가 `429 insufficient_quota`를 반환해 AI 의견 생성이 fallback 처리됨. B2 전제.

## B. 실기기/운영 QA (docs/10 시나리오 기준)

- [ ] B1. T1/T2/T3 — 실폰에서 오늘 수업 시작→진도→과제→완료, REQ-902 30초 조작 시간 측정 (A1 후).
- [ ] B2. T5-2 — AI 의견이 입력 코멘트 밖의 사실·수치를 만들지 않는지 확인. 현재 차단: API key는 Edge Runtime에 보이나 OpenAI가 `429 insufficient_quota`를 반환해 `generate-report`가 `ai_used=false` fallback으로 성공함. quota/billing 복구 후 재검증(A5 후).
- [ ] B3. T6 — 7707 신성화 실발송: 카톡 수신, 600~900자 온전성, dedupe 409, GoAlimi 중지 시 pending 유지, 21시 이후 window (A3 후).
- [ ] B4. T8 — GoAlimi 학생 등록/비활성화가 Bridge 10분 주기 내 GoLesson에 반영 (A3 후).
- [ ] B5. T9 — 실폰 홈 화면 설치, standalone 실행, 비행기모드 입력 보존, 복귀 후 재제출 (A1 후).
- [ ] B6. T11 — PC·폰 동시 세션, GoAlimi 바로가기 새 탭, 학원 밖 네트워크 미도달 안내 (A4 후).
- [ ] B7. 장문 발송 실측(docs/10 §2 이월분) — 900자 리포트 카톡 수신 온전성 1회(신성화, docs/08 §3.4) (A3 후).

## C. Go-Live 체크리스트 잔여 (docs/10 §2)

- [ ] C1. 실데이터 이관 — 학생/교재/진도 초기값 입력.
- [ ] C2. 야간 백업 export 동작 확인 + 복구 리허설 1회.
- [ ] C3. Bridge 재부팅 자동 기동 확인 (Task Scheduler ONLOGON).
- [ ] C4. 강사 온보딩 — 계정 발급 + 기본 흐름 교육.
- [ ] C5. 파일럿 개시 — 1주차 기존 방식 병행, 2주차 첫 실발송은 소수 학생부터.

## D. 파일럿 중/후

- [ ] D1. 파서 20문장 확정(강사 인터뷰) 후 19/20 이상 검증 (docs/10 §3).
- [ ] D2. QA fixture 정리 — preview SQL count 확인 → 사용자 승인 → cleanup SQL 실행. 실행 전 Bridge 중지 또는 GoAlimi 테스트 학생(9001~9003, 7707) 비활성/삭제 필요.
- ~~D3. GoAlimi repo에 greenlet requirements 반영~~ — A3 전제로 승격(2026-07-06, Codex 검토: T12 하니스에서 필요 확인, GoAlimi requirements.txt에 greenlet 명시 없음).
