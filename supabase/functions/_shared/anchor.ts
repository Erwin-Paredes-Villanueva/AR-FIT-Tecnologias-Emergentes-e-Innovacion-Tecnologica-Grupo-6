import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { productDataHash, ref, sendTx } from './chain.ts';

/** Registra un pedido (y sus prendas si hace falta) en Polygon Amoy. */
export async function anchorOrder(db: SupabaseClient, orderId: string): Promise<void> {
  const { data: o } = await db.from('orders').select('*, order_items(product_id)').eq('id', orderId).single();
  if (!o || o.chain_status === 'confirmed') return;
  try {
    const productIds: string[] = [...new Set<string>(o.order_items.map((i: { product_id: string }) => i.product_id))];
    for (const pid of productIds) {
      const { data: p } = await db.from('products').select('*').eq('id', pid).single();
      if (p && !p.chain_product_id) {
        const dataHash = productDataHash(p);
        const tx = await sendTx('registerProduct', [ref(p.id), ref(p.supplier_id), p.name, p.origin, p.materials, dataHash]);
        await db.from('products').update({ chain_product_id: ref(p.id), chain_tx: tx.hash, data_hash: dataHash }).eq('id', p.id);
      }
    }
    const tx = await sendTx('createOrder', [ref(o.id), ref(o.buyer_id), ref(o.supplier_id), productIds.map(ref), o.shipping_city]);
    await db.from('orders').update({ chain_order_id: ref(o.id), chain_status: 'confirmed' }).eq('id', o.id);
    const event = {
      order_id: o.id, status: 'created', location: o.shipping_city, note: 'Pedido creado y pagado',
      actor_id: o.buyer_id, actor_role: 'comprador', tx_hash: tx.hash, block_number: tx.blockNumber,
    };
    const { data: existing } = await db.from('shipment_events').select('id').eq('order_id', o.id).eq('status', 'created').maybeSingle();
    if (existing) await db.from('shipment_events').update(event).eq('id', existing.id);
    else await db.from('shipment_events').insert(event);
  } catch (e) {
    console.error('anchorOrder', orderId, e);
    await db.from('orders').update({ chain_status: 'failed' }).eq('id', orderId);
    const { data: existing } = await db.from('shipment_events').select('id').eq('order_id', orderId).eq('status', 'created').maybeSingle();
    if (!existing) {
      await db.from('shipment_events').insert({
        order_id: o.id, status: 'created', location: o.shipping_city, note: 'Pedido creado (registro blockchain pendiente)',
        actor_id: o.buyer_id, actor_role: 'comprador',
      });
    }
    throw e;
  }
}
