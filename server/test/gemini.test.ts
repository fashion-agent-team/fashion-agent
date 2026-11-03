import { test } from 'node:test';
import assert from 'node:assert/strict';
import { describeWithGemini, GeminiError } from '../src/gemini.ts';

function fakeFetch(status: number, body: unknown, capture?: (url: string, init: RequestInit) => void): typeof fetch {
  return (async (url: string, init: RequestInit) => {
    capture?.(url, init);
    return new Response(JSON.stringify(body), { status });
  }) as unknown as typeof fetch;
}

test('키는 헤더로, 사진과 프롬프트는 본문으로 보내고 JSON 텍스트를 파싱한다', async () => {
  let url = '';
  let init: RequestInit = {};
  const result = await describeWithGemini('IMG', 'outfit', {
    apiKey: 'KEY', model: 'm1',
    fetch: fakeFetch(200, { candidates: [{ content: { parts: [{ text: '{"garments":[],"lighting":"ok"}' }] } }] },
      (u, i) => { url = u; init = i; }),
  });
  assert.deepEqual(result, { garments: [], lighting: 'ok' });
  assert.match(url, /\/models\/m1:generateContent$/);
  assert.equal((init.headers as Record<string, string>)['x-goog-api-key'], 'KEY');
  assert.ok(!url.includes('KEY'), '키를 주소에 넣지 않는다');
  const sent = JSON.parse(init.body as string);
  assert.equal(sent.contents[0].parts[1].inline_data.data, 'IMG');
  assert.equal(sent.generationConfig.responseMimeType, 'application/json');
});

test('HTTP 오류와 빈 응답은 GeminiError', async () => {
  await assert.rejects(describeWithGemini('I', 'outfit', { apiKey: 'k', model: 'm', fetch: fakeFetch(429, {}) }), GeminiError);
  await assert.rejects(describeWithGemini('I', 'outfit', { apiKey: 'k', model: 'm', fetch: fakeFetch(200, { candidates: [] }) }), GeminiError);
});

test('Gemini 오류 본문의 이유를 메시지에 담는다', async () => {
  const fetch400 = fakeFetch(400, { error: { code: 400, message: 'API key not valid.', status: 'INVALID_ARGUMENT' } });
  await assert.rejects(
    describeWithGemini('I', 'outfit', { apiKey: 'k', model: 'm', fetch: fetch400 }),
    (e: unknown) => e instanceof GeminiError && e.message === 'Gemini 오류 (400): API key not valid.',
  );
});
