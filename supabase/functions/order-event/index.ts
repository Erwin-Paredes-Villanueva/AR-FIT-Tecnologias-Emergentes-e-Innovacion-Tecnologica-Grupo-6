// POST /order-event { order_id, status, location?, note?, carrier_id? }
// Cada rol solo puede registrar su parte del recorrido del pedido:
//   proveedor      → prepared (asigna transportista) | cancelled
//   transportista  → picked_up | in_transit | delivered
//   comprador      → received | cancelled
// El evento se escribe primero en Polygon Amoy y luego se refleja en la BD.
import { HttpError, json, serve } from '../_shared/cors.ts';
import { adminClient, requireUser } from '../_shared/supabase.ts';
import { EXPLORER, ref, sendTx, STATUS_CODE } from '../_shared/chain.ts';
import { anchorOrder } from '../_shared/anchor.ts';

const NEXT: Record<string, string[]> = {
  created: ['prepared', 'cancelled'],
  prepared: ['picked_up', 'cancelled'],
  picked_up: ['in_transit'],
  in_transit: ['in_transit', 'delivered'],
  delivered: ['received'],
};

const NOTES: Record<string, string> = {
  prepared: 'Prenda verificada, empacada y lista para despacho',
  picked_up: 'Paquete recogido por el transportista',
  in_transit: 'Paquete en tránsito',
  delivered: 'Paquete entregado en la dirección de destino',
  received: 'El comprador confirmó la recepción',
  cancelled: 'Pedido cancelado',
};

serve(async (req) => {
  const db = adminClient();
  const user = await requireUser(req, db);
  const { order_id, status, location, note, carrier_id } = await req.json();

  const { data: order } = await db.from('orders').select('*').eq('id', order_id).single();
  if (!order) throw new HttpError(404, 'Pedido no encontrado');
  if (!NEXT[order.status]?.includes(status)) throw new HttpError(409, `No se puede pasar de ${order.status} a ${status}`);

  const isAdmin = user.role === 'admin';
  const allowed =
    isAdmin ||
    (status === 'prepared' && user.id === order.supplier_id) ||
    (['picked_up', 'in_transit', 'delivered'].includes(status) && user.id === order.carrier_id) ||
    (status === 'received' && user.id === order.buyer_id) ||
    (status === 'cancelled' && [order.buyer_id, order.supplier_id].includes(user.id));
  if (!allowed) throw new HttpError(403, 'Tu rol no puede registrar este evento');

  const update: Record<string, unknown> = { status, updated_at: new Date().toISOString() };
  if (status === 'prepared') {
    if (!carrier_id) throw new HttpError(400, 'Selecciona un transportista');
    const { data: carrier } = await db.from('profiles').select('id,role').eq('id', carrier_id).single();
    if (carrier?.role !== 'transportista') throw new HttpError(400, 'Transportista no válido');
    update.carrier_id = carrier_id;
  }

  // si el alta on-chain del pedido falló antes, se reintenta ahora
  if (order.chain_status !== 'confirmed') await anchorOrder(db, order.id);

  const place = String(location ?? '').slice(0, 120);
  const text = String(note || NOTES[status]).slice(0, 200);
  const tx = await sendTx('addEvent', [ref(order.id), STATUS_CODE[status], place, user.role, ref(user.id), text]);

  await db.from('orders').update(update).eq('id', order.id);
  const { data: event } = await db.from('shipment_events').insert({
    order_id: order.id, status, location: place, note: text, actor_id: user.id, actor_role: user.role,
    tx_hash: tx.hash, block_number: tx.blockNumber,
  }).select().single();

  return json({ event, explorer: `${EXPLORER}/tx/${tx.hash}` });
});
