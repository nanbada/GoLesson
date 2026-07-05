# 07. AI SPEC — 파서·리포트 생성

설계 사상: **AI는 최후 수단.** 정형 입력은 regex+사전으로, 리포트 수치는 코드로. AI는 (1) 비정형 문장 파싱 fallback, (2) 선생님 의견 문단 다듬기 — 2곳에만 사용.

## 1. 파서 파이프라인 (Edge Function: parse-batch)

```
입력 텍스트 → 줄 분리(빈 줄 무시)
  └ 줄마다:
    ① 토큰화 → 사전 매칭
       학생: students.name + 성 제외 이름("민수"→"김민수"), 동명이인이면 ambiguous 반환
       과목: '영어'|'수학'|'영'|'수'
       교재: textbooks.title + aliases (해당 학생 배정 교재 우선.
             교재 미기재 시 그 학생·과목의 활성 교재가 1권이면 자동 매칭,
             복수면 진도 표기 단위(페이지/단원/Day)와 일치하는 교재 우선, 그래도 모호하면 오류 카드.
             과목 미기재 시 매칭된 교재의 과목으로 유추)
    ② 진도 regex 추출
    ③ 과제 regex 추출
    ④ 남은 텍스트 = 코멘트
    ⑤ **regex 성공 규칙: 학생 식별 + (진도 또는 과제) 파싱 성공. 코멘트만 있는 줄은 AI 폴백으로 넘어간다** — 이 규칙이 아니면 학생+코멘트만 있는 모든 줄이 regex 성공으로 표시돼 AI 폴백이 절대 발동하지 않는 모순이 생김.
    ⑥ 실패 → AI 호출 (1줄 단위)
    ⑦ AI도 실패 → 오류 카드 (원문 보존, 수동 지정 UI)
```

### 1.1 Regex 패턴 (초기 세트 — 파일럿 중 사전에 추가)

| 대상 | 패턴 | 예 |
|---|---|---|
| 진도 구간 | `(\d+)\s*[-~→>]{1,2}\s*(\d+)` | 38-42, 38~42, 38→42, 38->42 |
| 진도 단일 | `(?:p\.?\s*)?(\d+)(?:까지\|완료)?` (구간 없을 때) | p42, 42까지 |
| 단원 | `(\d+)\s*단원` / `[Uu]nit\s*(\d+)` / `[Dd]ay\s*(\d+)` / `(\d+)\s*챕터` | 3단원, Day3 |
| 과제 | 숙제 키워드(숙제\|과제\|hw)는 **독립 토큰**일 때만 시작점이며(예: "숙제는 다 해옴"의 "숙제는"은 키워드 아님), 키워드 뒤로는 숫자범위\|숫자\|단위토큰(단원\|Day\|챕터)\|교재별칭\|과제유형어(워크북\|문제집\|프린트)인 동안만 소비하고 그 외 토큰에서 멈춤. | 숙제 43~45, 과제: 1-3단원 |
| 과목 | `영어\|영\b\|수학\|수\b` | |

- 진도 단위 판정: 매칭된 교재의 unit_label을 따른다. "3단원" 패턴인데 교재 단위가 페이지면 → 단원 값을 memo로 넣고 진도는 미추출 처리(오류 카드).
- 구간이 아닌 단일 값은 from=last_position, to=값 으로 해석.
- from/to 역순 구간은 작은 값→큰 값으로 정렬한다. 예: `42-38`은 `38→42`로 반환한다(BR-104).
- **입력 제한**: 요청당 최대 200줄, 전체 텍스트 20,000자. 초과 시 400 bad_request 응답.

### 1.2 AI Fallback

- 호출 단위: 실패한 줄 1개씩 (컨텍스트 오염 방지, 비용 미미).
- 방식: Structured Output (JSON Schema 강제).

```jsonc
// system
"당신은 학원 수업 기록 파서다. 입력 줄에서 아래 스키마로 추출하라.
 학생 후보: [김민수, 이서연, ...]  교재 후보: [Bricks Reading(페이지), 쎈 5-1(페이지), 단어장(Day), ...]
 확실하지 않은 필드는 null. 수치를 지어내지 마라."
// response_format: json_schema
{ "student_name": "string|null", "subject": "영어|수학|null",
  "textbook_title": "string|null", "from_value": "int|null", "to_value": "int|null",
  "homework": "string|null", "comment": "string|null", "confidence": "high|low" }
```

