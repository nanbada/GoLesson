# 2026-07-03 세션 핸드오프

이 메모는 Claude/Codex가 다음 세션에서 현재 리뷰 결과를 잃지 않도록 남긴 내부 기록이다.

## 이번 세션에서 한 일

- `docs/00_PROJECT.md` ~ `docs/11_GOALIMI_INTEGRATION_STUDY.md` 전체를 리뷰했다.
- GoAlimi 실제 코드와 문서를 대조했다.
  - 로컬: `/Users/nanbada/projects/GoAlimi`
  - GitHub: `nanbada/GoAlimi`
  - 확인 커밋: `fead319f0c46fd1fe355d6152762d429760d4050`
  - GitHub `main`, 로컬 `origin/main`, 로컬 HEAD가 같은 커밋임을 확인했다.
- 외부 플랫폼 가정도 공식 문서 기준으로 확인했다.
  - Vercel Hobby는 비상업/개인 사용 제한이 명확하다.
  - Cloudflare Pages Free는 정적 PWA 호스팅 1순위가 더 적합하다.
- `AGENTS.md`를 현재 문서 기준으로 최적화했다.
- `CLAUDE.md`를 `AGENTS.md`와 같은 정책 수준으로 동기화했다.

## 리뷰 결론

현재 기획 방향 자체는 작다: Next.js 정적 PWA + Supabase + 학원 PC Bridge + GoAlimi 분리 운영.
다만 문서 그대로 구현하면 막히는 위험이 있다. 아래 항목은 구현 전 문서 수정 대상이다.

## 반드시 고칠 문서 이슈

1. Supabase GRANT 누락
   - `docs/04_DATABASE.md`는 RLS만 정의한다.
   - 2026-05-30 이후 신규 Supabase 프로젝트는 Data API 노출에 명시적 `GRANT`가 필요하다.
   - 마이그레이션 지침에 RLS + GRANT를 함께 넣어야 한다.

2. RLS 정책 자체 모순
   - `docs/04_DATABASE.md`는 공통 `for all` 정책을 제시하면서, 아래에서는 `students/parents/attendance` 클라이언트 쓰기 금지를 요구한다.
   - 테이블군별 정책으로 분리해야 한다.
   - `students`, `parents`, `attendance`: 클라이언트 select만. insert/update/delete는 Bridge/service_role 전용.

3. GoAlimi "코드 무변경" 표현 부정확
   - `docs/00_PROJECT.md`, `docs/11_*`는 GoAlimi 코드 무변경/즉시 진행처럼 읽힌다.
   - 하지만 `docs/08_GOALIMI.md`는 `custom_messages`, `/api/notify/custom` 추가가 필요하다.
   - 표현을 "kakao_pc.py/core 발송 자동화 무변경, GoAlimi API 확장 필요"로 바꿔야 한다.

4. GoAlimi 기존 큐 재사용 명세 부족
   - 실제 `NotificationJob.log_id`는 `attendance_logs.id` 전용이다.
   - 결과 콜백도 attendance 상태만 갱신한다.
   - custom message 발송은 별도 상태 갱신 경로가 필요하다.
   - 기존 helper는 학부모 조회를 `student_id`가 아니라 학생 이름 기준으로 한다. 동명이인 위험이 있으므로 custom endpoint는 `student_id` 기준이어야 한다.

5. Bridge 동기화 API 계약이 실제 GoAlimi와 다름
   - 문서의 `GET /api/admin/students`는 실제와 다르다. 실제 prefix는 `/api`, 학생 목록은 `/api/students`.
   - 실제 `/api/students`는 active 학생만 반환한다.
   - parents 별도 API, attendance `since_id` API는 현재 없다.
   - GoLesson 전용 read API 3개 또는 기존 API 확장 명세가 필요하다.

6. 비활성/삭제 출결 정합성
   - GoAlimi는 출결 hard delete API가 있다.
   - 단순 `id > last_synced_id` 증분 복사로는 삭제를 반영하지 못한다.
   - 리포트 출석 수치가 틀릴 수 있다.

7. 오늘 수업 view와 보강 수업 충돌
   - BR-201은 같은 날 같은 과목 2회 lesson을 허용한다.
   - `v_today_lessons`는 `student_id + subject + date`로만 join해 슬롯별 상태 매칭이 불가능하다.
   - `lessons.schedule_slot_id nullable` 또는 `planned_start_time` 같은 매칭 키가 필요하다.

