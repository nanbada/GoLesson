# 2026-07-06 진행상황 점검 + CLAUDE.md/AGENTS.md SSOT 재구성

## 목표

- 주말(07-04~05)과 오늘(07-06) Opus/Codex 세션이 남긴 작업을 저장소·원격 실상태와 대조해 확인.
- 남은 업무 목록 정리, 프로젝트 CLAUDE.md 최적화.

## 확인(검증 근거)

- 원격 Supabase(`dqibhcadjxqmvahcewfn`) MCP 실조회:
  - migrations 10개 적용, 마지막 `20260705130200_transactional_lesson_payment_rpc` — 핸드오프 기록과 일치.
  - Edge Functions `parse-batch`/`generate-report`/`enqueue-report` 모두 version 3, ACTIVE, verify_jwt=true — 일치.
- git: 07-04 기반 구축([1]~[4]) → 07-05 Web PWA+QA → 07-06 Codex 커밋 3건(`26cb937` 리뷰 반영, `553780c` AGENTS/README, `01a3664` 주석 정리). 원격 origin = github.com/nanbada/GoLesson.
- `web/next-env.d.ts` 수정분은 `next dev` 자동 생성 노이즈 → checkout으로 복원(dev 서버 재실행 시 다시 생길 수 있음, 무해).
- 프론트 호스팅(Cloudflare Pages) 배포 기록 없음 → 미배포로 판단. OPENAI secrets 미등록(docs/09 §4.1). Bridge 학원 PC 미설치.

## 변경

- `AGENTS.md` 보강(CLAUDE.md unique 규칙 흡수):
  - 세션 종료 시 memory/internal 기록 의무.
  - GoAlimi `docs/REFERENCE.md` 확인 의무.
  - Code Conventions 신설: 소스 주석/로그 영어, UI 문자열 한국어. Bridge `.bat` ASCII/`%~dp0`/ONLOGON.
  - 파서 목표 수치(5요소 95%, 19/20) 명시.
- `CLAUDE.md` 재작성: `@AGENTS.md` import + Claude 전용(세션 운영, Orchestration)만 유지. 규칙 이원화(드리프트) 제거 — 07-06 기준 AGENTS.md가 이미 더 최신이었음(RPC 이름, config push 금지 등).
- 폴더 정리: 지난 핸드오프 8건(07-03~07-05) + `handoff-codex-bridge.md` + ChatGPT 히스토리 문서를 `aidd_docs/archive/`로 git mv(이력 보존). `docs/`는 설계 SSOT 00~11만, `memory/internal/`은 07-06 최신만 남음. 살아있는 참조 5곳(AGENTS, 00_PROJECT, 핸드오프 프롬프트 3종) 경로 갱신. 지난 세션 memory 파일 안의 옛 경로는 히스토리라 그대로 둠.
- Codex 교차검토 반영(2026-07-06): A2를 '선택'으로 정정 — `OPENAI_API_KEY`는 이미 등록(Codex secrets list 확인; 내 직접 확인은 block-secrets 훅이 차단), 모델 secret은 코드 기본값 있음(parse-batch:423, generate-report:274). A1에 Node 버전 고정 추가(web/package.json engines>=20.9.0). greenlet을 D3→A3 전제로 승격(GoAlimi requirements.txt 부재 직접 확인). A4에 LAN IP 필수 명시(기본값 127.0.0.1은 폰 자신 — page.tsx:1167). B7 라벨 정정(T12-1이 아니라 docs/10 §2 장문 실측 항목). docs/10 T12-1 행 문구 정밀화(403 localhost_only, 0.0.0.0 바인딩 유지). GoLesson-old 프로젝트는 삭제 완료 확인(projects list 1건 — 보드에 없던 항목). golesson.pages.dev 404 재확인(A1 미완 유지).
- `aidd_docs/plans/remaining-work.md` 신설 — 남은 업무 SSOT 보드(A 배포 전제 → B 실기기 QA → C Go-Live 잔여 → D 파일럿 중/후). 관리 규칙: 완료 시 체크+날짜+근거, 항목 삭제 금지, 타 문서 복제 금지. AGENTS(First Read), CLAUDE, README, mvp-build-plan, 핸드오프/킥오프 프롬프트 3종이 보드를 가리킴. claude/codex 핸드오프의 기존 "남은 QA" 목록은 보드 포인터로 대체(복제 제거).

## 남은 업무(우선순위)

1. 배포 전제: Cloudflare Pages 프론트 배포(§4.2) → Supabase secrets OPENAI_* 등록 → 학원 PC GoAlimi 최신화+Bridge 설치(§4.3) → goalimi_admin_url 입력.
2. 실기기/운영 QA: T1/T2/T3(30초 측정), T5-2, T6 실발송(7707만), T8 실동기화, T9 실폰(재빌드+SW 캐시 클리어 선행), T11, T12-1·장문 900자 실측.
3. Go-Live 체크리스트 잔여: 실데이터 이관, 백업 export+복구 리허설, Bridge 재부팅 자동 기동, 강사 온보딩, 파일럿 개시.
4. 파일럿 중/후: 파서 20문장 확정(19/20), QA fixture 정리(사용자 승인+Bridge 중지 선행), GoAlimi repo greenlet requirements 반영(별도 프로젝트).

## 주의

- 커밋/푸시 안 함. staged rename 10건(archive 이동), 수정: AGENTS/CLAUDE/README/00_PROJECT/mvp-build-plan/핸드오프·킥오프 프롬프트 3종. untracked: memory 파일 2건 + remaining-work.md.
- 히스토리 문서 파일명은 git 인덱스에 NFD(자소분리)로 저장돼 있어 NFC로 타이핑한 경로는 git mv가 못 찾는다. 셸 글롭(`docs/GoLesson*`)이나 `git -c core.quotepath=off ls-files | grep <ASCII부분>`으로 실제 경로를 얻어 처리했다.
- CLAUDE.md import 구조가 마음에 안 들면 git으로 즉시 되돌릴 수 있음(이 커밋 전 상태는 `01a3664`).