- 후처리: student_name·textbook_title을 다시 사전 매칭해 id 확정 (AI가 낸 이름을 그대로 믿지 않는다). 단, regex 단계에서 이미 학생이 확정된 줄이면 AI가 다른 이름을 반환해도 **regex가 확정한 학생 id를 우선**한다. AI 이름 재매칭: 전체 이름 일치 우선, 이름(성 제외) 일치가 복수면 ambiguous_student 에러. from/to 역순이면 작은 값→큰 값으로 정렬한다. OpenAI 호출에 max_tokens 상한 있음(300). confidence=low면 카드에 "확인 필요" 배지.
- 오류(타임아웃·API 장애): 오류 카드 + parse_logs(status=failed) + [재시도] (REQ-506).

## 2. 리포트 생성 (Edge Function: generate-report)

### 2.1 통계 집계 (코드 — SQL)

```jsonc
// reports.stats 스키마
{ "period": {"start":"2026-06-20","end":"2026-07-03"},
  "attendance": {"scheduled": 8, "done": 8, "checkin": 8},
  "subjects": {
    "영어": { "progress": [{"textbook":"Bricks Reading","unit":"페이지","from":38,"to":72}],
             "homework": {"checked":6,"done":5,"partial":1,"not_done":0} },
    "수학": { ... } } }
```

- scheduled = 기간 내 schedule_slots 발생 횟수(요일 계산) − 취소 수업.
- progress from = 기간 시작 전 마지막 to (없으면 기간 내 최소 from), to = 기간 내 마지막 to. 교재별.

### 2.2 본문 템플릿 (90% — 코드)

```
[{학원명}] {student_name} 학습 리포트 ({M/D}~{M/D})

■ 출석: {done}회 수업 / 예정 {scheduled}회
■ 영어 진도: {textbook} {from}→{to}{unit}
■ 영어 과제: {done}회 완료 / {checked}회 ({partial}회 부분완료)
■ 수학 진도: …
■ 수학 과제: …

[영어 선생님 의견]
{ai_polished_comment_en}

[수학 선생님 의견]
{ai_polished_comment_math}

{맺음말 — app_settings.report_closing, 설정에서 편집}
```

규칙: 과목 미수강/코멘트 없음 → 해당 섹션 생략(BR-404). 전체 600~900자, 초과 시 의견 문단부터 축약.

### 2.3 의견 다듬기 (10% — AI)

```
// 입력: 기간 내 해당 과목 comments 원문 나열 (예: "독해 좋아짐 / 집중 흐림 / 단어 암기 성실")
// system
"초등 학부모에게 보내는 학습 의견 1문단(2~4문장, 200자 이내)을 작성하라.
 규칙: 존댓말. 입력에 없는 사실·수치 금지. 부정적 내용은 개선 방향과 함께 완곡하게.
 과장 금지('최고', '완벽' 금지). 학생 이름은 '{name} 학생'으로 1회만."
```

- AI 실패 시: 원본 코멘트를 "· " 목록으로 그대로 삽입하고 생성은 성공 처리 — 강사가 검토 단계에서 직접 다듬는다.

## 3. 모델·비용

| 용도 | 모델 | 근거 |
|---|---|---|
| 파싱 fallback | OpenAI 소형(nano/mini급, 예: gpt-4.1-nano $0.10/1M in) | 짧은 구조화 작업 |
| 의견 다듬기 | OpenAI 소형~중형(mini급) | 한국어 자연스러움 필요 |

- 모델명은 env(`OPENAI_MODEL_PARSE`, `OPENAI_MODEL_REPORT`)로 관리 — 구현 시점 최신 소형 모델로 핀 고정.
- 추정량: 리포트 30명×월 2회×~800tok + 파싱 fallback 소량 = **월 수십만 토큰 미만 → 월 수백 원 수준.**
- API 키는 Supabase Edge Function secrets에만 저장. 프론트 노출 금지.

## 4. 품질 기준 (REQ-508)

- 정형 입력 파싱 정확도: 초기 고정 문장 10개 전수 통과, 인터뷰로 20개 확정 후 19/20 이상(95%) 유지 (10_ACCEPTANCE §T4).
- AI 의견: 입력에 없는 사실 생성 0건 (검토 단계에서 발견 시 프롬프트 수정으로 대응).
- 파일럿 초기 2주는 파싱 결과 전수 확인 후 저장 습관을 안내(어차피 미리보기 필수).
