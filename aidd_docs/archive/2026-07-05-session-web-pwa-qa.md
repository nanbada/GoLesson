# 2026-07-05 세션 핸드오프 — [5] Web PWA 운영 QA 준비

후속 상태(2026-07-06): 원격 migration/functions 배포, T10/T13/T4-T5/핵심 DB 전이 검증, T12 Bridge/GoAlimi 하니스까지 완료됐다. 최신 Claude handoff는 `aidd_docs/plans/claude-handoff-prompt.md`, 최신 실행 기록은 `aidd_docs/memory/internal/2026-07-06-session-t12-bridge-harness.md`를 우선한다.

## 완료

- Supabase skill 기준으로 운영 프로젝트 확인:
  - `web/.env` 공개 URL/key의 project ref = `dqibhcadjxqmvahcewfn`.
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY` 값은 legacy anon JWT에서 publishable key(`sb_publishable_...`)로 교체됨. env 변수명은 기존 코드 호환을 위해 유지.
  - linked Supabase project = `GoLesson`, region `ap-northeast-2`, status `ACTIVE_HEALTHY`.
  - Auth user 1건과 owner profile 1건 연결됨.
- `supabase/seeds/prod_app_settings_seed.sql` 운영값 반영:
  - `academy_name = 루트원학원`
  - `report_greeting`, `report_closing` 기본 문구
  - `goalimi_admin_url`은 실제 학원 PC/LAN 주소 미확정이라 seed 제외. 설정 화면에서 입력.
- 운영 DB에 app_settings seed 적용 및 검증:
  - `academy_name`, `report_greeting`, `report_closing` 3건 확인.
- 운영 DB에 `supabase/seeds/qa_fixtures_seed.sql` 적용:
  - students 4, parents 4, textbooks 5, enrollments 5, student_textbooks 7, schedule_slots 9, lessons 2, lesson_progress 2, homeworks 2, attendance 6, payments 2, payment_items 3.
  - seed 파일을 실제 멱등으로 수정한 뒤 원격 DB에 재실행, 카운트 유지 확인.
- anon REST 접근 검증:
  - `app_settings`, `students` anon select 모두 `42501 permission denied`.
- Web PWA 검증:
  - `npm --prefix web run typecheck` 통과.
  - `npm --prefix web audit --omit=dev` → `found 0 vulnerabilities`.
  - publishable key 반영 후 `set -a; . ./web/.env; set +a; npm --prefix web run build` 통과, `/` static route 확인.
  - `web/out`을 `python3 -m http.server 3001 --bind 127.0.0.1`로 서빙.
  - `http://127.0.0.1:3001` 320x720 로그인 화면: 가로스크롤 없음, email/password input 44px, 로그인 버튼 44px, console error 없음.
- Supabase Auth 이메일 가입 비활성화 확인:
  - 공식 문서 기준: Auth General Configuration의 "Allow new users to sign up"을 끄면 기존 사용자만 로그인 가능.
  - 사용자 제공 스크린샷 `/Users/nanbada/Desktop/스크린샷 2026-07-05 오전 12.09.23.png` 확인: URL `supabase.com/dashboard/project/dqibhcadjxqmvahcewfn/auth/providers`, `Allow new users to sign up` 토글 off.
  - `supabase config push`는 로컬 `supabase/config.toml`의 dev 설정(`enable_signup=true`, `site_url=http://127.0.0.1:3000`)을 운영에 덮을 위험이 있어 실행하지 않음.
- Claude 전환용 문서 sync:
  - `aidd_docs/plans/claude-handoff-prompt.md` 추가. 다음 세션 단축 프롬프트로 사용.
  - `aidd_docs/plans/session-kickoff-prompt.md`, `mvp-build-plan.md`, `docs/09_DEPLOY.md`, `README.md`, `web/.env.example` 최신 상태 반영.
  - `docs/09_DEPLOY.md` 현재 상태에서 Auth signup/profile/app_settings/QA fixture 완료, publishable key 권장, 남은 QA 항목을 명시.

## 미완료 / 다음

- 운영 계정 로그인 후 docs/10 T1~T3·T5·T7·T9·T11 수동 QA:
  - 로그인 비밀번호/세션이 없어 authenticated UI QA는 미진행.
  - 고정 fixture 스케줄은 월~금만 있음. 2026-07-05 일요일에는 T1 "오늘 화면 수업 표시" 판정 불가. 2026-07-06 월요일부터 자연 판정하거나 임시 일요일 스케줄을 추가 후 QA 종료 시 제거.
  - T11 GoAlimi 바로가기는 실제 `goalimi_admin_url`이 필요함.
