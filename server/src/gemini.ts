import { buildPrompt } from './prompts.ts';
import { GEMINI_RESPONSE_SCHEMA, type Purpose } from './schema.ts';

export interface GeminiConfig {
  apiKey: string;
  model: string;
  /** 테스트에서 가짜 fetch를 넣을 수 있게 한다. */
  fetch?: typeof fetch;
  timeoutMs?: number;
}

export class GeminiError extends Error {
  readonly timedOut: boolean;

  constructor(message: string, timedOut = false) {
    super(message);
    this.timedOut = timedOut;
  }
}

const ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

/** 사진과 목적을 Gemini에 보내고, 정해진 형식의 JSON(파싱 전 값)을 돌려받는다. */
export async function describeWithGemini(
  imageBase64: string,
  purpose: Purpose,
  config: GeminiConfig,
): Promise<unknown> {
  const doFetch = config.fetch ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.timeoutMs ?? 25_000);

  let response: Response;
  try {
    response = await doFetch(`${ENDPOINT}/${config.model}:generateContent`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': config.apiKey,
      },
      body: JSON.stringify({
        contents: [{
          role: 'user',
          parts: [
            { text: buildPrompt(purpose) },
            { inline_data: { mime_type: 'image/jpeg', data: imageBase64 } },
          ],
        }],
        generationConfig: {
          temperature: 0.2,
          responseMimeType: 'application/json',
          responseSchema: GEMINI_RESPONSE_SCHEMA,
        },
      }),
      signal: controller.signal,
    });
  } catch (e) {
    const aborted = e instanceof Error && e.name === 'AbortError';
    throw new GeminiError(aborted ? 'Gemini 응답 시간 초과' : 'Gemini 연결 실패', aborted);
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    // 429는 무료 사용량 초과일 때가 많다. 400은 키·모델·사진 문제인데, 구글이 준 이유를 같이 남긴다.
    const reason = await errorReason(response);
    console.error(`Gemini ${response.status}: ${reason}`); // npx wrangler tail 로 볼 수 있다
    throw new GeminiError(`Gemini 오류 (${response.status})${reason ? `: ${reason}` : ''}`);
  }

  const body = (await response.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const text = body.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new GeminiError('Gemini 응답이 비어 있어요');
  try {
    return JSON.parse(text);
  } catch {
    throw new GeminiError('Gemini 응답이 JSON이 아니에요');
  }
}

/** 구글 오류 본문 {"error":{"message"}}에서 이유만 꺼낸다. 키는 본문에 들어 있지 않다. */
async function errorReason(response: Response): Promise<string> {
  try {
    const text = await response.text();
    try {
      const message = (JSON.parse(text) as { error?: { message?: unknown } }).error?.message;
      if (typeof message === 'string') return message.slice(0, 300);
    } catch {
      // JSON이 아니면 본문 앞부분을 그대로 쓴다.
    }
    return text.slice(0, 300);
  } catch {
    return '';
  }
}
