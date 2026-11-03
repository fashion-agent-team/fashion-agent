# 비전 프록시 (server/)

앱과 비전 LLM 사이에 두는 작은 서버입니다. **API 키는 여기에만 두고 앱에는 넣지 않습니다.** 프롬프트와 응답 형식도 여기서 관리해서, 앱을 다시 배포하지 않고 고칠 수 있게 합니다.

Cloudflare Workers + Gemini API로 만든 뼈대입니다. 앱은 `VISION_URL`을 주지 않으면 지금처럼 `FakeVisionService`(예시 응답)로 돕니다.

## 파일

| 파일 | 하는 일 |
| --- | --- |
| `src/index.ts` | 요청 받기. 주소·purpose·사진 크기·앱 토큰 확인, 오류 코드 정리 |
| `src/prompts.ts` | 옷 검사(outfit) 프롬프트. 격식·얼룩/찢어짐 기준 포함. **문구 다듬기는 여기서** |
| `src/gemini.ts` | Gemini 호출. 응답을 아래 JSON 형식으로만 받도록 강제 |
| `src/schema.ts` | 응답 형식 정의와 정리(모르는 값은 기본값, id는 g1·g2… 부여) |
| `test/` | 가짜 Gemini로 하는 테스트 |

## 실행

Node 22.6 이상이 필요합니다.

```bash
cd server
npm install
npm test                       # 가짜 Gemini로 테스트
cp .dev.vars.example .dev.vars # GEMINI_API_KEY 채우기 (커밋 금지)
npm run dev                    # http://localhost:8787
```

앱을 로컬 서버에 붙이기:

```bash
flutter run --dart-define=VISION_URL=http://localhost:8787
# 안드로이드 에뮬레이터는 http://10.0.2.2:8787
```

배포:

```bash
npx wrangler login
npx wrangler secret put GEMINI_API_KEY
npm run deploy                 # 나온 https://….workers.dev 주소를 VISION_URL로
```

모델은 `wrangler.toml`의 `GEMINI_MODEL`에서 바꿉니다. `APP_TOKEN` 비밀 값을 넣으면 `X-App-Token` 헤더가 같은 요청만 받습니다. 앱은 아직 이 헤더를 보내지 않으니, 토큰을 켜기 전에 `HttpVisionService`에 헤더를 추가해야 합니다.

## 오류 응답

200이 아니면 앱은 "분석하지 못했어요"라고 안내하고 다시 찍게 합니다. 본문은 `{"error": {"code", "message"}}`입니다.

| 상태 | code | 언제 |
| --- | --- | --- |
| 400 | `bad_json`, `bad_purpose`, `no_image` | 요청 형식이 틀림 |
| 401 | `unauthorized` | 앱 토큰이 다름 |
| 413 | `image_too_large` | 사진이 약 6MB 넘음 |
| 502 | `ai_failed`, `ai_bad_response` | Gemini 오류(무료 한도 초과 429 포함), 형식이 이상한 응답 |
| 504 | `ai_timeout` | 25초 안에 답이 없음 |

## 남은 일

- TODO(AI 담당): 실제 옷 사진으로 프롬프트 다듬기, `confidence` 기준이 맞는지 확인
- TODO: 앱 `HttpVisionService`에 `X-App-Token` 헤더 추가 후 토큰 켜기
- TODO: 무료 한도 초과(429) 때 사용자에게 따로 안내할지 정하기

## 엔드포인트

### `POST /describe-clothes`

옷 검사에서 펼쳐 놓은 옷을 분석합니다. 일정·날씨에 맞는지 판단은 앱이 하고, AI는 격식과 얼룩·찢어짐 같은 보이는 사실만 돌려줍니다.

요청

```json
{
  "purpose": "outfit",        // 지금은 outfit 하나
  "image": "<base64 JPEG>"
}
```

응답 (앱의 `ClothesScan.fromJson`과 같은 모양)

```json
{
  "garments": [
    {
      "id": "g1",
      "category": "top",            // top | bottom | outer | dress | shoes | other
      "name": "셔츠",
      "colorName": "남색",          // 사용자에게 그대로 읽어 줄 색 이름
      "colorFamily": "navy",        // black white gray navy beige brown khaki blue red pink orange yellow green purple unknown
      "tone": "dark",               // light | mid | dark
      "pattern": "줄무늬",          // 무늬 없으면 null
      "material": "면 같음",        // 사진으로 본 추정. 모르면 null
      "notes": "약간 구김 있음",    // 그 밖의 상태. 없으면 null
      "formality": "smart",         // formal(정장·구두) | smart(셔츠·니트·슬랙스) | casual(티·청바지) | sporty(운동복) | unknown
      "defects": [                  // 얼룩·찢어짐. 없으면 []
        { "kind": "stain", "where": "오른쪽 소매 끝", "confidence": 0.85 }  // kind: stain | tear | lint | other
      ],
      "box": { "x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4 },  // 사진 크기를 1로 본 비율
      "confidence": 0.86            // 0~1. 색을 얼마나 확신하는지
    }
  ],
  "framing": null,                  // 구도가 안 맞으면 "옷이 오른쪽에 잘렸어요. 폰을 오른쪽으로 조금 옮겨 주세요."
  "lighting": "ok"                  // ok | dark
}
```

## 프롬프트 원칙

- **본 사실만** 답하게 합니다. "어울린다", "예쁘다" 같은 판단은 묻지도 받지도 않습니다. 판단은 앱의 `lib/styling/` 규칙이 합니다.
- `defects`는 사진에서 실제로 보이는 것만 넣게 합니다. `where`는 "오른쪽 소매 끝", "밑단 왼쪽"처럼 손으로 찾아갈 수 있는 말로 받습니다. 애매하면 `confidence`를 낮추게 합니다. 앱은 0.7 미만이면 "손으로 확인해 보세요"라고만 말합니다.
- 색이 조명 때문에 애매하면 `confidence`를 낮추게 합니다. 앱은 0.6 미만이면 판단하지 않고 다시 비춰 달라고 합니다.
- `framing`은 "흐려요"가 아니라 "폰을 오른쪽으로", "한 걸음 뒤로"처럼 사용자가 바로 따라 할 수 있는 문장으로 받습니다.
- 응답은 위 JSON 스키마로 강제합니다(LLM의 구조화 출력 기능 사용).
