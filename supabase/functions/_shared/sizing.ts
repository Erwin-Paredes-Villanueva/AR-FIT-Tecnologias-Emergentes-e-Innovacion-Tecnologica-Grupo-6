// Estimación de medidas y recomendación de talla.
// La misma lógica existe en la app (lib/core/sizing.dart) para el probador RA.

import type { Profile } from './supabase.ts';

export type Body = { chest: number; waist: number; hip: number; shoulder: number; height: number };
export type SizeChart = Record<string, { chest?: number; waist?: number; hip?: number; length?: number }>;
export type FitResult = { size: string; fit: 'ajustada' | 'ideal' | 'holgada'; confidence: number };

export const SIZE_ORDER = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];

/**
 * Medidas del cuerpo: usa las declaradas y estima las faltantes a partir de
 * altura, peso (IMC) y sexo con relaciones antropométricas aproximadas.
 */
export function bodyOf(p: Profile): Body | null {
  const h = Number(p.height_cm);
  const w = Number(p.weight_kg);
  if (!h || !w) return null;
  const bmiDelta = w / (h / 100) ** 2 - 22;
  const female = p.gender === 'mujer';
  return {
    height: h,
    chest: Number(p.chest_cm) || (female ? 0.52 * h + 1.6 * bmiDelta : 0.55 * h + 1.5 * bmiDelta),
    waist: Number(p.waist_cm) || (female ? 0.41 * h + 2.2 * bmiDelta : 0.45 * h + 2.2 * bmiDelta),
    hip: Number(p.hip_cm) || (female ? 0.57 * h + 1.8 * bmiDelta : 0.53 * h + 1.6 * bmiDelta),
    shoulder: Number(p.shoulder_cm) || (female ? 0.22 * h : 0.23 * h),
  };
}

// holgura ideal (prenda - cuerpo, en cm de contorno) según la zona
const EASE: Record<string, [number, number]> = { chest: [4, 14], waist: [0, 8], hip: [2, 10] };

function zonesFor(tryonType: string): Array<'chest' | 'waist' | 'hip'> {
  if (tryonType === 'bottom') return ['waist', 'hip'];
  if (tryonType === 'full') return ['chest', 'waist', 'hip'];
  return ['chest'];
}

/** Elige la talla que mejor se ajusta al cuerpo del usuario. */
export function recommendSize(
  body: Body | null,
  declaredSize: string | null,
  chart: SizeChart,
  tryonType: string,
  available?: string[],
): FitResult | null {
  const sizes = Object.keys(chart).filter((s) => !available || available.includes(s));
  if (!sizes.length) return null;
  if (!body) {
    const s = declaredSize && sizes.includes(declaredSize) ? declaredSize : sizes[Math.floor(sizes.length / 2)];
    return { size: s, fit: 'ideal', confidence: declaredSize ? 0.5 : 0.2 };
  }
  let best: { size: string; penalty: number; ease: number } | null = null;
  for (const s of sizes) {
    let penalty = 0;
    let easeSum = 0;
    let n = 0;
    for (const z of zonesFor(tryonType)) {
      const g = chart[s][z];
      if (!g) continue;
      const ease = g - body[z];
      const [lo, hi] = EASE[z];
      if (ease < lo) penalty += (lo - ease) * 3; // apretado pesa más
      else if (ease > hi) penalty += ease - hi;
      easeSum += (ease - (lo + hi) / 2) / (hi - lo);
      n++;
    }
    if (!n) continue;
    if (!best || penalty < best.penalty) best = { size: s, penalty, ease: easeSum / n };
  }
  if (!best) return null;
  const fit = best.ease < -0.5 ? 'ajustada' : best.ease > 0.5 ? 'holgada' : 'ideal';
  return { size: best.size, fit, confidence: Math.max(0.3, 1 - best.penalty / 30) };
}
