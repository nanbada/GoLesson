# 2026-07-06 T12 Bridge/GoAlimi 하니스 핸드오프

## 목표

- 전날 남은 T12 Bridge/GoAlimi 정합 하니스 실행.
- token/context 절약을 위해 최신 핸드오프와 `bridge/tests/integration_bridge.py` 중심으로만 로드.

## 진행

- 활성 Goal 생성:
  - `T12 Bridge/GoAlimi 하니스 실행을 막는 의존성 문제를 해결하고, 남은 T6/T8/T12 QA 상태를 검증·정리한다`
- 전역 Python 3.14에는 `requests`가 없고, GoAlimi pinned `pydantic-core`가 Python 3.14와 호환되지 않아 Python 3.12 venv를 `/tmp/golesson-bridge-harness-venv`에 생성.
- 설치:
  - `bridge/requirements.txt`
  - `/Users/nanbada/projects/GoAlimi/requirements.txt`
  - 추가 임시 의존성 `greenlet>=3.0,<4`
- `greenlet`은 GoAlimi requirements에 없지만 SQLAlchemy async startup에 필요했다. 저장소 파일은 수정하지 않고 임시 venv에만 설치.
- 하니스는 원격 Supabase를 거부하므로, `supabase status -o env`에서 로컬 `API_URL`, `SERVICE_ROLE_KEY`를 읽어 `/tmp/golesson-bridge-local-config.json` 임시 config를 생성해 실행했다. 실행 후 임시 config 삭제.

## 검증

명령:

```bash
/tmp/golesson-bridge-harness-venv/bin/python -m bridge.tests.integration_bridge \
  --config /tmp/golesson-bridge-local-config.json \
  --goalimi-repo /Users/nanbada/projects/GoAlimi \
  --port 8001 \
  --verbose
```

결과:

- `PASS T8 student name`
- `PASS T8 student active`
- `PASS T8 parent local student mapping`
- `PASS T8 attendance local mapping`
- `PASS T8 inactive propagated`
- `PASS T8 reactivation propagated`
- `PASS T6 report sent`
- `PASS T6 custom id stored`
- `PASS T6 MockSender count`
- `PASS T6 GoAlimi down keeps pending`
- `PASS T6 send_window outside keeps pending`
- `PASS T12-6 attendance hard delete reflected`
- `PASS T12-7 dedupe returned existing custom`
- `PASS T12-7 report sent`
- `PASS T12-7 recovery caused no extra send`
- `PASS Bridge integration harness completed`

## 남은 실제 수동/실기기 QA

- T1/T2/T3 실제 손 입력 시간 측정과 모바일 조작 30초 기준.
- T5-2 OpenAI 실제 fallback 품질.
- T6 실제 카톡 수신, 600~900자 온전성, 21시 이후 실시간 window.
- T8 실제 GoAlimi 운영 동기화 10분 주기.
- T9 홈 화면 설치, 비행기 모드, 모바일 실제 기기.
- T11 같은 계정 다기기와 GoAlimi 새 탭 실제 네트워크.

## 주의

- `greenlet` 누락은 GoAlimi requirements 이슈다. 이번 작업에서는 GoAlimi repo를 수정하지 않았다.
- `/tmp/golesson-bridge-harness-venv`는 임시 실행 환경이다.
