// Motor de recomendación híbrido de AR-FIT.
//
//   score = 0.45·contenido + 0.25·colaborativo + 0.15·popularidad + 0.15·ajuste
//
// - Contenido: afinidad del usuario con categorías, estilos, colores y marcas,
//   aprendida de sus preferencias declaradas y de sus interacciones (vista,
//   favorito, prueba RA, carrito, compra) con decaimiento temporal.
// - Colaborativo: co-ocurrencia ítem-ítem entre usuarios ("quienes se probaron
//   esto también compraron...").
// - Popularidad: interacciones recientes de toda la comunidad.
// - Ajuste: si hay stock en la talla recomendada para su cuerpo y si el género
//   de la prenda coincide.
// Al final se re-ordena para dar diversidad de categorías.

import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import type { Profile } from './supabase.ts';
import { bodyOf, recommendSize, type FitResult, type SizeChart } from './sizing.ts';

export type Product = {
  id: string;
  supplier_id: string;
  name: string;
  brand: string;
  category: string;
  gender: string;
  style_tags: string[];
  color: string;
  price: number;
  size_chart: SizeChart;
  stock: Record<string, number>;
  tryon_type: string;
};

export type Recommendation = {
  product_id: string;
  score: number;
  reasons: string[];
  fit: FitResult | null;
};

export type StyleProfile = {
  categories: Array<{ key: string; weight: number }>;
  styles: Array<{ key: string; weight: number }>;
  colors: Array<{ key: string; weight: number }>;
  brands: Array<{ key: string; weight: number }>;
  signals: number;
};

const KIND_WEIGHT: Record<string, number> = { view: 1, like: 4, tryon: 3, cart: 5, purchase: 6 };
const HALF_LIFE_DAYS = 14;
const DECLARED_WEIGHT = 3;

const features = (p: Product) => [
  `cat:${p.category}`,
  `color:${p.color.toLowerCase()}`,
  `brand:${p.brand}`,
  ...p.style_tags.map((s) => `style:${s.toLowerCase()}`),
];

function decay(createdAt: string): number {
  const days = (Date.now() - new Date(createdAt).getTime()) / 86_400_000;
  return Math.pow(0.5, days / HALF_LIFE_DAYS);
}

const top = (aff: Map<string, number>, prefix: string, n = 6) => {
  const items = [...aff.entries()].filter(([k]) => k.startsWith(prefix));
  const max = Math.max(1e-9, ...items.map(([, v]) => v));
  return items
    .sort((a, b) => b[1] - a[1])
    .slice(0, n)
    .map(([k, v]) => ({ key: k.slice(prefix.length), weight: Math.round((v / max) * 100) / 100 }));
};

const LABEL: Record<string, string> = { cat: 'la categoría', style: 'el estilo', color: 'el color', brand: 'la marca' };

