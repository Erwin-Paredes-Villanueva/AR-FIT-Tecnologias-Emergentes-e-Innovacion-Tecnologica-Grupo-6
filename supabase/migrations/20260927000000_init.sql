-- AR-FIT · Marketplace phygital de moda
-- Esquema inicial: perfiles con medidas, catálogo, interacciones (IA),
-- pedidos por proveedor y eventos de trazabilidad anclados en Polygon Amoy.

create extension if not exists pgcrypto;

-- ------------------------------------------------------------------ perfiles
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  role text not null default 'comprador'
    check (role in ('comprador', 'proveedor', 'transportista', 'admin')),
  phone text,
  -- medidas corporales para el probador RA y la recomendación de talla
  gender text check (gender in ('mujer', 'hombre', 'otro')),
  weight_kg numeric(5, 1),
  height_cm numeric(5, 1),
  size text check (size in ('XS', 'S', 'M', 'L', 'XL', 'XXL')),
  chest_cm numeric(5, 1),
  waist_cm numeric(5, 1),
  hip_cm numeric(5, 1),
  shoulder_cm numeric(5, 1),
  -- preferencias declaradas (arranque en frío del recomendador)
  style_prefs text[] not null default '{}',
  color_prefs text[] not null default '{}',
  category_prefs text[] not null default '{}',
  -- datos de proveedor / transportista
  store_name text,
  company_name text,
  city text,
  address text,
  verified boolean not null default false,
  onboarded boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid();
$$;

-- crea el perfil al registrarse; el rol admin nunca se puede elegir desde la app
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  requested text := coalesce(new.raw_user_meta_data ->> 'role', 'comprador');
begin
  if requested not in ('comprador', 'proveedor', 'transportista') then
    requested := 'comprador';
  end if;
  insert into profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), requested);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- impide que un usuario se cambie el rol o se autoverifique
create or replace function public.protect_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.role := old.role;
    new.verified := old.verified;
  end if;
  return new;
end;
$$;

create trigger protect_profile_fields
  before update on public.profiles
  for each row execute function public.protect_profile_fields();

-- vista pública sin datos personales (nombre de tienda, rol, verificación)
create view public.public_profiles as
  select id, full_name, role, store_name, company_name, city, verified
  from public.profiles;

-- ------------------------------------------------------------------ catálogo
create table public.products (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  description text not null default '',
  brand text not null default '',
  category text not null
    check (category in ('polo', 'camisa', 'polera', 'casaca', 'vestido', 'pantalon', 'falda', 'short')),
  gender text not null default 'unisex' check (gender in ('mujer', 'hombre', 'unisex')),
  style_tags text[] not null default '{}',
  color text not null default '',
  price numeric(10, 2) not null check (price >= 0),
  -- tabla de tallas: {"M": {"chest": 100, "waist": 90, "hip": 100, "length": 70}, ...} en cm
  size_chart jsonb not null default '{}',
  stock jsonb not null default '{}',            -- {"M": 10, "L": 4}
  image_url text not null,
  tryon_image_url text,                          -- PNG con fondo transparente para RA
  tryon_type text not null default 'top' check (tryon_type in ('top', 'bottom', 'full')),
  -- puntos de anclaje normalizados en la imagen RA: hombros (top/full) o cintura (bottom)
  -- {"l": [x, y], "r": [x, y]}; si es null la app los estima del contorno
  tryon_anchor jsonb,
  -- procedencia (se ancla en blockchain)
  origin text not null default '',
  materials text not null default '',
  -- blockchain
  chain_product_id text,                         -- bytes32 (hex) = keccak256(id)
  chain_tx text,
  data_hash text,
  chain_verified boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index products_supplier_idx on public.products (supplier_id);
create index products_category_idx on public.products (category);

-- ------------------------------------------------ interacciones (señales IA)
create table public.interactions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  kind text not null check (kind in ('view', 'like', 'tryon', 'cart', 'purchase')),
  created_at timestamptz not null default now()
);

