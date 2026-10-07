-- Probador 3D con Snap Camera Kit: ID del lente (Lens Studio) de cada prenda.
-- Si es null, la app usa el probador deformable propio.
alter table public.products add column if not exists tryon_lens_id text;
