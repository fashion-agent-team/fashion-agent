# MCP 도구 입출력

agent가 부르는 MCP 도구의 이름과 JSON 입출력입니다. 서버는 Spring AI MCP Server(Streamable HTTP, `/mcp`)로 만들고, 메서드에 `@Tool`을 붙입니다. 도구 설명(`description`)은 Gemini가 읽고 고르는 근거라 **한국어로 언제 쓰는지까지** 적습니다.

**MCP 서버는 데이터만 돌려줍니다.** "이 옷이 오늘 일정·날씨에 맞는가" 같은 판단과 추천은 agent가 Gemini에 맡깁니다(흐름과 Gemini 입출력은 [README.md 5절](README.md#5-기능-구분과-agent-처리-방법)).

공통:

- `userId`가 있는 도구는 agent가 `X-User-Id` 값으로 덮어써서 넣습니다. Gemini가 채운 값은 쓰지 않습니다.
- 실패하면 도구 결과로 `{"error": {"code", "message"}}`를 돌려줍니다(예외를 그대로 던지지 않기). agent가 이걸 보고 사용자에게 안내합니다.
- 사람에게 읽어 줄 문장(`spokenSummary` 등)은 한국어 존댓말 한 문장씩.

## 공통 모양: Garment

지금 앱의 `Garment`(lib/models/garment.dart)와 같은 모양입니다. clothes_inspect가 만들고, closet이 저장하며, agent가 Gemini에 넘깁니다.

```json
{
  "id": "g1",
  "category": "top",            // top | bottom | outer | dress | shoes | other
  "name": "니트",
  "colorName": "차콜 그레이",
  "colorFamily": "gray",        // black white gray navy beige brown khaki blue red pink orange yellow green purple unknown
  "tone": "dark",               // light | mid | dark
  "pattern": null,
  "material": "니트 같음",
  "notes": null,
  "formality": "smart",         // formal | smart | casual | sporty | unknown
  "defects": [
    { "kind": "stain", "where": "오른쪽 소매 끝", "confidence": 0.85 }   // stain | tear | lint | other
  ],
  "box": { "x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4 },
  "position": "left",           // left | center | right (사진 기준 = 사용자 기준). clothes_inspect가 box로 계산
  "confidence": 0.96
}
```

**왼쪽·오른쪽은 바라보는 사람(사진) 기준 하나입니다.** 옷을 내려놓고 위에서 비추므로 사진 왼쪽이 사용자 왼쪽입니다.
- `position`(옷이 화면 어디에 있나): box 중심 x가 0.4 미만이면 left, 0.6 초과면 right, 그 사이는 center.
- `where`(옷 한 벌 안의 얼룩 위치): 같은 사진 기준("오른쪽 소매 끝" = 사진에서 오른쪽에 보이는 소매). agent는 이 값을 사용자가 "어디야?"라고 물을 때만 말합니다.

## mcp-weather

### `weather_today`
옷 추천 1단계에서 agent가 부르고, "오늘 날씨 어때?"에도 씁니다. 판단하지 않고 숫자를 돌려줍니다(`needsOuter`, `needsUmbrella`, `clothingAdvice`는 날씨 묻기 기능에서 바로 읽어 주기 위한 참고값).

입력 `{ "lat": 37.5665, "lon": 126.9780 }`

출력
```json
{
  "condition": "맑음",
  "temperature": 14.2,
  "apparentTemperature": 12.8,
  "minTemperature": 6.0,
  "maxTemperature": 17.0,
  "dailyRange": 11.0,
  "precipitationProbability": 10,
  "needsOuter": true,
  "needsUmbrella": false,
  "clothingAdvice": "자켓이나 가디건을 걸치세요."
}
```

## mcp-schedule

자리 종류(`occasion`)는 앱의 `lib/styling/schedule_rules.dart`와 같습니다. 일정의 데이터이고, 이 자리에 어떤 옷이 맞는지는 Gemini가 판단합니다: `mourning`(장례·조문) `wedding`(결혼식 하객) `formal`(면접·발표·상견례) `business`(회의·출근·수업) `active`(운동·등산) `casual`(그 밖).

### `schedule_add`
"다음 주 토요일 두 시에 친구 결혼식" 같은 말을 Gemini가 나눠서 부릅니다.

입력
```json
{ "userId": "…", "title": "친구 결혼식", "start": "2026-11-14T14:00:00+09:00", "place": "더채플앳청담" }
```
출력
```json
{ "eventId": "e_01", "occasion": "wedding", "placeCategory": "예식장", "spokenSummary": "11월 14일 토요일 오후 2시, 더채플앳청담에서 친구 결혼식을 등록했어요." }
```
`occasion`은 **제목 키워드를 먼저** 보고, 제목으로 못 정하면 `place`를 카카오 로컬 API로 찾은 장소 종류로 정하고, 둘 다 아니면 `casual`입니다(2026-11-04 정함). "친구 결혼식"은 장소가 호텔이어도 결혼식이기 때문입니다. 어느 쪽으로 정했는지는 DB의 `occasion_source`(`title`·`place`·`default`)에 남깁니다. 일정 당일 아침 8시에 FCM 알림을 보냅니다(도구가 아니라 서버 스케줄러).

### `schedule_list`
옷 추천 1단계에서 agent가 오늘 날짜로 부르고, "오늘 일정 뭐야?"에도 씁니다.

입력 `{ "userId": "…", "date": "2026-11-14" }`

출력
```json
{ "events": [{ "eventId": "e_01", "title": "친구 결혼식", "start": "2026-11-14T14:00:00+09:00",
               "place": "더채플앳청담", "placeCategory": "예식장", "occasion": "wedding" }] }
```
일정이 없으면 `{ "events": [] }`.

### `schedule_delete`
입력 `{ "userId": "…", "eventId": "e_01" }` → 출력 `{ "deleted": true }`

## mcp-clothes-state

### `clothes_inspect`
옷 추천 2단계에서 앱이 자동으로 보낸 한 장마다 agent가 직접 부릅니다(Gemini가 고르지 않음). 한 장에 옷이 두 벌 이상 있을 수 있습니다(비교). 얼룩·찢어짐을 **찾는 것**까지 하고, 그걸 어떻게 말할지는 Gemini가 정합니다.

입력 `{ "imageBase64": "<JPEG base64>" }`

출력: 지금 비전 서버의 `ClothesScan`에 `source`와 `modelVersion`을 더한 모양입니다.
```json
{
  "garments": [Garment, ...],
  "framing": null,              // 구도가 안 맞으면 "옷이 오른쪽에 잘렸어요. 폰을 오른쪽으로 조금 옮겨 주세요."
  "lighting": "ok",             // ok | dark
  "source": "model",            // model(우리 모델) | gemini(폴백)
  "modelVersion": "yolo-defect-v1"
}
```
판단 기준: 우리 모델의 결함 확신도가 0.5~0.7 사이인 것이 있으면 그 사진만 Gemini에 다시 묻고 `source: "gemini"`. 0.7 이상은 그대로, 0.5 미만은 버립니다(첫 기준, 학습 후 조정).

## mcp-face-check

### `face_check`
개별 기능입니다("얼굴 확인해 줘"). 옷 추천 흐름에서는 부르지 않습니다.

입력
```json
{ "imageBase64": "<JPEG base64>",
  "landmarks": { "leftEyebrow": [[x,y], ...], "rightEyebrow": [...], "upperLip": [...], "lowerLip": [...] } }
```
`landmarks`는 앱 ML Kit 윤곽점(사진 크기를 1로 본 비율)이고 없으면 서버가 사진만으로 봅니다.

출력
```json
{
  "framing": null,              // "얼굴이 화면 위쪽에 잘렸어요. 폰을 조금 내려 주세요."
  "lighting": "ok",
  "symmetry": { "ok": false, "notes": ["왼쪽 눈썹이 오른쪽보다 조금 짧게 그려졌어요."] },
  "teeth": { "foreignObject": true, "confidence": 0.82, "note": "앞니 사이에 뭔가 낀 것 같아요." },
  "source": "model"
}
```

## mcp-closet

### `closet_save`
옷 추천을 마칠 때("이걸로 할게") agent가 2단계에서 본 옷을 모아 부릅니다. 같은 옷이면 새로 만들지 않고 합칩니다(임베딩 유사도 + 종류·색 일치).

입력 `{ "userId": "…", "garments": [Garment, ...] }`

출력 `{ "saved": [{ "inputId": "g1", "garmentId": "c_17", "isNew": false }] }`

### `closet_wear`
입력 `{ "userId": "…", "garmentIds": ["c_17", "c_03"], "date": "2026-11-04" }` → 출력 `{ "recorded": 2 }`

### `closet_search`
RAG의 **검색 단계**입니다. 옷 추천 1단계에서 agent가 부르고(선택), 찾은 옷과 코디 지식을 Gemini에 넘기면 Gemini가 그 안에서만 골라 추천합니다(생성 단계).

입력
```json
{ "userId": "…", "situation": "오늘 오전 면접, 체감 9도", "occasion": "formal", "apparentTemperature": 9.5,
  "excludeGarmentIds": ["c_17"], "limit": 8 }
```
`situation`은 agent가 일정·날씨로 만든 문장이고 임베딩 검색에 씁니다. `occasion`, `apparentTemperature`는 있으면 필터로 씁니다. `excludeGarmentIds`는 빼고 싶은 옷(예: 어제 입은 옷)입니다.

출력
```json
{
  "candidates": [
    { "garmentId": "c_21", "category": "outer", "name": "자켓", "colorName": "회색", "formality": "smart",
      "lastWorn": "2026-10-28", "score": 0.83 }
  ],
  "styleNotes": [
    { "text": "면접에는 어두운 색 슬랙스와 셔츠, 단정한 자켓이 무난하다.", "source": "style_docs/interview.md" }
  ],
  "empty": false
}
```
옷장이 비어 있으면 `{ "candidates": [], "styleNotes": [...], "empty": true }`.

## mcp-helper

개별 기능입니다. 사용자가 "엄마한테 물어봐 줘"라고 할 때만 씁니다. 옷 추천 흐름에서 자동으로 부르지 않습니다.

### `helper_contacts`
입력 `{ "userId": "…" }` → 출력 `{ "contacts": [{ "contactId": "h_1", "name": "엄마", "relation": "가족" }] }`

### `helper_ask`
입력
```json
{ "userId": "…", "contactId": "h_1", "imageBase64": "<JPEG base64>", "question": "이 옷 오늘 결혼식에 괜찮은지 봐 줄래?" }
```
출력 `{ "requestId": "r_9", "expiresAt": "2026-11-05T09:00:00+09:00", "sentTo": "엄마" }`

사진을 R2에 24시간 두고, `https://<도메인>/h/<token>` 링크를 문자로 보냅니다. 가족이 웹 페이지에서 "괜찮아 / 얼룩 있어 / 직접 쓰기"로 답하면 저장하고 사용자에게 FCM 알림을 보냅니다.

### `helper_answer`
입력 `{ "userId": "…", "requestId": "r_9" }`

출력 `{ "status": "answered", "answer": "얼룩 없어, 그림자야.", "answeredBy": "엄마", "answeredAt": "…" }` (`status`: pending | answered | expired)