- T5-2 AI 의견 검증은 OpenAI key Supabase secret 설정 여부 확인 필요. 없으면 수치·구조까지만 판정.

## 주의

- `supabase/seeds/qa_fixtures_seed.sql`은 이제 재실행 가능하지만, QA 진행 중 사람이 만든 수업/결제 데이터와 혼합될 수 있으므로 필요할 때만 실행한다.
- service_role key는 프론트/env/git/docs에 넣지 않는다.
- 커밋/푸시 안 함.

## 수동 QA 실행 결과 (2026-07-05 오후)

운영 계정 로그인 후 docs/10 §1 실행. 원장(사람)이 실기기/브라우저 조작, Claude가 Supabase MCP로 DB 상태 독립 검증.

- **T7 수강료** ✅ — 2026-06 월합계 600,000원(카드 400,000 / 현금 200,000)이 화면·DB·수기계산 일치. 수정·삭제 시 audits 전후기록: `t_payments_audit`(AFTER UPDATE OR DELETE)가 before/after jsonb 기록. 클라이언트 삭제로 결제 row_id=4의 before 스냅샷(audits id=10, before=현금/2026-07-05/student_id=2, after=null) 검증. 잔여 테스트행 id=4는 화면에서 삭제·정리 완료(2026-07 결제 0건). 참고: audit before는 payments 행 수준이라 금액(payment_items)은 미포함 — 스키마 설계상 정상.
- **T5 리포트** ✅(수치·구조) — draft 수치가 실데이터 수기대조와 일치. T5-2 AI 의견은 `OPENAI_API_KEY`(Supabase secret) 미설정 시 보류.
- **T9 모바일·네트워크** — 코드레벨 ✅(Codex): 320px 무가로스크롤(app-shell max-width+반응형 1fr), 44px 터치타깃, PWA manifest/SW 설치요건 충족, `useStoredState` localStorage 초안 보존, 실패 시 초안 자동 유지. 실기기(홈설치 standalone·비행기모드 초안 보존·복귀 재제출) 확인 대기. ⚠ 오프라인 테스트 전 real-env 재빌드 + SW 캐시 클리어 선행.
- **T11 계정·바로가기** — 코드레벨 ✅(Codex): GoAlimi 바로가기 `<a target="_blank" rel="noopener" href={settings.goalimi_admin_url}>`, iframe 0건. 동시세션은 Supabase 기본 허용(강제 단일세션 코드 없음). "학원 네트워크에서만" 안내는 항상 표시되는 정적 텍스트(IP 차단 아님 — 스펙의 '페이지 미도달' 기대와 일치). 실기기(PC+폰 동시·새 탭·학원 밖 미도달) 확인 대기.
- **T1 오늘 화면** — 대기. 고정 fixture는 월~금이라 일요일 판정 불가. 2026-07-06 월요일부터.
- **T2 진도 경계·T3 과제 이월** — 실행 대기(미판정).

### 발송 안전 변경 (이 세션)

- ready 본문 잠금 트리거(`20260705120000`)를 잠깐 적용 후 **같은 날 되돌림**(`20260705130000`). 사유: BR-506이 ready 본문을 sent 전까지 클라이언트 수정 허용(1인 자기검토 — ready-lock 과설계). 또한 Bridge는 outbox 스냅샷(`bridge.py:296`)을 보내고 live body를 재독하지 않아 승인 후 편집이 발송에 도달하지 못함(무해). 최종 트리거는 sent-only 불변만 강제. Codex 리뷰 + 독립 검증으로 확인.
- `web/app/page.tsx` `edgeError()` 헬퍼 유지 — Edge 오류 메시지(예: "이미 발송 대기 중입니다.")를 사용자에게 노출.

### 다음

- 07-06 월요일: T1, 이어서 T2·T3 실행.
- 실기기 T9·T11(홈설치·오프라인·PC/폰 동시세션·GoAlimi 새 탭 — 실제 goalimi_admin_url 입력 후).
- [5] 종료 시 이월 문서주석: docs/10 T2-3 N/A 표기, T2-2 문구 정리.
