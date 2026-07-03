# 08. GOALIMI — 카카오톡 발송·데이터 연동

GoAlimi(`/Users/nanbada/projects/GoAlimi/`)는 **운영 중인 실서비스**다. 이 문서는 연동에 필요한 GoAlimi 측 변경을 **명세**한다 — 실제 구현·배포는 GoAlimi 프로젝트에서 그쪽 작업 지침(CLAUDE.md, REFERENCE.md)에 따라 별도 진행한다. GoLesson 저장소에서 GoAlimi 코드를 수정하지 않는다.
통합 여부 연구는 완료 — **분리 운영 확정**, UI는 새 탭 런처만(11_GOALIMI_INTEGRATION_STUDY §6·§8).

## 1. 연동 구조 (인바운드 금지 원칙)

```
Supabase (클라우드)
   ▲ HTTPS (아웃바운드만 — 학원 PC가 폴링)
   │
GoLesson Bridge  ── 학원 윈도우 PC, Python 단일 스크립트, Task Scheduler ONLOGON
   │ http://127.0.0.1:{port}
   ▼
GoAlimi FastAPI ── 기존 직렬 발송 큐 → kakao_pc.py → 카카오톡
```

- 학원 PC로 들어오는 연결 없음 → 포트포워딩·터널·방화벽 설정 불필요.
- 카톡 **발송 자동화 코어(kakao_pc.py·직렬 큐 워커)는 무변경**으로 재사용한다. 단, GoAlimi 측 **API 확장은 필요**하다(§3 — 테이블 1개 + 엔드포인트 5개). "GoAlimi 코드 무변경"이 아니라 "발송 코어 무변경 + 주변 API 추가"가 정확한 표현이며, 이 확장은 GoAlimi 프로젝트에서 별도 구현·배포한다.

## 2. GoAlimi 절대 규칙 준수 (연동 설계에 미치는 제약)

| GoAlimi 규칙 | GoLesson 설계 반영 |
|---|---|
| 발송은 직렬 큐 경유만 (공유 스레드풀 금지) | 신규 발송도 기존 queue.py로 enqueue만 한다 |
| timeout 재시도 금지 (이중발송 위험) | Bridge도 자동 재시도 금지 — 실패는 강사의 명시적 재전송만(BR-503) |
| out_of_hours 등 영구 실패 즉시 종결 | Bridge 발송 시간창 09~21시(BR-504)로 사전 회피 |
| 수신자 검증(제목 검증) 없는 발송 금지 | 수신자 지정은 GoAlimi의 기존 검증 로직 그대로 사용 |
| .bat ASCII 전용, 서버 재시작은 restart.bat | Bridge 설치 스크립트도 동일 관례 |
| 경로 하드코딩 금지 (다중 학원 이식성) | Bridge 설정은 `bridge_config.json` 1파일로 외부화 |

## 3. GoAlimi 측 필요 변경 명세 (GoAlimi 프로젝트에서 구현)

### 3.1 신규 테이블 `custom_messages`

```sql
CREATE TABLE IF NOT EXISTS custom_messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id  INTEGER NOT NULL REFERENCES students(id),
    body        TEXT    NOT NULL,
    dedupe_key  TEXT    NOT NULL UNIQUE,      -- 멱등성 (GoLesson outbox.dedupe_key)
    status      TEXT    NOT NULL DEFAULT 'pending'
                CHECK(status IN ('pending','sent','failed')),
    error       TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT (datetime('now','localtime')),
    sent_at     TIMESTAMP
);
```

### 3.2 신규 발송 엔드포인트 2개 (localhost 전용)

```
POST /api/notify/custom
  body: { "student_id": 7, "body": "…리포트 전문…", "dedupe_key": "report:45:v1" }
  동작: dedupe_key 존재 시 기존 행 반환(200, 멱등). 신규면 custom_messages insert
        → 기존 발송 큐에 enqueue (검증·시간대 규칙은 출결 알림과 동일 경로)
  응답: { "id": 3, "status": "pending" }

GET /api/notify/custom/{id}
  응답: { "id": 3, "status": "sent"|"failed"|"pending", "error": null, "sent_at": "…" }
```

기존 큐 재사용 시 필수 설계 조건 (실코드 확인 결과, 커밋 fead319 기준):

1. **결과 갱신 경로 분리**: `NotificationJob.log_id`는 attendance_logs.id 전용이고 큐 워커의 결과 콜백도 attendance 상태만 갱신한다. custom message용 결과 갱신 경로(잡 유형 구분 필드 추가 등)를 함께 구현해야 하며, in-flight 중복 방지 집합(`_in_flight`)이 attendance id와 custom id를 혼동하지 않도록 잡 식별자 공간을 분리한다.
2. **수신자 조회는 student_id 기준 + 발송 시점 재조회 (확정)**: 기존 체크인 헬퍼는 학생 이름으로 학부모를 조회한다 — 동명이인 오발송 위험. custom 엔드포인트는 반드시 `student_id` → 대표 학부모(is_primary, notify_enabled)로 **발송 시점에 GoAlimi DB에서 직접 조회**한다. GoLesson이 저장한 kakao_name은 UI 표시용 스냅샷일 뿐 POST로 전달하지 않는다 — GoLesson 사본은 최대 10분 지연이라, 마스터(GoAlimi)의 최신 대표 학부모로 보내는 쪽이 오발송 위험이 낮다(BR-701과 일치).
3. 에러 분류는 GoAlimi 기존 체계 그대로: `recipient_chat_not_found`·`room_mismatch`·`out_of_hours`(영구) / `focus_not_acquired`(환경) / `timeout`(일시, 재시도 금지).
4. 보안: 엔드포인트 전체 127.0.0.1 요청만 허용.