export async function recommend(
  db: SupabaseClient,
  user: Profile,
  limit = 40,
): Promise<{ items: Recommendation[]; profile: StyleProfile; products: Map<string, Product> }> {
  const [{ data: productRows }, { data: myEvents }, { data: allEvents }] = await Promise.all([
    db.from('products')
      .select('id,supplier_id,name,brand,category,gender,style_tags,color,price,size_chart,stock,tryon_type')
      .eq('active', true),
    db.from('interactions').select('product_id,kind,created_at').eq('user_id', user.id)
      .order('created_at', { ascending: false }).limit(500),
    db.from('interactions').select('user_id,product_id,kind,created_at')
      .gte('created_at', new Date(Date.now() - 90 * 86_400_000).toISOString())
      .order('created_at', { ascending: false }).limit(10000),
  ]);

  const products = new Map<string, Product>((productRows ?? []).map((p) => [p.id, p as Product]));

  // ---- 1. perfil de afinidad del usuario
  const aff = new Map<string, number>();
  const add = (k: string, v: number) => aff.set(k, (aff.get(k) ?? 0) + v);
  user.category_prefs.forEach((c) => add(`cat:${c}`, DECLARED_WEIGHT));
  user.style_prefs.forEach((s) => add(`style:${s.toLowerCase()}`, DECLARED_WEIGHT));
  user.color_prefs.forEach((c) => add(`color:${c.toLowerCase()}`, DECLARED_WEIGHT));

  const mine = new Map<string, number>(); // producto → peso de interacción
  const purchased = new Set<string>();
  for (const e of myEvents ?? []) {
    const p = products.get(e.product_id);
    if (!p) continue;
    const w = KIND_WEIGHT[e.kind] * decay(e.created_at);
    mine.set(p.id, (mine.get(p.id) ?? 0) + w);
    if (e.kind === 'purchase') purchased.add(p.id);
    features(p).forEach((f) => add(f, w));
  }
  const affNorm = Math.sqrt([...aff.values()].reduce((s, v) => s + v * v, 0)) || 1;

  // ---- 2. co-ocurrencia ítem-ítem
  const byUser = new Map<string, Set<string>>();
  const popularity = new Map<string, number>();
  for (const e of allEvents ?? []) {
    if (!byUser.has(e.user_id)) byUser.set(e.user_id, new Set());
    byUser.get(e.user_id)!.add(e.product_id);
    popularity.set(e.product_id, (popularity.get(e.product_id) ?? 0) + KIND_WEIGHT[e.kind] * decay(e.created_at));
  }
  const itemUsers = new Map<string, number>();
  const co = new Map<string, number>();
  for (const [uid, items] of byUser) {
    for (const i of items) itemUsers.set(i, (itemUsers.get(i) ?? 0) + 1);
    if (uid === user.id) continue;
    const seeds = [...items].filter((i) => mine.has(i));
    if (!seeds.length) continue;
    for (const j of items) {
      if (mine.has(j)) continue;
      for (const s of seeds) co.set(j, (co.get(j) ?? 0) + mine.get(s)! / Math.sqrt(itemUsers.get(s) ?? 1));
    }
  }
  const coMax = Math.max(1e-9, ...co.values());
  const popMax = Math.log1p(Math.max(0, ...popularity.values()));

  // ---- 3. puntuación
  const body = bodyOf(user);
  const scored: Recommendation[] = [];
  for (const p of products.values()) {
    const fs = features(p);
    const contributions = fs.map((f) => ({ f, v: aff.get(f) ?? 0 })).sort((a, b) => b.v - a.v);
    const content = contributions.reduce((s, c) => s + c.v, 0) / (affNorm * Math.sqrt(fs.length));
    const collab = (co.get(p.id) ?? 0) / coMax;
    const pop = popMax > 0 ? Math.log1p(popularity.get(p.id) ?? 0) / popMax : 0;

    const inStock = Object.entries(p.stock ?? {}).filter(([, q]) => q > 0).map(([s]) => s);
    const fit = recommendSize(body, user.size, p.size_chart, p.tryon_type, inStock);
    let fitScore = fit ? fit.confidence : -0.5;
    if (user.gender && user.gender !== 'otro' && p.gender !== 'unisex' && p.gender !== user.gender) fitScore -= 1.2;

    let score = 0.45 * content + 0.25 * collab + 0.15 * pop + 0.15 * fitScore;
    if (purchased.has(p.id)) score -= 0.3;

    const reasons: string[] = [];
    for (const c of contributions.slice(0, 2)) {
      if (c.v <= 0) break;
      const [type, value] = c.f.split(':');
      reasons.push(`Te gusta ${LABEL[type]} ${value}`);
    }
    if (collab > 0.3) reasons.push('Usuarios con gustos similares la eligieron');
    if (pop > 0.7) reasons.push('Tendencia en AR-FIT');
    if (fit && fit.confidence >= 0.6) reasons.push(`Tu talla ideal: ${fit.size}`);
    scored.push({ product_id: p.id, score: Math.round(score * 1000) / 1000, reasons, fit });
  }

  // ---- 4. re-ranking con diversidad (penaliza repetir categoría)
  scored.sort((a, b) => b.score - a.score);
  const result: Recommendation[] = [];
  const catCount = new Map<string, number>();
  const pool = [...scored];
  while (pool.length && result.length < limit) {
    let bestIdx = 0;
    let bestVal = -Infinity;
    for (let i = 0; i < Math.min(pool.length, 15); i++) {
      const cat = products.get(pool[i].product_id)!.category;
      const val = pool[i].score - 0.08 * (catCount.get(cat) ?? 0);
      if (val > bestVal) { bestVal = val; bestIdx = i; }
    }
    const [chosen] = pool.splice(bestIdx, 1);
    const cat = products.get(chosen.product_id)!.category;
    catCount.set(cat, (catCount.get(cat) ?? 0) + 1);
    result.push(chosen);
  }

  const profile: StyleProfile = {
    categories: top(aff, 'cat:'),
    styles: top(aff, 'style:'),
    colors: top(aff, 'color:'),
    brands: top(aff, 'brand:', 4),
    signals: myEvents?.length ?? 0,
  };
  return { items: result, profile, products };
}
