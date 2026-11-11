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
    { "kind": "stain", "where": "오른쪽 소매 끝", "confidence": 0.85, "checkedBy": "model" }   // kind: stain | tear | lint | other, checkedBy: model | gpt
  ],
  "box": { "x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4 },
  "position": "left",           // left | center | right (사진 기준 = 사용자 기준). clothes_inspect가 box로 계산
  "confidence": 0.96,
  "embedding": [0.01234, -0.0567, …]   // 옷 박스 사진 벡터 768개(길이 1). 벡터 모델이 없으면 null. 아래 참고
}
```

**`embedding`은 사람에게 읽어 줄 값이 아닙니다**(2026-11-11 추가, mcp-clothes-state 이슈 #15). clothes_inspect가 옷 박스를 Marqo FashionSigLIP으로 바꾼 숫자이고, 옷장이 "같은 옷인지" 판단할 때만 씁니다. agent는 이 값을 closet_save에 그대로 넘기고, **GPT에게 넘길 때는 빼세요**(옷 한 벌에 숫자 768개). 사진은 어디에도 저장하지 않습니다.

**왼쪽·오른쪽은 바라보는 사람(사진) 기준 하나입니다.** 옷을 내려놓고 위에서 비추므로 사진 왼쪽이 사용자 왼쪽입니다.
- `position`(옷이 화면 어디에 있나): box 중심 x가 0.4 미만이면 left, 0.6 초과면 right, 그 사이는 center.
- `where`(옷 한 벌 안의 얼룩 위치): 같은 사진 기준("오른쪽 소매 끝" = 사진에서 오른쪽에 보이는 소매). agent는 이 값을 사용자가 "어디야?"라고 물을 때만 말합니다.

**옷을 입고 찍은 사진(`mode=worn`)은 다릅니다.** 앱은 사진을 좌우로 뒤집지 않고 원본 그대로 보내고, 서버가 자세 인식(pose)으로 입은 사람의 몸 방향을 구해 `where`를 **입은 사람 몸 기준**으로 씁니다("오른쪽 소매" = 입은 사람의 오른팔). 사용자가 자기 몸을 만져 찾기 때문입니다. 얼굴 확인(mcp-face-check)의 셀카 규칙(앱이 뒤집어 보냄)과 다르니 주의하세요. 뒤집지 않고 보내는 것은 2026-11-06 정지원 제안이고, 팀 확인이 필요합니다(미정).

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
`occasion`은 **제목 키워드를 먼저** 보고, 제목으로 못 정하면 `place`를 카카오 로컬 API로 찾은 장소 종류로 정하고, 둘 다 아니면 `casual`입니다(2026-11-04 정함). "친구 결혼식"은 장소가 호텔이어도 결혼식이기 때문입니다. 어느 쪽으로 정했는지는 DB의 `occasion_source`(title·place·fallback)에 남깁니다. 일정 알림은 지금은 **앱이 폰 안에서 예약**합니다(2026-11-11): 앱이 `GET /api/v1/schedules?date=`로 오늘부터 8일 일정을 받아 전날 저녁 8시와 당일 아침 8시(첫 일정이 9시보다 이르면 1시간 전)에 로컬 알림을 겁니다. 앱을 열 때, agent와 대화를 마칠 때, 앱으로 돌아올 때 다시 맞춥니다(`lib/services/schedule_reminders.dart`). 원격 푸시(FCM·APNs)는 유료 Apple 개발자 계정이 생기면 서버 스케줄러(`MorningReminder`)로 옮길 수 있습니다.

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
  "source": "model",            // model(우리 모델) | helper(지인 확인)
  "modelVersion": "yolo26n-v6",
  "pendingHelper": null,        // 애매한 결함이 있을 때만 값이 있음(아래)
  "embeddingModel": "marqo-fashionSigLIP"   // garments[].embedding을 만든 모델. 없으면 null
}
```
판단 기준은 결함(`defects`) 하나하나의 모델 확신도로 정합니다(2026-11-06 결정. 근거는 mcp-clothes-state PR #2 `docs/model-comparison.md` "판단 기준 제안". 2026-11-08 확정: 모델 yolo26n v6 하나, 기준 0.5 / 0.3. 실험 기록은 mcp-clothes-state PR #5).

**옷 사진은 GPT 비전으로 보내지 않습니다**(2026-11-06 결정). 모델이 애매하면 지어내지 않고, 사용자가 원할 때 지인에게만 묻습니다.

| 확신도 | 처리 |
|---|---|
| 0.5 이상 | 결함으로 보고 `defects`에 넣어 바로 알립니다. |
| 0.3 이상 0.5 미만 | 애매함. `defects`에 넣지 않고 `pendingHelper.candidates`에 모읍니다. |
| 0.3 미만 | 버립니다. |

애매한 것이 있으면 이렇게 돌려줍니다. 사진은 넣지 않고 위치(box)만 줍니다. agent가 이 결과를 그대로 GPT에 넘기기 때문입니다.
```json
"pendingHelper": {
  "garmentId": "g1",
  "candidates": [
    { "kind": "stain", "where": "오른쪽 소매 끝", "confidence": 0.42,
      "box": { "x": 0.62, "y": 0.30, "w": 0.08, "h": 0.06 } }   // 원본 사진 기준 비율
  ],
  "note": "확실하지 않은 부분이 있어요."
}
```
- agent는 확실한 결함(0.5 이상)을 먼저 말하고, `note`를 읽은 뒤 "지인에게 물어볼까요?"라고 묻습니다. `note`에는 위치를 넣지 않습니다. `where`는 다른 결함과 같이 사용자가 "어디야?"라고 물을 때만 말합니다.
- 사용자가 원할 때만 `helper_ask`를 부릅니다. agent는 clothes_inspect에 보냈던 원본 사진에서 그 옷 한 벌(`garmentId`의 `box`)만 잘라 내고, 후보 `box`마다 테두리를 그린 **한 장**을 `imageBase64`로 넣습니다. 후보가 여러 개여도 한 벌에 한 번만 묻습니다(helper_ask 입력은 바꾸지 않음). 질문은 "표시한 곳이 얼룩인지 봐 줄래?"처럼 씁니다. 얼굴이 들어가지 않게 옷 부분만 보냅니다.
- 답은 지금은 사용자가 "답 왔어?"라고 물으면 agent가 `helper_answer`로 확인합니다(FCM 알림은 gateway가 생긴 뒤, helper_answer 절과 같음). 답으로 알릴 때 `source`는 `helper`입니다. 기다리는 동안 다른 안내는 그대로 이어 갑니다.
- 등록된 지인이 없거나 사용자가 묻지 않겠다고 하면 "확실하지 않은 부분이 있어요"까지만 말하고 끝냅니다.

## mcp-face-check

개별 기능입니다("얼굴 확인해 줘"). 옷 추천 흐름에서는 부르지 않습니다. 찍는 방법이 달라서 **얼굴(화장 대칭)과 치아를 나눠** 봅니다. agent가 먼저 "얼굴을 볼까요, 이를 확인할까요?"라고 묻고, 답에 맞는 도구 하나를 부릅니다(2026-11-05 팀 결정).

**왼쪽·오른쪽은 셀카 화면(거울) 기준입니다.** 앱은 보내기 전에 사진과 윤곽점을 셀카 화면처럼 좌우를 뒤집어 맞춥니다(폰·플러그인마다 전면 카메라 사진 저장 방향이 달라서). 그러면 옷과 같은 규칙 "사진 왼쪽 = 사용자 왼쪽"이 됩니다. 서버는 받은 사진 그대로 왼쪽·오른쪽을 말합니다.

사진은 앱이 카메라 영상에서 구도가 맞는 순간 한 장면만 꺼내 보낸 것이고, 서버는 판단에만 쓰고 남기지 않습니다.

**얼굴·치아 사진은 GPT 같은 외부 AI로 보내지 않습니다**(개인정보, 2026-11-06 결정). 대칭은 윤곽점 계산으로, 치아는 우리가 학습한 모델(ONNX)을 이 서버에서 돌려서 봅니다. 그래서 두 도구에는 `source` 값이 없습니다. 모델이 애매하면 지어내지 않고 "잘 모르겠다"고 돌려주고, agent가 가족·친구에게 물어볼지(helper) 제안합니다.

### `face_makeup_check`
"얼굴 볼래" → 앱이 얼굴을 실시간으로 비추며 구도를 안내하고, 잘 잡혀 1초 멈추면 그동안 찍은 3~5장을 보냅니다(2026-11-05 결정). 화장 대칭(눈썹, 입술 선, 볼·입술 색 좌우)을 장마다 재고 항목별 중간값으로 판단합니다. GPT는 쓰지 않습니다.

입력
```json
{ "imageBase64": "<JPEG base64>",
  "landmarks": { "leftEye": [[x,y], ...], "rightEye": [...],
                 "leftEyebrowTop": [...], "leftEyebrowBottom": [...], "rightEyebrowTop": [...], "rightEyebrowBottom": [...],
                 "upperLipTop": [...], "upperLipBottom": [...], "lowerLipTop": [...], "lowerLipBottom": [...],
                 "face": [...], "noseBridge": [...], "noseBottom": [...], "leftCheek": [[x,y]], "rightCheek": [[x,y]],
                 "yaw": 3.5, "roll": -2.0 },
  "frames": [ { "imageBase64": "…", "landmarks": { … } }, … ] }   // 같은 1초의 나머지 장면(최대 4개)
```
`landmarks`는 앱 ML Kit 얼굴 인식 **윤곽(contour) 모드** 결과입니다. 키는 ML Kit `FaceContour` 상수 이름을 camelCase로(LEFT_EYEBROW_TOP → `leftEyebrowTop`), 점은 사진 크기를 1로 본 비율이고 셀카 방향으로 뒤집은 뒤 좌표입니다. `yaw`, `roll`은 `headEulerAngleY`, `headEulerAngleZ`(도). 꼭 필요한 것은 `leftEye`, `rightEye`, `leftEyebrowTop`, `rightEyebrowTop`, `upperLipTop`, `lowerLipBottom`이고, 나머지는 있으면 더 정확합니다. 서버는 이름의 left/right를 믿지 않고 두 눈의 x 위치로 왼쪽을 다시 정합니다. 필수 윤곽이 없으면 `{"error": {"code": "no_landmarks"}}`(다시 찍기)입니다. 윤곽점은 위치를 잡는 데만 쓰고, 그려진 눈썹·입술 모양과 색은 사진 픽셀에서 잽니다(윤곽점은 그린 화장선을 따라가지 않음). "얼마나 다르면 비대칭인가" 기준값은 라벨 붙인 셀카로 학습합니다(mcp-face-check `training/`).

출력
```json
{
  "framing": null,              // "얼굴이 화면 위쪽에 잘렸어요. 폰을 조금 내려 주세요."
  "lighting": "ok",
  "symmetry": {
    "ok": false,
    "notes": ["왼쪽 눈썹이 오른쪽보다 조금 짧게 그려졌어요."],   // 차이가 큰 순서로 최대 3개, agent가 그대로 읽음
    "checks": [{ "name": "browLength", "side": "right", "value": 0.21, "limit": 0.15, "ok": false }, ...],  // 기준값 맞추기용
    "skipped": [],              // 한쪽이 그늘져 건너뛴 색 비교: cheekColor, lipColor
    "frames": 3                 // 판단에 쓴 장 수
  }
}
```
`framing`이 있거나 `lighting`이 `dark`면(절반 넘는 장이 그러면) `symmetry`는 `null`입니다. 비교 항목과 기준값은 mcp-face-check `docs/DEVELOPMENT.md`에 있습니다.

### `teeth_check`
"이 확인해 줘" → 폰을 입 가까이 대고 "'이~' 해 주세요" 안내. 앱이 ML Kit 입술 윤곽으로 입이 벌어진 걸 확인한 뒤 한 장. 이 사이에 낀 것을 봅니다.

입력
```json
{ "imageBase64": "<JPEG base64>",
  "mouthBox": { "x": 0.3, "y": 0.55, "w": 0.4, "h": 0.2 } }
```
`mouthBox`는 앱이 ML Kit 입술 윤곽 `UPPER_LIP_BOTTOM`과 `LOWER_LIP_TOP` 점으로 구한 입 안쪽 박스(비율)입니다. 서버는 이 박스의 긴 변 × 1.36 정사각형으로 잘라(학습 때와 같은 규칙) 모델에 넣습니다. 없으면 서버가 사진에서 찾습니다.

출력
```json
{
  "framing": null,              // "입이 다 보이지 않아요. 입을 조금 더 벌려 주세요."
  "lighting": "ok",
  "teeth": { "foreignObject": true, "confidence": 0.82, "note": "앞니 사이에 뭔가 낀 것 같아요." }
}
```
`foreignObject`는 모델 확률로 정합니다. 0.7 이상이면 `true`, 0.3 이하면 `false`, 그 사이는 `null`(애매함)입니다(첫 기준, 실제 사진으로 평가한 뒤 조정).
애매하면 `{"foreignObject": null, "confidence": 0.5, "note": "잘 보이지 않아서 확실하지 않아요."}`를 돌려주고, agent는 note를 읽은 뒤 "가족에게 사진 보내서 물어볼까요?"라고 묻습니다. 사용자가 원할 때만 `helper_ask`로 넘깁니다.

## mcp-closet

### `closet_save`
옷 추천을 마칠 때("이걸로 할게") agent가 2단계에서 본 옷을 모아 부릅니다. 같은 옷이면 새로 만들지 않고 합칩니다(`isNew: false`).

**옷 사진 벡터로 판단합니다**(2026-11-11 바뀜). clothes_inspect가 준 `garments[].embedding`과 `embeddingModel`을 그대로 넘기면, 같은 종류(category)이고 같은 모델로 만든 벡터가 있는 내 옷 중 가장 가까운 옷이 기준 이상일 때 합칩니다. 색 이름·색 계열·톤은 보지 않습니다. 같은 옷도 사진마다 색 판별이 달라져서 예전 규칙은 다시 찍은 옷을 36%만 맞게 합쳤고, 흰 티셔츠처럼 흔한 옷은 엉뚱한 옷에 합쳤습니다. 사진 벡터로는 DeepFashion 옷 600벌 측정에서 78%를 맞게 합치고 엉뚱하게 합치는 경우는 1.4%입니다(CC0 옷 사진으로 만든 보정 행렬, 기본값)(새 옷을 잘못 합치는 비율 5% 기준, mcp-closet `docs/DEVELOPMENT.md`). 합칠 때마다 그 옷의 벡터를 지금까지 본 사진의 평균으로 바꿔서 볼수록 더 잘 알아봅니다.

벡터가 없으면(clothes_inspect에 벡터 모델이 없거나, 길이가 768이 아니거나, `embeddingModel`을 안 넘김) 예전 규칙을 씁니다: 종류·색 계열이 같고, 글 임베딩 유사도 0.90 이상이고, 이름이 같은 묶음(니트=스웨터 …)이고, 톤(밝음↔어두움)과 무늬가 부딪히지 않을 때.

어느 쪽이든 이럴 때는 합치지 않습니다.
- 한 번에 넘긴 옷끼리(한 사진에 같이 있으면 다른 옷), 그리고 두 벌을 같은 옛 옷 하나에 합치지 않습니다.
- `forceNewIds`에 넣은 입력 id. 합쳤다고 알렸는데 사용자가 "그건 다른 옷이에요"라고 하면 agent가 그 옷을 이 목록에 넣어 다시 부릅니다.

입력 `{ "userId": "…", "garments": [Garment, ...], "forceNewIds": ["g2"], "embeddingModel": "marqo-fashionSigLIP" }` (`forceNewIds`, `embeddingModel`은 선택)

출력 `{ "saved": [{ "inputId": "g1", "garmentId": "c_17", "isNew": false }] }`

### `closet_wear`
입력 `{ "userId": "…", "garmentIds": ["c_17", "c_03"], "date": "2026-11-04" }` → 출력 `{ "recorded": 2 }`

`date`가 없으면 서울 기준 오늘. 같은 날 함께 기록한 옷이 그날의 조합이 됩니다(`closet_outfits`). 남의 옷이나 없는 id가 섞이면 `not_found`이고 아무것도 기록하지 않습니다.

### `closet_search`
RAG의 **검색 단계**입니다. 옷 추천 1단계에서 agent가 부르고(선택), 찾은 옷과 코디 지식을 GPT에 넘기면 GPT가 그 안에서만 골라 추천합니다(생성 단계).

입력
```json
{ "userId": "…", "situation": "오늘 오전 면접, 체감 9도", "occasion": "formal", "apparentTemperature": 9.5,
  "excludeGarmentIds": ["c_17"], "limit": 8, "imageQuery": "formal office attire for a job interview" }
```
`situation`은 agent가 일정·날씨로 만든 문장이고 임베딩 검색에 씁니다. `occasion`, `apparentTemperature`는 있으면 필터로 씁니다(앱 `schedule_rules`·`weather_rules`가 "맞지 않아요"라고 하는 옷만 뺌, 예: 면접에 운동복, 체감 23도 이상에 겉옷). `excludeGarmentIds`는 꼭 빼고 싶은 옷입니다.

`imageQuery`(선택, 200자 이내)는 찾는 옷을 **짧은 영어**로 쓴 것입니다(예: `jeans`, `striped clothes`, `warm winter clothes`). agent의 GPT가 `situation`을 영어로 옮겨 채웁니다. closet이 FashionSigLIP 글 모델로 옷 사진 벡터(closet_save 때 받은 `embedding`)와 비교해 점수에 더하므로, 이름·상황 질문 모두 더 잘 찾습니다(실측 위 5개 정답: 이름 44→57%, 상황 28→37%). 서버에 글 모델이 없으면 무시합니다.

closet_save는 사진 벡터가 있으면 그것으로 옷 이름(청바지·블라우스·카디건 …)을 다시 고르고 비어 있는 무늬·격식을 채웁니다. 그래서 후보의 `name`이 clothes_inspect가 준 이름과 다를 수 있습니다(예: 티셔츠 → 블라우스).

`score`는 임베딩 유사도에 자리에 맞는 격식이면 최대 0.06을 더하고, 최근에 입은 옷이면 뺀 값입니다(어제 0.06, 그제 0.04, 일주일 안 0.02). 최근 입은 옷은 빼지 않고 뒤로만 보냅니다(옷이 적은 사람도 추천을 받게). 후보는 종류(상의·하의·겉옷·신발)를 돌아가며 골라 한 종류로 몰리지 않습니다.

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

### `closet_outfits`
예전에 입은 조합입니다. 같은 날 `closet_wear`로 기록한 옷을 한 벌로 묶어 최근 날부터 줍니다. 개별 기능("지난번 면접 때 뭐 입었지?", "이 셔츠 전에 뭐랑 입었어?", "요즘 뭐 입었지?")에 쓰고, 옷 추천 흐름에서 자동으로 부르지 않습니다. "면접 때"처럼 일정으로 물으면 agent가 `schedule_list`로 날짜를 찾아 `from`·`to`에 넣습니다.

입력 `{ "userId": "…", "from": "2026-10-01", "to": "2026-11-04", "garmentId": "c_17", "limit": 5 }` (userId 말고는 선택. `to` 기본 오늘, `from` 기본 `to`의 90일 전, `limit` 기본 5·최대 30)

출력
```json
{ "outfits": [
  { "date": "2026-10-28",
    "garments": [
      { "garmentId": "c_21", "category": "outer", "name": "자켓", "colorName": "남색", "formality": "smart" },
      { "garmentId": "c_17", "category": "top", "name": "셔츠", "colorName": "흰색", "formality": "smart" },
      { "garmentId": "c_05", "category": "bottom", "name": "슬랙스", "colorName": "검은색", "formality": "formal" } ] } ] }
```
한 날 안의 옷은 겉옷·상의·원피스·하의·신발 순입니다. 기록이 없으면 `{ "outfits": [] }`. 남의 옷 `garmentId`는 `not_found`. 하루에 두 번 갈아입어도 한 벌로 묶입니다(표를 바꾸지 않으려고 `wears`만 씀).

### `closet_list`
옷장에 있는 옷 목록입니다. 개별 기능("내 옷장에 뭐 있어?", "바지 뭐 있지?")에 쓰고, 지울 옷을 사용자와 확인할 때도 씁니다.

입력 `{ "userId": "…", "category": "bottom", "limit": 50 }` (`category`·`limit` 선택, `limit` 기본 50)

출력
```json
{ "garments": [
    { "garmentId": "c_21", "category": "outer", "name": "자켓", "colorName": "남색", "formality": "smart",
      "lastWorn": "2026-10-28", "wearCount": 3 } ],
  "total": 14 }
```
겉옷·상의·원피스·하의·신발 순, 같은 종류는 최근에 본 옷부터. `lastWorn`은 입은 기록이 없으면 null. `total`은 전체(또는 그 종류) 벌 수. 모르는 `category`는 `bad_request`.

### `closet_remove`
옷을 지웁니다(버린 옷, 잘못 저장된 옷). 되돌릴 수 없고 그 옷의 입은 날 기록도 함께 지워져 `closet_outfits`에서 빠집니다. agent는 어떤 옷인지 읽어 주고 사용자가 "지워"라고 한 뒤에만 부릅니다.

입력 `{ "userId": "…", "garmentIds": ["c_17"] }` → 출력 `{ "removed": 1 }`

남의 옷이나 없는 id가 섞이면 `not_found`이고 아무것도 지우지 않습니다.

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
