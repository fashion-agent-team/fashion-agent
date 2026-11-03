// 앱의 ClothesScan.fromJson / Garment.fromJson과 같은 모양을 정의하고 검사한다.
// 형식을 바꾸면 lib/models/clothes_scan.dart, lib/models/garment.dart도 같이 바꾼다.

// 앱의 ScanPurpose와 같다. 지금은 펼쳐 놓은 옷을 보는 outfit 하나다.
export const PURPOSES = ['outfit'] as const;
export type Purpose = (typeof PURPOSES)[number];

export const CATEGORIES = ['top', 'bottom', 'outer', 'dress', 'shoes', 'other'] as const;
export const COLOR_FAMILIES = [
  'black', 'white', 'gray', 'navy', 'beige', 'brown', 'khaki',
  'blue', 'red', 'pink', 'orange', 'yellow', 'green', 'purple', 'unknown',
] as const;
export const TONES = ['light', 'mid', 'dark'] as const;
export const FORMALITIES = ['formal', 'smart', 'casual', 'sporty', 'unknown'] as const;
export const DEFECT_KINDS = ['stain', 'tear', 'lint', 'other'] as const;
export const LIGHTINGS = ['ok', 'dark'] as const;

export interface GarmentBox { x: number; y: number; w: number; h: number }

export interface GarmentDefect {
  kind: (typeof DEFECT_KINDS)[number];
  where: string | null;
  confidence: number;
}

export interface Garment {
  id: string;
  category: (typeof CATEGORIES)[number];
  name: string;
  colorName: string;
  colorFamily: (typeof COLOR_FAMILIES)[number];
  tone: (typeof TONES)[number];
  pattern: string | null;
  material: string | null;
  notes: string | null;
  formality: (typeof FORMALITIES)[number];
  defects: GarmentDefect[];
  box: GarmentBox | null;
  confidence: number;
}

export interface ClothesScan {
  garments: Garment[];
  framing: string | null;
  lighting: (typeof LIGHTINGS)[number];
}

export function isPurpose(value: unknown): value is Purpose {
  return typeof value === 'string' && (PURPOSES as readonly string[]).includes(value);
}

/** Gemini에게 주는 응답 형식. 이 형식의 JSON만 돌려받는다. */
export const GEMINI_RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    garments: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          category: { type: 'STRING', enum: [...CATEGORIES] },
          name: { type: 'STRING' },
          colorName: { type: 'STRING' },
          colorFamily: { type: 'STRING', enum: [...COLOR_FAMILIES] },
          tone: { type: 'STRING', enum: [...TONES] },
          pattern: { type: 'STRING', nullable: true },
          material: { type: 'STRING', nullable: true },
          notes: { type: 'STRING', nullable: true },
          formality: { type: 'STRING', enum: [...FORMALITIES] },
          defects: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                kind: { type: 'STRING', enum: [...DEFECT_KINDS] },
                where: { type: 'STRING', nullable: true },
                confidence: { type: 'NUMBER' },
              },
              required: ['kind', 'confidence'],
            },
          },
          box: {
            type: 'OBJECT',
            nullable: true,
            properties: {
              x: { type: 'NUMBER' }, y: { type: 'NUMBER' },
              w: { type: 'NUMBER' }, h: { type: 'NUMBER' },
            },
            required: ['x', 'y', 'w', 'h'],
          },
          confidence: { type: 'NUMBER' },
        },
        required: ['category', 'name', 'colorName', 'colorFamily', 'tone', 'formality', 'defects', 'confidence'],
      },
    },
    framing: { type: 'STRING', nullable: true },
    lighting: { type: 'STRING', enum: [...LIGHTINGS] },
  },
  required: ['garments', 'lighting'],
} as const;

export class SchemaError extends Error {}

/**
 * AI 응답을 앱이 믿고 쓸 수 있는 모양으로 다듬는다.
 * 모르는 값은 안전한 기본값으로 바꾸고, 앱이 쓰는 id(g1, g2…)는 여기서 붙인다.
 */
export function normalizeScan(raw: unknown): ClothesScan {
  if (!isObject(raw)) throw new SchemaError('응답이 JSON 객체가 아니에요');
  const list = Array.isArray(raw.garments) ? raw.garments : [];
  const garments = list.filter(isObject).map((g, i): Garment => ({
    id: `g${i + 1}`,
    category: pick(CATEGORIES, g.category, 'other'),
    name: text(g.name) ?? '옷',
    colorName: text(g.colorName) ?? '알 수 없는 색',
    colorFamily: pick(COLOR_FAMILIES, g.colorFamily, 'unknown'),
    tone: pick(TONES, g.tone, 'mid'),
    pattern: text(g.pattern),
    material: text(g.material),
    notes: text(g.notes),
    formality: pick(FORMALITIES, g.formality, 'unknown'),
    defects: (Array.isArray(g.defects) ? g.defects : []).filter(isObject).map((d) => ({
      kind: pick(DEFECT_KINDS, d.kind, 'other'),
      where: text(d.where),
      confidence: num01(d.confidence),
    })),
    box: box(g.box),
    confidence: num01(g.confidence),
  }));
  return {
    garments,
    framing: text(raw.framing),
    lighting: pick(LIGHTINGS, raw.lighting, 'ok'),
  };
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function pick<T extends string>(allowed: readonly T[], v: unknown, fallback: T): T {
  return typeof v === 'string' && (allowed as readonly string[]).includes(v) ? (v as T) : fallback;
}

function text(v: unknown): string | null {
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : null;
}

function clamp01(n: number): number {
  return Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : 0;
}

function num01(v: unknown): number {
  return clamp01(typeof v === 'number' ? v : 0);
}

function box(v: unknown): GarmentBox | null {
  if (!isObject(v)) return null;
  const { x, y, w, h } = v;
  if (![x, y, w, h].every((n) => typeof n === 'number' && Number.isFinite(n))) return null;
  return { x: clamp01(x as number), y: clamp01(y as number), w: clamp01(w as number), h: clamp01(h as number) };
}
