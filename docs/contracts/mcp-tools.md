# MCP 도구 입출력

agent가 부르는 MCP 도구의 이름과 JSON 입출력입니다. 서버는 Spring AI MCP Server(Streamable HTTP, `/mcp`)로 만들고, 메서드에 `@Tool`을 붙입니다. 도구 설명(`description`)은 GPT가 읽고 고르는 근거라 **한국어로 언제 쓰는지까지** 적습니다.

**MCP 서버는 데이터만 돌려줍니다.** "이 옷이 오늘 일정·날씨에 맞는가" 같은 판단과 추천은 agent가 GPT에 맡깁니다(흐름과 GPT 입출력은 [README.md 5절](README.md#5-기능-구분과-agent-처리-방법)).

공통:

- `userId`가 있는 도구는 agent가 `X-User-Id` 값으로 덮어써서 넣습니다. GPT가 채운 값은 쓰지 않습니다.
- 실패하면 도구 결과로 `{"error": {"code", "message"}}`를 돌려줍니다(예외를 그대로 던지지 않기). agent가 이걸 보고 사용자에게 안내합니다.
- 사람에게 읽어 줄 문장(`spokenSummary` 등)은 한국어 존댓말 한 문장씩.

## 공통 모양: Garment

지금 앱의 `Garment`(lib/models/garment.dart)와 같은 모양입니다. clothes_inspect가 만들고, closet이 저장하며, agent가 GPT에 넘깁니다.

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

자리 종류(`occasion`)는 앱의 `lib/styling/schedule_rules.dart`와 같습니다. 일정의 데이터이고, 이 자리에 어떤 옷이 맞는지는 GPT가 판단합니다: `mourning`(장례·조문) `wedding`(결혼식 하객) `formal`(면접·발표·상견례) `business`(회의·출근·수업) `active`(운동·등산) `casual`(그 밖).

### `schedule_add`
"다음 주 토요일 두 시에 친구 결혼식" 같은 말을 GPT가 나눠서 부릅니다.

입력
```json
{ "userId": "…", "title": "친구 결혼식", "start": "2026-11-14T14:00:00+09:00", "place": "더채플앳청담" }
```
출력
```json
{ "eventId": "e_01", "occasion": "wedding", "placeCategory": "예식장", "spokenSummary": "11월 14일 토요일 오후 2시, 더채플앳청담에서 친구 결혼식을 등록했어요." }
```
`occasion`은 **제목 키워드를 먼저** 보고, 제목으로 못 정하면 `place`를 카카오 로컬 API로 찾은 장소 종류로 정하고, 둘 다 아니면 `casual`입니다(2026-11-04 정함). "친구 결혼식"은 장소가 호텔이어도 결혼식이기 때문입니다. 어느 쪽으로 정했는지는 DB의 `occasion_source`(title·place·fallback)에 남깁니다. 일정 당일 아침 8시에 FCM 알림을 보냅니다(도구가 아니라 서버 스케줄러).

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
옷 추천 2단계에서 앱이 자동으로 보낸 한 장마다 agent가 직접 부릅니다(GPT가 고르지 않음). 한 장에 옷이 두 벌 이상 있을 수 있습니다(비교). 얼룩·찢어짐을 **찾는 것**까지 하고, 그걸 어떻게 말할지는 GPT가 정합니다.

입력 `{ "imageBase64": "<JPEG base64>", "mode": "laid", "view": null }`

- `mode`(없으면 `laid`): `laid`는 내려놓은 옷을 위에서 찍은 사진, `worn`은 옷을 입은 사람이 폰(세워 둠) 앞에 선 사진입니다(2026-11-06 추가).
- `view`(`mode=worn`일 때만): `front` | `side` | `back`. agent가 앞→옆→뒤 순서로 한 장씩 부릅니다. 앞모습에서 옷 종류·색을 정하고, 옆·뒤에서는 얼룩·찢어짐을 더 찾습니다. 옆·뒤 사진에서는 보이는 옷만 돌려주면 됩니다.
- `mode=worn`이면 `where`는 **입은 사람 몸 기준**("오른쪽 소매" = 입은 사람의 오른팔, "등 가운데")으로 씁니다. 사용자가 자기 몸을 만져 찾기 때문입니다. `position`은 쓰지 않아도 됩니다. 몸이 다 안 들어오면 `framing`에 "발이 안 보여요. 한 걸음 더 물러나 주세요." 같은 안내를 넣습니다.

출력: 지금 비전 서버의 `ClothesScan`에 `source`와 `modelVersion`을 더한 모양입니다.
```json
{
  "garments": [Garment, ...],
  "framing": null,              // 구도가 안 맞으면 "옷이 오른쪽에 잘렸어요. 폰을 오른쪽으로 조금 옮겨 주세요."
  "lighting": "ok",             // ok | dark
  "source": "model",            // model(우리 모델) | gpt(폴백)
  "modelVersion": "yolo-defect-v1"
}
```
판단 기준: 우리 모델의 결함 확신도가 0.5~0.7 사이인 것이 있으면 그 사진만 GPT에 다시 묻고 `source: "gpt"`. 0.7 이상은 그대로, 0.5 미만은 버립니다(첫 기준, 학습 후 조정).

## mcp-face-check

개별 기능입니다("얼굴 확인해 줘"). 옷 추천 흐름에서는 부르지 않습니다. 찍는 방법이 달라서 **얼굴(화장 대칭)과 치아를 나눠** 봅니다. agent가 먼저 "얼굴을 볼까요, 이를 확인할까요?"라고 묻고, 답에 맞는 도구 하나를 부릅니다(2026-11-05 팀 결정).

**왼쪽·오른쪽은 셀카 화면(거울) 기준입니다.** 앱은 보내기 전에 사진과 윤곽점을 셀카 화면처럼 좌우를 뒤집어 맞춥니다(폰·플러그인마다 전면 카메라 사진 저장 방향이 달라서). 그러면 옷과 같은 규칙 "사진 왼쪽 = 사용자 왼쪽"이 됩니다. 서버는 받은 사진 그대로 왼쪽·오른쪽을 말합니다.

사진은 앱이 카메라 영상에서 구도가 맞는 순간 한 장면만 꺼내 보낸 것이고, 서버는 판단에만 쓰고 남기지 않습니다.

### `face_makeup_check`
"얼굴 볼래" → 얼굴 전체가 들어오게 안내한 한 장. 화장 대칭(눈썹, 입술 선, 볼·입술 색 좌우)을 봅니다.

입력
```json
{ "imageBase64": "<JPEG base64>",
  "landmarks": { "leftEyebrow": [[x,y], ...], "rightEyebrow": [...], "upperLip": [...], "lowerLip": [...] } }
```
`landmarks`는 앱 ML Kit 윤곽점(사진 크기를 1로 본 비율, 셀카 방향으로 뒤집은 뒤 좌표)이고 없으면 서버가 사진만으로 봅니다.

출력
```json
{
  "framing": null,              // "얼굴이 화면 위쪽에 잘렸어요. 폰을 조금 내려 주세요."
  "lighting": "ok",
  "symmetry": { "ok": false, "notes": ["왼쪽 눈썹이 오른쪽보다 조금 짧게 그려졌어요."] },
  "source": "model"             // model | gpt
}
```

### `teeth_check`
"이 확인해 줘" → 폰을 입 가까이 대고 "'이~' 해 주세요" 안내. 앱이 ML Kit 입술 윤곽으로 입이 벌어진 걸 확인한 뒤 한 장. 이 사이에 낀 것을 봅니다.

입력
```json
{ "imageBase64": "<JPEG base64>",
  "mouthBox": { "x": 0.3, "y": 0.55, "w": 0.4, "h": 0.2 } }
```
`mouthBox`는 앱이 입술 윤곽으로 구한 입 영역(비율)이고, 서버는 이 부분을 잘라서 봅니다. 없으면 서버가 사진에서 찾습니다.

출력
```json
{
  "framing": null,              // "입이 다 보이지 않아요. 입을 조금 더 벌려 주세요."
  "lighting": "ok",
  "teeth": { "foreignObject": true, "confidence": 0.82, "note": "앞니 사이에 뭔가 낀 것 같아요." },
  "source": "model"             // model | gpt
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
RAG의 **검색 단계**입니다. 옷 추천 1단계에서 agent가 부르고(선택), 찾은 옷과 코디 지식을 GPT에 넘기면 GPT가 그 안에서만 골라 추천합니다(생성 단계).

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

사진을 R2에 24시간 두고, `옷 확인 부탁해요 https://<도메인>/h/<token>` 한 줄을 SMS(90바이트 이하)로 보냅니다(솔라피). 질문은 문자에 넣지 않고 답장 페이지에서 보여 줍니다. 가족이 웹 페이지에서 "괜찮아 / 얼룩 있어 / 직접 쓰기"로 답하면 저장하고, 사진은 그때 바로 지웁니다. 답이 오지 않아도 24시간 뒤에 지웁니다.

- 사진은 JPEG만, 약 6MB까지. 질문은 200자까지. 한 사용자가 한 시간에 10번까지 보낼 수 있습니다.
- 오류 `code`: `bad_request`(userId·질문이 틀림), `no_image`, `bad_image`(JPEG 아님), `image_too_large`, `not_found`(등록하지 않은 contactId), `rate_limited`, `upstream_failed`(문자·R2 실패. 이때는 요청을 남기지 않음).
- 답이 왔을 때 사용자에게 보내는 FCM 알림은 gateway가 생긴 뒤에 붙입니다(푸시 토큰이 gateway의 `account` 스키마에 있음). 그 전까지는 사용자가 "답 왔어?"라고 물으면 agent가 `helper_answer`로 확인합니다.

### `helper_answer`
입력 `{ "userId": "…", "requestId": "r_9" }`

출력
```json
// 답이 왔을 때
{ "requestId": "r_9", "status": "answered", "answer": "얼룩 없어, 그림자야.", "answeredBy": "엄마",
  "answeredAt": "2026-11-04T14:20:00+09:00", "sentTo": "엄마", "expiresAt": "2026-11-05T09:00:00+09:00" }
// 아직일 때
{ "requestId": "r_9", "status": "pending", "answer": null, "answeredBy": null, "answeredAt": null,
  "sentTo": "엄마", "expiresAt": "2026-11-05T09:00:00+09:00" }
```
`status`: pending | answered | expired. `answer`·`answeredBy`·`answeredAt`은 answered일 때만 값이 있고 나머지는 null입니다. `sentTo`·`expiresAt`은 항상 있어서, agent가 "엄마가 아직 답하지 않았어요. 내일 오전 9시까지 기다릴게요"처럼 말할 수 있습니다. 다른 사용자의 requestId면 `not_found`.
