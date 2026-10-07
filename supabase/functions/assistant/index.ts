// POST /assistant → asistente virtual de compra con Google Gemini.
// Se le da como contexto el perfil del usuario (medidas, gustos aprendidos) y
// las prendas mejor rankeadas por el recomendador, y responde en JSON con
// texto + ids de prendas sugeridas que la app muestra como tarjetas.
import { HttpError, json, serve } from '../_shared/cors.ts';
import { adminClient, requireUser } from '../_shared/supabase.ts';
import { recommend } from '../_shared/recommender.ts';
import { bodyOf } from '../_shared/sizing.ts';

type Msg = { role: 'user' | 'model'; text: string };

serve(async (req) => {
  const db = adminClient();
  const user = await requireUser(req, db);
  const { messages } = (await req.json()) as { messages: Msg[] };
  if (!Array.isArray(messages) || !messages.length) throw new HttpError(400, 'messages requerido');

  const { items, profile, products } = await recommend(db, user, 45);
  const body = bodyOf(user);
  const catalog = items.map((r) => {
    const p = products.get(r.product_id)!;
    const sizes = Object.entries(p.stock ?? {}).filter(([, q]) => q > 0).map(([s]) => s);
    return {
      id: p.id, nombre: p.name, marca: p.brand, categoria: p.category, genero: p.gender,
      estilos: p.style_tags, color: p.color, precio_pen: p.price, tallas_disponibles: sizes,
      talla_recomendada: r.fit?.size ?? null, calce: r.fit?.fit ?? null,
    };
  });

  const system = `Eres "Ari", la asistente virtual de compra de AR-FIT, un marketplace phygital de moda en Perú.
Hablas en español, con tono cercano y breve (máximo 4 frases). Ayudas a elegir prendas, combinar outfits,
elegir talla y explicas que cada prenda tiene su autenticidad y trazabilidad registrada en blockchain (Polygon)
y que puede probársela con el probador de realidad aumentada.
Solo recomiendas prendas del CATÁLOGO dado (usa sus ids exactos en product_ids, máximo 4). Si nada encaja, dilo.
Usa la talla_recomendada calculada a partir de las medidas del usuario cuando hables de tallas.
No inventes precios, stock ni datos. Los precios están en soles (S/).

USUARIO: ${JSON.stringify({
    nombre: user.full_name, genero: user.gender, talla_declarada: user.size,
    medidas_cm: body && { altura: body.height, pecho: Math.round(body.chest), cintura: Math.round(body.waist), cadera: Math.round(body.hip) },
    gustos_aprendidos: { estilos: profile.styles.map((s) => s.key), colores: profile.colors.map((c) => c.key), categorias: profile.categories.map((c) => c.key) },
  })}

CATÁLOGO (ordenado por afinidad con el usuario): ${JSON.stringify(catalog)}`;

  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) throw new HttpError(500, 'GEMINI_API_KEY no configurada');
  const model = Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.8-flash';

  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents: messages.slice(-12).map((m) => ({ role: m.role, parts: [{ text: m.text }] })),
      generationConfig: {
        temperature: 0.7,
        responseMimeType: 'application/json',
        responseSchema: {
          type: 'OBJECT',
          properties: {
            reply: { type: 'STRING' },
            product_ids: { type: 'ARRAY', items: { type: 'STRING' } },
          },
          required: ['reply', 'product_ids'],
        },
      },
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    console.error('Gemini', res.status, detail);
    throw new HttpError(502, res.status === 429 ? 'La IA está saturada, intenta en un minuto' : 'Error consultando la IA');
  }
  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? '').join('') ?? '{}';
  let parsed: { reply: string; product_ids: string[] };
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { reply: text, product_ids: [] };
  }
  const valid = (parsed.product_ids ?? []).filter((id) => products.has(id)).slice(0, 4);
  return json({ reply: parsed.reply, product_ids: valid });
});
