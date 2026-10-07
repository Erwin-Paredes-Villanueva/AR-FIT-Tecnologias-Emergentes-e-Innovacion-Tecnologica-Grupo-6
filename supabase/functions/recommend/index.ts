// POST /recommend → ranking personalizado + perfil de estilo aprendido
import { json, serve } from '../_shared/cors.ts';
import { adminClient, requireUser } from '../_shared/supabase.ts';
import { recommend } from '../_shared/recommender.ts';

serve(async (req) => {
  const db = adminClient();
  const user = await requireUser(req, db);
  const { limit = 60 } = await req.json().catch(() => ({}));
  const { items, profile } = await recommend(db, user, Math.min(Number(limit) || 60, 200));
  return json({ items, profile });
});
