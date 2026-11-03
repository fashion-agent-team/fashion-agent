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
    // 429는 무료 사용량 초과일 때가 많다.
    throw new GeminiError(`Gemini 오류 (${response.status})`);
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
