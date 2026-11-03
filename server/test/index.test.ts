import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle, type Deps, type Env } from '../src/index.ts';
import { GeminiError } from '../src/gemini.ts';

const env: Env = { GEMINI_API_KEY: 'test', GEMINI_MODEL: 'test-model' };

const fakeScan = {
  garments: [{ category: 'bottom', name: '청바지', colorName: '연청', colorFamily: 'blue', tone: 'light', confidence: 0.9 }],
  framing: null,
  lighting: 'ok',
};
const ok: Deps = { describe: async () => fakeScan };

function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request('https://proxy.test/describe-clothes', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

test('정상 요청은 앱이 읽는 모양으로 돌려준다', async () => {
  const res = await handle(post({ purpose: 'outfit', image: 'AAAA' }), env, ok);
  assert.equal(res.status, 200);
  const data = await res.json() as { garments: { id: string; name: string }[] };
  assert.equal(data.garments[0].id, 'g1');
  assert.equal(data.garments[0].name, '청바지');
});

test('purpose와 목적이 Gemini 호출로 전달된다', async () => {
  let seen = '';
  await handle(post({ purpose: 'closet', image: 'AAAA' }), env, {
    describe: async (_img, purpose) => { seen = purpose; return fakeScan; },
  });
  assert.equal(seen, 'closet');
});

test('잘못된 요청은 400', async () => {
  assert.equal((await handle(post('not json'), env, ok)).status, 400);
  assert.equal((await handle(post({ purpose: 'face', image: 'AAAA' }), env, ok)).status, 400);
  assert.equal((await handle(post({ purpose: 'check' }), env, ok)).status, 400);
});

test('APP_TOKEN이 있으면 헤더가 맞아야 한다', async () => {
  const locked = { ...env, APP_TOKEN: 'secret' };
  assert.equal((await handle(post({ purpose: 'check', image: 'AAAA' }), locked, ok)).status, 401);
  const res = await handle(post({ purpose: 'check', image: 'AAAA' }, { 'X-App-Token': 'secret' }), locked, ok);
  assert.equal(res.status, 200);
});

test('Gemini 실패는 502, 시간 초과는 504', async () => {
  const fail: Deps = { describe: async () => { throw new GeminiError('x'); } };
  const slow: Deps = { describe: async () => { throw new GeminiError('x', true); } };
  assert.equal((await handle(post({ purpose: 'check', image: 'AAAA' }), env, fail)).status, 502);
  assert.equal((await handle(post({ purpose: 'check', image: 'AAAA' }), env, slow)).status, 504);
});

test('없는 주소는 404, health는 200', async () => {
  assert.equal((await handle(new Request('https://proxy.test/nope'), env, ok)).status, 404);
  assert.equal((await handle(new Request('https://proxy.test/health'), env, ok)).status, 200);
});