create index interactions_user_idx on public.interactions (user_id, created_at desc);
create index interactions_product_idx on public.interactions (product_id);

create table public.favorites (
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table public.cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  size text not null,
  quantity int not null default 1 check (quantity between 1 and 20),
  created_at timestamptz not null default now(),
  unique (user_id, product_id, size)
);

-- ------------------------------------------------------------------- pedidos
-- un pedido por proveedor (el checkout divide el carrito)
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles (id),
  supplier_id uuid not null references public.profiles (id),
  carrier_id uuid references public.profiles (id),
  status text not null default 'created'
    check (status in ('created', 'prepared', 'picked_up', 'in_transit', 'delivered', 'received', 'cancelled')),
  total numeric(10, 2) not null,
  shipping_name text not null,
  shipping_address text not null,
  shipping_city text not null,
  payment_ref text not null,                    -- referencia del pago simulado
  chain_order_id text,
  chain_status text not null default 'pending' check (chain_status in ('pending', 'confirmed', 'failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index orders_buyer_idx on public.orders (buyer_id);
create index orders_supplier_idx on public.orders (supplier_id);
create index orders_carrier_idx on public.orders (carrier_id);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid not null references public.products (id),
  product_name text not null,
  image_url text not null,
  size text not null,
  quantity int not null,
  unit_price numeric(10, 2) not null
);

create table public.shipment_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  status text not null,
  location text not null default '',
  note text not null default '',
  actor_id uuid references public.profiles (id),
  actor_role text not null,
  tx_hash text,
  block_number bigint,
  created_at timestamptz not null default now()
);

create index shipment_events_order_idx on public.shipment_events (order_id, created_at);

create or replace function public.can_see_order(o public.orders)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() in (o.buyer_id, o.supplier_id, o.carrier_id) or public.is_admin();
$$;

-- ----------------------------------------------------------------------- RLS
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.interactions enable row level security;
alter table public.favorites enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.shipment_events enable row level security;

create policy "perfil propio o admin" on public.profiles
  for select using (id = auth.uid() or public.is_admin());
create policy "editar perfil propio o admin" on public.profiles
  for update using (id = auth.uid() or public.is_admin());

create policy "catálogo visible" on public.products
  for select using (active or supplier_id = auth.uid() or public.is_admin());
create policy "proveedor crea sus prendas" on public.products
  for insert with check (supplier_id = auth.uid() and public.my_role() = 'proveedor');
create policy "proveedor edita sus prendas" on public.products
  for update using (supplier_id = auth.uid() or public.is_admin());
create policy "proveedor elimina sus prendas" on public.products
  for delete using (supplier_id = auth.uid() or public.is_admin());

create policy "interacciones propias" on public.interactions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "favoritos propios" on public.favorites
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "carrito propio" on public.cart_items
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- pedidos y eventos solo se escriben desde Edge Functions (service role)
create policy "ver pedidos relacionados" on public.orders
  for select using (public.can_see_order(orders));
create policy "ver items de pedidos relacionados" on public.order_items
  for select using (exists (select 1 from public.orders o where o.id = order_id and public.can_see_order(o)));
create policy "ver eventos de pedidos relacionados" on public.shipment_events
  for select using (exists (select 1 from public.orders o where o.id = order_id and public.can_see_order(o)));

grant select on public.public_profiles to authenticated;

-- ------------------------------------------------------------------- storage
insert into storage.buckets (id, name, public)
values ('products', 'products', true)
on conflict (id) do nothing;

create policy "imágenes de prendas públicas" on storage.objects
  for select using (bucket_id = 'products');
create policy "proveedor sube a su carpeta" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'products' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "proveedor borra de su carpeta" on storage.objects
  for delete to authenticated
  using (bucket_id = 'products' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------- realtime
alter publication supabase_realtime add table public.orders, public.shipment_events;