### 3.3 GoLesson 전용 read API 3개 (신규 — 기존 API로는 부족, 실코드 확인)

기존 API 확인 결과: `GET /api/students`는 **active 학생만** 반환, 학부모 목록 API 없음, attendance 증분(`since_id`) 조회 없음. 따라서 동기화용 read API를 신설한다 (모두 127.0.0.1 전용):

```
GET /api/golesson/students     → 전체 학생 (active 포함 여부 무관: id, name, grade, school, active)
GET /api/golesson/parents      → 전체 학부모 (id, student_id, kakao_name, relation, is_primary, notify_enabled)
GET /api/golesson/attendance?since_id={n}&days={m}
                               → attendance_logs 증분 (id, student_id, event_type, event_at)
```

비활성 학생 포함이 필수인 이유: GoAlimi에서 퇴원 처리(active=0)된 학생을 GoLesson도 비활성으로 반영해야 하는데(BR-702), active만 반환하는 기존 API로는 "사라진 학생"과 "비활성 학생"을 구분할 수 없다.

### 3.4 검증 필요 리스크 (구현 전 확인)

- **장문 발송**: 리포트는 600~900자. kakao_pc.py의 입력 방식이 장문에서 안정적인지 실측 필요 (테스트 계정 7707 신성화). 불안정하면 리포트를 2분할 발송하는 옵션을 Bridge에 둔다.
- **줄바꿈**: 카톡 입력창에서 개행 처리 방식 확인 (Shift+Enter 등 kakao-send 스킬 pitfalls 참조).

## 4. Bridge 명세 (GoLesson 저장소 `bridge/` — 신규 개발)

단일 Python 스크립트 + 설정 파일. 외부 의존 최소(requests 정도).

```
bridge/
  bridge.py            메인 루프
  bridge_config.json   supabase_url, service_key, goalimi_base_url, poll_sec, send_window
  run_bridge.bat       ASCII 전용, %~dp0 관례
  (Task Scheduler ONLOGON 등록 — GoAlimi restart.bat 관례 준수, GoAlimi와 별개 태스크)
```

메인 루프 (60초 주기):

```
1) 발송 (09~21시만):
   claim_outbox RPC로 pending 최대 5건 인출(원자적 processing 전환, 05_API §3)
   → GoAlimi POST /api/notify/custom → 응답 id를 outbox.goalimi_custom_id에 저장
   → 결과 폴링(최대 60초)
   → outbox에 sent/failed 반영 (sent이면 reports도 sent 갱신 — 실패는 outbox만, BR-506)
2) 10분마다: students/parents/attendance 동기화 (GoAlimi → Supabase upsert)
3) 매일 03시: Supabase 전 테이블 JSON export → backup/ (30일 보관)
4) heartbeat: 매 주기 app_settings.bridge_last_poll_at 갱신
   (발송현황 화면 연결 경고의 근거 = 03_UI §7. 폴링 쿼리 자체가
    무료 티어 7일 미활동 pause 방지 활동을 겸한다)
```

장애 처리:

| 상황 | 동작 |
|---|---|
| GoAlimi 미기동/응답 없음 | outbox pending 유지(손실 없음), 다음 주기 재시도. 로그만 남김 |
| Supabase 접속 불가 | 대기 후 재시도. 발송 중이던 건은 processing 유지 |
| Bridge crash 후 재기동 | stale processing은 goalimi_custom_id 상태 조회 또는 dedupe_key 멱등 재POST로만 종결(05_API §3) — 임의 failed 전환 금지(이중발송 방지) |
| GoAlimi가 영구 실패 반환 | failed + 사유 그대로 기록 → 강사 화면 표시 |
| PC 재부팅 | Task Scheduler ONLOGON으로 자동 복구 |

로그: `bridge/logs/bridge.log` (UTF-8, 일 단위 로테이션, 14일 보관). GoAlimi service.log(CP949)와 분리.

## 5. 동기화 정합성 규칙

- 방향: GoAlimi → GoLesson 단방향 (BR-703). GoLesson의 학습 데이터는 역방향 전송 없음.
- 멱등 키: goalimi_student_id / goalimi_parent_id / goalimi_log_id (모두 unique).
- 삭제 대응(학생): GoAlimi에서 사라진 학생은 GoLesson에서 active=false 처리(하드 삭제 금지).
- 삭제 대응(출결): GoAlimi는 출결 **hard delete**가 가능하므로 `since_id` 증분 복사만으로는 삭제가 GoLesson에 남는다 → 리포트 출석 수치 오류. Bridge가 **매일 1회 최근 30일 대사**: 두 쪽 goalimi_log_id 집합을 비교해 GoAlimi에 없는 행을 GoLesson에서 삭제 (05_API §3).
- 지연 허용: 최대 10분. 신규 학생 등록 직후 GoLesson에 안 보이면 "동기화 대기 중" 안내(REQ-106).
