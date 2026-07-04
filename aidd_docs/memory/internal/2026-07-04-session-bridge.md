# 2026-07-04 세션 핸드오프 — [4] Bridge 구현·통합 검증

## 완료

- `bridge/bridge.py` 신규 구현:
  - `claim_outbox` RPC 기반 pending 인출.
  - GoLesson 내부 `students.id` → GoAlimi `goalimi_student_id` 변환 후 `POST /api/notify/custom`.
  - `goalimi_custom_id` 즉시 저장, `GET /api/notify/custom/{id}` 상태 폴링.
  - `sent` 시 `notification_outbox`와 `reports`를 sent로 갱신.
  - `failed` 시 outbox만 failed 처리(BR-506).
  - GoAlimi 미기동/연결 실패는 claimed row를 pending으로 되돌림(접수 전 실패라 이중발송 없음).
  - processing 회수: `goalimi_custom_id` 있으면 상태 조회, 없고 10분 초과면 dedupe_key 멱등 재POST.
  - 10분 동기화: students/parents/attendance.
  - 일일 최근 30일 출결 대사, 03시 JSON 백업, heartbeat(`app_settings.bridge_last_poll_at`).
- `bridge/bridge_config.example.json`: placeholder only. 실제 `bridge_config.json`은 `.gitignore`.
- `bridge/run_bridge.bat`: ASCII, `%~dp0`.
- `bridge/requirements.txt`: `requests`.
- `bridge/tests/test_bridge.py`: fake Supabase/GoAlimi 단위테스트 7개.
- `bridge/tests/integration_bridge.py`: GoAlimi 임시 SQLite DB + `GOALIMI_MOCK_SENDER=1` + Supabase REST/RPC 통합 하니스.
  - 원격 Supabase 실행은 시작 시점에 거부한다(운영 데이터 보호).
  - T6: pending→sent, reports sent, GoAlimi down 시 pending 유지/재기동 후 발송, send_window 밖 pending 유지.
  - T8: students/parents/attendance 동기화 + 학생 비활성/재활성 전파.
  - T12-6: GoAlimi 출결 hard delete 대사 후 GoLesson attendance 삭제.
  - T12-7: stale processing 회수, dedupe_key 멱등 재POST, MockSender 발송 증가 0.
- 문서 동기화:
  - `docs/09_DEPLOY.md` Bridge 설치 절차에 `pip install -r bridge/requirements.txt` 추가.
  - `docs/08_GOALIMI.md` Bridge 파일 구조와 테스트 하니스 갱신.
  - `docs/10_ACCEPTANCE_TEST.md` Bridge 로컬 보조 하니스 명시.
  - `README.md`, `aidd_docs/plans/mvp-build-plan.md`, `session-kickoff-prompt.md` 현재 상태 갱신.

## 검증

- `python3 -m py_compile bridge/bridge.py bridge/__init__.py bridge/tests/test_bridge.py` 통과.
- `python3 -m unittest bridge.tests.test_bridge` 통과: `Ran 7 tests ... OK`.
- `python3 -m py_compile bridge/tests/integration_bridge.py` 통과.
- `python3 -m bridge.tests.integration_bridge --config bridge/bridge_config.json --goalimi-repo /Users/nanbada/projects/GoAlimi --port 8000` 통과:
  - `PASS T6 report sent`
  - `PASS T6 GoAlimi down keeps pending`
  - `PASS T6 send_window outside keeps pending`
  - `PASS T8 inactive propagated`
  - `PASS T12-7 recovery caused no extra send`
  - `PASS Bridge integration harness completed`
- `git diff --check` clean.

## 미완료

- [4] Bridge의 로컬/Mock 완료 기준은 통과.
- 운영 전 남은 Go-Live 항목:
  - Windows 학원 PC에서 Task Scheduler ONLOGON 자동기동 확인.
  - 테스트 계정 7707 신성화로 600~900자 실제 카톡 장문 수신 1회 실측.
  - 야간 백업 파일 생성과 복구 리허설 1회.
- 다음 개발 단계: [5] Web PWA.
- 운영 `bridge_config.json`은 사용자/학원 PC에서 직접 배치해야 한다. service_role 키를 채팅·문서·git에 기록하지 말 것.
- 개발 통합 하니스는 로컬 Supabase 전용이다. 원격 프로젝트로 T6/T8/T12 하니스를 돌리지 말 것.

## 주의

- `requests`가 없는 개발 환경에서는 `python3 bridge/bridge.py --help`도 import 단계에서 실패한다. 학원 PC 또는 검증 venv에서 `python -m pip install -r bridge/requirements.txt` 후 실행.
- 로컬 검증용 `bridge/bridge_config.json`은 생성했지만 `.gitignore` 대상이며 커밋 금지. service_role 값은 문서에 남기지 않음.
- 커밋/푸시 안 함. 현재 GoLesson은 `origin/main`보다 `11568f7` 1커밋 앞서 있고, 이번 Bridge 변경은 워킹트리에 남아 있음.
