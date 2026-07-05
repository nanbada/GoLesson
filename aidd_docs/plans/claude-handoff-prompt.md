# Claude Handoff Prompt — [5] Web PWA 운영 수동 QA

아래 블록을 Claude Code 새 세션 시작 프롬프트로 사용한다. 토큰 절약용 단축본이며, 세부 근거는 파일 포인터만 따른다.

```text
Goal: aidd_docs/plans/mvp-build-plan.md의 [5] Web PWA 실계정 수동 QA 완료.
운영 Supabase env와 고정 QA fixture가 준비된 상태에서 docs/10_ACCEPTANCE_TEST.md §1의 T1~T3·T5·T7·T9·T11을 실계정/실기기 기준으로 판정한다.

완료 기준:
- T1-6: 실폰에서 기록 조작 합계 30초 이내.
- T2: 진도 경계 저장/거부/완료 처리 기준 통과.
- T3: take_home 과제 이월, 미완료, 재부여 시 이력 2건 확인.
- T5: 리포트 draft 3건, 수치가 fixture/실데이터와 일치. OpenAI secret 미설정이면 T5-2 AI 의견은 보류하고 수치·구조까지만 판정.
- T7: 2026-06 수강료 합계 600,000원 / 카드 400,000원 / 현금 200,000원, 수정 시 audits 전후 기록.
- T9: 320px 무가로스크롤, 홈 화면 설치, 오프라인 입력 보존.
- T11: PC·폰 동시 세션 유지, GoAlimi 바로가기 새 탭. 단, 실제 goalimi_admin_url 미입력 상태면 T11-3~4는 설정 입력 후 판정.

현재 완료된 선행 게이트(2026-07-05):
- 운영 Supabase project ref: dqibhcadjxqmvahcewfn, region ap-northeast-2, ACTIVE_HEALTHY.
- web/.env의 NEXT_PUBLIC_SUPABASE_URL 일치.
- NEXT_PUBLIC_SUPABASE_ANON_KEY 변수명에는 publishable key(sb_publishable_...) 사용. legacy anon JWT 아님.
- owner profile 1건 존재.
- app_settings: academy_name=루트원학원, report_greeting, report_closing 적재. goalimi_admin_url은 실제 학원 PC/LAN 주소 확인 후 설정 화면에서 입력.
- QA fixture seed 적재 완료: students 4, parents 4, textbooks 5, enrollments 5, student_textbooks 7, schedule_slots 9, lessons 2, lesson_progress 2, homeworks 2, attendance 6, payments 2, payment_items 3.
- supabase/seeds/qa_fixtures_seed.sql은 재실행해도 카운트 유지되도록 멱등화됨.
- Auth "Allow new users to sign up" off 확인 완료.
- publishable key로 anon REST app_settings/students select가 42501 permission denied.
- npm --prefix web run typecheck 통과, npm --prefix web audit --omit=dev = found 0 vulnerabilities, publishable key 반영 build 통과.
- web/out 정적 산출물은 http://127.0.0.1:3001 에서 Python http.server로 서빙 중일 수 있음. 안 떠 있으면 `set -a; . ./web/.env; set +a; npm --prefix web run build` 후 `cd web/out && python3 -m http.server 3001 --bind 127.0.0.1`.

주의:
- 오늘 2026-07-05는 일요일. 고정 fixture 스케줄은 월~금만 있으므로 T1 "오늘 수업 표시"는 2026-07-06 월요일부터 자연 판정하거나, 임시 일요일 스케줄을 추가하면 QA 후 제거한다.
- supabase config push 금지. 로컬 supabase/config.toml은 dev 설정(enable_signup=true, site_url=http://127.0.0.1:3000)이라 운영 덮어쓰기 위험.
- service_role / sb_secret 키를 web/.env, 채팅, 문서에 넣지 않는다.
- Disable JWT-based API keys는 아직 누르지 않는다. Bridge/service_role 사용처를 secret key로 전환한 뒤 별도 검토.
- 커밋/푸시는 사용자가 요청할 때만.

필수로 먼저 읽을 파일:
- CLAUDE.md
- aidd_docs/memory/internal/2026-07-05-session-web-pwa-qa.md
- docs/10_ACCEPTANCE_TEST.md
- docs/03_UI_SPEC.md §0, §7
- aidd_docs/fixtures/mvp-seed-data.md

보조 확인 파일:
- aidd_docs/plans/mvp-build-plan.md
- docs/09_DEPLOY.md §4.1~§4.2
- web/app/lib/supabase.ts
- supabase/seeds/prod_app_settings_seed.sql
- supabase/seeds/qa_fixtures_seed.sql

You're the lead. Show the shortest executable QA plan first, then execute. Do not broaden scope beyond [5] unless a blocker requires it.
```