8. PostgREST PATCH에서 `attempts:+1` 불가
   - `docs/05_API_SPEC.md`의 `{attempts:+1}`는 PostgREST 업데이트 문법이 아니다.
   - outbox claim은 RPC(`claim_outbox(limit)`)로 atomic update + attempts 증가 처리하는 편이 안전하다.

9. report 실패/재발송 상태 모델 불명확
   - `reports.status`에는 `failed`가 있지만 Bridge 실패 계약은 outbox만 failed로 둔다.
   - sent body 불변과 새 버전 재발송을 저장할 구조도 부족하다.
   - 실패 상태는 outbox 소유로 고정하거나 report version 구조를 추가해야 한다.

10. profile 생성 절차 누락
    - RLS는 `profiles.active=true`를 요구한다.
    - 배포 문서는 Auth 초대만 말한다.
    - 초대 후 `profiles` row seed 절차가 없으면 로그인해도 데이터 접근이 막힌다.

## 호스팅 판단

- Vercel Hobby는 학원 운영 도구에 바로 쓰지 않는 편이 맞다.
- Cloudflare Pages Free를 프론트 기본 호스팅으로 바꾸는 것이 더 적합하다.
- 남은 문서 수정 대상:
  - `docs/00_PROJECT.md`: 스택/다이어그램의 Vercel 표현
  - `docs/09_DEPLOY.md`: 프론트 배포 절차와 비용표
  - `docs/01_PRD.md`: "Supabase/Vercel 무료 티어" 문구
- 정적 export, Supabase Edge Functions, Next.js API Route 금지는 유지한다.

## 수정된 파일

- `AGENTS.md`: Codex용 작업 지침 최적화
- `CLAUDE.md`: Claude Code용 작업 지침 동기화
- `aidd_docs/memory/internal/2026-07-03-session-handoff.md`: 이 핸드오프 메모

## 아직 안 한 일

- `docs/00~11` 본문은 아직 수정하지 않았다. → **완료 (Claude, 아래 후속 기록)**
- Supabase DDL/RLS/GRANT 실제 마이그레이션은 아직 작성하지 않았다.
- GoAlimi 프로젝트 코드는 수정하지 않았다.
- 커밋/푸시는 하지 않았다.

---

## 후속: Claude 반영 기록 (2026-07-04)

위 "반드시 고칠 문서 이슈" 10건과 호스팅 판단을 `docs/00~11`에 전부 반영했다.
GoAlimi 관련 지적(4·5번)은 로컬 실코드로 재검증 후 반영 (NotificationJob.log_id=attendance 전용, 학부모 조회 이름 기준, /api/students active만, parents·since_id API 부재 — 모두 사실).

