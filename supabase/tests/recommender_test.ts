// deno test supabase/tests
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { recommend } from '../functions/_shared/recommender.ts';
import { recommendSize, bodyOf } from '../functions/_shared/sizing.ts';
import type { Profile } from '../functions/_shared/supabase.ts';

// cliente falso con la misma forma encadenable que supabase-js
function fakeDb(tables: Record<string, any[]>) {
  return {
    from(name: string) {
      let rows = [...(tables[name] ?? [])];
      const q: any = {
        select: () => q,
        eq: (k: string, v: unknown) => ((rows = rows.filter((r) => r[k] === v)), q),
        gte: (k: string, v: string) => ((rows = rows.filter((r) => r[k] >= v)), q),
        order: () => q,
        limit: () => q,
        then: (res: (v: unknown) => void) => res({ data: rows, error: null }),
      };
      return q;
    },
  } as any;
}

const chart = { S: { chest: 96 }, M: { chest: 102 }, L: { chest: 108 } };
const mk = (id: string, category: string, style: string[], color: string, gender = 'unisex') => ({
  id, supplier_id: 's', name: id, brand: 'B', category, gender, style_tags: style, color, price: 50,
  size_chart: chart, stock: { S: 1, M: 1, L: 1 }, tryon_type: 'top', active: true,
});
const products = [
  mk('urbano-1', 'polera', ['urbano', 'streetwear'], 'negro'),
  mk('urbano-2', 'polo', ['urbano'], 'negro'),
  mk('formal-1', 'camisa', ['formal', 'oficina'], 'blanco'),
  mk('vestido-1', 'vestido', ['elegante'], 'rojo', 'mujer'),
];
const user: Profile = {
  id: 'u', full_name: 'Test', role: 'comprador', gender: 'hombre', weight_kg: 70, height_cm: 175, size: 'M',
  chest_cm: null, waist_cm: null, hip_cm: null, shoulder_cm: null, style_prefs: ['urbano'], color_prefs: ['negro'],
  category_prefs: [], city: null, verified: false,
};
const now = new Date().toISOString();

Deno.test('prioriza el estilo del usuario y penaliza género distinto', async () => {
  const db = fakeDb({ products, interactions: [{ user_id: 'u', product_id: 'urbano-1', kind: 'tryon', created_at: now }] });
  const { items, profile } = await recommend(db, user, 10);
  assertEquals(items.length, 4);
  assert(items[0].product_id.startsWith('urbano'), `primero: ${items[0].product_id}`);
  assertEquals(items.at(-1)!.product_id, 'vestido-1');
  assertEquals(profile.styles[0].key, 'urbano');
  assert(items[0].reasons.length > 0);
});

Deno.test('filtrado colaborativo sugiere lo que eligieron usuarios similares', async () => {
  const interactions = [
    { user_id: 'u', product_id: 'formal-1', kind: 'like', created_at: now },
    { user_id: 'x', product_id: 'formal-1', kind: 'purchase', created_at: now },
    { user_id: 'x', product_id: 'vestido-1', kind: 'purchase', created_at: now },
  ];
  const { items } = await recommend(fakeDb({ products, interactions }), { ...user, gender: 'otro', style_prefs: [], color_prefs: [] }, 10);
  const v = items.find((i) => i.product_id === 'vestido-1')!;
  assert(v.reasons.some((r) => r.includes('similares')), JSON.stringify(v));
});

Deno.test('talla recomendada según medidas', () => {
  assertEquals(recommendSize(bodyOf({ ...user, chest_cm: 90 }), 'M', chart, 'top')!.size, 'S');
  assertEquals(recommendSize(bodyOf({ ...user, chest_cm: 100 }), 'M', chart, 'top')!.size, 'L');
  assertEquals(recommendSize(null, 'M', chart, 'top')!.size, 'M');
});
