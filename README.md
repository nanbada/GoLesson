# GoLesson

소규모 초등 영어/수학 1:1 학원 운영도구. 원장 1명 + 강사 1~3명, 학생 10~30명 규모의 파일럿 — ERP가 아니다.
"5초 안에 수업 시작, 30초 안에 기록 완료"가 목표. 월 운영비 0원(무료 티어 + 학원 PC).

## 구조

```
[강사: 폰/패드/PC]
      │ HTTPS
Next.js 정적 PWA (Cloudflare Pages)
      │ supabase-js (RLS)
Supabase — Postgres + Auth + Edge Functions
      ▲ 아웃바운드 폴링만
GoLesson Bridge (학원 윈도우 PC, Python)
      │ localhost
GoAlimi (기존 출결 서비스) → 카카오톡 → 학부모
```

핵심 결정: GoAlimi와 **분리 운영**(기능 흡수 없음, `docs/11` 참조), 학생 마스터 = GoAlimi(단방향 동기화), 진도·과제는 로그 방식, 파서는 regex 우선 + AI fallback, 리포트는 검토(draft→ready) 후에만 발송.

## 저장소 안내

| 경로 | 내용 |
|---|---|
| `docs/00~11_*.md` | 설계 SSOT (PRD·DB·API·업무규칙·연동·배포·QA) — `docs/00_PROJECT.md`부터 읽기 |
| `aidd_docs/plans/mvp-build-plan.md` | 구축 순서와 단계별 완료 기준 |
| `aidd_docs/fixtures/mvp-seed-data.md` | QA seed (docs/10 §3 고정 문장과 짝) |
| `aidd_docs/memory/internal/` | 세션 간 핸드오프 기록 |
| `CLAUDE.md` / `AGENTS.md` | AI 에이전트 작업 지침 (Claude Code / Codex — 공통 정책 동일, CLAUDE.md에만 오케스트레이션 섹션 추가) |
| `web/` `supabase/` `bridge/` | 구현 코드 (예정 — 아직 미작성) |

## 개발 시작 (새 세션)

1. `CLAUDE.md`(또는 `AGENTS.md`) → `docs/00_PROJECT.md` → `aidd_docs/memory/internal/` 최신 핸드오프 순으로 읽는다.
2. `aidd_docs/plans/mvp-build-plan.md`의 현재 단계부터 진행한다. 현재 상태: **설계 완료, 구현 착수 전** — 다음 작업은 [1] GoAlimi API 확장(GoAlimi 저장소에서)과 [2] Supabase 마이그레이션(병행 가능).

## 안전 규칙 (요약 — 상세는 CLAUDE.md)

- 발송 테스트는 GoAlimi 테스트 계정(출결번호 7707 신성화 = 운영자 카톡)으로만.
- 비밀키는 커밋 금지: service_role 키는 학원 PC `bridge_config.json`에만, OpenAI 키는 Supabase secrets에만.
- GoAlimi(`../GoAlimi`)는 읽기 전용 참고 — 이 저장소에서 수정하지 않는다.
