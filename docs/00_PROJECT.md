# 00. PROJECT — GoLesson 프로젝트 개요

> 소규모 초등 영어/수학 1:1 학원 운영도구. ERP가 아니다.
> "5초 안에 수업을 시작하고, 30초 안에 기록을 끝낸다."

## 1. 규모와 제약

| 항목 | 값 |
|---|---|
| 사용자 | 원장 1 + 강사 1~3 (동시 5명 이하) |
| 학생 | 10~30명 (초등, 영어/수학 1:1) |
| 운영비 | 월 0원 목표 (AI 호출비 제외, 월 수백 원 수준) |
| 원칙 | 오버엔지니어링 금지. Kubernetes/MSA/Redis 등 금지 |

## 2. 확정된 아키텍처 결정 (2026-07-03)

| 결정 | 내용 | 근거 |
|---|---|---|
| 구조 | **별도 신규 서비스** (GoAlimi 발송 코어 무변경 — 단 API 확장은 GoAlimi 측 별도 작업 필요, 08 §3) | GoAlimi는 운영 중 실서비스 — 장애 리스크 격리. 외부(집) 접근 필요 |
| 스택 | Next.js(정적 export PWA) + Supabase(Postgres/Auth/Edge Functions) + **Cloudflare Pages**(프론트 호스팅 1순위, Vercel은 대안) | 무료 티어 + 상업 사용 제약 없음 (Vercel Hobby는 비상업 전용 — 09 §3) |
| GoAlimi 연동 | 학원 PC의 **Bridge 워커**(Python)가 Supabase를 폴링 → GoAlimi 로컬 API로 카톡 발송 위임 | 학원 PC로의 인바운드 연결 불필요 (터널/포트포워딩 없음) |
| 학생 마스터 | **GoAlimi가 마스터** (등록/수정은 GoAlimi 관리자 화면) → Bridge가 GoLesson으로 단방향 동기화 | 이중 입력 방지, 기존 운영 습관 유지 |
| 파서 | Regex+사전 1차 → 실패분만 AI fallback | AI 비용 최소화 (ChatGPT 검토 결론) |
| 리포트 | 통계는 코드(템플릿) 90% + AI는 선생님 의견 다듬기 10% | 비용·품질 균형 |
| 서버 로직 위치 | Supabase Edge Functions (Next.js API 라우트 사용 안 함) | 프론트를 정적으로 유지 → 호스팅 교체 자유 (Vercel 약관 리스크 대비) |
| GoAlimi 통합 여부 | **분리 운영 확정** — 기능 흡수 없음, 재검토 트리거 관리 | 발송 엔진의 PC 종속, 체크인 오프라인 내성, 독립 제품 가치 (11_STUDY §6) |
| GoAlimi 화면 접근 | iframe 임베드 불가(mixed content) → 더보기 메뉴 **새 탭 런처**(REQ-910) | 11_STUDY §8 |
| 로그인 정책 | 사전 등록 5계정 미만, 자가 가입 없음, 동일 계정 다기기 동시 접속 허용 | REQ-908~909, BR-801/803 |

## 3. 사용자 인터뷰 결과 (2026-07-03, 원장)

| 질문 | 답변 | 설계 반영 |
|---|---|---|
| 진도 표기 | 영어·수학 모두 페이지/단원/Day 혼재. 교재마다 다름. **진도 중복(복습) 있음** | 교재당 진도 단위 1개 지정(`unit_label`), 진도는 로그 방식 저장 + 중복 허용 |
| 과제 방식 | 학원 내 과제시간 수행이 기본, 집 숙제는 예외 | `homeworks.kind`: `in_class`(당일 체크) / `take_home`(다음 수업 체크) |
| 리포트 | 1페이지 포맷. 기간 내 출결·진도·과제결과·영어/수학 과목별 선생님 의견 | 학생당 통합 리포트 1건, 과목별 의견 섹션, 카톡 텍스트 600~900자 |
| 수강료 | 단순 확인용 결제내역 (학생·과목별 금액·날짜·수단·메모) | 미납 추적/월정액 관리 **제외** (Non-goal) |

### 남은 인터뷰 항목 (개발 중 확인, 차단 요소 아님)
1. 강사가 자주 쓰는 메모 표현 20개 (파서 사전·리포트 문구에 반영)
2. 실제 사용 교재 전체 목록과 별칭 (초기 데이터)
3. 학부모가 가장 자주 묻는 질문 (리포트 템플릿 문구)
4. 카톡 장문(900자) 수신 시 학부모 가독성 확인 (파일럿 1회차 리포트 후)

## 4. 시스템 다이어그램

```
[강사: 폰/패드/PC 어디서나]
        │ HTTPS
        ▼
  Next.js PWA (정적, Cloudflare Pages)
        │ supabase-js (RLS)
        ▼
  Supabase ─ Postgres + Auth + Edge Functions(파싱·리포트)
        ▲
        │ REST 폴링 (아웃바운드만)
  ──────┼──────────────── 학원 윈도우 PC ─────
        │
  GoLesson Bridge (Python, Task Scheduler)
        │ localhost HTTP
        ▼
  GoAlimi (FastAPI) → 카카오톡 PC 자동화 → 학부모
```

## 5. 문서 맵 (SSOT)

| 문서 | 책임 | 주 독자 |
|---|---|---|
| 00_PROJECT | 개요·확정 결정·인터뷰 | 전체 |
| 01_PRD | 요구사항(REQ)+수용 기준 | 기획·개발·QA |
| 02_USER_FLOW | 사용자 흐름 | 기획·개발 |
| 03_UI_SPEC | 화면 명세 | 개발 |
| 04_DATABASE | ERD·DDL·RLS | 개발 |
| 05_API_SPEC | Edge Functions·Bridge 계약 | 개발 |
| 06_BUSINESS_RULE | 업무 규칙 | 개발·QA |
| 07_AI_SPEC | 파서·리포트 AI | 개발 |
| 08_GOALIMI | GoAlimi 연동·Bridge | 개발 |
| 09_DEPLOY | 배포·운영·백업 | 운영 |
| 10_ACCEPTANCE_TEST | 출시 승인 기준 | QA |
| 11_GOALIMI_INTEGRATION_STUDY | GoAlimi 통합 vs 분리 연구 (결론: 분리 + 재검토 트리거) | 기획 |

충돌 시 우선순위: 01_PRD > 06_BUSINESS_RULE > 각 상세 문서.
참고: `GoLesson AI용 추천 구조 및 개발자료.md`는 ChatGPT 검토 원본(히스토리)이며 SSOT 아님.

개발 보조 문서(SSOT 아님, `aidd_docs/`): `plans/mvp-build-plan.md`(구축 순서·완료 기준), `fixtures/mvp-seed-data.md`(QA seed — 10 §3 고정 문장과 짝), `memory/internal/`(세션 간 핸드오프 기록 — 세션 시작 시 최신 파일 확인).

## 6. 참고 프로젝트 (읽기 전용)

- `/Users/nanbada/projects/GoAlimi/` — 연동 대상. **코드 수정 금지**, 필요 변경은 08_GOALIMI에 명세만.
- `/Users/nanbada/projects/Claude-Setup/` — 개발 환경 참고용.
