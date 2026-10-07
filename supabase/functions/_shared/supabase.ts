import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { HttpError } from './cors.ts';

export type Profile = {
  id: string;
  full_name: string;
  role: 'comprador' | 'proveedor' | 'transportista' | 'admin';
  gender: string | null;
  weight_kg: number | null;
  height_cm: number | null;
  size: string | null;
  chest_cm: number | null;
  waist_cm: number | null;
  hip_cm: number | null;
  shoulder_cm: number | null;
  style_prefs: string[];
  color_prefs: string[];
  category_prefs: string[];
  city: string | null;
  verified: boolean;
};

/** Cliente con service role: salta RLS, solo se usa dentro de las funciones. */
export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
}

/** Valida el JWT del usuario que llama y devuelve su perfil. */
export async function requireUser(req: Request, db: SupabaseClient): Promise<Profile> {
  const token = req.headers.get('Authorization')?.replace('Bearer ', '');
  if (!token) throw new HttpError(401, 'Falta el token de sesión');
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, 'Sesión inválida');
  const { data: profile, error: pErr } = await db.from('profiles').select('*').eq('id', data.user.id).single();
  if (pErr || !profile) throw new HttpError(403, 'Perfil no encontrado');
  return profile as Profile;
}
