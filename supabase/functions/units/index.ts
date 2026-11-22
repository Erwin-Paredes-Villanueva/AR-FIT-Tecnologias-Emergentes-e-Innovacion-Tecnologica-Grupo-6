// POST /units
//   { action: 'issue', product_id, size, count }  → proveedor dueño o admin
//       Emite etiquetas: número de serie único + firma de AR-FIT + código de
//       barras de la talla, y registra las unidades en ARFitUnits (Polygon Amoy).
//   { action: 'claim', serial }                    → comprador
//       Activa la unidad a su nombre si la compró (pedido entregado/recibido).
//       Una segunda activación es imposible: delata una etiqueta clonada.
import { HttpError, json, serve } from '../_shared/cors.ts';
import { adminClient, requireUser } from '../_shared/supabase.ts';
import { EXPLORER, productDataHash, ref, relayer, sendTx, unitsContract } from '../_shared/chain.ts';
import { demoGtin, isValidEan13, newSerial, qrPayload, sizeBytes8, unitId, unitMessage } from '../_shared/units.ts';

serve(async (req) => {
  const db = adminClient();
  const user = await requireUser(req, db);
  const body = await req.json();

  if (body.action === 'issue') {
    const count = Math.trunc(Number(body.count ?? 1));
    const size = String(body.size ?? '');
    if (!(count >= 1 && count <= 20)) throw new HttpError(400, 'Puedes emitir entre 1 y 20 etiquetas por vez');

    const { data: p } = await db.from('products').select('*').eq('id', body.product_id).single();
    if (!p) throw new HttpError(404, 'Prenda no encontrada');
    if (p.supplier_id !== user.id && user.role !== 'admin') throw new HttpError(403, 'No es tu prenda');
    if (!(size in (p.size_chart ?? {}))) throw new HttpError(400, `La prenda no tiene talla ${size}`);

    // 1) la prenda (modelo) debe estar en ARFitTrace
    if (!p.chain_product_id) {
      const dataHash = productDataHash(p);
      const tx = await sendTx('registerProduct', [ref(p.id), ref(p.supplier_id), p.name, p.origin, p.materials, dataHash]);
      await db.from('products').update({ chain_product_id: ref(p.id), chain_tx: tx.hash, data_hash: dataHash }).eq('id', p.id);
    }

    // 2) código de barras de la talla (el del proveedor o uno de demostración)
    const gtins: Record<string, string> = { ...(p.gtins ?? {}) };
    let gtin = gtins[size];
    if (!gtin) {
      const { data: all } = await db.from('products').select('gtins');
      const used = new Set((all ?? []).flatMap((r: { gtins: Record<string, string> }) => Object.values(r.gtins ?? {})));
      for (let salt = 0; !gtin || used.has(gtin); salt++) gtin = demoGtin(p.id, size, salt);
      gtins[size] = gtin;
      await db.from('products').update({ gtins }).eq('id', p.id);
    }
    if (!isValidEan13(gtin)) throw new HttpError(400, `El código de barras ${gtin} no es un EAN-13 válido`);

    // 3) series firmadas por AR-FIT
    const wallet = relayer();
    const units = [];
    for (let i = 0; i < count; i++) {
      const serial = newSerial();
      const signature = await wallet.signMessage(unitMessage(serial, p.id, size, gtin));
      units.push({
        product_id: p.id,
        serial,
        unit_id: unitId(serial),
        size,
        gtin,
        qr_payload: qrPayload(serial, p.id, size, gtin, signature),
      });
    }

    // 4) registro on-chain del lote y en la base de datos
    const tx = await sendTx('issueUnits', [ref(p.id), sizeBytes8(size), BigInt(gtin), units.map((u) => u.unit_id)], unitsContract());
    const { data: rows, error } = await db
      .from('product_units')
      .insert(units.map((u) => ({ ...u, issue_tx: tx.hash })))
      .select('id, serial, size, gtin, qr_payload, created_at');
    if (error) throw error;
    return json({ units: rows, gtin, tx_hash: tx.hash, explorer: `${EXPLORER}/tx/${tx.hash}` });
  }

  if (body.action === 'claim') {
    const serial = String(body.serial ?? '').trim().toUpperCase();
    const { data: u } = await db.from('product_units').select('*').eq('serial', serial).single();
    if (!u) throw new HttpError(404, 'Esta etiqueta no fue emitida por AR-FIT');
    if (u.owner_id === user.id) return json({ already: true, claimed_at: u.claimed_at, tx_hash: u.claim_tx });
    if (u.owner_id) throw new HttpError(409, 'Esta prenda ya fue activada por otro comprador');

    // Solo quien la compró y la recibió puede activarla
    const { data: orders } = await db
      .from('orders')
      .select('id, status, order_items!inner(product_id, size)')
      .eq('buyer_id', user.id)
      .in('status', ['delivered', 'received'])
      .eq('order_items.product_id', u.product_id)
      .eq('order_items.size', u.size);
    if (!orders?.length) {
      throw new HttpError(403, `No tienes un pedido entregado de esta prenda en talla ${u.size}`);
    }

    const tx = await sendTx('claimUnit', [u.unit_id, ref(user.id)], unitsContract());
    const claimedAt = new Date().toISOString();
    await db.from('product_units')
      .update({ owner_id: user.id, order_id: orders[0].id, claimed_at: claimedAt, claim_tx: tx.hash })
      .eq('id', u.id);
    return json({ claimed_at: claimedAt, tx_hash: tx.hash, explorer: `${EXPLORER}/tx/${tx.hash}` });
  }

  throw new HttpError(400, 'Acción no válida');
});
