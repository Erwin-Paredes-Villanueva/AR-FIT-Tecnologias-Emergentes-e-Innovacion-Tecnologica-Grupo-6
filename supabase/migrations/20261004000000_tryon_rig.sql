-- Probador RA deformable: rig de la prenda (puntos clave normalizados para
-- torso, mangas y piernas) y vista de espalda con el mismo recorte.
-- Columnas nuevas (no dentro de tryon_anchor) para no romper versiones
-- anteriores de la app que leen tryon_anchor como {l, r}.
alter table public.products
  add column if not exists tryon_rig jsonb,
  add column if not exists tryon_back_url text;
