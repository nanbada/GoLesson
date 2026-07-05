# 2026-07-06 UX subagent review 반영

## 목표

- IT에 익숙하지 않은 원장/강사 기준으로 화면 흐름, 실수 방지, 접근성, PWA 품질을 점검하고 필요한 부분만 수정.
- 대규모 화면/폴더 재구성은 보류. 현재 MVP 규모에서는 회귀 위험이 더 큼.

## subagent 주요 결론

- 수업 화면은 시작 전 기록 폼을 숨기고, 시작 후에만 진도/과제/코멘트를 입력하게 해야 함.
- 새 수업 시작 후 생성된 lesson id를 UI 상태에 반영하지 않아 중복 시작 가능성이 있음.
- 리포트 검토 본문을 수정한 뒤 승인/발송하면 저장 전 본문이 발송될 수 있음.
- 빠른입력 오류 수정에서 빈 숫자 입력이 0으로 저장될 수 있음.
- PWA service worker가 같은 origin GET을 모두 cache-first 처리해 배포 후 오래된 화면이 남을 수 있음.
- 모바일 기본 화면 폭은 640px 이하가 적절하고, 비교 작업 화면만 넓게 쓰는 편이 나음.

## 변경

- `web/app/page.tsx`
  - `startLesson`이 생성/갱신된 lesson id를 반환하고 `lessonTarget.lessonId`에 반영.
  - 수업 시작 전에는 시작/결석 처리만 노출. 시작 후 진도/과제/코멘트/완료 버튼 노출.
  - 결석/취소 버튼을 sticky primary 영역에서 분리하고 확인창 추가.
  - 리포트 승인/발송 직전에 현재 본문 저장.
  - 빠른입력 숫자 빈값을 `null`로 유지하고, 학생/과목/기록 내용이 모두 있는 카드만 저장 가능 처리.
  - 더보기 탭 재진입 시 하위 화면 대신 더보기 메뉴로 리셋.
  - placeholder-only 필드 일부에 `aria-label`, segmented 버튼에 `aria-pressed` 추가.
- `web/app/globals.css`
  - 기본 앱 폭 640px, 학생/리포트/관리 split 화면만 980px.
  - 포커스 표시 추가, 버튼 줄바꿈 허용, sticky 완료 버튼 단일화 스타일 추가.
  - 빠른입력 저장 가능/확인 필요 요약 strip 추가.
- `web/app/layout.tsx`
  - `maximumScale: 1` 제거.
- `web/public/service-worker.js`
  - 캐시 버전 `golesson-shell-v2`.
  - navigation은 network-first, 정적 asset만 cache-first.

## 검증

- `npm --prefix web run typecheck` 통과.
- `npm --prefix web run build` 통과.
- `git diff --check` 통과.
- `curl -I http://127.0.0.1:3100` => `HTTP/1.1 200 OK`.

## 남은 판단

- 실제 로그인 후 모바일/데스크톱 수동 UX QA는 원격 Supabase 데이터와 계정 세션 필요.
- 보고서 기간 preset, mutation 후 부분 reload 최적화는 P2/P3. 현재 MVP 규모에서는 이번 패치에 포함하지 않음.
