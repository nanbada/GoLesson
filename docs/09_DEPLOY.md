# 09. DEPLOY — 배포·운영

## 1. 구성 요소와 비용

| 구성 | 서비스 | 플랜 | 비용 |
|---|---|---|---|
| 프론트 (정적 PWA) | **Cloudflare Pages** (1순위 — 상업 사용 제약 없음. Vercel은 대안, §3) | Free | 0원 |
| DB·Auth·Edge Functions | Supabase | Free | 0원 |
| 발송·동기화 | 학원 PC (기존 GoAlimi PC) | — | 0원 |
| AI | OpenAI API | 종량 | 월 수백 원 수준 |
| 도메인 | 선택 (pages.dev 서브도메인으로 시작) | — | 0원 |

## 2. 무료 티어 제약과 대응 (2026-07 확인)

| 제약 | 내용 | 대응 |
|---|---|---|
| Supabase 500MB DB | 데이터 한도 | 수년치 여유 (04_DATABASE §6) |
| Supabase 7일 미활동 pause | 쿼리 없으면 정지 | Bridge 폴링(60초)이 상시 활동 유지. Bridge 장기 중단 시 대시보드에서 수동 resume |
| Supabase 백업 없음 | Free 플랜 자동 백업 미제공 | Bridge 야간 JSON export → 학원 PC (§5) |
| Supabase 프로젝트 2개 | 계정당 한도 | GoLesson 1개만 사용. 타 학원 확장 시 학원별 프로젝트 or Pro 검토 |
| Cloudflare Pages Free 한도 | 빌드 500회/월, 정적 자산 대역폭 무제한 | 사용자 5명 — 문제 없음 |
| (대안) Vercel Hobby 비상업 약관 | 학원 운영 도구는 상업적 사용으로 해석될 소지 → **기본 호스팅으로 쓰지 않는다** | §3 참조 — 정적 export라 어느 쪽이든 반나절 내 이전 가능 |

## 3. 호스팅 결정 — Cloudflare Pages 기본, Vercel은 대안 (2026-07-03 확정)

- 결정: 프론트 기본 호스팅은 **Cloudflare Pages Free**. 정적 자산은 무료 + **상업 사용 제약 없음**.
- 배경: Vercel Hobby는 비상업/개인 사용 전용이 명확해(공식 약관 확인, 세션 핸드오프 2026-07-03), 수강료를 받는 학원의 운영 도구에는 바로 쓰지 않는 것이 맞다.
- 호스팅 중립 설계는 유지: 프론트는 **정적 export**(Next.js `output: 'export'`), 서버 로직은 전부 Supabase Edge Functions → 정적 파일은 어디서든 서빙 가능.
- 대안 경로 (필요 시 반나절 내 이전):
  1. Vercel (Pro $20/월 — 상업 사용 시. Hobby는 파일럿 임시 검증 용도로만)
  2. Cloudflare Workers + OpenNext (2026-02 v1.0 GA) — SSR이 필요해질 경우
- 금지: 특정 호스팅 전용 API(Vercel Edge Middleware/KV/Blob, Cloudflare 전용 바인딩 등) 사용 금지.

## 4. 배포 절차

### 4.1 Supabase

```
1. 프로젝트 생성 (리전: ap-northeast-2 서울)
2. supabase CLI로 마이그레이션 적용 (04_DATABASE DDL — supabase/migrations/)
   ※ 마이그레이션은 RLS 정책과 명시적 GRANT를 함께 포함 (04 §5 — 신규 프로젝트는 GRANT 없이 Data API 접근 불가)
3. 접근 검증: anon select → 거부, authenticated로 students insert → 거부 (04 §5 검증 절차)
4. Auth: 이메일 가입 비활성화, 강사 계정 5개 수동 초대
5. **profiles 시드**: 초대한 각 계정의 auth.users.id로 profiles row insert (name·role·active=true)
   ※ 이 단계를 빠뜨리면 RLS의 is_active_teacher()가 false → 로그인해도 모든 데이터 접근 차단
   스크립트: supabase/seeds/prod_profiles_seed.sql (이메일→id 매핑, 멱등)
6. Edge Functions 배포: parse-batch / generate-report / enqueue-report
7. Secrets 등록: OPENAI_API_KEY, OPENAI_MODEL_PARSE, OPENAI_MODEL_REPORT
8. app_settings 시드: academy_name, report_greeting, report_closing, goalimi_admin_url
   스크립트: supabase/seeds/prod_app_settings_seed.sql (값 수정 후 실행, 멱등)
```