| 이슈 | 반영 위치 |
|---|---|
| 1 GRANT 누락 | 04 §5 재작성 (RLS+GRANT 통합, 2026-05-30 이후 신규 프로젝트 주의 명시), 09 §4.1 |
| 2 RLS 모순 | 04 §5 테이블군별(A읽기전용/B CRUD/C +delete/D 시스템) 정책으로 분리 |
| 3 "코드 무변경" 표현 | 00 §2, 08 §1, 11 §3 — "발송 코어 무변경 + GoAlimi API 확장 필요"로 정정 |
| 4 큐 재사용 명세 | 08 §3.2 — 결과 갱신 경로 분리, in-flight 식별자 공간 분리, 수신자는 student_id 기준 |
| 5 동기화 API 계약 | 08 §3.3 — GoLesson 전용 read API 3개(/api/golesson/*) 신설 명세, 05 §3 갱신 |
| 6 출결 hard delete | 05 §3·08 §5 — 매일 1회 최근 30일 goalimi_log_id 대사로 삭제 반영 |
| 7 오늘 view 슬롯 충돌 | 04 — lessons.schedule_slot_id(nullable) 추가, v_today_lessons를 슬롯 join으로 수정 |
| 8 attempts:+1 불가 | 04 §3 claim_outbox RPC(FOR UPDATE SKIP LOCKED) 신설, 05 §3 절차 교체 |
| 9 report 실패 모델 | 04 reports.status에서 failed 제거(draft/ready/sent), 06 BR-506(실패는 outbox 소유), 03 §6 |
| 10 profiles seed | 09 §4.1 5단계 신설 (누락 시 전면 접근 차단 경고 포함) |
| 호스팅 | Cloudflare Pages 기본·Vercel 대안 — 00 §2·§4, 01 §7, 02 F7, 09 §1·§2·§3·§4.2·§6 |

추가 정합: 10_ACCEPTANCE T10에 RLS 테이블군·RPC 권한 검증 케이스 추가.
여전히 안 한 일: 실제 마이그레이션 작성, GoAlimi 코드 수정(08 §3은 명세만), 커밋/푸시.

## 후속 2차: GPT 추가 의견(P0~P2) 반영 (Claude, 2026-07-04)

| 이슈 | 반영 |
|---|---|
| P0-1 parse_logs D군 vs confirmed 충돌 | 04 §5 5-1: `grant update(status)` 컬럼 GRANT + created_by=auth.uid() RLS. 05 §2.1 근거 명시, T4-6·T10 검증 추가 |
| P0-2 sent 불변이 주석뿐 | 04 §3 `t_reports_immutable` 트리거(body/stats/student_id/period/status 차단). T6-4·T10 검증 |
| P0-3 Bridge crash 이중발송 | outbox에 `goalimi_custom_id` 추가, stale processing은 상태 재조회/멱등 재POST로만 종결('bridge_interrupted' 임의 failed 폐기) — 05 §3, 08 §4 장애 표, T12-7 |
| P1 "조건부 PATCH" 잔재 | 08 §4 → claim_outbox RPC로 정정 |
| P1 수신자 스냅샷 결정 | **GoAlimi가 발송 시점 student_id로 재조회로 확정** (마스터 최신 = 오발송 최소, BR-701 일치). outbox.kakao_name은 UI 표시용으로 역할 명시 — 04 주석, 08 §3.2 |
| P1 QA seed 없음 | `aidd_docs/fixtures/mvp-seed-data.md` 신설 (§3 고정 문장과 짝 관리), 10 §0에서 참조 |
| P1 T6-3 60초 과도 | 2분으로 완화 (poll 60s + 발송 40s) |
| P2 vercel.app 도메인 | 09 §1 → pages.dev |
| P2 C-12 참조 오류 | 09 §5 → "10 §2 Go-Live 백업 항목" |
| P2 RLS placeholder | 04 §5를 실행 가능 SQL로 재작성 (DO 블록 반복, 시퀀스 GRANT 포함) |
| P2 GoAlimi 확장 검증 부족 | 10 T12 신설 (localhost·dedupe 멱등·결과 경로 분리·in-flight 분리·비활성 포함·대사·crash 회수) |
| 빌드 순서 | `aidd_docs/plans/mvp-build-plan.md` 신설 (GoAlimi API → Supabase → Edge Fn → Bridge → Web → QA, 병행 규칙 포함) |

추가: 07 §1 파서 규칙 보강 — 교재 미지정 시 활성 교재 1권 자동 매칭, 복수면 진도 단위 힌트로 선택, 과목은 교재에서 유추 (fixture 문장과 정합).
여전히 안 한 일: 실제 마이그레이션 파일 작성, GoAlimi 코드 수정, 커밋/푸시.

## 후속 3차: 개발 착수 준비 완료 (Claude, 2026-07-04)

- CLAUDE.md·AGENTS.md 최신화: aidd_docs 체계(빌드플랜·픽스처·핸드오프 규약) + 2차 리뷰 확정 사항(claim_outbox RPC 전용, stale 회수, 불변 트리거, parse_logs 예외) 반영. 두 파일 공통 정책 동일 유지.
- CLAUDE.md에 Orchestration workflow 섹션 추가 (Fable 오케스트레이터 + deep-reasoner(Opus) + fast-worker(Sonnet) + Codex peer. high-stakes = 발송 안전·RLS·GoAlimi 계약·무결성 → 병렬 후 합성). Codex 플러그인 세팅은 2026-07-05 오전 예정 — 세팅 전엔 Codex 단계 생략.
- `aidd_docs/plans/session-kickoff-prompt.md` 신설: [2] Supabase용·[1] GoAlimi용 완성 프롬프트 + [3]~[6] 범용 템플릿.
- README.md(진입점)·.gitignore(비밀키 차단) 신설. 스펙 갭 마감: bridge_last_poll_at(03 §7·04·08 §4), 00 문서맵에 aidd_docs 추가.
- git: main 브랜치 초기 커밋 완료, origin=https://github.com/nanbada/GoLesson.git 연결. **push는 이 환경에 GitHub 인증이 없어 미완 — 사용자 PC에서 `git push -u origin main` 1회 필요.**
- 다음 세션: session-kickoff-prompt.md §1([2] Supabase) 또는 §2([1] GoAlimi, 해당 저장소에서) 프롬프트로 시작.
