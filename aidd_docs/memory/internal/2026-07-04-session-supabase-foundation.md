# 2026-07-04 세션 핸드오프 — [2] Supabase 기반 완성

빌드플랜 [2] 완료. 다음 세션은 [3] Edge Functions(이 저장소) 또는 [1] GoAlimi API 확장(GoAlimi 저장소).

## 산출물

- `supabase/migrations/` 4파일 (docs/04 §2~§5 구현):
  - `20260704090000_init_schema.sql` — DDL 19테이블 + 인덱스
  - `20260704090100_functions_triggers.sql` — last_position 캐시, updated_at×4, audits 공용 트리거(security definer), t_reports_immutable, claim_outbox RPC(+revoke/grant)
  - `20260704090200_views.sql` — 뷰 2개 (security_invoker=on + grant select)
  - `20260704090300_rls_grant.sql` — RLS+GRANT 테이블군별(A/B/C/D) + reports 3-1 예외 + service_role 명시 GRANT
- `supabase/seed.sql` — 로컬 dev용 app_settings (db reset 시 자동)
- `supabase/seeds/prod_profiles_seed.sql`·`prod_app_settings_seed.sql` — 09 §4.1 순서 5·8 운영 시드 (멱등, 값 수정 후 실행)
- `supabase/tests/t10-access.sh` — T10 자동 검증 (curl+REST, throwaway 유저 생성)
- `supabase/config.toml` — supabase init 기본값

## 검증 결과 [VERIFIED]

- `supabase db reset` 무결 적용 (마이그레이션 4개 + seed).
- T10 접근 테스트 **24/24 통과**: anon 전면 차단 / A군(students·parents·attendance) 쓰기 거부 / parse_logs 본인 행·status 컬럼만 / sent 리포트 불변(트리거, sent_at 변조 포함) / 클라이언트 status='sent' 위조 거부(insert·update) / 비활성 profile 차단 / claim_outbox service_role 전용(+attempts=1 원자 증가) / git 추적 파일에 JWT형 비밀 없음.
- 재실행 방법: `orb start` → `supabase start` → `supabase db reset` → `./supabase/tests/t10-access.sh`.
- T10 중 "로그아웃 상태 접근 → 로그인 화면"은 프론트 항목 — [5] Web PWA 단계에서 검증.

## 고위험(RLS/GRANT) 이중 검토 결과 — 병렬 워크플로가 실제로 작동

deep-reasoner(Opus)와 Codex를 같은 문제로 병렬 투입(서로 답 비공개):

- deep-reasoner: 문서 이탈 5건 전부 "정당·필요" 판정, 결함 0건.
- Codex: 같은 판정 + **실결함 2건(High) 발견** — ① 불변 트리거가 컬럼 열거 방식이라 sent_at·created_by·created_at 변조 통과 → jsonb 전체 비교(updated_at 제외)로 교체. ② B군 공통 정책이 클라이언트의 reports.status='sent' 직접 갱신 허용(발송 완료는 Bridge 소유) → reports 전용 정책(draft/ready만)으로 교체.
- 합성 시 추가: ②와 같은 논리로 insert에도 status 제약 (처음부터 sent로 insert 가능했음).
- 교훈: 단일 검토자(같은 모델 계열)의 "결함 0" 판정을 종결로 삼지 말 것. RLS/발송 안전은 이중 검토 유지.

## 문서 동기화 (설계 변경 → 같은 작업에서 반영 완료)

- docs/04: §3 audits security definer 필요 사유 + claim_outbox revoke 후 service_role grant SQL / §3 불변 트리거 jsonb 비교로 교체 / §4 security_invoker + grant select / §5 3-1(reports 예외)·7(service_role 명시 GRANT, BYPASSRLS≠privilege 우회) 신설.
- docs/09 §4.1: 순서 5·8에 시드 스크립트 경로 연결.
- docs/10 T10: reports.status='sent' 직접 insert/update 거부 케이스 추가.

## 원격 배포 (같은 날 이어서 진행) [VERIFIED]

- **운영 원격 프로젝트: `dqibhcadjxqmvahcewfn` (이름 GoLesson, ap-northeast-2 서울)** — 첫 프로젝트가 뭄바이(ap-south-1)로 생성돼 서울로 재생성함. 구 프로젝트는 `GoLesson-old`(`iokemqsdnhfawvabgxqt`)로 개명된 채 남아 있음 → 서울 검증 완료됐으므로 대시보드에서 삭제 권장(Free 플랜 2개 한도 점유 + 유령 스키마).
- 재링크는 `supabase link --project-ref dqibhcadjxqmvahcewfn`로 비대화식 성공(access token 기반, DB 비밀번호 불필요 — CLI가 login role 자동 초기화). `supabase login`은 최초 1회만 사용자 터미널 필요.
- `supabase db push` 완료 — `migration list`로 원격 4/4 기록 확인. push 말미의 pg-delta catalog 캐시 경고는 무해(적용과 무관한 로컬 캐시 단계, 로컬 edge_runtime 컨테이너가 이때 죽을 수 있음 → `docker start`로 복구).
- **원격(서울) T10 24/24 통과** (t10-access.sh를 API_URL/ANON_KEY/SERVICE_ROLE_KEY env로 실행). 09 §4.1 순서 3(접근 검증) 충족.
- 정리 검증: 실행 후 students·reports·parse_logs·notification_outbox·profiles 전부 0행, auth 사용자 0명.
- [5] 단계 Cloudflare Pages env: `NEXT_PUBLIC_SUPABASE_URL=https://dqibhcadjxqmvahcewfn.supabase.co` + anon key(신규 프로젝트 것).
- 원격 키는 legacy JWT(anon/service_role) + 신형(sb_publishable/sb_secret) 공존. T10은 legacy 사용. 키 전문은 채팅·파일에 미기록.
- Cloudflare Pages: 사용자가 GitHub 연결 완료(프로젝트명 golesson). [5] 단계 전까지 빌드 실패가 정상(09 §4.2).

## 환경 메모

- 이 세션에서 설치: supabase CLI 2.109.0(brew). Docker는 OrbStack — **세션 중 데몬이 저절로 내려간 적 있음**, supabase 명령 실패 시 `orb start` 먼저.
- 로컬 키(anon/service_role)는 supabase CLI 공용 데모 키 — 비밀 아님. 운영 키는 규칙대로 bridge_config.json·Supabase secrets에만.

## 안 한 일

- 커밋/푸시 (요청 시에만). untracked: `supabase/` 전체, `.claude/`, 이 핸드오프. modified: docs/04·09·10, 2026-07-03 핸드오프.
- GoLesson-old(뭄바이) 프로젝트 삭제 — 대시보드 수동, 사용자 작업.
- Auth 설정: 이메일 가입 비활성화(대시보드 수동, 09 §4.1 순서 4) + 강사 초대 → `prod_profiles_seed.sql` 실행(이메일 목록 필요).
- `prod_app_settings_seed.sql` 실행(실제 학원명 등 값 확정 후).
