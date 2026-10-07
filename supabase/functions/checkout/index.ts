// POST /checkout { shipping_name, shipping_address, shipping_city, payment_method }
// Valida el carrito, divide por proveedor, descuenta stock, registra el pago
// simulado y ancla cada pedido en Polygon Amoy (en segundo plano).
import { HttpError, json, serve } from '../_shared/cors.ts';
import { adminClient, requireUser } from '../_shared/supabase.ts';
import { anchorOrder } from '../_shared/anchor.ts';
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

const PAYMENT_METHODS = ['tarjeta', 'yape', 'contraentrega'];

serve(async (req) => {
  const db = adminClient();
  const user = await requireUser(req, db);
  const { shipping_name, shipping_address, shipping_city, payment_method } = await req.json();
  if (!shipping_name || !shipping_address || !shipping_city) throw new HttpError(400, 'Completa los datos de envío');
  if (!PAYMENT_METHODS.includes(payment_method)) throw new HttpError(400, 'Método de pago no válido');

  const { data: cart } = await db.from('cart_items')
    .select('id,product_id,size,quantity,products(*)').eq('user_id', user.id);
  if (!cart?.length) throw new HttpError(400, 'Tu carrito está vacío');

  // valida stock
  for (const item of cart) {
    const p = item.products as any;
    if (!p?.active) throw new HttpError(409, 'Una prenda ya no está disponible');
    if ((p.stock?.[item.size] ?? 0) < item.quantity) throw new HttpError(409, `Sin stock suficiente de ${p.name} talla ${item.size}`);
  }

  // agrupa por proveedor → un pedido por proveedor
  const groups = new Map<string, typeof cart>();
  for (const item of cart) {
    const sid = (item.products as any).supplier_id;
    groups.set(sid, [...(groups.get(sid) ?? []), item]);
  }

  const created: Array<{ id: string; supplier_id: string; items: typeof cart }> = [];
  for (const [supplierId, items] of groups) {
    const total = items.reduce((s, i) => s + Number((i.products as any).price) * i.quantity, 0);
    const paymentRef = `SIM-${payment_method.toUpperCase()}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const { data: order, error } = await db.from('orders').insert({
      buyer_id: user.id, supplier_id: supplierId, total, shipping_name, shipping_address, shipping_city,
      payment_ref: paymentRef,
    }).select().single();
    if (error) throw error;

    await db.from('order_items').insert(items.map((i) => {
      const p = i.products as any;
      return { order_id: order.id, product_id: p.id, product_name: p.name, image_url: p.image_url, size: i.size, quantity: i.quantity, unit_price: p.price };
    }));
    for (const i of items) {
      const p = i.products as any;
      const stock = { ...p.stock, [i.size]: p.stock[i.size] - i.quantity };
      p.stock = stock;
      await db.from('products').update({ stock }).eq('id', p.id);
    }
    await db.from('interactions').insert(items.map((i) => ({ user_id: user.id, product_id: i.product_id, kind: 'purchase' })));
    created.push({ id: order.id, supplier_id: supplierId, items });
  }
  await db.from('cart_items').delete().eq('user_id', user.id);

  // las transacciones tardan unos segundos: se confirman en segundo plano y la
  // app recibe el evento por Realtime
  EdgeRuntime.waitUntil(anchorOrders(db, created.map((o) => o.id)));

  return json({ orders: created.map((o) => o.id) });
});

async function anchorOrders(db: SupabaseClient, orderIds: string[]) {
  for (const id of orderIds) {
    await anchorOrder(db, id).catch(() => {}); // el error queda registrado en chain_status
  }
}
