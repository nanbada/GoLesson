# 2026-07-04 세션: [1] GoAlimi API 확장 — 완료

빌드플랜 [1] 단계. GoAlimi 프로젝트(`/Users/nanbada/projects/GoAlimi/`)에 custom 발송
API + GoLesson 동기화 read API를 구현하고 mock 모드로 전 시나리오 검증 완료.
발송 안전 코어는 deep-reasoner + Codex 병렬 검토 후 합성 설계로 확정.

## 구현 내용 (GoAlimi 저장소, 미커밋)

- `schema.sql` + `app/models.py`: `custom_messages` 테이블/ORM (dedupe_key UNIQUE,
  status CHECK pending|sending|sent|failed, error, sent_at).
- `app/routers/golesson.py` (신규): POST /api/notify/custom, GET /api/notify/custom/{id},
  GET /api/golesson/{students(비활성 포함)|parents|attendance?since_id}.
  전부 127.0.0.1 전용(403 localhost_only). 서버 바인딩 0.0.0.0은 유지(태블릿 체크인).
- `app/notification/queue.py`: NotificationJob에 `kind`("attendance"|"custom")와
  `max_attempts`(attendance=2, custom=1) 추가. `_in_flight`는 (kind, id) 튜플 키.
  `run()`에 on_start 콜백(물리 발송 직전, 실패 시 발송 스킵 error=precheck_failed).
- `app/main.py` lifespan: kind별 결과 디스패처(custom → custom_messages만, SSE 없음),
  기동 시 `recover_custom_messages()` 실행.
- `docs/REFERENCE.md` v1.8.0: §1.3/§2/§3.4(신설)/§4/§8(#27~30) 동기화 (fast-worker,
  §3.4→§3.5 재번호에 따른 §6.6 교차참조 수정 포함).

## 발송 안전 설계 확정 (이중 검토 합성 — 재논의 금지 근거)

1. **POST는 순수 멱등**: 같은 dedupe_key 재POST = 기존 행 반환만, 절대 재큐잉 안 함.
   (발송 완료 후 결과 기록 전 crash면 행이 pending인데 이미 발송됨 — 재큐잉=이중발송 TOCTOU)
2. **큐 유실 복구는 재기동 스캔 전담** (`recover_custom_messages`): pending → 학부모
   재조회 후 재큐잉(없으면 failed/no_primary_parent), sending → failed/interrupted 종결.
   fresh process라 race-free, Bridge 계약 변경 없음.
3. **sending 마커**: on_start가 pending→sending 조건부 UPDATE 후에만 물리 발송.
   기록 실패 시 발송 스킵 — 시도 기록 없는 발송은 복구 스캔이 재큐잉해 이중발송 되므로.
4. **custom 단일 시도**: 실패 판정이 물리 발송 후 false negative일 수 있어(kakao_pc
   발송 후 검증) 큐 내 재시도가 학부모 이중 수신이 됨. attendance는 기존 2회 유지.
5. **timeout·interrupted = 발송 여부 불확실**: failed로 종결하되 UI는 "수신 확인 후
   재발송" 안내. 재발송은 사람이 새 dedupe_key(v2)로만. (Codex의 in_doubt 별도 상태는
   5인 규모 과설계로 기각 — error 문자열로 충분)
6. 수신자 재조회 시점 해석: 접수 시점 + 재기동 재큐잉 시점에 GoAlimi DB(마스터) 조회.
   큐 체류 수 초라 "발송 시점 재조회" 스펙 의도 충족. GoLesson kakao_name 미전달.
7. attendance 3분 자동 재발송 워커는 custom을 의도적으로 미커버(BR-503).

리뷰 이력: Codex 5건(C1 재큐잉 이중발송 CRITICAL, C2 stranded pending HIGH,
C3 상속 2회 재시도 CRITICAL, C4 timeout 오판 HIGH, C5 접수시점 조회 MEDIUM) 전부 반영.
deep-reasoner의 "timeout 재시도됨" 주장은 오독(queue.py는 timeout에 명시적 break) —
기각했으나 그 주석의 통찰(스레드가 뒤늦게 발송 완료 가능)은 4·5번에 반영.

## 검증 (GOALIMI_MOCK_SENDER=1, docs/10 T12 기준 — 전부 통과)

- T12-1: LAN IP 접근 403 localhost_only, localhost 200.
- T12-2: 같은 dedupe_key 3회 POST → 행 1개(id=1), `[MockSender]` 발송 로그 정확히 1줄.
- T12-3: custom sent+sent_at 기록, attendance_logs 증가 0 (경로 분리).
- T12-4: attendance 2건 + custom 1건 동시 → 전부 발송, in-flight 충돌 0.
- T12-5: /api/golesson/students에 비활성 학생 포함, 기존 /api/students는 제외 (기존 동작 불변).
- 오류: 404 student_not_found / 422 no_primary_parent(행 미생성) / 422 empty body / GET 404.
- 재기동 복구: pending 행 → 정확히 1회 발송, sending 행 → failed/interrupted 발송 0회,
  학부모 없는 pending → failed/no_primary_parent. failed 행 재POST → 기존 행 반환, 발송 0회.
- 출결 회귀: 체크인 IN/OUT 기존 경로 정상 발송 (on_start는 attendance에 no-op).

## 문서 동기화

- GoLesson `docs/08_GOALIMI.md` §3: 구현 완료 표기, sending 상태·재기동 복구·필수 설계
  조건 1~6 확정 반영. §3.4(장문 900자 실측)만 미결 — Go-Live 체크리스트, 7707 계정.
- GoLesson `docs/05_API_SPEC.md` §3: pending/sending 비종결(계속 폴링), 재POST 무재발송,
  422 no_primary_parent 즉시 failed, timeout/interrupted UI 안내 추가.

## 안 한 일 / 다음

- **커밋 안 함** (GoAlimi·GoLesson 둘 다, 사용자 요청 대기). GoAlimi 변경 5파일 + REFERENCE.md.
- 다음 단계: 빌드플랜 **[4] Bridge** (claim_outbox 폴링 → POST /api/notify/custom →
  goalimi_custom_id 저장 → 상태 폴링 종결. 이 세션에서 확정된 계약은 docs/05 §3 참조).
- 사용자 게이트 대기: OpenAI 키(T4/T5-2), 강사 초대, GoLesson-old 삭제, app_settings seed,
  장문 실발송 실측(docs/08 §3.4).
