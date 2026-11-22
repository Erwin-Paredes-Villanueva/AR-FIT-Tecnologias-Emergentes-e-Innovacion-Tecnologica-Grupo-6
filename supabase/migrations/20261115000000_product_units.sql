-- Verificación anti-fraude en 3 capas:
--   1) código de barras (GTIN / EAN-13) de la etiqueta, uno por talla
--   2) QR único por unidad física, firmado por AR-FIT y registrado en Polygon Amoy (ARFitUnits)
--   3) activación de la unidad a nombre del comprador (detecta etiquetas clonadas)

-- Códigos de barras por talla: {"M": "7750123000014", "L": "7750123000021"}
alter table public.products
  add column if not exists gtins jsonb not null default '{}';

create table if not exists public.product_units (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  serial text not null unique,                 -- serie impresa en el QR (no se publica on-chain)
  unit_id text not null unique,                -- keccak256(serie), clave en ARFitUnits
  size text not null,
  gtin text not null check (gtin ~ '^[0-9]{13}$'),
  qr_payload text not null,                    -- contenido completo del QR (incluye la firma)
  issue_tx text,
  owner_id uuid references public.profiles (id),
  order_id uuid references public.orders (id),
  claimed_at timestamptz,
  claim_tx text,
  created_at timestamptz not null default now()
);

create index if not exists product_units_product_idx on public.product_units (product_id, size);
create index if not exists product_units_owner_idx on public.product_units (owner_id);

alter table public.product_units enable row level security;

-- El proveedor ve las etiquetas de sus prendas (para imprimirlas), el dueño ve
-- las suyas y el admin todas. Solo las Edge Functions (service role) escriben.
drop policy if exists "ver unidades propias" on public.product_units;
create policy "ver unidades propias" on public.product_units
  for select using (
    owner_id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.products p where p.id = product_id and p.supplier_id = auth.uid())
  );
