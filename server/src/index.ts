import { describeWithGemini, GeminiError } from './gemini.ts';
import { isPurpose, normalizeScan, SchemaError, type Purpose } from './schema.ts';

export interface Env {
  GEMINI_API_KEY: string;
  GEMINI_MODEL: string;
  /** 비워 두면 검사하지 않는다. 채우면 앱이 X-App-Token 헤더로 같은 값을 보내야 한다. */
  APP_TOKEN?: string;
}

/** 테스트에서 Gemini 호출을 바꿔 끼우기 위한 자리. */
export interface Deps {
  describe: (imageBase64: string, purpose: Purpose, env: Env) => Promise<unknown>;
}

const defaultDeps: Deps = {
  describe: (image, purpose, env) =>
    describeWithGemini(image, purpose, { apiKey: env.GEMINI_API_KEY, model: env.GEMINI_MODEL }),
};

/** base64 문자열 길이 기준. 약 6MB JPEG까지 받는다. */
const MAX_IMAGE_BASE64 = 8_000_000;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-App-Token',
};

export async function handle(request: Request, env: Env, deps: Deps = defaultDeps): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (url.pathname === '/health') return json({ ok: true });
  if (url.pathname !== '/describe-clothes') return error(404, 'not_found', '없는 주소예요');
  if (request.method !== 'POST') return error(405, 'method_not_allowed', 'POST만 받아요');

  if (env.APP_TOKEN && request.headers.get('X-App-Token') !== env.APP_TOKEN) {
    return error(401, 'unauthorized', '앱 토큰이 맞지 않아요');
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return error(400, 'bad_json', '요청 본문이 JSON이 아니에요');
  }
  const { purpose, image } = (body ?? {}) as { purpose?: unknown; image?: unknown };
  if (!isPurpose(purpose)) return error(400, 'bad_purpose', 'purpose는 outfit, closet, check 중 하나예요');
  if (typeof image !== 'string' || image.length === 0) return error(400, 'no_image', 'image(base64 JPEG)가 없어요');
  if (image.length > MAX_IMAGE_BASE64) return error(413, 'image_too_large', '사진이 너무 커요');

  try {
    const raw = await deps.describe(image, purpose, env);
    return json(normalizeScan(raw));
  } catch (e) {
    if (e instanceof GeminiError) {
      return error(e.timedOut ? 504 : 502, e.timedOut ? 'ai_timeout' : 'ai_failed', e.message);
    }
    if (e instanceof SchemaError) return error(502, 'ai_bad_response', e.message);
    throw e;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS },
  });
}

// 앱은 200이 아니면 "분석하지 못했어요… 다시 눌러 주세요"로 안내한다. code는 로그와 디버깅용이다.
function error(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

export default {
  fetch: (request: Request, env: Env) => handle(request, env),
} satisfies ExportedHandler<Env>;
