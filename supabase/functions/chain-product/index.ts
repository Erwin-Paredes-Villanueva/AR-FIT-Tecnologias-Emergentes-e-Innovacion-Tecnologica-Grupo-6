// POST /chain-product
//   { action: 'register', product_id }          → proveedor dueño o admin
//   { action: 'verify', product_id, verified }   → solo admin
// Ancla la procedencia de la prenda en Polygon Amoy.
import { HttpError, json, serve } from '../_shared/cors.ts';
import { adminClient, requireUser } from '../_shared/supabase.ts';
import { EXPLORER, productDataHash, ref, sendTx } from '../_shared/chain.ts';

serve(async (req) => {
  const db = adminClient();
  const user = await requireUser(req, db);
  const { action, product_id, verified } = await req.json();

  const { data: p, error } = await db.from('products').select('*').eq('id', product_id).single();
  if (error || !p) throw new HttpError(404, 'Prenda no encontrada');

  if (action === 'register') {
    if (p.supplier_id !== user.id && user.role !== 'admin') throw new HttpError(403, 'No es tu prenda');
    const dataHash = productDataHash(p);
    let tx;
    if (!p.chain_product_id) {
      tx = await sendTx('registerProduct', [ref(p.id), ref(p.supplier_id), p.name, p.origin, p.materials, dataHash]);
    } else if (p.data_hash !== dataHash) {
      tx = await sendTx('updateProductHash', [ref(p.id), dataHash]);
    } else {
      return json({ tx_hash: p.chain_tx, explorer: `${EXPLORER}/tx/${p.chain_tx}`, unchanged: true });
    }
    await db.from('products')
      .update({ chain_product_id: ref(p.id), chain_tx: tx.hash, data_hash: dataHash })
      .eq('id', p.id);
    return json({ tx_hash: tx.hash, block: tx.blockNumber, explorer: `${EXPLORER}/tx/${tx.hash}` });
  }

  if (action === 'verify') {
    if (user.role !== 'admin') throw new HttpError(403, 'Solo administradores');
    if (!p.chain_product_id) throw new HttpError(409, 'La prenda aún no está registrada en blockchain');
    const tx = await sendTx('setProductVerified', [ref(p.id), Boolean(verified)]);
    await db.from('products').update({ chain_verified: Boolean(verified) }).eq('id', p.id);
    return json({ tx_hash: tx.hash, explorer: `${EXPLORER}/tx/${tx.hash}` });
  }

  throw new HttpError(400, 'Acción no válida');
});
