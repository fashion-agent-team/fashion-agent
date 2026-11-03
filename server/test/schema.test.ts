import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeScan, SchemaError } from '../src/schema.ts';

test('정상 응답은 그대로 두고 id를 g1부터 붙인다', () => {
  const scan = normalizeScan({
    garments: [{
      category: 'top', name: '셔츠', colorName: '남색', colorFamily: 'navy', tone: 'dark',
      pattern: '줄무늬', material: null, notes: null,
      box: { x: 0.1, y: 0.2, w: 0.3, h: 0.4 }, confidence: 0.86,
    }],
    framing: null,
    lighting: 'ok',
  });
  assert.equal(scan.garments[0].id, 'g1');
  assert.equal(scan.garments[0].colorFamily, 'navy');
  assert.deepEqual(scan.garments[0].box, { x: 0.1, y: 0.2, w: 0.3, h: 0.4 });
  assert.equal(scan.framing, null);
  assert.equal(scan.lighting, 'ok');
});

test('모르는 값은 안전한 기본값으로 바꾼다', () => {
  const scan = normalizeScan({
    garments: [{ category: 'hat', colorFamily: 'teal', tone: 'bright', confidence: 3, pattern: '  ' }],
    lighting: 'dim',
  });
  const g = scan.garments[0];
  assert.equal(g.category, 'other');
  assert.equal(g.colorFamily, 'unknown');
  assert.equal(g.tone, 'mid');
  assert.equal(g.confidence, 1);
  assert.equal(g.pattern, null);
  assert.equal(g.name, '옷');
  assert.equal(scan.lighting, 'ok');
});

test('garments가 없으면 빈 목록이다 (앱이 다시 찍기로 안내)', () => {
  assert.deepEqual(normalizeScan({ lighting: 'dark' }).garments, []);
});

test('객체가 아니면 SchemaError', () => {
  assert.throws(() => normalizeScan('hello'), SchemaError);
  assert.throws(() => normalizeScan([1, 2]), SchemaError);
});