현재 상태(2026-07-05):
- 운영 프로젝트 `dqibhcadjxqmvahcewfn`(서울 ap-northeast-2) 연결.
- 마이그레이션 4개 원격 적용, 원격 T10 24/24 통과.
- Edge Functions 3개(`parse-batch`, `generate-report`, `enqueue-report`) 원격 배포 완료, `ACTIVE`, `verify_jwt=true`.
- 원격 smoke 통과: 인증 teacher로 `parse-batch`, `generate-report`, `enqueue-report` 오류 계약 확인.
- Auth 이메일 가입 비활성화 확인. owner profile 1건 확인.
- `app_settings` 운영 seed 적용: `academy_name=루트원학원`, `report_greeting`, `report_closing`. `goalimi_admin_url`은 실제 학원 PC/LAN 주소 확인 후 설정 화면에서 입력.
- QA fixture seed 적재 완료: 학생 4·교재 5·스케줄 9·수업 2·결제 2. `supabase/seeds/qa_fixtures_seed.sql` 재실행 카운트 유지 확인.
- 미완료: 실제 운영 강사 초대(필요 시), `OPENAI_API_KEY` secrets 등록(T5-2 AI 의견 검증용), docs/10 T1~T3·T5·T7·T9·T11 실계정 수동 QA.

### 4.2 프론트 (Cloudflare Pages)

```
1. GitHub 저장소 연결 → Pages 프로젝트 생성 (빌드: next build, 출력: out/ — 정적 export)
   ※ 모노레포이므로 루트 디렉토리를 web/으로 지정. web/ 생성 전([5] 이전)에는 빌드 실패가 정상
2. env: NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY
   ※ `NEXT_PUBLIC_SUPABASE_ANON_KEY` 변수명에는 Supabase publishable key(`sb_publishable_...`) 사용 권장. legacy anon key도 호환되지만 신규 운영 env는 publishable key로 둔다.
3. next.config: output 'export' + PWA(manifest·SW — Serwist 권장)
4. 폰·패드에서 설치(A2HS) 확인
※ Vercel로 이전/병행 시에도 동일 구성(정적 export) — 절차만 다르고 코드 변경 없음
```

### 4.3 Bridge (학원 PC)

```
1. GoAlimi PC에 bridge/ 폴더 복사 (경로 하드코딩 금지, %~dp0 관례)
2. Python 의존성 설치: `python -m pip install -r bridge/requirements.txt`
3. bridge_config.json 작성:
   { "supabase_url": "...", "service_key": "...",
     "goalimi_base_url": "http://127.0.0.1:8000",
     "poll_sec": 60, "send_window": [9, 21], "backup_dir": "backup" }
4. Task Scheduler ONLOGON 등록 (GoAlimi와 별개 태스크, run_bridge.bat — ASCII 전용)
5. 검증: 테스트 학생(7707 신성화)으로 리포트 1건 발송 → 운영자 본인 카톡 수신 확인
```

개발 검증 보조: 로컬 Supabase + GoAlimi MockSender 환경에서는 `python3 -m bridge.tests.integration_bridge --config bridge/bridge_config.json --goalimi-repo /Users/nanbada/projects/GoAlimi --port 8000`로 T6/T8/T12-6~7을 확인한다. 이 하니스는 GoAlimi 임시 DB를 쓰며 실제 카톡을 발송하지 않고, 원격 Supabase 실행을 거부한다.

주의: service_key는 전권 키다. bridge_config.json 외 어디에도 두지 않으며 git 커밋 금지(.gitignore).

## 5. 백업·복구

- 매일 03시 Bridge가 Supabase 전 테이블 → `backup/YYYY-MM-DD/*.json` (30일 보관).
- 학원 PC 자체는 GoAlimi 기존 backup.bat 체계 유지 (GoAlimi DB는 GoAlimi가 백업).
- 복구 리허설: 출시 전 1회 — export JSON을 새 Supabase 프로젝트에 재적재해 화면 확인 (10_ACCEPTANCE §2 Go-Live '백업' 항목).

## 6. 환경 변수 요약

| 위치 | 키 |
|---|---|
| Cloudflare Pages (또는 대체 호스팅) | NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY(publishable key 권장) |
| Supabase Secrets | OPENAI_API_KEY, OPENAI_MODEL_PARSE, OPENAI_MODEL_REPORT |
| 학원 PC | bridge_config.json (service_key 포함 — 유일한 보관처) |

## 7. 모니터링 (파일럿 수준)

- 발송·동기화 이상: 프론트 발송현황 화면 + Bridge 최근 폴링 시각 경고(03_UI §7)로 충분.
- 로그: bridge.log(학원 PC) / Supabase 대시보드 Edge Function 로그 / GoAlimi service.log.
- 별도 APM·알림 시스템 도입 금지 (오버엔지니어링).
