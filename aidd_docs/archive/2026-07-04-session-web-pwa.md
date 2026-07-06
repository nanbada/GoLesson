# 2026-07-04 세션 핸드오프 — [5] Web PWA 1차 구현

## 완료

- `aidd_docs/plans/session-kickoff-prompt.md` [5] Context 최적화:
  - 존재하지 않는 `docs/02_ARCHITECTURE.md` 제거.
  - 실제 SSOT 포인터(`docs/01_PRD.md`, `docs/02_USER_FLOW.md`, `docs/03_UI_SPEC.md`, `docs/05_API_SPEC.md`, `docs/10_ACCEPTANCE_TEST.md`)와 DB/RLS 마이그레이션 포인터 추가.
- `web/` 신규 구현:
  - Next.js 16 정적 export(`output: "export"`) + React 19 + Supabase JS 2.110.0 + lucide icons.
  - Supabase Auth 이메일 로그인, 세션 자동 갱신, 비활성 profile 안내.
  - 화면: 오늘, 수업 기록, 학생 목록/상세, 빠른입력, 리포트, 수강료, 교재, 발송현황, GoAlimi 바로가기, 설정.
  - 일반 CRUD는 `supabase-js` + RLS 경계 준수. `students`/`parents`/`attendance`는 read-only로만 사용.
  - Edge Function 호출: `parse-batch`, `generate-report`, `enqueue-report`.
  - PWA manifest + SVG icon + service worker. service worker는 production에서만 등록(개발 캐시 간섭 방지).
  - 입력 draft 일부 localStorage 보존: 수업, 빠른입력, 수강료.
  - KST 날짜 유틸(`toISOString()` 날짜 밀림 회피).
- `web/.env.example` 추가. `.gitignore`에서 예시 env만 추적 허용, `*.tsbuildinfo` ignore 추가.
- `README.md`, `aidd_docs/plans/mvp-build-plan.md`, `session-kickoff-prompt.md` 현재 상태 갱신.

## 검증

- `npm install` 후 `postcss` override 적용: `npm audit --omit=dev` → `found 0 vulnerabilities`.
- `npm run typecheck` → 통과.
- `NEXT_PUBLIC_SUPABASE_URL=https://example.supabase.co NEXT_PUBLIC_SUPABASE_ANON_KEY=dummy-anon-key npm run build` → 통과, route `/` static export 확인.
- Headless Chrome 렌더 검증:
  - 320×720: 로그인 화면 hydration 완료, `documentElement.scrollWidth=320`, 버튼/입력 정상, 스크린샷 `/tmp/golesson-mobile.png`.
  - 1280×800: 로그인 화면 중앙 정렬 정상, 스크린샷 `/tmp/golesson-desktop.png`.

## 미완료 / 다음

- 실계정 Supabase env로 로그인 후 docs/10 T1~T3·T5·T7·T9·T11 수동 QA 필요.
- 운영 전 아직 남은 사용자/운영 게이트:
  - Auth 이메일 가입 비활성화, 강사 초대, `profiles` seed.
  - `app_settings` 운영 seed.
  - OpenAI key secrets 후 AI fallback/리포트 의견 실검증.
  - Bridge/GoAlimi 실기기 장문 900자 수신 실측.
- 현재 dev 서버는 더미 공개 env로 `http://127.0.0.1:3000`에 떠 있음. 실제 로컬 검증 시 `web/.env.local`에 운영/로컬 Supabase 공개 env를 넣고 재시작.
- 커밋/푸시 안 함.

## 주의

- 빌드 시 `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`가 없으면 정적 산출물은 "환경 변수 필요" 화면을 렌더한다. Cloudflare Pages에는 두 env를 반드시 설정해야 한다.
- `service_role` 키는 프론트 env에 절대 넣지 않는다.
